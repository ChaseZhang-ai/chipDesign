
module sky130_sram_1rw1r_128x256_8(
    clk0,csb0,web0,wmask0,addr0,din0,dout0,
    clk1,csb1,addr1,dout1
  );

  parameter NUM_WMASKS = 16 ;
  parameter DATA_WIDTH = 128 ;
  parameter ADDR_WIDTH = 8 ;
  parameter RAM_DEPTH = 1 << ADDR_WIDTH;
  parameter DELAY = 3 ;

  input  clk0; // clock
  input   csb0; // active low chip select
  input  web0; // active low write control
  input [NUM_WMASKS-1:0]   wmask0; // write mask
  input [ADDR_WIDTH-1:0]  addr0;
  input [DATA_WIDTH-1:0]  din0;
  output [DATA_WIDTH-1:0] dout0;
  input  clk1; // clock
  input   csb1; // active low chip select
  input [ADDR_WIDTH-1:0]  addr1;
  output [DATA_WIDTH-1:0] dout1;

  reg  csb0_reg;
  reg  web0_reg;
  reg [NUM_WMASKS-1:0]   wmask0_reg;
  reg [ADDR_WIDTH-1:0]  addr0_reg;
  reg [DATA_WIDTH-1:0]  din0_reg;
  reg [DATA_WIDTH-1:0]  dout0;

  always @(posedge clk0)
  begin
    csb0_reg = csb0;
    web0_reg = web0;
    wmask0_reg = wmask0;
    addr0_reg = addr0;
    din0_reg = din0;
    dout0 = 128'bx;
    if ( !csb0_reg && !web0_reg )
      if (pf2 != 0)
        $fdisplay(pf2, "%0t %m P0W a=%0d hi=%h lo=%h wm=%b hix=%b lox=%b",
                  $time, addr0_reg, din0_reg[31:16], din0_reg[15:0], wmask0_reg,
                  (^din0_reg[31:16])===1'bx, (^din0_reg[15:0])===1'bx);
  end

  reg  csb1_reg;
  reg [ADDR_WIDTH-1:0]  addr1_reg;
  reg [DATA_WIDTH-1:0]  dout1;

  always @(posedge clk1)
  begin
    csb1_reg = csb1;
    addr1_reg = addr1;
    dout1 = 128'bx;
  end

reg [DATA_WIDTH-1:0]    mem [0:RAM_DEPTH-1];

  always @ (negedge clk0)
  begin : MEM_WRITE0
    if ( !csb0_reg && !web0_reg ) begin
        if (wmask0_reg[0])
                mem[addr0_reg][7:0] = din0_reg[7:0];
        if (wmask0_reg[1])
                mem[addr0_reg][15:8] = din0_reg[15:8];
        if (wmask0_reg[2])
                mem[addr0_reg][23:16] = din0_reg[23:16];
        if (wmask0_reg[3])
                mem[addr0_reg][31:24] = din0_reg[31:24];
        if (wmask0_reg[4])
                mem[addr0_reg][39:32] = din0_reg[39:32];
        if (wmask0_reg[5])
                mem[addr0_reg][47:40] = din0_reg[47:40];
        if (wmask0_reg[6])
                mem[addr0_reg][55:48] = din0_reg[55:48];
        if (wmask0_reg[7])
                mem[addr0_reg][63:56] = din0_reg[63:56];
        if (wmask0_reg[8])
                mem[addr0_reg][71:64] = din0_reg[71:64];
        if (wmask0_reg[9])
                mem[addr0_reg][79:72] = din0_reg[79:72];
        if (wmask0_reg[10])
                mem[addr0_reg][87:80] = din0_reg[87:80];
        if (wmask0_reg[11])
                mem[addr0_reg][95:88] = din0_reg[95:88];
        if (wmask0_reg[12])
                mem[addr0_reg][103:96] = din0_reg[103:96];
        if (wmask0_reg[13])
                mem[addr0_reg][111:104] = din0_reg[111:104];
        if (wmask0_reg[14])
                mem[addr0_reg][119:112] = din0_reg[119:112];
        if (wmask0_reg[15])
                mem[addr0_reg][127:120] = din0_reg[127:120];
    end
  end

  always @ (negedge clk0)
  begin : MEM_READ0
    if (!csb0_reg && web0_reg)
       dout0 <= #(DELAY) mem[addr0_reg];
  end

  always @ (negedge clk1)
  begin : MEM_READ1
    if (!csb1_reg)
       dout1 <= #(DELAY) mem[addr1_reg];
  end

integer pf2;
initial begin
  pf2 = $fopen("p4b3_sram_probe.txt","w");
  if (pf2 == 0) pf2 = 1; // 打不开就退化为 stdout 句柄占位(不致命)
end

endmodule
