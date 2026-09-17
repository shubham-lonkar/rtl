// Copyright (c) 2026 Shubham Lonkar
// SPDX-License-Identifier: MIT

// axi_dma_pkg -- AXI encodings and the CSR map

package axi_dma_pkg;

    // AXI response codes (AXI4 A3.4.4)
    localparam logic [1:0] RESP_OKAY   = 2'b00;
    localparam logic [1:0] RESP_EXOKAY = 2'b01;
    localparam logic [1:0] RESP_SLVERR = 2'b10;
    localparam logic [1:0] RESP_DECERR = 2'b11;

    localparam logic [1:0] BURST_FIXED = 2'b00;
    localparam logic [1:0] BURST_INCR  = 2'b01;
    localparam logic [1:0] BURST_WRAP  = 2'b10;

    localparam int unsigned BOUNDARY = 4096;

    localparam int unsigned MAX_AXI_BEATS = 256;

    // CSR map, byte offsets on the AXI4-Lite slave
    localparam logic [7:0] REG_CTRL   = 8'h00;  // [0] START (self-clearing)
    localparam logic [7:0] REG_STATUS = 8'h04;  // RO: [0] BUSY [1] DONE [2] ERR
                                                // [4:3] last non-OKAY resp
    localparam logic [7:0] REG_SRC    = 8'h08;
    localparam logic [7:0] REG_DST    = 8'h0C;
    localparam logic [7:0] REG_LEN    = 8'h10;  // bytes
    localparam logic [7:0] REG_BURST  = 8'h14;  // max beats per burst, 1..256
    localparam logic [7:0] REG_IRQ    = 8'h18;  // [0] DONE latch, W1C

endpackage
