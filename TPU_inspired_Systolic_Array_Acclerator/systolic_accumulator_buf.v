
`timescale 1ns / 1ps

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

module tb_accumulator_buffer;

parameter DATA_WIDTH = 32;
    parameter NUM_PE = 16;
    parameter DEPTH = 16;
    parameter ADDR_WIDTH = 4;
    parameter PE_ADDR_WIDTH = 4;

reg clk;
    reg rst_n;

    reg [NUM_PE*DATA_WIDTH-1:0] pe_results;

reg write_enable;
    reg accumulate_enable;
    reg [ADDR_WIDTH-1:0] write_addr;

reg clear_entry;
    reg [ADDR_WIDTH-1:0] clear_addr;

reg [ADDR_WIDTH-1:0] read_addr;
    reg [PE_ADDR_WIDTH-1:0] read_pe;

    wire signed [DATA_WIDTH-1:0] read_data;

integer i;
    integer errors;

accumulator_buffer #(
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_PE(NUM_PE),
        .DEPTH(DEPTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .PE_ADDR_WIDTH(PE_ADDR_WIDTH)
    ) DUT (
        .clk(clk),
        .rst_n(rst_n),

        .pe_results(pe_results),

.write_enable(write_enable),
        .accumulate_enable(accumulate_enable),
        .write_addr(write_addr),

.clear_entry(clear_entry),
        .clear_addr(clear_addr),

.read_addr(read_addr),
        .read_pe(read_pe),
        .read_data(read_data)
    );

// Clock generation
    initial clk = 0;
    always #5 clk = ~clk;

// Write all PE lanes simultaneously
    task write_results;
        input [ADDR_WIDTH-1:0] addr;
        input accumulate;
        begin
            @(negedge clk);

write_enable = 1;
            accumulate_enable = accumulate;
            write_addr = addr;

@(posedge clk);
            #1;

@(negedge clk);
            write_enable = 0;
        end
    endtask

// Read and check one PE lane
    task check_result;
        input [ADDR_WIDTH-1:0] addr;
        input [PE_ADDR_WIDTH-1:0] pe;
        input signed [31:0] expected;

begin
            read_addr = addr;
            read_pe = pe;

            #1;

if (read_data === expected) begin
                $display(
                    "PASS: Address=%0d PE=%0d Result=%0d",
                    addr, pe, $signed(read_data)
                );
            end
            else begin
                $display(
                    "FAIL: Address=%0d PE=%0d Expected=%0d Actual=%0d",
                    addr, pe, expected, $signed(read_data)
                );

errors = errors + 1;
            end
        end
    endtask

// Clear one complete entry
    task clear_buffer_entry;
        input [ADDR_WIDTH-1:0] addr;
        begin
            @(negedge clk);

clear_entry = 1;
            clear_addr = addr;

@(posedge clk);
            #1;

@(negedge clk);
            clear_entry = 0;
        end
    endtask

    initial begin

        rst_n = 0;

        pe_results = 0;

write_enable = 0;
        accumulate_enable = 0;
        write_addr = 0;

clear_entry = 0;
        clear_addr = 0;

read_addr = 0;
        read_pe = 0;

        errors = 0;

// ---------------------------------
        // TEST 1: Reset
        // ---------------------------------

        repeat (2) @(posedge clk);

@(negedge clk);
        rst_n = 1;

        $display("\nTEST 1: Reset completed");

// ---------------------------------
        // TEST 2: Parallel write
        // ---------------------------------

        $display("\nTEST 2: Parallel PE write");

        for (i = 0; i <NUM_PE; i = i + 1) begin
            pe_results[i*DATA_WIDTH +: DATA_WIDTH] = i + 1;
        end

        write_results(4'd0, 1'b0);

        for (i = 0; i <NUM_PE; i = i + 1) begin
            check_result(4'd0, i, i + 1);
        end

// ---------------------------------
        // TEST 3: Accumulate
        // ---------------------------------

        $display("\nTEST 3: Accumulate PE results");

        for (i = 0; i <NUM_PE; i = i + 1) begin
            pe_results[i*DATA_WIDTH +: DATA_WIDTH] = 10;
        end

        write_results(4'd0, 1'b1);

        for (i = 0; i <NUM_PE; i = i + 1) begin
            check_result(4'd0, i, (i + 1) + 10);
        end

// ---------------------------------
        // TEST 4: Overwrite
        // ---------------------------------

        $display("\nTEST 4: Overwrite existing entry");

        for (i = 0; i <NUM_PE; i = i + 1) begin
            pe_results[i*DATA_WIDTH +: DATA_WIDTH] = 100;
        end

        write_results(4'd0, 1'b0);

check_result(4'd0, 0, 100);
        check_result(4'd0, 7, 100);
        check_result(4'd0, 15, 100);

// ---------------------------------
        // TEST 5: Address independence
        // ---------------------------------

        $display("\nTEST 5: Address independence");

        for (i = 0; i <NUM_PE; i = i + 1) begin
            pe_results[i*DATA_WIDTH +: DATA_WIDTH] = 200;
        end

        write_results(4'd1, 1'b0);

check_result(4'd0, 0, 100);
        check_result(4'd1, 0, 200);

// ---------------------------------
        // TEST 6: Clear one entry
        // ---------------------------------

        $display("\nTEST 6: Clear one entry");

        clear_buffer_entry(4'd0);

check_result(4'd0, 0, 0);
        check_result(4'd0, 7, 0);
        check_result(4'd0, 15, 0);

// Address 1 must remain unchanged
        check_result(4'd1, 0, 200);

// ---------------------------------
        // TEST 7: Full reset
        // ---------------------------------

        $display("\nTEST 7: Full reset");

@(negedge clk);
        rst_n = 0;

@(posedge clk);
        #1;

        rst_n = 1;

check_result(4'd1, 0, 0);
        check_result(4'd1, 7, 0);
        check_result(4'd1, 15, 0);

// ---------------------------------
        // FINAL RESULT
        // ---------------------------------

if (errors == 0)
            $display("\nALL ACCUMULATOR BUFFER TESTS PASSED");
        else
            $display(
                "\nACCUMULATOR BUFFER TEST FAILED: %0d errors",
                errors
            );

        $finish;

    end

initial begin

    $dumpfile("tb_accumulator_buffer.vcd");
    $dumpvars(0,tb_accumulator_buffer);

end

endmodule
