// Copyright (c) 2026 Shubham Lonkar
// SPDX-License-Identifier: MIT

`default_nettype none

// regfile -- RV32I architectural register file, 32 x 32, 2 read / 1 write

module regfile (
    input  wire        clk,
    input  wire        wen,        // from WB, already qualified with valid
    input  wire [4:0]  raddr0,
    input  wire [4:0]  raddr1,
    input  wire [4:0]  waddr,
    input  wire [31:0] wdata,
    output logic [31:0] rdata0,
    output logic [31:0] rdata1
);

    logic [31:0] regs [0:31];

    always_ff @(posedge clk) begin
        if (wen && (waddr != 5'd0))
            regs[waddr] <= wdata;
    end

    logic bypass0, bypass1;

    assign bypass0 = wen && (waddr == raddr0);
    assign bypass1 = wen && (waddr == raddr1);

    assign rdata0 = (raddr0 == 5'd0) ? 32'd0 :
                    bypass0          ? wdata :
                                       regs[raddr0];

    assign rdata1 = (raddr1 == 5'd0) ? 32'd0 :
                    bypass1          ? wdata :
                                       regs[raddr1];

endmodule

`default_nettype wire
