// Copyright (c) 2026 Shubham Lonkar
// SPDX-License-Identifier: MIT

`default_nettype none

// axi_dma_csr -- AXI4-Lite slave holding the descriptor registers

module axi_dma_csr
    import axi_dma_pkg::*;
#(
    parameter int ADDR_W = 8
) (
    input  wire              clk,
    input  wire              rst_n,

    // AXI4-Lite slave
    input  wire [ADDR_W-1:0] s_awaddr_i,
    input  wire              s_awvalid_i,
    output logic             s_awready_o,

    input  wire [31:0]       s_wdata_i,
    input  wire [3:0]        s_wstrb_i,
    input  wire              s_wvalid_i,
    output logic             s_wready_o,

    output logic [1:0]       s_bresp_o,
    output logic             s_bvalid_o,
    input  wire              s_bready_i,

    input  wire [ADDR_W-1:0] s_araddr_i,
    input  wire              s_arvalid_i,
    output logic             s_arready_o,

    output logic [31:0]      s_rdata_o,
    output logic [1:0]       s_rresp_o,
    output logic             s_rvalid_o,
    input  wire              s_rready_i,

    // to the engine
    output logic             start_o,           // one-cycle pulse
    output logic [31:0]      src_o,
    output logic [31:0]      dst_o,
    output logic [31:0]      len_o,
    output logic [8:0]       max_beats_o,       // 1..256

    input  wire              busy_i,
    input  wire              done_i,            // one-cycle pulse from the FSM
    input  wire              err_i,
    input  wire [1:0]        resp_i,

    output logic             irq_o
);

    logic [31:0] src_q, dst_q, len_q;
    logic [8:0]  max_beats_q;
    logic        irq_en_q, done_q, err_q;
    logic [1:0]  resp_q;

    assign src_o       = src_q;
    assign dst_o       = dst_q;
    assign len_o       = len_q;
    assign max_beats_o = max_beats_q;
    assign irq_o       = irq_en_q && done_q;

    // write channel
    logic              aw_q, w_q;
    logic [ADDR_W-1:0] awaddr_q;
    logic [31:0]       wdata_q;
    logic [3:0]        wstrb_q;
    logic              do_write;

    assign s_awready_o = !aw_q;
    assign s_wready_o  = !w_q;
    assign do_write    = aw_q && w_q && !s_bvalid_o;

    function automatic logic [31:0] merge (input logic [31:0] old,
                                           input logic [31:0] nw,
                                           input logic [3:0]  strb);
        for (int k = 0; k < 4; k++)
            merge[k*8 +: 8] = strb[k] ? nw[k*8 +: 8] : old[k*8 +: 8];
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aw_q        <= 1'b0;
            w_q         <= 1'b0;
            awaddr_q    <= '0;
            wdata_q     <= '0;
            wstrb_q     <= '0;
            s_bvalid_o  <= 1'b0;
            s_bresp_o   <= RESP_OKAY;

            src_q       <= '0;
            dst_q       <= '0;
            len_q       <= '0;
            max_beats_q <= 9'd16;
            irq_en_q    <= 1'b0;
            done_q      <= 1'b0;
            err_q       <= 1'b0;
            resp_q      <= RESP_OKAY;
            start_o     <= 1'b0;
        end
        else begin
            start_o <= 1'b0;                    // default: pulse

            if (s_awvalid_i && s_awready_o) begin
                aw_q     <= 1'b1;
                awaddr_q <= s_awaddr_i;
            end
            if (s_wvalid_i && s_wready_o) begin
                w_q     <= 1'b1;
                wdata_q <= s_wdata_i;
                wstrb_q <= s_wstrb_i;
            end

            if (do_write) begin
                aw_q       <= 1'b0;
                w_q        <= 1'b0;
                s_bvalid_o <= 1'b1;
                s_bresp_o  <= RESP_OKAY;        // no illegal offsets: unmapped reads as 0

                case (awaddr_q)
                    REG_CTRL: begin
                        if (wdata_q[0] && !busy_i) begin
                            start_o <= 1'b1;
                            done_q  <= 1'b0;
                            err_q   <= 1'b0;
                            resp_q  <= RESP_OKAY;
                        end
                        irq_en_q <= wdata_q[2];
                    end
                    REG_SRC:   src_q       <= merge(src_q, wdata_q, wstrb_q);
                    REG_DST:   dst_q       <= merge(dst_q, wdata_q, wstrb_q);
                    REG_LEN:   len_q       <= merge(len_q, wdata_q, wstrb_q);
                    REG_BURST: begin
                        if (wdata_q[8:0] == 9'd0)              max_beats_q <= 9'd1;
                        else if (wdata_q[31:9] != '0)          max_beats_q <= 9'd256;
                        else if (wdata_q[8:0] > 9'd256)        max_beats_q <= 9'd256;
                        else                                    max_beats_q <= wdata_q[8:0];
                    end
                    REG_IRQ:   if (wdata_q[0]) done_q <= 1'b0;   // W1C
                    default:   ;
                endcase
            end

            if (s_bvalid_o && s_bready_i)
                s_bvalid_o <= 1'b0;

            if (done_i) done_q <= 1'b1;
            if (err_i) begin
                err_q  <= 1'b1;
                resp_q <= resp_i;
            end
        end
    end

    // read channel
    logic [31:0] rdata_c;

    always_comb begin
        case (s_araddr_i)
            REG_CTRL:   rdata_c = {29'd0, irq_en_q, 1'b0, 1'b0};
            REG_STATUS: rdata_c = {27'd0, resp_q, err_q, done_q, busy_i};
            REG_SRC:    rdata_c = src_q;
            REG_DST:    rdata_c = dst_q;
            REG_LEN:    rdata_c = len_q;
            REG_BURST:  rdata_c = {23'd0, max_beats_q};
            REG_IRQ:    rdata_c = {31'd0, done_q};
            default:    rdata_c = 32'd0;
        endcase
    end

    assign s_arready_o = !s_rvalid_o;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_rvalid_o <= 1'b0;
            s_rdata_o  <= '0;
            s_rresp_o  <= RESP_OKAY;
        end
        else begin
            if (s_arvalid_i && s_arready_o) begin
                s_rvalid_o <= 1'b1;
                s_rdata_o  <= rdata_c;
                s_rresp_o  <= RESP_OKAY;
            end
            else if (s_rvalid_o && s_rready_i) begin
                s_rvalid_o <= 1'b0;
            end
        end
    end

endmodule

`default_nettype wire
