`ifndef _SOC_PKG_SV
 `include "soc_pkg.sv"
`endif

module soc_rr_mux4 #(
  parameter logic [3:0] SEL_ID = 4'd0
) (
  input  logic                  clk,
  input  logic                  rst_n,

  input  soc_pkg::soc_req_t     m0_req,
  output soc_pkg::soc_resp_t    m0_resp,
  input  soc_pkg::soc_req_t     m1_req,
  output soc_pkg::soc_resp_t    m1_resp,
  input  soc_pkg::soc_req_t     m2_req,
  output soc_pkg::soc_resp_t    m2_resp,
  input  soc_pkg::soc_req_t     m3_req,
  output soc_pkg::soc_resp_t    m3_resp,

  output soc_pkg::soc_req_t     s_req,
  input  soc_pkg::soc_resp_t    s_resp
);

  typedef enum logic [1:0] { IDLE, BUSY, RELEASE } state_e;
  state_e state;

  logic [1:0] rr_ptr;
  logic [1:0] grant_q;
  logic [1:0] grant_c;
  logic       grant_vld;

  wire m0_hit = m0_req.valid && (soc_pkg::soc_slave_decode(m0_req.addr) == SEL_ID);
  wire m1_hit = m1_req.valid && (soc_pkg::soc_slave_decode(m1_req.addr) == SEL_ID);
  wire m2_hit = m2_req.valid && (soc_pkg::soc_slave_decode(m2_req.addr) == SEL_ID);
  wire m3_hit = m3_req.valid && (soc_pkg::soc_slave_decode(m3_req.addr) == SEL_ID);

  wire [3:0] hits = {m3_hit, m2_hit, m1_hit, m0_hit};

  always_comb begin
    grant_c   = 2'd0;
    grant_vld = 1'b0;
    if (hits[rr_ptr])             begin grant_c = rr_ptr;        grant_vld = 1'b1; end
    else if (hits[rr_ptr ^ 2'd1]) begin grant_c = rr_ptr ^ 2'd1;  grant_vld = 1'b1; end
    else if (hits[rr_ptr ^ 2'd2]) begin grant_c = rr_ptr ^ 2'd2;  grant_vld = 1'b1; end
    else if (hits[rr_ptr ^ 2'd3]) begin grant_c = rr_ptr ^ 2'd3;  grant_vld = 1'b1; end
  end

  soc_pkg::soc_req_t grant_req;
  always_comb begin
    case (state)
      IDLE:    grant_req = (grant_c   == 2'd0) ? m0_req :
                           (grant_c   == 2'd1) ? m1_req :
                           (grant_c   == 2'd2) ? m2_req : m3_req;
      default: grant_req = (grant_q  == 2'd0) ? m0_req :
                           (grant_q  == 2'd1) ? m1_req :
                           (grant_q  == 2'd2) ? m2_req : m3_req;
    endcase
  end

  reg grant_still_valid;
  always @* begin
    case (grant_q)
      2'd0:    grant_still_valid = m0_req.valid;
      2'd1:    grant_still_valid = m1_req.valid;
      2'd2:    grant_still_valid = m2_req.valid;
      default: grant_still_valid = m3_req.valid;
    endcase
  end

  always_comb begin
    s_req.valid  = 1'b0;
    s_req.write  = 1'b0;
    s_req.addr   = 32'd0;
    s_req.wdata  = 32'd0;
    s_req.wstrb  = 4'd0;
    if ((state == IDLE && grant_vld) || state == BUSY) begin
      s_req = grant_req;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state  <= IDLE;
      grant_q <= 2'd0;
      rr_ptr <= 2'd0;
    end else begin
      case (state)
        IDLE: begin
          if (grant_vld) begin
            grant_q <= grant_c;
            state   <= BUSY;
          end
        end
        BUSY: begin
          if (s_resp.valid) begin
            rr_ptr <= grant_q + 2'd1;
            state  <= RELEASE;
          end else if (!grant_still_valid) begin
            rr_ptr <= grant_q + 2'd1;
            state  <= RELEASE;
          end
        end
        RELEASE: begin
          if (!grant_still_valid) state <= IDLE;
        end
        default: state <= IDLE;
      endcase
    end
  end

  soc_pkg::soc_resp_t resp_gnt;
  always_comb begin
    resp_gnt.valid = 1'b0;
    resp_gnt.rdata = 32'd0;
    resp_gnt.resp  = 2'd0;
    if (state == BUSY) resp_gnt = s_resp;
  end

  always_comb begin
    m0_resp.valid = 1'b0; m0_resp.rdata = 32'd0; m0_resp.resp = 2'd0;
    m1_resp.valid = 1'b0; m1_resp.rdata = 32'd0; m1_resp.resp = 2'd0;
    m2_resp.valid = 1'b0; m2_resp.rdata = 32'd0; m2_resp.resp = 2'd0;
    m3_resp.valid = 1'b0; m3_resp.rdata = 32'd0; m3_resp.resp = 2'd0;
    if (state == BUSY) begin
      case (grant_q)
        2'd0: m0_resp = resp_gnt;
        2'd1: m1_resp = resp_gnt;
        2'd2: m2_resp = resp_gnt;
        2'd3: m3_resp = resp_gnt;
      endcase
    end
  end

endmodule
