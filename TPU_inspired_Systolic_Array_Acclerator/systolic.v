
module systolic_pe (
    input wire clk,
    input wire rst_n,
    input wire clear_acc,

    input wire signed [7:0] a_in,
    input wire signed [7:0] b_in,

    input wire a_valid_in,
    input wire b_valid_in,

    output reg signed [7:0] a_out,
    output reg signed [7:0] b_out,

    output reg a_valid_out,
    output reg b_valid_out,

    output reg signed [31:0] acc_out
);

    wire signed [15:0] product;

    assign product = $signed(a_in) * $signed(b_in);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_out       <= 8'sd0;
            b_out       <= 8'sd0;
            a_valid_out <= 1'b0;
            b_valid_out <= 1'b0;
            acc_out     <= 32'sd0;
        end
        else begin

            // Forward A horizontally
            a_out       <= a_in;
            a_valid_out <= a_valid_in;

            // Forward B vertically
            b_out       <= b_in;
            b_valid_out <= b_valid_in;

            if (clear_acc) begin
                acc_out <= 32'sd0;
            end
            else if (a_valid_in && b_valid_in) begin
                acc_out <= acc_out +
                           {{16{product[15]}}, product};
            end
        end
    end

endmodule


module systolic_array #(parameter N = 4)(
    input wire clk,
    input wire rst_n,
    input wire clear_acc,


    input wire [N*8-1:0] a_row_in,
    input wire [N-1:0] a_valid_in,

    input wire [N*8-1:0] b_col_in,
    input wire [N-1:0] b_valid_in,

    // N x N signed 32-bit PE accumulators
    output wire [N*N*32-1:0] acc_out
);

    // Internal horizontal and vertical data paths
    wire [N*N*8-1:0] a_data;
    wire [N*N*8-1:0] b_data;

    wire [N*N-1:0] a_valid;
    wire [N*N-1:0] b_valid;

    genvar i, j;

    generate
        for (i = 0; i < N; i = i + 1) begin : ROW
            for (j = 0; j < N; j = j + 1) begin : COL

                wire signed [7:0] pe_a_in;
                wire signed [7:0] pe_b_in;

                wire pe_a_valid;
                wire pe_b_valid;

                wire signed [7:0] pe_a_out;
                wire signed [7:0] pe_b_out;

                wire pe_a_valid_out;
                wire pe_b_valid_out;

                // A enters from the left
                if (j == 0) begin
                    assign pe_a_in =
                        a_row_in[i*8 +: 8];

                    assign pe_a_valid =
                        a_valid_in[i];
                end
                else begin
                    assign pe_a_in =
                        a_data[(i*N+j-1)*8 +: 8];

                    assign pe_a_valid =
                        a_valid[(i*N+j-1)];
                end

                // B enters from the top
                if (i == 0) begin
                    assign pe_b_in =
                        b_col_in[j*8 +: 8];

                    assign pe_b_valid =
                        b_valid_in[j];
                end
                else begin
                    assign pe_b_in =
                        b_data[((i-1)*N+j)*8 +: 8];

                    assign pe_b_valid =
                        b_valid[((i-1)*N+j)];
                end

                // Instantiate processing element
                systolic_pe PE (
                    .clk(clk),
                    .rst_n(rst_n),
                    .clear_acc(clear_acc),

                    .a_in(pe_a_in),
                    .b_in(pe_b_in),

                    .a_valid_in(pe_a_valid),
                    .b_valid_in(pe_b_valid),

                    .a_out(pe_a_out),
                    .b_out(pe_b_out),

                    .a_valid_out(pe_a_valid_out),
                    .b_valid_out(pe_b_valid_out),

                    .acc_out(
                        acc_out[(i*N+j)*32 +: 32]
                    )
                );

                // Connect outputs to neighboring PEs
                assign a_data[(i*N+j)*8 +: 8] =
                    pe_a_out;

                assign b_data[(i*N+j)*8 +: 8] =
                    pe_b_out;

                assign a_valid[(i*N+j)] =
                    pe_a_valid_out;

                assign b_valid[(i*N+j)] =
                    pe_b_valid_out;

            end
        end
    endgenerate

endmodule


