// Copyright (c) 2026 Shubham Lonkar
// SPDX-License-Identifier: MIT

`default_nettype none

// riscv_cov -- functional coverage, bound into the core

module riscv_cov
    import riscv_pkg::*;
(
    input wire         clk,
    input wire         rst_n,

    input wire  ctrl_t id_ex_ctrl,
    input wire         id_ex_valid,
    input wire  fwd_e  fwd_a,
    input wire  fwd_e  fwd_b,
    input wire         stall,
    input wire         redirect_valid,

    input wire  [31:0] ex_mem_alu,
    input wire  [2:0]  ex_mem_funct3,
    input wire  ctrl_t ex_mem_ctrl,
    input wire         ex_mem_valid,

    input wire  [2:0]  id_ex_funct3
);

    typedef enum { C_R, C_I, C_LOAD, C_STORE, C_BRANCH,
                   C_JAL, C_JALR, C_LUI, C_AUIPC } instr_class_e;

    function automatic instr_class_e classify(ctrl_t c);
        if (c.branch)                     return C_BRANCH;
        if (c.jump)                       return (c.alu_src_a == SRC_A_PC) ? C_JAL : C_JALR;
        if (c.mem_read)                   return C_LOAD;
        if (c.mem_write)                  return C_STORE;
        if (c.alu_src_a == SRC_A_ZERO)    return C_LUI;
        if (c.alu_src_a == SRC_A_PC)      return C_AUIPC;
        if (c.alu_src_b == SRC_B_IMM)     return C_I;
        return C_R;
    endfunction

    instr_class_e ex_class;
    assign ex_class = classify(id_ex_ctrl);

    // execute
    covergroup cg_exec @(posedge clk iff (rst_n && id_ex_valid));
        cp_class: coverpoint ex_class;

        cp_fwd_a: coverpoint fwd_a {
            bins none    = {FWD_NONE};
            bins ex_mem  = {FWD_EX_MEM};
            bins mem_wb  = {FWD_MEM_WB};
        }
        cp_fwd_b: coverpoint fwd_b {
            bins none    = {FWD_NONE};
            bins ex_mem  = {FWD_EX_MEM};
            bins mem_wb  = {FWD_MEM_WB};
        }

        x_class_fwd_a: cross cp_class, cp_fwd_a {
            ignore_bins no_rs1 = binsof(cp_class) intersect {C_LUI, C_AUIPC, C_JAL} &&
                                 binsof(cp_fwd_a) intersect {FWD_EX_MEM, FWD_MEM_WB};
        }
        x_class_fwd_b: cross cp_class, cp_fwd_b {
            ignore_bins no_rs2 = binsof(cp_class) intersect
                                     {C_I, C_LOAD, C_JALR, C_LUI, C_AUIPC, C_JAL} &&
                                 binsof(cp_fwd_b) intersect {FWD_EX_MEM, FWD_MEM_WB};
        }
    endgroup

    // hazard
    covergroup cg_hazard @(posedge clk iff rst_n);
        cp_stall:    coverpoint stall    { bins quiet = {0}; bins fired = {1}; }
        cp_redirect: coverpoint redirect_valid { bins quiet = {0}; bins fired = {1}; }
    endgroup

    wire mem_op = ex_mem_valid && (ex_mem_ctrl.mem_read || ex_mem_ctrl.mem_write);

    covergroup cg_mem @(posedge clk iff (rst_n && mem_op));
        cp_dir: coverpoint ex_mem_ctrl.mem_read {
            bins store = {0};
            bins load  = {1};
        }

        cp_width: coverpoint ex_mem_funct3 {
            bins b  = {MEM_B};
            bins h  = {MEM_H};
            bins w  = {MEM_W};
            bins bu = {MEM_BU};
            bins hu = {MEM_HU};
        }

        cp_offset: coverpoint ex_mem_alu[1:0] {
            bins off0 = {2'b00};
            bins off1 = {2'b01};
            bins off2 = {2'b10};
            bins off3 = {2'b11};
        }

        x_width_offset: cross cp_width, cp_offset {
            ignore_bins half_misaligned = binsof(cp_width) intersect {MEM_H, MEM_HU} &&
                                          binsof(cp_offset) intersect {2'b01, 2'b11};
            ignore_bins word_misaligned = binsof(cp_width) intersect {MEM_W} &&
                                          binsof(cp_offset) intersect {2'b01, 2'b10, 2'b11};
        }

        x_dir_width: cross cp_dir, cp_width {
            ignore_bins store_unsigned = binsof(cp_dir.store) &&
                                         binsof(cp_width) intersect {MEM_BU, MEM_HU};
        }
    endgroup

    wire branch_resolves = id_ex_valid && id_ex_ctrl.branch;

    covergroup cg_branch @(posedge clk iff (rst_n && branch_resolves));
        cp_cond: coverpoint id_ex_funct3 {
            bins beq  = {3'b000};
            bins bne  = {3'b001};
            bins blt  = {3'b100};
            bins bge  = {3'b101};
            bins bltu = {3'b110};
            bins bgeu = {3'b111};
        }
        cp_mispredict: coverpoint redirect_valid {
            bins correct = {0};
            bins wrong   = {1};
        }
        x_cond_mispredict: cross cp_cond, cp_mispredict;
    endgroup

    cg_exec   exec_cov   = new();
    cg_hazard hazard_cov = new();
    cg_mem    mem_cov    = new();
    cg_branch branch_cov = new();

    function automatic void report();
        $display("\n--- functional coverage ---");
        $display("  execute (class x forwarding) : %5.1f%%", exec_cov.get_coverage());
        $display("      class                    : %5.1f%%", exec_cov.cp_class.get_coverage());
        $display("      cross class x fwd_a      : %5.1f%%", exec_cov.x_class_fwd_a.get_coverage());
        $display("      cross class x fwd_b      : %5.1f%%", exec_cov.x_class_fwd_b.get_coverage());
        $display("  hazard  (stall, redirect)    : %5.1f%%", hazard_cov.get_coverage());
        $display("  memory  (width x offset)     : %5.1f%%", mem_cov.get_coverage());
        $display("      cross width x offset     : %5.1f%%", mem_cov.x_width_offset.get_coverage());
        $display("  branch  (cond x mispredict)  : %5.1f%%", branch_cov.get_coverage());
        $display("  overall                      : %5.1f%%", $get_coverage());
    endfunction

endmodule

bind riscv_core riscv_cov u_cov (.*);

`default_nettype wire
