#!/usr/bin/env python3
"""AME-Chip decode 工作负载建模: miniGPT(2L/256d/4h/1024ffn/vocab1024/ctx128).

导出两个静态 ONNX 到 models/:
  minigpt_prefill.onnx : 整段 prompt(T=PREFILL_T=16) token id 输入, 一次前向,
                         输出 logits[1,T,1024] + 初始 KV cache [2,4,T,64]x2
  minigpt_decode.onnx  : 单步 decode, 输入
                         x_emb  [1,256]   当前 token 的 (tok_emb+pos_emb), 查表由宿主/控制器完成
                         k_cache[2,4,128,64] 全量 KV cache(层,头,上下文,头维), 行主序
                         v_cache[2,4,128,64]
                         mask   [1,1,1,128] 加性 mask(无效位置 -1e9), 由控制器按 pos 生成
                         输出 logits[1,1024] + 本步新 k/v 行 k_new/v_new [2,4,1,64]
                         (写回 cache 的 pos 行由 DMA/控制器完成, 不进图 —— 与硬件一致)

图内只有 MatMul/Gemm + elementwise + softmax, 全静态形状, 无 ScatterND/Range/循环,
保证 TPU-MLIR model_transform 可解析。decode 图所有 Linear 均为 M x K 矩阵乘 K x 1 向量
(GEMV), 注意力 QK/PV 为按头 batched GEMV。

权重随机初始化(seed 固定), 全 fp32; 另存 minigpt_weights.npz 供 golden 复现。
导出后用 onnxruntime 对 eager 参考做数值一致性检查, 并验证 prefill->decode 级联等价。
"""
import json
import math
import os

import numpy as np
import onnx
import torch
import torch.nn as nn
import torch.nn.functional as F

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS = os.path.join(ROOT, "models")

OPSET = 17
IR_VERSION = 8
SEED = 42
MASK_NEG = -1e9

PREFILL_T = 16


class Config:
    n_layer = 2
    d_model = 256
    n_head = 4
    d_ffn = 1024
    vocab = 1024
    max_ctx = 128
    prefill_T = 16

    @property
    def head_dim(self):
        return self.d_model // self.n_head


