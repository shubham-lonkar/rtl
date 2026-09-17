// Copyright (c) 2026 Shubham Lonkar
// SPDX-License-Identifier: MIT

// axi_dma_uvm_pkg -- the whole UVM environment in one package

package axi_dma_uvm_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    import axi_dma_pkg::*;

    `uvm_analysis_imp_decl(_axi)
    `uvm_analysis_imp_decl(_lite)

    // Transactions

    // One CSR access on the AXI4-Lite port.
    class axi_lite_txn extends uvm_sequence_item;
        rand bit         is_write;
        rand bit [7:0]   addr;
        rand bit [31:0]  data;
        rand bit [3:0]   strb;
             bit [1:0]   resp;

        constraint c_strb  { strb == 4'hF; }
        constraint c_addr  { addr inside {REG_CTRL, REG_STATUS, REG_SRC,
                                          REG_DST, REG_LEN, REG_BURST, REG_IRQ}; }

        `uvm_object_utils_begin(axi_lite_txn)
            `uvm_field_int(is_write, UVM_ALL_ON)
            `uvm_field_int(addr,     UVM_ALL_ON)
            `uvm_field_int(data,     UVM_ALL_ON)
            `uvm_field_int(resp,     UVM_ALL_ON)
        `uvm_object_utils_end

        function new(string name = "axi_lite_txn");
            super.new(name);
        endfunction
    endclass

    class axi4_burst_txn extends uvm_sequence_item;
        rand bit          is_write;
        rand bit [31:0]   addr;
        rand bit [7:0]    len;         // beats-1
        rand bit [2:0]    size;
        rand bit [1:0]    burst;
             bit [31:0]   data [$];
             bit [1:0]    resp;

        `uvm_object_utils_begin(axi4_burst_txn)
            `uvm_field_int(is_write, UVM_ALL_ON)
            `uvm_field_int(addr,     UVM_ALL_ON)
            `uvm_field_int(len,      UVM_ALL_ON)
            `uvm_field_queue_int(data, UVM_ALL_ON)
        `uvm_object_utils_end

        function new(string name = "axi4_burst_txn");
            super.new(name);
        endfunction

        function int unsigned bytes();
            return (len + 1) * (1 << size);
        endfunction

        function bit crosses_4k();
            return ((addr % BOUNDARY) + bytes()) > BOUNDARY;
        endfunction
    endclass

    class dma_desc_txn extends uvm_sequence_item;
        rand bit [31:0] src;
        rand bit [31:0] dst;
        rand bit [31:0] len;
        rand int        max_beats;

        constraint c_align  { src[1:0] == 2'b00; dst[1:0] == 2'b00; len[1:0] == 2'b00; }
        constraint c_range  { src inside {[0 : 32'h3FFF]};
                              dst inside {[32'h4000 : 32'h7FFF]};
                              len inside {[4 : 4096]};
                              src + len <= 32'h4000;
                              dst + len <= 32'h8000; }
        constraint c_beats  { max_beats inside {1, 2, 4, 8, 16, 64, 256}; }

        constraint c_cross  { soft (src % BOUNDARY) inside {[BOUNDARY-64 : BOUNDARY-4]}; }

        `uvm_object_utils_begin(dma_desc_txn)
            `uvm_field_int(src,       UVM_ALL_ON)
            `uvm_field_int(dst,       UVM_ALL_ON)
            `uvm_field_int(len,       UVM_ALL_ON)
            `uvm_field_int(max_beats, UVM_ALL_ON)
        `uvm_object_utils_end

        function new(string name = "dma_desc_txn");
            super.new(name);
        endfunction
    endclass

    // Configuration
    class axi_dma_cfg extends uvm_object;
        virtual axi_lite_if #(8)  lite_vif;
        virtual axi4_if     #(32) axi_vif;

        int unsigned stall_pct   = 0;      // 0..99
        int unsigned err_rate    = 0;      // 0..99, chance a burst answers SLVERR
        bit          is_active   = 1;

        `uvm_object_utils(axi_dma_cfg)

        function new(string name = "axi_dma_cfg");
            super.new(name);
        endfunction
    endclass

    // AXI4-Lite master agent -- drives the CSR port
    class axi_lite_sequencer extends uvm_sequencer #(axi_lite_txn);
        `uvm_component_utils(axi_lite_sequencer)
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
    endclass

    class axi_lite_driver extends uvm_driver #(axi_lite_txn);
        `uvm_component_utils(axi_lite_driver)

        axi_dma_cfg cfg;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(axi_dma_cfg)::get(this, "", "cfg", cfg))
                `uvm_fatal(get_type_name(), "no cfg")
        endfunction

        task run_phase(uvm_phase phase);
            reset_signals();
            forever begin
                seq_item_port.get_next_item(req);
                drive(req);
                seq_item_port.item_done();
            end
        endtask

        virtual task reset_signals();
            cfg.lite_vif.mst_cb.awvalid <= 1'b0;
            cfg.lite_vif.mst_cb.awaddr  <= '0;
            cfg.lite_vif.mst_cb.wvalid  <= 1'b0;
            cfg.lite_vif.mst_cb.wdata   <= '0;
            cfg.lite_vif.mst_cb.wstrb   <= '0;
            cfg.lite_vif.mst_cb.bready  <= 1'b0;
            cfg.lite_vif.mst_cb.arvalid <= 1'b0;
            cfg.lite_vif.mst_cb.araddr  <= '0;
            cfg.lite_vif.mst_cb.rready  <= 1'b0;
            @(posedge cfg.lite_vif.rst_n);
            @(cfg.lite_vif.mst_cb);
        endtask

        virtual task drive(axi_lite_txn t);
            if (t.is_write) drive_write(t);
            else            drive_read(t);
        endtask

        virtual task drive_write(axi_lite_txn t);
            fork
                begin
                    cfg.lite_vif.mst_cb.awaddr  <= t.addr;
                    cfg.lite_vif.mst_cb.awvalid <= 1'b1;
                    do @(cfg.lite_vif.mst_cb); while (!cfg.lite_vif.mst_cb.awready);
                    cfg.lite_vif.mst_cb.awvalid <= 1'b0;
                end
                begin
                    cfg.lite_vif.mst_cb.wdata  <= t.data;
                    cfg.lite_vif.mst_cb.wstrb  <= t.strb;
                    cfg.lite_vif.mst_cb.wvalid <= 1'b1;
                    do @(cfg.lite_vif.mst_cb); while (!cfg.lite_vif.mst_cb.wready);
                    cfg.lite_vif.mst_cb.wvalid <= 1'b0;
                end
            join

            cfg.lite_vif.mst_cb.bready <= 1'b1;
            do @(cfg.lite_vif.mst_cb); while (!cfg.lite_vif.mst_cb.bvalid);
            t.resp = cfg.lite_vif.mst_cb.bresp;
            cfg.lite_vif.mst_cb.bready <= 1'b0;
        endtask

        virtual task drive_read(axi_lite_txn t);
            cfg.lite_vif.mst_cb.araddr  <= t.addr;
            cfg.lite_vif.mst_cb.arvalid <= 1'b1;
            cfg.lite_vif.mst_cb.rready  <= 1'b1;
            do @(cfg.lite_vif.mst_cb); while (!cfg.lite_vif.mst_cb.arready);
            cfg.lite_vif.mst_cb.arvalid <= 1'b0;

            do @(cfg.lite_vif.mst_cb); while (!cfg.lite_vif.mst_cb.rvalid);
            t.data = cfg.lite_vif.mst_cb.rdata;
            t.resp = cfg.lite_vif.mst_cb.rresp;
            cfg.lite_vif.mst_cb.rready <= 1'b0;
        endtask
    endclass

    class axi_lite_monitor extends uvm_monitor;
        `uvm_component_utils(axi_lite_monitor)

        axi_dma_cfg cfg;
        uvm_analysis_port #(axi_lite_txn) ap;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            ap = new("ap", this);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(axi_dma_cfg)::get(this, "", "cfg", cfg))
                `uvm_fatal(get_type_name(), "no cfg")
        endfunction

        protected bit [7:0]  aw_q [$];
        protected bit [31:0] wdata_q [$];
        protected bit [3:0]  wstrb_q [$];
        protected bit [7:0]  ar_q [$];

        task run_phase(uvm_phase phase);
            fork
                collect_aw();
                collect_w();
                collect_b();
                collect_ar();
                collect_r();
            join
        endtask

        protected task collect_aw();
            forever begin
                @(cfg.lite_vif.mon_cb);
                if (cfg.lite_vif.mon_cb.awvalid && cfg.lite_vif.mon_cb.awready)
                    aw_q.push_back(cfg.lite_vif.mon_cb.awaddr);
            end
        endtask

        protected task collect_w();
            forever begin
                @(cfg.lite_vif.mon_cb);
                if (cfg.lite_vif.mon_cb.wvalid && cfg.lite_vif.mon_cb.wready) begin
                    wdata_q.push_back(cfg.lite_vif.mon_cb.wdata);
                    wstrb_q.push_back(cfg.lite_vif.mon_cb.wstrb);
                end
            end
        endtask

        protected task collect_b();
            axi_lite_txn t;
            forever begin
                @(cfg.lite_vif.mon_cb);
                if (cfg.lite_vif.mon_cb.bvalid && cfg.lite_vif.mon_cb.bready) begin
                    if (aw_q.size() == 0 || wdata_q.size() == 0) begin
                        `uvm_error(get_type_name(), "B response with no pending AW/W")
                    end
                    else begin
                        t = axi_lite_txn::type_id::create("lite_wr");
                        t.is_write = 1'b1;
                        t.addr     = aw_q.pop_front();
                        t.data     = wdata_q.pop_front();
                        t.strb     = wstrb_q.pop_front();
                        t.resp     = cfg.lite_vif.mon_cb.bresp;
                        ap.write(t);
                    end
                end
            end
        endtask

        protected task collect_ar();
            forever begin
                @(cfg.lite_vif.mon_cb);
                if (cfg.lite_vif.mon_cb.arvalid && cfg.lite_vif.mon_cb.arready)
                    ar_q.push_back(cfg.lite_vif.mon_cb.araddr);
            end
        endtask

        protected task collect_r();
            axi_lite_txn t;
            forever begin
                @(cfg.lite_vif.mon_cb);
                if (cfg.lite_vif.mon_cb.rvalid && cfg.lite_vif.mon_cb.rready) begin
                    if (ar_q.size() == 0) begin
                        `uvm_error(get_type_name(), "R beat with no pending AR")
                    end
                    else begin
                        t = axi_lite_txn::type_id::create("lite_rd");
                        t.is_write = 1'b0;
                        t.addr     = ar_q.pop_front();
                        t.data     = cfg.lite_vif.mon_cb.rdata;
                        t.resp     = cfg.lite_vif.mon_cb.rresp;
                        ap.write(t);
                    end
                end
            end
        endtask
    endclass

    class axi_lite_agent extends uvm_agent;
        `uvm_component_utils(axi_lite_agent)

        axi_dma_cfg        cfg;
        axi_lite_sequencer sqr;
        axi_lite_driver    drv;
        axi_lite_monitor   mon;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(axi_dma_cfg)::get(this, "", "cfg", cfg))
                `uvm_fatal(get_type_name(), "no cfg")
            mon = axi_lite_monitor::type_id::create("mon", this);
            if (cfg.is_active) begin
                sqr = axi_lite_sequencer::type_id::create("sqr", this);
                drv = axi_lite_driver::type_id::create("drv", this);
            end
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            if (cfg.is_active)
                drv.seq_item_port.connect(sqr.seq_item_export);
        endfunction
    endclass

    class axi_mem_model extends uvm_object;
        bit [31:0] mem [bit [31:0]];        // keyed by word address

        `uvm_object_utils(axi_mem_model)

        function new(string name = "axi_mem_model");
            super.new(name);
        endfunction

        function bit [31:0] read(bit [31:0] byte_addr);
            bit [31:0] wa = byte_addr >> 2;
            return mem.exists(wa) ? mem[wa] : 32'h0;
        endfunction

        function void write(bit [31:0] byte_addr, bit [31:0] data, bit [3:0] strb);
            bit [31:0] wa  = byte_addr >> 2;
            bit [31:0] old = mem.exists(wa) ? mem[wa] : 32'h0;
            for (int k = 0; k < 4; k++)
                if (strb[k]) old[k*8 +: 8] = data[k*8 +: 8];
            mem[wa] = old;
        endfunction
    endclass

    class axi4_slave_driver extends uvm_driver #(axi4_burst_txn);
        `uvm_component_utils(axi4_slave_driver)

        axi_dma_cfg   cfg;
        axi_mem_model mem;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(axi_dma_cfg)::get(this, "", "cfg", cfg))
                `uvm_fatal(get_type_name(), "no cfg")
            if (!uvm_config_db#(axi_mem_model)::get(this, "", "mem", mem))
                `uvm_fatal(get_type_name(), "no mem")
        endfunction

        localparam int BEAT_BYTES = 4;

        task run_phase(uvm_phase phase);
            reset_signals();
            fork
                read_loop();
                write_loop();
            join
        endtask

        protected task reset_signals();
            cfg.axi_vif.slv_cb.arready <= 1'b0;
            cfg.axi_vif.slv_cb.rvalid  <= 1'b0;
            cfg.axi_vif.slv_cb.rlast   <= 1'b0;
            cfg.axi_vif.slv_cb.rdata   <= '0;
            cfg.axi_vif.slv_cb.rresp   <= RESP_OKAY;
            cfg.axi_vif.slv_cb.awready <= 1'b0;
            cfg.axi_vif.slv_cb.wready  <= 1'b0;
            cfg.axi_vif.slv_cb.bvalid  <= 1'b0;
            cfg.axi_vif.slv_cb.bresp   <= RESP_OKAY;
            @(posedge cfg.axi_vif.rst_n);
            @(cfg.axi_vif.slv_cb);
        endtask

        protected function bit stall();
            return (cfg.stall_pct > 0) && ($urandom_range(99, 0) < cfg.stall_pct);
        endfunction

        protected function int err_beat(int n);
            if (cfg.err_rate == 0)                    return -1;
            if ($urandom_range(99, 0) >= cfg.err_rate) return -1;
            return $urandom_range(n - 1, 0);
        endfunction

        protected task read_loop();
            bit [31:0] a;
            int        n, bad;
            forever begin
                while (stall()) @(cfg.axi_vif.slv_cb);

                cfg.axi_vif.slv_cb.arready <= 1'b1;
                do @(cfg.axi_vif.slv_cb); while (!cfg.axi_vif.slv_cb.arvalid);
                a = cfg.axi_vif.slv_cb.araddr;
                n = cfg.axi_vif.slv_cb.arlen + 1;
                cfg.axi_vif.slv_cb.arready <= 1'b0;

                bad = err_beat(n);

                for (int k = 0; k < n; k++) begin
                    if (stall()) begin
                        cfg.axi_vif.slv_cb.rvalid <= 1'b0;
                        @(cfg.axi_vif.slv_cb);
                    end
                    cfg.axi_vif.slv_cb.rdata  <= mem.read(a + k * BEAT_BYTES);
                    cfg.axi_vif.slv_cb.rresp  <= (k == bad) ? RESP_SLVERR : RESP_OKAY;
                    cfg.axi_vif.slv_cb.rlast  <= (k == n - 1);
                    cfg.axi_vif.slv_cb.rvalid <= 1'b1;
                    do @(cfg.axi_vif.slv_cb); while (!cfg.axi_vif.slv_cb.rready);
                end

                cfg.axi_vif.slv_cb.rvalid <= 1'b0;
                cfg.axi_vif.slv_cb.rlast  <= 1'b0;
            end
        endtask

        protected task write_loop();
            bit [31:0] a;
            int        n, k, bad;
            bit [1:0]  resp;
            forever begin
                while (stall()) @(cfg.axi_vif.slv_cb);

                cfg.axi_vif.slv_cb.awready <= 1'b1;
                do @(cfg.axi_vif.slv_cb); while (!cfg.axi_vif.slv_cb.awvalid);
                a = cfg.axi_vif.slv_cb.awaddr;
                n = cfg.axi_vif.slv_cb.awlen + 1;
                cfg.axi_vif.slv_cb.awready <= 1'b0;

                bad  = err_beat(n);
                resp = RESP_OKAY;
                k    = 0;

                while (k < n) begin
                    if (stall()) begin
                        cfg.axi_vif.slv_cb.wready <= 1'b0;
                        @(cfg.axi_vif.slv_cb);
                        continue;
                    end
                    cfg.axi_vif.slv_cb.wready <= 1'b1;
                    @(cfg.axi_vif.slv_cb);
                    if (cfg.axi_vif.slv_cb.wvalid) begin
                        mem.write(a + k * BEAT_BYTES,
                                  cfg.axi_vif.slv_cb.wdata,
                                  cfg.axi_vif.slv_cb.wstrb);
                        if (k == bad) resp = RESP_SLVERR;

                        if (cfg.axi_vif.slv_cb.wlast && (k != n - 1))
                            `uvm_error(get_type_name(),
                                $sformatf("WLAST on beat %0d of %0d at 0x%08x", k + 1, n, a))
                        if (!cfg.axi_vif.slv_cb.wlast && (k == n - 1))
                            `uvm_error(get_type_name(),
                                $sformatf("no WLAST on final beat %0d at 0x%08x", n, a))
                        k++;
                    end
                end
                cfg.axi_vif.slv_cb.wready <= 1'b0;

                while (stall()) @(cfg.axi_vif.slv_cb);
                cfg.axi_vif.slv_cb.bresp  <= resp;
                cfg.axi_vif.slv_cb.bvalid <= 1'b1;
                do @(cfg.axi_vif.slv_cb); while (!cfg.axi_vif.slv_cb.bready);
                cfg.axi_vif.slv_cb.bvalid <= 1'b0;
            end
        endtask
    endclass

    class axi4_monitor extends uvm_monitor;
        `uvm_component_utils(axi4_monitor)

        axi_dma_cfg cfg;
        uvm_analysis_port #(axi4_burst_txn) ap;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            ap = new("ap", this);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(axi_dma_cfg)::get(this, "", "cfg", cfg))
                `uvm_fatal(get_type_name(), "no cfg")
        endfunction

        protected axi4_burst_txn ar_q [$];
        protected axi4_burst_txn aw_q [$];
        protected axi4_burst_txn b_q  [$];

        task run_phase(uvm_phase phase);
            fork
                collect_ar();
                collect_r();
                collect_aw();
                collect_w();
                collect_b();
            join
        endtask

        protected task collect_ar();
            axi4_burst_txn t;
            forever begin
                @(cfg.axi_vif.mon_cb);
                if (cfg.axi_vif.mon_cb.arvalid && cfg.axi_vif.mon_cb.arready) begin
                    t = axi4_burst_txn::type_id::create("rd_burst");
                    t.is_write = 1'b0;
                    t.addr     = cfg.axi_vif.mon_cb.araddr;
                    t.len      = cfg.axi_vif.mon_cb.arlen;
                    t.size     = cfg.axi_vif.mon_cb.arsize;
                    t.burst    = cfg.axi_vif.mon_cb.arburst;
                    t.resp     = RESP_OKAY;
                    ar_q.push_back(t);
                end
            end
        endtask

        protected task collect_r();
            axi4_burst_txn t;
            forever begin
                @(cfg.axi_vif.mon_cb);
                if (cfg.axi_vif.mon_cb.rvalid && cfg.axi_vif.mon_cb.rready) begin
                    if (ar_q.size() == 0) begin
                        `uvm_error(get_type_name(), "R beat with no outstanding AR")
                    end
                    else begin
                        t = ar_q[0];
                        t.data.push_back(cfg.axi_vif.mon_cb.rdata);
                        // Worst response across the burst, not the last one.
                        if (cfg.axi_vif.mon_cb.rresp != RESP_OKAY)
                            t.resp = cfg.axi_vif.mon_cb.rresp;
                        if (cfg.axi_vif.mon_cb.rlast) begin
                            void'(ar_q.pop_front());
                            ap.write(t);
                        end
                    end
                end
            end
        endtask

        protected task collect_aw();
            axi4_burst_txn t;
            forever begin
                @(cfg.axi_vif.mon_cb);
                if (cfg.axi_vif.mon_cb.awvalid && cfg.axi_vif.mon_cb.awready) begin
                    t = axi4_burst_txn::type_id::create("wr_burst");
                    t.is_write = 1'b1;
                    t.addr     = cfg.axi_vif.mon_cb.awaddr;
                    t.len      = cfg.axi_vif.mon_cb.awlen;
                    t.size     = cfg.axi_vif.mon_cb.awsize;
                    t.burst    = cfg.axi_vif.mon_cb.awburst;
                    t.resp     = RESP_OKAY;
                    aw_q.push_back(t);
                end
            end
        endtask

        protected task collect_w();
            axi4_burst_txn t;
            forever begin
                @(cfg.axi_vif.mon_cb);
                if (cfg.axi_vif.mon_cb.wvalid && cfg.axi_vif.mon_cb.wready) begin
                    if (aw_q.size() == 0) begin
                        `uvm_error(get_type_name(), "W beat with no outstanding AW")
                    end
                    else begin
                        t = aw_q[0];
                        t.data.push_back(cfg.axi_vif.mon_cb.wdata);
                        if (cfg.axi_vif.mon_cb.wlast) begin
                            void'(aw_q.pop_front());
                            b_q.push_back(t);
                        end
                    end
                end
            end
        endtask

        protected task collect_b();
            axi4_burst_txn t;
            forever begin
                @(cfg.axi_vif.mon_cb);
                if (cfg.axi_vif.mon_cb.bvalid && cfg.axi_vif.mon_cb.bready) begin
                    if (b_q.size() == 0) begin
                        `uvm_error(get_type_name(), "B response with no completed write burst")
                    end
                    else begin
                        t = b_q.pop_front();
                        t.resp = cfg.axi_vif.mon_cb.bresp;
                        ap.write(t);
                    end
                end
            end
        endtask
    endclass

    class axi4_slave_agent extends uvm_agent;
        `uvm_component_utils(axi4_slave_agent)

        axi_dma_cfg      cfg;
        axi4_slave_driver drv;
        axi4_monitor      mon;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(axi_dma_cfg)::get(this, "", "cfg", cfg))
                `uvm_fatal(get_type_name(), "no cfg")
            mon = axi4_monitor::type_id::create("mon", this);
            if (cfg.is_active)
                drv = axi4_slave_driver::type_id::create("drv", this);
        endfunction
    endclass

    class axi_dma_scoreboard extends uvm_scoreboard;
        `uvm_component_utils(axi_dma_scoreboard)

        uvm_analysis_imp_axi  #(axi4_burst_txn, axi_dma_scoreboard) axi_imp;
        uvm_analysis_imp_lite #(axi_lite_txn,   axi_dma_scoreboard) lite_imp;

        axi_mem_model mem;
        int unsigned  bursts_seen, bytes_moved;
        int unsigned  descs_checked, descs_with_err, errors;

        // Shadow of the CSR, built from observed writes.
        protected bit [31:0] shadow_src, shadow_dst, shadow_len;

        // State of the descriptor currently in flight.
        protected bit        active;
        protected bit [31:0] act_src, act_dst, act_len;
        protected bit [31:0] expected [$];
        protected axi4_burst_txn rd_bursts [$];
        protected axi4_burst_txn wr_bursts [$];

        function new(string name, uvm_component parent);
            super.new(name, parent);
            axi_imp  = new("axi_imp", this);
            lite_imp = new("lite_imp", this);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(axi_mem_model)::get(this, "", "mem", mem))
                `uvm_fatal(get_type_name(), "no mem")
        endfunction

        // CSR
        virtual function void write_lite(axi_lite_txn t);
            if (t.is_write) begin
                case (t.addr)
                    REG_SRC: shadow_src = t.data;
                    REG_DST: shadow_dst = t.data;
                    REG_LEN: shadow_len = t.data;
                    REG_CTRL: if (t.data[0]) start_descriptor();
                    default: ;
                endcase
            end
            else if (t.addr == REG_STATUS && active && t.data[1]) begin
                finish_descriptor(t.data);
            end
        endfunction

        protected function void start_descriptor();
            act_src = shadow_src;
            act_dst = shadow_dst;
            act_len = shadow_len;

            expected.delete();
            rd_bursts.delete();
            wr_bursts.delete();

            for (int unsigned off = 0; off < act_len; off += 4)
                expected.push_back(mem.read(act_src + off));

            active = 1'b1;
        endfunction

        protected function void finish_descriptor(bit [31:0] status);
            bit err = status[2];

            descs_checked++;
            if (err) descs_with_err++;

            if (!err) begin
                check_data();
                check_tiling(rd_bursts, act_src, "read");
                check_tiling(wr_bursts, act_dst, "write");
            end

            active = 1'b0;
        endfunction

        protected function void check_data();
            int unsigned n = 0;
            foreach (expected[k]) begin
                bit [31:0] got = mem.read(act_dst + k * 4);
                if (got !== expected[k]) begin
                    if (n < 4)      // one bad descriptor should not flood the log
                        `uvm_error(get_type_name(), $sformatf(
                            "data mismatch at dst 0x%08x (+%0d): got 0x%08x expected 0x%08x",
                            act_dst + k * 4, k * 4, got, expected[k]))
                    n++;
                    errors++;
                end
            end
            if (n >= 4)
                `uvm_error(get_type_name(), $sformatf(
                    "%0d total mismatches for descriptor src 0x%08x dst 0x%08x len %0d",
                    n, act_src, act_dst, act_len))
        endfunction

        protected function void check_tiling(ref axi4_burst_txn q [$],
                                             input bit [31:0] base,
                                             input string what);
            bit [31:0] next = base;
            int unsigned total = 0;

            foreach (q[k]) begin
                if (q[k].addr !== next) begin
                    `uvm_error(get_type_name(), $sformatf(
                        "%s burst %0d starts at 0x%08x, expected 0x%08x -- gap or overlap",
                        what, k, q[k].addr, next))
                    errors++;
                end
                next  += q[k].bytes();
                total += q[k].bytes();
            end

            if (total !== act_len) begin
                `uvm_error(get_type_name(), $sformatf(
                    "%s bursts moved %0d bytes, descriptor asked for %0d",
                    what, total, act_len))
                errors++;
            end
        endfunction

        // AXI
        virtual function void write_axi(axi4_burst_txn t);
            bursts_seen++;
            bytes_moved += t.bytes();

            if (t.burst !== BURST_INCR) begin
                `uvm_error(get_type_name(), $sformatf(
                    "burst at 0x%08x is type %b, expected INCR", t.addr, t.burst))
                errors++;
            end
            if (t.addr[1:0] != 2'b00) begin
                `uvm_error(get_type_name(), $sformatf(
                    "burst at 0x%08x is not beat-aligned", t.addr))
                errors++;
            end
            if (t.data.size() != int'(t.len) + 1) begin
                `uvm_error(get_type_name(), $sformatf(
                    "burst at 0x%08x carried %0d beats, AxLEN promised %0d",
                    t.addr, t.data.size(), t.len + 1))
                errors++;
            end

            if (active) begin
                if (t.is_write) wr_bursts.push_back(t);
                else            rd_bursts.push_back(t);
            end
        endfunction

        function void report_phase(uvm_phase phase);
            `uvm_info(get_type_name(), $sformatf(
                "%0d descriptors checked (%0d with injected errors), %0d bursts, %0d bytes",
                descs_checked, descs_with_err, bursts_seen, bytes_moved), UVM_LOW)

            if (descs_checked == 0)
                `uvm_error(get_type_name(),
                           "no descriptor ever completed -- the test checked nothing")
        endfunction
    endclass

    // Coverage
    class axi_dma_coverage extends uvm_subscriber #(axi4_burst_txn);
        `uvm_component_utils(axi_dma_coverage)

        axi4_burst_txn item;

        covergroup cg_burst;
            option.per_instance = 1;

            cp_len: coverpoint item.len {
                bins len_1     = {0};
                bins len_short = {[1:15]};
                bins len_mid   = {[16:63]};
                bins len_long  = {[64:254]};
                bins len_max   = {255};
            }

            cp_off: coverpoint (item.addr % BOUNDARY) {
                bins off_base = {0};
                bins off_lo   = {[1:1023]};
                bins off_mid  = {[1024:3071]};
                bins off_hi   = {[3072:4091]};
                bins off_edge = {[4092:4095]};
            }

            cp_dir: coverpoint item.is_write;

            x_len_off: cross cp_len, cp_off, cp_dir {
                ignore_bins edge_needs_one_beat =
                    binsof(cp_off.off_edge) &&
                    binsof(cp_len) intersect {[1:255]};
            }
        endgroup

        function new(string name, uvm_component parent);
            super.new(name, parent);
            cg_burst = new();
        endfunction

        function void write(axi4_burst_txn t);
            item = t;
            cg_burst.sample();
        endfunction

        function void report_phase(uvm_phase phase);
            `uvm_info(get_type_name(), $sformatf(
                "burst coverage %0.1f%%  (len %0.1f%%, offset %0.1f%%, cross %0.1f%%)",
                cg_burst.get_coverage(),
                cg_burst.cp_len.get_coverage(),
                cg_burst.cp_off.get_coverage(),
                cg_burst.x_len_off.get_coverage()), UVM_LOW)
        endfunction
    endclass

    // Environment
    class axi_dma_env extends uvm_env;
        `uvm_component_utils(axi_dma_env)

        axi_dma_cfg        cfg;
        axi_mem_model      mem;
        axi_lite_agent     lite_agt;
        axi4_slave_agent   axi_agt;
        axi_dma_scoreboard sb;
        axi_dma_coverage   cov;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(axi_dma_cfg)::get(this, "", "cfg", cfg))
                `uvm_fatal(get_type_name(), "no cfg")

            mem = axi_mem_model::type_id::create("mem");
            uvm_config_db#(axi_mem_model)::set(this, "*", "mem", mem);

            lite_agt = axi_lite_agent::type_id::create("lite_agt", this);
            axi_agt  = axi4_slave_agent::type_id::create("axi_agt", this);
            sb       = axi_dma_scoreboard::type_id::create("sb", this);
            cov      = axi_dma_coverage::type_id::create("cov", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            axi_agt.mon.ap.connect(sb.axi_imp);
            axi_agt.mon.ap.connect(cov.analysis_export);
            lite_agt.mon.ap.connect(sb.lite_imp);
        endfunction
    endclass

    // Sequences

    class dma_desc_seq extends uvm_sequence #(axi_lite_txn);
        `uvm_object_utils(dma_desc_seq)

        rand dma_desc_txn desc;

        function new(string name = "dma_desc_seq");
            super.new(name);
            desc = dma_desc_txn::type_id::create("desc");
        endfunction

        localparam int MAX_POLLS = 200000;

        task body();
            bit [31:0] ctrl, status;
            int        polls;

            write_reg(REG_SRC,   desc.src);
            write_reg(REG_DST,   desc.dst);
            write_reg(REG_LEN,   desc.len);
            write_reg(REG_BURST, desc.max_beats);

            read_reg(REG_CTRL, ctrl);
            write_reg(REG_CTRL, (ctrl & ~32'h1) | 32'h1);

            for (polls = 0; polls < MAX_POLLS; polls++) begin
                read_reg(REG_STATUS, status);
                if (status[1]) break;             // DONE
            end

            if (polls == MAX_POLLS)
                `uvm_error(get_type_name(), $sformatf(
                    "descriptor src 0x%08x dst 0x%08x len %0d never reported DONE",
                    desc.src, desc.dst, desc.len))

            write_reg(REG_IRQ, 32'h1);
        endtask

        task automatic write_reg(bit [7:0] addr, bit [31:0] data);
            axi_lite_txn t = axi_lite_txn::type_id::create("wr");
            start_item(t);
            t.is_write = 1'b1;
            t.addr     = addr;
            t.data     = data;
            t.strb     = 4'hF;
            finish_item(t);
        endtask

        task automatic read_reg(bit [7:0] addr, output bit [31:0] data);
            axi_lite_txn t = axi_lite_txn::type_id::create("rd");
            start_item(t);
            t.is_write = 1'b0;
            t.addr     = addr;
            t.strb     = 4'hF;
            finish_item(t);
            data = t.data;        // the driver wrote the response back into it
        endtask
    endclass

    class dma_random_seq extends uvm_sequence #(axi_lite_txn);
        `uvm_object_utils(dma_random_seq)

        rand int unsigned n;
        constraint c_n { n inside {[5:20]}; }

        function new(string name = "dma_random_seq");
            super.new(name);
        endfunction

        task body();
            repeat (n) begin
                dma_desc_seq s = dma_desc_seq::type_id::create("s");
                if (!s.randomize()) `uvm_error(get_type_name(), "randomize failed")
                s.start(m_sequencer);
            end
        endtask
    endclass

    // Tests
    class axi_dma_base_test extends uvm_test;
        `uvm_component_utils(axi_dma_base_test)

        axi_dma_env env;
        axi_dma_cfg cfg;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            cfg = axi_dma_cfg::type_id::create("cfg");

            if (!uvm_config_db#(virtual axi_lite_if #(8))::get(this, "", "lite_vif", cfg.lite_vif))
                `uvm_fatal(get_type_name(), "no lite_vif")
            if (!uvm_config_db#(virtual axi4_if #(32))::get(this, "", "axi_vif", cfg.axi_vif))
                `uvm_fatal(get_type_name(), "no axi_vif")

            configure(cfg);
            uvm_config_db#(axi_dma_cfg)::set(this, "*", "cfg", cfg);
            env = axi_dma_env::type_id::create("env", this);
        endfunction

        // Derived tests override this instead of rebuilding build_phase.
        virtual function void configure(axi_dma_cfg c);
        endfunction

        task run_phase(uvm_phase phase);
            dma_random_seq seq = dma_random_seq::type_id::create("seq");
            phase.raise_objection(this);
            if (!seq.randomize()) `uvm_error(get_type_name(), "randomize failed")
            seq.start(env.lite_agt.sqr);
            phase.drop_objection(this);
        endtask
    endclass

    class axi_dma_smoke_test extends axi_dma_base_test;
        `uvm_component_utils(axi_dma_smoke_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        task run_phase(uvm_phase phase);
            dma_desc_seq seq = dma_desc_seq::type_id::create("seq");
            phase.raise_objection(this);
            if (!seq.randomize() with { desc.len == 64; desc.max_beats == 16; })
                `uvm_error(get_type_name(), "randomize failed")
            seq.start(env.lite_agt.sqr);
            phase.drop_objection(this);
        endtask
    endclass

    // Stress: heavy backpressure on every channel.
    class axi_dma_stall_test extends axi_dma_base_test;
        `uvm_component_utils(axi_dma_stall_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void configure(axi_dma_cfg c);
            c.stall_pct = 50;
        endfunction
    endclass

    class axi_dma_long_test extends axi_dma_base_test;
        `uvm_component_utils(axi_dma_long_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        task run_phase(uvm_phase phase);
            dma_desc_seq seq;
            phase.raise_objection(this);
            repeat (4) begin
                seq = dma_desc_seq::type_id::create("seq");
                if (!seq.randomize() with {
                        desc.len       == 4096;
                        desc.max_beats == 256;
                        desc.src inside {32'h0000, 32'h1000, 32'h2000, 32'h3000};
                        desc.dst inside {32'h4000, 32'h5000, 32'h6000, 32'h7000}; })
                    `uvm_error(get_type_name(), "randomize failed")
                seq.start(env.lite_agt.sqr);
            end
            phase.drop_objection(this);
        endtask
    endclass

    class axi_dma_err_test extends axi_dma_base_test;
        `uvm_component_utils(axi_dma_err_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void configure(axi_dma_cfg c);
            c.stall_pct = 20;
            c.err_rate  = 10;
        endfunction
    endclass

endpackage