`timescale 1ns / 1ps

// module tb_systolic_pe;

//     reg clk;
//     reg rst_n;
//     reg clear_acc;

//     reg signed [7:0] a_in;
//     reg signed [7:0] b_in;

//     reg a_valid_in;
//     reg b_valid_in;

//     wire signed [7:0] a_out;
//     wire signed [7:0] b_out;

//     wire a_valid_out;
//     wire b_valid_out;

//     wire signed [31:0] acc_out;

//     integer errors;

//     // DUT
//     systolic_pe DUT (
//         .clk(clk),
//         .rst_n(rst_n),
//         .clear_acc(clear_acc),

//         .a_in(a_in),
//         .b_in(b_in),

//         .a_valid_in(a_valid_in),
//         .b_valid_in(b_valid_in),

//         .a_out(a_out),
//         .b_out(b_out),

//         .a_valid_out(a_valid_out),
//         .b_valid_out(b_valid_out),

//         .acc_out(acc_out)
//     );

//     // Clock: 10 ns period
//     always #5 clk = ~clk;

//     // Apply inputs on falling edge
//     task apply_mac;
//         input signed [7:0] a;
//         input signed [7:0] b;
//         input valid;
//         begin
//             @(negedge clk);
//             a_in = a;
//             b_in = b;
//             a_valid_in = valid;
//             b_valid_in = valid;
//         end
//     endtask

//     task check_acc;
//         input signed [31:0] expected;
//         begin
//             @(posedge clk);
//             #1;
//             if (acc_out !== expected) begin
//                 $display("FAIL: Expected %0d, Got %0d",
//                          expected, acc_out);
//                 errors = errors + 1;
//             end
//             else begin
//                 $display("PASS: Accumulator = %0d", acc_out);
//             end
//         end
//     endtask

//     initial begin

//         clk = 0;
//         rst_n = 0;
//         clear_acc = 0;

//         a_in = 0;
//         b_in = 0;
//         a_valid_in = 0;
//         b_valid_in = 0;

//         errors = 0;

//         // Reset
//         repeat(2) @(negedge clk);
//         rst_n = 1;

//         // Clear accumulator
//         clear_acc = 1;
//         @(posedge clk);
//         #1;
//         if (acc_out !== 0) begin
//             $display("FAIL: Reset/clear");
//             errors = errors + 1;
//         end
//         @(negedge clk);
//         clear_acc = 0;

//         // 10 * 5 = 50
//         apply_mac(10, 5, 1);
//         check_acc(50);

//         // 4 * 3 = 12; total = 62
//         apply_mac(4, 3, 1);
//         check_acc(62);

//         // -2 * 6 = -12; total = 50
//         apply_mac(-2, 6, 1);
//         check_acc(50);

//         // 8 * 2 = 16; total = 66
//         apply_mac(8, 2, 1);
//         check_acc(66);

//         // Invalid cycle: accumulator must not change
//         apply_mac(100, 100, 0);
//         check_acc(66); // Meaning the same value holds

//         // Forwarding check
//         if (a_out !== 8'd100 || b_out !== 8'd100 ||
//             a_valid_out !== 1'b0 || b_valid_out !== 1'b0) begin
//             $display("FAIL: Forwarding check");
//             errors = errors + 1;
//         end
//         else begin
//             $display("PASS: Operand forwarding");
//         end

//         // Clear accumulator
//         @(negedge clk);
//         clear_acc = 1;
//         @(posedge clk);
//         #1;
//         if (acc_out !== 0) begin
//             $display("FAIL: Accumulator clear");
//             errors = errors + 1;
//         end
//         else begin
//             $display("PASS: Accumulator clear");
//         end

//         if (errors == 0)
//             $display("\nALL PE TESTS PASSED");
//         else
//             $display("\nPE TEST FAILED: %0d errors", errors);

//         $finish;
//     end

//     initial begin
//     $dumpfile("tb_systolic_pe.vcd");
//     $dumpvars(0,tb_systolic_pe);
//     end

// endmodule


`timescale 1ns / 1ps

