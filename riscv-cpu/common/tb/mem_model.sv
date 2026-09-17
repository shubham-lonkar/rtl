// Copyright (c) 2026 Shubham Lonkar
// SPDX-License-Identifier: MIT

`default_nettype none

// mem_model -- behavioural instruction and data memory

module imem #(parameter int WORDS = 256) (
    input  wire  [31:0] addr_i,
    output logic [31:0] rdata_o
);
    logic [31:0] mem [0:WORDS-1];
    assign rdata_o = mem[addr_i[31:2]];    // word-indexed; PC is byte-addressed
endmodule

module dmem #(parameter int WORDS = 256) (
    input  wire         clk,
    input  wire  [31:0] addr_i,
    input  wire  [31:0] wdata_i,
    input  wire  [3:0]  be_i,
    input  wire         we_i,
    output logic [31:0] rdata_o
);
    logic [31:0] mem [0:WORDS-1];

    assign rdata_o = mem[addr_i[31:2]];

    always_ff @(posedge clk)
        if (we_i)
            for (int lane = 0; lane < 4; lane++)
                if (be_i[lane]) mem[addr_i[31:2]][8*lane +: 8] <= wdata_i[8*lane +: 8];
endmodule

`default_nettype wire
