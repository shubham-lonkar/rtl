// Copyright (c) 2026 Shubham Lonkar
// SPDX-License-Identifier: MIT

`default_nettype none
`timescale 1ns/1ps

// Branch predictor index function
`ifdef BP_SEL_BIMODAL
  `define BP_MODE_SEL riscv_pkg::BP_BIMODAL
`elsif BP_SEL_GSELECT
  `define BP_MODE_SEL riscv_pkg::BP_GSELECT
`else
  `define BP_MODE_SEL riscv_pkg::BP_GSHARE
`endif

// tb_oo_core -- runs the SAME program.hex as the in-order core and checks the SAME architectural state

module tb_oo_core;

    logic clk = 1'b0;
    logic rst_n;

    always #5 clk = ~clk;

    logic [31:0] imem_addr, imem_rdata, dmem_addr, dmem_wdata, dmem_rdata;
    logic        dmem_we;

    oo_core #(.BP_MODE(`BP_MODE_SEL)) u_core (
        .clk(clk), .rst_n(rst_n),
        .imem_addr_o(imem_addr), .imem_rdata_i(imem_rdata),
        .dmem_addr_o(dmem_addr), .dmem_wdata_o(dmem_wdata),
        .dmem_we_o(dmem_we),     .dmem_rdata_i(dmem_rdata)
    );

    imem u_imem (.addr_i(imem_addr), .rdata_o(imem_rdata));
    dmem u_dmem (.clk(clk), .addr_i(dmem_addr), .wdata_i(dmem_wdata),
                 .be_i(4'hF), .we_i(dmem_we), .rdata_o(dmem_rdata));

    int errors = 0;

    int bp_total = 0;
    int bp_wrong = 0;

    always @(posedge clk) if (rst_n) begin
        if (u_core.br_resolve) begin
            bp_total++;
            if (u_core.mispredict) bp_wrong++;
        end
    end

    task automatic check_reg(input int idx, input logic [31:0] exp);
        logic [31:0] got;
        got = u_core.u_rf.regs[idx];
        if (got !== exp) begin
            $display("  FAIL  x%0d = 0x%08x, expected 0x%08x", idx, got, exp);
            errors++;
        end
        else
            $display("  ok    x%0d = 0x%08x", idx, got);
    endtask

    initial begin
        for (int k = 0; k < 256; k++) u_imem.mem[k] = 32'd0;  // speculation runs past
        $readmemh("../../common/tb/program.hex", u_imem.mem);
        for (int k = 0; k < 256; k++) u_dmem.mem[k] = 32'd0;

        rst_n = 1'b0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;

        repeat (300) @(posedge clk);

        $display("\n--- architectural state ---");
        check_reg( 1, 32'd5);
        check_reg( 2, 32'd7);
        check_reg( 3, 32'd12);
        check_reg( 4, 32'd7);
        check_reg( 5, 32'd0);
        check_reg( 6, 32'd12);          // load, executed at commit
        check_reg( 7, 32'd19);          // consumer woken by the commit-side CDB
        check_reg( 8, 32'd42);
        check_reg( 9, 32'd1);
        check_reg(10, 32'd56);          // jal link, ready at dispatch
        check_reg(11, 32'd3);
        check_reg(13, 32'd9);
        check_reg(16, 32'd9);           // in-order needs a regfile bypass here; this does not
        check_reg(17, 32'h1234_5000);
        check_reg(18, 32'd84);

        if (u_dmem.mem[0] !== 32'd12) begin
            $display("  FAIL  mem[0] = 0x%08x, expected 0x0000000c", u_dmem.mem[0]);
            errors++;
        end
        else
            $display("  ok    mem[0] = 0x%08x", u_dmem.mem[0]);

        $display("\n--- branch prediction ---");
        $display("  branches resolved : %0d", bp_total);
        $display("  mispredicted      : %0d", bp_wrong);
        if (bp_total > 0)
            $display("  accuracy          : %0d%%", (100*(bp_total-bp_wrong))/bp_total);

        if (bp_total < 8) begin
            $display("  FAIL  only %0d branches resolved -- predictor not exercised", bp_total);
            errors++;
        end
        else if (bp_wrong * 2 >= bp_total) begin
            $display("  FAIL  %0d/%0d mispredicted -- predictor is not learning", bp_wrong, bp_total);
            errors++;
        end
        else
            $display("  ok    predictor converged");

        $display("\n%s -- %0d error(s)\n", (errors == 0) ? "PASS" : "FAIL", errors);
        $finish;
    end

endmodule

`default_nettype wire
