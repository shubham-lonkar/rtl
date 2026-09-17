// Copyright (c) 2026 Shubham Lonkar
// SPDX-License-Identifier: MIT

`default_nettype none
`timescale 1ns/1ps

// axi_slave_mem -- behavioural AXI4 slave with memory

module axi_slave_mem #(
    parameter int DATA_W = 32,
    parameter int WORDS  = 8192               // 32 KB, so 4KB boundaries exist
) (
    input  wire clk,
    input  wire rst_n,

    input  wire [31:0]  awaddr_i,
    input  wire [7:0]   awlen_i,
    input  wire [2:0]   awsize_i,
    input  wire [1:0]   awburst_i,
    input  wire [3:0]   awid_i,
    input  wire         awvalid_i,
    output logic        awready_o,

    input  wire [DATA_W-1:0]   wdata_i,
    input  wire [DATA_W/8-1:0] wstrb_i,
    input  wire                wlast_i,
    input  wire                wvalid_i,
    output logic               wready_o,

    output logic [1:0]  bresp_o,
    output logic        bvalid_o,
    input  wire         bready_i,

    input  wire [31:0]  araddr_i,
    input  wire [7:0]   arlen_i,
    input  wire [2:0]   arsize_i,
    input  wire [1:0]   arburst_i,
    input  wire [3:0]   arid_i,
    input  wire         arvalid_i,
    output logic        arready_o,

    output logic [DATA_W-1:0] rdata_o,
    output logic [1:0]        rresp_o,
    output logic              rlast_o,
    output logic              rvalid_o,
    input  wire               rready_i
);

    import axi_dma_pkg::*;

    localparam int BEAT_BYTES = DATA_W / 8;

    logic [DATA_W-1:0] mem [0:WORDS-1];

    int    stall_pct = 0;
    logic [31:0] err_addr = 32'hFFFF_FFFF;

    int    rd_bursts = 0, wr_bursts = 0;      // observed, for the tests to check

    // protocol checks
    function automatic void check_burst(input string ch,
                                        input logic [31:0] addr,
                                        input logic [7:0]  len,
                                        input logic [1:0]  burst,
                                        input logic [2:0]  size);
        int unsigned bytes;
        bytes = (len + 1) * (1 << size);

        if (burst !== BURST_INCR)
            $error("%s burst at 0x%08x: type %b, expected INCR", ch, addr, burst);

        if (size !== 3'($clog2(BEAT_BYTES)))
            $error("%s burst at 0x%08x: size %0d, expected %0d",
                   ch, addr, size, $clog2(BEAT_BYTES));

        if (addr[$clog2(BEAT_BYTES)-1:0] != '0)
            $error("%s burst at 0x%08x is not beat-aligned", ch, addr);

        // The rule the whole splitter exists to obey.
        if ((addr % BOUNDARY) + bytes > BOUNDARY)
            $error("%s burst at 0x%08x length %0d bytes CROSSES a 4KB boundary",
                   ch, addr, bytes);
    endfunction

    function automatic bit stall();
        return (stall_pct > 0) && (($urandom_range(99, 0)) < stall_pct);
    endfunction

    // read channel
    initial begin
        logic [31:0] a;
        int          n;
        logic [3:0]  id;

        arready_o = 1'b0;
        rvalid_o  = 1'b0;
        rlast_o   = 1'b0;
        rdata_o   = '0;
        rresp_o   = RESP_OKAY;

        @(posedge rst_n);

        forever begin
            while (stall()) @(posedge clk);

            arready_o <= 1'b1;
            forever begin @(posedge clk); if (arvalid_i) break; end
            a  = araddr_i;
            n  = arlen_i + 1;
            id = arid_i;
            check_burst("AR", araddr_i, arlen_i, arburst_i, arsize_i);
            arready_o <= 1'b0;
            rd_bursts++;

            for (int k = 0; k < n; k++) begin
                if (stall()) begin
                    rvalid_o <= 1'b0;
                    @(posedge clk);
                end
                rdata_o  <= mem[(a >> $clog2(BEAT_BYTES)) + k];
                rresp_o  <= ((a + k*BEAT_BYTES) == err_addr) ? RESP_SLVERR : RESP_OKAY;
                rlast_o  <= (k == n-1);
                rvalid_o <= 1'b1;
                forever begin @(posedge clk); if (rready_i) break; end
            end
            rvalid_o <= 1'b0;
            rlast_o  <= 1'b0;
        end
    end

    // write channel
    initial begin
        logic [31:0] a;
        int          n, k;
        logic [1:0]  resp;

        awready_o = 1'b0;
        wready_o  = 1'b0;
        bvalid_o  = 1'b0;
        bresp_o   = RESP_OKAY;

        @(posedge rst_n);

        forever begin
            while (stall()) @(posedge clk);

            awready_o <= 1'b1;
            forever begin @(posedge clk); if (awvalid_i) break; end
            a = awaddr_i;
            n = awlen_i + 1;
            check_burst("AW", awaddr_i, awlen_i, awburst_i, awsize_i);
            awready_o <= 1'b0;
            wr_bursts++;

            resp = RESP_OKAY;
            k    = 0;
            wready_o <= 1'b1;
            forever begin
                @(posedge clk);
                if (wvalid_i && wready_o) begin
                    for (int byt = 0; byt < BEAT_BYTES; byt++)
                        if (wstrb_i[byt])
                            mem[(a >> $clog2(BEAT_BYTES)) + k][byt*8 +: 8] <= wdata_i[byt*8 +: 8];

                    if ((a + k*BEAT_BYTES) == err_addr) resp = RESP_SLVERR;

                    // WLAST must land on exactly the beat AWLEN promised.
                    if (wlast_i && (k != n-1))
                        $error("AW burst at 0x%08x: WLAST on beat %0d of %0d", a, k+1, n);
                    if (!wlast_i && (k == n-1))
                        $error("AW burst at 0x%08x: no WLAST on final beat %0d", a, n);

                    k++;
                    if (k == n) break;
                end
                if (stall()) begin
                    wready_o <= 1'b0;
                    @(posedge clk);
                    wready_o <= 1'b1;
                end
            end
            wready_o <= 1'b0;

            while (stall()) @(posedge clk);
            bresp_o  <= resp;
            bvalid_o <= 1'b1;
            forever begin @(posedge clk); if (bready_i) break; end
            bvalid_o <= 1'b0;
        end
    end

endmodule

`default_nettype wire
