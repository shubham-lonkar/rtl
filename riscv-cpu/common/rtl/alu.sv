// Copyright (c) 2026 Shubham Lonkar
// SPDX-License-Identifier: MIT

`default_nettype none

// alu -- RV32I integer ALU, alu_op is {funct7[5], funct3}

module alu (
    input  wire [3:0]  alu_op,
    input  wire [31:0] a, b,
    output logic [31:0] result
);

    always_comb begin
        case (alu_op)
        4'b0000: result = a + b;            //ADD
        4'b0001: result = a << b[4:0];           //SLL
        4'b0010: result = ($signed(a) < $signed(b))?32'b1:32'b0;          //SLT
        4'b0011: result = (a < b)?32'b1:32'b0;          //SLTU
        4'b0100: result = a ^ b;          //XOR
        4'b0101: result = a >> b[4:0];           //SRL
        4'b0110: result = a | b;          //OR
        4'b0111: result = a & b;          //AND
        4'b1000: result = a - b;          //SUB
        4'b1101: result = $signed(a) >>> b[4:0];          //SRA
        default: result =  32'dx;         //Default
        endcase
    end

endmodule

`default_nettype wire
