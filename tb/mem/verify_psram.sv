module verify_psram #(
  parameter int unsigned A_BITS = 23
) (
  input  logic              clk_i,
  input  logic [A_BITS-1:0] a_i,     // 字节地址
  input  logic [15:0]       di_i,    // 芯片 → 器件
  output logic [15:0]       do_o,    // 器件 → 芯片(地址拍后一拍有效)
  input  logic              ce_ni,
  input  logic              oe_ni,
  input  logic              we_ni
);
  localparam int unsigned NW = 1 << (A_BITS - 1); // 半字数(8 MB → 4M)
  logic [15:0] mem [0:NW-1];
  logic [15:0] do_q;

  always_ff @(posedge clk_i) begin
    if (!ce_ni) begin
      if (!we_ni) mem[a_i[A_BITS-1:1]] <= di_i;
      if (!oe_ni) do_q <= mem[a_i[A_BITS-1:1]];
    end
  end
  assign do_o = do_q;

  task automatic poke_hw(input longint unsigned idx, input logic [15:0] v);
    mem[idx] = v;
  endtask
  function automatic logic [15:0] peek_hw(input longint unsigned idx);
    peek_hw = mem[idx];
  endfunction

  task automatic poke_word(input longint unsigned hw_idx, input logic [31:0] v);
    mem[hw_idx]     = v[15:0];
    mem[hw_idx + 1] = v[31:16];
  endtask
  function automatic logic [31:0] peek_word(input longint unsigned hw_idx);
    peek_word = {mem[hw_idx + 1], mem[hw_idx]};
  endfunction

  task automatic poke_addr(input logic [31:0] byte_addr, input logic [31:0] v);
    poke_word(longint'(byte_addr & ((1 << A_BITS) - 1)) >> 1, v);
  endtask
  function automatic logic [31:0] peek_addr(input logic [31:0] byte_addr);
    peek_addr = peek_word(longint'(byte_addr & ((1 << A_BITS) - 1)) >> 1);
  endfunction

  task automatic dump_hw_range(input string fname,
                               input longint unsigned base_hw,
                               input int unsigned n);
    integer fd;
    begin
      fd = $fopen(fname, "w");
      for (int unsigned i = 0; i < n; i++)
        $fwrite(fd, "%04x\n", mem[base_hw + i]);
      $fclose(fd);
    end
  endtask

endmodule
