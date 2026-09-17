// Copyright (c) 2026 Shubham Lonkar
// SPDX-License-Identifier: MIT

`default_nettype none

// hazard_unit -- all hazard policy in one file

module hazard_unit
    import riscv_pkg::*;
(
    // consumer, in EX
    input  wire  [4:0]  id_ex_rs1_addr_i,
    input  wire  [4:0]  id_ex_rs2_addr_i,

    // producers
    input  wire  [4:0]  ex_mem_rd_addr_i,
    input  wire  ctrl_t ex_mem_ctrl_i,
    input  wire         ex_mem_valid_i,
    input  wire  [4:0]  mem_wb_rd_addr_i,
    input  wire  ctrl_t mem_wb_ctrl_i,
    input  wire         mem_wb_valid_i,

    // load-use: load in EX, consumer still in ID
    input  wire  [4:0]  id_ex_rd_addr_i,
    input  wire  ctrl_t id_ex_ctrl_i,
    input  wire         id_ex_valid_i,
    input  wire  [4:0]  if_id_rs1_addr_i,
    input  wire  [4:0]  if_id_rs2_addr_i,

    input  wire         redirect_valid_i,

    output fwd_e        fwd_a_o,
    output fwd_e        fwd_b_o,
    output logic        stall_o,
    output logic        flush_o
);

    logic ex_mem_produces, mem_wb_produces;

    assign ex_mem_produces = ex_mem_valid_i && ex_mem_ctrl_i.reg_write &&
                             (ex_mem_rd_addr_i != 5'd0);
    assign mem_wb_produces = mem_wb_valid_i && mem_wb_ctrl_i.reg_write &&
                             (mem_wb_rd_addr_i != 5'd0);

    always_comb begin
        if      (ex_mem_produces && (ex_mem_rd_addr_i == id_ex_rs1_addr_i)) fwd_a_o = FWD_EX_MEM;
        else if (mem_wb_produces && (mem_wb_rd_addr_i == id_ex_rs1_addr_i)) fwd_a_o = FWD_MEM_WB;
        else                                                                fwd_a_o = FWD_NONE;

        if      (ex_mem_produces && (ex_mem_rd_addr_i == id_ex_rs2_addr_i)) fwd_b_o = FWD_EX_MEM;
        else if (mem_wb_produces && (mem_wb_rd_addr_i == id_ex_rs2_addr_i)) fwd_b_o = FWD_MEM_WB;
        else                                                                fwd_b_o = FWD_NONE;
    end

    assign stall_o = id_ex_valid_i && id_ex_ctrl_i.mem_read &&
                     (id_ex_rd_addr_i != 5'd0) &&
                     ((id_ex_rd_addr_i == if_id_rs1_addr_i) ||
                      (id_ex_rd_addr_i == if_id_rs2_addr_i));

    assign flush_o = redirect_valid_i;

endmodule

`default_nettype wire
