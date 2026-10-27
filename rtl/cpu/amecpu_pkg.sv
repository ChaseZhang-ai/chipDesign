`ifndef _AMECPU_PKG_SV
 `define _AMECPU_PKG_SV

package amecpu_pkg;

  localparam int unsigned XLEN = 32;

  localparam logic [6:0] OP_LUI    = 7'b0110111;
  localparam logic [6:0] OP_AUIPC  = 7'b0010111;
  localparam logic [6:0] OP_JAL    = 7'b1101111;
  localparam logic [6:0] OP_JALR   = 7'b1100111;
  localparam logic [6:0] OP_BRANCH = 7'b1100011;
  localparam logic [6:0] OP_LOAD   = 7'b0000011;
  localparam logic [6:0] OP_STORE  = 7'b0100011;
  localparam logic [6:0] OP_ALUI   = 7'b0010011;
  localparam logic [6:0] OP_ALUR   = 7'b0110011;
  localparam logic [6:0] OP_FENCE  = 7'b0001111;
  localparam logic [6:0] OP_SYSTEM = 7'b1110011;

  localparam logic [3:0] ALU_ADD   = 4'd0;
  localparam logic [3:0] ALU_SUB   = 4'd1;
  localparam logic [3:0] ALU_AND   = 4'd2;
  localparam logic [3:0] ALU_OR    = 4'd3;
  localparam logic [3:0] ALU_XOR   = 4'd4;
  localparam logic [3:0] ALU_SLL   = 4'd5;
  localparam logic [3:0] ALU_SRL   = 4'd6;
  localparam logic [3:0] ALU_SRA   = 4'd7;
  localparam logic [3:0] ALU_SLT   = 4'd8;
  localparam logic [3:0] ALU_SLTU  = 4'd9;
  localparam logic [3:0] ALU_COPYB = 4'd10; // LUI:结果 = imm

  localparam logic [2:0] LS_B  = 3'd0;
  localparam logic [2:0] LS_H  = 3'd1;
  localparam logic [2:0] LS_W  = 3'd2;
  localparam logic [2:0] LS_BU = 3'd4;
  localparam logic [2:0] LS_HU = 3'd5;

  localparam logic [11:0] CSR_MSTATUS   = 12'h300;
  localparam logic [11:0] CSR_MTVEC     = 12'h305;
  localparam logic [11:0] CSR_MSCRATCH  = 12'h340;
  localparam logic [11:0] CSR_MEPC      = 12'h341;
  localparam logic [11:0] CSR_MCAUSE    = 12'h342;
  localparam logic [11:0] CSR_FLAGS     = 12'h7C2;
  localparam logic [11:0] CSR_MCYCLE    = 12'hB00;
  localparam logic [11:0] CSR_MCYCLEH   = 12'hB80;
  localparam logic [11:0] CSR_MINSTRET  = 12'hB02;
  localparam logic [11:0] CSR_MINSTRETH = 12'hB82;
  localparam logic [11:0] CSR_CYCLE     = 12'hC00;
  localparam logic [11:0] CSR_CYCLEH    = 12'hC80;
  localparam logic [11:0] CSR_INSTRET   = 12'hC02;
  localparam logic [11:0] CSR_INSTRETH  = 12'hC82;

  localparam logic [31:0] MCAUSE_MEXT_IRQ = 32'h8000_0010;

  localparam logic [1:0] TRACE_FLAG_RD    = 2'b01; // rd 有效写回
  localparam logic [1:0] TRACE_FLAG_SKIPW = 2'b10; // wdata 依赖 mcycle,差分跳过

endpackage
`endif // _AMECPU_PKG_SV