class Block(nn.Module):
    def __init__(self, cfg: Config):
        super().__init__()
        d, f = cfg.d_model, cfg.d_ffn
        self.ln1 = nn.LayerNorm(d)
        self.Wqkv = nn.Linear(d, 3 * d)
        self.Wo = nn.Linear(d, d)
        self.ln2 = nn.LayerNorm(d)
        self.fc1 = nn.Linear(d, f)
        self.fc2 = nn.Linear(f, d)

    def split_heads(self, t, n_head):
        B, T, D = t.shape
        return t.view(B, T, n_head, D // n_head).transpose(1, 2)


class MiniGPT(nn.Module):
    def __init__(self, cfg: Config):
        super().__init__()
        self.cfg = cfg
        self.wte = nn.Embedding(cfg.vocab, cfg.d_model)
        self.wpe = nn.Embedding(cfg.max_ctx, cfg.d_model)
        self.blocks = nn.ModuleList(Block(cfg) for _ in range(cfg.n_layer))
        self.ln_f = nn.LayerNorm(cfg.d_model)
        self.lm_head = nn.Linear(cfg.d_model, cfg.vocab)
        self.scale = 1.0 / math.sqrt(cfg.head_dim)
        m = cfg.prefill_T
        mask = torch.full((1, 1, m, m), MASK_NEG).triu(1)
        self.register_buffer("causal_mask", mask)
        self.export_mode = "prefill"
        self.apply(self._init)

    def _init(self, mod):
        if isinstance(mod, (nn.Linear, nn.Embedding)):
            nn.init.normal_(mod.weight, std=0.02)
            if isinstance(mod, nn.Linear) and mod.bias is not None:
                nn.init.zeros_(mod.bias)
        elif isinstance(mod, nn.LayerNorm):
            nn.init.ones_(mod.weight)
            nn.init.zeros_(mod.bias)

    def forward_prefill(self, ids):  # ids [1,T] int64
        cfg = self.cfg
        T = ids.size(1)
        x = self.wte(ids) + self.wpe.weight[:T].unsqueeze(0)      # [1,T,D]
        ks, vs = [], []
        for blk in self.blocks:
            h = blk.ln1(x)
            qkv = blk.Wqkv(h)                                      # [1,T,3D]
            q, k, v = qkv.split(cfg.d_model, dim=-1)
            q, k, v = (self._heads(t) for t in (q, k, v))          # [1,H,T,hd]
            if T == cfg.prefill_T:
                mask = self.causal_mask[:, :, :T, :T]
            else:
                mask = torch.full((1, 1, T, T), MASK_NEG, dtype=x.dtype)
                mask = mask.triu(1)
            att = torch.matmul(q, k.transpose(-1, -2)) * self.scale + mask
            att = F.softmax(att, dim=-1)
            y = torch.matmul(att, v)                               # [1,H,T,hd]
            y = y.transpose(1, 2).reshape(1, T, cfg.d_model)
            x = x + blk.Wo(y)
            x = x + blk.fc2(F.gelu(blk.fc1(blk.ln2(x))))
            ks.append(k)
            vs.append(v)
        x = self.ln_f(x)
        logits = self.lm_head(x)                                   # [1,T,vocab]
        k_cache = torch.stack(ks, 0).squeeze(1)                    # [L,H,T,hd]
        v_cache = torch.stack(vs, 0).squeeze(1)
        return logits, k_cache, v_cache

    def _heads(self, t):  # [1,T,D] -> [1,H,T,hd]
        c = self.cfg
        return t.view(1, -1, c.n_head, c.head_dim).transpose(1, 2)

    def forward_decode(self, x_emb, k_cache, v_cache, mask):
        cfg = self.cfg
        H, hd = cfg.n_head, cfg.head_dim
        x = x_emb.view(1, cfg.d_model)
        k_news, v_news = [], []
        for l, blk in enumerate(self.blocks):
            h = blk.ln1(x)
            qkv = blk.Wqkv(h)                                      # [1,3D] GEMV
            q, k, v = qkv.split(cfg.d_model, dim=-1)
            q = q.view(1, H, hd).transpose(0, 1)                   # [H,1,hd]
            k = k.view(1, H, hd).transpose(0, 1)
            v = v.view(1, H, hd).transpose(0, 1)
            kc, vc = k_cache[l], v_cache[l]                        # [H,ctx,hd]
            att = torch.matmul(q, kc.transpose(-1, -2)) * self.scale  # [H,1,ctx]
            att = att + mask
            att = F.softmax(att, dim=-1)
            y = torch.matmul(att, vc)                              # [H,1,hd] GEMV
            y = y.transpose(0, 1).reshape(1, cfg.d_model)
            x = x + blk.Wo(y)                                      # GEMV
            x = x + blk.fc2(F.gelu(blk.fc1(blk.ln2(x))))           # 2x GEMV
            k_news.append(k.unsqueeze(0))
            v_news.append(v.unsqueeze(0))
        x = self.ln_f(x)
        logits = self.lm_head(x)                                   # [1,vocab] GEMV
        k_new = torch.cat(k_news, 0)                               # [L,H,1,hd]
        v_new = torch.cat(v_news, 0)
        return logits, k_new, v_new

    def forward(self, *args):
        if self.export_mode == "prefill":
            return self.forward_prefill(*args)
        return self.forward_decode(*args)

    def forward_full(self, ids):
        logits, kc, vc = self.forward_prefill(ids)
        return logits, kc, vc


def export_onnx(model, path, args, input_names, output_names):
    torch.onnx.export(model, args, path, input_names=input_names,
                      output_names=output_names, opset_version=OPSET,
                      dynamo=False, do_constant_folding=True)
    m = onnx.load(path)
    m.ir_version = IR_VERSION
    onnx.checker.check_model(m)
    onnx.save(m, path)
    return path


def npz_for_transform(path, **arrays):
    np.savez(path, **arrays)


def main():
    os.makedirs(MODELS, exist_ok=True)
    torch.manual_seed(SEED)
    cfg = Config()
    model = MiniGPT(cfg).eval()

    n_params = sum(p.numel() for p in model.parameters())
    print(f"miniGPT params: {n_params} ({n_params * 4 / 2**20:.2f} MiB fp32)")

    ids_ex = torch.randint(0, cfg.vocab, (1, PREFILL_T))
    prefill_path = os.path.join(MODELS, "minigpt_prefill.onnx")
    model.export_mode = "prefill"
    export_onnx(model, prefill_path, (ids_ex,), ["ids"],
                ["logits", "k_cache", "v_cache"])
    print(f"exported {prefill_path}")

    x_ex = torch.randn(1, cfg.d_model)
    kc_ex = torch.randn(cfg.n_layer, cfg.n_head, cfg.max_ctx, cfg.head_dim)
    vc_ex = torch.randn_like(kc_ex)
    mask_ex = torch.zeros(1, 1, 1, cfg.max_ctx)
    decode_path = os.path.join(MODELS, "minigpt_decode.onnx")
    model.export_mode = "decode"
    export_onnx(model, decode_path, (x_ex, kc_ex, vc_ex, mask_ex),
                ["x_emb", "k_cache", "v_cache", "mask"],
                ["logits", "k_new", "v_new"])
    print(f"exported {decode_path}")

    g = torch.Generator().manual_seed(SEED + 1)
    ids_fix = torch.randint(0, cfg.vocab, (1, PREFILL_T), generator=g)
    npz_for_transform(os.path.join(MODELS, "minigpt_prefill_input.npz"),
                      ids=ids_fix.numpy().astype(np.int64))
    x_fix = torch.randn(1, cfg.d_model, generator=g).numpy()
    kc_fix = torch.randn(cfg.n_layer, cfg.n_head, cfg.max_ctx,
                         cfg.head_dim, generator=g).numpy()
    vc_fix = torch.randn_like(torch.from_numpy(kc_fix)).numpy()
    mask_fix = np.zeros((1, 1, 1, cfg.max_ctx), np.float32)
    mask_fix[..., 7:] = MASK_NEG
    npz_for_transform(os.path.join(MODELS, "minigpt_decode_input.npz"),
                      x_emb=x_fix.astype(np.float32), k_cache=kc_fix.astype(np.float32),
                      v_cache=vc_fix.astype(np.float32), mask=mask_fix.astype(np.float32))

    sd = {k: v.detach().numpy() for k, v in model.state_dict().items()}
    np.savez(os.path.join(MODELS, "minigpt_weights.npz"), **sd)
    with open(os.path.join(MODELS, "minigpt_config.json"), "w") as f:
        cfg_dict = {k: v for k, v in vars(Config).items()
                    if not k.startswith("_") and not isinstance(v, property)}
        json.dump({**cfg_dict, "seed": SEED, "opset": OPSET,
                   "ir_version": IR_VERSION, "mask_neg": MASK_NEG,
                   "prefill_T": PREFILL_T}, f, indent=2)

    import onnxruntime as ort

    def ort_run(path, feed):
        so = ort.SessionOptions()
        s = ort.InferenceSession(path, so, providers=["CPUExecutionProvider"])
        return s.run(None, feed)

    def eager_prefill(ids_np):
        with torch.no_grad():
            return model.forward_prefill(torch.from_numpy(ids_np))

    def eager_decode(x, kc, vc, mk):
        with torch.no_grad():
            return model.forward_decode(x, kc, vc, mk)

    ok = True

    lg_e, ke, ve = eager_prefill(ids_fix.numpy())
    lg_o, k_o, v_o = ort_run(prefill_path, {"ids": ids_fix.numpy().astype(np.int64)})
    d1 = np.abs(lg_o[0] - lg_e.numpy()[0]).max()
    print(f"[check] prefill logits max|dEAGER-ONNX| = {d1:.3e}")
    ok &= d1 < 1e-3

    pos = 6
    mask6 = torch.zeros(1, 1, 1, cfg.max_ctx)
    mask6[..., pos + 1:] = MASK_NEG
    lg_ed, kn_ed, vn_ed = eager_decode(torch.from_numpy(x_fix),
                                       torch.from_numpy(kc_fix),
                                       torch.from_numpy(vc_fix), mask6)
    lg_od, kn, vn = ort_run(decode_path, {
        "x_emb": x_fix, "k_cache": kc_fix, "v_cache": vc_fix, "mask": mask_fix})
    d2 = np.abs(lg_od[0] - lg_ed.numpy()[0]).max()
    d2b = np.abs(kn - kn_ed.numpy()).max()
    print(f"[check] decode logits max|dEAGER-ONNX| = {d2:.3e}, k_new = {d2b:.3e}")
    ok &= d2 < 1e-3 and d2b < 1e-3

    ids17 = torch.randint(0, cfg.vocab, (1, 17), generator=torch.Generator().manual_seed(7))
    with torch.no_grad():
        lg17, k17, v17 = model.forward_prefill(ids17)
    cache_k = np.zeros((cfg.n_layer, cfg.n_head, cfg.max_ctx, cfg.head_dim), np.float32)
    cache_v = np.zeros_like(cache_k)
    cache_k[..., :17, :] = k17.numpy()
    cache_v[..., :17, :] = v17.numpy()
    tok16 = (model.wte(ids17[0, 16]) + model.wpe.weight[16]).detach()
    m17 = torch.zeros(1, 1, 1, cfg.max_ctx)
    m17[..., 17:] = MASK_NEG
    lg_cd, _, _ = ort_run(decode_path, {
        "x_emb": tok16.view(1, -1).numpy(), "k_cache": cache_k,
        "v_cache": cache_v, "mask": m17.numpy()})
    d3 = np.abs(lg_cd[0] - lg17[0, 16].numpy()).max()
    print(f"[check] prefill->decode cascade last-position max|d| = {d3:.3e}")
    ok &= d3 < 1e-2

    print("ALL CHECKS", "PASSED" if ok else "FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
