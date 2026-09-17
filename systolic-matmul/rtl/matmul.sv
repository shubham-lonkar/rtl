// Copyright (c) 2026 Shubham Lonkar
// SPDX-License-Identifier: MIT

`timescale 1ns / 1ps
`define DWIDTH 8
`define AWIDTH 10
`define MEM_SIZE 1024

`define MAT_MUL_SIZE 4
`define MASK_WIDTH 4
`define LOG2_MAT_MUL_SIZE 2

`define BB_MAT_MUL_SIZE `MAT_MUL_SIZE
`define NUM_CYCLES_IN_MAC 3
`define MEM_ACCESS_LATENCY 1
`define REG_DATAWIDTH 16
`define REG_ADDRWIDTH 8
`define ADDR_STRIDE_WIDTH 8
`define MAX_BITS_POOL 3

module matmul_4x4_systolic(
    clk,
    reset,
    pe_reset,
    start_mat_mul,
    done_mat_mul,
    address_mat_a,
    address_mat_b,
    address_mat_c,
    address_stride_a,
    address_stride_b,
    address_stride_c,
    a_data,
    b_data,
    a_data_in, //Data values coming in from previous matmul - systolic connections
    b_data_in,
    c_data_in, //Data values coming in from previous matmul - systolic shifting
    c_data_out, //Data values going out to next matmul - systolic shifting
    a_data_out,
    b_data_out,
    a_addr,
    b_addr,
    c_addr,
    c_data_available,
    validity_mask_a_rows,
    validity_mask_a_cols_b_rows,
    validity_mask_b_cols,
    final_mat_mul_size,
    a_loc,
    b_loc
    );

    input logic clk;
    input logic reset;
    input logic pe_reset;
    input logic start_mat_mul;
    output logic done_mat_mul;
    input logic [`AWIDTH-1:0] address_mat_a;
    input logic [`AWIDTH-1:0] address_mat_b;
    input logic [`AWIDTH-1:0] address_mat_c;
    input logic [`ADDR_STRIDE_WIDTH-1:0] address_stride_a;
    input logic [`ADDR_STRIDE_WIDTH-1:0] address_stride_b;
    input logic [`ADDR_STRIDE_WIDTH-1:0] address_stride_c;
    input logic [`MAT_MUL_SIZE*`DWIDTH-1:0] a_data;
    input logic [`MAT_MUL_SIZE*`DWIDTH-1:0] b_data;
    input logic [`MAT_MUL_SIZE*`DWIDTH-1:0] a_data_in;
    input logic [`MAT_MUL_SIZE*`DWIDTH-1:0] b_data_in;
    input logic [`MAT_MUL_SIZE*`DWIDTH-1:0] c_data_in;
    output logic [`MAT_MUL_SIZE*`DWIDTH-1:0] c_data_out;
    output logic [`MAT_MUL_SIZE*`DWIDTH-1:0] a_data_out;
    output logic [`MAT_MUL_SIZE*`DWIDTH-1:0] b_data_out;
    output logic [`AWIDTH-1:0] a_addr;
    output logic [`AWIDTH-1:0] b_addr;
    output logic [`AWIDTH-1:0] c_addr;
    output logic c_data_available;
    input logic [`MASK_WIDTH-1:0] validity_mask_a_rows;
    input logic [`MASK_WIDTH-1:0] validity_mask_a_cols_b_rows;
    input logic [`MASK_WIDTH-1:0] validity_mask_b_cols;
    //7:0 is okay here. We aren't going to make a matmul larger than 128x128
    //In fact, these will get optimized out by the synthesis tool, because
    //we hardcode them at the instantiation level.
    input logic [7:0] final_mat_mul_size;
    input logic [7:0] a_loc;
    input logic [7:0] b_loc;

//////////////////////////////////////////////////////////////////////////
// Logic for clock counting and when to assert done
//////////////////////////////////////////////////////////////////////////

    //This is 7 bits because the expectation is that clock count will be pretty
    //small. For large matmuls, this will need to increased to have more bits.
    //In general, a systolic multiplier takes f(N)+P cycles, where N is the size 
    //of the matmul and P is the number of pipleine stages in the MAC block.
    //f(N) is a function describing the number of cycles taken to perform matmul
    //with a systolic array strcture.
    logic [7:0] clk_cnt;
    
    //Finding out number of cycles to assert matmul done.
    logic [7:0] clk_cnt_for_done;
    logic [7:0] cycles_for_matmul; 
        
    assign cycles_for_matmul = 8'd14;
    assign clk_cnt_for_done = (cycles_for_matmul + `NUM_CYCLES_IN_MAC) ;  


    always_ff @(posedge clk) 
    begin
        if (reset || ~start_mat_mul) 
        begin
            clk_cnt <= 0;
            done_mat_mul <= 0;
        end
        else if (clk_cnt == clk_cnt_for_done) 
        begin
            done_mat_mul <= 1;
            clk_cnt <= clk_cnt + 1;
        end
        else if (done_mat_mul == 0) 
            clk_cnt <= clk_cnt + 1;   
        else 
        begin
            done_mat_mul <= 0;
            clk_cnt <= clk_cnt + 1;
        end
    end


    logic [`DWIDTH-1:0] a0_data;
    logic [`DWIDTH-1:0] a1_data;
    logic [`DWIDTH-1:0] a2_data;
    logic [`DWIDTH-1:0] a3_data;
    logic [`DWIDTH-1:0] b0_data;
    logic [`DWIDTH-1:0] b1_data;
    logic [`DWIDTH-1:0] b2_data;
    logic [`DWIDTH-1:0] b3_data;
    logic [`DWIDTH-1:0] a1_data_delayed_1;
    logic [`DWIDTH-1:0] a2_data_delayed_1;
    logic [`DWIDTH-1:0] a2_data_delayed_2;
    logic [`DWIDTH-1:0] a3_data_delayed_1;
    logic [`DWIDTH-1:0] a3_data_delayed_2;
    logic [`DWIDTH-1:0] a3_data_delayed_3;
    logic [`DWIDTH-1:0] b1_data_delayed_1;
    logic [`DWIDTH-1:0] b2_data_delayed_1;
    logic [`DWIDTH-1:0] b2_data_delayed_2;
    logic [`DWIDTH-1:0] b3_data_delayed_1;
    logic [`DWIDTH-1:0] b3_data_delayed_2;
    logic [`DWIDTH-1:0] b3_data_delayed_3;
    
