`ifndef _AMECPU_PKG_SV
 `include "amecpu_pkg.sv"
`endif

module cpu_alu (
  input  logic [3:0]  op_i,
  input  logic [31:0] a_i,
  input  logic [31:0] b_i,
  output logic [31:0] y_o
);

  always_comb begin
    case (op_i)
      amecpu_pkg::ALU_ADD:   y_o = a_i + b_i;
      amecpu_pkg::ALU_SUB:   y_o = a_i - b_i;
      amecpu_pkg::ALU_AND:   y_o = a_i & b_i;
      amecpu_pkg::ALU_OR:    y_o = a_i | b_i;
      amecpu_pkg::ALU_XOR:   y_o = a_i ^ b_i;
      amecpu_pkg::ALU_SLL:   y_o = a_i << b_i[4:0];
      amecpu_pkg::ALU_SRL:   y_o = a_i >> b_i[4:0];
      amecpu_pkg::ALU_SRA:   y_o = $signed(a_i) >>> b_i[4:0];
      amecpu_pkg::ALU_SLT:   y_o = {31'h0, $signed(a_i) < $signed(b_i)};
      amecpu_pkg::ALU_SLTU:  y_o = {31'h0, a_i < b_i};
      amecpu_pkg::ALU_COPYB: y_o = b_i;
      default:               y_o = 32'h0;
    endcase
  end

endmodule
