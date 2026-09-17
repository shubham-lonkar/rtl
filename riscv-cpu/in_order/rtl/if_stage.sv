// Copyright (c) 2026 Shubham Lonkar
// SPDX-License-Identifier: MIT

`default_nettype none

// if_stage -- RV32I instruction fetch, owns the PC and the IF/ID register

module if_stage
    import riscv_pkg::*;
#(
    parameter bp_mode_e BP_MODE = BP_GSHARE
) (
    input  wire         clk,
    input  wire         rst_n,               // async assert, sync deassert (synchronizer is external)

    input  wire         stall_i,             // load-use hazard: hold PC and IF/ID
    input  wire         redirect_valid_i,    // EX resolved a mispredict or a jump
    input  wire [31:0]  redirect_pc_i,       // target to fetch from
    input  wire         flush_i,             // kill the instruction currently in IF/ID

    output logic [31:0]  imem_addr_o,         // byte address to instruction memory
    input  wire [31:0]  imem_rdata_i,        // instruction returned combinationally

    // predictor update, from EX
    input  wire                 bp_update_valid_i,
    input  wire [BP_IDX_W-1:0]  bp_update_index_i,
    input  wire                 bp_update_taken_i,

    input  wire                   bp_recover_valid_i,
    input  wire [BP_GHR_BITS-1:0] bp_recover_ghr_i,
    input  wire                   bp_recover_taken_i,

    output logic [31:0]  if_id_pc_o,          // PC of the instruction in IF/ID
    output logic [31:0]  if_id_pc4_o,         // pc+4, link value for JAL/JALR
    output logic [31:0]  if_id_instr_o,       // instruction in IF/ID
    output logic         if_id_valid_o,       // 0 = bubble

    output logic                   if_id_pred_taken_o,
    output logic [BP_IDX_W-1:0]    if_id_pred_index_o,
    output logic [BP_GHR_BITS-1:0] if_id_pred_ghr_o
);

    localparam logic [31:0] RESET_PC = 32'h0000_0000;   // boot address

    logic [31:0] pc;                                    // architectural fetch pointer
    logic [31:0] pc_plus4;                              // next sequential address
    logic [31:0] next_pc;                               // value the PC takes at the next edge

    assign pc_plus4 = pc + 32'd4;

    assign imem_addr_o = pc;

    logic                  bp_taken;
    logic [31:0]           bp_target;
    logic [BP_IDX_W-1:0]   bp_index;
    logic [BP_GHR_BITS-1:0] bp_ghr;
    logic                  bp_is_branch;

    logic bp_take;

    assign bp_take = bp_is_branch && !stall_i && !redirect_valid_i;

    branch_predictor #(
        .BP_MODE (BP_MODE)
    ) u_bp (
        .clk              (clk),
        .rst_n            (rst_n),
        .pc_i             (pc),
        .instr_i          (imem_rdata_i),
        .valid_i          (1'b1),
        .is_branch_o      (bp_is_branch),
        .predict_taken_o  (bp_taken),
        .predict_target_o (bp_target),
        .predict_index_o  (bp_index),
        .predict_ghr_o    (bp_ghr),
        .predict_take_i   (bp_take),
        .update_valid_i   (bp_update_valid_i),
        .update_index_i   (bp_update_index_i),
        .update_taken_i   (bp_update_taken_i),
        .recover_valid_i  (bp_recover_valid_i),
        .recover_ghr_i    (bp_recover_ghr_i),
        .recover_taken_i  (bp_recover_taken_i)
    );

    always_comb begin
        if      (redirect_valid_i) next_pc = redirect_pc_i;
        else if (bp_taken)         next_pc = bp_target;
        else                       next_pc = pc_plus4;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pc <= RESET_PC;
        else if (!stall_i || redirect_valid_i)          // update, or forced by a redirect
            pc <= next_pc;
        else
            pc <= pc;                                   // stalled: hold
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_id_pc_o         <= 32'd0;
            if_id_pc4_o        <= 32'd0;
            if_id_instr_o      <= 32'd0;
            if_id_valid_o      <= 1'b0;                 // valid=0 means bubble
            if_id_pred_taken_o <= 1'b0;
            if_id_pred_index_o <= '0;
            if_id_pred_ghr_o   <= '0;
        end
        else if (flush_i) begin                         // wrong-path: capture, then mark dead
            if_id_pc_o         <= pc;
            if_id_pc4_o        <= pc_plus4;
            if_id_instr_o      <= imem_rdata_i;
            if_id_valid_o      <= 1'b0;                 // only this bit matters; the rest are don't-care
            if_id_pred_taken_o <= 1'b0;
            if_id_pred_index_o <= bp_index;
            if_id_pred_ghr_o   <= bp_ghr;
        end
        else if (!stall_i) begin                        // normal capture
            if_id_pc_o         <= pc;
            if_id_pc4_o        <= pc_plus4;
            if_id_instr_o      <= imem_rdata_i;         // note: rdata (in), not addr (out)
            if_id_valid_o      <= 1'b1;
            if_id_pred_taken_o <= bp_taken;
            if_id_pred_index_o <= bp_index;
            if_id_pred_ghr_o   <= bp_ghr;
        end
        // no else: stalled and not flushed -> hold
    end

endmodule

`default_nettype wire
