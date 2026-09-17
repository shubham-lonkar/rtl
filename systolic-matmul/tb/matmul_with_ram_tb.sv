// Copyright (c) 2026 Shubham Lonkar
// SPDX-License-Identifier: MIT

`timescale 1ns / 1ps
`define DWIDTH 8
`define AWIDTH 10
`define MAT_MUL_SIZE 4
`define MASK_WIDTH 4

//////////////////////////////////////////////////////////////////////////
// Self-checking TB for the 4x4 E3M4 systolic matmul (matmul_with_ram)
// Test data is powers of two so every mult/add is exact in E3M4 -- no
// need to model GRS rounding to check results.
//   Test 1: A = 2*I      -> C = 2*B                (checks addressing)
//   Test 2: A = all-ones -> C[i][j] = 1+2+4+8 = 15  (checks accumulate)
//////////////////////////////////////////////////////////////////////////
module matmul_with_ram_tb;

    logic clk;
    logic resetn;
    logic pe_resetn;
    logic start;
    logic done;

    logic [`AWIDTH-1:0] bram_addr_a_ext, bram_addr_b_ext, bram_addr_c_ext;
    logic [`MAT_MUL_SIZE*`DWIDTH-1:0] bram_wdata_a_ext, bram_wdata_b_ext, bram_wdata_c_ext;
    logic [`MAT_MUL_SIZE*`DWIDTH-1:0] bram_rdata_a_ext, bram_rdata_b_ext, bram_rdata_c_ext;
    logic [`MASK_WIDTH-1:0] bram_we_a_ext, bram_we_b_ext, bram_we_c_ext;

    int errors;

    //////////////////////////////////////////////////////////////////
    // DUT
    //////////////////////////////////////////////////////////////////
    matmul_with_ram u_matmul (
        .clk               (clk),
        .resetn            (resetn),
        .pe_resetn         (pe_resetn),
        .address_mat_a     (`AWIDTH'd0),
        .address_mat_b     (`AWIDTH'd0),
        .address_mat_c     (`AWIDTH'd0),
        .address_stride_a  (8'd1),
        .address_stride_b  (8'd1),
        .address_stride_c  (8'd1),
        .bram_addr_a_ext   (bram_addr_a_ext),
        .bram_rdata_a_ext  (bram_rdata_a_ext),
        .bram_wdata_a_ext  (bram_wdata_a_ext),
        .bram_we_a_ext     (bram_we_a_ext),
        .bram_addr_b_ext   (bram_addr_b_ext),
        .bram_rdata_b_ext  (bram_rdata_b_ext),
        .bram_wdata_b_ext  (bram_wdata_b_ext),
        .bram_we_b_ext     (bram_we_b_ext),
        .bram_addr_c_ext   (bram_addr_c_ext),
        .bram_rdata_c_ext  (bram_rdata_c_ext),
        .bram_wdata_c_ext  (bram_wdata_c_ext),
        .bram_we_c_ext     (bram_we_c_ext),
        .start             (start),
        .done              (done)
    );

    //////////////////////////////////////////////////////////////////
    // Clock / reset
    //////////////////////////////////////////////////////////////////
    initial clk = 0;
    always #5 clk = ~clk;   // 100 MHz functional clock (timing comes from STA, not this)

    //////////////////////////////////////////////////////////////////
    // E3M4 encode of small exact integers 0-15 (sign=0, bias=3)
    //////////////////////////////////////////////////////////////////
    function automatic logic [7:0] e3m4(input int unsigned v);
        case (v)
            0:  e3m4 = 8'h00;
            1:  e3m4 = 8'h30;
            2:  e3m4 = 8'h40;
            4:  e3m4 = 8'h50;
            8:  e3m4 = 8'h60;
            15: e3m4 = 8'h6E;
            default: begin
                e3m4 = 8'h00;
                $display("ERROR: e3m4() called with unsupported value %0d", v);
            end
        endcase
    endfunction

    // pack 4 row/column elements (idx0 = LSB byte) into one BRAM word
    function automatic logic [31:0] pack4(input int e0, e1, e2, e3);
        pack4 = {e3m4(e3), e3m4(e2), e3m4(e1), e3m4(e0)};
    endfunction

    //////////////////////////////////////////////////////////////////
    // BRAM access tasks (through the DUT's external ports, port 1 of
    // each dual-port RAM)
    //////////////////////////////////////////////////////////////////
    task automatic write_a(input [`AWIDTH-1:0] addr, input [31:0] data);
        @(negedge clk);
        bram_addr_a_ext  = addr;
        bram_wdata_a_ext = data;
        bram_we_a_ext    = 4'b1111;
        @(negedge clk);
        bram_we_a_ext    = 4'b0000;
    endtask

    task automatic write_b(input [`AWIDTH-1:0] addr, input [31:0] data);
        @(negedge clk);
        bram_addr_b_ext  = addr;
        bram_wdata_b_ext = data;
        bram_we_b_ext    = 4'b1111;
        @(negedge clk);
        bram_we_b_ext    = 4'b0000;
    endtask

    task automatic read_c(input [`AWIDTH-1:0] addr, output [31:0] data);
        @(negedge clk);
        bram_addr_c_ext = addr;
        @(negedge clk);
        data = bram_rdata_c_ext;
    endtask

    // matrix_C RAM stores C column-major: ram_c[col] = {C[3][col],C[2][col],C[1][col],C[0][col]}
    task automatic check_c(input int expected [4][4], input string test_name);
        logic [31:0] col_data;
        int actual_int;
        logic [7:0] actual_e3m4, expected_e3m4;
        for (int col = 0; col < 4; col++) begin
            read_c(col, col_data);
            for (int row = 0; row < 4; row++) begin
                actual_e3m4   = col_data[row*8 +: 8];
                expected_e3m4 = e3m4(expected[row][col]);
                if (actual_e3m4 !== expected_e3m4) begin
                    $display("%s: FAIL C[%0d][%0d] = 0x%02h, expected 0x%02h (%0d)",
                              test_name, row, col, actual_e3m4, expected_e3m4, expected[row][col]);
                    errors++;
                end else begin
                    $display("%s: PASS C[%0d][%0d] = 0x%02h (%0d)",
                              test_name, row, col, actual_e3m4, expected[row][col]);
                end
            end
        end
    endtask

    task automatic run_matmul;
        start = 1;
        @(posedge clk);
        start = 0;
        @(posedge done);
        repeat (2) @(posedge clk);
    endtask

    task automatic clear_pe_array;
        pe_resetn = 0;
        repeat (2) @(posedge clk);
        pe_resetn = 1;
        repeat (2) @(posedge clk);
    endtask

    //////////////////////////////////////////////////////////////////
    // Stimulus
    //////////////////////////////////////////////////////////////////
    int expected [4][4];

    initial begin
        errors           = 0;
        start            = 0;
        resetn           = 0;
        pe_resetn        = 0;
        bram_we_a_ext    = 4'b0;
        bram_we_b_ext    = 4'b0;
        bram_we_c_ext    = 4'b0;   // driven by DUT normally; ext port unused for writes here
        bram_addr_a_ext  = '0;
        bram_addr_b_ext  = '0;
        bram_addr_c_ext  = '0;
        bram_wdata_a_ext = '0;
        bram_wdata_b_ext = '0;
        bram_wdata_c_ext = '0;

        repeat (5) @(posedge clk);
        resetn    = 1;
        pe_resetn = 1;
        repeat (5) @(posedge clk);

        //=====================================================
        // Test 1: A = 2*I, B = arbitrary -> C = 2*B
        //=====================================================
        $display("\n=== Test 1: A = 2*I (connectivity / addressing) ===");
        write_a(0, pack4(2, 0, 0, 0));  // row 0
        write_a(1, pack4(0, 2, 0, 0));  // row 1
        write_a(2, pack4(0, 0, 2, 0));  // row 2
        write_a(3, pack4(0, 0, 0, 2));  // row 3

        // B kept <=4 so 2*B stays exact (max exact int in E3M4 is 15)
        write_b(0, pack4(1, 2, 4, 0));  // row 0
        write_b(1, pack4(4, 1, 2, 0));  // row 1
        write_b(2, pack4(2, 4, 1, 0));  // row 2
        write_b(3, pack4(0, 2, 4, 1));  // row 3

        run_matmul();

        expected = '{'{2, 4, 8, 0}, '{8, 2, 4, 0}, '{4, 8, 2, 0}, '{0, 4, 8, 2}};
        check_c(expected, "Test1");

        clear_pe_array();

        //=====================================================
        // Test 2: A = all-ones, B columns permutations of {1,2,4,8}
        // -> every C[i][j] = 1+2+4+8 = 15
        //=====================================================
        $display("\n=== Test 2: A = all-ones (4-term accumulation) ===");
        write_a(0, pack4(1, 1, 1, 1));
        write_a(1, pack4(1, 1, 1, 1));
        write_a(2, pack4(1, 1, 1, 1));
        write_a(3, pack4(1, 1, 1, 1));

        write_b(0, pack4(1, 2, 4, 8));
        write_b(1, pack4(2, 4, 8, 1));
        write_b(2, pack4(4, 8, 1, 2));
        write_b(3, pack4(8, 1, 2, 4));

        run_matmul();

        expected = '{'{15, 15, 15, 15}, '{15, 15, 15, 15}, '{15, 15, 15, 15}, '{15, 15, 15, 15}};
        check_c(expected, "Test2");

        repeat (10) @(posedge clk);
        if (errors == 0) $display("\n*** ALL TESTS PASSED ***");
        else              $display("\n*** %0d CHECK(S) FAILED ***", errors);

        $finish;
    end

    initial begin
        #100000;
        $display("ERROR: testbench timeout");
        $finish;
    end

endmodule
