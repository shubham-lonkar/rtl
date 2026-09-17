// Copyright (c) 2026 Shubham Lonkar
// SPDX-License-Identifier: MIT

`default_nettype none

// axi_dma_fifo -- synchronous FIFO, used three times: once for the data path and twice for the read/write command queues

module axi_dma_fifo #(
    parameter int WIDTH = 32,
    parameter int DEPTH = 16                    // power of two
) (
    input  wire              clk,
    input  wire              rst_n,

    input  wire              wr_en_i,
    input  wire  [WIDTH-1:0] wr_data_i,
    output logic             full_o,

    input  wire              rd_en_i,
    output logic [WIDTH-1:0] rd_data_o,
    output logic             empty_o,

    output logic [$clog2(DEPTH):0] count_o      // one bit wider: 0..DEPTH
);

    localparam int PTR_W = $clog2(DEPTH);

    initial if (2**PTR_W != DEPTH)
        $fatal(1, "axi_dma_fifo: DEPTH (%0d) must be a power of two", DEPTH);

    logic [WIDTH-1:0] mem [DEPTH-1:0];
    logic [PTR_W-1:0] wr_ptr, rd_ptr;

    assign empty_o   = (count_o == '0);
    assign full_o    = (count_o == DEPTH[$clog2(DEPTH):0]);
    assign rd_data_o = mem[rd_ptr];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr  <= '0;
            rd_ptr  <= '0;
            count_o <= '0;
        end
        else begin
            if (wr_en_i && !full_o) begin
                mem[wr_ptr] <= wr_data_i;
                wr_ptr      <= wr_ptr + 1'b1;
            end
            if (rd_en_i && !empty_o)
                rd_ptr <= rd_ptr + 1'b1;

            case ({wr_en_i && !full_o, rd_en_i && !empty_o})
                2'b10:   count_o <= count_o + 1'b1;
                2'b01:   count_o <= count_o - 1'b1;
                default: ;
            endcase
        end
    end

endmodule

`default_nettype wire
