// Copyright (c) 2026 Shubham Lonkar
// SPDX-License-Identifier: MIT

`default_nettype none

// axi_dma_wr -- AXI4 master write channel

module axi_dma_wr
    import axi_dma_pkg::*;
#(
    parameter int DATA_W = 32
) (
    input  wire         clk,
    input  wire         rst_n,

    // burst command: {addr[31:0], awlen[7:0]}
    input  wire         cmd_valid_i,
    input  wire [39:0]  cmd_data_i,
    output logic        cmd_ready_o,

    // AXI4 master, write address
    output logic [31:0] m_awaddr_o,
    output logic [7:0]  m_awlen_o,
    output logic [2:0]  m_awsize_o,
    output logic [1:0]  m_awburst_o,
    output logic [3:0]  m_awid_o,
    output logic        m_awvalid_o,
    input  wire         m_awready_i,

    // AXI4 master, write data
    output logic [DATA_W-1:0]   m_wdata_o,
    output logic [DATA_W/8-1:0] m_wstrb_o,
    output logic                m_wlast_o,
    output logic                m_wvalid_o,
    input  wire                 m_wready_i,

    // AXI4 master, write response
    input  wire [1:0]   m_bresp_i,
    input  wire         m_bvalid_i,
    output logic        m_bready_o,

    // data FIFO
    input  wire [DATA_W-1:0] fifo_data_i,
    input  wire              fifo_empty_i,
    output logic             fifo_rd_o,

    // status
    output logic       burst_done_o,       // one pulse per B response
    output logic       err_o,
    output logic [1:0] resp_o
);

    localparam int BEAT_BYTES = DATA_W / 8;

    typedef enum logic [1:0] { S_IDLE, S_ADDR, S_DATA, S_RESP } state_e;
    state_e state_q;

    logic [31:0] addr_q;
    logic [7:0]  len_q;
    logic [8:0]  beat_q;                    // beats sent so far

    assign cmd_ready_o = (state_q == S_IDLE) && cmd_valid_i;

    assign m_awaddr_o  = addr_q;
    assign m_awlen_o   = len_q;
    assign m_awsize_o  = 3'($clog2(BEAT_BYTES));
    assign m_awburst_o = BURST_INCR;
    assign m_awid_o    = 4'd0;
    assign m_awvalid_o = (state_q == S_ADDR);

    assign m_wdata_o  = fifo_data_i;
    assign m_wstrb_o  = {(DATA_W/8){1'b1}};
    assign m_wvalid_o = (state_q == S_DATA) && !fifo_empty_i;
    assign m_wlast_o  = (state_q == S_DATA) && (beat_q == {1'b0, len_q});

    assign fifo_rd_o  = m_wvalid_o && m_wready_i;

    assign m_bready_o = (state_q == S_RESP);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q      <= S_IDLE;
            addr_q       <= '0;
            len_q        <= '0;
            beat_q       <= '0;
            burst_done_o <= 1'b0;
            err_o        <= 1'b0;
            resp_o       <= RESP_OKAY;
        end
        else begin
            burst_done_o <= 1'b0;           // pulses
            err_o        <= 1'b0;

            case (state_q)
                S_IDLE: begin
                    if (cmd_valid_i) begin
                        addr_q  <= cmd_data_i[39:8];
                        len_q   <= cmd_data_i[7:0];
                        beat_q  <= '0;
                        state_q <= S_ADDR;
                    end
                end

                S_ADDR: if (m_awready_i) state_q <= S_DATA;

                S_DATA: begin
                    if (m_wvalid_o && m_wready_i) begin
                        beat_q <= beat_q + 1'b1;
                        if (m_wlast_o) state_q <= S_RESP;
                    end
                end

                S_RESP: begin
                    if (m_bvalid_i) begin
                        burst_done_o <= 1'b1;
                        if (m_bresp_i != RESP_OKAY) begin
                            err_o  <= 1'b1;
                            resp_o <= m_bresp_i;
                        end
                        state_q <= S_IDLE;
                    end
                end

                default: state_q <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
