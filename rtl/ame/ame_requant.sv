`ifndef _AMECHIP_PKG_SV
 `include "amechip_pkg.sv"
`endif

module ame_requant (
  input  logic        clk_i,  // 乘积寄存时钟
  input  logic [31:0] y_i,    // INT32 累加结果(有符号)
  input  logic [31:0] m_i,    // uint32 乘数
  input  logic [5:0]  s_i,    // 移位量 1..63(0 = 未配置,钳 0)
  input  logic        rnd_i,  // ROUND_SEL:1 = round-half-up
  output logic [7:0]  q_o     // INT8 二补码(组合第 2 拍)
);

  logic [31:0] y1_q;
  logic [31:0] m1_q;
  logic [5:0]  s1_q;
  logic        rn1_q;

  wire [5:0] sh  = (s_i == 6'd0) ? 6'd0 : s_i;
  wire       do_rn = rnd_i && (s_i != 6'd0);

  always_ff @(posedge clk_i) begin
    y1_q  <= y_i;
    m1_q  <= m_i;
    s1_q  <= sh;
    rn1_q <= do_rn;
  end

  logic [63:0] p_u_q;
  logic        y_neg_q;
  logic [31:0] m_q;
  logic [5:0]  sh_q;
  logic [63:0] rnd_add_q;

  wire [63:0] p_u = y1_q * m1_q;   // 32×32 → 64(FF→FF,关键路径只剩乘法)

  always_ff @(posedge clk_i) begin
    p_u_q     <= p_u;
    y_neg_q   <= y1_q[31];
    m_q       <= m1_q;
    sh_q      <= s1_q;
    rnd_add_q <= rn1_q ? (64'd1 << (s1_q - 6'd1)) : 64'd0;
  end

  logic [63:0] corr;
  logic [63:0] prod;
  logic [63:0] biased;
  logic [63:0] shifted;

  assign corr    = y_neg_q ? ({32'd0, m_q} << 32) : 64'd0;  // -(M<<32) mod 2^64
  assign prod    = p_u_q - corr;                            // s64(y)×u64(M) 低 64 位
  assign biased  = prod + rnd_add_q;
  assign shifted = $signed(biased) >>> sh_q;                // 算术右移

  always_comb begin
    if ($signed(shifted) > $signed(64'sd127))      q_o = 8'sd127;
    else if ($signed(shifted) < -$signed(64'sd128)) q_o = -8'sd128;
    else                                           q_o = shifted[7:0];
  end

endmodule
