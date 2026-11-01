`timescale 1ns / 1ps

module matrix_operation_sequencer #(
    parameter COUNT_WIDTH = 8
)(
    input wire clk,
    input wire rst_n,

    // Operation control
    input wire start,

    // Matrix tile configuration
    input wire [COUNT_WIDTH-1:0] m_tiles,
    input wire [COUNT_WIDTH-1:0] n_tiles,
    input wire [COUNT_WIDTH-1:0] k_tiles,

    // Completion signals from accelerator modules
    input wire load_a_done,
    input wire load_b_done,
    input wire clear_done,
    input wire compute_done,
    input wire store_done,

    // Operation start pulses
    output reg load_a_start,
    output reg load_b_start,
    output reg clear_acc_start,
    output reg compute_start,
    output reg store_start,

    // Current tile indices
    output reg [COUNT_WIDTH-1:0] tile_m,
    output reg [COUNT_WIDTH-1:0] tile_n,
    output reg [COUNT_WIDTH-1:0] tile_k,

    // Status
    output wire busy,
    output reg done,
    output reg error
);

    // FSM states
    localparam IDLE       = 4'd0;
    localparam LOAD_A     = 4'd1;
    localparam WAIT_A     = 4'd2;
    localparam LOAD_B     = 4'd3;
    localparam WAIT_B     = 4'd4;
    localparam CLEAR_ACC  = 4'd5;
    localparam WAIT_CLEAR = 4'd6;
    localparam COMPUTE    = 4'd7;
    localparam WAIT_COMP  = 4'd8;
    localparam STORE      = 4'd9;
    localparam WAIT_STORE = 4'd10;

    reg [3:0] state;

    reg [COUNT_WIDTH-1:0] m_count;
    reg [COUNT_WIDTH-1:0] n_count;
    reg [COUNT_WIDTH-1:0] k_count;

    reg [COUNT_WIDTH-1:0] m_limit;
    reg [COUNT_WIDTH-1:0] n_limit;
    reg [COUNT_WIDTH-1:0] k_limit;

    assign busy = (state != IDLE);

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            state <= IDLE;

            m_count <= 0;
            n_count <= 0;
            k_count <= 0;

            m_limit <= 0;
            n_limit <= 0;
            k_limit <= 0;

            tile_m <= 0;
            tile_n <= 0;
            tile_k <= 0;

            load_a_start <= 0;
            load_b_start <= 0;
            clear_acc_start <= 0;
            compute_start <= 0;
            store_start <= 0;

            done <= 0;
            error <= 0;

        end else begin

            // Default: all operation signals are one-cycle pulses
            load_a_start <= 0;
            load_b_start <= 0;
            clear_acc_start <= 0;
            compute_start <= 0;
            store_start <= 0;

            done <= 0;
            error <= 0;

            case (state)

                // ---------------------------------
                // IDLE
                // ---------------------------------
                IDLE: begin

                    if (start) begin

                        if ((m_tiles == 0) ||
                            (n_tiles == 0) ||
                            (k_tiles == 0)) begin

                            error <= 1;
                            state <= IDLE;

                        end else begin

                            m_limit <= m_tiles;
                            n_limit <= n_tiles;
                            k_limit <= k_tiles;

                            m_count <= 0;
                            n_count <= 0;
                            k_count <= 0;

                            tile_m <= 0;
                            tile_n <= 0;
                            tile_k <= 0;

                            state <= LOAD_A;

                        end
                    end
                end

                // ---------------------------------
                // LOAD ACTIVATION TILE
                // ---------------------------------
                LOAD_A: begin

                    load_a_start <= 1;
                    state <= WAIT_A;

                end

                WAIT_A: begin

                    if (load_a_done)
                        state <= LOAD_B;

                end

                // ---------------------------------
                // LOAD WEIGHT TILE
                // ---------------------------------
                LOAD_B: begin

                    load_b_start <= 1;
                    state <= WAIT_B;

                end

                WAIT_B: begin

                    if (load_b_done) begin

                        // Clear accumulator only for first K tile
                        if (k_count == 0)
                            state <= CLEAR_ACC;
                        else
                            state <= COMPUTE;

                    end
                end

                // ---------------------------------
                // CLEAR ACCUMULATOR
                // ---------------------------------
                CLEAR_ACC: begin

                    clear_acc_start <= 1;
                    state <= WAIT_CLEAR;

                end

                WAIT_CLEAR: begin

                    if (clear_done)
                        state <= COMPUTE;

                end

                // ---------------------------------
                // START MATRIX COMPUTATION
                // ---------------------------------
                COMPUTE: begin

                    compute_start <= 1;
                    state <= WAIT_COMP;

                end

                WAIT_COMP: begin

                    if (compute_done) begin

                        // More K tiles remain
                        if (k_count + 1'b1 < k_limit) begin

                            k_count <= k_count + 1'b1;
                            tile_k <= k_count + 1'b1;

                            state <= LOAD_A;

                        end else begin

                            // All K tiles processed
                            state <= STORE;

                        end
                    end
                end

                // ---------------------------------
                // STORE OUTPUT TILE
                // ---------------------------------
                STORE: begin

                    store_start <= 1;
                    state <= WAIT_STORE;

                end

                WAIT_STORE: begin

                    if (store_done) begin

                        // Move to next N tile
                        if (n_count + 1'b1 < n_limit) begin

                            n_count <= n_count + 1'b1;
                            tile_n <= n_count + 1'b1;

                            k_count <= 0;
                            tile_k <= 0;

                            state <= LOAD_A;

                        end

                        // Move to next M tile
                        else if (m_count + 1'b1 < m_limit) begin

                            m_count <= m_count + 1'b1;
                            tile_m <= m_count + 1'b1;

                            n_count <= 0;
                            tile_n <= 0;

                            k_count <= 0;
                            tile_k <= 0;

                            state <= LOAD_A;

                        end

                        // Entire operation completed
                        else begin

                            done <= 1;
                            state <= IDLE;

                        end

                    end
                end

                default: begin
                    state <= IDLE;
                end

            endcase
        end
    end

endmodule


module tb_matrix_operation_sequencer;

    reg clk;
    reg rst_n;
    reg start;

    reg [7:0] m_tiles;
    reg [7:0] n_tiles;
    reg [7:0] k_tiles;

    reg load_a_done;
    reg load_b_done;
    reg clear_done;
    reg compute_done;
    reg store_done;

    wire load_a_start;
    wire load_b_start;
    wire clear_acc_start;
    wire compute_start;
    wire store_start;

    wire [7:0] tile_m;
    wire [7:0] tile_n;
    wire [7:0] tile_k;

    wire busy;
    wire done;
    wire error;

    integer load_a_count;
    integer load_b_count;
    integer clear_count;
    integer compute_count;
    integer store_count;

    // DUT
    matrix_operation_sequencer dut (

        .clk(clk),
        .rst_n(rst_n),

        .start(start),

        .m_tiles(m_tiles),
        .n_tiles(n_tiles),
        .k_tiles(k_tiles),

        .load_a_done(load_a_done),
        .load_b_done(load_b_done),
        .clear_done(clear_done),
        .compute_done(compute_done),
        .store_done(store_done),

        .load_a_start(load_a_start),
        .load_b_start(load_b_start),
        .clear_acc_start(clear_acc_start),
        .compute_start(compute_start),
        .store_start(store_start),

        .tile_m(tile_m),
        .tile_n(tile_n),
        .tile_k(tile_k),

        .busy(busy),
        .done(done),
        .error(error)
    );

    // Clock: 10 ns period
    always #5 clk = ~clk;

    // Simulate completion of each operation
    always @(posedge clk) begin

        if (!rst_n) begin

            load_a_done <= 0;
            load_b_done <= 0;
            clear_done <= 0;
            compute_done <= 0;
            store_done <= 0;

            load_a_count <= 0;
            load_b_count <= 0;
            clear_count <= 0;
            compute_count <= 0;
            store_count <= 0;

        end else begin

            load_a_done <= load_a_start;
            load_b_done <= load_b_start;
            clear_done <= clear_acc_start;
            compute_done <= compute_start;
            store_done <= store_start;

            if (load_a_start)
                load_a_count <= load_a_count + 1;

            if (load_b_start)
                load_b_count <= load_b_count + 1;

            if (clear_acc_start)
                clear_count <= clear_count + 1;

            if (compute_start)
                compute_count <= compute_count + 1;

            if (store_start)
                store_count <= store_count + 1;

        end
    end

    // Main test
    initial begin

        clk = 0;
        rst_n = 0;
        start = 0;

        m_tiles = 2;
        n_tiles = 2;
        k_tiles = 3;

        load_a_done = 0;
        load_b_done = 0;
        clear_done = 0;
        compute_done = 0;
        store_done = 0;

        #20;
        rst_n = 1;

        #10;
        start = 1;

        #10;
        start = 0;

        wait(done == 1);

        #10;

        $display("--------------------------------");
        $display("MATRIX OPERATION SEQUENCER TEST");
        $display("--------------------------------");

        $display("Activation loads : %0d", load_a_count);
        $display("Weight loads     : %0d", load_b_count);
        $display("Accumulator clears: %0d", clear_count);
        $display("Compute operations: %0d", compute_count);
        $display("Output stores     : %0d", store_count);

        if (load_a_count == 12 &&
            load_b_count == 12 &&
            clear_count == 4 &&
            compute_count == 12 &&
            store_count == 4 &&
            error == 0) begin

            $display("TEST PASSED");

        end else begin

            $display("TEST FAILED");

        end

        $finish;

    end
    initial begin

    $dumpfile("tb_matrix_operation_sequencer.vcd");
    $dumpvars(0,tb_matrix_operation_sequencer);

end

endmodule