module tb_systolic_array;

    parameter N = 4;

    // Clock and control
    reg clk;
    reg rst_n;
    reg clear_acc;

    // Array inputs
    reg [N*8-1:0] a_row_in;
    reg [N-1:0] a_valid_in;

    reg [N*8-1:0] b_col_in;
    reg [N-1:0] b_valid_in;

    // Array outputs
    wire [N*N*32-1:0] acc_out;

    // Reference matrices
    reg signed [7:0] A [0:N-1][0:N-1];
    reg signed [7:0] B [0:N-1][0:N-1];

    integer i, j, k;
    integer cycle_count;
    integer expected;
    integer actual;
    integer errors;

    reg [N*8-1:0] a_temp;
    reg [N*8-1:0] b_temp;

    // DUT
    systolic_array #(
        .N(N)
    ) DUT (
        .clk(clk),
        .rst_n(rst_n),
        .clear_acc(clear_acc),

        .a_row_in(a_row_in),
        .a_valid_in(a_valid_in),

        .b_col_in(b_col_in),
        .b_valid_in(b_valid_in),

        .acc_out(acc_out)
    );

    // 100 MHz clock
    initial clk = 1'b0;
    always #5 clk = ~clk;


    // ------------------------------------------------
    // Initialize test matrices
    // ------------------------------------------------

    task initialize_matrices;
    begin

        // Matrix A
        A[0][0] = 1;  A[0][1] = 2;
        A[0][2] = 3;  A[0][3] = 4;

        A[1][0] = 5;  A[1][1] = 6;
        A[1][2] = 7;  A[1][3] = 8;

        A[2][0] = 9;  A[2][1] = 10;
        A[2][2] = 11; A[2][3] = 12;

        A[3][0] = 13; A[3][1] = 14;
        A[3][2] = 15; A[3][3] = 16;


        // Matrix B
        B[0][0] = 1; B[0][1] = 0;
        B[0][2] = 0; B[0][3] = 0;

        B[1][0] = 0; B[1][1] = 2;
        B[1][2] = 0; B[1][3] = 0;

        B[2][0] = 0; B[2][1] = 0;
        B[2][2] = 3; B[2][3] = 0;

        B[3][0] = 0; B[3][1] = 0;
        B[3][2] = 0; B[3][3] = 4;

    end
    endtask


    // ------------------------------------------------
    // Generate skewed input data
    // ------------------------------------------------

    task feed_matrices;
        integer r, c, idx;
    begin

        // 2*N-1 cycles are required to inject
        // all skewed matrix elements.

        for (cycle_count = 0;
             cycle_count < (2*N-1);
             cycle_count = cycle_count + 1) begin

            @(negedge clk);

            a_temp = 0;
            b_temp = 0;

            a_valid_in = 0;
            b_valid_in = 0;

            // Feed A rows.
            // Row r is delayed by r cycles.

            for (r = 0; r < N; r = r+1) begin

                idx = cycle_count - r;

                if (idx >= 0 && idx < N) begin

                    a_temp[r*8 +: 8] = A[r][idx];
                    a_valid_in[r] = 1'b1;

                end

            end


            // Feed B columns.
            // Column c is delayed by c cycles.

            for (c = 0; c < N; c = c+1) begin

                idx = cycle_count - c;

                if (idx >= 0 && idx < N) begin

                    b_temp[c*8 +: 8] = B[idx][c];
                    b_valid_in[c] = 1'b1;

                end

            end

            a_row_in = a_temp;
            b_col_in = b_temp;

            $display(
                "Input cycle %0d: A_valid=%b B_valid=%b",
                cycle_count, a_valid_in, b_valid_in
            );

        end

        // Stop injecting new operands
        @(negedge clk);

        a_row_in = 0;
        b_col_in = 0;

        a_valid_in = 0;
        b_valid_in = 0;

    end
    endtask


    // ------------------------------------------------
    // Wait for data propagation and computation
    // ------------------------------------------------

    task wait_for_completion;
    begin

        // Allow the final operands to travel
        // through the registered PE connections.

        repeat (N+2) begin
            @(posedge clk);
        end

        #1;

    end
    endtask



    task check_results;
    begin

        errors = 0;

        $display("\n=================================");
        $display("     SYSTOLIC ARRAY RESULTS");
        $display("=================================");

        for (i = 0; i < N; i = i+1) begin

            for (j = 0; j < N; j = j+1) begin

                expected = 0;

                // Software reference multiplication
                for (k = 0; k < N; k = k+1) begin

                    expected = expected +
                               A[i][k] * B[k][j];

                end

                // Extract corresponding PE accumulator
                actual = $signed(
                    acc_out[(i*N+j)*32 +: 32]
                );

                if (actual == expected) begin

                    $display(
                        "PASS C[%0d][%0d]: Expected=%0d Actual=%0d",
                        i, j, expected, actual
                    );

                end
                else begin

                    $display(
                        "FAIL C[%0d][%0d]: Expected=%0d Actual=%0d",
                        i, j, expected, actual
                    );

                    errors = errors + 1;

                end

            end

        end

        $display("---------------------------------");

        if (errors == 0)
            $display("ALL ARRAY TESTS PASSED");
        else
            $display("ARRAY TEST FAILED: %0d errors", errors);

        $display("=================================\n");

    end
    endtask



    initial begin

        rst_n = 0;
        clear_acc = 0;

        a_row_in = 0;
        b_col_in = 0;

        a_valid_in = 0;
        b_valid_in = 0;

        errors = 0;

        initialize_matrices();

        // Reset
        repeat (3) @(negedge clk);
        rst_n = 1;

        // Clear all PE accumulators
        @(negedge clk);
        clear_acc = 1;

        @(negedge clk);
        clear_acc = 0;

        // Feed both matrices
        feed_matrices();

        // Wait for all PE computations
        wait_for_completion();

        // Verify all 16 outputs
        check_results();

        $finish;

    end

    initial begin
    $dumpfile("tb_systolic_array.vcd");
    $dumpvars(0,tb_systolic_array);
    end
endmodule