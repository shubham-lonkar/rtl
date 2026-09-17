// Copyright (c) 2026 Shubham Lonkar
// SPDX-License-Identifier: MIT

`default_nettype none

// axi_dma_top -- AXI4-Lite programmed, AXI4 mastering block-copy DMA

module axi_dma_top
    import axi_dma_pkg::*;
#(
    parameter int DATA_W           = 32,
    parameter int DATA_FIFO_DEPTH  = 64,     // power of two
    parameter int CMD_FIFO_DEPTH   = 4
) (
    input  wire         clk,
    input  wire         rst_n,

    // AXI4-Lite slave: register programming
    input  wire [7:0]   s_awaddr_i,
    input  wire         s_awvalid_i,
    output logic        s_awready_o,
    input  wire [31:0]  s_wdata_i,
    input  wire [3:0]   s_wstrb_i,
    input  wire         s_wvalid_i,
    output logic        s_wready_o,
    output logic [1:0]  s_bresp_o,
    output logic        s_bvalid_o,
    input  wire         s_bready_i,
    input  wire [7:0]   s_araddr_i,
    input  wire         s_arvalid_i,
    output logic        s_arready_o,
    output logic [31:0] s_rdata_o,
    output logic [1:0]  s_rresp_o,
    output logic        s_rvalid_o,
    input  wire         s_rready_i,

    // AXI4 master: the data mover
    output logic [31:0] m_awaddr_o,
    output logic [7:0]  m_awlen_o,
    output logic [2:0]  m_awsize_o,
    output logic [1:0]  m_awburst_o,
    output logic [3:0]  m_awid_o,
    output logic        m_awvalid_o,
    input  wire         m_awready_i,

    output logic [DATA_W-1:0]   m_wdata_o,
    output logic [DATA_W/8-1:0] m_wstrb_o,
    output logic                m_wlast_o,
    output logic                m_wvalid_o,
    input  wire                 m_wready_i,

    input  wire [1:0]   m_bresp_i,
    input  wire         m_bvalid_i,
    output logic        m_bready_o,

    output logic [31:0] m_araddr_o,
    output logic [7:0]  m_arlen_o,
    output logic [2:0]  m_arsize_o,
    output logic [1:0]  m_arburst_o,
    output logic [3:0]  m_arid_o,
    output logic        m_arvalid_o,
    input  wire         m_arready_i,

    input  wire [DATA_W-1:0] m_rdata_i,
    input  wire [1:0]        m_rresp_i,
    input  wire              m_rlast_i,
    input  wire              m_rvalid_i,
    output logic             m_rready_o,

    output logic        irq_o
);

    // CSR <-> engine
    logic        start, busy, done;
    logic [31:0] src, dst, len;
    logic [8:0]  max_beats_csr, max_beats_eff;

    logic        rd_err, wr_err, any_err;
    logic [1:0]  rd_resp, wr_resp, any_resp;

    assign any_err  = rd_err || wr_err;
    assign any_resp = rd_err ? rd_resp : wr_resp;

    always_comb begin
        max_beats_eff = max_beats_csr;
        if (max_beats_csr > DATA_FIFO_DEPTH[8:0])
            max_beats_eff = DATA_FIFO_DEPTH[8:0];
    end

    axi_dma_csr u_csr (
        .clk(clk), .rst_n(rst_n),
        .s_awaddr_i(s_awaddr_i), .s_awvalid_i(s_awvalid_i), .s_awready_o(s_awready_o),
        .s_wdata_i(s_wdata_i), .s_wstrb_i(s_wstrb_i), .s_wvalid_i(s_wvalid_i),
        .s_wready_o(s_wready_o),
        .s_bresp_o(s_bresp_o), .s_bvalid_o(s_bvalid_o), .s_bready_i(s_bready_i),
        .s_araddr_i(s_araddr_i), .s_arvalid_i(s_arvalid_i), .s_arready_o(s_arready_o),
        .s_rdata_o(s_rdata_o), .s_rresp_o(s_rresp_o), .s_rvalid_o(s_rvalid_o),
        .s_rready_i(s_rready_i),
        .start_o(start), .src_o(src), .dst_o(dst), .len_o(len),
        .max_beats_o(max_beats_csr),
        .busy_i(busy), .done_i(done), .err_i(any_err), .resp_i(any_resp),
        .irq_o(irq_o)
    );

    // command queues
    logic        rd_cmd_valid, wr_cmd_valid;
    logic [39:0] rd_cmd_data,  wr_cmd_data;
    logic        rd_cmd_full,  wr_cmd_full;

    logic        rd_q_valid, wr_q_valid;
    logic [39:0] rd_q_data,  wr_q_data;
    logic        rd_q_pop,   wr_q_pop;
    logic        rd_q_empty, wr_q_empty;

    logic        wr_burst_done;

    axi_dma_split #(.DATA_W(DATA_W)) u_split (
        .clk(clk), .rst_n(rst_n),
        .start_i(start), .src_i(src), .dst_i(dst), .len_i(len),
        .max_beats_i(max_beats_eff),
        .rd_cmd_valid_o(rd_cmd_valid), .rd_cmd_data_o(rd_cmd_data),
        .rd_cmd_ready_i(!rd_cmd_full),
        .wr_cmd_valid_o(wr_cmd_valid), .wr_cmd_data_o(wr_cmd_data),
        .wr_cmd_ready_i(!wr_cmd_full),
        .wr_burst_done_i(wr_burst_done), .err_i(any_err),
        .busy_o(busy), .done_o(done)
    );

    axi_dma_fifo #(.WIDTH(40), .DEPTH(CMD_FIFO_DEPTH)) u_rd_cmd_q (
        .clk(clk), .rst_n(rst_n),
        .wr_en_i(rd_cmd_valid && !rd_cmd_full), .wr_data_i(rd_cmd_data), .full_o(rd_cmd_full),
        .rd_en_i(rd_q_pop), .rd_data_o(rd_q_data), .empty_o(rd_q_empty),
        .count_o()
    );
    assign rd_q_valid = !rd_q_empty;

    axi_dma_fifo #(.WIDTH(40), .DEPTH(CMD_FIFO_DEPTH)) u_wr_cmd_q (
        .clk(clk), .rst_n(rst_n),
        .wr_en_i(wr_cmd_valid && !wr_cmd_full), .wr_data_i(wr_cmd_data), .full_o(wr_cmd_full),
        .rd_en_i(wr_q_pop), .rd_data_o(wr_q_data), .empty_o(wr_q_empty),
        .count_o()
    );
    assign wr_q_valid = !wr_q_empty;

    // data path
    logic                            dfifo_wr, dfifo_rd, dfifo_empty;
    logic [DATA_W-1:0]               dfifo_wdata, dfifo_rdata;
    logic [$clog2(DATA_FIFO_DEPTH):0] dfifo_count;

    axi_dma_fifo #(.WIDTH(DATA_W), .DEPTH(DATA_FIFO_DEPTH)) u_data_q (
        .clk(clk), .rst_n(rst_n),
        .wr_en_i(dfifo_wr), .wr_data_i(dfifo_wdata), .full_o(),
        .rd_en_i(dfifo_rd), .rd_data_o(dfifo_rdata), .empty_o(dfifo_empty),
        .count_o(dfifo_count)
    );

    axi_dma_rd #(.DATA_W(DATA_W), .FIFO_DEPTH(DATA_FIFO_DEPTH)) u_rd (
        .clk(clk), .rst_n(rst_n),
        .cmd_valid_i(rd_q_valid), .cmd_data_i(rd_q_data), .cmd_ready_o(rd_q_pop),
        .m_araddr_o(m_araddr_o), .m_arlen_o(m_arlen_o), .m_arsize_o(m_arsize_o),
        .m_arburst_o(m_arburst_o), .m_arid_o(m_arid_o),
        .m_arvalid_o(m_arvalid_o), .m_arready_i(m_arready_i),
        .m_rdata_i(m_rdata_i), .m_rresp_i(m_rresp_i), .m_rlast_i(m_rlast_i),
        .m_rvalid_i(m_rvalid_i), .m_rready_o(m_rready_o),
        .fifo_wr_o(dfifo_wr), .fifo_data_o(dfifo_wdata), .fifo_count_i(dfifo_count),
        .err_o(rd_err), .resp_o(rd_resp)
    );

    axi_dma_wr #(.DATA_W(DATA_W)) u_wr (
        .clk(clk), .rst_n(rst_n),
        .cmd_valid_i(wr_q_valid), .cmd_data_i(wr_q_data), .cmd_ready_o(wr_q_pop),
        .m_awaddr_o(m_awaddr_o), .m_awlen_o(m_awlen_o), .m_awsize_o(m_awsize_o),
        .m_awburst_o(m_awburst_o), .m_awid_o(m_awid_o),
        .m_awvalid_o(m_awvalid_o), .m_awready_i(m_awready_i),
        .m_wdata_o(m_wdata_o), .m_wstrb_o(m_wstrb_o), .m_wlast_o(m_wlast_o),
        .m_wvalid_o(m_wvalid_o), .m_wready_i(m_wready_i),
        .m_bresp_i(m_bresp_i), .m_bvalid_i(m_bvalid_i), .m_bready_o(m_bready_o),
        .fifo_data_i(dfifo_rdata), .fifo_empty_i(dfifo_empty), .fifo_rd_o(dfifo_rd),
        .burst_done_o(wr_burst_done), .err_o(wr_err), .resp_o(wr_resp)
    );

endmodule

`default_nettype wire
