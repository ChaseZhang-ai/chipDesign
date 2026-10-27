
module stub_cpu (
  input  logic               clk,
  input  logic               rst_n,

  output soc_pkg::soc_req_t  bus_req,
  input  soc_pkg::soc_resp_t bus_resp,

  output logic               ame_req_valid,
  output logic [31:0]        ame_req_instr,
  output logic [31:0]        ame_req_rs1,
  output logic [31:0]        ame_req_rs2,
  input  logic               ame_req_ready,
  input  logic               ame_resp_valid,
  input  logic [31:0]        ame_resp_data,
  input  logic               ame_resp_err,

  input  logic               irq_i,
  output logic               cpu_wfi_o,
  output logic               buserr_evt_o
);

  typedef enum logic [2:0] {
    S_IF, S_EX, S_MEM, S_GAP, S_AME_REQ, S_AME_RESP, S_HALT
  } state_e;

  state_e      state;
  logic [31:0] pc;
  logic [31:0] instr_q;
  logic [31:0] regs [0:31];
  logic [31:0] retire_cnt;
  logic        wfi_q;
  logic [31:0] buserr_sticky;

  logic [31:0] pc_next_q;
  logic [31:0] mem_addr_q, mem_wdata_q;
  logic [3:0]  mem_wstrb_q;
  logic [4:0]  mem_rd_q;
  logic        is_store_q;
  logic [1:0]  mem_size_q;
  logic        mem_sign_q;
  logic [31:0] ame_rd_q;

  assign cpu_wfi_o = (state == S_HALT) && wfi_q;

  wire [6:0]  op  = instr_q[6:0];
  wire [4:0]  rd  = instr_q[11:7];
  wire [2:0]  f3  = instr_q[14:12];
  wire [4:0]  rs1 = instr_q[19:15];
  wire [4:0]  rs2 = instr_q[24:20];
  wire [6:0]  f7  = instr_q[31:25];

  wire [31:0] rs1v = (rs1 == 5'd0) ? 32'd0 : regs[rs1];
  wire [31:0] rs2v = (rs2 == 5'd0) ? 32'd0 : regs[rs2];

  wire [31:0] imm_i = {{20{instr_q[31]}}, instr_q[31:20]};
  wire [31:0] imm_s = {{20{instr_q[31]}}, instr_q[31:25], instr_q[11:7]};
  wire [31:0] imm_b = {{19{instr_q[31]}}, instr_q[31], instr_q[7],
                       instr_q[30:25], instr_q[11:8], 1'b0};
  wire [31:0] imm_u = {instr_q[31:12], 12'd0};
  wire [31:0] imm_j = {{11{instr_q[31]}}, instr_q[31], instr_q[19:12],
                       instr_q[20], instr_q[30:21], 1'b0};

  logic [31:0] alu_wb_c;
  logic        wb_en_c;
  logic [31:0] wb_val_c;
  logic        jump_c;
  logic [31:0] jump_target_c;
  logic        mem_acc_c;
  logic        ame_acc_c;
  logic        illegal_c;
  logic        is_store_c;
  logic        is_sys_c;       // wfi/ecall/ebreak
  logic [1:0]  mem_size_c;
  logic        mem_sign_c;
  logic [31:0] mem_addr_c;
  logic [31:0] mem_wdata_c;
  logic [3:0]  mem_wstrb_c;

  always @* begin
    wb_en_c = 1'b0; wb_val_c = 32'd0;
    jump_c = 1'b0; jump_target_c = 32'd0;
    mem_acc_c = 1'b0; ame_acc_c = 1'b0; illegal_c = 1'b0; is_store_c = 1'b0;
    is_sys_c = 1'b0;
    mem_size_c = 2'd2; mem_sign_c = 1'b0;
    mem_addr_c = (op == 7'b01000_11) ? (rs1v + imm_s) : (rs1v + imm_i);
    mem_wdata_c = 32'd0; mem_wstrb_c = 4'd0;

    case (op)
      7'b01101_11: begin // LUI
        wb_en_c = 1'b1; wb_val_c = imm_u;
      end
      7'b00101_11: begin // AUIPC
        wb_en_c = 1'b1; wb_val_c = pc + imm_u;
      end
      7'b11011_11: begin // JAL
        wb_en_c = 1'b1; wb_val_c = pc + 4;
        jump_c = 1'b1; jump_target_c = pc + imm_j;
      end
      7'b11001_11: begin // JALR
        wb_en_c = 1'b1; wb_val_c = pc + 4;
        jump_c = 1'b1; jump_target_c = (rs1v + imm_i) & 32'hFFFF_FFFE;
      end
      7'b11000_11: begin // BRANCH
        case (f3)
          3'd0: if (rs1v == rs2v)                   begin jump_c = 1'b1; end
          3'd1: if (rs1v != rs2v)                   begin jump_c = 1'b1; end
          3'd4: if ($signed(rs1v) <  $signed(rs2v)) begin jump_c = 1'b1; end
          3'd5: if ($signed(rs1v) >= $signed(rs2v)) begin jump_c = 1'b1; end
          3'd6: if (rs1v <  rs2v)                   begin jump_c = 1'b1; end
          3'd7: if (rs1v >= rs2v)                   begin jump_c = 1'b1; end
          default: illegal_c = 1'b1;
        endcase
        jump_target_c = pc + imm_b;
      end
      7'b00000_11: begin // LOAD
        mem_acc_c = 1'b1;
        wb_en_c   = 1'b1; wb_val_c = 32'd0;
        case (f3)
          3'd0: begin mem_size_c = 2'd0; mem_sign_c = 1'b1; end  // lb
          3'd1: begin mem_size_c = 2'd1; mem_sign_c = 1'b1; end  // lh
          3'd2: begin mem_size_c = 2'd2; mem_sign_c = 1'b0; end  // lw
          3'd4: begin mem_size_c = 2'd0; mem_sign_c = 1'b0; end  // lbu
          3'd5: begin mem_size_c = 2'd1; mem_sign_c = 1'b0; end  // lhu
          default: illegal_c = 1'b1;
        endcase
      end
      7'b01000_11: begin // STORE
        mem_acc_c  = 1'b1; is_store_c = 1'b1;
        case (f3)
          3'd0: begin
            mem_size_c = 2'd0;
            mem_wdata_c = {4{rs2v[7:0]}} << (8 * mem_addr_c[1:0]);
            case (mem_addr_c[1:0])
              2'd0: mem_wstrb_c = 4'b0001;
              2'd1: mem_wstrb_c = 4'b0010;
              2'd2: mem_wstrb_c = 4'b0100;
              2'd3: mem_wstrb_c = 4'b1000;
            endcase
          end
          3'd1: begin
            mem_size_c  = 2'd1;
            mem_wdata_c = {2{rs2v[15:0]}} << (8 * {mem_addr_c[1], 1'b0});
            mem_wstrb_c = mem_addr_c[1] ? 4'b1100 : 4'b0011;
          end
          3'd2: begin
            mem_size_c  = 2'd2;
            mem_wdata_c = rs2v;
            mem_wstrb_c = 4'b1111;
          end
          default: illegal_c = 1'b1;
        endcase
      end
      7'b00100_11: begin // OP-IMM
        wb_en_c = 1'b1;
        case (f3)
          3'd0: wb_val_c = rs1v + imm_i;
          3'd1: wb_val_c = rs1v << instr_q[24:20];
          3'd2: wb_val_c = {31'd0, $signed(rs1v) < $signed(imm_i)};
          3'd3: wb_val_c = {31'd0, rs1v < imm_i};
          3'd4: wb_val_c = rs1v ^ imm_i;
          3'd5: wb_val_c = instr_q[30] ? ($signed(rs1v) >>> instr_q[24:20])
                                       : (rs1v >> instr_q[24:20]);
          3'd6: wb_val_c = rs1v | imm_i;
          3'd7: wb_val_c = rs1v & imm_i;
        endcase
      end
      7'b01100_11: begin // OP(R)
        wb_en_c = 1'b1;
        if (f7 == 7'd1) begin
          case (f3)
            3'd0: wb_val_c = rs1v * rs2v;
            3'd1: wb_val_c = mult_hi($signed(rs1v), $signed(rs2v));
            3'd2: wb_val_c = mult_hi_u($signed(rs1v), rs2v);
            3'd3: wb_val_c = mult_hi_u(rs1v, rs2v);
            3'd4: wb_val_c = div_s(rs1v, rs2v);
            3'd5: wb_val_c = (rs2v == 32'd0) ? 32'hFFFF_FFFF : (rs1v / rs2v);
            3'd6: wb_val_c = rem_s(rs1v, rs2v);
            3'd7: wb_val_c = (rs2v == 32'd0) ? rs1v : (rs1v % rs2v);
          endcase
        end else begin
          case (f3)
            3'd0: wb_val_c = instr_q[30] ? (rs1v - rs2v) : (rs1v + rs2v);
            3'd1: wb_val_c = rs1v << rs2v[4:0];
            3'd2: wb_val_c = {31'd0, $signed(rs1v) < $signed(rs2v)};
            3'd3: wb_val_c = {31'd0, rs1v < rs2v};
            3'd4: wb_val_c = rs1v ^ rs2v;
            3'd5: wb_val_c = instr_q[30] ? ($signed(rs1v) >>> rs2v[4:0])
                                         : (rs1v >> rs2v[4:0]);
            3'd6: wb_val_c = rs1v | rs2v;
            3'd7: wb_val_c = rs1v & rs2v;
          endcase
          if ((f3 == 3'd1 || f3 == 3'd5) && instr_q[30]) illegal_c = 1'b1;
        end
      end
      7'b00011_11: begin // MISC-MEM(fence/fence.i = nop)
      end
      7'b11100_11: begin // SYSTEM
        if (f3 == 3'd0) is_sys_c = 1'b1;
        else            illegal_c = 1'b1;
      end
      7'b00010_11: begin // custom-0(opcode 0x0B)→ AME
        ame_acc_c = 1'b1;
      end
      default: illegal_c = 1'b1;
    endcase
  end

  function automatic [31:0] mult_hi (input signed [31:0] a, input signed [31:0] b);
    longint p;
    p = longint'(a) * longint'(b);
    mult_hi = p[63:32];
  endfunction
  function automatic [31:0] mult_hi_u (input signed [31:0] a, input [31:0] b);
    longint p;
    p = longint'(a) * longint'({1'b0, b});
    mult_hi_u = p[63:32];
  endfunction
  function automatic [31:0] div_s (input [31:0] a, input [31:0] b);
    if (b == 32'd0) div_s = 32'hFFFF_FFFF;
    else if (a == 32'h8000_0000 && b == 32'hFFFF_FFFF) div_s = 32'h8000_0000;
    else            div_s = $signed(a) / $signed(b);
  endfunction
  function automatic [31:0] rem_s (input [31:0] a, input [31:0] b);
    if (b == 32'd0) rem_s = a;
    else if (a == 32'h8000_0000 && b == 32'hFFFF_FFFF) rem_s = 32'd0;
    else            rem_s = $signed(a) % $signed(b);
  endfunction

  always_comb begin
    bus_req.valid = (state == S_IF) || (state == S_MEM);
    bus_req.write = (state == S_MEM) && is_store_q;
    bus_req.addr  = (state == S_IF) ? pc : mem_addr_q;
    bus_req.wdata = mem_wdata_q;
    bus_req.wstrb = mem_wstrb_q;
  end

  logic [7:0] ld_byte_c;
  always @* begin
    case (mem_addr_q[1:0])
      2'd0: ld_byte_c = bus_resp.rdata[7:0];
      2'd1: ld_byte_c = bus_resp.rdata[15:8];
      2'd2: ld_byte_c = bus_resp.rdata[23:16];
      2'd3: ld_byte_c = bus_resp.rdata[31:24];
    endcase
  end

  logic [31:0] load_data_c;
  always @* begin
    case (mem_size_q)
      2'd0: load_data_c = mem_sign_q ? {{24{ld_byte_c[7]}}, ld_byte_c}
                                     : {24'd0, ld_byte_c};
      2'd1: load_data_c = mem_sign_q ? (mem_addr_q[1] ? {{16{bus_resp.rdata[31]}}, bus_resp.rdata[31:16]}
                                                      : {{16{bus_resp.rdata[15]}}, bus_resp.rdata[15:0]})
                                     : (mem_addr_q[1] ? {16'd0, bus_resp.rdata[31:16]}
                                                      : {16'd0, bus_resp.rdata[15:0]});
      default: load_data_c = bus_resp.rdata;
    endcase
  end

  wire ame_is_st = (f3 == amechip_pkg::AME_F3_STY) || (f3 == amechip_pkg::AME_F3_STQ);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_IF;
      pc <= amechip_pkg::RESET_VECTOR;
      instr_q <= 32'd0;
      retire_cnt <= 32'd0;
      pc_next_q <= 32'd0;
      mem_addr_q <= 32'd0; mem_wdata_q <= 32'd0; mem_wstrb_q <= 4'd0;
      mem_rd_q <= 5'd0; is_store_q <= 1'b0;
      mem_size_q <= 2'd2; mem_sign_q <= 1'b0;
      ame_req_valid <= 1'b0; ame_req_instr <= 32'd0; ame_req_rs1 <= 32'd0; ame_req_rs2 <= 32'd0;
      ame_rd_q <= 32'hFFFF_FFFF;
      buserr_sticky <= 32'd0;
      buserr_evt_o <= 1'b0;
      wfi_q <= 1'b0;
      for (int i = 0; i < 32; i++) regs[i] <= 32'd0;
    end else begin
      buserr_evt_o <= 1'b0;

      case (state)
        S_IF: begin
          if (bus_resp.valid) begin
            if (bus_resp.resp != amechip_pkg::AXI_OKAY) begin
              buserr_sticky <= buserr_sticky + 32'd1;
              buserr_evt_o  <= 1'b1;
              $display("[stub_cpu] FETCH BUSERR pc=%08x resp=%b — halt", pc, bus_resp.resp);
              state <= S_HALT;
            end else begin
              instr_q   <= bus_resp.rdata;
              pc_next_q <= pc + 32'd4;
              state     <= S_EX;
            end
          end
        end

        S_EX: begin
          retire_cnt <= retire_cnt + 32'd1;
          if (illegal_c) begin
            $display("[stub_cpu] ILLEGAL instr=%08x pc=%08x — halt (retire=%0d)",
                     instr_q, pc, retire_cnt + 1);
            state <= S_HALT;
          end else if (ame_acc_c) begin
            ame_req_instr <= instr_q;
            ame_req_rs1   <= rs1v;
            ame_req_rs2   <= rs2v;
            ame_rd_q      <= ame_is_st ? {27'd0, rd} : 32'hFFFF_FFFF;
            ame_req_valid <= 1'b1;
            state         <= S_AME_REQ;
          end else if (is_sys_c) begin
            case (instr_q[31:20])
              12'h000: begin                                            // ecall
                $display("[stub_cpu] ECALL pc=%08x (retire=%0d)", pc, retire_cnt + 1);
                state <= S_HALT;
              end
              12'h001: begin                                            // ebreak
                $display("[stub_cpu] EBREAK pc=%08x (retire=%0d)", pc, retire_cnt + 1);
                state <= S_HALT;
              end
              12'h105: begin                                            // wfi
                $display("[stub_cpu] WFI pc=%08x retire=%0d — 核停机", pc, retire_cnt + 1);
                wfi_q <= 1'b1;
                state <= S_HALT;
              end
              default: state <= S_HALT;
            endcase
          end else if (mem_acc_c) begin
            mem_addr_q  <= mem_addr_c;
            mem_wdata_q <= mem_wdata_c;
            mem_wstrb_q <= mem_wstrb_c;
            mem_rd_q    <= rd;
            is_store_q  <= is_store_c;
            mem_size_q  <= mem_size_c;
            mem_sign_q  <= mem_sign_c;
            state       <= S_MEM;
          end else begin
            if (wb_en_c && rd != 5'd0) regs[rd] <= wb_val_c;
            pc    <= jump_c ? jump_target_c : pc_next_q;
            state <= S_IF;
          end
        end

        S_MEM: begin
          if (bus_resp.valid) begin
            if (bus_resp.resp != amechip_pkg::AXI_OKAY) begin
              buserr_sticky <= buserr_sticky + 32'd1;
              buserr_evt_o  <= 1'b1;
            end
            if (!is_store_q && rd != 5'd0) begin
              regs[mem_rd_q] <= (bus_resp.resp == amechip_pkg::AXI_OKAY)
                                ? load_data_c : 32'd0;
            end
            pc    <= pc_next_q;
            state <= S_GAP;
          end
        end

        S_GAP: begin
          state <= S_IF;
        end

        S_AME_REQ: begin
          if (ame_req_ready) begin
            ame_req_valid <= 1'b0;
            state         <= S_AME_RESP;
          end
        end
        S_AME_RESP: begin
          if (ame_resp_valid) begin
            if (ame_rd_q[4:0] != 5'd0 && ame_rd_q != 32'hFFFF_FFFF) begin
              regs[ame_rd_q[4:0]] <= ame_resp_data;
            end
            pc    <= pc_next_q;
            state <= S_IF;
          end
        end

        S_HALT: begin
          ;
        end

        default: state <= S_IF;
      endcase
    end
  end

  wire unused_irq = irq_i;
  wire unused_buserr_sticky = |buserr_sticky;

endmodule
