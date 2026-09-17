// Copyright (c) 2026 Shubham Lonkar
// SPDX-License-Identifier: MIT

`default_nettype none
`timescale 1ns/1ps

// tb_axi_dma -- directed, self-checking test suite for the DMA

module tb_axi_dma;

    import axi_dma_pkg::*;

    localparam int DATA_W = 32;
    localparam int WORDS  = 8192;             // 32 KB

    logic clk = 1'b0;
    logic rst_n;
    always #5 clk = ~clk;

    // AXI4-Lite (TB drives)
    logic [7:0]  s_awaddr;  logic s_awvalid, s_awready;
    logic [31:0] s_wdata;   logic [3:0] s_wstrb; logic s_wvalid, s_wready;
    logic [1:0]  s_bresp;   logic s_bvalid, s_bready;
    logic [7:0]  s_araddr;  logic s_arvalid, s_arready;
    logic [31:0] s_rdata;   logic [1:0] s_rresp; logic s_rvalid, s_rready;

    // AXI4 master (DUT -> slave model)
    logic [31:0] m_awaddr, m_araddr;
    logic [7:0]  m_awlen,  m_arlen;
    logic [2:0]  m_awsize, m_arsize;
    logic [1:0]  m_awburst, m_arburst;
    logic [3:0]  m_awid, m_arid;
    logic        m_awvalid, m_awready, m_arvalid, m_arready;
    logic [DATA_W-1:0]   m_wdata, m_rdata;
    logic [DATA_W/8-1:0] m_wstrb;
    logic        m_wlast, m_wvalid, m_wready;
    logic [1:0]  m_bresp, m_rresp;
    logic        m_bvalid, m_bready, m_rlast, m_rvalid, m_rready;
    logic        irq;

    axi_dma_top #(
        .DATA_W(DATA_W), .DATA_FIFO_DEPTH(64), .CMD_FIFO_DEPTH(4)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .s_awaddr_i(s_awaddr), .s_awvalid_i(s_awvalid), .s_awready_o(s_awready),
        .s_wdata_i(s_wdata), .s_wstrb_i(s_wstrb), .s_wvalid_i(s_wvalid),
        .s_wready_o(s_wready),
        .s_bresp_o(s_bresp), .s_bvalid_o(s_bvalid), .s_bready_i(s_bready),
        .s_araddr_i(s_araddr), .s_arvalid_i(s_arvalid), .s_arready_o(s_arready),
        .s_rdata_o(s_rdata), .s_rresp_o(s_rresp), .s_rvalid_o(s_rvalid),
        .s_rready_i(s_rready),
        .m_awaddr_o(m_awaddr), .m_awlen_o(m_awlen), .m_awsize_o(m_awsize),
        .m_awburst_o(m_awburst), .m_awid_o(m_awid),
        .m_awvalid_o(m_awvalid), .m_awready_i(m_awready),
        .m_wdata_o(m_wdata), .m_wstrb_o(m_wstrb), .m_wlast_o(m_wlast),
        .m_wvalid_o(m_wvalid), .m_wready_i(m_wready),
        .m_bresp_i(m_bresp), .m_bvalid_i(m_bvalid), .m_bready_o(m_bready),
        .m_araddr_o(m_araddr), .m_arlen_o(m_arlen), .m_arsize_o(m_arsize),
        .m_arburst_o(m_arburst), .m_arid_o(m_arid),
        .m_arvalid_o(m_arvalid), .m_arready_i(m_arready),
        .m_rdata_i(m_rdata), .m_rresp_i(m_rresp), .m_rlast_i(m_rlast),
        .m_rvalid_i(m_rvalid), .m_rready_o(m_rready),
        .irq_o(irq)
    );

    axi_slave_mem #(.DATA_W(DATA_W), .WORDS(WORDS)) mem (
        .clk(clk), .rst_n(rst_n),
        .awaddr_i(m_awaddr), .awlen_i(m_awlen), .awsize_i(m_awsize),
        .awburst_i(m_awburst), .awid_i(m_awid),
        .awvalid_i(m_awvalid), .awready_o(m_awready),
        .wdata_i(m_wdata), .wstrb_i(m_wstrb), .wlast_i(m_wlast),
        .wvalid_i(m_wvalid), .wready_o(m_wready),
        .bresp_o(m_bresp), .bvalid_o(m_bvalid), .bready_i(m_bready),
        .araddr_i(m_araddr), .arlen_i(m_arlen), .arsize_i(m_arsize),
        .arburst_i(m_arburst), .arid_i(m_arid),
        .arvalid_i(m_arvalid), .arready_o(m_arready),
        .rdata_o(m_rdata), .rresp_o(m_rresp), .rlast_o(m_rlast),
        .rvalid_o(m_rvalid), .rready_i(m_rready)
    );

    int errors = 0;
    int checks = 0;

    // helpers
    task automatic csr_write(input logic [7:0] addr, input logic [31:0] data);
        @(posedge clk);
        s_awaddr <= addr; s_awvalid <= 1'b1;
        s_wdata  <= data; s_wstrb <= 4'hF; s_wvalid <= 1'b1;
        s_bready <= 1'b1;
        forever begin @(posedge clk); if (s_awready) break; end
        s_awvalid <= 1'b0;
        while (!s_wready) @(posedge clk);
        @(posedge clk);
        s_wvalid <= 1'b0;
        forever begin @(posedge clk); if (s_bvalid) break; end
        s_bready <= 1'b0;
    endtask

    task automatic csr_read(input logic [7:0] addr, output logic [31:0] data);
        @(posedge clk);
        s_araddr <= addr; s_arvalid <= 1'b1; s_rready <= 1'b1;
        forever begin @(posedge clk); if (s_arready) break; end
        s_arvalid <= 1'b0;
        forever begin @(posedge clk); if (s_rvalid) break; end
        data = s_rdata;
        s_rready <= 1'b0;
    endtask

    task automatic expect_eq(input string what, input logic [31:0] got,
                             input logic [31:0] exp);
        checks++;
        if (got !== exp) begin
            $display("    FAIL  %s = 0x%08x, expected 0x%08x", what, got, exp);
            errors++;
        end
    endtask

    task automatic seed(input int src_word, input int dst_word, input int nwords);
        for (int k = 0; k < nwords; k++) begin
            mem.mem[src_word + k] = 32'hA5A5_0000 + k;
            mem.mem[dst_word + k] = 32'hDEAD_BEEF;
        end
    endtask

    task automatic check_copy(input string name, input int src_word,
                              input int dst_word, input int nwords);
        int bad = 0;
        for (int k = 0; k < nwords; k++)
            if (mem.mem[dst_word + k] !== mem.mem[src_word + k]) begin
                if (bad < 3)
                    $display("    FAIL  %s word %0d: dst 0x%08x != src 0x%08x",
                             name, k, mem.mem[dst_word + k], mem.mem[src_word + k]);
                bad++;
            end
        checks++;
        if (bad != 0) begin
            $display("    FAIL  %s: %0d of %0d words wrong", name, bad, nwords);
            errors++;
        end
    endtask

    task automatic run_dma(input logic [31:0] src, input logic [31:0] dst,
                           input logic [31:0] len, input int max_beats,
                           output logic [31:0] status);
        int guard;
        logic [31:0] ctrl;
        csr_write(REG_SRC,   src);
        csr_write(REG_DST,   dst);
        csr_write(REG_LEN,   len);
        csr_write(REG_BURST, max_beats);
        csr_read(REG_CTRL, ctrl);
        csr_write(REG_CTRL, ctrl | 32'h1);     // START

        guard = 0;
        forever begin
            csr_read(REG_STATUS, status);
            if (status[1]) break;              // DONE
            guard++;
            if (guard > 20000) begin
                $display("    FAIL  timeout waiting for DONE (status=0x%08x)", status);
                errors++;
                break;
            end
        end
    endtask

    // tests
    task automatic t_regs();
        logic [31:0] d;
        $display("  [regs] register access");
        csr_write(REG_SRC, 32'h1234_5678);  csr_read(REG_SRC, d);
        expect_eq("SRC", d, 32'h1234_5678);
        csr_write(REG_DST, 32'h8765_4321);  csr_read(REG_DST, d);
        expect_eq("DST", d, 32'h8765_4321);
        csr_write(REG_LEN, 32'h0000_0100);  csr_read(REG_LEN, d);
        expect_eq("LEN", d, 32'h0000_0100);

        // Clamping: 0 becomes 1, anything over 256 becomes 256.
        csr_write(REG_BURST, 32'd0);    csr_read(REG_BURST, d);
        expect_eq("BURST clamp lo", d, 32'd1);
        csr_write(REG_BURST, 32'd9999); csr_read(REG_BURST, d);
        expect_eq("BURST clamp hi", d, 32'd256);
        csr_write(REG_BURST, 32'd16);   csr_read(REG_BURST, d);
        expect_eq("BURST", d, 32'd16);

        csr_read(REG_STATUS, d);
        expect_eq("STATUS idle", d, 32'd0);
        csr_read(8'hFC, d);
        expect_eq("unmapped reads 0", d, 32'd0);
    endtask

    task automatic t_single_beat();
        logic [31:0] st;
        $display("  [single] one beat, 4 bytes");
        seed(0, 512, 1);
        run_dma(32'h0000, 32'h0800, 32'd4, 16, st);
        expect_eq("STATUS", st, 32'd2);        // DONE, not BUSY, no ERR
        check_copy("single", 0, 512, 1);
    endtask

    task automatic t_one_burst();
        logic [31:0] st;
        $display("  [burst] one full 16-beat burst, 64 bytes");
        seed(0, 512, 16);
        run_dma(32'h0000, 32'h0800, 32'd64, 16, st);
        expect_eq("STATUS", st, 32'd2);
        check_copy("burst", 0, 512, 16);
    endtask

    task automatic t_multi_burst();
        logic [31:0] st;
        int nw = 256;                           // 1 KB -> 16 bursts of 16 beats
        $display("  [multi] 1 KB across many bursts");
        seed(0, 512, nw);
        mem.rd_bursts = 0; mem.wr_bursts = 0;
        run_dma(32'h0000, 32'h0800, nw*4, 16, st);
        expect_eq("STATUS", st, 32'd2);
        check_copy("multi", 0, 512, nw);
        checks++;
        if (mem.rd_bursts != 16 || mem.wr_bursts != 16) begin
            $display("    FAIL  expected 16 read and 16 write bursts, saw %0d / %0d",
                     mem.rd_bursts, mem.wr_bursts);
            errors++;
        end
    endtask

    task automatic t_4kb_cross();
        logic [31:0] st;
        int src_w = 32'h0FF0 >> 2;
        int dst_w = 32'h2000 >> 2;
        int nw    = 64;                         // 256 bytes
        $display("  [4kb]   transfer straddling a 4KB boundary");
        seed(src_w, dst_w, nw);
        mem.rd_bursts = 0;
        run_dma(32'h0FF0, 32'h2000, nw*4, 64, st);
        expect_eq("STATUS", st, 32'd2);
        check_copy("4kb", src_w, dst_w, nw);
        checks++;
        if (mem.rd_bursts < 2) begin
            $display("    FAIL  4KB transfer used %0d burst(s); it must split",
                     mem.rd_bursts);
            errors++;
        end
    endtask

    task automatic t_max_burst();
        logic [31:0] st;
        $display("  [maxlen] max_beats=256, clamped by the data FIFO");
        seed(0, 1024, 256);
        run_dma(32'h0000, 32'h1000, 32'd1024, 256, st);
        expect_eq("STATUS", st, 32'd2);
        check_copy("maxlen", 0, 1024, 256);
    endtask

    task automatic t_backpressure();
        logic [31:0] st;
        $display("  [stall] random slave stalls on every channel");
        mem.stall_pct = 40;
        seed(0, 512, 128);
        run_dma(32'h0000, 32'h0800, 32'd512, 16, st);
        expect_eq("STATUS", st, 32'd2);
        check_copy("stall", 0, 512, 128);
        mem.stall_pct = 0;
    endtask

    task automatic t_zero_len();
        logic [31:0] st;
        $display("  [zero]  zero-length descriptor");
        run_dma(32'h0000, 32'h0800, 32'd0, 16, st);
        expect_eq("STATUS", st, 32'd2);        // completes, does not hang
    endtask

    task automatic t_read_error();
        logic [31:0] st;
        $display("  [rderr] SLVERR on a read beat");
        seed(0, 512, 64);
        mem.err_addr = 32'h0020;               // inside the first burst
        run_dma(32'h0000, 32'h0800, 32'd256, 16, st);
        mem.err_addr = 32'hFFFF_FFFF;
        checks++;
        if (!st[2]) begin
            $display("    FAIL  ERR not set after SLVERR (status=0x%08x)", st);
            errors++;
        end
        expect_eq("STATUS resp field", st[4:3], RESP_SLVERR);
    endtask

    task automatic t_write_error();
        logic [31:0] st;
        $display("  [wrerr] SLVERR on a write beat");
        seed(0, 512, 64);
        mem.err_addr = 32'h0800;               // first destination word
        run_dma(32'h0000, 32'h0800, 32'd256, 16, st);
        mem.err_addr = 32'hFFFF_FFFF;
        checks++;
        if (!st[2]) begin
            $display("    FAIL  ERR not set after write SLVERR (status=0x%08x)", st);
            errors++;
        end
    endtask

    task automatic t_irq();
        logic [31:0] st, d;
        $display("  [irq]   interrupt enable and W1C");
        seed(0, 512, 16);
        csr_write(REG_CTRL, 32'h4);            // IRQ_EN, no START
        run_dma(32'h0000, 32'h0800, 32'd64, 16, st);
        checks++;
        if (!irq) begin
            $display("    FAIL  irq_o low after DONE with IRQ_EN set");
            errors++;
        end
        csr_write(REG_IRQ, 32'h1);             // W1C
        csr_read(REG_IRQ, d);
        expect_eq("IRQ after W1C", d, 32'd0);
        checks++;
        if (irq) begin
            $display("    FAIL  irq_o still high after W1C");
            errors++;
        end
        csr_write(REG_CTRL, 32'h0);
    endtask

    task automatic t_back_to_back();
        logic [31:0] st;
        $display("  [b2b]   three descriptors back to back");
        for (int n = 0; n < 3; n++) begin
            seed(n*64, 512 + n*64, 32);
            run_dma(n*256, 32'h0800 + n*256, 32'd128, 8, st);
            expect_eq($sformatf("STATUS pass %0d", n), st, 32'd2);
            check_copy($sformatf("b2b %0d", n), n*64, 512 + n*64, 32);
        end
    endtask

    // main
    initial begin
        s_awvalid = 0; s_wvalid = 0; s_bready = 0; s_arvalid = 0; s_rready = 0;
        s_awaddr = 0; s_wdata = 0; s_wstrb = 0; s_araddr = 0;

        for (int k = 0; k < WORDS; k++) mem.mem[k] = 32'd0;

        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        $display("\n=== axi_dma directed tests ===");
        t_regs();
        t_single_beat();
        t_one_burst();
        t_multi_burst();
        t_4kb_cross();
        t_max_burst();
        t_backpressure();
        t_zero_len();
        t_read_error();
        t_write_error();
        t_irq();
        t_back_to_back();

        $display("\n%s -- %0d check(s), %0d error(s)\n",
                 (errors == 0) ? "PASS" : "FAIL", checks, errors);
        $finish;
    end

    initial begin
        #5_000_000;
        $display("\nFAIL -- global timeout\n");
        $finish;
    end

endmodule

`default_nettype wire
