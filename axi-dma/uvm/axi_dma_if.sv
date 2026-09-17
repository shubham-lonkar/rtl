// Copyright (c) 2026 Shubham Lonkar
// SPDX-License-Identifier: MIT

`timescale 1ns/1ps

// Interfaces for the UVM environment

// AXI4-Lite: the CSR programming port
interface axi_lite_if #(parameter int ADDR_W = 8) (input logic clk, input logic rst_n);

    logic [ADDR_W-1:0] awaddr;
    logic              awvalid, awready;
    logic [31:0]       wdata;
    logic [3:0]        wstrb;
    logic              wvalid,  wready;
    logic [1:0]        bresp;
    logic              bvalid,  bready;
    logic [ADDR_W-1:0] araddr;
    logic              arvalid, arready;
    logic [31:0]       rdata;
    logic [1:0]        rresp;
    logic              rvalid,  rready;

    clocking mst_cb @(posedge clk);
        default input #1step output #1;
        output awaddr, awvalid, wdata, wstrb, wvalid, bready,
               araddr, arvalid, rready;
        input  awready, wready, bresp, bvalid, arready, rdata, rresp, rvalid;
    endclocking

    clocking mon_cb @(posedge clk);
        default input #1step;
        input awaddr, awvalid, awready, wdata, wstrb, wvalid, wready,
              bresp, bvalid, bready, araddr, arvalid, arready,
              rdata, rresp, rvalid, rready;
    endclocking

    modport mst (clocking mst_cb, input clk, rst_n);
    modport mon (clocking mon_cb, input clk, rst_n);

endinterface

interface axi4_if #(parameter int DATA_W = 32) (input logic clk, input logic rst_n);

    logic [31:0]        awaddr;
    logic [7:0]         awlen;
    logic [2:0]         awsize;
    logic [1:0]         awburst;
    logic [3:0]         awid;
    logic               awvalid, awready;

    logic [DATA_W-1:0]  wdata;
    logic [DATA_W/8-1:0] wstrb;
    logic               wlast, wvalid, wready;

    logic [1:0]         bresp;
    logic               bvalid, bready;

    logic [31:0]        araddr;
    logic [7:0]         arlen;
    logic [2:0]         arsize;
    logic [1:0]         arburst;
    logic [3:0]         arid;
    logic               arvalid, arready;

    logic [DATA_W-1:0]  rdata;
    logic [1:0]         rresp;
    logic               rlast, rvalid, rready;

    clocking slv_cb @(posedge clk);
        default input #1step output #1;
        output awready, wready, bresp, bvalid, arready, rdata, rresp, rlast, rvalid;
        input  awaddr, awlen, awsize, awburst, awid, awvalid,
               wdata, wstrb, wlast, wvalid, bready,
               araddr, arlen, arsize, arburst, arid, arvalid, rready;
    endclocking

    clocking mon_cb @(posedge clk);
        default input #1step;
        input awaddr, awlen, awsize, awburst, awid, awvalid, awready,
              wdata, wstrb, wlast, wvalid, wready, bresp, bvalid, bready,
              araddr, arlen, arsize, arburst, arid, arvalid, arready,
              rdata, rresp, rlast, rvalid, rready;
    endclocking

    modport slv (clocking slv_cb, input clk, rst_n);
    modport mon (clocking mon_cb, input clk, rst_n);

    aw_stable: assert property (@(posedge clk) disable iff (!rst_n)
        (awvalid && !awready) |=> (awvalid && $stable(awaddr) && $stable(awlen)
                                   && $stable(awsize) && $stable(awburst)))
        else $error("AW payload changed or AWVALID dropped before AWREADY");

    ar_stable: assert property (@(posedge clk) disable iff (!rst_n)
        (arvalid && !arready) |=> (arvalid && $stable(araddr) && $stable(arlen)
                                   && $stable(arsize) && $stable(arburst)))
        else $error("AR payload changed or ARVALID dropped before ARREADY");

    w_stable: assert property (@(posedge clk) disable iff (!rst_n)
        (wvalid && !wready) |=> (wvalid && $stable(wdata) && $stable(wstrb)
                                 && $stable(wlast)))
        else $error("W payload changed or WVALID dropped before WREADY");

    function automatic int burst_bytes(input logic [7:0] len, input logic [2:0] size);
        return (int'(len) + 1) * (1 << int'(size));
    endfunction

    aw_4kb: assert property (@(posedge clk) disable iff (!rst_n)
        (awvalid && awready) |->
            ((int'(awaddr) % 4096) + burst_bytes(awlen, awsize) <= 4096))
        else $error("AW burst crosses a 4KB boundary: addr 0x%08x offset %0d len %0d size %0d",
                    $sampled(awaddr), $sampled(awaddr) & 32'hFFF,
                    $sampled(awlen), $sampled(awsize));

    ar_4kb: assert property (@(posedge clk) disable iff (!rst_n)
        (arvalid && arready) |->
            ((int'(araddr) % 4096) + burst_bytes(arlen, arsize) <= 4096))
        else $error("AR burst crosses a 4KB boundary: addr 0x%08x offset %0d len %0d size %0d",
                    $sampled(araddr), $sampled(araddr) & 32'hFFF,
                    $sampled(arlen), $sampled(arsize));

    // Only INCR makes sense for a block copy.
    aw_incr: assert property (@(posedge clk) disable iff (!rst_n)
        (awvalid && awready) |-> (awburst == 2'b01))
        else $error("AW burst type is not INCR");

    ar_incr: assert property (@(posedge clk) disable iff (!rst_n)
        (arvalid && arready) |-> (arburst == 2'b01))
        else $error("AR burst type is not INCR");

endinterface
