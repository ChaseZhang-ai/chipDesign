`ifndef _AMECPU_PKG_SV
 `include "amecpu_pkg.sv"
`endif

module cpu_csr (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic [11:0] raddr_i,
  output logic [31:0] rdata_o,
  output logic        rlegal_o,
  output logic        wro_o,     // 写口地址是否只读(核心据此判非法)
  input  logic        we_i,
  input  logic [11:0] waddr_i,
  input  logic [31:0] wdata_i,
  input  logic [2:0]  wf3_i,
  input  logic        retire_i,
  input  logic [1:0]  retire_pend_i,  // EX 级读 minstret 时在 MEM/WB 的未退休指令数
  input  logic        ev_ill_i,
  input  logic        ev_ame_err_i,
  input  logic        ev_bus_err_i,
  input  logic        ev_ecall_i,
  input  logic        ev_ebreak_i,
  input  logic        irq_i,
  input  logic        trap_i,
  input  logic [31:0] trap_pc_i,
  input  logic        mret_i,
  output logic        mie_o,
  output logic [31:0] mtvec_base_o
);

  logic [63:0] mcycle_q;
  logic [63:0] minstret_q;
  logic        mie_q, mpie_q;
  logic [31:0] mtvec_q, mepc_q, mcause_q, mscratch_q, flags_q;

  function automatic logic addr_legal(input logic [11:0] a);
    case (a)
      amecpu_pkg::CSR_MSTATUS,  amecpu_pkg::CSR_MTVEC,
      amecpu_pkg::CSR_MSCRATCH, amecpu_pkg::CSR_MEPC,
      amecpu_pkg::CSR_MCAUSE,   amecpu_pkg::CSR_FLAGS,
      amecpu_pkg::CSR_MCYCLE,   amecpu_pkg::CSR_MCYCLEH,
      amecpu_pkg::CSR_MINSTRET, amecpu_pkg::CSR_MINSTRETH,
      amecpu_pkg::CSR_CYCLE,    amecpu_pkg::CSR_CYCLEH,
      amecpu_pkg::CSR_INSTRET,  amecpu_pkg::CSR_INSTRETH: addr_legal = 1'b1;
      default: addr_legal = 1'b0;
    endcase
  endfunction

  function automatic logic addr_ro(input logic [11:0] a);
    case (a)
      amecpu_pkg::CSR_CYCLE,    amecpu_pkg::CSR_CYCLEH,
      amecpu_pkg::CSR_INSTRET,  amecpu_pkg::CSR_INSTRETH: addr_ro = 1'b1;
      default: addr_ro = 1'b0;
    endcase
  endfunction

  assign rlegal_o = addr_legal(raddr_i);
  assign wro_o    = addr_ro(waddr_i);

  always_comb begin
    case (raddr_i)
      amecpu_pkg::CSR_MSTATUS:   rdata_o = {24'h0, mpie_q, 3'b0, mie_q, 3'b0};
      amecpu_pkg::CSR_MTVEC:     rdata_o = mtvec_q;
      amecpu_pkg::CSR_MSCRATCH:  rdata_o = mscratch_q;
      amecpu_pkg::CSR_MEPC:      rdata_o = mepc_q;
      amecpu_pkg::CSR_MCAUSE:    rdata_o = mcause_q;
      amecpu_pkg::CSR_FLAGS:     rdata_o = flags_q;
      amecpu_pkg::CSR_MCYCLE:    rdata_o = mcycle_q[31:0];
      amecpu_pkg::CSR_MCYCLEH:   rdata_o = mcycle_q[63:32];
      amecpu_pkg::CSR_MINSTRET:  rdata_o = minstret_q[31:0] + {30'h0, retire_pend_i};
      amecpu_pkg::CSR_MINSTRETH: rdata_o = minstret_q[63:32];
      amecpu_pkg::CSR_CYCLE:     rdata_o = mcycle_q[31:0];
      amecpu_pkg::CSR_CYCLEH:    rdata_o = mcycle_q[63:32];
      amecpu_pkg::CSR_INSTRET:   rdata_o = minstret_q[31:0] + {30'h0, retire_pend_i};
      amecpu_pkg::CSR_INSTRETH:  rdata_o = minstret_q[63:32];
      default:                   rdata_o = 32'h0;
    endcase
  end

  wire csr_write_op = (wf3_i == 3'd1) || (wf3_i == 3'd5) ||   // CSRRW/CSRRWI
                      (wf3_i == 3'd2) || (wf3_i == 3'd6) ||   // CSRRS/CSRRSI
                      (wf3_i == 3'd3) || (wf3_i == 3'd7);     // CSRRC/CSRRCI
  wire [31:0] w_old = rdata_o; // 写口与读口同地址(EX 使用;minstret 系 = 补偿后
  wire [31:0] w_new = (wf3_i == 3'd1 || wf3_i == 3'd5) ? wdata_i
                    : (wf3_i == 3'd2 || wf3_i == 3'd6) ? (w_old | wdata_i)
                    : (w_old & ~wdata_i);

  wire [5:0] ev_bits = {1'b0, ev_ebreak_i, ev_ecall_i, ev_bus_err_i, ev_ame_err_i, ev_ill_i};

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      mcycle_q   <= 64'h0;
      minstret_q <= 64'h0;
      mie_q      <= 1'b0;
      mpie_q     <= 1'b0;
      mtvec_q    <= 32'h0000_0100;          // 契约复位值(ARCH_SPEC §2)
      mepc_q     <= 32'h0;
      mcause_q   <= 32'h0;
      mscratch_q <= 32'h0;
      flags_q    <= 32'h0;
    end else begin
      mcycle_q   <= mcycle_q + 64'd1;
      if (retire_i) minstret_q <= minstret_q + 64'd1;

      if (we_i && csr_write_op) begin
        case (waddr_i)
          amecpu_pkg::CSR_MSTATUS: begin
            mie_q  <= w_new[3];
            mpie_q <= w_new[7];
          end
          amecpu_pkg::CSR_MTVEC:    mtvec_q    <= w_new;
          amecpu_pkg::CSR_MSCRATCH: mscratch_q <= w_new;
          amecpu_pkg::CSR_MEPC:     mepc_q     <= w_new;
          amecpu_pkg::CSR_MCAUSE:   mcause_q   <= w_new;
          amecpu_pkg::CSR_MCYCLE:   mcycle_q[31:0]   <= w_new;
          amecpu_pkg::CSR_MCYCLEH:  mcycle_q[63:32]  <= w_new;
          amecpu_pkg::CSR_MINSTRET, amecpu_pkg::CSR_INSTRET:
            if (w_new != rdata_o)
              minstret_q[31:0] <= w_new - {30'h0, retire_pend_i};
          amecpu_pkg::CSR_MINSTRETH, amecpu_pkg::CSR_INSTRETH:
            minstret_q[63:32] <= w_new;   // 高字无在途补偿,直写
          default: ; // RO 别名:写忽略(核心已按非法处理,不会到这)
        endcase
      end

      if (we_i && csr_write_op && (waddr_i == amecpu_pkg::CSR_FLAGS)) begin
        flags_q <= w_new | {26'h0, ev_bits};
      end else begin
        flags_q <= flags_q | {26'h0, ev_bits};
      end

      if (trap_i) begin
        mepc_q  <= trap_pc_i;
        mcause_q<= amecpu_pkg::MCAUSE_MEXT_IRQ;
        mpie_q  <= mie_q;
        mie_q   <= 1'b0;
      end else if (mret_i) begin
        mie_q  <= mpie_q;
        mpie_q <= 1'b1;
      end
    end
  end

  assign mie_o        = mie_q;
  assign mtvec_base_o = {mtvec_q[31:2], 2'b00};

endmodule
