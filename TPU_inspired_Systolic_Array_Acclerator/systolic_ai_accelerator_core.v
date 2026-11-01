`timescale 1ns / 1ps

module systolic_ai_accelerator_core #(
    parameter N = 4,
    parameter ADDR_WIDTH = 8,
    parameter ACC_ADDR_WIDTH = 4
)(
    input wire clk,
    input wire rst_n,

    input wire start,
    input wire [ADDR_WIDTH-1:0] activation_base_addr,
    input wire [ADDR_WIDTH-1:0] weight_base_addr,
    input wire [ACC_ADDR_WIDTH-1:0] result_addr,
    input wire accumulate_enable,

    output wire busy,
    output wire done,

    // Activation scratchpad write port
    input wire activation_we,
    input wire [ADDR_WIDTH-1:0] activation_waddr,
    input wire signed [7:0] activation_wdata,

    // Weight scratchpad write port
    input wire weight_we,
    input wire [ADDR_WIDTH-1:0] weight_waddr,
    input wire signed [7:0] weight_wdata,

    // Accumulator buffer read port
    input wire [ACC_ADDR_WIDTH-1:0] acc_read_addr,
    input wire [3:0] acc_read_pe,
    input wire acc_read_valid,

    input wire acc_clear_entry,
    input wire [ACC_ADDR_WIDTH-1:0] acc_clear_addr,

    // Output processing configuration
    input wire [4:0] quant_shift,
    input wire quant_enable,
    input wire [1:0] activation_mode,

    output wire signed [7:0] output_data,
    output wire output_valid
);

    // Scratchpad signals
    wire [ADDR_WIDTH-1:0] activation_raddr;
    wire [ADDR_WIDTH-1:0] weight_raddr;

    wire signed [7:0] activation_rdata;
    wire signed [7:0] weight_rdata;

    // Systolic array signals
    wire clear_pe_acc;

    wire [N*8-1:0] a_row_in;
    wire [N-1:0] a_valid_in;

    wire [N*8-1:0] b_col_in;
    wire [N-1:0] b_valid_in;

    wire [N*N*32-1:0] pe_results;

    // Accumulator signals
    wire acc_buffer_write_enable;
    wire [ACC_ADDR_WIDTH-1:0] acc_buffer_write_addr;
    wire acc_buffer_accumulate_enable;

    wire signed [31:0] acc_read_data;

    // Output processing signals
    wire signed [7:0] quantized_data;
    wire quant_valid;

    // Activation scratchpad
    scratchpad_ram #(
        .DATA_WIDTH(8),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DEPTH(256)
    ) activation_memory (
        .clk(clk),
        .rst_n(rst_n),
        .write_enable(activation_we),
        .write_addr(activation_waddr),
        .write_data(activation_wdata),
        .read_addr(activation_raddr),
        .read_data(activation_rdata)
    );

    // Weight scratchpad
    scratchpad_ram #(
        .DATA_WIDTH(8),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DEPTH(256)
    ) weight_memory (
        .clk(clk),
        .rst_n(rst_n),
        .write_enable(weight_we),
        .write_addr(weight_waddr),
        .write_data(weight_wdata),
        .read_addr(weight_raddr),
        .read_data(weight_rdata)
    );

    // Systolic array controller
    systolic_array_controller #(
        .N(N),
        .K(N),
        .ADDR_WIDTH(ADDR_WIDTH),
        .ACC_ADDR_WIDTH(ACC_ADDR_WIDTH)
    ) array_controller (
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

        .acc_buffer_write_enable(acc_buffer_write_enable),
        .acc_buffer_write_addr(acc_buffer_write_addr),
        .acc_buffer_accumulate_enable(
            acc_buffer_accumulate_enable
        )
    );

    // 4x4 systolic array
    systolic_array #(
        .N(N)
    ) systolic_array_inst (
        .clk(clk),
        .rst_n(rst_n),
        .clear_acc(clear_pe_acc),

        .a_row_in(a_row_in),
        .a_valid_in(a_valid_in),

        .b_col_in(b_col_in),
        .b_valid_in(b_valid_in),

        .acc_out(pe_results)
    );

    // Accumulator buffer
    accumulator_buffer #(
        .DATA_WIDTH(32),
        .NUM_PE(N*N),
        .DEPTH(16),
        .ADDR_WIDTH(ACC_ADDR_WIDTH),
        .PE_ADDR_WIDTH(4)
    ) accumulator_memory (
        .clk(clk),
        .rst_n(rst_n),

        .pe_results(pe_results),

        .write_enable(acc_buffer_write_enable),
        .accumulate_enable(acc_buffer_accumulate_enable),
        .write_addr(acc_buffer_write_addr),

        .clear_entry(acc_clear_entry),
        .clear_addr(acc_clear_addr),

        .read_addr(acc_read_addr),
        .read_pe(acc_read_pe),

        .read_data(acc_read_data)
    );

    // Quantization
    quantization_unit quantizer (
        .data_in(acc_read_data),
        .quant_shift(quant_shift),
        .quant_enable(quant_enable),

        .valid_in(acc_read_valid),

        .data_out(quantized_data),
        .valid_out(quant_valid)
    );

    // Activation
    activation_unit activation (
        .data_in(quantized_data),
        .activation_mode(activation_mode),

        .valid_in(quant_valid),

        .data_out(output_data),
        .valid_out(output_valid)
    );

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

module quantization_unit (
    input  wire signed [31:0] data_in,
    input  wire        [4:0]  quant_shift,
    input  wire               quant_enable,
    input  wire               valid_in,

    output reg  signed [7:0]  data_out,
    output wire               valid_out
);

    reg        [32:0] magnitude;
    reg        [33:0] rounded_magnitude;
    reg        [32:0] scaled_magnitude;
    reg signed [33:0] scaled_value;

    assign valid_out = valid_in;

    always @(*) begin
        // Default values
        magnitude        = 33'd0;
        rounded_magnitude = 34'd0;
        scaled_magnitude = 33'd0;
        scaled_value     = 34'sd0;
        data_out         = 8'sd0;

        if (!quant_enable) begin
            // Bypass: retain the lowest 8 bits.
            data_out = data_in[7:0];
        end
        else begin
            // Convert signed input to unsigned magnitude.
            if (data_in[31])
                magnitude = -$signed({data_in[31], data_in});
            else
                magnitude = {1'b0, data_in};

            // Add half an LSB before shifting for rounding.
            if (quant_shift == 0)
                rounded_magnitude = {1'b0, magnitude};
            else
                rounded_magnitude =
                    {1'b0, magnitude} +
                    (34'd1 << (quant_shift - 1'b1));

            // Scale the magnitude.
            scaled_magnitude =
                rounded_magnitude >> quant_shift;

            // Restore the original sign.
            if (data_in[31])
                scaled_value = -$signed({1'b0, scaled_magnitude});
            else
                scaled_value = $signed({1'b0, scaled_magnitude});

            // Saturate to signed INT8.
            if (scaled_value > 34'sd127)
                data_out = 8'sd127;
            else if (scaled_value < -34'sd128)
                data_out = -8'sd128;
            else
                data_out = scaled_value[7:0];
        end
    end

endmodule

module activation_unit (
    input  wire signed [7:0] data_in,
    input  wire        [1:0] activation_mode,
    input  wire               valid_in,

    output reg  signed [7:0] data_out,
    output wire               valid_out
);

    // Activation modes
    localparam ACT_LINEAR = 2'b00;
    localparam ACT_RELU   = 2'b01;
    localparam ACT_RELU6  = 2'b10;

    assign valid_out = valid_in;

    always @(*) begin
        data_out = data_in;

        case (activation_mode)

            // Linear / bypass
            ACT_LINEAR: begin
                data_out = data_in;
            end

            // ReLU: max(0, x)
            ACT_RELU: begin
                if (data_in < 0)
                    data_out = 8'sd0;
                else
                    data_out = data_in;
            end

            // ReLU6: min(6, max(0, x))
            ACT_RELU6: begin
                if (data_in < 0)
                    data_out = 8'sd0;
                else if (data_in > 8'sd6)
                    data_out = 8'sd6;
                else
                    data_out = data_in;
            end

            // Reserved mode: bypass
            default: begin
                data_out = data_in;
            end

        endcase
    end

endmodule

`timescale 1ns / 1ps

