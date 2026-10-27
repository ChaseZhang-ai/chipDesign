`timescale 1ns/1ps
`ifndef _AMECHIP_PKG_SV
 `include "amechip_pkg.sv"
`endif

module tb_ame_model #(
  parameter int AME_M = 16,
  parameter int AME_N = 16
) (
  input  logic        clk_i,
  input  logic        rst_ni,

  input  logic        req_valid,
  input  logic [31:0] req_instr,
  input  logic [31:0] req_rs1,
  input  logic [31:0] req_rs2,
  output logic        req_ready,
  output logic        resp_valid,
  output logic [31:0] resp_data,
  output logic        resp_err,

  input  logic        xstall_i      // 人为反压(协议合法的额外 !ready)
);

  logic [5:0]  n_eff, kt;
  logic [31:0] rq_m   [0:31];
  logic [5:0]  rq_s   [0:31];
  logic        rq_r   [0:31];
  logic [7:0]  wbuf   [0:1023];
  logic [7:0]  xbuf   [0:1023];
  logic [7:0]  tile   [0:1][0:AME_N-1][0:AME_M-1];
  logic [7:0]  xreg   [0:1][0:AME_M-1];
  logic signed [31:0] y [0:AME_N-1];

  logic [1:0] tset [0:1];
  logic [1:0] xset [0:1];
  logic [7:0] ld_cnt  [0:3];   // [0:1]=ld.w 组 0/1,[2:3]=ld.x 组 0/1
  logic [7:0] exe_cnt;         // exe 背景倒计时(→ 阵列 IDLE)

  wire array_idle = (exe_cnt == 8'd0) && (tset[0] != 2'd1) && (tset[1] != 2'd1);

  wire [2:0] f3 = req_instr[14:12];
  wire [6:0] f7 = req_instr[31:25];
  wire [5:0] cfg_n = req_instr[4:0];
  wire [5:0] cfg_k = req_instr[9:5];

  logic accept_ok;
  always_comb begin
    case (f3)
      3'd0, 3'd1, 3'd5, 3'd6, 3'd7:
        accept_ok = array_idle;                                       // cfg/qcfg/st.*/sync
      3'd2: accept_ok = (tset[req_rs1[2]] == 2'd0) || (tset[req_rs1[2]] == 2'd2);   // ld.w
      3'd3: accept_ok = (xset[req_rs1[9]] == 2'd0) || (xset[req_rs1[9]] == 2'd2);   // ld.x
      3'd4: accept_ok = array_idle && (tset[req_rs1[0]] == 2'd2)
                        && (xset[req_rs1[0]] == 2'd2);                // exe/exef
      default: accept_ok = 1'b0;
    endcase
  end

  wire accept = req_valid && accept_ok && !xstall_i;

  assign req_ready  = accept_ok && !xstall_i;

  logic        resp_v_q;
  logic [31:0] resp_d_q;
  logic        resp_e_q;
  assign resp_valid = resp_v_q;
  assign resp_data  = resp_d_q;
  assign resp_err   = resp_e_q;

  logic [31:0] r_data;
  logic        r_err;

  function automatic logic signed [31:0] requant(input integer nidx);
    logic signed [63:0] p;
    logic signed [63:0] yy;
    logic signed [63:0] mm;
    logic signed [31:0] v;
    begin
      yy = {{32{y[nidx][31]}}, y[nidx]};      // y:int64 语义符号扩展
      mm = $signed({32'h0, rq_m[nidx]});      // M:uint32 零扩展
      p  = yy * mm;
      if (rq_r[nidx]) p = p + (64'sd1 <<< (rq_s[nidx] - 1));
      v = p >>> rq_s[nidx];
      if (v > 32'sd127)  v = 32'sd127;
      if (v < -32'sd128) v = -32'sd128;
      requant = v;
    end
  endfunction

  always_comb begin
    r_data = 32'h0;
    r_err  = 1'b0;
    if (accept) begin
      case (f3)
        3'd0: begin // cfg
          if ((req_instr[11:10] != 2'b00) || (cfg_n == 6'd0)
              || (cfg_n > 6'd16) || (cfg_k == 6'd0) || (cfg_k > 6'd16))
            r_err = 1'b1;
        end
        3'd1: begin // qcfg
          if ((req_rs2[31:7] != 25'h0) || (req_rs2[5:0] == 6'd0)
              || (req_instr[11:7] >= 5'd16))
            r_err = 1'b1;
        end
        3'd2: if (req_rs1[31:3] != 29'h0)  r_err = 1'b1;      // ld.w
        3'd3: if (req_rs1[31:10] != 22'h0) r_err = 1'b1;      // ld.x
        3'd4: begin // exe/exef
          if ((req_rs1[31:1] != 31'h0) || (n_eff == 6'd0) || (kt == 6'd0))
            r_err = 1'b1;
        end
        3'd5, 3'd6: begin // st.y/st.q
          if (req_rs1[31:5] != 27'h0)
            r_err = 1'b1;
          else if (req_rs1[4:0] >= n_eff) begin
            r_err = 1'b1;                                     // i ≥ N_eff → 0 + ERR
          end else begin
            r_data = (f3 == 3'd5) ? y[req_rs1[4:0]] : requant(req_rs1[4:0]);
          end
        end
        default: ; // sync:无操作
      endcase
    end
  end

  integer n, k;
  logic signed [31:0] acc;
  logic signed [31:0] prod;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      n_eff   <= 6'd0;
      kt      <= 6'd0;
      exe_cnt <= 8'd0;
      tset[0] <= 2'd0; tset[1] <= 2'd0;
      xset[0] <= 2'd0; xset[1] <= 2'd0;
      ld_cnt[0] <= 8'd0; ld_cnt[1] <= 8'd0; ld_cnt[2] <= 8'd0; ld_cnt[3] <= 8'd0;
      resp_v_q <= 1'b0;
      resp_d_q <= 32'h0;
      resp_e_q <= 1'b0;
      for (n = 0; n < 32; n++) begin rq_m[n] <= 32'h0; rq_s[n] <= 6'd0; rq_r[n] <= 1'b0; end
      for (n = 0; n < AME_N; n++) y[n] <= 32'sd0;
    end else begin
      for (n = 0; n < 2; n++) begin
        if (tset[n] == 2'd1) begin
          if (ld_cnt[n] <= 8'd1) begin tset[n] <= 2'd2; ld_cnt[n] <= 8'd0; end
          else ld_cnt[n] <= ld_cnt[n] - 8'd1;
        end
        if (xset[n] == 2'd1) begin
          if (ld_cnt[n + 2] <= 8'd1) begin xset[n] <= 2'd2; ld_cnt[n + 2] <= 8'd0; end
          else ld_cnt[n + 2] <= ld_cnt[n + 2] - 8'd1;
        end
      end
      if (exe_cnt != 8'd0) exe_cnt <= exe_cnt - 8'd1;

      if (exe_cnt <= 8'd1) begin
        for (n = 0; n < 2; n++) begin
          if (tset[n] == 2'd3) tset[n] <= 2'd2;
          if (xset[n] == 2'd3) xset[n] <= 2'd2;
        end
      end

      if (accept) begin
        case (f3)
          3'd0: if (!r_err) begin n_eff <= cfg_n; kt <= cfg_k; end
          3'd1: if (!r_err) begin
            rq_m[req_instr[11:7]] <= req_rs1;
            rq_s[req_instr[11:7]] <= req_rs2[5:0];
            rq_r[req_instr[11:7]] <= req_rs2[6];
          end
          3'd2: if (!r_err) begin
            tset[req_rs1[2]]   <= 2'd1;
            ld_cnt[req_rs1[2]] <= 8'd16;               // AME_M 拍装载(§6)
            for (n = 0; n < AME_N; n++)
              for (k = 0; k < AME_M; k++)
                tile[req_rs1[2]][n][k] <= wbuf[req_rs1[1:0] * 256 + n * kt + k];
          end
          3'd3: if (!r_err) begin
            xset[req_rs1[9]]     <= 2'd1;
            ld_cnt[2 + req_rs1[9]] <= 8'd2;            // ≤2 拍(§6)
            for (k = 0; k < AME_M; k++)
              xreg[req_rs1[9]][k] <= xbuf[req_rs1[8:0] + k];
          end
          3'd4: if (!r_err) begin
            if (f7 == 7'h05) for (n = 0; n < AME_N; n++) y[n] <= 32'sd0; // EXEF 清 Y
            for (k = 0; k < AME_M; k++)
              for (n = 0; n < AME_N; n++) begin
                prod = $signed(tile[req_rs1[0]][n][k]) * $signed(xreg[req_rs1[0]][k]);
                acc  = y[n] + prod;
                if (acc > 32'sd2147483647)  acc = 32'sd2147483647;
                if (acc < -32'sd2147483648) acc = -32'sd2147483648;
                y[n] <= acc;
              end
            tset[req_rs1[0]]   <= 2'd3;
            xset[req_rs1[0]]   <= 2'd3;
            exe_cnt            <= kt + 8'd2;           // KT+2 拍(§6)
          end
          default: ;
        endcase
      end

      resp_v_q <= accept;
      resp_d_q <= r_data;
      resp_e_q <= r_err;
    end
  end

  integer i;
  initial begin
    for (i = 0; i < 1024; i++) begin
      wbuf[i] = (i * 7 + 13) & 8'hFF;
      xbuf[i] = (i * 7 + 13) & 8'hFF;
    end
    for (n = 0; n < 2; n++)
      for (i = 0; i < AME_N; i++)
        for (k = 0; k < AME_M; k++)
          tile[n][i][k] = 8'h0;
    for (n = 0; n < 2; n++)
      for (k = 0; k < AME_M; k++)
        xreg[n][k] = 8'h0;
  end

endmodule
