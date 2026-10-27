
module stub_ame #(
  parameter int unsigned AME_M       = amechip_pkg::AME_M_DEF,
  parameter int unsigned AME_N       = amechip_pkg::AME_N_DEF,
  parameter int unsigned WBUF_DEPTH  = amechip_pkg::WBUF_DEPTH,  // 1024
  parameter int unsigned XBUF_DEPTH  = amechip_pkg::XBUF_DEPTH   // 1024
) (
  input  logic        clk,
  input  logic        rst_n,

  input  logic        req_valid,
  output logic        req_ready,
  input  logic [31:0] req_instr,
  input  logic [31:0] req_rs1,
  input  logic [31:0] req_rs2,
  output logic        resp_valid,
  output logic [31:0] resp_data,
  output logic        resp_err,

  input  logic        win_req_valid,
  output logic        win_req_ready,
  input  logic        win_req_write,
  input  logic [31:0] win_req_addr,
  input  logic [31:0] win_req_wdata,
  input  logic [3:0]  win_req_wstrb,
  output logic        win_resp_valid,
  output logic [31:0] win_resp_rdata,
  output logic        win_resp_err,

  output logic        busy_o,
  output logic        evt_done_o,
  output logic        evt_err_o
);

  localparam logic [5:0] M6 = AME_M;
  localparam logic [5:0] N6 = AME_N;
  localparam logic [9:0] WBUF_MSK = WBUF_DEPTH - 1;
  localparam logic [9:0] XBUF_MSK = XBUF_DEPTH - 1;

  logic signed [7:0]  tile [0:1][0:AME_N-1][0:AME_M-1];
  logic signed [7:0]  xreg [0:1][0:AME_M-1];
  logic [7:0]         wbuf [0:WBUF_DEPTH-1];
  logic [7:0]         xbuf [0:XBUF_DEPTH-1];
  logic signed [31:0] y_acc  [0:AME_N-1];
  logic [31:0]        rq_m   [0:31];
  logic [5:0]         rq_s   [0:31];
  logic               rq_rnd [0:31];

  logic [5:0] cfg_neff, cfg_kt;
  logic [1:0] tset [0:1];
  logic [1:0] xset [0:1];

  logic [5:0] run_cnt;
  logic [5:0] ldw_cnt;
  logic [1:0] ldx_cnt;
  logic       run_tsel;
  logic       ldw_tsel, ldw_r1, ldw_r0;
  logic       ldx_xsel;
  logic [8:0] ldx_off;

  logic        st_done_q, st_err_q;
  logic [31:0] ame_irqen_q;

  wire idle   = (run_cnt == 6'd0) && (ldw_cnt == 6'd0) && (ldx_cnt == 2'd0);
  wire exe_last = (run_cnt == 6'd1) && (ldw_cnt == 6'd0) && (ldx_cnt == 2'd0);

  wire [2:0] f3   = req_instr[14:12];
  wire [6:0] f7   = req_instr[31:25];
  wire [4:0] rd_f = req_instr[11:7];

  wire is_cfg  = (f3 == amechip_pkg::AME_F3_CFG);
  wire is_qcfg = (f3 == amechip_pkg::AME_F3_QCFG);
  wire is_ldw  = (f3 == amechip_pkg::AME_F3_LDW);
  wire is_ldx  = (f3 == amechip_pkg::AME_F3_LDX);
  wire is_exe  = (f3 == amechip_pkg::AME_F3_EXE);
  wire is_sty  = (f3 == amechip_pkg::AME_F3_STY);
  wire is_stq  = (f3 == amechip_pkg::AME_F3_STQ);
  wire is_sync = (f3 == amechip_pkg::AME_F3_SYNC);

  logic ready_c;
  always @* begin
    if (is_cfg || is_qcfg || is_sty || is_stq || is_sync) ready_c = idle;
    else if (is_ldw) ready_c = (tset[req_rs1[2]] == amechip_pkg::AME_TSET_EMPTY)
                            || (tset[req_rs1[2]] == amechip_pkg::AME_TSET_READY);
    else if (is_ldx) ready_c = (xset[req_rs1[9]] == amechip_pkg::AME_TSET_EMPTY)
                            || (xset[req_rs1[9]] == amechip_pkg::AME_TSET_READY);
    else if (is_exe) ready_c = idle
                            && (tset[req_rs1[0]] == amechip_pkg::AME_TSET_READY)
                            && (xset[req_rs1[0]] == amechip_pkg::AME_TSET_READY);
    else             ready_c = 1'b1;
  end

  assign req_ready = ready_c;
  wire accept = req_valid && req_ready;

  wire [11:0] cfg_imm  = req_instr[31:20];
  wire [4:0]  cfg_n_i  = req_instr[24:20];
  wire [4:0]  cfg_kt_i = req_instr[29:25];

  logic invalid_c;
  always @* begin
    invalid_c = 1'b0;
    if (is_cfg)
      invalid_c = (cfg_imm[11:10] != 2'b00) || (cfg_n_i == 5'd0)
                || ({1'b0, cfg_n_i} > N6) || (cfg_kt_i == 5'd0)
                || ({1'b0, cfg_kt_i} > M6);
    else if (is_qcfg)
      invalid_c = ({1'b0, rd_f} >= N6) || (req_rs2[31:7] != 25'd0)
                || (req_rs2[5:0] == 6'd0);
    else if (is_ldw)
      invalid_c = (req_rs1[31:3] != 29'd0);
    else if (is_ldx)
      invalid_c = (req_rs1[31:10] != 22'd0);
    else if (is_exe)
      invalid_c = (req_rs1[31:1] != 31'd0) || (cfg_neff == 6'd0) || (cfg_kt == 6'd0);
    else if (is_sty || is_stq)
      invalid_c = (req_rs1[31:5] != 27'd0) || ({1'b0, req_rs1[4:0]} >= {1'b0, cfg_neff[4:0]});
  end

  function automatic logic signed [7:0] requant_ch (
    input logic signed [31:0] y,
    input logic [31:0]        m,
    input logic [5:0]         s,
    input logic               rnd
  );
    longint prod;
    prod = longint'(y) * longint'(m);
    if (s == 6'd0) begin
      requant_ch = 8'sd0;
    end else begin
      if (rnd) prod = prod + (64'sd1 <<< (s - 6'd1));
      prod = prod >>> s;
      if      (prod > 127)  requant_ch = 8'sd127;
      else if (prod < -128) requant_ch = -8'sd128;
      else                  requant_ch = prod[7:0];
    end
  endfunction

  wire [4:0] st_idx = req_rs1[4:0];
  wire       st_idx_ok = ({1'b0, st_idx} < {1'b0, cfg_neff[4:0]});
  wire [4:0] st_idx_s = st_idx_ok ? st_idx : 5'd0;
  wire signed [7:0] stq_val = requant_ch(y_acc[st_idx_s], rq_m[st_idx_s],
                                         rq_s[st_idx_s], rq_rnd[st_idx_s]);
  logic [31:0] st_data_c;
  always @* begin
    if (is_sty) st_data_c = st_idx_ok ? y_acc[st_idx_s] : 32'd0;
    else        st_data_c = {{24{stq_val[7]}}, stq_val};
  end

  logic        resp_pend_q;
  logic [31:0] resp_data_q;
  logic        resp_err_q;

  assign resp_valid = resp_pend_q;
  assign resp_data  = resp_data_q;
  assign resp_err   = resp_err_q;

  wire win_evclr_done, win_evclr_err;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      resp_pend_q <= 1'b0; resp_data_q <= 32'd0; resp_err_q <= 1'b0;
      run_cnt <= 6'd0; ldw_cnt <= 6'd0; ldx_cnt <= 2'd0;
      run_tsel <= 1'b0; ldw_tsel <= 1'b0; ldw_r1 <= 1'b0; ldw_r0 <= 1'b0;
      ldx_xsel <= 1'b0; ldx_off <= 9'd0;
      cfg_neff <= 6'd0; cfg_kt <= 6'd0;
      tset[0] <= amechip_pkg::AME_TSET_EMPTY; tset[1] <= amechip_pkg::AME_TSET_EMPTY;
      xset[0] <= amechip_pkg::AME_TSET_EMPTY; xset[1] <= amechip_pkg::AME_TSET_EMPTY;
      st_done_q <= 1'b0; st_err_q <= 1'b0; ame_irqen_q <= 32'd0;
      for (int n = 0; n < AME_N; n++) y_acc[n] <= 32'sd0;
      for (int i = 0; i < 32; i++) begin
        rq_m[i] <= 32'd0; rq_s[i] <= 6'd0; rq_rnd[i] <= 1'b0;
      end
    end else begin
      resp_pend_q <= 1'b0;
      resp_err_q  <= 1'b0;

      if (ldw_cnt != 6'd0) begin
        if (ldw_cnt == 6'd1) begin
          for (int n = 0; n < AME_N; n++) begin
            for (int k = 0; k < AME_M; k++) begin
              if ((n < cfg_neff) && (k < cfg_kt)) begin
                tile[ldw_tsel][n][k] <= $signed(
                  wbuf[({ldw_r1, ldw_r0, 8'd0} + n * cfg_kt + k) % WBUF_DEPTH]);
              end
            end
          end
          tset[ldw_tsel] <= amechip_pkg::AME_TSET_READY;
        end
        ldw_cnt <= ldw_cnt - 6'd1;
      end

      if (ldx_cnt != 2'd0) begin
        if (ldx_cnt == 2'd1) begin
          for (int k = 0; k < AME_M; k++) begin
            if (k < cfg_kt)
              xreg[ldx_xsel][k] <= $signed(xbuf[(ldx_off + k) & XBUF_MSK]);
          end
          xset[ldx_xsel] <= amechip_pkg::AME_TSET_READY;
        end
        ldx_cnt <= ldx_cnt - 2'd1;
      end

      if (run_cnt != 6'd0) begin
        if (run_cnt == 6'd1) begin
          begin : accum
            longint tmp [0:AME_N-1];
            for (int n = 0; n < AME_N; n++) tmp[n] = longint'(y_acc[n]);
            for (int k = 0; k < AME_M; k++) begin
              if (k < cfg_kt) begin
                for (int n = 0; n < AME_N; n++) begin
                  if (n < cfg_neff) begin
                    tmp[n] = tmp[n]
                           + longint'($signed(tile[run_tsel][n][k]))
                           * longint'($signed(xreg[run_tsel][k]));
                    if (tmp[n] > 64'sd2147483647)       tmp[n] = 64'sd2147483647;
                    else if (tmp[n] < -64'sd2147483648) tmp[n] = -64'sd2147483648;
                  end
                end
              end
            end
            for (int n = 0; n < AME_N; n++) y_acc[n] <= tmp[n][31:0];
          end
          tset[run_tsel] <= amechip_pkg::AME_TSET_EMPTY;
          xset[run_tsel] <= amechip_pkg::AME_TSET_EMPTY;
        end
        run_cnt <= run_cnt - 6'd1;
      end

      if (accept) begin
        resp_pend_q <= 1'b1;
        resp_err_q  <= invalid_c;
        resp_data_q <= 32'd0;
        if (is_cfg) begin
          if (!invalid_c) begin
            cfg_neff <= {1'b0, cfg_n_i};
            cfg_kt   <= {1'b0, cfg_kt_i};
          end
        end else if (is_qcfg) begin
          if (!invalid_c) begin
            rq_m[rd_f]   <= req_rs1;
            rq_s[rd_f]   <= req_rs2[5:0];
            rq_rnd[rd_f] <= req_rs2[6];
          end
        end else if (is_ldw) begin
          ldw_tsel <= req_rs1[2];
          ldw_r1   <= req_rs1[1];
          ldw_r0   <= req_rs1[0];
          tset[req_rs1[2]] <= amechip_pkg::AME_TSET_LOADING;
          ldw_cnt  <= M6;
        end else if (is_ldx) begin
          ldx_xsel <= req_rs1[9];
          ldx_off  <= req_rs1[8:0];
          xset[req_rs1[9]] <= amechip_pkg::AME_TSET_LOADING;
          ldx_cnt  <= 2'd2;
        end else if (is_exe) begin
          if (!invalid_c) begin
            if (f7 == amechip_pkg::AME_F7_EXEF) begin
              for (int n = 0; n < AME_N; n++) y_acc[n] <= 32'sd0;
            end
            run_tsel <= req_rs1[0];
            tset[req_rs1[0]] <= amechip_pkg::AME_TSET_RUNNING;
            xset[req_rs1[0]] <= amechip_pkg::AME_TSET_RUNNING;
            run_cnt  <= cfg_kt + 6'd2;
          end
        end else if (is_sty || is_stq) begin
          resp_data_q <= st_data_c;
        end
      end

      if (accept && invalid_c) st_err_q <= 1'b1;
      if (exe_last) st_done_q <= 1'b1;
      if (win_evclr_done) st_done_q <= 1'b0;           // W1C(§4.7 EVCLEAR)
      if (win_evclr_err)  st_err_q  <= 1'b0;
    end
  end

  assign evt_done_o = exe_last  && ame_irqen_q[0];
  assign evt_err_o  = (accept && invalid_c) && ame_irqen_q[1];
  assign busy_o     = !idle;

  logic        win_resp_pend_q;
  logic [31:0] win_resp_data_q;
  logic        win_resp_err_q;

  assign win_req_ready  = !win_resp_pend_q;
  assign win_resp_valid = win_resp_pend_q;
  assign win_resp_rdata = win_resp_data_q;
  assign win_resp_err   = win_resp_err_q;

  wire        win_fire = win_req_valid && win_req_ready;
  wire        win_wr   = win_fire && win_req_write;
  wire        win_align = (win_req_addr[1:0] == 2'b00);
  wire [12:0] woff     = win_req_addr[12:0] - 13'h1000;


  wire in_win  = (win_req_addr >= amechip_pkg::A_AME_BASE)
              && (win_req_addr <= amechip_pkg::A_AME_END);
  wire in_wbuf = in_win && (woff < amechip_pkg::AME_XBUF_OFF);
  wire in_xbuf = in_win && (woff >= amechip_pkg::AME_XBUF_OFF)
                         && (woff < amechip_pkg::AME_Y32_OFF);

  wire in_y32  = (win_req_addr >= (amechip_pkg::A_AME_BASE + amechip_pkg::AME_Y32_OFF))
              && (win_req_addr <  (amechip_pkg::A_AME_BASE + amechip_pkg::AME_Y32_OFF + 32'h80));
  wire in_yq   = (win_req_addr >= (amechip_pkg::A_AME_BASE + amechip_pkg::AME_YQ_OFF))
              && (win_req_addr <  (amechip_pkg::A_AME_BASE + amechip_pkg::AME_YQ_OFF + 32'h20));
  wire is_status  = (win_req_addr == (amechip_pkg::A_AME_BASE + amechip_pkg::AME_STATUS_OFF));
  wire is_irqen   = (win_req_addr == (amechip_pkg::A_AME_BASE + amechip_pkg::AME_IRQEN_OFF));
  wire is_evclear = (win_req_addr == (amechip_pkg::A_AME_BASE + amechip_pkg::AME_EVCLEAR_OFF));

  wire        y32_n_ok = ({1'b0, woff[6:2]} < {1'b0, N6});   // n < AME_N
  wire [4:0]  y32_n    = woff[6:2];
  wire [1:0]  yq_word  = woff[3:2];

  assign win_evclr_done = win_wr && is_evclear && win_req_wdata[0];
  assign win_evclr_err  = win_wr && is_evclear && win_req_wdata[1];

  logic [31:0] win_rd_c;
  logic        win_rd_err_c;
  logic        win_wr_err_c;

  always @* begin
    win_rd_c     = 32'd0;
    win_rd_err_c = 1'b0;
    win_wr_err_c = 1'b0;

    if (!win_align) begin
      win_wr_err_c = 1'b1;
    end else if (in_wbuf || in_xbuf) begin
      if (!win_wr) begin
        if (in_wbuf) begin
          win_rd_c = {wbuf[(woff[9:0] + 10'd3) & WBUF_MSK],
                      wbuf[(woff[9:0] + 10'd2) & WBUF_MSK],
                      wbuf[(woff[9:0] + 10'd1) & WBUF_MSK],
                      wbuf[(woff[9:0] + 10'd0) & WBUF_MSK]};
        end else begin
          win_rd_c = {xbuf[(woff[9:0] + 10'd3) & XBUF_MSK],
                      xbuf[(woff[9:0] + 10'd2) & XBUF_MSK],
                      xbuf[(woff[9:0] + 10'd1) & XBUF_MSK],
                      xbuf[(woff[9:0] + 10'd0) & XBUF_MSK]};
        end
      end
    end else if (in_y32) begin
      if (win_wr) begin
        if (!y32_n_ok)   win_wr_err_c = 1'b1;
        else if (busy_o) win_wr_err_c = 1'b1;
      end else begin
        win_rd_c = y32_n_ok ? y_acc[y32_n] : 32'd0;
      end
    end else if (in_yq) begin
      if (win_wr) begin
        win_wr_err_c = 1'b1;                           // YQ RO
      end else begin
        if (woff[4] == 1'b0) begin
          win_rd_c = {requant_ch(y_acc[{yq_word, 2'd3}], rq_m[{yq_word, 2'd3}], rq_s[{yq_word, 2'd3}], rq_rnd[{yq_word, 2'd3}]),
                      requant_ch(y_acc[{yq_word, 2'd2}], rq_m[{yq_word, 2'd2}], rq_s[{yq_word, 2'd2}], rq_rnd[{yq_word, 2'd2}]),
                      requant_ch(y_acc[{yq_word, 2'd1}], rq_m[{yq_word, 2'd1}], rq_s[{yq_word, 2'd1}], rq_rnd[{yq_word, 2'd1}]),
                      requant_ch(y_acc[{yq_word, 2'd0}], rq_m[{yq_word, 2'd0}], rq_s[{yq_word, 2'd0}], rq_rnd[{yq_word, 2'd0}])};
        end
      end
    end else if (is_status) begin
      if (win_wr) win_wr_err_c = 1'b1;
      else win_rd_c = {24'd0, st_err_q, 1'b0,
                       (xset[1] == amechip_pkg::AME_TSET_READY),
                       (xset[0] == amechip_pkg::AME_TSET_READY),
                       (tset[1] == amechip_pkg::AME_TSET_READY),
                       (tset[0] == amechip_pkg::AME_TSET_READY),
                       st_done_q, busy_o};
    end else if (is_irqen) begin
      if (win_wr) ;
      else win_rd_c = ame_irqen_q;
    end else if (is_evclear) begin
      if (win_wr) ;
      else win_rd_c = 32'd0;
    end else begin
      if (win_wr) win_wr_err_c = 1'b1;
    end
  end

  wire [9:0] wbyte = woff[9:0];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      win_resp_pend_q <= 1'b0;
      win_resp_data_q <= 32'd0;
      win_resp_err_q  <= 1'b0;
      ame_irqen_q     <= 32'd0;
    end else begin
      win_resp_pend_q <= 1'b0;
      win_resp_err_q  <= 1'b0;
      if (win_fire) begin
        win_resp_pend_q <= 1'b1;
        win_resp_err_q  <= win_wr ? win_wr_err_c : win_rd_err_c;
        win_resp_data_q <= win_rd_c;
        if (win_wr && !win_wr_err_c) begin
          if (in_wbuf) begin
            if (win_req_wstrb[0]) wbuf[(wbyte + 10'd0) & WBUF_MSK] <= win_req_wdata[7:0];
            if (win_req_wstrb[1]) wbuf[(wbyte + 10'd1) & WBUF_MSK] <= win_req_wdata[15:8];
            if (win_req_wstrb[2]) wbuf[(wbyte + 10'd2) & WBUF_MSK] <= win_req_wdata[23:16];
            if (win_req_wstrb[3]) wbuf[(wbyte + 10'd3) & WBUF_MSK] <= win_req_wdata[31:24];
          end else if (in_xbuf) begin
            if (win_req_wstrb[0]) xbuf[(wbyte + 10'd0) & XBUF_MSK] <= win_req_wdata[7:0];
            if (win_req_wstrb[1]) xbuf[(wbyte + 10'd1) & XBUF_MSK] <= win_req_wdata[15:8];
            if (win_req_wstrb[2]) xbuf[(wbyte + 10'd2) & XBUF_MSK] <= win_req_wdata[23:16];
            if (win_req_wstrb[3]) xbuf[(wbyte + 10'd3) & XBUF_MSK] <= win_req_wdata[31:24];
          end else if (in_y32 && y32_n_ok && !busy_o) begin
            y_acc[y32_n] <= win_req_wdata;
          end else if (is_irqen) begin
            ame_irqen_q <= win_req_wdata;
          end
        end
      end
    end
  end

endmodule
