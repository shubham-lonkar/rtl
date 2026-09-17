// Copyright (c) 2026 Shubham Lonkar
// SPDX-License-Identifier: MIT

`default_nettype none

// riscv_sva -- pipeline invariants as bound checkers

module riscv_sva
    import riscv_pkg::*;
(
    input wire         clk,
    input wire         rst_n,

    input wire         stall,
    input wire         flush,
    input wire         redirect_valid,

    input wire  [31:0] ex_mem_alu,
    input wire  [2:0]  ex_mem_funct3,
    input wire  ctrl_t ex_mem_ctrl,
    input wire         ex_mem_valid,

    input wire         mem_wb_valid,
    input wire         wb_we,

    input wire  [31:0] imem_addr_o,
    input wire  [3:0]  dmem_be_o,
    input wire         dmem_we_o
);

    int sva_errors = 0;

    a_no_stall_and_flush: assert property (@(posedge clk) disable iff (!rst_n)
        !(stall && flush))
    else begin
        sva_errors++;
        $error("stall and flush asserted together");
    end

    a_pc_aligned: assert property (@(posedge clk) disable iff (!rst_n)
        imem_addr_o[1:0] == 2'b00)
    else begin
        sva_errors++;
        $error("PC misaligned: 0x%08x", imem_addr_o);
    end

    a_no_wb_when_invalid: assert property (@(posedge clk) disable iff (!rst_n)
        !mem_wb_valid |-> !wb_we)
    else begin
        sva_errors++;
        $error("register write from an invalid MEM/WB");
    end

    a_no_store_when_invalid: assert property (@(posedge clk) disable iff (!rst_n)
        !ex_mem_valid |-> !dmem_we_o)
    else begin
        sva_errors++;
        $error("store from an invalid EX/MEM");
    end

    wire mem_access = ex_mem_valid &&
                      (ex_mem_ctrl.mem_read || ex_mem_ctrl.mem_write);

    a_halfword_aligned: assert property (@(posedge clk) disable iff (!rst_n)
        (mem_access && (ex_mem_funct3 == MEM_H || ex_mem_funct3 == MEM_HU))
            |-> ex_mem_alu[0] == 1'b0)
    else begin
        sva_errors++;
        $error("misaligned halfword access at 0x%08x", ex_mem_alu);
    end

    a_word_aligned: assert property (@(posedge clk) disable iff (!rst_n)
        (mem_access && ex_mem_funct3 == MEM_W) |-> ex_mem_alu[1:0] == 2'b00)
    else begin
        sva_errors++;
        $error("misaligned word access at 0x%08x", ex_mem_alu);
    end

    a_store_writes_something: assert property (@(posedge clk) disable iff (!rst_n)
        dmem_we_o |-> dmem_be_o != 4'b0000)
    else begin
        sva_errors++;
        $error("store with no byte enables set");
    end

    a_store_be_matches_width: assert property (@(posedge clk) disable iff (!rst_n)
        dmem_we_o |-> ($countones(dmem_be_o) ==
                       (ex_mem_funct3 == MEM_B ? 1 :
                        ex_mem_funct3 == MEM_H ? 2 : 4)))
    else begin
        sva_errors++;
        $error("byte enables 0b%04b do not match funct3 %03b",
               dmem_be_o, ex_mem_funct3);
    end

    a_redirect_flushes: assert property (@(posedge clk) disable iff (!rst_n)
        redirect_valid |-> flush)
    else begin
        sva_errors++;
        $error("redirect without flush");
    end

endmodule

module regfile_sva (
    input wire        clk,
    input wire [4:0]  raddr0,
    input wire [4:0]  raddr1,
    input wire [31:0] rdata0,
    input wire [31:0] rdata1
);

    int sva_errors = 0;

    a_x0_reads_zero_port0: assert property (@(posedge clk)
        (raddr0 == 5'd0) |-> (rdata0 == 32'd0))
    else begin
        sva_errors++;
        $error("x0 read non-zero on port 0: 0x%08x", rdata0);
    end

    a_x0_reads_zero_port1: assert property (@(posedge clk)
        (raddr1 == 5'd0) |-> (rdata1 == 32'd0))
    else begin
        sva_errors++;
        $error("x0 read non-zero on port 1: 0x%08x", rdata1);
    end

endmodule

bind riscv_core riscv_sva   u_sva     (.*);
bind regfile    regfile_sva u_rf_sva  (.*);

`default_nettype wire
