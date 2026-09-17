// Copyright (c) 2026 Shubham Lonkar
// SPDX-License-Identifier: MIT

`default_nettype none
`timescale 1ns/1ps

`ifndef BP_MODE_SEL
  `define BP_MODE_SEL riscv_pkg::BP_GSHARE
`endif

// tb_bp -- branch predictor benchmark harness, in-order core

module tb_bp;

    logic clk = 1'b0;
    logic rst_n;

    always #5 clk = ~clk;

    logic [31:0] imem_addr, imem_rdata, dmem_addr, dmem_wdata, dmem_rdata;
    logic [3:0]  dmem_be;
    logic        dmem_we;

    riscv_core #(.BP_MODE(`BP_MODE_SEL)) u_core (
        .clk(clk), .rst_n(rst_n),
        .imem_addr_o(imem_addr), .imem_rdata_i(imem_rdata),
        .dmem_addr_o(dmem_addr), .dmem_wdata_o(dmem_wdata),
        .dmem_be_o(dmem_be),
        .dmem_we_o(dmem_we),     .dmem_rdata_i(dmem_rdata)
    );

    imem u_imem (.addr_i(imem_addr), .rdata_o(imem_rdata));
    dmem u_dmem (.clk(clk), .addr_i(dmem_addr), .wdata_i(dmem_wdata),
                 .be_i(dmem_be), .we_i(dmem_we), .rdata_o(dmem_rdata));

    `include "bp_scenarios.svh"

    localparam int MAX_CYC = 100000;

    int  errors  = 0;
    int  bp_total, bp_wrong, cycles;
    bit  counting = 1'b0;

    always @(posedge clk) if (rst_n && counting) begin
        cycles++;
        if (u_core.bp_update_valid) begin
            bp_total++;
            if (u_core.u_ex.mispredict) bp_wrong++;
        end
    end

    task automatic run_scn(input int n);
        int  guard;
        int  acc;
        logic [31:0] got;

        for (int k = 0; k < riscv_pkg::BP_BHT_DEPTH; k++)
            u_core.u_if.u_bp.bht[k] = '0;
        u_core.u_if.u_bp.ghr = '0;

        for (int k = 0; k < 256; k++) u_imem.mem[k] = 32'd0;
        for (int k = 0; k < 256; k++) u_dmem.mem[k] = 32'd0;
        $readmemh({"../../common/tb/", bp_scn[n].hex}, u_imem.mem);

        rst_n = 1'b0;
        repeat (3) @(posedge clk);
        bp_total = 0;
        bp_wrong = 0;
        cycles   = 0;
        rst_n    = 1'b1;
        counting = 1'b1;

        guard = 0;
        while (u_dmem.mem[BP_DONE_WORD] !== 32'd1 && guard < MAX_CYC) begin
            @(posedge clk);
            guard++;
        end
        repeat (8) @(posedge clk);      // let the pipeline drain
        counting = 1'b0;

        got = u_core.u_id.u_regfile.regs[bp_scn[n].chk_reg];
        acc = (bp_total == 0) ? 0 : (100 * (bp_total - bp_wrong)) / bp_total;

        $display("  %-13s %7d %8d %7d%%  %8d   %s",
                 bp_scn[n].name, bp_total, bp_wrong, acc, cycles,
                 (guard >= MAX_CYC) ? "TIMEOUT" :
                 (got !== bp_scn[n].chk_val) ? "BAD RESULT" : "ok");

        if (guard >= MAX_CYC) begin
            $display("     FAIL  %s never completed", bp_scn[n].name);
            errors++;
        end
        else if (got !== bp_scn[n].chk_val) begin
            $display("     FAIL  %s: x%0d = 0x%08x, expected 0x%08x",
                     bp_scn[n].name, bp_scn[n].chk_reg, got, bp_scn[n].chk_val);
            errors++;
        end
    endtask

    initial begin
        $display("\n=== in-order core, BP_MODE=%s, %0d entries, %0d GHR bits, %0d-bit counters ===",
                 u_core.BP_MODE.name(), riscv_pkg::BP_BHT_DEPTH,
                 riscv_pkg::BP_GHR_BITS, riscv_pkg::BP_CTR_BITS);
        $display("  %-13s %7s %8s %8s %8s", "scenario", "brs", "wrong", "acc", "cycles");

        for (int n = 0; n < BP_N_SCN; n++) run_scn(n);

        if (u_core.u_sva.sva_errors != 0) begin
            $display("\n  FAIL  %0d core assertion failure(s)", u_core.u_sva.sva_errors);
            errors += u_core.u_sva.sva_errors;
        end

        $display("\n%s -- %0d error(s)\n", (errors == 0) ? "PASS" : "FAIL", errors);
        $finish;
    end

endmodule

`default_nettype wire