//////////////////////////////////////////////////////////////////////////
// Instantiation of systolic data setup
//////////////////////////////////////////////////////////////////////////
    systolic_data_setup u_systolic_data_setup(
        .clk(clk),
        .reset(reset),
        .start_mat_mul(start_mat_mul),
        .a_addr(a_addr),
        .b_addr(b_addr),
        .address_mat_a(address_mat_a),
        .address_mat_b(address_mat_b),
        .address_stride_a(address_stride_a),
        .address_stride_b(address_stride_b),
        .a_data(a_data),
        .b_data(b_data),
        .clk_cnt(clk_cnt),
        .a0_data(a0_data),
        .a1_data_delayed_1(a1_data_delayed_1),
        .a2_data_delayed_2(a2_data_delayed_2),
        .a3_data_delayed_3(a3_data_delayed_3),
        .b0_data(b0_data),
        .b1_data_delayed_1(b1_data_delayed_1),
        .b2_data_delayed_2(b2_data_delayed_2),
        .b3_data_delayed_3(b3_data_delayed_3),
        .validity_mask_a_rows(validity_mask_a_rows),
        .validity_mask_a_cols_b_rows(validity_mask_a_cols_b_rows),
        .validity_mask_b_cols(validity_mask_b_cols),
        .final_mat_mul_size(final_mat_mul_size),
        .a_loc(a_loc),
        .b_loc(b_loc)
        );


//////////////////////////////////////////////////////////////////////////
// Logic to mux data_in coming from neighboring matmuls
//////////////////////////////////////////////////////////////////////////
    logic [`DWIDTH-1:0] a0;
    logic [`DWIDTH-1:0] a1;
    logic [`DWIDTH-1:0] a2;
    logic [`DWIDTH-1:0] a3;
    logic [`DWIDTH-1:0] b0;
    logic [`DWIDTH-1:0] b1;
    logic [`DWIDTH-1:0] b2;
    logic [`DWIDTH-1:0] b3;
    
    logic [`DWIDTH-1:0] a0_data_in;
    logic [`DWIDTH-1:0] a1_data_in;
    logic [`DWIDTH-1:0] a2_data_in;
    logic [`DWIDTH-1:0] a3_data_in;
    assign a0_data_in = a_data_in[`DWIDTH-1:0];
    assign a1_data_in = a_data_in[2*`DWIDTH-1:`DWIDTH];
    assign a2_data_in = a_data_in[3*`DWIDTH-1:2*`DWIDTH];
    assign a3_data_in = a_data_in[4*`DWIDTH-1:3*`DWIDTH];
    
    logic [`DWIDTH-1:0] b0_data_in;
    logic [`DWIDTH-1:0] b1_data_in;
    logic [`DWIDTH-1:0] b2_data_in;
    logic [`DWIDTH-1:0] b3_data_in;
    assign b0_data_in = b_data_in[`DWIDTH-1:0];
    assign b1_data_in = b_data_in[2*`DWIDTH-1:`DWIDTH];
    assign b2_data_in = b_data_in[3*`DWIDTH-1:2*`DWIDTH];
    assign b3_data_in = b_data_in[4*`DWIDTH-1:3*`DWIDTH];
    
    //If b_loc is 0, that means this matmul block is on the top-row of the
    //final large matmul. In that case, b will take inputs from mem.
    //If b_loc != 0, that means this matmul block is not on the top-row of the
    //final large matmul. In that case, b will take inputs from the matmul on top
    //of this one.
    assign a0 = (b_loc==0) ? a0_data           : a0_data_in;
    assign a1 = (b_loc==0) ? a1_data_delayed_1 : a1_data_in;
    assign a2 = (b_loc==0) ? a2_data_delayed_2 : a2_data_in;
    assign a3 = (b_loc==0) ? a3_data_delayed_3 : a3_data_in;

    //If a_loc is 0, that means this matmul block is on the left-col of the
    //final large matmul. In that case, a will take inputs from mem.
    //If a_loc != 0, that means this matmul block is not on the left-col of the
    //final large matmul. In that case, a will take inputs from the matmul on left
    //of this one.
    assign b0 = (a_loc==0) ? b0_data           : b0_data_in;
    assign b1 = (a_loc==0) ? b1_data_delayed_1 : b1_data_in;
    assign b2 = (a_loc==0) ? b2_data_delayed_2 : b2_data_in;
    assign b3 = (a_loc==0) ? b3_data_delayed_3 : b3_data_in;
    

    logic [`DWIDTH-1:0] matrixC00;
    logic [`DWIDTH-1:0] matrixC01;
    logic [`DWIDTH-1:0] matrixC02;
    logic [`DWIDTH-1:0] matrixC03;
    logic [`DWIDTH-1:0] matrixC10;
    logic [`DWIDTH-1:0] matrixC11;
    logic [`DWIDTH-1:0] matrixC12;
    logic [`DWIDTH-1:0] matrixC13;
    logic [`DWIDTH-1:0] matrixC20;
    logic [`DWIDTH-1:0] matrixC21;
    logic [`DWIDTH-1:0] matrixC22;
    logic [`DWIDTH-1:0] matrixC23;
    logic [`DWIDTH-1:0] matrixC30;
    logic [`DWIDTH-1:0] matrixC31;
    logic [`DWIDTH-1:0] matrixC32;
    logic [`DWIDTH-1:0] matrixC33;
    

//////////////////////////////////////////////////////////////////////////
// Instantiation of the output logic
//////////////////////////////////////////////////////////////////////////
    output_logic u_output_logic(
        .clk(clk),
        .reset(reset),
        .start_mat_mul(start_mat_mul),
        .done_mat_mul(done_mat_mul),
        .address_mat_c(address_mat_c),
        .address_stride_c(address_stride_c),
        .c_data_out(c_data_out),
        .c_data_in(c_data_in),
        .c_addr(c_addr),
        .c_data_available(c_data_available),
        .clk_cnt(clk_cnt),
        .row_latch_en(row_latch_en),
        .final_mat_mul_size(final_mat_mul_size),
        .matrixC00(matrixC00),
        .matrixC01(matrixC01),
        .matrixC02(matrixC02),
        .matrixC03(matrixC03),
        .matrixC10(matrixC10),
        .matrixC11(matrixC11),
        .matrixC12(matrixC12),
        .matrixC13(matrixC13),
        .matrixC20(matrixC20),
        .matrixC21(matrixC21),
        .matrixC22(matrixC22),
        .matrixC23(matrixC23),
        .matrixC30(matrixC30),
        .matrixC31(matrixC31),
        .matrixC32(matrixC32),
        .matrixC33(matrixC33)
        );

//////////////////////////////////////////////////////////////////////////
// Instantiations of the actual PEs
//////////////////////////////////////////////////////////////////////////
    systolic_pe_matrix u_systolic_pe_matrix(
        .reset(reset),
        .clk(clk),
        .pe_reset(pe_reset),
        .start_mat_mul(start_mat_mul),
        .a0(a0), 
        .a1(a1), 
        .a2(a2), 
        .a3(a3),
        .b0(b0), 
        .b1(b1), 
        .b2(b2), 
        .b3(b3),
        .matrixC00(matrixC00),
        .matrixC01(matrixC01),
        .matrixC02(matrixC02),
        .matrixC03(matrixC03),
        .matrixC10(matrixC10),
        .matrixC11(matrixC11),
        .matrixC12(matrixC12),
        .matrixC13(matrixC13),
        .matrixC20(matrixC20),
        .matrixC21(matrixC21),
        .matrixC22(matrixC22),
        .matrixC23(matrixC23),
        .matrixC30(matrixC30),
        .matrixC31(matrixC31),
        .matrixC32(matrixC32),
        .matrixC33(matrixC33),
        .a_data_out(a_data_out),
        .b_data_out(b_data_out)
        );

