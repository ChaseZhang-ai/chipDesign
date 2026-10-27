`ifndef _AMECPU_PKG_SV
 `include "amecpu_pkg.sv"
`endif

module cpu_muldiv (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        start_i,
  input  logic [2:0]  fn_i,
  input  logic [31:0] rs1_i,
  input  logic [31:0] rs2_i,
  output logic        busy_o,
  output logic        idle_o,     // S_IDLE:start 可被接受
  output logic        done_o,
  output logic [31:0] result_o
);

  typedef enum logic [1:0] { S_IDLE = 2'd0, S_RUN = 2'd1, S_DONE = 2'd2 } state_e;
  localparam logic [2:0] FN_MUL = 3'd0, FN_MULH = 3'd1, FN_MULHSU = 3'd2, FN_MULHU = 3'd3;

  state_e    state_q;
  logic [5:0] cnt_q;
  logic [2:0] fn_q;

  logic [31:0] mul_a_q;   // 乘数绝对值(不变)
  logic [31:0] mul_b_q;   // 移位中的乘数低半部
  logic [32:0] acc_q;     // 部分和高半部(含进位)
  logic        mul_neg_q; // 64 位积取负

  logic [32:0] div_r_q;   // 余数
  logic [31:0] div_x_q;   // 被除数移位窗(高位先出)
  logic [31:0] div_q_q;   // 商累加
  logic [31:0] div_s_q;   // 除数绝对值
  logic        div_nq_q;  // 商取负
  logic        div_nr_q;  // 余取负

  logic [31:0] result_q;

  logic [31:0] result_cmb;
  always_comb begin
    case (fn_q)
      FN_MUL:    result_cmb = mul_prod[31:0];
      FN_MULH:   result_cmb = mul_fix[63:32];
      FN_MULHSU: result_cmb = mul_fix[63:32];
      FN_MULHU:  result_cmb = mul_prod[63:32];
      default: begin // DIV/REM 族
        if (is_rem_final(fn_q))
          result_cmb = div_nr_q ? (~{div_r_q[31:0]} + 32'd1) : div_r_q[31:0];
        else
          result_cmb = div_nq_q ? (~div_q_q + 32'd1) : div_q_q;
      end
    endcase
  end

  logic        special_q;
  logic [31:0] special_val_q;

  assign busy_o   = (state_q == S_RUN);
  assign idle_o   = (state_q == S_IDLE);
  assign done_o   = (state_q == S_DONE);
  assign result_o = done_o ? (special_q ? special_val_q : result_cmb) : result_q;

  wire is_mul_op  = (fn_i == 3'd0) || (fn_i == 3'd1) || (fn_i == 3'd2) || (fn_i == 3'd3);
  wire mul_signed = (fn_i == FN_MULH) || (fn_i == FN_MULHSU);
  wire div_signed = (fn_i == 3'd4) || (fn_i == 3'd6); // DIV / REM
  wire is_rem     = (fn_i == 3'd6) || (fn_i == 3'd7); // REM / REMU

  logic        st_neg;   // 乘积/商取负
  logic        st_rneg;  // 余数取负
  logic [31:0] st_a, st_s;

  always_comb begin
    st_neg  = 1'b0;
    st_rneg = 1'b0;
    if (is_mul_op) begin
      st_neg = (fn_i == FN_MULH)   ? (rs1_i[31] ^ rs2_i[31])
             : (fn_i == FN_MULHSU) ? rs1_i[31]
             : 1'b0;
      st_a = (fn_i == FN_MULH || fn_i == FN_MULHSU) ?
             ((rs1_i[31]) ? (~rs1_i + 32'd1) : rs1_i) : rs1_i;  // MULH/MULHSU 取 |a|
      st_s = (fn_i == FN_MULH) ?
             ((rs2_i[31]) ? (~rs2_i + 32'd1) : rs2_i) : rs2_i;  // 仅 MULH 取 |b|
    end else begin
      st_neg  = div_signed && (rs1_i[31] ^ rs2_i[31]);
      st_rneg = div_signed && rs1_i[31];
      st_a    = (div_signed && rs1_i[31]) ? (~rs1_i + 32'd1) : rs1_i;
      st_s    = (div_signed && rs2_i[31]) ? (~rs2_i + 32'd1) : rs2_i;
    end
  end

  wire [32:0] mul_add  = acc_q + (mul_b_q[0] ? {1'b0, mul_a_q} : 33'd0);
  wire [32:0] mul_acc_n= {1'b0, mul_add[32:1]};
  wire [31:0] mul_b_n  = {mul_add[0], mul_b_q[31:1]};

  wire [32:0] div_r_shift = {div_r_q[31:0], div_x_q[31]};
  wire        div_ge      = (div_r_shift >= {1'b0, div_s_q});
  wire [32:0] div_r_sub   = div_r_shift - {1'b0, div_s_q};
  wire [32:0] div_r_n     = div_ge ? div_r_sub : div_r_shift;
  wire [31:0] div_x_n     = div_x_q << 1;
  wire [31:0] div_q_n     = {div_q_q[30:0], div_ge};

  wire [63:0] mul_prod = {acc_q[31:0], mul_b_q};
  wire [63:0] mul_fix  = mul_neg_q ? (~mul_prod + 64'd1) : mul_prod;

  function automatic logic is_rem_final(input logic [2:0] f);
    begin
      is_rem_final = f[1];
    end
  endfunction

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q  <= S_IDLE;
      cnt_q    <= 6'd0;
      fn_q     <= 3'd0;
      mul_a_q  <= 32'h0;
      mul_b_q  <= 32'h0;
      acc_q    <= 33'h0;
      mul_neg_q<= 1'b0;
      div_r_q  <= 33'h0;
      div_x_q  <= 32'h0;
      div_q_q  <= 32'h0;
      div_s_q  <= 32'h0;
      div_nq_q  <= 1'b0;
      div_nr_q  <= 1'b0;
      result_q  <= 32'h0;
      special_q <= 1'b0;
      special_val_q <= 32'h0;
    end else begin
      case (state_q)
        S_IDLE: begin
          if (start_i) begin
            fn_q  <= fn_i;
            cnt_q <= 6'd0;
            if (rs2_i == 32'h0 && !is_mul_op) begin
              special_val_q <= is_rem ? rs1_i : 32'hFFFF_FFFF;
              special_q     <= 1'b1;
              result_q      <= is_rem ? rs1_i : 32'hFFFF_FFFF;
              state_q       <= S_DONE;
            end else if (div_signed && (rs1_i == 32'h8000_0000) && (rs2_i == 32'hFFFF_FFFF)) begin
              special_val_q <= is_rem ? 32'h0 : 32'h8000_0000;
              special_q     <= 1'b1;
              result_q      <= is_rem ? 32'h0 : 32'h8000_0000;
              state_q       <= S_DONE;
            end else if (is_mul_op) begin
              mul_a_q  <= st_a;
              mul_b_q  <= st_s;
              acc_q    <= 33'h0;
              mul_neg_q<= st_neg;
              special_q<= 1'b0;
              state_q  <= S_RUN;
            end else begin
              div_x_q  <= st_a;
              div_s_q  <= st_s;
              div_r_q  <= 33'h0;
              div_q_q  <= 32'h0;
              div_nq_q <= st_neg;
              div_nr_q <= st_rneg;
              special_q<= 1'b0;
              state_q  <= S_RUN;
            end
          end
        end

        S_RUN: begin
          cnt_q <= cnt_q + 6'd1;
          if ((fn_q == 3'd0) || (fn_q == 3'd1) || (fn_q == 3'd2) || (fn_q == 3'd3)) begin
            acc_q   <= mul_acc_n;
            mul_b_q <= mul_b_n;
          end else begin
            div_r_q <= div_r_n;
            div_x_q <= div_x_n;
            div_q_q <= div_q_n;
          end
          if (cnt_q == 6'd31) state_q <= S_DONE;
        end

        S_DONE: begin
          result_q <= result_cmb;   // 锁存,供 IDLE 期保持
          state_q  <= S_IDLE;
        end

        default: state_q <= S_IDLE;
      endcase
    end
  end

endmodule
