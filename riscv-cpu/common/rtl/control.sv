// Copyright (c) 2026 Shubham Lonkar
// SPDX-License-Identifier: MIT

`default_nettype none

// control -- opcode to control-bundle decode, pure combinational

module control
    import riscv_pkg::*;
(
    input  wire  [6:0] opcode_i,
    input  wire  [2:0] funct3_i,
    input  wire        funct7_5_i,   // instr[30]
    output ctrl_t      ctrl_o
);

    logic       alt_op;
    logic [3:0] alu_op_funct;

    assign alt_op       = funct7_5_i && ((opcode_i == OP_R) ||
                                         (opcode_i == OP_I && funct3_i == 3'b101));
    assign alu_op_funct = {alt_op, funct3_i};

    always_comb begin
        ctrl_o = CTRL_NOP;

        case (opcode_i)
            OP_R: begin
                ctrl_o.reg_write = 1'b1;
                ctrl_o.alu_op    = alu_op_funct;
            end

            // Same as R-type but operand B is the immediate.
            OP_I: begin
                ctrl_o.reg_write = 1'b1;
                ctrl_o.alu_src_b = SRC_B_IMM;
                ctrl_o.alu_op    = alu_op_funct;
            end

            OP_LOAD: begin
                ctrl_o.reg_write = 1'b1;
                ctrl_o.alu_src_b = SRC_B_IMM;
                ctrl_o.mem_read  = 1'b1;
                ctrl_o.wb_sel    = WB_LOAD;
            end

            OP_STORE: begin
                ctrl_o.alu_src_b = SRC_B_IMM;
                ctrl_o.mem_write = 1'b1;
            end

            OP_BRANCH: begin
                ctrl_o.branch = 1'b1;
            end

            OP_JAL: begin
                ctrl_o.reg_write = 1'b1;
                ctrl_o.alu_src_a = SRC_A_PC;
                ctrl_o.alu_src_b = SRC_B_IMM;
                ctrl_o.wb_sel    = WB_PC4;
                ctrl_o.jump      = 1'b1;
            end

            OP_JALR: begin
                ctrl_o.reg_write = 1'b1;
                ctrl_o.alu_src_b = SRC_B_IMM;
                ctrl_o.wb_sel    = WB_PC4;
                ctrl_o.jump      = 1'b1;
            end

            OP_LUI: begin
                ctrl_o.reg_write = 1'b1;
                ctrl_o.alu_src_a = SRC_A_ZERO;
                ctrl_o.alu_src_b = SRC_B_IMM;
            end

            OP_AUIPC: begin
                ctrl_o.reg_write = 1'b1;
                ctrl_o.alu_src_a = SRC_A_PC;
                ctrl_o.alu_src_b = SRC_B_IMM;
            end

            default: ctrl_o = CTRL_NOP;   // illegal opcode retires as a NOP (§4)
        endcase
    end

endmodule

`default_nettype wire
