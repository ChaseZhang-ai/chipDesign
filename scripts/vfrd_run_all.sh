#!/usr/bin/env bash
# P3D 一键复现:场景生成 → 全 real 全芯片仿真 → golden 终判 + KPI
set -euo pipefail
cd "$(dirname "$0")/../tb/soc"
make e2e
echo
echo "== artifacts: tb/soc/build/{p3d_scene.hex,p3d_golden.npz,p3d_e2e.log,p3d_check.log} =="