endmodule

//////////////////////////////////////////////////////////////////////////
// Output logic
//////////////////////////////////////////////////////////////////////////
module output_logic(
    clk,
    reset,
    start_mat_mul,
    done_mat_mul,
    address_mat_c,
    address_stride_c,
    c_data_in,
    c_data_out, //Data values going out to next matmul - systolic shifting
    c_addr,
    c_data_available,
    clk_cnt,
    row_latch_en,
    final_mat_mul_size,
    matrixC00,
    matrixC01,
    matrixC02,
    matrixC03,
    matrixC10,
    matrixC11,
    matrixC12,
    matrixC13,
    matrixC20,
    matrixC21,
    matrixC22,
    matrixC23,
    matrixC30,
    matrixC31,
    matrixC32,
    matrixC33
    );

    input logic clk;
    input logic reset;
    input logic start_mat_mul;
    input logic done_mat_mul;
    input logic [`AWIDTH-1:0] address_mat_c;
    input logic [`ADDR_STRIDE_WIDTH-1:0] address_stride_c;
    input logic [`MAT_MUL_SIZE*`DWIDTH-1:0] c_data_in;
    output logic [`MAT_MUL_SIZE*`DWIDTH-1:0] c_data_out;
    output logic [`AWIDTH-1:0] c_addr;
    output logic c_data_available;
    input logic [7:0] clk_cnt;
    output logic row_latch_en;
    input logic [7:0] final_mat_mul_size;
    input logic [`DWIDTH-1:0] matrixC00;
    input logic [`DWIDTH-1:0] matrixC01;
    input logic [`DWIDTH-1:0] matrixC02;
    input logic [`DWIDTH-1:0] matrixC03;
    input logic [`DWIDTH-1:0] matrixC10;
    input logic [`DWIDTH-1:0] matrixC11;
    input logic [`DWIDTH-1:0] matrixC12;
    input logic [`DWIDTH-1:0] matrixC13;
    input logic [`DWIDTH-1:0] matrixC20;
    input logic [`DWIDTH-1:0] matrixC21;
    input logic [`DWIDTH-1:0] matrixC22;
    input logic [`DWIDTH-1:0] matrixC23;
    input logic [`DWIDTH-1:0] matrixC30;
    input logic [`DWIDTH-1:0] matrixC31;
    input logic [`DWIDTH-1:0] matrixC32;
    input logic [`DWIDTH-1:0] matrixC33;
    
//////////////////////////////////////////////////////////////////////////
// Logic to capture matrix C data from the PEs and shift it out
//////////////////////////////////////////////////////////////////////////
    assign row_latch_en = ((clk_cnt == ((final_mat_mul_size<<2) - final_mat_mul_size -1 +`NUM_CYCLES_IN_MAC)));
    
    //logic [`AWIDTH-1:0] c_addr;
    logic start_capturing_c_data;
    integer counter;
    //logic [`MAT_MUL_SIZE*`DWIDTH-1:0] c_data_out;
    logic [`MAT_MUL_SIZE*`DWIDTH-1:0] c_data_out_1;
    logic [`MAT_MUL_SIZE*`DWIDTH-1:0] c_data_out_2;
    logic [`MAT_MUL_SIZE*`DWIDTH-1:0] c_data_out_3;
    
    logic [`MAT_MUL_SIZE*`DWIDTH-1:0] col0;
    logic [`MAT_MUL_SIZE*`DWIDTH-1:0] col1;
    logic [`MAT_MUL_SIZE*`DWIDTH-1:0] col2;
    logic [`MAT_MUL_SIZE*`DWIDTH-1:0] col3;
    assign col0 = {matrixC30, matrixC20, matrixC10, matrixC00};
    assign col1 = {matrixC31, matrixC21, matrixC11, matrixC01};
    assign col2 = {matrixC32, matrixC22, matrixC12, matrixC02};
    assign col3 = {matrixC33, matrixC23, matrixC13, matrixC03};

//If save_output_to_accum is asserted, that means we are not intending to shift
//out the outputs, because the outputs are still partial sums. 
    logic condition_to_start_shifting_output;
    assign condition_to_start_shifting_output = row_latch_en ;  

