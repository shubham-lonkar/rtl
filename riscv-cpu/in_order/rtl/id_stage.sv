// Copyright (c) 2026 Shubham Lonkar
// SPDX-License-Identifier: MIT

`default_nettype none

// id_stage -- instantiates regfile / imm_gen / control and owns the ID/EX register

module id_stage
    import riscv_pkg::*;
(
    input  wire         clk,
    input  wire         rst_n,

    // from IF
    input  wire  [31:0] if_id_pc_i,
    input  wire  [31:0] if_id_pc4_i,
    input  wire  [31:0] if_id_instr_i,
    input  wire         if_id_valid_i,

    input  wire                   if_id_pred_taken_i,
    input  wire [BP_IDX_W-1:0]    if_id_pred_index_i,
    input  wire [BP_GHR_BITS-1:0] if_id_pred_ghr_i,

    input  wire         stall_i,        // load-use: IF/ID holds, ID/EX drains
    input  wire         flush_i,        // taken branch/jump from EX

    // write port, from WB
    input  wire  [4:0]  wb_rd_addr_i,
    input  wire  [31:0] wb_rd_data_i,
    input  wire         wb_we_i,

    // ID/EX
    output logic [31:0] id_ex_pc_o,
    output logic [31:0] id_ex_pc4_o,
    output logic [31:0] id_ex_rs1_data_o,
    output logic [31:0] id_ex_rs2_data_o,
    output logic [31:0] id_ex_imm_o,
    output logic [4:0]  id_ex_rs1_addr_o,   // for the forwarding unit
    output logic [4:0]  id_ex_rs2_addr_o,
    output logic [4:0]  id_ex_rd_addr_o,
    output logic [2:0]  id_ex_funct3_o,     // load/store width, branch condition
    output ctrl_t       id_ex_ctrl_o,
    output logic        id_ex_valid_o,
    output logic                   id_ex_pred_taken_o,
    output logic [BP_IDX_W-1:0]    id_ex_pred_index_o,
    output logic [BP_GHR_BITS-1:0] id_ex_pred_ghr_o
);

    logic [4:0] rs1_addr, rs2_addr, rd_addr;
    logic [2:0] funct3;

    assign rs1_addr = if_id_instr_i [19:15];
    assign rs2_addr = if_id_instr_i [24:20];
    assign rd_addr = if_id_instr_i [11:7];
    assign funct3 = if_id_instr_i [14:12];

    logic [31:0] rs1_data, rs2_data, imm;
    ctrl_t       ctrl;

    regfile u_regfile (
        .clk    (clk),
        .wen    (wb_we_i),
        .raddr0 (rs1_addr),
        .raddr1 (rs2_addr),
        .waddr  (wb_rd_addr_i),
        .wdata  (wb_rd_data_i),
        .rdata0 (rs1_data),
        .rdata1 (rs2_data)
    );

    imm_gen u_imm_gen (
        .instr_i(if_id_instr_i),
        .imm_o(imm)
    );

    control u_control (
        .opcode_i(if_id_instr_i[6:0]),
        .funct3_i(funct3),
        .funct7_5_i(if_id_instr_i[30]),   // instr[30]
        .ctrl_o(ctrl)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_ex_pc_o <= '0;
            id_ex_pc4_o <= '0;
            id_ex_rs1_data_o <= '0;
            id_ex_rs2_data_o <= '0;
            id_ex_imm_o     <= '0;
            id_ex_rs1_addr_o <= '0;
            id_ex_rs2_addr_o <= '0;
            id_ex_rd_addr_o <= '0;
            id_ex_funct3_o <= '0;
            id_ex_ctrl_o <= '0;
            id_ex_valid_o <= '0;
            id_ex_pred_taken_o <= '0;
            id_ex_pred_index_o <= '0;
            id_ex_pred_ghr_o   <= '0;
        end
        else begin
            id_ex_pc_o <= if_id_pc_i;
            id_ex_pc4_o <= if_id_pc4_i;
            id_ex_rs1_data_o <= rs1_data;
            id_ex_rs2_data_o <= rs2_data;
            id_ex_imm_o     <= imm;
            id_ex_rs1_addr_o <= rs1_addr;
            id_ex_rs2_addr_o <= rs2_addr;
            id_ex_rd_addr_o <= rd_addr;
            id_ex_funct3_o <= funct3;
            id_ex_ctrl_o <= ctrl;
            id_ex_valid_o <= if_id_valid_i && !stall_i && !flush_i;
            id_ex_pred_taken_o <= if_id_pred_taken_i;
            id_ex_pred_index_o <= if_id_pred_index_i;
            id_ex_pred_ghr_o   <= if_id_pred_ghr_i;
        end
    end

endmodule

`default_nettype wire
