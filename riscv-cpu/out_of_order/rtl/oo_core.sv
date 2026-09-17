// Copyright (c) 2026 Shubham Lonkar
// SPDX-License-Identifier: MIT

`default_nettype none

// oo_core -- RV32I, out-of-order execute, in-order commit

module oo_core
    import riscv_pkg::*;
    import oo_pkg::*;
#(
    parameter bp_mode_e BP_MODE = BP_GSHARE
) (
    input  wire         clk,
    input  wire         rst_n,

    output logic [31:0] imem_addr_o,
    input  wire  [31:0] imem_rdata_i,

    output logic [31:0] dmem_addr_o,
    output logic [31:0] dmem_wdata_o,
    output logic        dmem_we_o,
    input  wire  [31:0] dmem_rdata_i
);

    // state
    logic [31:0]      pc;
    rob_e             rob [0:ROB_DEPTH-1];
    logic [ROB_W-1:0] rob_head, rob_tail;
    logic [ROB_W:0]   rob_count;
    rs_e              rs  [0:RS_DEPTH-1];

    logic             rat_valid [0:31];
    logic [ROB_W-1:0] rat_tag   [0:31];

    logic             jalr_pending;

    logic             fu_valid, fu_taken, fu_is_mem;
    logic [ROB_W-1:0] fu_tag;
    logic [31:0]      fu_res;

    logic             cdb_alu_valid, cdb_mem_valid;
    logic [ROB_W-1:0] cdb_alu_tag,   cdb_mem_tag;
    logic [31:0]      cdb_alu_data,  cdb_mem_data;

    wire [31:0] instr  = imem_rdata_i;
    wire [4:0]  rs1_a  = instr[19:15];
    wire [4:0]  rs2_a  = instr[24:20];
    wire [4:0]  rd_a   = instr[11:7];
    wire [2:0]  f3     = instr[14:12];

    assign imem_addr_o = pc;

    logic                bp_taken;
    logic [31:0]         bp_target;
    logic [BP_IDX_W-1:0]   bp_index;
    logic [BP_GHR_BITS-1:0] bp_ghr;
    logic                  bp_is_branch;

    logic is_jal, is_jalr;

    always_comb begin
        is_jal  = 1'b0;
        is_jalr = 1'b0;
        case (instr[6:0])
            OP_JAL:  is_jal  = 1'b1;
            OP_JALR: is_jalr = 1'b1;
            default: ;
        endcase
    end

    ctrl_t       ctrl;
    logic [31:0] imm;
    logic [31:0] rf_rd0, rf_rd1, rf_rd2;

    control u_control (
        .opcode_i(instr[6:0]), .funct3_i(f3), .funct7_5_i(instr[30]), .ctrl_o(ctrl)
    );

    imm_gen u_imm_gen (.instr_i(instr), .imm_o(imm));

    function automatic src_t lookup(input logic [4:0] a, input logic [31:0] rf_v);
        src_t s;
        s.v  = rf_v;                 // rf already returns 0 for x0
        s.qv = 1'b0;
        s.q  = '0;
        if ((a != 5'd0) && rat_valid[a]) begin
            if (rob[rat_tag[a]].ready) s.v = rob[rat_tag[a]].value;
            else begin s.qv = 1'b1; s.q = rat_tag[a]; end
        end
        if (s.qv && cdb_alu_valid && (cdb_alu_tag == s.q)) begin s.qv = 1'b0; s.v = cdb_alu_data; end
        if (s.qv && cdb_mem_valid && (cdb_mem_tag == s.q)) begin s.qv = 1'b0; s.v = cdb_mem_data; end
        return s;
    endfunction

    src_t src_rs1, src_rs2, vj_src, vk_src;

    always_comb begin
        src_rs1 = lookup(rs1_a, rf_rd0);
        src_rs2 = lookup(rs2_a, rf_rd1);

        case (ctrl.alu_src_a)
            SRC_A_PC:   vj_src = '{v: pc,    qv: 1'b0, q: '0};
            SRC_A_ZERO: vj_src = '{v: 32'd0, qv: 1'b0, q: '0};
            default:    vj_src = src_rs1;
        endcase

        vk_src = (ctrl.alu_src_b == SRC_B_IMM) ? '{v: imm, qv: 1'b0, q: '0} : src_rs2;
    end

    // dispatch
    logic                rs_free_v;
    logic [RS_W-1:0]     rs_free_i;

    always_comb begin
        rs_free_v = 1'b0;
        rs_free_i = '0;
        for (int k = RS_DEPTH-1; k >= 0; k--)
            if (!rs[k].busy) begin rs_free_v = 1'b1; rs_free_i = k[RS_W-1:0]; end
    end

    wire is_mem_op = ctrl.mem_read || ctrl.mem_write;
    wire needs_rs  = !ctrl.jump;          // JAL's result and target are both known now
    wire rob_full  = (rob_count == ROB_DEPTH);

    logic mispredict;

    wire can_disp  = !rob_full && !jalr_pending && !mispredict &&
                     (!needs_rs || rs_free_v);

    logic            issue_v;
    logic [RS_W-1:0] issue_i;

    always_comb begin
        issue_v = 1'b0;
        issue_i = '0;
        for (int k = RS_DEPTH-1; k >= 0; k--)
            if (rs[k].busy && !rs[k].qj_valid && !rs[k].qk_valid) begin
                issue_v = 1'b1;
                issue_i = k[RS_W-1:0];
            end
    end

    rs_e         ie;
    logic [31:0] alu_res;
    logic        br_taken;

    assign ie = rs[issue_i];

    alu u_alu (.alu_op(ie.alu_op), .a(ie.vj), .b(ie.vk), .result(alu_res));

    always_comb begin
        case (ie.funct3)
            3'b000:  br_taken = (ie.vj == ie.vk);
            3'b001:  br_taken = (ie.vj != ie.vk);
            3'b100:  br_taken = ($signed(ie.vj) <  $signed(ie.vk));
            3'b101:  br_taken = ($signed(ie.vj) >= $signed(ie.vk));
            3'b110:  br_taken = (ie.vj <  ie.vk);
            3'b111:  br_taken = (ie.vj >= ie.vk);
            default: br_taken = 1'b0;
        endcase
    end

    assign cdb_alu_valid = fu_valid && !fu_is_mem;
    assign cdb_alu_tag   = fu_tag;
    assign cdb_alu_data  = fu_res;

    // commit
    rob_e h;
    assign h = rob[rob_head];

    wire commit_mem = h.busy && (h.is_load || h.is_store) && h.addr_ready;
    wire commit_alu = h.busy && h.ready && !h.is_load && !h.is_store;
    wire do_commit  = commit_mem || commit_alu;

    wire br_resolve = do_commit && h.is_branch;

    assign mispredict = br_resolve && (h.taken != h.pred_taken);

    branch_predictor #(
        .BP_MODE (BP_MODE)
    ) u_bp (
        .clk              (clk),
        .rst_n            (rst_n),
        .pc_i             (pc),
        .instr_i          (instr),
        .valid_i          (1'b1),
        .is_branch_o      (bp_is_branch),
        .predict_taken_o  (bp_taken),
        .predict_target_o (bp_target),
        .predict_index_o  (bp_index),
        .predict_ghr_o    (bp_ghr),
        .predict_take_i   (can_disp && bp_is_branch),
        .update_valid_i   (br_resolve),
        .update_index_i   (h.pred_index),
        .update_taken_i   (h.taken),
        .recover_valid_i  (mispredict),
        .recover_ghr_i    (h.pred_ghr),
        .recover_taken_i  (h.taken)
    );

    assign dmem_addr_o  = h.value;          // the FU put the address here
    assign dmem_wdata_o = rf_rd2;
    assign dmem_we_o    = commit_mem && h.is_store;

    assign cdb_mem_valid = commit_mem && h.is_load;
    assign cdb_mem_tag   = rob_head;
    assign cdb_mem_data  = dmem_rdata_i;

    wire [31:0] commit_data = h.is_load ? dmem_rdata_i : h.value;

    bp_decode_agrees: assert property (@(posedge clk) disable iff (!rst_n)
        bp_is_branch == ctrl.branch)
      else $error("branch_predictor and control disagree on OP_BRANCH");

    arch_regfile u_rf (
        .clk    (clk),
        .wen    (do_commit && h.reg_write && (h.rd_addr != 5'd0)),
        .raddr0 (rs1_a),
        .raddr1 (rs2_a),
        .raddr2 (h.rs2_addr),
        .waddr  (h.rd_addr),
        .wdata  (commit_data),
        .rdata0 (rf_rd0),
        .rdata1 (rf_rd1),
        .rdata2 (rf_rd2)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc             <= 32'd0;
            rob_head       <= '0;
            rob_tail       <= '0;
            rob_count      <= '0;
            jalr_pending   <= 1'b0;
            fu_valid       <= 1'b0;
            fu_tag         <= '0;
            fu_res         <= '0;
            fu_taken       <= 1'b0;
            fu_is_mem      <= 1'b0;
            for (int k = 0; k < ROB_DEPTH; k++) rob[k] <= '0;
            for (int k = 0; k < RS_DEPTH;  k++) rs[k]  <= '0;
            for (int k = 0; k < 32;        k++) rat_valid[k] <= 1'b0;
        end
        else begin
            fu_valid  <= issue_v;
            fu_tag    <= ie.tag;
            fu_res    <= alu_res;
            fu_taken  <= br_taken;
            fu_is_mem <= ie.is_mem;
            if (issue_v) rs[issue_i].busy <= 1'b0;

            for (int k = 0; k < RS_DEPTH; k++) begin
                if (rs[k].busy) begin
                    if (rs[k].qj_valid && cdb_alu_valid && (rs[k].qj == cdb_alu_tag)) begin
                        rs[k].qj_valid <= 1'b0;  rs[k].vj <= cdb_alu_data;
                    end
                    else if (rs[k].qj_valid && cdb_mem_valid && (rs[k].qj == cdb_mem_tag)) begin
                        rs[k].qj_valid <= 1'b0;  rs[k].vj <= cdb_mem_data;
                    end
                    if (rs[k].qk_valid && cdb_alu_valid && (rs[k].qk == cdb_alu_tag)) begin
                        rs[k].qk_valid <= 1'b0;  rs[k].vk <= cdb_alu_data;
                    end
                    else if (rs[k].qk_valid && cdb_mem_valid && (rs[k].qk == cdb_mem_tag)) begin
                        rs[k].qk_valid <= 1'b0;  rs[k].vk <= cdb_mem_data;
                    end
                end
            end

            if (fu_valid) begin
                rob[fu_tag].value <= fu_res;
                rob[fu_tag].taken <= fu_taken;
                if (fu_is_mem) rob[fu_tag].addr_ready <= 1'b1;
                else           rob[fu_tag].ready      <= 1'b1;
            end

            if (do_commit) begin
                rob[rob_head].busy <= 1'b0;
                rob_head <= rob_head + 1'b1;

                if ((h.rd_addr != 5'd0) && rat_valid[h.rd_addr] &&
                    (rat_tag[h.rd_addr] == rob_head))
                    rat_valid[h.rd_addr] <= 1'b0;

                if (h.is_jalr) begin
                    jalr_pending <= 1'b0;
                    pc           <= h.target;
                end
            end

            if (can_disp) begin
                rob[rob_tail] <= '{ busy       : 1'b1,
                                    ready      : ctrl.jump,     // JAL: pc+4, known now
                                    addr_ready : 1'b0,
                                    is_load    : ctrl.mem_read,
                                    is_store   : ctrl.mem_write,
                                    is_branch  : ctrl.branch,
                                    is_jump    : ctrl.jump,
                                    is_jalr    : is_jalr,
                                    reg_write  : ctrl.reg_write,
                                    taken      : 1'b0,
                                    rd_addr    : rd_a,
                                    rs2_addr   : rs2_a,
                                    value      : pc + 32'd4,    // only used by JAL
                                    target     : pc + imm,
                                    npc        : pc + 32'd4,    // not-taken resume point
                                    pred_taken : bp_taken,
                                    pred_index : bp_index,
                                    pred_ghr   : bp_ghr };
                rob_tail <= rob_tail + 1'b1;

                if (ctrl.reg_write && (rd_a != 5'd0)) begin
                    rat_valid[rd_a] <= 1'b1;
                    rat_tag[rd_a]   <= rob_tail;
                end

                if (needs_rs)
                    rs[rs_free_i] <= '{ busy      : 1'b1,
                                        alu_op    : ctrl.alu_op,
                                        funct3    : f3,
                                        is_branch : ctrl.branch,
                                        is_mem    : is_mem_op,
                                        vj        : vj_src.v,
                                        vk        : vk_src.v,
                                        qj_valid  : vj_src.qv,
                                        qk_valid  : vk_src.qv,
                                        qj        : vj_src.q,
                                        qk        : vk_src.q,
                                        tag       : rob_tail };

                if (is_jalr) jalr_pending <= 1'b1;

                if      (is_jal)   pc <= pc + imm;
                else if (bp_taken) pc <= bp_target;
                else               pc <= pc + 32'd4;
            end

            // 6. occupancy
            case ({can_disp, do_commit})
                2'b10:   rob_count <= rob_count + 1'b1;
                2'b01:   rob_count <= rob_count - 1'b1;
                default: ;
            endcase

            if (mispredict) begin
                for (int k = 0; k < ROB_DEPTH; k++) rob[k].busy   <= 1'b0;
                for (int k = 0; k < RS_DEPTH;  k++) rs[k].busy    <= 1'b0;
                for (int k = 0; k < 32;        k++) rat_valid[k]  <= 1'b0;

                fu_valid  <= 1'b0;                  // kill whatever is in the FU
                rob_tail  <= rob_head + 1'b1;       // head retired this cycle
                rob_count <= '0;
                pc        <= h.taken ? h.target : h.npc;
            end
        end
    end

endmodule

`default_nettype wire
