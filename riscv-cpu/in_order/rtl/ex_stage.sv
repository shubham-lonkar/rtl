// Copyright (c) 2026 Shubham Lonkar
// SPDX-License-Identifier: MIT

`default_nettype none

// ex_stage -- operand selection, the ALU, branch resolution, and EX/MEM

module ex_stage
    import riscv_pkg::*;
(
    input  wire         clk,
    input  wire         rst_n,

    // ID/EX
    input  wire  [31:0] id_ex_pc_i,
    input  wire  [31:0] id_ex_pc4_i,
    input  wire  [31:0] id_ex_rs1_data_i,
    input  wire  [31:0] id_ex_rs2_data_i,
    input  wire  [31:0] id_ex_imm_i,
    input  wire  [4:0]  id_ex_rd_addr_i,
    input  wire  [2:0]  id_ex_funct3_i,
    input  wire  ctrl_t id_ex_ctrl_i,
    input  wire         id_ex_valid_i,

    input  wire                   id_ex_pred_taken_i,
    input  wire [BP_IDX_W-1:0]    id_ex_pred_index_i,
    input  wire [BP_GHR_BITS-1:0] id_ex_pred_ghr_i,

    // forwarding, from hazard_unit
    input  wire  fwd_e  fwd_a_i,
    input  wire  fwd_e  fwd_b_i,
    input  wire  [31:0] ex_mem_fwd_i,     // EX/MEM alu_result
    input  wire  [31:0] mem_wb_fwd_i,     // WB mux output

    // EX/MEM
    output logic [31:0] ex_mem_alu_o,
    output logic [31:0] ex_mem_rs2_o,     // store data
    output logic [31:0] ex_mem_pc4_o,
    output logic [4:0]  ex_mem_rd_addr_o,
    output logic [2:0]  ex_mem_funct3_o,  // load/store width, for MEM's aligner
    output ctrl_t       ex_mem_ctrl_o,
    output logic        ex_mem_valid_o,

    // to if_stage
    output logic        redirect_valid_o,
    output logic [31:0] redirect_pc_o,

    output logic                 bp_update_valid_o,
    output logic [BP_IDX_W-1:0]  bp_update_index_o,
    output logic                 bp_update_taken_o,

    output logic                   bp_recover_valid_o,
    output logic [BP_GHR_BITS-1:0] bp_recover_ghr_o,
    output logic                   bp_recover_taken_o
);

    logic [31:0] rs1_fwd, rs2_fwd, alu_a, alu_b, alu_result;
    logic        br_taken;

    always_comb begin
        case (fwd_a_i)
            FWD_EX_MEM: rs1_fwd = ex_mem_fwd_i;
            FWD_MEM_WB: rs1_fwd = mem_wb_fwd_i;
            default:    rs1_fwd = id_ex_rs1_data_i;
        endcase
        case (fwd_b_i)
            FWD_EX_MEM: rs2_fwd = ex_mem_fwd_i;
            FWD_MEM_WB: rs2_fwd = mem_wb_fwd_i;
            default:    rs2_fwd = id_ex_rs2_data_i;
        endcase
    end

    always_comb begin
        case (id_ex_ctrl_i.alu_src_a)
            SRC_A_PC:   alu_a = id_ex_pc_i;
            SRC_A_ZERO: alu_a = 32'd0;
            default:    alu_a = rs1_fwd;
        endcase
    end

    assign alu_b = (id_ex_ctrl_i.alu_src_b == SRC_B_IMM) ? id_ex_imm_i : rs2_fwd;

    alu u_alu (
        .alu_op (id_ex_ctrl_i.alu_op),
        .a      (alu_a),
        .b      (alu_b),
        .result (alu_result)
    );

    always_comb begin
        case (id_ex_funct3_i)
            3'b000:  br_taken = (rs1_fwd == rs2_fwd);                    // BEQ
            3'b001:  br_taken = (rs1_fwd != rs2_fwd);                    // BNE
            3'b100:  br_taken = ($signed(rs1_fwd) <  $signed(rs2_fwd));  // BLT
            3'b101:  br_taken = ($signed(rs1_fwd) >= $signed(rs2_fwd));  // BGE
            3'b110:  br_taken = (rs1_fwd <  rs2_fwd);                    // BLTU
            3'b111:  br_taken = (rs1_fwd >= rs2_fwd);                    // BGEU
            default: br_taken = 1'b0;
        endcase
    end

    logic mispredict;

    assign mispredict = id_ex_ctrl_i.branch && (br_taken != id_ex_pred_taken_i);

    assign redirect_valid_o = id_ex_valid_i && (id_ex_ctrl_i.jump || mispredict);

    assign redirect_pc_o = id_ex_ctrl_i.jump ? {alu_result[31:1], 1'b0}
                         : br_taken          ? (id_ex_pc_i + id_ex_imm_i)
                         :                     id_ex_pc4_i;

    assign bp_update_valid_o = id_ex_valid_i && id_ex_ctrl_i.branch;
    assign bp_update_index_o = id_ex_pred_index_i;
    assign bp_update_taken_o = br_taken;

    assign bp_recover_valid_o = id_ex_valid_i && mispredict;
    assign bp_recover_ghr_o   = id_ex_pred_ghr_i;
    assign bp_recover_taken_o = br_taken;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_mem_alu_o     <= '0;
            ex_mem_rs2_o     <= '0;
            ex_mem_pc4_o     <= '0;
            ex_mem_rd_addr_o <= '0;
            ex_mem_funct3_o  <= '0;
            ex_mem_ctrl_o    <= CTRL_NOP;
            ex_mem_valid_o   <= 1'b0;
        end
        else begin
            ex_mem_alu_o     <= alu_result;
            ex_mem_rs2_o     <= rs2_fwd;
            ex_mem_pc4_o     <= id_ex_pc4_i;
            ex_mem_rd_addr_o <= id_ex_rd_addr_i;
            ex_mem_funct3_o  <= id_ex_funct3_i;
            ex_mem_ctrl_o    <= id_ex_ctrl_i;
            ex_mem_valid_o   <= id_ex_valid_i;
        end
    end

endmodule

`default_nettype wire
