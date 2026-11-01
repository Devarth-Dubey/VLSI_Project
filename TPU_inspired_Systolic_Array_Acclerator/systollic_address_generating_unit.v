`timescale 1ns / 1ps

module address_generation_unit #(
    parameter ADDR_WIDTH = 32,
    parameter TILE_SIZE = 4
)(
    input wire clk,
    input wire rst_n,

    // Start control
    input wire start,
    input wire [1:0] mode,
    // 00 = Activation A
    // 01 = Weight B
    // 10 = Output C

    // Matrix base addresses (byte addresses)
    input wire [ADDR_WIDTH-1:0] base_a,
    input wire [ADDR_WIDTH-1:0] base_b,
    input wire [ADDR_WIDTH-1:0] base_c,

    // Matrix dimensions
    input wire [ADDR_WIDTH-1:0] matrix_k,
    input wire [ADDR_WIDTH-1:0] matrix_n,

    // Tile indices
    input wire [7:0] tile_m,
    input wire [7:0] tile_n,
    input wire [7:0] tile_k,

    // Address output handshake
    output reg [ADDR_WIDTH-1:0] address,
    output wire address_valid,
    input wire address_ready,

    // Status
    output wire busy,
    output reg done,
    output reg error
);

    localparam MODE_A = 2'b00;
    localparam MODE_B = 2'b01;
    localparam MODE_C = 2'b10;

    reg active;

    reg [1:0] mode_reg;

    reg [ADDR_WIDTH-1:0] base_reg;
    reg [ADDR_WIDTH-1:0] stride_reg;

    reg [7:0] tile_row;
    reg [7:0] tile_col;

    reg [2:0] row_count;
    reg [2:0] col_count;

    reg [ADDR_WIDTH-1:0] global_row;
    reg [ADDR_WIDTH-1:0] global_col;
    reg [ADDR_WIDTH-1:0] element_index;

    assign busy = active;
    assign address_valid = active;

    // Address calculation
    always @(*) begin

        global_row = 0;
        global_col = 0;
        element_index = 0;
        address = 0;

        global_row = ({24'd0, tile_row} << 2)
                     + row_count;

        global_col = ({24'd0, tile_col} << 2)
                     + col_count;

        case (mode_reg)

            // Activation matrix A
            MODE_A: begin

                element_index =
                    (global_row * stride_reg) + global_col;

                address = base_reg + element_index;

            end

            // Weight matrix B
            MODE_B: begin

                element_index =
                    (global_row * stride_reg) + global_col;

                address = base_reg + element_index;

            end

            // Output matrix C (INT32)
            MODE_C: begin

                element_index =
                    (global_row * stride_reg) + global_col;

                address = base_reg + (element_index << 2);

            end

            default: begin
                address = 0;
            end

        endcase

    end

    // Sequential control
    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            active <= 0;

            mode_reg <= 0;
            base_reg <= 0;
            stride_reg <= 0;

            tile_row <= 0;
            tile_col <= 0;

            row_count <= 0;
            col_count <= 0;

            done <= 0;
            error <= 0;

        end else begin

            done <= 0;
            error <= 0;

            // Accept a new request
            if (start && !active) begin

                if ((mode == 2'b11) ||
                    (matrix_k == 0) ||
                    (matrix_n == 0)) begin

                    error <= 1;

                end else begin

                    mode_reg <= mode;

                    tile_row <= 0;
                    tile_col <= 0;

                    row_count <= 0;
                    col_count <= 0;

                    case (mode)

                        MODE_A: begin
                            base_reg <= base_a;
                            stride_reg <= matrix_k;
                            tile_row <= tile_m;
                            tile_col <= tile_k;
                        end

                        MODE_B: begin
                            base_reg <= base_b;
                            stride_reg <= matrix_n;
                            tile_row <= tile_k;
                            tile_col <= tile_n;
                        end

                        MODE_C: begin
                            base_reg <= base_c;
                            stride_reg <= matrix_n;
                            tile_row <= tile_m;
                            tile_col <= tile_n;
                        end

                    endcase

                    active <= 1;

                end
            end

            // Advance only after address handshake
            else if (active && address_ready) begin

                if ((row_count == TILE_SIZE-1) &&
                    (col_count == TILE_SIZE-1)) begin

                    active <= 0;
                    done <= 1;

                end else begin

                    if (col_count == TILE_SIZE-1) begin

                        col_count <= 0;
                        row_count <= row_count + 1'b1;

                    end else begin

                        col_count <= col_count + 1'b1;

                    end

                end

            end

        end

    end

endmodule



module tb_address_generation_unit;

    reg clk;
    reg rst_n;
    reg start;

    reg [1:0] mode;

    reg [31:0] base_a;
    reg [31:0] base_b;
    reg [31:0] base_c;

    reg [31:0] matrix_k;
    reg [31:0] matrix_n;

    reg [7:0] tile_m;
    reg [7:0] tile_n;
    reg [7:0] tile_k;

    reg address_ready;

    wire [31:0] address;
    wire address_valid;
    wire busy;
    wire done;
    wire error;

    integer address_count;

    address_generation_unit dut (

        .clk(clk),
        .rst_n(rst_n),

        .start(start),
        .mode(mode),

        .base_a(base_a),
        .base_b(base_b),
        .base_c(base_c),

        .matrix_k(matrix_k),
        .matrix_n(matrix_n),

        .tile_m(tile_m),
        .tile_n(tile_n),
        .tile_k(tile_k),

        .address(address),
        .address_valid(address_valid),
        .address_ready(address_ready),

        .busy(busy),
        .done(done),
        .error(error)
    );

    always #5 clk = ~clk;

    // Accept every valid address
    always @(posedge clk) begin

        if (!rst_n)
            address_count <= 0;

        else if (address_valid && address_ready)
            address_count <= address_count + 1;

    end

    task run_test;
        input [1:0] test_mode;
        input [31:0] expected_first_address;
        begin

            @(negedge clk);

            mode = test_mode;
            address_count = 0;
            start = 1;

            @(negedge clk);
            start = 0;

            wait(address_valid);

            if (address !== expected_first_address) begin
                $display("FAIL: First address mismatch.");
                $display("Expected: %h, Actual: %h",
                         expected_first_address, address);
                $finish;
            end

            wait(done);

            #1;

            if (address_count == 16)
                $display("Mode %b PASSED: 16 addresses generated",
                         test_mode);
            else begin
                $display("Mode %b FAILED: count = %0d",
                         test_mode, address_count);
                $finish;
            end

            @(negedge clk);

        end
    endtask

    initial begin

        clk = 0;
        rst_n = 0;
        start = 0;

        mode = 0;

        base_a = 32'h00001000;
        base_b = 32'h00002000;
        base_c = 32'h00003000;

        matrix_k = 16;
        matrix_n = 16;

        tile_m = 1;
        tile_n = 2;
        tile_k = 2;

        address_ready = 1;

        #20;
        rst_n = 1;

        // A: row 4, column 8
        run_test(2'b00, 32'h00001048);

        // B: row 8, column 8
        // (8 * 16) + 8 = 136 = 0x88
        run_test(2'b01, 32'h00002088);

        // C: row 4, column 8
        // ((4 * 16) + 8) * 4 = 288 = 0x120
        run_test(2'b10, 32'h00003120);

        $display("--------------------------------");
        $display("AGU TESTS PASSED");
        $display("--------------------------------");

        $finish;

    end
    initial begin

    $dumpfile("tb_address_generation_unit.vcd");
    $dumpvars(0,tb_address_generation_unit);

end

endmodule