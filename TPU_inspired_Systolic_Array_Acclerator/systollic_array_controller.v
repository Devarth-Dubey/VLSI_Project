
`timescale 1ns / 1ps

module systolic_array_controller #(
    parameter N = 4,
    parameter K = 4,
    parameter ADDR_WIDTH = 8,
    parameter ACC_ADDR_WIDTH = 4
)(
    input wire clk,
    input wire rst_n,

    // Start and configuration
    input wire start,
    input wire [ADDR_WIDTH-1:0] activation_base_addr,
    input wire [ADDR_WIDTH-1:0] weight_base_addr,
    input wire [ACC_ADDR_WIDTH-1:0] result_addr,
    input wire accumulate_enable,

    output wire busy,
    output wire done,

    // Scratchpad read interfaces
    output reg [ADDR_WIDTH-1:0] activation_raddr,
    input wire signed [7:0] activation_rdata,

    output reg [ADDR_WIDTH-1:0] weight_raddr,
    input wire signed [7:0] weight_rdata,

    // Systolic array interface
    output reg clear_pe_acc,

    output reg [N*8-1:0] a_row_in,
    output reg [N-1:0] a_valid_in,

    output reg [N*8-1:0] b_col_in,
    output reg [N-1:0] b_valid_in,

    input wire [N*N*32-1:0] pe_results,

    // Accumulator buffer interface
    output reg acc_buffer_write_enable,
    output reg [ACC_ADDR_WIDTH-1:0] acc_buffer_write_addr,
    output reg acc_buffer_accumulate_enable
);

    localparam IDLE    = 3'd0;
    localparam LOAD_A  = 3'd1;
    localparam LOAD_B  = 3'd2;
    localparam CLEAR   = 3'd3;
    localparam FEED    = 3'd4;
    localparam DRAIN   = 3'd5;
    localparam CAPTURE = 3'd6;
    localparam DONE    = 3'd7;

    localparam TILE_SIZE = N*K;
    localparam FEED_LAST = K+N-2;

    localparam LOAD_WIDTH =
        (TILE_SIZE <= 1) ? 1 : $clog2(TILE_SIZE);

    localparam FEED_WIDTH =
        (K+N <= 2) ? 1 : $clog2(K+N-1);

    localparam DRAIN_WIDTH =
        (N <= 2) ? 1 : $clog2(N);

    reg [2:0] state;

    reg [LOAD_WIDTH-1:0] load_count;
    reg [FEED_WIDTH-1:0] feed_count;
    reg [DRAIN_WIDTH-1:0] drain_count;

    reg [ADDR_WIDTH-1:0] activation_base_reg;
    reg [ADDR_WIDTH-1:0] weight_base_reg;

    reg [ACC_ADDR_WIDTH-1:0] result_addr_reg;
    reg accumulate_reg;

    // Internal tile staging registers
    reg signed [7:0] a_tile [0:TILE_SIZE-1];
    reg signed [7:0] b_tile [0:TILE_SIZE-1];


integer reset_i;
integer feed_r;
integer feed_c;
integer index_a;
integer index_b;

    // ------------------------------------------------
    // Controller state machine
    // ------------------------------------------------

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            state <= IDLE;

            load_count <= 0;
            feed_count <= 0;
            drain_count <= 0;

            activation_base_reg <= 0;
            weight_base_reg <= 0;

            result_addr_reg <= 0;
            accumulate_reg <= 0;

            for (reset_i = 0; reset_i < TILE_SIZE; reset_i = reset_i + 1) begin
                a_tile[reset_i] <= 0;
                b_tile[reset_i] <= 0;
            end

        end
        else begin

            case (state)

                IDLE: begin

                    if (start) begin

                        activation_base_reg <= activation_base_addr;
                        weight_base_reg <= weight_base_addr;

                        result_addr_reg <= result_addr;
                        accumulate_reg <= accumulate_enable;

                        load_count <= 0;

                        state <= LOAD_A;

                    end

                end


                LOAD_A: begin

                    a_tile[load_count] <= activation_rdata;

                    if (load_count == TILE_SIZE-1) begin

                        load_count <= 0;
                        state <= LOAD_B;

                    end
                    else begin

                        load_count <= load_count + 1'b1;

                    end

                end


                LOAD_B: begin

                    b_tile[load_count] <= weight_rdata;

                    if (load_count == TILE_SIZE-1) begin

                        load_count <= 0;
                        feed_count <= 0;

                        state <= CLEAR;

                    end
                    else begin

                        load_count <= load_count + 1'b1;

                    end

                end


                CLEAR: begin

                    feed_count <= 0;
                    state <= FEED;

                end


                FEED: begin

                    if (feed_count == FEED_LAST) begin

                        drain_count <= 0;
                        state <= DRAIN;

                    end
                    else begin

                        feed_count <= feed_count + 1'b1;

                    end

                end


                DRAIN: begin

                    if (drain_count == N-2) begin

                        state <= CAPTURE;

                    end
                    else begin

                        drain_count <= drain_count + 1'b1;

                    end

                end


                CAPTURE: begin

                    state <= DONE;

                end


                DONE: begin

                    state <= IDLE;

                end


                default: begin

                    state <= IDLE;

                end

            endcase

        end

    end


    // ------------------------------------------------
    // Scratchpad addresses and data feeder
    // ------------------------------------------------

    always @(*) begin

        activation_raddr = activation_base_reg;
        weight_raddr = weight_base_reg;

        a_row_in = 0;
        b_col_in = 0;

        a_valid_in = 0;
        b_valid_in = 0;

        clear_pe_acc = 0;

        acc_buffer_write_enable = 0;
        acc_buffer_write_addr = result_addr_reg;
        acc_buffer_accumulate_enable = accumulate_reg;

        index_a = 0;
        index_b = 0;



        case (state)

            LOAD_A: begin

                activation_raddr =
                    activation_base_reg + load_count;

            end


            LOAD_B: begin

                weight_raddr =
                    weight_base_reg + load_count;

            end


            CLEAR: begin

                clear_pe_acc = 1;

            end


            FEED: begin

                for (feed_r = 0; feed_r < N; feed_r = feed_r + 1) begin

                    index_a = feed_count;
                    index_a = index_a - feed_r;

                    if ((index_a >= 0) && (index_a < K)) begin
                        a_row_in[feed_r*8 +: 8] =
                            a_tile[feed_r*K + index_a];

                        a_valid_in[feed_r] = 1'b1;
                    end

                end

                for (feed_c = 0; feed_c < N; feed_c = feed_c + 1) begin

                    index_b = feed_count;
                    index_b = index_b - feed_c;

                    if ((index_b >= 0) && (index_b < K)) begin
                        b_col_in[feed_c*8 +: 8] =
                            b_tile[index_b*N + feed_c];

                        b_valid_in[feed_c] = 1'b1;
                    end

                end

            end


            CAPTURE: begin

                acc_buffer_write_enable = 1'b1;

            end


            default: begin

                // No operation

            end

        endcase

    end


    // ------------------------------------------------
    // Status outputs
    // ------------------------------------------------

    assign busy = (state != IDLE) && (state != DONE);

    assign done = (state == DONE);

endmodule

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

module scratchpad_ram #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 8,
    parameter DEPTH      = 256
)(
    input  wire                         clk,
    input  wire                         rst_n,

    // Write port
    input  wire                         write_enable,
    input  wire [ADDR_WIDTH-1:0]        write_addr,
    input  wire [DATA_WIDTH-1:0]        write_data,

    // Read port
    input  wire [ADDR_WIDTH-1:0]        read_addr,
    output wire signed [DATA_WIDTH-1:0] read_data
);

    // Register-based memory
    reg [DATA_WIDTH-1:0] memory [0:DEPTH-1];

    integer i;

    // Synchronous write and reset
    always @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < DEPTH; i = i + 1)
                memory[i] <= {DATA_WIDTH{1'b0}};
        end
        else if (write_enable) begin
            memory[write_addr] <= write_data;
        end
    end

    // Asynchronous read
    assign read_data = memory[read_addr];

endmodule

module scratchpad_subsystem #(
parameter DATA_WIDTH = 8,
parameter ADDR_WIDTH = 8,
parameter DEPTH      = 256
)(
input wire clk,
input wire rst_n,

// Activation scratchpad write port
input wire activation_we,
input wire [ADDR_WIDTH-1:0] activation_waddr,
input wire [DATA_WIDTH-1:0] activation_wdata,

// Activation scratchpad read port
input wire [ADDR_WIDTH-1:0] activation_raddr,
output wire signed [DATA_WIDTH-1:0] activation_rdata,

// Weight scratchpad write port
input wire weight_we,
input wire [ADDR_WIDTH-1:0] weight_waddr,
input wire [DATA_WIDTH-1:0] weight_wdata,

// Weight scratchpad read port
input wire [ADDR_WIDTH-1:0] weight_raddr,
output wire signed [DATA_WIDTH-1:0] weight_rdata
);

// Activation memory
scratchpad_ram #(
.DATA_WIDTH(DATA_WIDTH),
.ADDR_WIDTH(ADDR_WIDTH),
.DEPTH(DEPTH)
) activation_memory (
.clk(clk),
.rst_n(rst_n),

.write_enable(activation_we),
.write_addr(activation_waddr),
.write_data(activation_wdata),

.read_addr(activation_raddr),
.read_data(activation_rdata)
);

// Weight memory
scratchpad_ram #(
.DATA_WIDTH(DATA_WIDTH),
.ADDR_WIDTH(ADDR_WIDTH),
.DEPTH(DEPTH)
) weight_memory (
.clk(clk),
.rst_n(rst_n),

.write_enable(weight_we),
.write_addr(weight_waddr),
.write_data(weight_wdata),

.read_addr(weight_raddr),
.read_data(weight_rdata)
);

endmodule

module accumulator_buffer #(
    parameter DATA_WIDTH = 32,
    parameter NUM_PE     = 16,
    parameter DEPTH      = 16,
    parameter ADDR_WIDTH = 4,
    parameter PE_ADDR_WIDTH = 4
)(
    input wire clk,
    input wire rst_n,

    // Parallel PE results
    input wire [NUM_PE*DATA_WIDTH-1:0] pe_results,

    // Write control
    input wire write_enable,
    input wire accumulate_enable,
    input wire [ADDR_WIDTH-1:0] write_addr,

    // Clear one buffer entry
    input wire clear_entry,
    input wire [ADDR_WIDTH-1:0] clear_addr,

    // Read control
    input wire [ADDR_WIDTH-1:0] read_addr,
    input wire [PE_ADDR_WIDTH-1:0] read_pe,

    output wire signed [DATA_WIDTH-1:0] read_data
);

    // Each entry stores NUM_PE independent accumulators
    reg signed [DATA_WIDTH-1:0]
        memory [0:DEPTH-1][0:NUM_PE-1];

    integer i, j;

    // Synchronous reset, clear and write
    always @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < DEPTH; i = i + 1) begin
                for (j = 0; j < NUM_PE; j = j + 1) begin
                    memory[i][j] <= {DATA_WIDTH{1'b0}};
                end
            end
        end
        else if (clear_entry) begin
            for (j = 0; j < NUM_PE; j = j + 1) begin
                memory[clear_addr][j] <= {DATA_WIDTH{1'b0}};
            end
        end
        else if (write_enable) begin
            for (j = 0; j < NUM_PE; j = j + 1) begin

                if (accumulate_enable) begin
                    memory[write_addr][j] <=
                        memory[write_addr][j] +
                        $signed(pe_results[j*DATA_WIDTH +: DATA_WIDTH]);
                end
                else begin
                    memory[write_addr][j] <=
                        $signed(pe_results[j*DATA_WIDTH +: DATA_WIDTH]);
                end

            end
        end
    end

    // Asynchronous read of one PE lane
    assign read_data = memory[read_addr][read_pe];

endmodule

module tb_systolic_array_controller;

    parameter N = 4;

reg clk;
    reg rst_n;

// External scratchpad write interface
    reg activation_we;
    reg [7:0] activation_waddr;
    reg [7:0] activation_wdata;

reg weight_we;
    reg [7:0] weight_waddr;
    reg [7:0] weight_wdata;

// Scratchpad read interface
    wire [7:0] activation_raddr;
    wire signed [7:0] activation_rdata;

wire [7:0] weight_raddr;
    wire signed [7:0] weight_rdata;

// Controller configuration
    reg start;
    reg [7:0] activation_base_addr;
    reg [7:0] weight_base_addr;

reg [3:0] result_addr;
    reg accumulate_enable;

wire busy;
    wire done;

// Systolic array signals
    wire clear_pe_acc;

wire [N*8-1:0] a_row_in;
    wire [N-1:0] a_valid_in;

wire [N*8-1:0] b_col_in;
    wire [N-1:0] b_valid_in;

    wire [N*N*32-1:0] pe_results;

// Accumulator signals
    wire acc_buffer_we;
    wire [3:0] acc_buffer_waddr;
    wire acc_buffer_accumulate;

reg [3:0] acc_read_addr;
    reg [3:0] acc_read_pe;

    wire signed [31:0] acc_read_data;

integer i;
    integer errors;
    integer expected;

reg [7:0] A [0:15];
    reg [7:0] B [0:15];

// ------------------------------------------------
    // Clock
    // ------------------------------------------------

initial clk = 0;
    always #5 clk = ~clk;

// ------------------------------------------------
    // Scratchpad subsystem
    // ------------------------------------------------

scratchpad_subsystem #(
        .DATA_WIDTH(8),
        .ADDR_WIDTH(8),
        .DEPTH(256)
    ) SCRATCHPAD (

.clk(clk),
        .rst_n(rst_n),

.activation_we(activation_we),
        .activation_waddr(activation_waddr),
        .activation_wdata(activation_wdata),

.activation_raddr(activation_raddr),
        .activation_rdata(activation_rdata),

.weight_we(weight_we),
        .weight_waddr(weight_waddr),
        .weight_wdata(weight_wdata),

.weight_raddr(weight_raddr),
        .weight_rdata(weight_rdata)

    );

// ------------------------------------------------
    // Controller
    // ------------------------------------------------

systolic_array_controller #(
        .N(4),
        .K(4),
        .ADDR_WIDTH(8),
        .ACC_ADDR_WIDTH(4)
    ) CONTROLLER (

.clk(clk),
        .rst_n(rst_n),

        .start(start),

.activation_base_addr(activation_base_addr),
        .weight_base_addr(weight_base_addr),

.result_addr(result_addr),
        .accumulate_enable(accumulate_enable),

.busy(busy),
        .done(done),

.activation_raddr(activation_raddr),
        .activation_rdata(activation_rdata),

.weight_raddr(weight_raddr),
        .weight_rdata(weight_rdata),

        .clear_pe_acc(clear_pe_acc),

.a_row_in(a_row_in),
        .a_valid_in(a_valid_in),

.b_col_in(b_col_in),
        .b_valid_in(b_valid_in),

        .pe_results(pe_results),

.acc_buffer_write_enable(acc_buffer_we),
        .acc_buffer_write_addr(acc_buffer_waddr),
        .acc_buffer_accumulate_enable(acc_buffer_accumulate)

    );

// ------------------------------------------------
    // Systolic array
    // ------------------------------------------------

systolic_array #(
        .N(N)
    ) ARRAY (

.clk(clk),
        .rst_n(rst_n),
        .clear_acc(clear_pe_acc),

.a_row_in(a_row_in),
        .a_valid_in(a_valid_in),

.b_col_in(b_col_in),
        .b_valid_in(b_valid_in),

        .acc_out(pe_results)

    );

// ------------------------------------------------
    // Accumulator buffer
    // ------------------------------------------------

accumulator_buffer #(
        .DATA_WIDTH(32),
        .NUM_PE(16),
        .DEPTH(16),
        .ADDR_WIDTH(4),
        .PE_ADDR_WIDTH(4)
    ) ACCUMULATOR (

.clk(clk),
        .rst_n(rst_n),

        .pe_results(pe_results),

.write_enable(acc_buffer_we),
        .accumulate_enable(acc_buffer_accumulate),
        .write_addr(acc_buffer_waddr),

.clear_entry(1'b0),
        .clear_addr(4'd0),

.read_addr(acc_read_addr),
        .read_pe(acc_read_pe),

        .read_data(acc_read_data)

    );

// ------------------------------------------------
    // Load matrices into scratchpad
    // ------------------------------------------------

    task load_matrices;

        integer j;

        begin

            for (j = 0; j < 16; j = j + 1) begin

                @(negedge clk);

activation_we = 1'b1;
                weight_we = 1'b1;

activation_waddr = j;
                weight_waddr = j;

activation_wdata = A[j];
                weight_wdata = B[j];

            end

            @(negedge clk);

activation_we = 0;
            weight_we = 0;

        end

    endtask

// ------------------------------------------------
    // Check accumulator results
    // ------------------------------------------------

    task check_results;

integer row;
        integer col;
        integer pe;

        begin

            errors = 0;

            $display("\nChecking matrix multiplication results:");

            for (row = 0; row < 4; row = row + 1) begin

                for (col = 0; col < 4; col = col + 1) begin

                    pe = row*4 + col;

// B is diagonal: B[col][col] = col+1
                    expected = (row*4 + col + 1)*(col+1);

acc_read_addr = 0;
                    acc_read_pe = pe;

                    #1;

                    if ($signed(acc_read_data) == expected) begin

$display(
                            "PASS: C[%0d][%0d] = %0d",
                            row, col, $signed(acc_read_data)
                        );

end
                    else begin

$display(
                            "FAIL: C[%0d][%0d] Expected=%0d Actual=%0d",
                            row, col, expected,
                            $signed(acc_read_data)
                        );

                        errors = errors + 1;

                    end

                end

            end

        end

    endtask

// ------------------------------------------------
    // Main test
    // ------------------------------------------------

    initial begin

        rst_n = 0;

        start = 0;

activation_we = 0;
        activation_waddr = 0;
        activation_wdata = 0;

weight_we = 0;
        weight_waddr = 0;
        weight_wdata = 0;

activation_base_addr = 0;
        weight_base_addr = 0;

result_addr = 0;
        accumulate_enable = 0;

acc_read_addr = 0;
        acc_read_pe = 0;

        errors = 0;

// Matrix A = 1 through 16
        for (i = 0; i<16; i = i + 1) begin
            A[i] = i + 1;
            B[i] = 0;
        end

// Matrix B = diagonal [1,2,3,4]
        B[0]  = 1;
        B[5]  = 2;
        B[10] = 3;
        B[15] = 4;

// Reset
        repeat (3) @(posedge clk);

@(negedge clk);
        rst_n = 1;

// Load scratchpad
        $display("\nLoading activation and weight matrices");

        load_matrices();

// Start controller
        $display("\nStarting systolic array operation");

@(negedge clk);
        start = 1;

@(negedge clk);
        start = 0;

// Wait for completion
        wait(done == 1'b1);

        $display("\nController operation completed");

// Read results
        check_results();

if (errors == 0)
            $display("\nALL CONTROLLER INTEGRATION TESTS PASSED");
        else
            $display(
                "\nCONTROLLER INTEGRATION FAILED: %0d errors",
                errors
            );

        $finish;

    end

// Timeout protection
    initial begin
        #10000;
        $display("ERROR: Simulation timeout");
        $finish;
    end

    initial begin

    $dumpfile("tb_systolic_array_controller.vcd");
    $dumpvars(0,tb_systolic_array_controller);

end

endmodule