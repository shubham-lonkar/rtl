// Copyright (c) 2026 Shubham Lonkar
// SPDX-License-Identifier: MIT

`default_nettype none

// axi_dma_rd -- AXI4 master read channel

module axi_dma_rd
    import axi_dma_pkg::*;
#(
    parameter int DATA_W     = 32,
    parameter int FIFO_DEPTH = 512
) (
    input  wire         clk,
    input  wire         rst_n,

    // burst command: {addr[31:0], arlen[7:0]}
    input  wire         cmd_valid_i,
    input  wire [39:0]  cmd_data_i,
    output logic        cmd_ready_o,

    // AXI4 master, read address
    output logic [31:0] m_araddr_o,
    output logic [7:0]  m_arlen_o,
    output logic [2:0]  m_arsize_o,
    output logic [1:0]  m_arburst_o,
    output logic [3:0]  m_arid_o,
    output logic        m_arvalid_o,
    input  wire         m_arready_i,

    // AXI4 master, read data
    input  wire [DATA_W-1:0] m_rdata_i,
    input  wire [1:0]        m_rresp_i,
    input  wire              m_rlast_i,
    input  wire              m_rvalid_i,
    output logic             m_rready_o,

    // data FIFO
    output logic              fifo_wr_o,
    output logic [DATA_W-1:0] fifo_data_o,
    input  wire [$clog2(FIFO_DEPTH):0] fifo_count_i,

    // status
    output logic       err_o,
    output logic [1:0] resp_o
);

    localparam int BEAT_BYTES = DATA_W / 8;

    typedef enum logic [1:0] { S_IDLE, S_ADDR, S_DATA } state_e;
    state_e state_q;

    logic [31:0] addr_q;
    logic [7:0]  len_q;

    logic [$clog2(FIFO_DEPTH):0] space;
    logic [8:0]                  need;

    assign space = FIFO_DEPTH[$clog2(FIFO_DEPTH):0] - fifo_count_i;
    assign need  = {1'b0, cmd_data_i[7:0]} + 9'd1;      // arlen+1 beats

    logic room;
    assign room = ({7'd0, space} >= {7'd0, need});

    assign cmd_ready_o = (state_q == S_IDLE) && room;

    assign m_araddr_o  = addr_q;
    assign m_arlen_o   = len_q;
    assign m_arsize_o  = 3'($clog2(BEAT_BYTES));        // full-width beats only
    assign m_arburst_o = BURST_INCR;
    assign m_arid_o    = 4'd0;
    assign m_arvalid_o = (state_q == S_ADDR);

    // Unconditional: the space was reserved before ARVALID went out.
    assign m_rready_o  = (state_q == S_DATA);

    assign fifo_wr_o   = (state_q == S_DATA) && m_rvalid_i;
    assign fifo_data_o = m_rdata_i;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= S_IDLE;
            addr_q  <= '0;
            len_q   <= '0;
            err_o   <= 1'b0;
            resp_o  <= RESP_OKAY;
        end
        else begin
            err_o <= 1'b0;                              // pulse

            case (state_q)
                S_IDLE: begin
                    if (cmd_valid_i && room) begin
                        addr_q  <= cmd_data_i[39:8];
                        len_q   <= cmd_data_i[7:0];
                        state_q <= S_ADDR;
                    end
                end

                S_ADDR: if (m_arready_i) state_q <= S_DATA;

                S_DATA: begin
                    if (m_rvalid_i) begin
                        if (m_rresp_i != RESP_OKAY) begin
                            err_o  <= 1'b1;
                            resp_o <= m_rresp_i;
                        end
                        if (m_rlast_i) state_q <= S_IDLE;
                    end
                end

                default: state_q <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
