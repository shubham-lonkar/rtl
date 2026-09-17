// Copyright (c) 2026 Shubham Lonkar
// SPDX-License-Identifier: MIT

`default_nettype none

// arch_regfile -- committed architectural state only

module arch_regfile (
    input  wire         clk,
    input  wire         wen,
    input  wire  [4:0]  raddr0,     // dispatch rs1
    input  wire  [4:0]  raddr1,     // dispatch rs2
    input  wire  [4:0]  raddr2,     // commit: store data
    input  wire  [4:0]  waddr,
    input  wire  [31:0] wdata,
    output logic [31:0] rdata0,
    output logic [31:0] rdata1,
    output logic [31:0] rdata2
);

    logic [31:0] regs [0:31];

    always_ff @(posedge clk)
        if (wen && (waddr != 5'd0))
            regs[waddr] <= wdata;

    assign rdata0 = (raddr0 == 5'd0) ? 32'd0 : regs[raddr0];
    assign rdata1 = (raddr1 == 5'd0) ? 32'd0 : regs[raddr1];
    assign rdata2 = (raddr2 == 5'd0) ? 32'd0 : regs[raddr2];

endmodule

`default_nettype wire
