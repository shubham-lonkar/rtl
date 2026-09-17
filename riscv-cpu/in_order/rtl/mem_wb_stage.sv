// Copyright (c) 2026 Shubham Lonkar
// SPDX-License-Identifier: MIT

`default_nettype none

// mem_wb_stage -- the data memory port, the MEM/WB register, and the writeback mux

module mem_wb_stage
    import riscv_pkg::*;
(
    input  wire         clk,
    input  wire         rst_n,

    // EX/MEM
    input  wire  [31:0] ex_mem_alu_i,
    input  wire  [31:0] ex_mem_rs2_i,
    input  wire  [31:0] ex_mem_pc4_i,
    input  wire  [4:0]  ex_mem_rd_addr_i,
    input  wire  [2:0]  ex_mem_funct3_i,
    input  wire  ctrl_t ex_mem_ctrl_i,
    input  wire         ex_mem_valid_i,

    // data memory
    output logic [31:0] dmem_addr_o,
    output logic [31:0] dmem_wdata_o,
    output logic [3:0]  dmem_be_o,
    output logic        dmem_we_o,
    input  wire  [31:0] dmem_rdata_i,

    // write port, to regfile
    output logic [4:0]  wb_rd_addr_o,
    output logic [31:0] wb_rd_data_o,
    output logic        wb_we_o,

    // for the hazard unit
    output ctrl_t       mem_wb_ctrl_o,
    output logic [4:0]  mem_wb_rd_addr_o,
    output logic        mem_wb_valid_o
);

    logic [1:0] st_off;
    assign st_off = ex_mem_alu_i[1:0];

    always_comb begin
        case (ex_mem_funct3_i)
            MEM_B:   dmem_be_o = 4'b0001 << st_off;
            MEM_H:   dmem_be_o = st_off[1] ? 4'b1100 : 4'b0011;
            default: dmem_be_o = 4'b1111;              // MEM_W
        endcase
    end

    always_comb begin
        case (ex_mem_funct3_i)
            MEM_B:   dmem_wdata_o = {4{ex_mem_rs2_i[7:0]}};
            MEM_H:   dmem_wdata_o = {2{ex_mem_rs2_i[15:0]}};
            default: dmem_wdata_o = ex_mem_rs2_i;      // MEM_W
        endcase
    end

    assign dmem_addr_o = ex_mem_alu_i;
    assign dmem_we_o   = ex_mem_ctrl_i.mem_write && ex_mem_valid_i;

    // MEM/WB
    logic [31:0] mem_wb_alu, mem_wb_load, mem_wb_pc4;
    logic [2:0]  mem_wb_funct3;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_wb_alu       <= '0;
            mem_wb_load      <= '0;
            mem_wb_pc4       <= '0;
            mem_wb_funct3    <= '0;
            mem_wb_rd_addr_o <= '0;
            mem_wb_ctrl_o    <= CTRL_NOP;
            mem_wb_valid_o   <= 1'b0;
        end
        else begin
            mem_wb_alu       <= ex_mem_alu_i;
            mem_wb_load      <= dmem_rdata_i;   // memory is combinational in v1
            mem_wb_pc4       <= ex_mem_pc4_i;
            mem_wb_funct3    <= ex_mem_funct3_i;
            mem_wb_rd_addr_o <= ex_mem_rd_addr_i;
            mem_wb_ctrl_o    <= ex_mem_ctrl_i;
            mem_wb_valid_o   <= ex_mem_valid_i;
        end
    end

    logic [1:0]  ld_off;
    logic [7:0]  ld_byte;
    logic [15:0] ld_half;

    assign ld_off  = mem_wb_alu[1:0];
    assign ld_byte = mem_wb_load[8*ld_off +: 8];
    assign ld_half = ld_off[1] ? mem_wb_load[31:16] : mem_wb_load[15:0];

    logic [31:0] load_ext;

    always_comb begin
        case (mem_wb_funct3)
            MEM_B:   load_ext = {{24{ld_byte[7]}},  ld_byte};
            MEM_H:   load_ext = {{16{ld_half[15]}}, ld_half};
            MEM_BU:  load_ext = {24'd0, ld_byte};
            MEM_HU:  load_ext = {16'd0, ld_half};
            default: load_ext = mem_wb_load;           // MEM_W
        endcase
    end

    always_comb begin
        case (mem_wb_ctrl_o.wb_sel)
            WB_LOAD: wb_rd_data_o = load_ext;
            WB_PC4:  wb_rd_data_o = mem_wb_pc4;
            default: wb_rd_data_o = mem_wb_alu;
        endcase
    end

    // Architectural write #2 of 2.
    assign wb_rd_addr_o = mem_wb_rd_addr_o;
    assign wb_we_o      = mem_wb_ctrl_o.reg_write && mem_wb_valid_o;

endmodule

`default_nettype wire
