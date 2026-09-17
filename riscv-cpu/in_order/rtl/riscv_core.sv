// Copyright (c) 2026 Shubham Lonkar
// SPDX-License-Identifier: MIT

`default_nettype none

// riscv_core -- RV32I, 5 stages, in-order

module riscv_core
    import riscv_pkg::*;
#(
    parameter bp_mode_e BP_MODE = BP_GSHARE
) (
    input  wire         clk,
    input  wire         rst_n,

    output logic [31:0] imem_addr_o,
    input  wire  [31:0] imem_rdata_i,

    output logic [31:0] dmem_addr_o,
    output logic [31:0] dmem_wdata_o,
    output logic [3:0]  dmem_be_o,
    output logic        dmem_we_o,
    input  wire  [31:0] dmem_rdata_i
);

    // IF/ID
    logic [31:0] if_id_pc, if_id_pc4, if_id_instr;
    logic        if_id_valid;
    logic                  if_id_pred_taken;
    logic [BP_IDX_W-1:0]   if_id_pred_index;
    logic [BP_GHR_BITS-1:0] if_id_pred_ghr;

    // ID/EX
    logic [31:0] id_ex_pc, id_ex_pc4, id_ex_rs1_data, id_ex_rs2_data, id_ex_imm;
    logic [4:0]  id_ex_rs1_addr, id_ex_rs2_addr, id_ex_rd_addr;
    logic [2:0]  id_ex_funct3;
    ctrl_t       id_ex_ctrl;
    logic        id_ex_valid;
    logic                  id_ex_pred_taken;
    logic [BP_IDX_W-1:0]   id_ex_pred_index;
    logic [BP_GHR_BITS-1:0] id_ex_pred_ghr;

    // EX/MEM
    logic [31:0] ex_mem_alu, ex_mem_rs2, ex_mem_pc4;
    logic [4:0]  ex_mem_rd_addr;
    logic [2:0]  ex_mem_funct3;
    ctrl_t       ex_mem_ctrl;
    logic        ex_mem_valid;

    // MEM/WB
    ctrl_t       mem_wb_ctrl;
    logic [4:0]  mem_wb_rd_addr;
    logic        mem_wb_valid;

    // write port
    logic [4:0]  wb_rd_addr;
    logic [31:0] wb_rd_data;
    logic        wb_we;

    // hazard
    fwd_e        fwd_a, fwd_b;
    logic        stall, flush, redirect_valid;
    logic [31:0] redirect_pc;

    // predictor update, EX -> IF
    logic                  bp_update_valid, bp_update_taken;
    logic [BP_IDX_W-1:0]   bp_update_index;
    logic                  bp_recover_valid, bp_recover_taken;
    logic [BP_GHR_BITS-1:0] bp_recover_ghr;

    if_stage #(.BP_MODE(BP_MODE)) u_if (
        .clk(clk), .rst_n(rst_n),
        .stall_i(stall),
        .redirect_valid_i(redirect_valid),
        .redirect_pc_i(redirect_pc),
        .flush_i(flush),
        .imem_addr_o(imem_addr_o),
        .imem_rdata_i(imem_rdata_i),
        .if_id_pc_o(if_id_pc),
        .if_id_pc4_o(if_id_pc4),
        .if_id_instr_o(if_id_instr),
        .if_id_valid_o(if_id_valid),
        .if_id_pred_taken_o(if_id_pred_taken),
        .if_id_pred_index_o(if_id_pred_index),
        .if_id_pred_ghr_o(if_id_pred_ghr),
        .bp_update_valid_i(bp_update_valid),
        .bp_update_index_i(bp_update_index),
        .bp_update_taken_i(bp_update_taken),
        .bp_recover_valid_i(bp_recover_valid),
        .bp_recover_ghr_i(bp_recover_ghr),
        .bp_recover_taken_i(bp_recover_taken)
    );

    id_stage u_id (
        .clk(clk), .rst_n(rst_n),
        .if_id_pc_i(if_id_pc),
        .if_id_pc4_i(if_id_pc4),
        .if_id_instr_i(if_id_instr),
        .if_id_valid_i(if_id_valid),
        .if_id_pred_taken_i(if_id_pred_taken),
        .if_id_pred_index_i(if_id_pred_index),
        .if_id_pred_ghr_i(if_id_pred_ghr),
        .stall_i(stall),
        .flush_i(flush),
        .wb_rd_addr_i(wb_rd_addr),
        .wb_rd_data_i(wb_rd_data),
        .wb_we_i(wb_we),
        .id_ex_pc_o(id_ex_pc),
        .id_ex_pc4_o(id_ex_pc4),
        .id_ex_rs1_data_o(id_ex_rs1_data),
        .id_ex_rs2_data_o(id_ex_rs2_data),
        .id_ex_imm_o(id_ex_imm),
        .id_ex_rs1_addr_o(id_ex_rs1_addr),
        .id_ex_rs2_addr_o(id_ex_rs2_addr),
        .id_ex_rd_addr_o(id_ex_rd_addr),
        .id_ex_funct3_o(id_ex_funct3),
        .id_ex_ctrl_o(id_ex_ctrl),
        .id_ex_valid_o(id_ex_valid),
        .id_ex_pred_taken_o(id_ex_pred_taken),
        .id_ex_pred_index_o(id_ex_pred_index),
        .id_ex_pred_ghr_o(id_ex_pred_ghr)
    );

    ex_stage u_ex (
        .clk(clk), .rst_n(rst_n),
        .id_ex_pc_i(id_ex_pc),
        .id_ex_pc4_i(id_ex_pc4),
        .id_ex_rs1_data_i(id_ex_rs1_data),
        .id_ex_rs2_data_i(id_ex_rs2_data),
        .id_ex_imm_i(id_ex_imm),
        .id_ex_rd_addr_i(id_ex_rd_addr),
        .id_ex_funct3_i(id_ex_funct3),
        .id_ex_ctrl_i(id_ex_ctrl),
        .id_ex_valid_i(id_ex_valid),
        .id_ex_pred_taken_i(id_ex_pred_taken),
        .id_ex_pred_index_i(id_ex_pred_index),
        .id_ex_pred_ghr_i(id_ex_pred_ghr),
        .fwd_a_i(fwd_a),
        .fwd_b_i(fwd_b),
        .ex_mem_fwd_i(ex_mem_alu),
        .mem_wb_fwd_i(wb_rd_data),
        .ex_mem_alu_o(ex_mem_alu),
        .ex_mem_rs2_o(ex_mem_rs2),
        .ex_mem_pc4_o(ex_mem_pc4),
        .ex_mem_rd_addr_o(ex_mem_rd_addr),
        .ex_mem_funct3_o(ex_mem_funct3),
        .ex_mem_ctrl_o(ex_mem_ctrl),
        .ex_mem_valid_o(ex_mem_valid),
        .redirect_valid_o(redirect_valid),
        .redirect_pc_o(redirect_pc),
        .bp_update_valid_o(bp_update_valid),
        .bp_update_index_o(bp_update_index),
        .bp_update_taken_o(bp_update_taken),
        .bp_recover_valid_o(bp_recover_valid),
        .bp_recover_ghr_o(bp_recover_ghr),
        .bp_recover_taken_o(bp_recover_taken)
    );

    mem_wb_stage u_mem_wb (
        .clk(clk), .rst_n(rst_n),
        .ex_mem_alu_i(ex_mem_alu),
        .ex_mem_rs2_i(ex_mem_rs2),
        .ex_mem_pc4_i(ex_mem_pc4),
        .ex_mem_rd_addr_i(ex_mem_rd_addr),
        .ex_mem_funct3_i(ex_mem_funct3),
        .ex_mem_ctrl_i(ex_mem_ctrl),
        .ex_mem_valid_i(ex_mem_valid),
        .dmem_addr_o(dmem_addr_o),
        .dmem_wdata_o(dmem_wdata_o),
        .dmem_be_o(dmem_be_o),
        .dmem_we_o(dmem_we_o),
        .dmem_rdata_i(dmem_rdata_i),
        .wb_rd_addr_o(wb_rd_addr),
        .wb_rd_data_o(wb_rd_data),
        .wb_we_o(wb_we),
        .mem_wb_ctrl_o(mem_wb_ctrl),
        .mem_wb_rd_addr_o(mem_wb_rd_addr),
        .mem_wb_valid_o(mem_wb_valid)
    );

    hazard_unit u_hazard (
        .id_ex_rs1_addr_i(id_ex_rs1_addr),
        .id_ex_rs2_addr_i(id_ex_rs2_addr),
        .ex_mem_rd_addr_i(ex_mem_rd_addr),
        .ex_mem_ctrl_i(ex_mem_ctrl),
        .ex_mem_valid_i(ex_mem_valid),
        .mem_wb_rd_addr_i(mem_wb_rd_addr),
        .mem_wb_ctrl_i(mem_wb_ctrl),
        .mem_wb_valid_i(mem_wb_valid),
        .id_ex_rd_addr_i(id_ex_rd_addr),
        .id_ex_ctrl_i(id_ex_ctrl),
        .id_ex_valid_i(id_ex_valid),
        .if_id_rs1_addr_i(if_id_instr[19:15]),
        .if_id_rs2_addr_i(if_id_instr[24:20]),
        .redirect_valid_i(redirect_valid),
        .fwd_a_o(fwd_a),
        .fwd_b_o(fwd_b),
        .stall_o(stall),
        .flush_o(flush)
    );

endmodule

`default_nettype wire
