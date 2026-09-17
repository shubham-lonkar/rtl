// Copyright (c) 2026 Shubham Lonkar
// SPDX-License-Identifier: MIT

`default_nettype none
`timescale 1ns/1ps

`ifdef BP_SEL_BIMODAL
  `define BP_MODE_SEL riscv_pkg::BP_BIMODAL
`elsif BP_SEL_GSELECT
  `define BP_MODE_SEL riscv_pkg::BP_GSELECT
`else
  `define BP_MODE_SEL riscv_pkg::BP_GSHARE
`endif

// tb_trace -- per-instruction comparison against the Python ISS

module tb_trace;

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

    localparam int MAX_TRACE = 4096;
    localparam int MAX_CYC   = 20000;

    string programs [3] = '{"program", "mem_program", "cov_program"};

    logic [31:0] g_pc  [MAX_TRACE];
    int          g_rd  [MAX_TRACE];
    logic [31:0] g_val [MAX_TRACE];
    int          g_len;

    int errors  = 0;
    int retired = 0;
    bit checking = 1'b0;

    // trace
    function automatic void load_trace(string name);
        int fd, code;
        logic [31:0] pc, val;
        int rd;
        fd = $fopen({"../../common/tb/", name, ".trace"}, "r");
        if (fd == 0) begin
            $display("  FAIL  cannot open %s.trace -- run: python iss.py %s.hex",
                     name, name);
            errors++;
            g_len = 0;
            return;
        end
        g_len = 0;
        forever begin
            code = $fscanf(fd, "%h %d %h", pc, rd, val);
            if (code != 3) break;
            g_pc[g_len]  = pc;
            g_rd[g_len]  = rd;
            g_val[g_len] = val;
            g_len++;
        end
        $fclose(fd);
    endfunction

    wire        retire_valid = u_core.u_mem_wb.mem_wb_valid_o;
    wire [31:0] retire_pc    = u_core.u_mem_wb.mem_wb_pc4 - 32'd4;
    wire [4:0]  retire_rd    = (u_core.wb_we && u_core.wb_rd_addr != 5'd0)
                                   ? u_core.wb_rd_addr : 5'd0;
    wire [31:0] retire_val   = (retire_rd != 5'd0) ? u_core.wb_rd_data : 32'd0;

    always @(posedge clk) begin
        if (rst_n && checking && retire_valid && retired < g_len) begin
            if (retire_pc  !== g_pc[retired] ||
                retire_rd  !== g_rd[retired] ||
                retire_val !== g_val[retired]) begin
                $display("  FAIL  retire %0d: pc 0x%08x x%0d=0x%08x   expected pc 0x%08x x%0d=0x%08x",
                         retired, retire_pc, retire_rd, retire_val,
                         g_pc[retired], g_rd[retired], g_val[retired]);
                errors++;
            end
            retired++;
        end
    end

    // run
    task automatic run_program(string name);
        int cyc;
        int errors_at_start;

        $display("\n--- %s ---", name);
        errors_at_start = errors;
        load_trace(name);
        if (g_len == 0) return;

        checking = 1'b0;
        rst_n    = 1'b0;
        retired  = 0;
        @(negedge clk);

        for (int k = 0; k < 32; k++) u_core.u_id.u_regfile.regs[k] = 32'd0;
        for (int k = 0; k < 256; k++) u_dmem.mem[k] = 32'd0;
        for (int k = 0; k < 256; k++) u_imem.mem[k] = 32'd0;
        $readmemh({"../../common/tb/", name, ".hex"}, u_imem.mem);

        repeat (3) @(posedge clk);
        rst_n    = 1'b1;
        checking = 1'b1;

        cyc = 0;
        while (retired < g_len && cyc < MAX_CYC) begin
            @(posedge clk);
            cyc++;
        end
        checking = 1'b0;

        if (retired < g_len) begin
            $display("  FAIL  only %0d of %0d instructions retired in %0d cycles",
                     retired, g_len, MAX_CYC);
            errors++;
        end
        else if (errors != errors_at_start) begin
            $display("  FAIL  %0d of %0d instructions diverged from the ISS",
                     errors - errors_at_start, retired);
        end
        else begin
            $display("  ok    %0d instructions match the ISS (%0d cycles, CPI %.2f)",
                     retired, cyc, real'(cyc) / real'(retired));
        end
    endtask

    initial begin
        foreach (programs[n]) run_program(programs[n]);

        $display("\n--- assertions ---");
        if (u_core.u_sva.sva_errors != 0) begin
            $display("  FAIL  %0d core assertion failure(s)", u_core.u_sva.sva_errors);
            errors += u_core.u_sva.sva_errors;
        end
        else
            $display("  ok    core invariants held");

        if (u_core.u_id.u_regfile.u_rf_sva.sva_errors != 0) begin
            $display("  FAIL  %0d regfile assertion failure(s)",
                     u_core.u_id.u_regfile.u_rf_sva.sva_errors);
            errors += u_core.u_id.u_regfile.u_rf_sva.sva_errors;
        end
        else
            $display("  ok    x0 read zero on every access");

        u_core.u_cov.report();

        $display("\n%s -- %0d error(s)\n", (errors == 0) ? "PASS" : "FAIL", errors);
        $finish;
    end

endmodule

`default_nettype wire