module tb_systolic_ai_accelerator_core;

    reg clk;
    reg rst_n;

    reg start;
    reg [7:0] activation_base_addr;
    reg [7:0] weight_base_addr;
    reg [3:0] result_addr;
    reg accumulate_enable;

    wire busy;
    wire done;

    reg activation_we;
    reg [7:0] activation_waddr;
    reg signed [7:0] activation_wdata;

    reg weight_we;
    reg [7:0] weight_waddr;
    reg signed [7:0] weight_wdata;

    reg [3:0] acc_read_addr;
    reg [3:0] acc_read_pe;
    reg acc_read_valid;

    reg acc_clear_entry;
    reg [3:0] acc_clear_addr;

    reg [4:0] quant_shift;
    reg quant_enable;
    reg [1:0] activation_mode;

    wire signed [7:0] output_data;
    wire output_valid;

    integer i;
    integer timeout;
    integer errors;

    integer expected [0:15];

    // DUT
    systolic_ai_accelerator_core DUT (
        .clk(clk),
        .rst_n(rst_n),

        .start(start),

        .activation_base_addr(activation_base_addr),
        .weight_base_addr(weight_base_addr),

        .result_addr(result_addr),
        .accumulate_enable(accumulate_enable),

        .busy(busy),
        .done(done),

        .activation_we(activation_we),
        .activation_waddr(activation_waddr),
        .activation_wdata(activation_wdata),

        .weight_we(weight_we),
        .weight_waddr(weight_waddr),
        .weight_wdata(weight_wdata),

        .acc_read_addr(acc_read_addr),
        .acc_read_pe(acc_read_pe),
        .acc_read_valid(acc_read_valid),

        .acc_clear_entry(acc_clear_entry),
        .acc_clear_addr(acc_clear_addr),

        .quant_shift(quant_shift),
        .quant_enable(quant_enable),
        .activation_mode(activation_mode),

        .output_data(output_data),
        .output_valid(output_valid)
    );

    // Clock: 10 ns period
    always #5 clk = ~clk;

    // Write activation scratchpad
    task write_activation;
        input integer addr;
        input integer data;
        begin
            @(negedge clk);
            activation_we = 1'b1;
            activation_waddr = addr;
            activation_wdata = data;

            @(negedge clk);
            activation_we = 1'b0;
        end
    endtask

    // Write weight scratchpad
    task write_weight;
        input integer addr;
        input integer data;
        begin
            @(negedge clk);
            weight_we = 1'b1;
            weight_waddr = addr;
            weight_wdata = data;

            @(negedge clk);
            weight_we = 1'b0;
        end
    endtask

             always @(posedge clk) begin
    if (rst_n) begin
        $display(
            "TIME=%0t START=%b BUSY=%b DONE=%b STATE=%0d",
            $time,
            start,
            busy,
            done,
            DUT.array_controller.state
        );
    end
