# M 扩展边界:乘法符号组合、除零、INT_MIN/-1 溢出、REM 符号
  .org 0x10000
boot:
  j start

  .org 0x0
start:
  li x1, -1
  li x2, -1
  mul x3, x1, x2          # -1*-1 = 1
  mulh x4, x1, x2         # 高 32 位 = 0
  li x5, 0x80000000
  mul x6, x5, x5          # 低 32 = 0
  mulh x7, x5, x5         # 0x80000000*0x80000000 = 0x40000000_00000000 → 高 0x40000000
  mulhu x8, x5, x5        # 同上(无符号一致)
  mulhsu x9, x5, x5       # 有符号×无符号:-2^31 * 2^31 = -0x4000_0000_0000_0000 → 高 0xC0000000
  li x10, -1
  mulhu x11, x10, x10     # 0xFFFFFFFF^2 高 = 0xFFFFFFFE
  mulh x12, x10, x10      # (-1)^2 高 = 0
  mulhsu x13, x10, x10    # -1 * 0xFFFFFFFF 高 = 0xFFFFFFFE
  mulhsu x14, x5, x10     # -2^31 * 0xFFFFFFFF = -(2^31)*(2^32-1) → 高?
  mul x15, x10, x5        # 0x80000000
  li x16, 0xFFFFFFFF
  mulhu x17, x16, x16
  mulh x18, x16, x16      # (-1)*(-1) → 0

  # 除法
  li x20, 7
  li x21, -2
  div x22, x20, x21       # -3
  rem x23, x20, x21       # 1
  div x24, x21, x20       # 0
  rem x25, x21, x20       # -2
  divu x26, x21, x20      # 0x7FFFFFFE
  remu x27, x21, x20      # 1
  div x28, x5, x1         # INT_MIN / -1 = INT_MIN(溢出)
  rem x29, x5, x1         # 0
  div x30, x5, x20        # -1140850688*... = -(2^31)/7
  div x31, x20, x0        # 除零 → -1
  divu x5, x20, x0        # 除零 → 0xFFFFFFFF
  rem x6, x20, x0         # 除零 → 被除数 7
  remu x7, x21, x0        # 除零 → 0xFFFFFFFE
  li x8, -7
  div x9, x8, x21         # -7/-2 = 3
  rem x10, x8, x21        # -1
  divu x11, x8, x21       # 0xFFFFFFF9 / 0xFFFFFFFE = 0
  remu x12, x8, x21       # 0xFFFFFFF9
  li x13, 0x7FFFFFFF
  div x14, x13, x21       # -1098415423...(常规)
  mul x15, x13, x13       # 低 32 = 1
  mulh x16, x13, x13      # 0x3FFFFFFF

  ebreak
