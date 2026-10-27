#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# check_boot_hex.sh — boot ROM 冻结回归护栏(P4A2 任务 0,裁决 P4B-01/P4B-06)
#
# 背景: scripts/build_hex.py boot 从 rtl/soc/boot/boot.s 重装旧停机镜像
# ("AME-CHIP BOOT OK"+wfi),2026-10-24 曾静默覆盖已冻结的 P3D loader 镜像,
# 导致 P4A 网表/GDS 烤入错误 ROM(P4B-01 BLOCKER)。
#
# 行为: 权威镜像冻结在 syn/amechip/boot_frozen/boot.hex(P3D loader,
# "P3D BOOT OK"+4KB XMEM→OCRAM 拷贝+跳转,源 tb/soc/verify_p3d_boot.s)。
# 本脚本校验 rtl/soc/boot/boot.hex 与权威镜像逐字节一致;不一致则
# **先恢复冻结镜像再报错退出**(build_hex.py 已把回退镜像写到盘上,
# 若只报错不恢复,下一次综合仍会烤入错误 ROM)。
#
# 用法: bash check_boot_hex.sh [REPO_ROOT]   (默认仓库根 = 本脚本上三级)
# 退出码: 0 = 一致;1 = 曾不一致(已恢复,构建必须中止)
# -----------------------------------------------------------------------------
set -u
REPO="${1:-$(cd "$(dirname "$0")/../../.." && pwd)}"
FROZEN="$REPO/syn/amechip/boot_frozen/boot.hex"
TARGET="$REPO/rtl/soc/boot/boot.hex"

if [ ! -f "$FROZEN" ]; then
  echo "BOOT_HEX_GUARD ERROR: 冻结镜像缺失: $FROZEN" >&2
  exit 1
fi
if [ ! -f "$TARGET" ]; then
  echo "BOOT_HEX_GUARD ERROR: 目标缺失: $TARGET(从冻结镜像恢复)" >&2
  cp "$FROZEN" "$TARGET"
  exit 1
fi

m_t=$(md5sum "$TARGET" | cut -d' ' -f1)
m_f=$(md5sum "$FROZEN" | cut -d' ' -f1)
if [ "$m_t" = "$m_f" ]; then
  echo "BOOT_HEX_GUARD OK: $TARGET md5=$m_t (P3D loader 冻结镜像)"
  exit 0
fi

echo "BOOT_HEX_GUARD VIOLATION: $TARGET md5=$m_t != 冻结镜像 md5=$m_f" >&2
echo "  (boot.hex 被回退——典型原因: scripts/build_hex.py boot 从 boot.s 重装旧停机镜像, 见 P4B-06)" >&2
echo "  正在从冻结镜像恢复 $TARGET ..." >&2
cp "$FROZEN" "$TARGET"
echo "  已恢复为 md5=$m_f;本次构建中止。若确要更换 ROM 内容,须走 ROM 重冻结裁决并同步更新" >&2
echo "  syn/amechip/boot_frozen/boot.hex(见 reports/P4A2_REPORT.md 任务 0)。" >&2
exit 1