end

    initial begin

        // Waveform generation
        $dumpfile("systolic_accelerator.vcd");
        $dumpvars(0, tb_systolic_ai_accelerator_core);


        // Initialize
        clk = 0;
        rst_n = 0;

        start = 0;

        activation_base_addr = 0;
        weight_base_addr = 0;
        result_addr = 0;

        accumulate_enable = 0;

        activation_we = 0;
        activation_waddr = 0;
        activation_wdata = 0;

        weight_we = 0;
        weight_waddr = 0;
        weight_wdata = 0;

        acc_read_addr = 0;
        acc_read_pe = 0;
        acc_read_valid = 0;

        acc_clear_entry = 0;
        acc_clear_addr = 0;

        quant_shift = 0;
        quant_enable = 0;
        activation_mode = 2'b00;

        errors = 0;
        timeout = 0;

        // Expected matrix:
        // 1   4   9   16
        // 5   12  21  32
        // 9   20  33  48
        // 13  28  45  64

        expected[0]  = 1;
        expected[1]  = 4;
        expected[2]  = 9;
        expected[3]  = 16;

        expected[4]  = 5;
        expected[5]  = 12;
        expected[6]  = 21;
        expected[7]  = 32;

        expected[8]  = 9;
        expected[9]  = 20;
        expected[10] = 33;
        expected[11] = 48;

        expected[12] = 13;
        expected[13] = 28;
        expected[14] = 45;
        expected[15] = 64;

        // Reset
        repeat(5) @(negedge clk);
        rst_n = 1'b1;

        repeat(2) @(negedge clk);

        // ---------------------------------
        // LOAD MATRIX A
        // ---------------------------------

        $display("--------------------------------");
        $display("Loading activation matrix A");
        $display("--------------------------------");

        // A =
        //  1  2  3  4
        //  5  6  7  8
        //  9 10 11 12
        // 13 14 15 16

        write_activation(0, 1);
        write_activation(1, 2);
        write_activation(2, 3);
        write_activation(3, 4);

        write_activation(4, 5);
        write_activation(5, 6);
        write_activation(6, 7);
        write_activation(7, 8);

        write_activation(8, 9);
        write_activation(9, 10);
        write_activation(10, 11);
        write_activation(11, 12);

        write_activation(12, 13);
        write_activation(13, 14);
        write_activation(14, 15);
        write_activation(15, 16);

        // ---------------------------------
        // LOAD MATRIX B
        // ---------------------------------

        $display("--------------------------------");
        $display("Loading weight matrix B");
        $display("--------------------------------");

        // B =
        // 1 0 0 0
        // 0 2 0 0
        // 0 0 3 0
        // 0 0 0 4

        write_weight(0, 1);
        write_weight(1, 0);
        write_weight(2, 0);
        write_weight(3, 0);

        write_weight(4, 0);
        write_weight(5, 2);
        write_weight(6, 0);
        write_weight(7, 0);

        write_weight(8, 0);
        write_weight(9, 0);
        write_weight(10, 3);
        write_weight(11, 0);

        write_weight(12, 0);
        write_weight(13, 0);
        write_weight(14, 0);
        write_weight(15, 4);

        // ---------------------------------
        // START COMPUTATION
        // ---------------------------------

        $display("--------------------------------");
        $display("Starting accelerator");
        $display("--------------------------------");
        @(negedge clk);
        start = 1'b1;

        $display("START ASSERTED at time %0t", $time);

        @(posedge clk);
        #1;
        $display("After start: busy=%b done=%b state=%0d",
                busy, done, DUT.array_controller.state);

        @(negedge clk);
        start = 1'b0;

        $display("START DEASSERTED at time %0t", $time);

        // Wait for completion

        timeout = 0;

        while ((done !== 1'b1) && (timeout < 200)) begin
            @(posedge clk);
            #1;  // Allow nonblocking assignments to update
            timeout = timeout + 1;
        end

        if (done !== 1'b1) begin
            $display("ERROR: Accelerator timeout!");
            $display("busy = %b, done = %b", busy, done);
            $finish;
        end
        else begin
            $display("--------------------------------");
            $display("Accelerator computation completed");
            $display("Completion detected at time %0t", $time);
            $display("--------------------------------");
        end
        $display("--------------------------------");
        $display("Accelerator computation completed");
        $display("--------------------------------");

        // ---------------------------------
        // READ AND VERIFY RESULTS
        // ---------------------------------

        $display("");
        $display("Expected and actual matrix results:");
        $display("");

        acc_read_addr = result_addr;
        acc_read_valid = 1'b1;

        for (i = 0; i < 16; i = i + 1) begin

            @(negedge clk);

            acc_read_pe = i;

            // Allow combinational read/output logic to settle
            #1;

            if (output_valid !== 1'b1) begin
                $display("ERROR: Output invalid at PE %0d", i);
                errors = errors + 1;
            end
            else if ($signed(output_data) !== expected[i]) begin
                $display(
                    "FAIL PE[%0d][%0d]: Expected %0d, Got %0d",
                    i/4, i%4,
                    expected[i],
                    $signed(output_data)
                );
                errors = errors + 1;
            end
            else begin
                $display(
                    "PASS PE[%0d][%0d]: Result = %0d",
                    i/4, i%4,
                    $signed(output_data)
                );
            end

        end

        acc_read_valid = 1'b0;

        // ---------------------------------
        // FINAL STATUS
        // ---------------------------------

        $display("");
        $display("--------------------------------");

        if (errors == 0) begin
            $display("TEST PASSED!");
            $display("All 16 matrix results are correct.");
        end
        else begin
            $display("TEST FAILED!");
            $display("Number of errors = %0d", errors);
        end

        $display("--------------------------------");

        #20;
        $finish;

     end
// initial begin

//     $dumpfile("tb_systolic_ai_accelerator_core.vcd");
//     $dumpvars(0,tb_systolic_ai_accelerator_core);

// end

endmodule
