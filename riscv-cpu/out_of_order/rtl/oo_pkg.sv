// Copyright (c) 2026 Shubham Lonkar
// SPDX-License-Identifier: MIT

// oo_pkg -- the two out-of-order structures and the machine's size

package oo_pkg;

    import riscv_pkg::*;

    localparam int ROB_DEPTH = 8;
    localparam int ROB_W     = 3;
    localparam int RS_DEPTH  = 4;
    localparam int RS_W      = 2;

    typedef struct packed {
        logic        busy;
        logic        ready;        // architectural result available
        logic        addr_ready;   // mem ops only: address computed
        logic        is_load;
        logic        is_store;
        logic        is_branch;
        logic        is_jump;
        logic        is_jalr;      // unsupported (§5); kept apart from JAL so
        logic        reg_write;
        logic        taken;        // resolved direction, written at writeback
        logic [4:0]  rd_addr;
        logic [4:0]  rs2_addr;     // store data, read from the arch RF at commit
        logic [31:0] value;
        logic [31:0] target;       // known at dispatch: pc + imm
        logic [31:0] npc;          // pc + 4: where a not-taken branch resumes
        logic                    pred_taken;
        logic [BP_IDX_W-1:0]     pred_index;   // BHT entry read at predict time
        logic [BP_GHR_BITS-1:0]  pred_ghr;     // speculative GHR as it was then
    } rob_e;

    typedef struct packed {
        logic             busy;
        logic [3:0]       alu_op;
        logic [2:0]       funct3;
        logic             is_branch;
        logic             is_mem;
        logic [31:0]      vj;
        logic [31:0]      vk;
        logic             qj_valid;
        logic             qk_valid;
        logic [ROB_W-1:0] qj;
        logic [ROB_W-1:0] qk;
        logic [ROB_W-1:0] tag;     // destination ROB entry
    } rs_e;

    typedef struct packed {
        logic [31:0]      v;
        logic             qv;
        logic [ROB_W-1:0] q;
    } src_t;

endpackage
