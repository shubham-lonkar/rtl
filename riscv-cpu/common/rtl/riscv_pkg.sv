// Copyright (c) 2026 Shubham Lonkar
// SPDX-License-Identifier: MIT

`ifndef BP_IDX_W_DEF
  `define BP_IDX_W_DEF 10
`endif
`ifndef BP_GHR_BITS_DEF
  `define BP_GHR_BITS_DEF 4
`endif
`ifndef BP_CTR_BITS_DEF
  `define BP_CTR_BITS_DEF 2
`endif

// riscv_pkg -- shared encodings and the control bundle

package riscv_pkg;

    // RV32I opcodes
    localparam logic [6:0] OP_R      = 7'b0110011;
    localparam logic [6:0] OP_I      = 7'b0010011;
    localparam logic [6:0] OP_LOAD   = 7'b0000011;
    localparam logic [6:0] OP_STORE  = 7'b0100011;
    localparam logic [6:0] OP_BRANCH = 7'b1100011;
    localparam logic [6:0] OP_JAL    = 7'b1101111;
    localparam logic [6:0] OP_JALR   = 7'b1100111;
    localparam logic [6:0] OP_LUI    = 7'b0110111;
    localparam logic [6:0] OP_AUIPC  = 7'b0010111;

    localparam logic [3:0] ALU_ADD  = 4'b0000;
    localparam logic [3:0] ALU_SUB  = 4'b1000;

    localparam logic [2:0] MEM_B  = 3'b000;
    localparam logic [2:0] MEM_H  = 3'b001;
    localparam logic [2:0] MEM_W  = 3'b010;
    localparam logic [2:0] MEM_BU = 3'b100;
    localparam logic [2:0] MEM_HU = 3'b101;

    typedef enum logic [1:0] { FWD_NONE, FWD_EX_MEM, FWD_MEM_WB } fwd_e;

    typedef enum logic [1:0] { SRC_A_RS1, SRC_A_PC,  SRC_A_ZERO } alu_src_a_e;
    typedef enum logic       { SRC_B_RS2, SRC_B_IMM              } alu_src_b_e;
    typedef enum logic [1:0] { WB_ALU,    WB_LOAD,   WB_PC4      } wb_sel_e;

    // Control bundle, 14 bits
    typedef struct packed {
        logic       reg_write;
        alu_src_a_e alu_src_a;
        alu_src_b_e alu_src_b;
        logic [3:0] alu_op;
        logic       mem_read;
        logic       mem_write;
        wb_sel_e    wb_sel;
        logic       branch;      // conditional redirect -- EX evaluates
        logic       jump;        // unconditional redirect
    } ctrl_t;

    localparam ctrl_t CTRL_NOP = '{
        reg_write : 1'b0,
        alu_src_a : SRC_A_RS1,
        alu_src_b : SRC_B_RS2,
        alu_op    : ALU_ADD,
        mem_read  : 1'b0,
        mem_write : 1'b0,
        wb_sel    : WB_ALU,
        branch    : 1'b0,
        jump      : 1'b0
    };

    typedef enum logic [1:0] {
        BP_BIMODAL,   // PC only -- no global history
        BP_GSELECT,   // {PC[hi], GHR} concatenated
        BP_GSHARE     // PC ^ GHR
    } bp_mode_e;

    localparam int BP_IDX_W     = `BP_IDX_W_DEF;
    localparam int BP_BHT_DEPTH = 1 << BP_IDX_W;
    localparam int BP_GHR_BITS  = `BP_GHR_BITS_DEF;
    localparam int BP_CTR_BITS  = `BP_CTR_BITS_DEF;

endpackage
