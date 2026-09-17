// Copyright (c) 2026 Shubham Lonkar
// SPDX-License-Identifier: MIT

`default_nettype none

// branch_predictor -- one table, three index functions, two counter widths

module branch_predictor
    import riscv_pkg::*;
#(
    parameter  bp_mode_e BP_MODE   = BP_GSHARE,
    parameter  int       BHT_DEPTH = BP_BHT_DEPTH,
    parameter  int       GHR_BITS  = BP_GHR_BITS,
    parameter  int       CTR_BITS  = BP_CTR_BITS,
    parameter  bit       RESET_BHT = 1'b0,
    localparam int       IDX_W     = $clog2(BHT_DEPTH)
) (
    input  wire              clk,
    input  wire              rst_n,

    // predict port: combinational, same cycle as the I-mem read
    input  wire  [31:0]      pc_i,
    input  wire  [31:0]      instr_i,
    input  wire              valid_i,
    output logic             is_branch_o,       // instr_i is a conditional branch
    output logic             predict_taken_o,   // 0 for anything that is not one
    output logic [31:0]      predict_target_o,  // pc + B-immediate
    output logic [IDX_W-1:0] predict_index_o,   // SNAPSHOT -- caller must return this
    output logic [GHR_BITS-1:0] predict_ghr_o,  // SNAPSHOT -- caller must return this too

    input  wire              predict_take_i,

    // update port: resolution, snapshots handed back by the caller
    input  wire              update_valid_i,    // a branch resolved: train the BHT
    input  wire [IDX_W-1:0]  update_index_i,
    input  wire              update_taken_i,

    // recovery port: the resolved branch was mispredicted
    input  wire                 recover_valid_i,
    input  wire [GHR_BITS-1:0]  recover_ghr_i,   // GHR as it was when predicted
    input  wire                 recover_taken_i  // what actually happened
);

    localparam int GSEL_GHR = (GHR_BITS < IDX_W) ? GHR_BITS : IDX_W - 1;

    initial begin
        if (2**IDX_W != BHT_DEPTH)
            $fatal(1, "branch_predictor: BHT_DEPTH (%0d) must be a power of two", BHT_DEPTH);
        if (CTR_BITS < 1 || CTR_BITS > 2)
            $fatal(1, "branch_predictor: CTR_BITS (%0d) must be 1 or 2", CTR_BITS);
        if (GHR_BITS < 1)
            $fatal(1, "branch_predictor: GHR_BITS (%0d) must be >= 1", GHR_BITS);
        if (BP_MODE == BP_GSELECT && GHR_BITS >= IDX_W)
            $fatal(1, "branch_predictor: gselect needs GHR_BITS (%0d) < index width (%0d)",
                      GHR_BITS, IDX_W);
    end

    // State
    logic [CTR_BITS-1:0] bht [BHT_DEPTH-1:0];
    logic [GHR_BITS-1:0] ghr;

    logic [IDX_W-1:0] pc_idx, index;

    assign pc_idx = pc_i[IDX_W+1:2];

    always_comb begin
        case (BP_MODE)
            BP_GSELECT: index = { pc_idx[IDX_W-GSEL_GHR-1:0], ghr[GSEL_GHR-1:0] };
            BP_GSHARE:  index = pc_idx ^ { {(IDX_W-GHR_BITS){1'b0}}, ghr };
            default:    index = pc_idx;                       // BP_BIMODAL
        endcase
    end

    assign predict_index_o = index;
    assign predict_ghr_o   = ghr;

    always_comb begin
        case (instr_i[6:0])
            OP_BRANCH: is_branch_o = valid_i;
            default:   is_branch_o = 1'b0;
        endcase
    end

    assign predict_taken_o = is_branch_o && bht[index][CTR_BITS-1];

    logic [31:0] imm_b;
    assign imm_b = {{19{instr_i[31]}}, instr_i[31], instr_i[7],
                    instr_i[30:25], instr_i[11:8], 1'b0};

    assign predict_target_o = pc_i + imm_b;

    function automatic logic [CTR_BITS-1:0] ctr_next (input logic [CTR_BITS-1:0] c,
                                                      input logic               taken);
        if (taken) ctr_next = (c == {CTR_BITS{1'b1}}) ? c : c + 1'b1;
        else       ctr_next = (c == {CTR_BITS{1'b0}}) ? c : c - 1'b1;
    endfunction

    generate
        if (RESET_BHT) begin : g_bht_flops
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n)
                    for (int k = 0; k < BHT_DEPTH; k++) bht[k] <= '0;
                else if (update_valid_i)
                    bht[update_index_i] <= ctr_next(bht[update_index_i], update_taken_i);
            end
        end
        else begin : g_bht_ram
            initial for (int k = 0; k < BHT_DEPTH; k++) bht[k] = '0;

            always_ff @(posedge clk)
                if (update_valid_i)
                    bht[update_index_i] <= ctr_next(bht[update_index_i], update_taken_i);
        end
    endgenerate

    logic [GHR_BITS:0] ghr_spec, ghr_fixed;

    assign ghr_spec  = {ghr,           predict_taken_o};
    assign ghr_fixed = {recover_ghr_i, recover_taken_i};

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)               ghr <= '0;
        else if (recover_valid_i) ghr <= ghr_fixed[GHR_BITS-1:0];
        else if (predict_take_i)  ghr <= ghr_spec [GHR_BITS-1:0];
    end

endmodule

`default_nettype wire
