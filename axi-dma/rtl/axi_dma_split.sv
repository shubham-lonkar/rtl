// Copyright (c) 2026 Shubham Lonkar
// SPDX-License-Identifier: MIT

`default_nettype none

// axi_dma_split -- descriptor FSM

module axi_dma_split
    import axi_dma_pkg::*;
#(
    parameter int DATA_W = 32
) (
    input  wire         clk,
    input  wire         rst_n,

    // descriptor, from the CSR block
    input  wire         start_i,
    input  wire [31:0]  src_i,
    input  wire [31:0]  dst_i,
    input  wire [31:0]  len_i,
    input  wire [8:0]   max_beats_i,

    // burst commands: {addr[31:0], axlen[7:0]}
    output logic        rd_cmd_valid_o,
    output logic [39:0] rd_cmd_data_o,
    input  wire         rd_cmd_ready_i,

    output logic        wr_cmd_valid_o,
    output logic [39:0] wr_cmd_data_o,
    input  wire         wr_cmd_ready_i,

    // completion and errors
    input  wire         wr_burst_done_i,   // one pulse per B response
    input  wire         err_i,             // any non-OKAY response, from either engine

    output logic        busy_o,
    output logic        done_o             // one-cycle pulse
);

    localparam int BEAT_BYTES = DATA_W / 8;
    localparam int BEAT_SHIFT = $clog2(BEAT_BYTES);

    typedef enum logic [1:0] { S_IDLE, S_RUN, S_DRAIN, S_FIN } state_e;
    state_e state_q;

    logic [31:0] src_q, dst_q, rem_q;
    logic [8:0]  max_beats_q;
    logic [15:0] outstanding_q;             // bursts issued but not yet B-responded
    logic        err_q;

    // burst sizing
    logic [31:0] to4k_src, to4k_dst, max_bytes, chunk;
    logic [8:0]  beats;

    assign to4k_src  = BOUNDARY - {20'd0, src_q[11:0]};
    assign to4k_dst  = BOUNDARY - {20'd0, dst_q[11:0]};
    assign max_bytes = {23'd0, max_beats_q} << BEAT_SHIFT;

    always_comb begin
        chunk = rem_q;
        if (to4k_src  < chunk) chunk = to4k_src;
        if (to4k_dst  < chunk) chunk = to4k_dst;
        if (max_bytes < chunk) chunk = max_bytes;
    end

    assign beats = chunk[BEAT_SHIFT + 8 : BEAT_SHIFT];

    logic issue;
    assign issue = (state_q == S_RUN) && !err_q && rd_cmd_ready_i && wr_cmd_ready_i;

    assign rd_cmd_valid_o = (state_q == S_RUN) && !err_q && wr_cmd_ready_i;
    assign wr_cmd_valid_o = (state_q == S_RUN) && !err_q && rd_cmd_ready_i;
    assign rd_cmd_data_o  = {src_q, beats[7:0] - 8'd1};
    assign wr_cmd_data_o  = {dst_q, beats[7:0] - 8'd1};

    assign busy_o = (state_q != S_IDLE);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q       <= S_IDLE;
            src_q         <= '0;
            dst_q         <= '0;
            rem_q         <= '0;
            max_beats_q   <= 9'd16;
            outstanding_q <= '0;
            err_q         <= 1'b0;
            done_o        <= 1'b0;
        end
        else begin
            done_o <= 1'b0;

            if (err_i) err_q <= 1'b1;

            case ({issue, wr_burst_done_i})
                2'b10:   outstanding_q <= outstanding_q + 1'b1;
                2'b01:   outstanding_q <= outstanding_q - 1'b1;
                default: ;
            endcase

            case (state_q)
                S_IDLE: begin
                    if (start_i) begin
                        src_q         <= src_i;
                        dst_q         <= dst_i;
                        rem_q         <= len_i;
                        max_beats_q   <= max_beats_i;
                        outstanding_q <= '0;
                        err_q         <= 1'b0;
                        state_q       <= (len_i == 32'd0) ? S_FIN : S_RUN;
                    end
                end

                S_RUN: begin
                    if (err_q)
                        state_q <= S_DRAIN;     // stop issuing; let what is in flight finish
                    else if (issue) begin
                        src_q <= src_q + chunk;
                        dst_q <= dst_q + chunk;
                        rem_q <= rem_q - chunk;
                        if (rem_q == chunk) state_q <= S_DRAIN;
                    end
                end

                S_DRAIN: begin
                    if (outstanding_q == 16'd0 || (outstanding_q == 16'd1 && wr_burst_done_i))
                        state_q <= S_FIN;
                end

                S_FIN: begin
                    done_o  <= 1'b1;
                    state_q <= S_IDLE;
                end

                default: state_q <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
