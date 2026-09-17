// Copyright (c) 2026 Shubham Lonkar
// SPDX-License-Identifier: MIT

`default_nettype none

// imm_gen -- immediate decode for all five RV32I formats

module imm_gen (
    input  wire [31:0] instr_i,
    output logic [31:0] imm_o
);

wire  [6:0] opcode = instr_i[6:0];
logic [31:0] imm_i;
logic [31:0] imm_s;
logic [31:0] imm_b;
logic [31:0] imm_u;
logic [31:0] imm_j;

assign imm_b = {{19{instr_i[31]}}, instr_i[31], instr_i[7], instr_i[30:25], instr_i[11:8], 1'b0};
assign imm_i = {{20{instr_i[31]}}, instr_i[31:20]};
assign imm_s = {{20{instr_i[31]}}, instr_i[31:25], instr_i[11:7]};
assign imm_u = {instr_i[31:12], 12'b0};
assign imm_j = {{11{instr_i[31]}}, instr_i[31], instr_i[19:12], instr_i[20], instr_i[30:21], 1'b0};

always_comb begin
    case (opcode)
        7'b0010011: imm_o = imm_i;  //I-type  imm
        7'b0000011: imm_o = imm_i;  //I-type  Load
        7'b1100111: imm_o = imm_i;  //I-type  jalr
        7'b0100011: imm_o = imm_s;  //S-type
        7'b1100011: imm_o = imm_b;  //B-type 
        7'b0010111: imm_o = imm_u;  //U-type  auipc
        7'b0110111: imm_o = imm_u;  //U-type  lui
        7'b1101111: imm_o = imm_j;  //J-type
        default:    imm_o = 32'bx;  
    endcase
end

endmodule

`default_nettype wire