//For larger matmuls, this logic will have more entries in the case statement
    always_ff @(posedge clk) 
    begin
        if (reset | ~start_mat_mul) 
        begin
            start_capturing_c_data <= 1'b0;
            c_data_available <= 1'b0;
            c_addr <= address_mat_c - address_stride_c;
            c_data_out <= 0;
            counter <= 0;
            c_data_out_1 <= 0; 
            c_data_out_2 <= 0; 
            c_data_out_3 <= 0; 
        end
        else if (condition_to_start_shifting_output) 
        begin
            start_capturing_c_data <= 1'b1;
            c_data_available <= 1'b1;
            c_addr <= c_addr + address_stride_c;
            c_data_out <= col0; 
            c_data_out_1 <= col1; 
            c_data_out_2 <= col2; 
            c_data_out_3 <= col3; 
            counter <= counter + 1;
        end 
        else if (done_mat_mul) 
        begin
            start_capturing_c_data <= 1'b0;
            c_data_available <= 1'b0;
            c_addr <= address_mat_c+address_stride_c;
            c_data_out <= 0;
            c_data_out_1 <= 0;
            c_data_out_2 <= 0;
            c_data_out_3 <= 0;
        end 
        else if (counter >= `MAT_MUL_SIZE) 
        begin
            c_addr <= c_addr + address_stride_c;
            c_data_out <= c_data_out_1;
            c_data_out_1 <= c_data_out_2;
            c_data_out_2 <= c_data_out_3;
            c_data_out_3 <= c_data_in;
        end
        else if (start_capturing_c_data) 
        begin
            c_data_available <= 1'b1;
            c_addr <= c_addr + address_stride_c;
            counter <= counter + 1;
            c_data_out <= c_data_out_1;
            c_data_out_1 <= c_data_out_2;
            c_data_out_2 <= c_data_out_3;
            c_data_out_3 <= c_data_in;
        end
    end

endmodule

//////////////////////////////////////////////////////////////////////////
// Systolic data setup
//////////////////////////////////////////////////////////////////////////
module systolic_data_setup(
    clk,
    reset,
    start_mat_mul,
    a_addr,
    b_addr,
    address_mat_a,
    address_mat_b,
    address_stride_a,
    address_stride_b,
    a_data,
    b_data,
    clk_cnt,
    a0_data,
    a1_data_delayed_1,
    a2_data_delayed_2,
    a3_data_delayed_3,
    b0_data,
    b1_data_delayed_1,
    b2_data_delayed_2,
    b3_data_delayed_3,
    validity_mask_a_rows,
    validity_mask_a_cols_b_rows,
    validity_mask_b_cols,
    final_mat_mul_size,
    a_loc,
    b_loc
    );

    input logic clk;
    input logic reset;
    input logic start_mat_mul;
    output logic [`AWIDTH-1:0] a_addr;
    output logic [`AWIDTH-1:0] b_addr;
    input logic [`AWIDTH-1:0] address_mat_a;
    input logic [`AWIDTH-1:0] address_mat_b;
    input logic [`ADDR_STRIDE_WIDTH-1:0] address_stride_a;
    input logic [`ADDR_STRIDE_WIDTH-1:0] address_stride_b;
    input logic [`MAT_MUL_SIZE*`DWIDTH-1:0] a_data;
    input logic [`MAT_MUL_SIZE*`DWIDTH-1:0] b_data;
    input logic [7:0] clk_cnt;
    output logic [`DWIDTH-1:0] a0_data;
    output logic [`DWIDTH-1:0] a1_data_delayed_1;
    output logic [`DWIDTH-1:0] a2_data_delayed_2;
    output logic [`DWIDTH-1:0] a3_data_delayed_3;
    output logic [`DWIDTH-1:0] b0_data;
    output logic [`DWIDTH-1:0] b1_data_delayed_1;
    output logic [`DWIDTH-1:0] b2_data_delayed_2;
    output logic [`DWIDTH-1:0] b3_data_delayed_3;
    input logic [`MASK_WIDTH-1:0] validity_mask_a_rows;
    input logic [`MASK_WIDTH-1:0] validity_mask_a_cols_b_rows;
    input logic [`MASK_WIDTH-1:0] validity_mask_b_cols;
    input logic [7:0] final_mat_mul_size;
    input logic [7:0] a_loc;
    input logic [7:0] b_loc;
    
    //logic [`DWIDTH-1:0] a0_data;
    logic [`DWIDTH-1:0] a1_data;
    logic [`DWIDTH-1:0] a2_data;
    logic [`DWIDTH-1:0] a3_data;
    //logic [`DWIDTH-1:0] b0_data;
    logic [`DWIDTH-1:0] b1_data;
    logic [`DWIDTH-1:0] b2_data;
    logic [`DWIDTH-1:0] b3_data;

//////////////////////////////////////////////////////////////////////////
// Logic to generate addresses to BRAM A
//////////////////////////////////////////////////////////////////////////
    //logic [`AWIDTH-1:0] a_addr;
    logic a_mem_access; //flag that tells whether the matmul is trying to access memory or not
    
    always_ff @(posedge clk) 
    begin
        if ((reset || ~start_mat_mul) || (clk_cnt >= (a_loc<<`LOG2_MAT_MUL_SIZE)+final_mat_mul_size)) begin
            a_addr <= address_mat_a-address_stride_a;
            a_mem_access <= 0;
        end
        else if ((clk_cnt >= (a_loc<<`LOG2_MAT_MUL_SIZE)) && (clk_cnt < (a_loc<<`LOG2_MAT_MUL_SIZE)+final_mat_mul_size)) 
        begin
            a_addr <= a_addr + address_stride_a;
            a_mem_access <= 1;
        end
    end  

//////////////////////////////////////////////////////////////////////////
// Logic to generate valid signals for data coming from BRAM A
//////////////////////////////////////////////////////////////////////////
    logic [7:0] a_mem_access_counter;
    always_ff @(posedge clk) 
    begin
        if (reset || ~start_mat_mul) 
            a_mem_access_counter <= 0;
        else if (a_mem_access == 1) 
            a_mem_access_counter <= a_mem_access_counter + 1;  
        else 
            a_mem_access_counter <= 0;
    end

    logic a_data_valid; //flag that tells whether the data from memory is valid
    assign a_data_valid = 
        ((validity_mask_a_cols_b_rows[0]==1'b0 && a_mem_access_counter==1) ||
        (validity_mask_a_cols_b_rows[1]==1'b0 && a_mem_access_counter==2) ||
        (validity_mask_a_cols_b_rows[2]==1'b0 && a_mem_access_counter==3) ||
        (validity_mask_a_cols_b_rows[3]==1'b0 && a_mem_access_counter==4)) ?
        1'b0 : (a_mem_access_counter >= `MEM_ACCESS_LATENCY);
    
//////////////////////////////////////////////////////////////////////////
// Logic to delay certain parts of the data received from BRAM A (systolic data setup)
//////////////////////////////////////////////////////////////////////////
//Slice data into chunks and qualify it with whether it is valid or not
    assign a0_data = a_data[`DWIDTH-1:0] & {`DWIDTH{a_data_valid}} & {`DWIDTH{validity_mask_a_rows[0]}};
    assign a1_data = a_data[2*`DWIDTH-1:`DWIDTH] & {`DWIDTH{a_data_valid}} & {`DWIDTH{validity_mask_a_rows[1]}};
    assign a2_data = a_data[3*`DWIDTH-1:2*`DWIDTH] & {`DWIDTH{a_data_valid}} & {`DWIDTH{validity_mask_a_rows[2]}};
    assign a3_data = a_data[4*`DWIDTH-1:3*`DWIDTH] & {`DWIDTH{a_data_valid}} & {`DWIDTH{validity_mask_a_rows[3]}};

//For larger matmuls, more such delaying flops will be needed
    //logic [`DWIDTH-1:0] a1_data_delayed_1;
    logic [`DWIDTH-1:0] a2_data_delayed_1;
    //logic [`DWIDTH-1:0] a2_data_delayed_2;
    logic [`DWIDTH-1:0] a3_data_delayed_1;
    logic [`DWIDTH-1:0] a3_data_delayed_2;
    //logic [`DWIDTH-1:0] a3_data_delayed_3;
    
    always_ff @(posedge clk) 
    begin
        if (reset || ~start_mat_mul || clk_cnt==0) 
        begin
            a1_data_delayed_1 <= 0;
            a2_data_delayed_1 <= 0;
            a2_data_delayed_2 <= 0;
            a3_data_delayed_1 <= 0;
            a3_data_delayed_2 <= 0;
            a3_data_delayed_3 <= 0;
        end
        else 
        begin
            a1_data_delayed_1 <= a1_data;
            a2_data_delayed_1 <= a2_data;
            a2_data_delayed_2 <= a2_data_delayed_1;
            a3_data_delayed_1 <= a3_data;
            a3_data_delayed_2 <= a3_data_delayed_1;
            a3_data_delayed_3 <= a3_data_delayed_2;
        end
    end

//////////////////////////////////////////////////////////////////////////
// Logic to generate addresses to BRAM B
//////////////////////////////////////////////////////////////////////////
    //logic [`AWIDTH-1:0] b_addr;
    logic b_mem_access; //flag that tells whether the matmul is trying to access memory or not

    always_ff @(posedge clk) 
    begin
        if ((reset || ~start_mat_mul) || (clk_cnt >= (b_loc<<`LOG2_MAT_MUL_SIZE)+final_mat_mul_size)) 
        begin
            b_addr <= address_mat_b - address_stride_b;
            b_mem_access <= 0;
        end
        else if ((clk_cnt >= (b_loc<<`LOG2_MAT_MUL_SIZE)) && (clk_cnt < (b_loc<<`LOG2_MAT_MUL_SIZE)+final_mat_mul_size)) 
        begin
            b_addr <= b_addr + address_stride_b;
            b_mem_access <= 1;
        end
    end  

//////////////////////////////////////////////////////////////////////////
// Logic to generate valid signals for data coming from BRAM B
//////////////////////////////////////////////////////////////////////////
    logic [7:0] b_mem_access_counter;
    always_ff @(posedge clk) 
    begin
        if (reset || ~start_mat_mul) 
            b_mem_access_counter <= 0;
        else if (b_mem_access == 1)
            b_mem_access_counter <= b_mem_access_counter + 1;  
        else
            b_mem_access_counter <= 0;
    end

    logic b_data_valid; //flag that tells whether the data from memory is valid
    assign b_data_valid = 
        ((validity_mask_a_cols_b_rows[0]==1'b0 && b_mem_access_counter==1) ||
        (validity_mask_a_cols_b_rows[1]==1'b0 && b_mem_access_counter==2) ||
        (validity_mask_a_cols_b_rows[2]==1'b0 && b_mem_access_counter==3) ||
        (validity_mask_a_cols_b_rows[3]==1'b0 && b_mem_access_counter==4)) ?
        1'b0 : (b_mem_access_counter >= `MEM_ACCESS_LATENCY);


//////////////////////////////////////////////////////////////////////////
// Logic to delay certain parts of the data received from BRAM B (systolic data setup)
//////////////////////////////////////////////////////////////////////////
//Slice data into chunks and qualify it with whether it is valid or not
    assign b0_data = b_data[`DWIDTH-1:0] & {`DWIDTH{b_data_valid}} & {`DWIDTH{validity_mask_b_cols[0]}};
    assign b1_data = b_data[2*`DWIDTH-1:`DWIDTH] & {`DWIDTH{b_data_valid}} & {`DWIDTH{validity_mask_b_cols[1]}};
    assign b2_data = b_data[3*`DWIDTH-1:2*`DWIDTH] & {`DWIDTH{b_data_valid}} & {`DWIDTH{validity_mask_b_cols[2]}};
    assign b3_data = b_data[4*`DWIDTH-1:3*`DWIDTH] & {`DWIDTH{b_data_valid}} & {`DWIDTH{validity_mask_b_cols[3]}};

//For larger matmuls, more such delaying flops will be needed
    //logic [`DWIDTH-1:0] b1_data_delayed_1;
    logic [`DWIDTH-1:0] b2_data_delayed_1;
    //logic [`DWIDTH-1:0] b2_data_delayed_2;
    logic [`DWIDTH-1:0] b3_data_delayed_1;
    logic [`DWIDTH-1:0] b3_data_delayed_2;
    //logic [`DWIDTH-1:0] b3_data_delayed_3;
    
    always_ff @(posedge clk) 
    begin
        if (reset || ~start_mat_mul || clk_cnt==0) 
        begin
            b1_data_delayed_1 <= 0;
            b2_data_delayed_1 <= 0;
            b2_data_delayed_2 <= 0;
            b3_data_delayed_1 <= 0;
            b3_data_delayed_2 <= 0;
            b3_data_delayed_3 <= 0;
        end
        else 
        begin
            b1_data_delayed_1 <= b1_data;
            b2_data_delayed_1 <= b2_data;
            b2_data_delayed_2 <= b2_data_delayed_1;
            b3_data_delayed_1 <= b3_data;
            b3_data_delayed_2 <= b3_data_delayed_1;
            b3_data_delayed_3 <= b3_data_delayed_2;
        end
    end

endmodule



//////////////////////////////////////////////////////////////////////////
// Systolically connected PEs
//////////////////////////////////////////////////////////////////////////
module systolic_pe_matrix(
    reset,
    clk,
    pe_reset,
    start_mat_mul,
    a0, a1, a2, a3,
    b0, b1, b2, b3,
    matrixC00,
    matrixC01,
    matrixC02,
    matrixC03,
    matrixC10,
    matrixC11,
    matrixC12,
    matrixC13,
    matrixC20,
    matrixC21,
    matrixC22,
    matrixC23,
    matrixC30,
    matrixC31,
    matrixC32,
    matrixC33,
    a_data_out,
    b_data_out
    );

    input logic clk;
    input logic reset;
    input logic pe_reset;
    input logic start_mat_mul;
    input logic [`DWIDTH-1:0] a0;
    input logic [`DWIDTH-1:0] a1;
    input logic [`DWIDTH-1:0] a2;
    input logic [`DWIDTH-1:0] a3;
    input logic [`DWIDTH-1:0] b0;
    input logic [`DWIDTH-1:0] b1;
    input logic [`DWIDTH-1:0] b2;
    input logic [`DWIDTH-1:0] b3;
    output logic [`DWIDTH-1:0] matrixC00;
    output logic [`DWIDTH-1:0] matrixC01;
    output logic [`DWIDTH-1:0] matrixC02;
    output logic [`DWIDTH-1:0] matrixC03;
    output logic [`DWIDTH-1:0] matrixC10;
    output logic [`DWIDTH-1:0] matrixC11;
    output logic [`DWIDTH-1:0] matrixC12;
    output logic [`DWIDTH-1:0] matrixC13;
    output logic [`DWIDTH-1:0] matrixC20;
    output logic [`DWIDTH-1:0] matrixC21;
    output logic [`DWIDTH-1:0] matrixC22;
    output logic [`DWIDTH-1:0] matrixC23;
    output logic [`DWIDTH-1:0] matrixC30;
    output logic [`DWIDTH-1:0] matrixC31;
    output logic [`DWIDTH-1:0] matrixC32;
    output logic [`DWIDTH-1:0] matrixC33;
    output logic [`MAT_MUL_SIZE*`DWIDTH-1:0] a_data_out;
    output logic [`MAT_MUL_SIZE*`DWIDTH-1:0] b_data_out;

    logic [`DWIDTH-1:0] a00to01, a01to02, a02to03, a03to04;
    logic [`DWIDTH-1:0] a10to11, a11to12, a12to13, a13to14;
    logic [`DWIDTH-1:0] a20to21, a21to22, a22to23, a23to24;
    logic [`DWIDTH-1:0] a30to31, a31to32, a32to33, a33to34;
    
    logic [`DWIDTH-1:0] b00to10, b10to20, b20to30, b30to40; 
    logic [`DWIDTH-1:0] b01to11, b11to21, b21to31, b31to41;
    logic [`DWIDTH-1:0] b02to12, b12to22, b22to32, b32to42;
    logic [`DWIDTH-1:0] b03to13, b13to23, b23to33, b33to43;
    
    logic effective_rst;
    assign effective_rst = reset | pe_reset;
    
    
    //There are a total of 16 PEs arranged in a mesh structure like in the lecture slides. 	
	//Each PE has a number. PE00 is the top-left PE. PE01 is the second PE on the first row. 
	//PE10 is the first PE on the second row. PE33 is the bottom right PE.	
    //Signals a0, a1, a2, a3 are coming from matrix A. They need to be be connected to the first column of PEs.
	//b0, b1, b2, b3 signals are coming from matrix B. They need to be connected to the first row of the PEs.
	//Signals axytozw go from PExy to PEzw horizontally.
	//Signals bxytozw go from PExy to PEzw vertically.
	//Signals matrixCxx are the output results from each PE.
	//Reset and clock signals of all PEs are the same.	

	processing_element pe00(.reset(effective_rst), .clk(clk), .in_a(a0),      .in_b(b0), .out_a(a00to01), .out_b(b00to10), .out_c(matrixC00));
	processing_element pe01(.reset(effective_rst), .clk(clk), .in_a(a00to01), .in_b(b1), .out_a(a01to02), .out_b(b01to11), .out_c(matrixC01));
	processing_element pe02(.reset(effective_rst), .clk(clk), .in_a(a01to02), .in_b(b2), .out_a(a02to03), .out_b(b02to12), .out_c(matrixC02));
	processing_element pe03(.reset(effective_rst), .clk(clk), .in_a(a02to03), .in_b(b3), .out_a(a03to04), .out_b(b03to13), .out_c(matrixC03));

	processing_element pe10(.reset(effective_rst), .clk(clk), .in_a(a1),      .in_b(b00to10), .out_a(a10to11), .out_b(b10to20), .out_c(matrixC10));
	processing_element pe11(.reset(effective_rst), .clk(clk), .in_a(a10to11), .in_b(b01to11), .out_a(a11to12), .out_b(b11to21), .out_c(matrixC11));
	processing_element pe12(.reset(effective_rst), .clk(clk), .in_a(a11to12), .in_b(b02to12), .out_a(a12to13), .out_b(b12to22), .out_c(matrixC12));
	processing_element pe13(.reset(effective_rst), .clk(clk), .in_a(a12to13), .in_b(b03to13), .out_a(a13to14), .out_b(b13to23), .out_c(matrixC13));

	processing_element pe20(.reset(effective_rst), .clk(clk), .in_a(a2),      .in_b(b10to20), .out_a(a20to21), .out_b(b20to30), .out_c(matrixC20));
	processing_element pe21(.reset(effective_rst), .clk(clk), .in_a(a20to21), .in_b(b11to21), .out_a(a21to22), .out_b(b21to31), .out_c(matrixC21));
	processing_element pe22(.reset(effective_rst), .clk(clk), .in_a(a21to22), .in_b(b12to22), .out_a(a22to23), .out_b(b22to32), .out_c(matrixC22));
	processing_element pe23(.reset(effective_rst), .clk(clk), .in_a(a22to23), .in_b(b13to23), .out_a(a23to24), .out_b(b23to33), .out_c(matrixC23));

	processing_element pe30(.reset(effective_rst), .clk(clk), .in_a(a3),      .in_b(b20to30), .out_a(a30to31), .out_b(b30to40), .out_c(matrixC30));
	processing_element pe31(.reset(effective_rst), .clk(clk), .in_a(a30to31), .in_b(b21to31), .out_a(a31to32), .out_b(b31to41), .out_c(matrixC31));
	processing_element pe32(.reset(effective_rst), .clk(clk), .in_a(a31to32), .in_b(b22to32), .out_a(a32to33), .out_b(b32to42), .out_c(matrixC32));
	processing_element pe33(.reset(effective_rst), .clk(clk), .in_a(a32to33), .in_b(b23to33), .out_a(a33to34), .out_b(b33to43), .out_c(matrixC33));

    assign a_data_out = {a33to34,a23to24,a13to14,a03to04};
    assign b_data_out = {b33to43,b32to42,b31to41,b30to40};

endmodule


//////////////////////////////////////////////////////////////////////////
// Processing element (PE)
//////////////////////////////////////////////////////////////////////////
module processing_element(
    reset, 
    clk, 
    in_a,
    in_b, 
    out_a, 
    out_b, 
    out_c
    );

    input logic reset;
    input logic clk;
    input logic  [`DWIDTH-1:0] in_a;
    input logic  [`DWIDTH-1:0] in_b;
    output logic [`DWIDTH-1:0] out_a;
    output logic [`DWIDTH-1:0] out_b;
    output logic [`DWIDTH-1:0] out_c;  //reduced precision

    //logic [`DWIDTH-1:0] out_a;
    //logic [`DWIDTH-1:0] out_b;
    //logic [`DWIDTH-1:0] out_c;
    logic [`DWIDTH-1:0] out_mac;

    assign out_c = out_mac;

    MAC_E3M4 mac_unit(
    .clk(clk),       // system clock
    .rst_n(~reset),     // active-low reset
    .A(in_a),         // E3M4 float multiplicand
    .B(in_b),         // E3M4 float multiplier
    .Y(out_mac),         // E3M4 float accumulated output
    .prod(),      // gated product
    .sum(),       // gated sum
    .flag()
    );

    always_ff @(posedge clk)
    begin
        if(reset) 
        begin
            out_a<=0;
            out_b<=0;
        end
        else 
        begin  
            out_a<=in_a;
            out_b<=in_b;
        end
    end
 
endmodule

//////////////////////////////////////////////////////////////////////////
// Multiply-and-accumulate (MAC) block
// 3-stage pipeline: capture -> multiply -> accumulate (matches NUM_CYCLES_IN_MAC)
//////////////////////////////////////////////////////////////////////////
module MAC_E3M4 (
    input  logic        clk,       // system clock
    input  logic        rst_n,     // active-low, synchronous reset
    input  logic [7:0]  A,         // E3M4 float multiplicand
    input  logic [7:0]  B,         // E3M4 float multiplier
    output logic [7:0]  Y,         // E3M4 float accumulated output (registered)
    output logic [7:0]  prod,      // registered product (stage 2 output)
    output logic [7:0]  sum,       // combinational sum feeding stage 3's register
    output logic        flag       // exception/zero flag on the current Y
);

  // stage 1: capture
  logic [7:0] a_flop, b_flop;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      a_flop <= 8'd0;
      b_flop <= 8'd0;
    end else begin
      a_flop <= A;
      b_flop <= B;
    end
  end

  // stage 2: multiply
  logic [7:0] prod_raw;
  FPMult8_E3M4 mult_i (
    .A    (a_flop),
    .B    (b_flop),
    .Z    (prod_raw),
    .Flags(),
    .NaN  (),
    .inf  (),
    .zero()
  );

  always_ff @(posedge clk) begin
    if (!rst_n) prod <= 8'd0;
    else        prod <= prod_raw;
  end

  // stage 3: accumulate
  logic [7:0] acc_reg;
  FPAddSub_E3M4 add_i (
    .A         (prod),
    .B         (acc_reg),
    .operation (1'b0),
    .P         (sum),
    .Flags     (),
    .NaN       (),
    .inf       (),
    .zero      ()
  );

  always_ff @(posedge clk) begin
    if (!rst_n) acc_reg <= 8'd0;
    else        acc_reg <= sum;
  end

  assign Y = acc_reg;

  // exception/zero flags
  logic A_Inf, B_Inf, A_NaN, B_NaN, inf, NaN, zero;
  assign A_Inf = (a_flop[6:4] == 3'b111) && (a_flop[3:0] == 4'b0000);
  assign B_Inf = (b_flop[6:4] == 3'b111) && (b_flop[3:0] == 4'b0000);
  assign A_NaN = (a_flop[6:4] == 3'b111) && (|a_flop[3:0]);
  assign B_NaN = (b_flop[6:4] == 3'b111) && (|b_flop[3:0]);

  always_comb begin
    inf  = A_Inf || B_Inf;
    NaN  = A_NaN || B_NaN;
    zero = (!NaN && !inf) && (acc_reg == 8'd0);
    flag = NaN || inf || zero;
  end

endmodule

//////////////////////////////////////////////////////////////////////////////////
// 8-bit Floating-Point Adder/Subtractor E3M4 with GRS Rounding
// - Pre-align ? Align ? AlignShift1 ? Execution ? Normalize ? Round(GRS) ? Exception ? Pack
//////////////////////////////////////////////////////////////////////////////////
// Code your design here

`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 8-bit Floating-Point Adder E3M4
//////////////////////////////////////////////////////////////////////////////////
// Description:
//   Unpipelined 8-bit floating-point adder/subtractor in E3M4 format
//   Supports addition/subtraction (operation=0:add, 1:subtract)
//   Handles special cases: zero, infinity, NaN
//   Follows steps: unpack → align → shift → execute → normalize → exception → pack
//
// Ports:
//   A, B       : 8-bit inputs {Sign[7], Exp[6:4], Mantissa[3:0]}
//   operation  : 0=add, 1=subtract
//   P          : 8-bit result in E3M4
//   Flags      : {Overflow, Underflow, DivideByZero, Invalid, Inexact}
//   NaN, inf, zero : status flags
//////////////////////////////////////////////////////////////////////////////////

module FPAddSub_E3M4(
    input  logic [7:0] A,         // {Sign, Exp[6:4], Mant[3:0]}
    input  logic [7:0] B,
    input  logic       operation, // 0 = add, 1 = subtract
    output logic [7:0] P,         // final 8-bit result
    output logic [4:0] Flags,     // {Overflow, Underflow, DivideByZero, Invalid, Inexact}
    output logic       NaN,       // asserted when output is NaN
    output logic       inf,       // asserted when output is Infinity
    output logic       zero       // asserted when output is Zero
);

    // ---------------------------------------------------
    // 1) Pre-Alignment & Input Exception Detection
    //    Unpack sign, exponent, mantissa and detect special values
    // ---------------------------------------------------
    logic        Sa, Sb;                   // sign bits
    logic [2:0]  expA, expB;               // exponents
    logic [3:0]  mantA, mantB;             // mantissas
    logic        A_NaN, B_NaN;             // input NaN indicators
    logic        A_Inf, B_Inf;             // input Infinity indicators
    logic        A_Zero, B_Zero;           // input Zero indicators
    logic [3:0]  DAB4, DBA4;               // 4-bit exponent difference
    logic [5:0]  ShiftDet;                 // shift control bits [3:0]
    logic [6:0]  Aout, Bout;               // combined exponent+mantissa
    logic        Opout;                    // buffered operation bit

    assign Sa    = A[7];                   // sign of A
    assign Sb    = B[7];                   // sign of B
    assign expA  = A[6:4];
    assign expB  = B[6:4];
    assign mantA = A[3:0];
    assign mantB = B[3:0];

    // Detect NaN, Inf, Zero for inputs
    assign A_NaN  = (expA == 3'b111) && |mantA;
    assign B_NaN  = (expB == 3'b111) && |mantB;
    assign A_Inf  = (expA == 3'b111) && ~|mantA;
    assign B_Inf  = (expB == 3'b111) && ~|mantB;
    assign A_Zero = (expA == 3'b000) && (mantA == 4'b0000);
    assign B_Zero = (expB == 3'b000) && (mantB == 4'b0000);

    // Compute exponent difference for alignment (Aexp - Bexp and vice versa)
    assign DAB4    = {1'b0, expA} + ~{1'b0, expB} + 1;
    assign DBA4    = {1'b0, expB} + ~{1'b0, expA} + 1;
    assign ShiftDet = {DBA4[2:0], DAB4[2:0]};

    assign Aout  = A[6:0];
    assign Bout  = B[6:0];
    assign Opout = operation;

    // ---------------------------------------------------
    // 2) Alignment
    //    Identify which operand has larger exponent and determine shift amount
    // ---------------------------------------------------
    logic        MaxAB;                   // 1 if |B| > |A|
    logic [2:0]  CExp, Shift;             // common exponent, shift count
    logic [3:0]  Mmax, MminP;             // larger and smaller mantissas
    logic [4:0]  Mmin;                    // shifted smaller mantissa with hidden bit

    assign MaxAB = (Aout < Bout);
    assign CExp  = MaxAB ? expB : expA;   // choose larger exponent
    assign Shift = MaxAB ? ShiftDet[5:3] : ShiftDet[2:0];
    assign Mmax  = MaxAB ? Bout[3:0] : Aout[3:0];
    assign MminP = MaxAB ? Aout[3:0] : Bout[3:0];

    // ---------------------------------------------------
    // 3) AlignShift: perform a coarse shift by 4, then fine shift by 0-3 bits
    // ---------------------------------------------------
    logic [4:0] lvl1;
    always_comb begin
        if (Shift[2]) lvl1 = {1'b1, MminP} >> 4;  // coarse by 4
        else          lvl1 = {1'b1, MminP};       // keep hidden bit
    end
    assign Mmin = lvl1 >> Shift[1:0];            // fine shift

    // ---------------------------------------------------
    // 4) Execution: align the mantissa add/sub
    // ---------------------------------------------------
    logic [5:0] Sum;
    logic       PSgn, Opr;

    assign Opr   = Opout ^ Sa ^ Sb;
    wire [4:0] A_mant = {1'b1, Mmax};
    wire [4:0] B_mant =         Mmin;
    wire [5:0] A_ext  = {1'b0, A_mant};
    wire [5:0] B_ext  = {1'b0, B_mant};
    assign Sum   = Opr ? (A_ext - B_ext)
                      : (A_ext + B_ext);
    assign PSgn  = MaxAB ? Sb : Sa;

    // ---------------------------------------------------
    // 5) Normalize: detect leading one and shift
    // ---------------------------------------------------
    logic        MSBShift, ZeroSum;
    logic [2:0]  NormShift;
    logic [3:0]  ExpOK4, ExpOF4;
    logic [2:0]  NormE;
    logic [5:0]  Mnorm;

    assign MSBShift = Sum[5];
    assign ZeroSum  = (Sum == 0);

    assign NormShift = MSBShift ? 3'd0 :
                       Sum[4]   ? 3'd1 :
                       Sum[3]   ? 3'd2 :
                       Sum[2]   ? 3'd3 :
                       Sum[1]   ? 3'd4 :
                       Sum[0]   ? 3'd5 :
                                  3'd0;

    assign ExpOK4 = {1'b0, CExp} - NormShift;
    assign ExpOF4 = ExpOK4 + 4'd1;

    always_comb begin
        if (MSBShift) begin
            Mnorm = {1'b1, Sum[4:1], 1'b0};
            NormE = ExpOF4[2:0];
        end else begin
            Mnorm = Sum << NormShift;
            NormE = ExpOK4[2:0] + 3'd1;  // bump exponent on left-shift
        end
    end

    // ---------------------------------------------------
    // 6) Exception flags
    // ---------------------------------------------------
    logic EOF, NegE, Overflow, Underflow, DivideByZero, Invalid, Inexact;

    assign EOF          = MSBShift ? ExpOF4[3] : ExpOK4[3];
    assign NegE         = ExpOK4[3];
    assign Overflow     = EOF   | A_Inf | B_Inf | A_NaN | B_NaN;
    assign Underflow    = NegE && !MSBShift && (Sum[4:0] != 5'd0);
    assign DivideByZero = 1'b0;
    assign Invalid      = A_NaN | B_NaN;
    assign Inexact      = (!MSBShift && (Sum[4:0] != 5'd0))
                        || Overflow
                        || Underflow;

    assign Flags = {Overflow, Underflow, DivideByZero, Invalid, Inexact};

    // ---------------------------------------------------
    // 7) Pack final result
    // ---------------------------------------------------
    logic [7:0] P_inner;
    assign P_inner = ZeroSum
               ? 8'd0
               : { PSgn, NormE, Mnorm[4:1] };
              
               
    // ---------------------------------------------------
  // 8) Overrides for special cases
    // ---------------------------------------------------
    always_comb begin
      if (A_Zero )
        P = B;
      else if(A_NaN || A_Inf)
        P = A;
      else if (B_Zero )
        P = A;
      else if(B_NaN || B_Inf)
        P = B;
      else
        P = P_inner;
    end

    // ---------------------------------------------------
  // 8) NaN/Inf/Zero flags outputs
    // ---------------------------------------------------
    always_comb begin
        NaN  = 1'b0;
        inf  = 1'b0;
        zero = 1'b0;

        if (A_NaN || B_NaN) begin
            NaN = 1'b1;
        end else if ((A_Inf && B_Zero) || (B_Inf && A_Zero)) begin
            NaN = 1'b1;
        end else if (A_Inf || B_Inf) begin
            inf = 1'b1;
        end else if (A_Zero && B_Zero) begin
            zero = 1'b1;
        end
    end

endmodule

//////////////////////////////////////////////////////////////////////////
// FP MUL block
//////////////////////////////////////////////////////////////////////////
module FPMult8_E3M4 (
  input  logic [7:0] A,      // e3m4 FP input A: [7]=S, [6:4]=E, [3:0]=M
  input  logic [7:0] B,      // e3m4 FP input B
  output logic [7:0] Z,      // e3m4 FP product
  output logic [6:0] Flags,  // Flags: {AnyExcZero, ANaN, BNaN, AInf, BInf, AisZero, BisZero}
  output logic       NaN,    // asserted when output is NaN
  output logic       inf,    // asserted when output is Infinity
  output logic       zero    // asserted when output is Zero
);
  localparam int BIAS = 3;

  // --- Prep: unpack & detect NaN/Inf/Zero ---
  logic        Sa, Sb;
  logic [2:0]  expa, expb;
  logic [3:0]  manta, mantb;
  logic        ANaN, BNaN, AInf, BInf;
  logic        AisZero, BisZero;
 
  // unpack 
  assign Sa      = A[7];
  assign Sb      = B[7];
  assign expa    = A[6:4];
  assign expb    = B[6:4];
  assign manta   = A[3:0];
  assign mantb   = B[3:0];

  // special cases
  assign AisZero = (expa == 3'b000) && (manta == 4'b0000);
  assign BisZero = (expb == 3'b000) && (mantb == 4'b0000);
  assign ANaN    = (expa == 3'b111) && (manta != 4'b0000);
  assign BNaN    = (expb == 3'b111) && (mantb != 4'b0000);
  assign AInf    = (expa == 3'b111) && (manta == 4'b0000);
  assign BInf    = (expb == 3'b111) && (mantb == 4'b0000);

  // flags vector
  assign Flags = {
    (ANaN|BNaN|AInf|BInf|AisZero|BisZero), // Any exception or zero
     ANaN, BNaN, AInf, BInf, AisZero, BisZero
  };

  // --- Build implicit-1 mantissas ---
  logic [4:0] mant_a;
  logic [4:0] mant_b;
  assign mant_a = {1'b1, manta};
  assign mant_b = {1'b1, mantb};

  // --- Execute: multiply, normalize, GRS ---
  logic [9:0] Mp;
  assign Mp = mant_a * mant_b;         // 5�5 ? 10 bits

  logic       Sp;
  assign Sp        = Sa ^ Sb;

  logic       overflow1;
  assign overflow1 = Mp[9];

  logic [3:0] NormM;
  assign NormM     = overflow1 ? Mp[8:5] : Mp[7:4];

  logic [3:0] NormE;
  assign NormE     = expa + expb + overflow1;

  logic       guard_bit;
  assign guard_bit  = overflow1 ? Mp[4]    : Mp[3];

  logic       round_bit;
  assign round_bit  = overflow1 ? Mp[3]    : Mp[2];

  logic       sticky_bit;
  assign sticky_bit = overflow1 ? |Mp[2:0] : (Mp[1:0] != 2'b00);

  logic       GRS;
  assign GRS        = guard_bit & (round_bit | sticky_bit);

  // --- Normalize for rounding ---
  logic [3:0] RoundM;
  logic [3:0] RoundE;
  logic [3:0] RoundEP;
  assign RoundM   = NormM;
  assign RoundE   = NormE - BIAS;
  assign RoundEP  = NormE - (BIAS - 1);

  // --- Round: true overflow test with 5-bit path ---
  logic [4:0] RoundM5;
  logic [4:0] RoundMP5;
  logic [4:0] Pre5;
  logic       overflow2;
  logic [3:0] FinalM;
  logic [2:0] FinalE;

  assign RoundM5   = {1'b0, NormM};
  assign RoundMP5  = RoundM5 + 5'd1;
  assign Pre5      = GRS ? RoundMP5 : RoundM5;
  assign overflow2 = Pre5[4];
  assign FinalM    = overflow2 ? Pre5[4:1] : Pre5[3:0];
  assign FinalE    = overflow2 ? RoundEP[2:0] : RoundE[2:0];

  // --- Final pack with special-case handling ---
  logic [7:0] Zpre;
  always_comb begin
    // default clears
    NaN  = 1'b0;
    inf  = 1'b0;
    zero = 1'b0;

    if (ANaN || BNaN) begin
      Zpre = {1'b0, 3'b111, 4'b1000};    // QNaN
      NaN  = 1'b1;
    end else if ((AInf && BisZero) || (BInf && AisZero)) begin
      Zpre = {1'b0, 3'b111, 4'b1000};    // Invalid = QNaN
      NaN  = 1'b1;
    end else if (AInf || BInf) begin
      Zpre = {Sp, 3'b111, 4'b0000};      // Infinity
      inf  = 1'b1;
    end else if (AisZero || BisZero) begin
      Zpre = {Sp, 3'b000, 4'b0000};      // Zero
      zero = 1'b1;
    end else begin
      Zpre = {Sp, FinalE[2:0], FinalM};  // Normal result
    end
  end

  assign Z = Zpre;
endmodule