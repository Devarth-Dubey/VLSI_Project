
module dma_controller #(
    parameter ADDR_WIDTH = 8,
    parameter LEN_WIDTH  = 16,
    parameter DATA_WIDTH = 8
)(
    input wire clk,
    input wire rst_n,

    // DMA configuration
    input wire start,
    input wire direction,  // 0: external -> scratchpad
                            // 1: scratchpad -> external
    input wire [ADDR_WIDTH-1:0] ext_base_addr,
    input wire [ADDR_WIDTH-1:0] sp_base_addr,
    input wire [LEN_WIDTH-1:0] transfer_length,

    // External memory interface
    output reg ext_mem_req,
    output reg ext_mem_we,
    output reg [ADDR_WIDTH-1:0] ext_mem_addr,
    output reg [DATA_WIDTH-1:0] ext_mem_wdata,
    input wire [DATA_WIDTH-1:0] ext_mem_rdata,
    input wire ext_mem_ready,

    // Scratchpad interface
    output reg [ADDR_WIDTH-1:0] sp_addr,
    output reg sp_we,
    output reg [DATA_WIDTH-1:0] sp_wdata,
    input wire [DATA_WIDTH-1:0] sp_rdata,

    // Status
    output wire busy,
    output reg done
);

    localparam IDLE      = 3'd0;
    localparam EXT_READ  = 3'd1;
    localparam SP_WRITE  = 3'd2;
    localparam SP_READ   = 3'd3;
    localparam EXT_WRITE = 3'd4;
    localparam DONE      = 3'd5;

    reg [2:0] state;

    reg direction_reg;

    reg [ADDR_WIDTH-1:0] ext_addr_reg;
    reg [ADDR_WIDTH-1:0] sp_addr_reg;

    reg [LEN_WIDTH-1:0] length_reg;
    reg [LEN_WIDTH-1:0] count;

    reg [DATA_WIDTH-1:0] data_buffer;

    assign busy = (state != IDLE) && (state != DONE);

    // ------------------------------------------------
    // Combinational outputs
    // ------------------------------------------------

    always @(*) begin

        ext_mem_req   = 1'b0;
        ext_mem_we    = 1'b0;
        ext_mem_addr  = ext_addr_reg;
        ext_mem_wdata = data_buffer;

        sp_addr  = sp_addr_reg;
        sp_we    = 1'b0;
        sp_wdata = data_buffer;

        case (state)

            // Read external memory
            EXT_READ: begin
                ext_mem_req  = 1'b1;
                ext_mem_we   = 1'b0;
                ext_mem_addr = ext_addr_reg;
            end

            // Write received data into scratchpad
            SP_WRITE: begin
                sp_we    = 1'b1;
                sp_addr  = sp_addr_reg;
                sp_wdata = data_buffer;
            end

            // Read scratchpad before external write
            SP_READ: begin
                sp_addr = sp_addr_reg;
            end

            // Write scratchpad data to external memory
            EXT_WRITE: begin
                ext_mem_req   = 1'b1;
                ext_mem_we    = 1'b1;
                ext_mem_addr  = ext_addr_reg;
                ext_mem_wdata = data_buffer;
            end

            default: begin
            end

        endcase
    end

    // ------------------------------------------------
    // Sequential FSM
    // ------------------------------------------------

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin
            state          <= IDLE;
            direction_reg  <= 1'b0;

            ext_addr_reg   <= 0;
            sp_addr_reg    <= 0;

            length_reg     <= 0;
            count          <= 0;

            data_buffer    <= 0;
            done           <= 1'b0;
        end

        else begin

            done <= 1'b0;

            case (state)

                // ------------------------------------
                // IDLE
                // ------------------------------------
                IDLE: begin

                    if (start && transfer_length != 0) begin

                        direction_reg <= direction;

                        ext_addr_reg <= ext_base_addr;
                        sp_addr_reg  <= sp_base_addr;

                        length_reg <= transfer_length;
                        count      <= 0;

                        if (direction == 1'b0)
                            state <= EXT_READ;
                        else
                            state <= SP_READ;

                    end

                    else if (start && transfer_length == 0) begin
                        state <= DONE;
                    end

                end

                // ------------------------------------
                // External memory read
                // ------------------------------------
                EXT_READ: begin

                    if (ext_mem_ready) begin

                        data_buffer <= ext_mem_rdata;
                        state <= SP_WRITE;

                    end

                end

                // ------------------------------------
                // Scratchpad write
                // ------------------------------------
                SP_WRITE: begin

                    // sp_we is asserted during this state.
                    // Scratchpad samples it at this clock edge.

                    if (count == length_reg - 1'b1) begin
                        state <= DONE;
                    end
                    else begin

                        count <= count + 1'b1;

                        ext_addr_reg <= ext_addr_reg + 1'b1;
                        sp_addr_reg  <= sp_addr_reg + 1'b1;

                        state <= EXT_READ;

                    end

                end

                // ------------------------------------
                // Scratchpad read
                // ------------------------------------
                SP_READ: begin

                    data_buffer <= sp_rdata;

                    state <= EXT_WRITE;

                end

                // ------------------------------------
                // External memory write
                // ------------------------------------
                EXT_WRITE: begin

                    if (ext_mem_ready) begin

                        if (count == length_reg - 1'b1) begin
                            state <= DONE;
                        end
                        else begin

                            count <= count + 1'b1;

                            ext_addr_reg <= ext_addr_reg + 1'b1;
                            sp_addr_reg  <= sp_addr_reg + 1'b1;

                            state <= SP_READ;

                        end

                    end

                end

                // ------------------------------------
                // DONE
                // ------------------------------------
                DONE: begin

                    done <= 1'b1;
                    state <= IDLE;

                end

                default: begin
                    state <= IDLE;
                end

            endcase

        end

    end

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




`timescale 1ns/1ps

module tb_dma_controller;

    reg clk;
    reg rst_n;

    reg start;
    reg direction;

    reg [7:0] ext_base_addr;
    reg [7:0] sp_base_addr;
    reg [15:0] transfer_length;

    wire ext_mem_req;
    wire ext_mem_we;
    wire [7:0] ext_mem_addr;
    wire [7:0] ext_mem_wdata;
    reg  [7:0] ext_mem_rdata;
    reg ext_mem_ready;

    wire [7:0] sp_addr;
    wire sp_we;
    wire [7:0] sp_wdata;
    wire [7:0] sp_rdata;

    wire busy;
    wire done;

    reg [7:0] external_memory [0:255];

    integer i;
    integer errors;

    // ----------------------------------------
    // DUT
    // ----------------------------------------

    dma_controller dut (
        .clk(clk),
        .rst_n(rst_n),

        .start(start),
        .direction(direction),

        .ext_base_addr(ext_base_addr),
        .sp_base_addr(sp_base_addr),
        .transfer_length(transfer_length),

        .ext_mem_req(ext_mem_req),
        .ext_mem_we(ext_mem_we),
        .ext_mem_addr(ext_mem_addr),
        .ext_mem_wdata(ext_mem_wdata),
        .ext_mem_rdata(ext_mem_rdata),
        .ext_mem_ready(ext_mem_ready),

        .sp_addr(sp_addr),
        .sp_we(sp_we),
        .sp_wdata(sp_wdata),
        .sp_rdata(sp_rdata),

        .busy(busy),
        .done(done)
    );

    // ----------------------------------------
    // Scratchpad
    // ----------------------------------------

  scratchpad_ram #(
    .DATA_WIDTH(8),
    .ADDR_WIDTH(8),
    .DEPTH(256)
) scratchpad (
    .clk(clk),
    .rst_n(rst_n),

    // Write port
    .write_enable(sp_we),
    .write_addr(sp_addr),
    .write_data(sp_wdata),

    // Read port
    .read_addr(sp_addr),
    .read_data(sp_rdata)
);

    // ----------------------------------------
    // Clock
    // ----------------------------------------

    always #5 clk = ~clk;

    // ----------------------------------------
    // External memory model
    // One-cycle response
    // ----------------------------------------

    always @(posedge clk) begin

        ext_mem_ready <= 1'b0;

        if (rst_n && ext_mem_req) begin

            ext_mem_ready <= 1'b1;

            if (ext_mem_we) begin
                external_memory[ext_mem_addr]
                    <= ext_mem_wdata;
            end
            else begin
                ext_mem_rdata
                    <= external_memory[ext_mem_addr];
            end

        end

    end

    // ----------------------------------------
    // Wait for DMA completion
    // ----------------------------------------

    task wait_done;
        begin
            wait(done == 1'b1);
            @(posedge clk);
            #1;
        end
    endtask

    // ----------------------------------------
    // Main test
    // ----------------------------------------

    initial begin

        clk = 0;
        rst_n = 0;

        start = 0;
        direction = 0;

        ext_base_addr = 0;
        sp_base_addr = 0;
        transfer_length = 0;

        ext_mem_rdata = 0;
        ext_mem_ready = 0;

        errors = 0;

        // Initialize external memory
        for (i = 0; i < 256; i = i + 1)
            external_memory[i] = 0;

        // Test data
        external_memory[10] = 8'd11;
        external_memory[11] = 8'd22;
        external_memory[12] = 8'd33;
        external_memory[13] = 8'd44;

        // Reset
        repeat (3) @(posedge clk);
        rst_n = 1;

        repeat (2) @(posedge clk);

        // ====================================
        // TEST 1:
        // External memory -> scratchpad
        // ====================================

        $display("\nTEST 1: External memory to scratchpad");

        @(negedge clk);

        direction = 0;
        ext_base_addr = 8'd10;
        sp_base_addr = 8'd20;
        transfer_length = 16'd4;

        start = 1;

        @(negedge clk);
        start = 0;

        wait_done();

        if (scratchpad.memory[20] !== 8'd11 ||
            scratchpad.memory[21] !== 8'd22 ||
            scratchpad.memory[22] !== 8'd33 ||
            scratchpad.memory[23] !== 8'd44) begin

            $display("FAIL: External to scratchpad transfer");
            errors = errors + 1;

        end
        else begin
            $display("PASS: External to scratchpad transfer");
        end

        // ====================================
        // TEST 2:
        // Scratchpad -> external memory
        // ====================================

        $display("\nTEST 2: Scratchpad to external memory");

        @(negedge clk);

        direction = 1;
        ext_base_addr = 8'd40;
        sp_base_addr = 8'd20;
        transfer_length = 16'd4;

        start = 1;

        @(negedge clk);
        start = 0;

        wait_done();

        if (external_memory[40] !== 8'd11 ||
            external_memory[41] !== 8'd22 ||
            external_memory[42] !== 8'd33 ||
            external_memory[43] !== 8'd44) begin

            $display("FAIL: Scratchpad to external transfer");
            errors = errors + 1;

        end
        else begin
            $display("PASS: Scratchpad to external transfer");
        end

        // ====================================
        // TEST 3:
        // Zero-length transfer
        // ====================================

        $display("\nTEST 3: Zero-length transfer");

        @(negedge clk);

        direction = 0;
        transfer_length = 0;
        start = 1;

        @(negedge clk);
        start = 0;

        wait_done();

        $display("PASS: Zero-length transfer completed");

        // ====================================
        // RESULT
        // ====================================

        if (errors == 0)
            $display("\nALL DMA TESTS PASSED");
        else
            $display("\nDMA TEST FAILED: %0d errors", errors);

        $finish;

    end

    // Timeout
    initial begin
        #100000;
        $display("ERROR: Simulation timeout");
        $finish;
    end
initial begin

    $dumpfile("tb_dma_controller.vcd");
    $dumpvars(0,tb_dma_controller);

end
endmodule
