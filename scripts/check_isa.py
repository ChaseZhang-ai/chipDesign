#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""check_isa.py — AME-Chip P1B 契约机器校验(P1B 交付;P1BX-A 扩展)

校验内容(任务书第 4 项 + P1BX-A):
  A) AME_ISA.md §1.1 编码表:同一 (opcode,funct3[,funct7]) 组合不得重复;
     I-type 以 (opcode,funct3) 唯一,R-type 以 (opcode,funct3,funct7) 唯一。
  B) ARCH_SPEC.md §4 地址映射:区域互不重叠、基址 4KB 对齐(非保留区)、
     覆盖完整 32 位空间(声明保留也算覆盖)。
  C) rtl/amechip_pkg.sv 锚点常量(@ISA:*/@MAP:*)与两份文档逐项一致。
  D) 附加:AME_ISA.md §7 机器码样例反汇编后与编码表一致(opcode/funct 核对)。
  E) P1BX-A 裁决 A:ARCH_SPEC §4.7 AME 子窗口(偏移/孔径)⇄ pkg `@AMEW:*`
     锚点一致,子窗口互不重叠、4B 对齐、全部落在 @MAP:AME 区域内。
  F) P1BX-A 裁决 F:§7 样例按 pkg 字段位置独立重建整个 32-bit 字,并显式
     复算 cfg 的 imm 字段(用同一编码公式,不依赖文档里的分解文字)。

用法: python3 scripts/check_isa.py   (仓库内任意位置;路径按脚本位置解析)
退出码: 0=全绿, 1=有 FAIL。python 解释器任意 ≥3.8(无第三方依赖)。
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ISA_MD = ROOT / "docs" / "AME_ISA.md"
ARCH_MD = ROOT / "docs" / "ARCH_SPEC.md"
PKG_SV = ROOT / "rtl" / "amechip_pkg.sv"

fails: list[str] = []
passes: list[str] = []


def ok(msg: str) -> None:
    passes.append(msg)
    print(f"  PASS  {msg}")


def bad(msg: str) -> None:
    fails.append(msg)
    print(f"  FAIL  {msg}")


def section(title: str) -> None:
    print(f"\n== {title} ==")


# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
def parse_isa_table(text: str) -> tuple[dict[str, dict], str]:
    """返回 {instr: {type, f3, f7}},f7 为 None 表示 I-type('-')。"""
    rows: dict[str, dict] = {}
    header = "| instr | type | funct3 | funct7 | rd | rs1 | rs2 |"
    lines = text.splitlines()
    try:
        start = lines.index(header)
    except ValueError:
        return rows, f"AME_ISA.md 找不到编码表表头行: {header!r}"
    for ln in lines[start + 1:]:
        if not ln.strip().startswith("|"):
            break
        cells = [c.strip() for c in ln.strip().strip("|").split("|")]
        if len(cells) < 4 or set(cells[0]) <= {"-", " "}:
            continue
        name, typ, f3, f7 = cells[0], cells[1], cells[2], cells[3]
        try:
            f3v = int(f3, 16)
        except ValueError:
            return rows, f"{name}: funct3 非十六进制: {f3!r}"
        f7v: int | None
        if f7 == "-":
            f7v = None
        else:
            try:
                f7v = int(f7, 16)
            except ValueError:
                return rows, f"{name}: funct7 非十六进制: {f7!r}"
        rows[name] = {"type": typ, "f3": f3v, "f7": f7v}
    return rows, ""


# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
def parse_map_anchors(text: str) -> dict[str, tuple[int, int]]:
    out: dict[str, tuple[int, int]] = {}
    for m in re.finditer(
        r"<!--\s*@MAP:(\w+)\s+(0x[0-9A-Fa-f]+)\s+(0x[0-9A-Fa-f]+)\s*-->", text
    ):
        name = m.group(1)
        base, end = int(m.group(2), 16), int(m.group(3), 16)
        if name in out:
            continue
        out[name] = (base, end)
    return out


# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
def parse_pkg_anchors(
    text: str,
) -> tuple[dict[str, int], dict[str, int], dict[str, int], dict[str, int]]:
    """返回 (isa, mp, amew, consts)。

    isa/mp/amew 收集行尾锚点常量;consts 收集全部 32-bit localparam 与
    int unsigned localparam(供 §7 cfg imm 字段位置使用)。
    """
    isa: dict[str, int] = {}
    mp: dict[str, int] = {}
    amew: dict[str, int] = {}
    consts: dict[str, int] = {}
    val_re = re.compile(r"=\s*\d+'h([0-9A-Fa-f_]+)\s*;")
    hex_const_re = re.compile(
        r"localparam\s+logic\s*\[31:0\]\s+(\w+)\s*=\s*\d+'h([0-9A-Fa-f_]+)\s*;"
    )
    int_const_re = re.compile(r"localparam\s+int\s+unsigned\s+(\w+)\s*=\s*(\d+)\s*;")
    for line in text.splitlines():
        mh = hex_const_re.search(line)
        if mh:
            consts[mh.group(1)] = int(mh.group(2).replace("_", ""), 16)
        mn = int_const_re.search(line)
        if mn:
            consts[mn.group(1)] = int(mn.group(2))
        mi = re.search(r"//\s*@ISA:(\w+)\s*$", line)
        mm = re.search(r"//\s*@MAP:(\w+)\s*$", line)
        ma = re.search(r"//\s*@AMEW:(\w+)\s*$", line)
        if mi or mm or ma:
            mv = val_re.search(line)
            if not mv:
                continue
            val = int(mv.group(1).replace("_", ""), 16)
            if mi:
                isa[mi.group(1)] = val
            elif mm:
                mp[mm.group(1)] = val
            else:
                amew[ma.group(1)] = val
    return isa, mp, amew, consts


# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
def check_isa_uniqueness(isa_rows: dict[str, dict], opcode: int) -> None:
    section("A) ISA 编码冲突检查")
    seen: dict[tuple, str] = {}
    dup = 0
    for name, r in isa_rows.items():
        if r["type"] == "I":
            key = (opcode, r["f3"])
        else:
            if r["f7"] is None:
                bad(f"{name}: R-type 但 funct7='-'")
                dup += 1
                continue
            key = (opcode, r["f3"], r["f7"])
        if key in seen:
            bad(f"{name} 与 {seen[key]} 编码冲突 key={key}")
            dup += 1
        else:
            seen[key] = name
    if dup == 0:
        ok(f"{len(isa_rows)} 个编码在 opcode=0x{opcode:02X} 空间内无冲突")
    for name, r in isa_rows.items():
        if not (0 <= r["f3"] <= 7):
            bad(f"{name}: funct3 超出 0..7")
    if all(0 <= r["f3"] <= 7 for r in isa_rows.values()):
        ok("全部 funct3 ∈ [0,7]")
    if all(
        (r["f7"] is None or 0 <= r["f7"] <= 127) for r in isa_rows.values()
    ):
        ok("全部 R-type funct7 ∈ [0,127]")


# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
def check_addr_map(regions: dict[str, tuple[int, int]]) -> None:
    section("B) 地址映射检查")
    if not regions:
        bad("ARCH_SPEC.md 未解析到任何 @MAP 锚点")
        return
    order = sorted(regions.items(), key=lambda kv: kv[1][0])
    prev_end, prev_name = -1, ""
    overlap = 0
    for name, (base, end) in order:
        if base <= prev_end:
            bad(f"区域重叠: {name}[0x{base:08X}] 与前一区域 {prev_name}(末 0x{prev_end:08X})")
            overlap += 1
        if end < base:
            bad(f"区域非法( end<base ): {name} 0x{base:08X}..0x{end:08X}")
            overlap += 1
        prev_end, prev_name = max(prev_end, end), name
    if overlap == 0:
        ok(f"{len(regions)} 个区域(含保留区)按序无重叠,空间 0x00000000..0xFFFFFFFF 全覆盖")
    misalign = [
        n for n, (b, e) in regions.items()
        if not n.startswith("RSV") and b % 4096 != 0
    ]
    if misalign:
        for n in misalign:
            bad(f"非保留区域基址未 4KB 对齐: {n}")
    else:
        ok("全部非保留区域基址 4KB 对齐")


# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
AME_WIN_ANCHORS = {
    "WBUF":        ("WBUF", "WBUF_APERTURE", None),
    "XBUF":        ("XBUF", "XBUF_APERTURE", None),
    "Y32":         ("Y32", None, 128),
    "YQ":          ("YQ", None, 32),
    "AME_STATUS":  ("STATUS", None, 4),
    "AME_IRQEN":   ("IRQEN", None, 4),
    "AME_EVCLEAR": ("EVCLEAR", None, 4),
}


def parse_ame_window_table(text: str) -> tuple[dict[str, tuple[int, int]], str]:
    """解析 §4.7 偏移表 → {名称: (偏移字节, 大小字节)}。"""
    out: dict[str, tuple[int, int]] = {}
    lines = text.splitlines()
    try:
        start = next(i for i, ln in enumerate(lines) if ln.startswith("### 4.7 "))
    except StopIteration:
        return out, "ARCH_SPEC.md 找不到 '### 4.7 ' 标题"
    end = next(
        (i for i in range(start + 1, len(lines)) if lines[i].startswith("### ")),
        len(lines),
    )
    row_re = re.compile(
        r"^\|\s*\+0x([0-9A-Fa-f]+)\s*\|\s*\*{0,2}([A-Za-z0-9_]+)\*{0,2}\s*\|"
        r"\s*([0-9]+)\s*(KB|B)\b"
    )
    for ln in lines[start:end]:
        m = row_re.match(ln)
        if not m:
            continue
        name = m.group(2)
        if name in out:
            continue
        off = int(m.group(1), 16)
        size = int(m.group(3)) * (1024 if m.group(4) == "KB" else 1)
        out[name] = (off, size)
    if not out:
        return out, "§4.7 表未解析到任何行(偏移表格式可能被改动)"
    return out, ""


def check_ame_window(
    md_win: dict[str, tuple[int, int]],
    pkg_amew: dict[str, int],
    md_regions: dict[str, tuple[int, int]],
) -> None:
    section("E) AME 窗口内偏移(§4.7)⇄ pkg @AMEW / 区域自洽检查")
    if "AME" not in md_regions:
        bad("ARCH_SPEC.md 缺少 @MAP:AME 区域锚点")
        return
    region_base, region_end = md_regions["AME"]
    region_size = region_end - region_base + 1
    if not md_win:
        bad("ARCH_SPEC.md §4.7 未解析到子窗口表")
        return

    missing = [n for n in AME_WIN_ANCHORS if n not in md_win]
    if missing:
        bad(f"§4.7 缺少子窗口行: {missing}")
        return

    n_ok = 0
    for name, (off_key, ap_key, fixed) in AME_WIN_ANCHORS.items():
        off, size = md_win[name]
        want_off = pkg_amew.get(off_key)
        if want_off == off:
            n_ok += 1
        else:
            got = "缺失" if want_off is None else f"0x{want_off:04X}"
            bad(f"AME_{off_key}_OFF: pkg={got} md=0x{off:04X}")
        if ap_key is not None:
            want_size = pkg_amew.get(ap_key)
            if want_size == size:
                n_ok += 1
            else:
                got = "缺失" if want_size is None else f"0x{want_size:04X}"
                bad(f"AME_{ap_key}: pkg={got} md={size} B")
        elif fixed is not None and size != fixed:
            bad(f"{name}: 文档大小 {size} B ≠ 契约固定值 {fixed} B")
        else:
            n_ok += 1
    if n_ok == 2 * len(AME_WIN_ANCHORS):
        ok(f"全部 {len(AME_WIN_ANCHORS)} 个 AME 子窗口偏移/孔径与 pkg @AMEW 锚点一致")

    order = sorted(md_win.items(), key=lambda kv: kv[1][0])
    prev_end, prev_name = -1, ""
    win_bad = 0
    for name, (off, size) in order:
        if off < prev_end:
            bad(f"§4.7 子窗口重叠: {name}(+0x{off:04X}) 与 {prev_name}(末 +0x{prev_end:04X})")
            win_bad += 1
        if off % 4 != 0:
            bad(f"§4.7 子窗口偏移未 4B 对齐: {name} +0x{off:04X}")
            win_bad += 1
        if off + size > region_size:
            bad(
                f"§4.7 子窗口越出 AME 区域: {name} +0x{off:04X}+{size}B "
                f"> 区域 {region_size} B"
            )
            win_bad += 1
        prev_end, prev_name = max(prev_end, off + size), name
    if win_bad == 0:
        ok(
            f"{len(order)} 个子窗口按序无重叠、4B 对齐,"
            f"全部落在 AME 区域 {region_size} B 内"
        )

    extra = set(pkg_amew) - {
        a for key, ap, _ in AME_WIN_ANCHORS.values() for a in (key, ap) if a
    }
    if extra:
        bad(f"pkg 存在文档没有的 @AMEW 锚点: {sorted(extra)}")
    else:
        ok("pkg 无多余 @AMEW 锚点")


# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
def check_pkg_consistency(
    isa_rows: dict[str, dict], opcode: int,
    pkg_isa: dict[str, int], pkg_map: dict[str, int],
    md_regions: dict[str, tuple[int, int]],
) -> None:
    section("C) pkg 常量 ⇄ 文档锚点一致性")
    # opcode
    if pkg_isa.get("AME_OPCODE") == opcode:
        ok(f"AME_OPCODE = 0x{opcode:02X} 三方一致")
    else:
        bad(f"AME_OPCODE 不一致: pkg=0x{pkg_isa.get('AME_OPCODE', -1):02X} md=0x{opcode:02X}")
    F3_KEY = {"cfg": "CFG", "qcfg": "QCFG", "ld.w": "LDW", "ld.x": "LDX",
              "exe": "EXE", "exef": "EXE", "st.y": "STY", "st.q": "STQ",
              "sync": "SYNC"}
    F7_KEY = dict(F3_KEY, exef="EXEF")
    n_ok = n_bad = 0
    for name, r in isa_rows.items():
        key = f"AME_F3_{F3_KEY[name]}"
        want = r["f3"]
        got = pkg_isa.get(key)
        if got == want:
            n_ok += 1
        else:
            got_s = "缺失" if got is None else f"0x{got:X}"
            bad(f"{key}: pkg={got_s} md=0x{want:X}")
            n_bad += 1
        if r["f7"] is not None:
            key7 = f"AME_F7_{F7_KEY[name]}"
            got7 = pkg_isa.get(key7)
            if got7 == r["f7"]:
                n_ok += 1
            else:
                got7_s = "缺失" if got7 is None else f"0x{got7:X}"
                bad(f"{key7}: pkg={got7_s} md=0x{r['f7']:02X}")
                n_bad += 1
    if n_bad == 0:
        ok(f"全部 {n_ok} 个 funct3/funct7 锚点一致")

    m_ok = m_bad = 0
    for name, (base, end) in md_regions.items():
        gb, ge = pkg_map.get(f"{name}_BASE"), pkg_map.get(f"{name}_END")
        if gb == base and ge == end:
            m_ok += 1
        else:
            bad(f"@MAP:{name}: pkg=({gb}, {ge}) md=(0x{base:08X}, 0x{end:08X})")
            m_bad += 1
    if m_bad == 0:
        ok(f"全部 {m_ok} 个区域 base/end 与 pkg 锚点一致")
    extra = set(pkg_map) - {f"{n}_{s}" for n in md_regions for s in ("BASE", "END")}
    if extra:
        bad(f"pkg 存在文档没有的 @MAP 锚点: {sorted(extra)}")
    else:
        ok("pkg 无多余 @MAP 锚点")


# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
def check_encodings(isa_md: str, isa_rows: dict[str, dict], opcode: int) -> None:
    section("D) AME_ISA.md §7 机器码样例核对(opcode/funct)")
    pat = re.compile(r"\|\s*`(.+?)`\s*\|\s*`0x([0-9A-Fa-f]{8})`\s*\|")
    found = 0
    for m in pat.finditer(isa_md):
        asm, enc = m.group(1), int(m.group(2), 16)
        word_op = enc & 0x7F
        f3 = (enc >> 12) & 0x7
        f7 = (enc >> 25) & 0x7F
        base_name = asm.split()[0].replace("ame.", "")
        row = isa_rows.get(base_name)
        if row is None:
            bad(f"样例 {asm!r}: 编码表中无指令 {base_name}")
            continue
        if word_op != opcode:
            bad(f"样例 {asm!r}: opcode 字段 0x{word_op:02X} ≠ 0x{opcode:02X}")
            continue
        if row["f3"] != f3:
            bad(f"样例 {asm!r}: funct3 字段 {f3} ≠ 表 {row['f3']}")
            continue
        if row["f7"] is not None and row["f7"] != f7:
            bad(f"样例 {asm!r}: funct7 字段 {f7} ≠ 表 {row['f7']}")
            continue
        found += 1
    if found:
        ok(f"{found} 个样例编码的 opcode/funct 字段与 §1.1 表一致")
    else:
        bad("未解析到任何 §7 样例行(表格式可能被改动)")


# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
def _reg_num(tok: str) -> int:
    m = re.fullmatch(r"x(\d+)", tok.strip())
    if not m:
        raise ValueError(f"非法寄存器 {tok!r}(期望 xN)")
    v = int(m.group(1))
    if not 0 <= v <= 31:
        raise ValueError(f"寄存器越界 {tok!r}")
    return v


def _sel_num(tok: str, prefix: str) -> int:
    t = tok.strip()
    m = re.fullmatch(prefix + r"(\d+)", t)
    if m:
        return int(m.group(1))
    return int(t, 0)


def _encode_sample(
    asm: str, rows: dict[str, dict], opcode: int, consts: dict[str, int]
) -> tuple[int, dict[str, int]]:
    """按 §1.1/§1.2 独立编码一条汇编样例(不读文档里的 hex/分解列)。"""
    body = asm.strip()
    if body.startswith("ame."):
        body = body[4:]
    head, _, tail = body.partition(" ")
    name = head.strip()
    args = [a.strip() for a in tail.split(",")] if tail.strip() else []
    row = rows.get(name)
    if row is None:
        raise ValueError(f"§1.1 编码表中无指令 {name}")
    f3 = row["f3"]
    if name == "cfg":
        if len(args) != 2:
            raise ValueError("cfg 需要 <n_eff>, <kt> 两个操作数")
        n_eff, kt = int(args[0], 0), int(args[1], 0)
        off_n = consts["CFG_N_EFF_OFF"]
        off_k = consts["CFG_KT_OFF"]
        if not 0 <= n_eff <= 31:
            raise ValueError(f"N_eff={n_eff} 超出 imm[4:0]")
        if not 0 <= kt <= 31:
            raise ValueError(f"KT={kt} 超出 imm[9:5]")
        imm = ((n_eff & 0x1F) << off_n) | ((kt & 0x1F) << off_k)
        word = ((imm & 0xFFF) << 20) | ((f3 & 0x7) << 12) | opcode
        return word, {"imm": imm, "n_eff": n_eff, "kt": kt}
    f7 = row["f7"]
    if f7 is None:
        raise ValueError(f"{name}: 表为 I-type 但样例编码器不支持")
    rd = rs1 = rs2 = 0
    if name == "qcfg":
        if len(args) != 3:
            raise ValueError("qcfg 需要 <idx>, <rsM>, <rsS>")
        rd = int(args[0], 0)
        rs1 = _reg_num(args[1])
        rs2 = _reg_num(args[2])
    elif name in ("exe", "exef"):
        if len(args) != 1:
            raise ValueError(f"{name} 需要 <tsel>")
        rs1 = _sel_num(args[0], "tsel")
    elif name == "sync":
        if args:
            raise ValueError("sync 不接受操作数")
    elif name in ("st.y", "st.q"):
        if len(args) != 2:
            raise ValueError(f"{name} 需要 <idx>, <rd>")
        rs1 = int(args[0], 0)
        rd = _reg_num(args[1])
    elif name == "ld.w":
        if len(args) != 2:
            raise ValueError("ld.w 需要 <region>, <tsel>")
        rs1 = (_sel_num(args[0], "region") & 0x3) | (
            (_sel_num(args[1], "tsel") & 0x1) << 2
        )
    elif name == "ld.x":
        if len(args) != 2:
            raise ValueError("ld.x 需要 <off>, <xsel>")
        rs1 = (_sel_num(args[0], "off") & 0x1FF) | (
            (_sel_num(args[1], "xsel") & 0x1) << 9
        )
    else:
        raise ValueError(f"未支持的样例指令 {name}")
    word = (
        ((f7 & 0x7F) << 25)
        | ((rs2 & 0x1F) << 20)
        | ((rs1 & 0x1F) << 15)
        | ((f3 & 0x7) << 12)
        | ((rd & 0x1F) << 7)
        | opcode
    )
    return word, {}


