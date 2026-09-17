// Copyright (c) 2026 Shubham Lonkar
// SPDX-License-Identifier: MIT

`timescale 1ns/1ps

// tb_axi_dma_uvm -- static top for the UVM environment

module tb_axi_dma_uvm;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import axi_dma_uvm_pkg::*;

    localparam int DATA_W = 32;

    logic clk = 1'b0;
    logic rst_n;

    always #5 clk = ~clk;

    initial begin
        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
    end

    axi_lite_if #(.ADDR_W(8))    lite (.clk(clk), .rst_n(rst_n));
    axi4_if     #(.DATA_W(DATA_W)) axi (.clk(clk), .rst_n(rst_n));

    axi_dma_top #(
        .DATA_W(DATA_W), .DATA_FIFO_DEPTH(256), .CMD_FIFO_DEPTH(4)
    ) dut (
        .clk(clk), .rst_n(rst_n),

        .s_awaddr_i(lite.awaddr), .s_awvalid_i(lite.awvalid), .s_awready_o(lite.awready),
        .s_wdata_i(lite.wdata),   .s_wstrb_i(lite.wstrb),     .s_wvalid_i(lite.wvalid),
        .s_wready_o(lite.wready),
        .s_bresp_o(lite.bresp),   .s_bvalid_o(lite.bvalid),   .s_bready_i(lite.bready),
        .s_araddr_i(lite.araddr), .s_arvalid_i(lite.arvalid), .s_arready_o(lite.arready),
        .s_rdata_o(lite.rdata),   .s_rresp_o(lite.rresp),     .s_rvalid_o(lite.rvalid),
        .s_rready_i(lite.rready),

        .m_awaddr_o(axi.awaddr), .m_awlen_o(axi.awlen), .m_awsize_o(axi.awsize),
        .m_awburst_o(axi.awburst), .m_awid_o(axi.awid),
        .m_awvalid_o(axi.awvalid), .m_awready_i(axi.awready),
        .m_wdata_o(axi.wdata), .m_wstrb_o(axi.wstrb), .m_wlast_o(axi.wlast),
        .m_wvalid_o(axi.wvalid), .m_wready_i(axi.wready),
        .m_bresp_i(axi.bresp), .m_bvalid_i(axi.bvalid), .m_bready_o(axi.bready),
        .m_araddr_o(axi.araddr), .m_arlen_o(axi.arlen), .m_arsize_o(axi.arsize),
        .m_arburst_o(axi.arburst), .m_arid_o(axi.arid),
        .m_arvalid_o(axi.arvalid), .m_arready_i(axi.arready),
        .m_rdata_i(axi.rdata), .m_rresp_i(axi.rresp), .m_rlast_i(axi.rlast),
        .m_rvalid_i(axi.rvalid), .m_rready_o(axi.rready),

        .irq_o()
    );

    initial begin
        uvm_config_db#(virtual axi_lite_if #(8))::set(null, "uvm_test_top", "lite_vif", lite);
        uvm_config_db#(virtual axi4_if #(32))::set(null, "uvm_test_top", "axi_vif", axi);
        run_test("axi_dma_smoke_test");
    end

    initial begin
        #5_000_000;
        `uvm_fatal("TIMEOUT", "global timeout")
    end

endmodule
