
`ifndef _AMECHIP_PKG_SV
 `include "amechip_pkg.sv"
`endif
`ifndef _SOC_PKG_SV
 `include "soc_pkg.sv"
`endif

module vrfb_kv_model (
  input logic clk,
  input logic rst_n,

  input  soc_pkg::soc_req_t  bus_req,
  output soc_pkg::soc_resp_t bus_resp,

  output soc_pkg::soc_req_t  m_req,
  input  soc_pkg::soc_resp_t m_resp,

  input  logic dump_i,
  output logic evt_done_o,
  output logic evt_err_o,
  output logic busy_o
);

  localparam int NLAYER = 2, NTYPE = 2, NHEAD = 4, NCTX = 256, NDHEAD = 64;
  localparam int KVB = NLAYER * NTYPE * NHEAD * NCTX * NDHEAD;  // 262144

  logic [7:0] kv [0:KVB-1];

  function automatic int kvidx(input int l, input int t, input int h, input int p);
    kvidx = ((((l * NTYPE + t) * NHEAD + h) * NCTX + p) * NDHEAD);
  endfunction

  logic [31:0] ctrl_q, layer_q, head_q, pos_q, count_q, src_q, dst_q, pitch_q, slice_q;
  logic        busy_q, done_q, err_q;
  logic [3:0]  errcode_q;
  assign busy_o = busy_q;

  localparam logic [1:0] B_IDLE = 2'd0, B_REQ = 2'd1, B_RSP = 2'd2, B_GAP = 2'd3;
  logic [1:0]  bst_q;
  logic        bwr_q;
  logic [31:0] baddr_q, bwdat_q;
  logic [3:0]  bstrb_q;

  assign m_req.valid = (bst_q == B_REQ);
  assign m_req.write = bwr_q;
  assign m_req.addr  = baddr_q;
  assign m_req.wdata = bwdat_q;
  assign m_req.wstrb = bstrb_q;

  localparam logic [1:0] S_IDLE = 2'd0, S_OP = 2'd1, S_WAIT = 2'd2;
  logic [1:0]  st_q;
  logic [2:0]  mode_q;
  logic        trans_q;
  logic [31:0] dd_q, dl_q, pch_q;
  logic [31:0] it_q;

  wire [4:0] off = bus_req.addr[4:2];

  logic        csr_v_q;
  logic [31:0] csr_d_q;
  logic [1:0]  csr_r_q;

  logic [31:0] cur_rowi, cur_coli, cur_sba, cur_dba;
  always_comb begin
    if (dl_q == 0) begin
      cur_rowi = 0;
      cur_coli = 0;
    end else begin
      cur_rowi = it_q / dl_q;
      cur_coli = it_q % dl_q;
    end
    if (mode_q >= 3'd3 && mode_q <= 3'd4)
      cur_sba = kvidx(int'(layer_q), int'(mode_q) - 3, int'(head_q),
                      int'(pos_q) + int'(cur_rowi)) + int'(dd_q) + int'(cur_coli);
    else
      cur_sba = 0;
    cur_dba  = trans_q ? (dst_q + cur_coli * 16 + cur_rowi)
                       : (dst_q + cur_rowi * pch_q + cur_coli);
  end

  int i, b, fd, k, l, t, h, p, j;
  int va, vb;   // 内部写入地址(Verilator:NBA 下标须为简单变量)
  logic [31:0] tmpw [0:KVB/4-1];
  reg [1023:0] FNAME_KV, FNAME_KVD;
  logic        dump_d;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) dump_d <= 1'b0;
    else        dump_d <= dump_i;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ctrl_q <= 0; layer_q <= 0; head_q <= 0; pos_q <= 0; count_q <= 0;
      src_q <= 0; dst_q <= 0; pitch_q <= 0; slice_q <= 0;
      busy_q <= 0; done_q <= 0; err_q <= 0; errcode_q <= 0;
      st_q <= S_IDLE; mode_q <= 0; trans_q <= 0;
      dd_q <= 0; dl_q <= 0; pch_q <= 0; it_q <= 0;
      bst_q <= B_IDLE; bwr_q <= 0; baddr_q <= 0; bwdat_q <= 0; bstrb_q <= 0;
      csr_v_q <= 0; csr_d_q <= 0; csr_r_q <= 2'b00;
    end else begin
      evt_done_o <= 1'b0;
      evt_err_o  <= 1'b0;
      csr_v_q <= bus_req.valid && !csr_v_q;
      csr_d_q <= 32'd0;
      csr_r_q <= amechip_pkg::AXI_OKAY;

      if (bus_req.valid && !csr_v_q) begin
        if (bus_req.write) begin
          if (bus_req.wdata[9] && busy_q) begin
            busy_q    <= 1'b0;
            err_q     <= 1'b1;
            errcode_q <= 4'd3;
            st_q      <= S_IDLE;
            bst_q     <= B_GAP;
            evt_err_o <= ctrl_q[3];
          end else if (!busy_q) begin
            case (off)
              5'd0: ctrl_q  <= bus_req.wdata;
              5'd1: layer_q <= bus_req.wdata;
              5'd2: head_q  <= bus_req.wdata;
              5'd3: pos_q   <= bus_req.wdata;
              5'd4: count_q <= bus_req.wdata;
              5'd5: src_q   <= bus_req.wdata;
              5'd6: dst_q   <= bus_req.wdata;
              5'd7: pitch_q <= bus_req.wdata;
              5'd9: slice_q <= bus_req.wdata;
              default: ;
            endcase
            if (off == 5'd8) begin
              if (bus_req.wdata[1]) done_q <= 1'b0;   // W1C
              if (bus_req.wdata[2]) err_q  <= 1'b0;
            end
            if (off == 5'd0 && bus_req.wdata[8]) begin
              mode_q  <= bus_req.wdata[2:0];
              trans_q <= bus_req.wdata[4];
              it_q    <= 0;
              if (bus_req.wdata[2:0] <= 3'd2) begin
                if (pos_q >= NCTX) begin
                  err_q <= 1'b1; errcode_q <= 4'd1; evt_err_o <= bus_req.wdata[3];
                end else begin
                  busy_q <= 1'b1; done_q <= 1'b0; err_q <= 1'b0; errcode_q <= 4'd0;
                  st_q   <= S_OP;
                end
              end else if (bus_req.wdata[2:0] == 3'd5) begin
                if ((pos_q + count_q > NCTX) || (count_q == 0)) begin
                  err_q <= 1'b1; errcode_q <= 4'd1; evt_err_o <= bus_req.wdata[3];
                end else begin
                  busy_q <= 1'b1; done_q <= 1'b0; err_q <= 1'b0; errcode_q <= 4'd0;
                  st_q   <= S_OP;
                end
              end else begin
                if ((slice_q == 0) || (slice_q[9:5] == 0)) begin
                  dd_q <= 0;
                  dl_q <= NDHEAD;
                  pch_q <= (pitch_q == 0) ? NDHEAD : pitch_q;
                end else begin
                  dd_q <= {27'd0, slice_q[4:0]};
                  dl_q <= {27'd0, slice_q[9:5]};
                  pch_q <= (pitch_q == 0) ? {27'd0, slice_q[9:5]} : pitch_q;
                end
                if ((pos_q + count_q > NCTX) || (count_q == 0) ||
                    ((slice_q != 0) && (slice_q[9:5] != 0) &&
                     ({27'd0, slice_q[4:0]} + {27'd0, slice_q[9:5]} > NDHEAD)) ||
                    (bus_req.wdata[4] && count_q > 16)) begin
                  err_q <= 1'b1; errcode_q <= 4'd1; evt_err_o <= bus_req.wdata[3];
                end else begin
                  busy_q <= 1'b1; done_q <= 1'b0; err_q <= 1'b0; errcode_q <= 4'd0;
                  st_q   <= S_OP;
                end
              end
            end
          end
        end else begin
          case (off)
            5'd0: csr_d_q <= ctrl_q;
            5'd1: csr_d_q <= layer_q;
            5'd2: csr_d_q <= head_q;
            5'd3: csr_d_q <= pos_q;
            5'd4: csr_d_q <= count_q;
            5'd5: csr_d_q <= src_q;
            5'd6: csr_d_q <= dst_q;
            5'd7: csr_d_q <= pitch_q;
            5'd8: csr_d_q <= {24'd0, errcode_q, 1'b0, err_q, done_q, busy_q};
            5'd9: csr_d_q <= slice_q;
            default: csr_d_q <= 32'd0;
          endcase
        end
      end

      if (bst_q == B_REQ && m_resp.valid) begin
        if (m_resp.resp != amechip_pkg::AXI_OKAY) begin
          err_q     <= 1'b1;
          errcode_q <= 4'd2;
          busy_q    <= 1'b0;
          st_q      <= S_IDLE;
          bst_q     <= B_GAP;
          evt_err_o <= ctrl_q[3];
        end else if (mode_q <= 3'd2) begin
          va = kvidx(int'(layer_q), int'((it_q >> 4) & 1), int'((it_q >> 5) & 3), int'(pos_q))
             + int'(it_q & 15) * 4;
          vb = kvidx(int'(layer_q), int'(mode_q), int'(head_q), int'(pos_q))
             + int'(it_q) * 4;
          if (mode_q == 3'd2) begin
            kv[va + 0] <= m_resp.rdata[7:0];
            kv[va + 1] <= m_resp.rdata[15:8];
            kv[va + 2] <= m_resp.rdata[23:16];
            kv[va + 3] <= m_resp.rdata[31:24];
          end else begin
            kv[vb + 0] <= m_resp.rdata[7:0];
            kv[vb + 1] <= m_resp.rdata[15:8];
            kv[vb + 2] <= m_resp.rdata[23:16];
            kv[vb + 3] <= m_resp.rdata[31:24];
          end
          st_q <= S_WAIT;
        end else begin
          st_q <= S_WAIT;
        end
        bst_q <= B_GAP;
      end else if (bst_q == B_GAP) begin
        bst_q <= B_IDLE;
      end

      if (st_q == S_OP && bst_q == B_IDLE && !(bus_req.valid && !csr_v_q && bus_req.write && busy_q == 1'b0)) begin
        if (mode_q <= 3'd2) begin
          if ((mode_q == 3'd2) ? (it_q < 128) : (it_q < 16)) begin
            bwr_q   <= 1'b0;
            baddr_q <= src_q + (it_q << 2);
            bwdat_q <= 32'd0;
            bstrb_q <= 4'd0;
            bst_q   <= B_REQ;
          end else begin
            busy_q <= 1'b0; done_q <= 1'b1; st_q <= S_IDLE;
            evt_done_o <= ctrl_q[3];
          end
        end else if (mode_q == 3'd5) begin
          if (it_q < (count_q << 7)) begin
            va = kvidx(int'(layer_q), (it_q < (count_q << 6)) ? 0 : 1, int'(head_q),
                       int'(pos_q) + int'((it_q >> 6) % count_q)) + int'(it_q & 63);
            kv[va] <= 8'd0;
            it_q <= it_q + 1;
          end else begin
            busy_q <= 1'b0; done_q <= 1'b1; st_q <= S_IDLE;
            evt_done_o <= ctrl_q[3];
          end
        end else begin
          if (it_q < (count_q * dl_q)) begin
            bwr_q   <= 1'b1;
            baddr_q <= cur_dba;
            bwdat_q <= {4{kv[cur_sba]}};
            bstrb_q <= 4'b0001 << cur_dba[1:0];
            bst_q   <= B_REQ;
          end else begin
            busy_q <= 1'b0; done_q <= 1'b1; st_q <= S_IDLE;
            evt_done_o <= ctrl_q[3];
          end
        end
      end else if (st_q == S_WAIT) begin
        it_q <= it_q + 1;
        st_q <= S_OP;
      end
    end
  end

  assign bus_resp.valid = csr_v_q;
  assign bus_resp.rdata = csr_d_q;
  assign bus_resp.resp  = csr_r_q;

  initial begin
    for (i = 0; i < KVB; i++) kv[i] = 8'd0;
    if ($value$plusargs("KV_HEX=%s", FNAME_KV)) begin
      for (i = 0; i < KVB/4; i++) tmpw[i] = 32'd0;
      $readmemh(FNAME_KV, tmpw);
      for (i = 0; i < KVB/4; i++)
        for (b = 0; b < 4; b++) kv[i*4 + b] = tmpw[i][8*b +: 8];
    end
    if (!$value$plusargs("KV_DUMP=%s", FNAME_KVD)) FNAME_KVD = "";
  end

  always @(posedge clk) begin
    if (dump_i && !dump_d && (FNAME_KVD != "")) begin
      fd = $fopen(FNAME_KVD, "w");
      for (l = 0; l < NLAYER; l = l + 1)
        for (t = 0; t < NTYPE; t = t + 1)
          for (h = 0; h < NHEAD; h = h + 1)
            for (p = 0; p < 16; p = p + 1)
              for (k = 0; k < 16; k = k + 1) begin
                j = kvidx(l, t, h, p) + k*4;
                $fwrite(fd, "%02X%02X%02X%02X\n",
                        kv[j+3], kv[j+2], kv[j+1], kv[j]);
              end
      $fclose(fd);
      $display("[vrfb_kv] dumped rows0..15");
    end
  end

endmodule