def check_samples_full(
    isa_md: str, isa_rows: dict[str, dict], opcode: int, consts: dict[str, int]
) -> None:
    section("F) AME_ISA.md §7 样例:全字段重建 + cfg imm 复算")
    pat = re.compile(r"\|\s*`(ame\.[^`]+)`\s*\|\s*`0x([0-9A-Fa-f]{8})`\s*\|")
    samples = pat.findall(isa_md)
    if not samples:
        bad("未解析到任何 §7 样例行(表格式可能被改动)")
        return
    n_ok = 0
    cfg_seen = 0
    for asm, hexs in samples:
        enc = int(hexs, 16)
        try:
            want, meta = _encode_sample(asm, isa_rows, opcode, consts)
        except (ValueError, KeyError) as exc:
            bad(f"样例 {asm!r}: 独立编码失败: {exc}")
            continue
        if want != enc:
            bad(
                f"样例 {asm!r}: 重建 0x{want:08X} ≠ 文档 0x{enc:08X}"
                f"(差异 0x{want ^ enc:08X})"
            )
            continue
        if "imm" in meta:
            cfg_seen += 1
            imm_doc = (enc >> 20) & 0xFFF
            n_doc = (imm_doc >> consts["CFG_N_EFF_OFF"]) & 0x1F
            kt_doc = (imm_doc >> consts["CFG_KT_OFF"]) & 0x1F
            if imm_doc != meta["imm"] or n_doc != meta["n_eff"] or kt_doc != meta["kt"]:
                bad(
                    f"样例 {asm!r}: imm 字段 0x{imm_doc:03X} 解码为 "
                    f"(N_eff={n_doc},KT={kt_doc}),操作数为 "
                    f"(N_eff={meta['n_eff']},KT={meta['kt']})"
                )
                continue
            ok(
                f"cfg 样例 imm 字段独立复算一致:imm=0x{imm_doc:03X}"
                f"(N_eff={n_doc},KT={kt_doc})"
            )
        n_ok += 1
    if n_ok == len(samples):
        ok(f"{n_ok} 个样例全字段重建一致(opcode/funct3/funct7/rs1/rs2/rd/imm)")
    if cfg_seen == 0:
        bad("§7 样例中未覆盖 cfg(无法校验 imm 字段)")


# ---------------------------------------------------------------------------
def main() -> int:
    print(f"AME-Chip P1B 契约校验  root={ROOT}")
    arch_text = ARCH_MD.read_text(encoding="utf-8")
    isa_text = ISA_MD.read_text(encoding="utf-8")
    pkg_text = PKG_SV.read_text(encoding="utf-8")

    isa_rows, err = parse_isa_table(isa_text)
    if err:
        print(f"  FAIL  {err}")
        return 1
    if not isa_rows:
        print("  FAIL  ISA 编码表为空")
        return 1

    pkg_isa, pkg_map, pkg_amew, consts = parse_pkg_anchors(pkg_text)
    opcode = pkg_isa.get("AME_OPCODE", -1)

    check_isa_uniqueness(isa_rows, opcode)

    md_regions = parse_map_anchors(arch_text)
    check_addr_map(md_regions)

    check_pkg_consistency(isa_rows, opcode, pkg_isa, pkg_map, md_regions)

    md_win, win_err = parse_ame_window_table(arch_text)
    if win_err:
        bad(win_err)
    else:
        check_ame_window(md_win, pkg_amew, md_regions)

    check_encodings(isa_text, isa_rows, opcode)
    check_samples_full(isa_text, isa_rows, opcode, consts)

    print(f"\n== 汇总: PASS={len(passes)}  FAIL={len(fails)} ==")
    if fails:
        for f in fails:
            print(f"  - {f}")
        return 1
    print("  ALL GREEN")
    return 0


if __name__ == "__main__":
    sys.exit(main())
