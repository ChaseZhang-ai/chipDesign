`ifndef _AMECHIP_PKG_SV
 `include "amechip_pkg.sv"
`endif
`ifndef _AMECPU_PKG_SV
 `include "amecpu_pkg.sv"
`endif

module ame_cpu (
  input  logic clk_i,
  input  logic rst_ni,              // 同步释放后的片内复位(clk_rst_if.rst_n)

  output logic [31:0] ax_aw_addr,
  output logic        ax_aw_valid,
  input  logic        ax_aw_ready,
  output logic [31:0] ax_w_data,
  output logic [3:0]  ax_w_strb,
  output logic        ax_w_valid,
  input  logic        ax_w_ready,
  input  logic [1:0]  ax_b_resp,
  input  logic        ax_b_valid,
  output logic        ax_b_ready,
  output logic [31:0] ax_ar_addr,
  output logic        ax_ar_valid,
  input  logic        ax_ar_ready,
  input  logic [31:0] ax_r_data,
  input  logic [1:0]  ax_r_resp,
  input  logic        ax_r_valid,
  output logic        ax_r_ready,

  output logic        ame_req_valid,
  output logic [31:0] ame_req_instr,
  output logic [31:0] ame_req_rs1,
  output logic [31:0] ame_req_rs2,
  input  logic        ame_req_ready,
  input  logic        ame_resp_valid,
  input  logic [31:0] ame_resp_data,
  input  logic        ame_resp_err,

  input  logic        irq_i,        // INTC 汇集中断(高有效)
  output logic        halt_o,       // ebreak 提交后置位(TB 停机,粘滞)
  output logic        wfi_o,        // wfi 提交脉冲(最小实现 = NOP+脉冲,见 NOTES)
  output logic        bus_err_o,    // 总线错误脉冲 → SoC INTC bit8(IRQ_BUSERR)

  output logic        trace_valid_o,
  output logic [31:0] trace_pc_o,
  output logic [31:0] trace_instr_o,
  output logic [4:0]  trace_rd_o,
  output logic [31:0] trace_wdata_o,
  output logic [1:0]  trace_flag_o  // [0]=写 rd [1]=wdata 依赖 mcycle,差分跳过
);

  import amecpu_pkg::*;
  import amechip_pkg::*;

  logic        stall;            // 流水停顿(EX 或 MEM 忙)
  logic        pipe_advance;     // 本拍结束流水推进
  logic        redirect;         // 本拍重定向取指(分支/jal/mret/中断)
  logic [31:0] redirect_target;

  wire         if_grant, if_rvalid, if_err;
  wire [31:0]  if_rdata;
  wire         dm_rvalid, dm_grant, dm_err;
  wire [31:0]  dm_rdata;
  logic        dm_req_valid, dm_we;
  logic [31:0] dm_addr, dm_wdata;
  logic [3:0]  dm_wstrb;

  wire         ex_stall_loaduse; // load-use 互锁
  wire         mul_can_start;    // 乘除发起(停等期间标记)
  wire         mem_busy;         // MEM 级 load/store 未完成
  wire         ex_nop_effect;    // 本条 EX 指令效果失效(非法/未对齐/CSR 非法)
  wire         take_irq;         // 本拍采样到中断
  wire         csr_rlegal, csr_wro, csr_mie;
  logic [31:0] csr_rdata, csr_mtvec_base;
  wire         ame_req_v;        // AME 请求 EX 级呈现(v0.3:打入请求寄存器才对外)
  wire         ame_waiting;      // AME 请求未能装入请求寄存器 → EX 停等
  logic        amreq_v_q;        // v0.3 请求寄存器(对引脚做 §6 握手)
  logic [31:0] amreq_instr_q, amreq_rs1_q, amreq_rs2_q;

  wire [31:0] op_a_raw, op_b_raw; // EX 操作数(经全部旁路)

  logic [31:0] pc_q;         // 下一个待发取指地址
  logic [31:0] fetch_pc_q;   // 在途取指的地址(响应对应)
  logic        fetch_infl_q; // 有一笔 IF 读在 AXI 上
  logic        halt_q;
  logic        drain_q;      // ebreak 进入 EX 后置位:封死取指与 ID→EX(粘滞)

  logic        if_id_valid_q;
  logic [31:0] if_id_pc_q;
  logic [31:0] if_id_instr_q;
  logic        if_buf_valid_q;
  logic [31:0] if_buf_pc_q;
  logic [31:0] if_buf_instr_q;

  logic fetch_poison_q;

  wire  if_can_req = !fetch_infl_q && !if_buf_valid_q && !halt_q && !drain_q;
  wire  fetch_poison_needed = (fetch_infl_q || if_grant) && !if_rvalid;

  cpu_axi_bridge u_bridge (
    .clk_i          (clk_i),
    .rst_ni         (rst_ni),
    .if_req_valid_i (if_can_req),
    .if_addr_i      (pc_q),
    .if_grant_o     (if_grant),
    .if_rvalid_o    (if_rvalid),
    .if_rdata_o     (if_rdata),
    .if_err_o       (if_err),
    .dm_req_valid_i (dm_req_valid),
    .dm_we_i        (dm_we),
    .dm_addr_i      (dm_addr),
    .dm_wdata_i     (dm_wdata),
    .dm_wstrb_i     (dm_wstrb),
    .dm_grant_o     (dm_grant),
    .dm_rvalid_o    (dm_rvalid),
    .dm_rdata_o     (dm_rdata),
    .dm_err_o       (dm_err),
    .ax_aw_addr     (ax_aw_addr),
    .ax_aw_valid    (ax_aw_valid),
    .ax_aw_ready    (ax_aw_ready),
    .ax_w_data      (ax_w_data),
    .ax_w_strb      (ax_w_strb),
    .ax_w_valid     (ax_w_valid),
    .ax_w_ready     (ax_w_ready),
    .ax_b_resp      (ax_b_resp),
    .ax_b_valid     (ax_b_valid),
    .ax_b_ready     (ax_b_ready),
    .ax_ar_addr     (ax_ar_addr),
    .ax_ar_valid    (ax_ar_valid),
    .ax_ar_ready    (ax_ar_ready),
    .ax_r_data      (ax_r_data),
    .ax_r_resp      (ax_r_resp),
    .ax_r_valid     (ax_r_valid),
    .ax_r_ready     (ax_r_ready)
  );

  wire rdata_in = if_rvalid && !redirect && !drain_q && !fetch_poison_q; // 重定向/停机/毒化:过期回复作废
  wire pipe_kill = redirect || drain_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      pc_q           <= amechip_pkg::RESET_VECTOR;
      fetch_pc_q     <= 32'h0;
      fetch_infl_q   <= 1'b0;
      fetch_poison_q <= 1'b0;
      drain_q        <= 1'b0;
      if_id_valid_q  <= 1'b0;
      if_id_pc_q     <= 32'h0;
      if_id_instr_q  <= 32'h0;
      if_buf_valid_q <= 1'b0;
      if_buf_pc_q    <= 32'h0;
      if_buf_instr_q <= 32'h0;
    end else begin
      if (if_grant)            fetch_infl_q <= 1'b1;
      else if (if_rvalid)      fetch_infl_q <= 1'b0;

      if ((redirect || drain_q) && fetch_poison_needed)
                               fetch_poison_q <= 1'b1;
      else if (if_rvalid)      fetch_poison_q <= 1'b0;
      if (ex_ebreak) drain_q <= 1'b1;

      if (if_grant) fetch_pc_q <= pc_q;

      if (redirect)      pc_q <= redirect_target;
      else if (if_grant) pc_q <= pc_q + 32'd4;

      if (pipe_kill) begin
        if_id_valid_q  <= 1'b0;
        if_buf_valid_q <= 1'b0;
      end else if (!stall) begin
        if (if_buf_valid_q) begin
          if_id_valid_q  <= 1'b1;
          if_id_pc_q     <= if_buf_pc_q;
          if_id_instr_q  <= if_buf_instr_q;
          if_buf_valid_q <= rdata_in;
          if_buf_pc_q    <= fetch_pc_q;
          if_buf_instr_q <= if_rdata;
        end else if (rdata_in) begin
          if_id_valid_q  <= 1'b1;
          if_id_pc_q     <= fetch_pc_q;
          if_id_instr_q  <= if_rdata;
        end else begin
          if_id_valid_q  <= 1'b0;
        end
      end else if (rdata_in) begin
        if_buf_valid_q <= 1'b1;
        if_buf_pc_q    <= fetch_pc_q;
        if_buf_instr_q <= if_rdata;
      end
    end
  end

  wire [31:0] id_instr = if_id_instr_q;
  wire [6:0]  f_op     = id_instr[6:0];
  wire [4:0]  f_rd     = id_instr[11:7];
  wire [2:0]  f_f3     = id_instr[14:12];
  wire [6:0]  f_f7     = id_instr[31:25];

  wire [31:0] imm_i = {{20{id_instr[31]}}, id_instr[31:20]};
  wire [31:0] imm_s = {{20{id_instr[31]}}, id_instr[31:25], id_instr[11:7]};
  wire [31:0] imm_b = {{19{id_instr[31]}}, id_instr[31], id_instr[7], id_instr[30:25], id_instr[11:8], 1'b0};
  wire [31:0] imm_u = {id_instr[31:12], 12'b0};
  wire [31:0] imm_j = {{11{id_instr[31]}}, id_instr[31], id_instr[19:12], id_instr[20], id_instr[30:21], 1'b0};

  logic       d_rs1_en, d_rs2_en, d_rd_we;
  logic [4:0] d_rd;
  logic [3:0] d_alu_op;
  logic       d_alu_a_pc, d_alu_b_imm;
  logic       d_is_load, d_is_store, d_is_ame, d_ame_rd, d_is_muldiv;
  logic [2:0] d_ls_size;
  logic       d_is_branch, d_is_jal, d_is_jalr;
  logic [2:0] d_branch_f3;
  logic       d_is_csr, d_is_ebreak, d_is_mret, d_is_wfi, d_is_ecall;
  logic [2:0] d_csr_f3;
  logic [11:0] d_csr_addr;
  logic       d_illegal, d_csr_skip;
  logic [31:0] d_imm;

  always_comb begin
    d_rs1_en = 1'b0; d_rs2_en = 1'b0; d_rd_we = 1'b0;
    d_rd     = f_rd;
    d_alu_op = ALU_ADD; d_alu_a_pc = 1'b0; d_alu_b_imm = 1'b0;
    d_is_load = 1'b0; d_is_store = 1'b0; d_is_ame = 1'b0; d_ame_rd = 1'b0;
    d_is_muldiv = 1'b0; d_ls_size = 3'd0;
    d_is_branch = 1'b0; d_is_jal = 1'b0; d_is_jalr = 1'b0; d_branch_f3 = 3'd0;
    d_is_csr = 1'b0; d_is_ebreak = 1'b0; d_is_mret = 1'b0; d_is_wfi = 1'b0; d_is_ecall = 1'b0;
    d_csr_f3 = 3'd0; d_csr_addr = 12'h0;
    d_illegal = 1'b0; d_csr_skip = 1'b0;
    d_imm = 32'h0;

    case (f_op)
      OP_LUI: begin
        d_rd_we = 1'b1; d_alu_op = ALU_COPYB; d_alu_b_imm = 1'b1; d_imm = imm_u;
      end
      OP_AUIPC: begin
        d_rd_we = 1'b1; d_alu_op = ALU_ADD; d_alu_a_pc = 1'b1; d_alu_b_imm = 1'b1; d_imm = imm_u;
      end
      OP_JAL: begin
        d_rd_we = 1'b1; d_is_jal = 1'b1; d_alu_op = ALU_ADD;
        d_alu_a_pc = 1'b1; d_alu_b_imm = 1'b1; d_imm = imm_j;
      end
      OP_JALR: begin
        if (f_f3 != 3'd0) d_illegal = 1'b1;
        else begin
          d_rd_we = 1'b1; d_is_jalr = 1'b1; d_rs1_en = 1'b1;
          d_alu_op = ALU_ADD; d_alu_b_imm = 1'b1; d_imm = imm_i;
        end
      end
      OP_BRANCH: begin
        d_rs1_en = 1'b1; d_rs2_en = 1'b1; d_is_branch = 1'b1;
        d_branch_f3 = f_f3; d_alu_op = ALU_ADD;
        d_alu_a_pc = 1'b1; d_alu_b_imm = 1'b1; d_imm = imm_b;
        if ((f_f3 == 3'd2) || (f_f3 == 3'd3)) d_illegal = 1'b1;
      end
      OP_LOAD: begin
        d_rs1_en = 1'b1; d_rd_we = 1'b1; d_is_load = 1'b1;
        d_ls_size = f_f3; d_alu_op = ALU_ADD; d_alu_b_imm = 1'b1; d_imm = imm_i;
        if ((f_f3 == 3'd3) || (f_f3 == 3'd6) || (f_f3 == 3'd7)) d_illegal = 1'b1;
      end
      OP_STORE: begin
        d_rs1_en = 1'b1; d_rs2_en = 1'b1; d_is_store = 1'b1;
        d_ls_size = f_f3; d_alu_op = ALU_ADD; d_alu_b_imm = 1'b1; d_imm = imm_s;
        if (f_f3 > 3'd2) d_illegal = 1'b1;
      end
      OP_ALUI: begin
        d_rs1_en = 1'b1; d_rd_we = 1'b1; d_alu_b_imm = 1'b1; d_imm = imm_i;
        case (f_f3)
          3'd0: d_alu_op = ALU_ADD;
          3'd1: begin
            if (f_f7 != 7'd0) d_illegal = 1'b1;
            d_alu_op = ALU_SLL;
          end
          3'd2: d_alu_op = ALU_SLT;
          3'd3: d_alu_op = ALU_SLTU;
          3'd4: d_alu_op = ALU_XOR;
          3'd5: begin
            if (f_f7 == 7'd0)       d_alu_op = ALU_SRL;
            else if (f_f7 == 7'h20) d_alu_op = ALU_SRA;
            else                    d_illegal = 1'b1;
          end
          3'd6: d_alu_op = ALU_OR;
          3'd7: d_alu_op = ALU_AND;
          default: d_illegal = 1'b1;
        endcase
      end
      OP_ALUR: begin
        d_rs1_en = 1'b1; d_rs2_en = 1'b1; d_rd_we = 1'b1;
        if (f_f7 == 7'd0) begin
          case (f_f3)
            3'd0: d_alu_op = ALU_ADD;
            3'd1: d_alu_op = ALU_SLL;
            3'd2: d_alu_op = ALU_SLT;
            3'd3: d_alu_op = ALU_SLTU;
            3'd4: d_alu_op = ALU_XOR;
            3'd5: d_alu_op = ALU_SRL;
            3'd6: d_alu_op = ALU_OR;
            3'd7: d_alu_op = ALU_AND;
            default: d_illegal = 1'b1;
          endcase
        end else if (f_f7 == 7'h20) begin
          if (f_f3 == 3'd0)      d_alu_op = ALU_SUB;
          else if (f_f3 == 3'd5) d_alu_op = ALU_SRA;
          else                   d_illegal = 1'b1;
        end else if (f_f7 == 7'h01) begin
          d_is_muldiv = 1'b1; // funct3 由 EX 用 instr[14:12] 直传
        end else begin
          d_illegal = 1'b1;
        end
      end
      OP_FENCE: begin
        if ((f_f3 != 3'd0) && (f_f3 != 3'd1)) d_illegal = 1'b1;
      end
      OP_SYSTEM: begin
        if (f_f3 == 3'd0) begin
          case (id_instr[31:20])
            12'h000: d_is_ecall  = 1'b1;
            12'h001: d_is_ebreak = 1'b1;
            12'h302: d_is_mret   = 1'b1;
            12'h105: d_is_wfi    = 1'b1;
            default: d_illegal = 1'b1;
          endcase
        end else if ((f_f3 == 3'd1) || (f_f3 == 3'd2) || (f_f3 == 3'd3) ||
                     (f_f3 == 3'd5) || (f_f3 == 3'd6) || (f_f3 == 3'd7)) begin
          d_is_csr   = 1'b1;
          d_csr_f3   = f_f3;
          d_csr_addr = id_instr[31:20];
          d_rs1_en   = (f_f3 < 3'd5);
          d_rd_we    = 1'b1;
          d_imm      = {27'h0, id_instr[19:15]}; // 立数形式的 zimm
          d_csr_skip = (id_instr[31:20] == CSR_MCYCLE)  || (id_instr[31:20] == CSR_MCYCLEH) ||
                       (id_instr[31:20] == CSR_CYCLE)   || (id_instr[31:20] == CSR_CYCLEH);
        end else begin
          d_illegal = 1'b1;
        end
      end
      amechip_pkg::AME_OPCODE: begin
        d_is_ame = 1'b1;
        d_rs1_en = 1'b1;  // req_rs1 = 旁路后的 GPR 值
        d_rs2_en = 1'b1;  // req_rs2 同(当前未用,仍须正确驱动)
        if (f_f3 == amechip_pkg::AME_F3_CFG) begin
        end else begin
          case (f_f3)
            amechip_pkg::AME_F3_QCFG: if (f_f7 != amechip_pkg::AME_F7_QCFG) d_illegal = 1'b1;
            amechip_pkg::AME_F3_LDW:  if (f_f7 != amechip_pkg::AME_F7_LDW)  d_illegal = 1'b1;
            amechip_pkg::AME_F3_LDX:  if (f_f7 != amechip_pkg::AME_F7_LDX)  d_illegal = 1'b1;
            amechip_pkg::AME_F3_EXE:
              if ((f_f7 != amechip_pkg::AME_F7_EXE) && (f_f7 != amechip_pkg::AME_F7_EXEF))
                d_illegal = 1'b1;
            amechip_pkg::AME_F3_STY: begin
              if (f_f7 != amechip_pkg::AME_F7_STY) d_illegal = 1'b1;
              d_ame_rd = 1'b1;
            end
            amechip_pkg::AME_F3_STQ: begin
              if (f_f7 != amechip_pkg::AME_F7_STQ) d_illegal = 1'b1;
              d_ame_rd = 1'b1;
            end
            amechip_pkg::AME_F3_SYNC: if (f_f7 != amechip_pkg::AME_F7_SYNC) d_illegal = 1'b1;
            default: d_illegal = 1'b1;
          endcase
        end
        d_rd_we = d_ame_rd; // 仅 st.y/st.q 写 rd
      end
      default: d_illegal = 1'b1;
    endcase
    if (d_illegal) begin
      d_rs1_en = 1'b0; d_rs2_en = 1'b0; d_rd_we = 1'b0;
      d_is_load = 1'b0; d_is_store = 1'b0; d_is_ame = 1'b0; d_ame_rd = 1'b0;
      d_is_muldiv = 1'b0; d_is_branch = 1'b0; d_is_jal = 1'b0; d_is_jalr = 1'b0;
      d_is_csr = 1'b0; d_is_ebreak = 1'b0; d_is_mret = 1'b0; d_is_wfi = 1'b0;
      d_is_ecall = 1'b0; d_csr_skip = 1'b0;
      d_illegal = 1'b1;
    end
  end

  logic [31:0] rf_rdata1, rf_rdata2;

  logic        idex_valid;
  logic        idex_rs1_en, idex_rs2_en, idex_rd_we;
  logic [4:0]  idex_rd;
  logic [3:0]  idex_alu_op;
  logic        idex_alu_a_pc, idex_alu_b_imm;
  logic        idex_is_load, idex_is_store, idex_is_ame, idex_ame_rd, idex_is_muldiv;
  logic [2:0]  idex_ls_size;
  logic        idex_is_branch, idex_is_jal, idex_is_jalr;
  logic [2:0]  idex_branch_f3;
  logic        idex_is_csr, idex_is_ebreak, idex_is_mret, idex_is_wfi, idex_is_ecall;
  logic [2:0]  idex_csr_f3;
  logic [11:0] idex_csr_addr;
  logic        idex_illegal, idex_csr_skip;
  logic [31:0] idex_pc, idex_instr, idex_imm, idex_rs1_val, idex_rs2_val;
  logic        idex_mul_started;

  wire idex_fill = pipe_advance && !redirect;
  wire idex_kill = redirect;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      idex_valid <= 1'b0;
    end else if (idex_kill) begin
      idex_valid <= 1'b0;
    end else if (idex_fill) begin
      idex_valid       <= if_id_valid_q;
      idex_rs1_en      <= d_rs1_en;
      idex_rs2_en      <= d_rs2_en;
      idex_rd_we       <= d_rd_we;
      idex_rd          <= d_rd;
      idex_alu_op      <= d_alu_op;
      idex_alu_a_pc    <= d_alu_a_pc;
      idex_alu_b_imm   <= d_alu_b_imm;
      idex_is_load     <= d_is_load;
      idex_is_store    <= d_is_store;
      idex_is_ame      <= d_is_ame;
      idex_ame_rd      <= d_ame_rd;
      idex_is_muldiv   <= d_is_muldiv;
      idex_ls_size     <= d_ls_size;
      idex_is_branch   <= d_is_branch;
      idex_is_jal      <= d_is_jal;
      idex_is_jalr     <= d_is_jalr;
      idex_branch_f3   <= d_branch_f3;
      idex_is_csr      <= d_is_csr;
      idex_is_ebreak   <= d_is_ebreak;
      idex_is_mret     <= d_is_mret;
      idex_is_wfi      <= d_is_wfi;
      idex_is_ecall    <= d_is_ecall;
      idex_csr_f3      <= d_csr_f3;
      idex_csr_addr    <= d_csr_addr;
      idex_illegal     <= d_illegal;
      idex_csr_skip    <= d_csr_skip;
      idex_pc          <= if_id_pc_q;
      idex_instr       <= if_id_instr_q;
      idex_imm         <= d_imm;
      idex_rs1_val     <= rf_rdata1;
      idex_rs2_val     <= rf_rdata2;
      idex_mul_started <= 1'b0;
    end else if (mul_can_start) begin
      idex_mul_started <= 1'b1;   // 停等期间标记已发起
    end
  end

  wire [31:0] exmem_fwd_val = exmem_is_ame_rd ? ame_resp_data : exmem_result;

  wire fmatch_a = exmem_valid && exmem_rd_we && (exmem_rd != 5'h0)
                  && idex_rs1_en && (exmem_rd == idex_instr[19:15]);
  wire fmatch_b = exmem_valid && exmem_rd_we && (exmem_rd != 5'h0)
                  && idex_rs2_en && (exmem_rd == idex_instr[24:20]);
  wire fmatch_a_w = memwb_valid && memwb_rd_we && (memwb_rd != 5'h0)
                    && idex_rs1_en && (memwb_rd == idex_instr[19:15]);
  wire fmatch_b_w = memwb_valid && memwb_rd_we && (memwb_rd != 5'h0)
                    && idex_rs2_en && (memwb_rd == idex_instr[24:20]);

  assign op_a_raw = fmatch_a   ? exmem_fwd_val
                  : fmatch_a_w ? memwb_wdata
                  :              idex_rs1_val;
  assign op_b_raw = fmatch_b   ? exmem_fwd_val
                  : fmatch_b_w ? memwb_wdata
                  :              idex_rs2_val;

  wire lu_a = idex_rs1_en && (exmem_rd == idex_instr[19:15]);
  wire lu_b = idex_rs2_en && (exmem_rd == idex_instr[24:20]);
  assign ex_stall_loaduse = exmem_valid && exmem_is_load && exmem_rd_we
                            && (exmem_rd != 5'h0) && (lu_a || lu_b);

  wire [31:0] alu_a = idex_alu_a_pc ? idex_pc : op_a_raw;
  wire [31:0] alu_b = idex_alu_b_imm ? idex_imm : op_b_raw;
  logic [31:0] alu_y;

  wire         muldiv_run;
  wire         muldiv_idle;
  wire         muldiv_done;
  wire [31:0]  muldiv_y;
  assign mul_can_start = idex_valid && idex_is_muldiv && !idex_mul_started
                         && muldiv_idle && !ex_stall_loaduse && !mem_busy;
  wire mul_waiting = idex_valid && idex_is_muldiv
                     && !(idex_mul_started && muldiv_done);

  wire [11:0] csr_raddr = idex_is_csr ? idex_csr_addr : CSR_MEPC;
  wire  [1:0] retire_pend = {1'b0, exmem_valid} + {1'b0, memwb_fresh_q}; // EX 读时在 MEM/WB 的更老指令
  wire        csr_we_pulse = pipe_advance && idex_valid && idex_is_csr && !ex_nop_effect;
  wire [31:0] csr_wdata = idex_csr_f3[2] ? {27'h0, idex_imm[4:0]} : op_a_raw;
  wire        mret_commit = pipe_advance && idex_valid && idex_is_mret;

  wire ex_misaligned = idex_valid && (idex_is_load || idex_is_store) &&
       ((idex_ls_size == LS_W) && (alu_y[1:0] != 2'b00) ||
        (idex_ls_size == LS_H) && (alu_y[0] != 1'b0));
  wire csr_bad = idex_valid && idex_is_csr && (!csr_rlegal
                 || (csr_wro && idex_rd_we && !csr_pure_read));
  wire csr_pure_read = ((idex_csr_f3 == 3'd2) || (idex_csr_f3 == 3'd6))
                       && (idex_instr[19:15] == 5'h0);
  assign ex_nop_effect = idex_illegal || ex_misaligned || csr_bad;

  wire ex_rd_we = idex_valid && idex_rd_we && !ex_nop_effect;

  wire [31:0] ex_result = (idex_is_jal || idex_is_jalr) ? (idex_pc + 32'd4)
                        : idex_is_csr     ? csr_rdata
                        : idex_is_muldiv  ? muldiv_y
                        : alu_y;

  wire cmp_eq  = (op_a_raw == op_b_raw);
  wire cmp_lt  = ($signed(op_a_raw) < $signed(op_b_raw));
  wire cmp_ltu = (op_a_raw < op_b_raw);
  logic br_taken;
  always_comb begin
    case (idex_branch_f3)
      3'd0:    br_taken = cmp_eq;    // BEQ
      3'd1:    br_taken = !cmp_eq;   // BNE
      3'd4:    br_taken = cmp_lt;    // BLT
      3'd5:    br_taken = !cmp_lt;   // BGE
      3'd6:    br_taken = cmp_ltu;   // BLTU
      3'd7:    br_taken = !cmp_ltu;  // BGEU
      default: br_taken = 1'b0;
    endcase
  end
  wire ex_ebreak = idex_valid && idex_is_ebreak;
  wire do_branch = idex_valid && idex_is_branch && br_taken;
  wire do_jump   = idex_valid && (idex_is_jal || idex_is_jalr);

  logic        exmem_valid;
  logic [31:0] exmem_pc, exmem_instr, exmem_result, exmem_store_data;
  logic [4:0]  exmem_rd;
  logic        exmem_rd_we, exmem_is_load, exmem_is_store, exmem_is_ame_rd;
  logic        exmem_flag_skip, exmem_is_ebreak, exmem_is_wfi;
  logic [2:0]  exmem_ls_size;

  wire mem_is_load  = exmem_valid && exmem_is_load;
  wire mem_is_store = exmem_valid && exmem_is_store;
  wire mem_is_ame   = exmem_valid && exmem_is_ame_rd;
  wire mem_active   = mem_is_load || mem_is_store || mem_is_ame;
  wire mem_load_leave  = mem_is_load  && dm_rvalid;
  wire mem_store_leave = mem_is_store && dm_grant;
  wire mem_ame_leave   = mem_is_ame   && ame_resp_valid;
  wire mem_leave       = mem_load_leave || mem_store_leave || mem_ame_leave;
  assign mem_busy      = mem_active && !mem_leave;

  assign dm_req_valid = mem_is_load || mem_is_store;
  assign dm_we        = mem_is_store;
  assign dm_addr      = exmem_result;
  assign dm_wdata     = exmem_store_data << (8 * dm_addr[1:0]);  // 字节道对齐

  always_comb begin
    case (exmem_ls_size[1:0])
      2'd0:    dm_wstrb = 4'b0001 << dm_addr[1:0];         // SB
      2'd1:    dm_wstrb = dm_addr[1] ? 4'b1100 : 4'b0011;  // SH
      default: dm_wstrb = 4'b1111;                         // SW
    endcase
  end

  function automatic logic [31:0] load_adjust(input logic [31:0] wd,
                                              input logic [2:0]  size,
                                              input logic [1:0]  a);
    logic [7:0]  b;
    logic [15:0] h;
    begin
      case (size)
        LS_B:  begin b = wd[8 * a +: 8]; load_adjust = {{24{b[7]}}, b}; end
        LS_H:  begin h = a[1] ? wd[31:16] : wd[15:0]; load_adjust = {{16{h[15]}}, h}; end
        LS_BU: begin b = wd[8 * a +: 8]; load_adjust = {24'h0, b}; end
        LS_HU: begin h = a[1] ? wd[31:16] : wd[15:0]; load_adjust = {16'h0, h}; end
        default: load_adjust = wd; // LS_W
      endcase
    end
  endfunction


  wire ex_bundle_valid     = idex_valid;
  wire ex_bundle_rd_we     = ex_rd_we;
  wire ex_bundle_is_load   = idex_valid && idex_is_load  && !ex_nop_effect;
  wire ex_bundle_is_store  = idex_valid && idex_is_store && !ex_nop_effect;
  wire ex_bundle_is_ame_rd = idex_valid && idex_is_ame && idex_ame_rd && !ex_nop_effect;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      exmem_valid <= 1'b0;
    end else if (mem_leave) begin
      exmem_valid       <= pipe_advance ? ex_bundle_valid : 1'b0;
      exmem_pc          <= ex_bundle_valid ? idex_pc : 32'h0;
      exmem_instr       <= ex_bundle_valid ? idex_instr : 32'h0;
      exmem_rd          <= idex_rd;
      exmem_rd_we       <= ex_bundle_rd_we;
      exmem_result      <= ex_result;
      exmem_is_load     <= ex_bundle_is_load;
      exmem_is_store    <= ex_bundle_is_store;
      exmem_ls_size     <= idex_ls_size;
      exmem_store_data  <= op_b_raw;
      exmem_is_ame_rd   <= ex_bundle_is_ame_rd;
      exmem_flag_skip   <= idex_csr_skip && !(idex_illegal || csr_bad);
      exmem_is_ebreak   <= idex_is_ebreak;
      exmem_is_wfi      <= idex_is_wfi;
    end else if (pipe_advance) begin
      exmem_valid       <= ex_bundle_valid;
      exmem_pc          <= idex_pc;
      exmem_instr       <= idex_instr;
      exmem_rd          <= idex_rd;
      exmem_rd_we       <= ex_bundle_rd_we;
      exmem_result      <= ex_result;
      exmem_is_load     <= ex_bundle_is_load;
      exmem_is_store    <= ex_bundle_is_store;
      exmem_ls_size     <= idex_ls_size;
      exmem_store_data  <= op_b_raw;
      exmem_is_ame_rd   <= ex_bundle_is_ame_rd;
      exmem_flag_skip   <= idex_csr_skip && !(idex_illegal || csr_bad);
      exmem_is_ebreak   <= idex_is_ebreak;
      exmem_is_wfi      <= idex_is_wfi;
    end
  end

  logic        memwb_valid;
  logic        memwb_fresh_q;   // 本拍 memwb 为新装入的指令(只提交一次)
  logic [31:0] memwb_pc, memwb_instr, memwb_wdata;
  logic [4:0]  memwb_rd;
  logic        memwb_rd_we, memwb_flag_skip, memwb_is_ebreak, memwb_is_wfi;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      memwb_valid   <= 1'b0;
      memwb_fresh_q <= 1'b0;
    end else begin
      memwb_fresh_q <= 1'b0;   // 默认清零;仅新装入拍置位
      if (mem_load_leave) begin
      memwb_valid     <= 1'b1;
      memwb_pc        <= exmem_pc;
      memwb_instr     <= exmem_instr;
      memwb_rd        <= exmem_rd;
      memwb_rd_we     <= exmem_rd_we;
      memwb_wdata     <= load_adjust(dm_rdata, exmem_ls_size, dm_addr[1:0]);
      memwb_flag_skip <= exmem_flag_skip;
      memwb_is_ebreak <= exmem_is_ebreak;
      memwb_is_wfi    <= exmem_is_wfi;
      memwb_fresh_q   <= 1'b1;
    end else if (mem_store_leave) begin
      memwb_valid     <= 1'b1;
      memwb_pc        <= exmem_pc;
      memwb_instr     <= exmem_instr;
      memwb_rd        <= exmem_rd;
      memwb_rd_we     <= 1'b0;
      memwb_wdata     <= 32'h0;
      memwb_flag_skip <= exmem_flag_skip;
      memwb_is_ebreak <= exmem_is_ebreak;
      memwb_is_wfi    <= exmem_is_wfi;
      memwb_fresh_q   <= 1'b1;
    end else if (mem_ame_leave) begin
      memwb_valid     <= 1'b1;
      memwb_pc        <= exmem_pc;
      memwb_instr     <= exmem_instr;
      memwb_rd        <= exmem_rd;
      memwb_rd_we     <= exmem_rd_we;
      memwb_wdata     <= ame_resp_data;   // st.y/st.q resp(1/2 拍统一在此捕获)
      memwb_flag_skip <= exmem_flag_skip;
      memwb_is_ebreak <= exmem_is_ebreak;
      memwb_is_wfi    <= exmem_is_wfi;
      memwb_fresh_q   <= 1'b1;
    end else if (pipe_advance) begin
      memwb_valid     <= exmem_valid;
      memwb_pc        <= exmem_pc;
      memwb_instr     <= exmem_instr;
      memwb_rd        <= exmem_rd;
      memwb_rd_we     <= exmem_rd_we;
      memwb_wdata     <= exmem_is_ame_rd ? ame_resp_data : exmem_result;
      memwb_flag_skip <= exmem_flag_skip;
      memwb_is_ebreak <= exmem_is_ebreak;
      memwb_is_wfi    <= exmem_is_wfi;
      memwb_fresh_q   <= exmem_valid;
      end
    end
  end

  wire ex_stall = ex_stall_loaduse || ame_waiting || mul_waiting;
  assign stall        = ex_stall || mem_busy;
  assign pipe_advance = !stall;

  assign redirect = (pipe_advance && (do_branch || do_jump || mret_commit)) || take_irq;
  assign redirect_target = take_irq       ? csr_mtvec_base
                         : idex_is_mret   ? {csr_rdata[31:1], 1'b0}
                         :                  alu_y;

  wire [31:0] next_unret_pc = if_id_valid_q  ? if_id_pc_q
                            : if_buf_valid_q ? if_buf_pc_q
                            : fetch_infl_q   ? fetch_pc_q
                            :                  pc_q;
  assign take_irq = irq_i && csr_mie && !idex_valid && !halt_q;
  wire ev_ill = pipe_advance && idex_valid && ex_nop_effect;
  wire bus_err_pulse = if_err || dm_err;

  wire wb_fire = memwb_valid && memwb_fresh_q && !halt_q; // 新装入才提交(停等期间不重复)
  assign trace_valid_o = wb_fire;
  assign trace_pc_o    = memwb_pc;
  assign trace_instr_o = memwb_instr;
  assign trace_rd_o    = memwb_rd;
  assign trace_wdata_o = memwb_wdata;
  assign trace_flag_o  = {memwb_flag_skip, memwb_rd_we && (memwb_rd != 5'h0)};

  assign halt_o = halt_q;
  wire ebreak_pulse = wb_fire && memwb_is_ebreak;
  assign wfi_o  = wb_fire && memwb_is_wfi;
  wire ecall_pulse  = pipe_advance && idex_valid && idex_is_ecall;

  wire ame_issue_ok = !ex_stall_loaduse && !mem_busy;
  assign ame_req_v   = idex_valid && idex_is_ame && ame_issue_ok;
  wire amreq_ld_ok   = !amreq_v_q || ame_req_ready;
  wire ame_stq_acc   = amreq_v_q && ame_req_ready
                       && (amreq_instr_q[14:12] == amechip_pkg::AME_F3_STQ);
  logic [1:0]        ame_resp_drain_q;
  wire               ame_resp_drain_busy = (ame_resp_drain_q != 2'd0)
                                           || (amreq_v_q && ame_req_ready);
  wire               ame_rd_deposit      = ex_bundle_is_ame_rd && ame_resp_drain_busy;
  wire               amreq_ld            = ame_req_v && amreq_ld_ok && !ame_rd_deposit;
  assign ame_waiting = ame_req_v && !amreq_ld;
  wire ame_err_pulse = ame_resp_valid && ame_resp_err;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      amreq_v_q <= 1'b0;
      ame_resp_drain_q <= 2'd0;
    end else begin
      ame_resp_drain_q <= 2'd0;
      if (amreq_v_q && ame_req_ready)
        ame_resp_drain_q <= ame_stq_acc ? 2'd3 : 2'd1;   // 接受沿:resp 在途
      else if (ame_resp_drain_busy)
        ame_resp_drain_q <= ame_resp_drain_q - 2'd1;
      if (amreq_ld) begin
        amreq_v_q     <= 1'b1;
        amreq_instr_q <= idex_instr;
        amreq_rs1_q   <= op_a_raw;
        amreq_rs2_q   <= op_b_raw;
      end else if (amreq_v_q && ame_req_ready) begin
        amreq_v_q <= 1'b0;              // 已接受且无新请求:撤销
      end
    end
  end

  assign ame_req_valid = amreq_v_q;
  assign ame_req_instr = amreq_instr_q;
  assign ame_req_rs1   = amreq_rs1_q;
  assign ame_req_rs2   = amreq_rs2_q;

  cpu_regfile u_rf (
    .clk_i    (clk_i),
    .rst_ni   (rst_ni),
    .raddr1_i (id_instr[19:15]),
    .rdata1_o (rf_rdata1),
    .raddr2_i (id_instr[24:20]),
    .rdata2_o (rf_rdata2),
    .we_i     (wb_fire && memwb_rd_we && (memwb_rd != 5'h0)),
    .waddr_i  (memwb_rd),
    .wdata_i  (memwb_wdata)
  );

  cpu_alu u_alu (
    .op_i (idex_alu_op),
    .a_i  (alu_a),
    .b_i  (alu_b),
    .y_o  (alu_y)
  );

  cpu_muldiv u_muldiv (
    .clk_i    (clk_i),
    .rst_ni   (rst_ni),
    .start_i  (mul_can_start),
    .fn_i     (idex_instr[14:12]),
    .rs1_i    (op_a_raw),
    .rs2_i    (op_b_raw),
    .busy_o   (muldiv_run),
    .idle_o   (muldiv_idle),
    .done_o   (muldiv_done),
    .result_o (muldiv_y)
  );

  cpu_csr u_csr (
    .clk_i        (clk_i),
    .rst_ni       (rst_ni),
    .raddr_i      (csr_raddr),
    .rdata_o      (csr_rdata),
    .rlegal_o     (csr_rlegal),
    .wro_o        (csr_wro),
    .we_i         (csr_we_pulse),
    .waddr_i      (idex_csr_addr),
    .wdata_i      (csr_wdata),
    .wf3_i        (idex_csr_f3),
    .retire_i     (wb_fire),
    .retire_pend_i(retire_pend),
    .ev_ill_i     (ev_ill),
    .ev_ame_err_i (ame_err_pulse),
    .ev_bus_err_i (bus_err_pulse),
    .ev_ecall_i   (ecall_pulse),
    .ev_ebreak_i  (ebreak_pulse),
    .irq_i        (irq_i),
    .trap_i       (take_irq),
    .trap_pc_i    (next_unret_pc),
    .mret_i       (mret_commit),
    .mie_o        (csr_mie),
    .mtvec_base_o (csr_mtvec_base)
  );

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) halt_q <= 1'b0;
    else if (ebreak_pulse) halt_q <= 1'b1;
  end

  assign bus_err_o = bus_err_pulse;

endmodule
