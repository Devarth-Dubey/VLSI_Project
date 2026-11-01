
`timescale 1ns / 1ps

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

`timescale 1ns / 1ps


module tb_scratchpad_subsystem;

reg clk;
reg rst_n;

reg activation_we;
reg [7:0] activation_waddr;
reg [7:0] activation_wdata;
reg [7:0] activation_raddr;
wire signed [7:0] activation_rdata;

reg weight_we;
reg [7:0] weight_waddr;
reg [7:0] weight_wdata;
reg [7:0] weight_raddr;
wire signed [7:0] weight_rdata;

integer errors;

scratchpad_subsystem #(
.DATA_WIDTH(8),
.ADDR_WIDTH(8),
.DEPTH(256)
) DUT (
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

initial clk = 0;
always #5 clk = ~clk;

task check_results;
input signed [7:0] expected_activation;
input signed [7:0] expected_weight;
begin
#1;

if ((activation_rdata === expected_activation) &&
(weight_rdata === expected_weight)) begin

$display("PASS: Activation = %0d, Weight = %0d",
$signed(activation_rdata),
$signed(weight_rdata));
end
else begin
$display("FAIL: Activation expected %0d got %0d; Weight expected %0d got %0d",
expected_activation,
$signed(activation_rdata),
expected_weight,
$signed(weight_rdata));

errors = errors + 1;
end
end
endtask

initial begin
rst_n = 0;

activation_we = 0;
activation_waddr = 0;
activation_wdata = 0;
activation_raddr = 0;

weight_we = 0;
weight_waddr = 0;
weight_wdata = 0;
weight_raddr = 0;

errors = 0;

// Reset
repeat (2) @(posedge clk);
@(negedge clk);
rst_n = 1;

// Write activation and weight to the SAME address
@(negedge clk);
activation_we = 1;
activation_waddr = 8'd5;
activation_wdata = 8'd25;

weight_we = 1;
weight_waddr = 8'd5;
weight_wdata = 8'd10;

@(posedge clk);
#1;

// Stop writes
@(negedge clk);
activation_we = 0;
weight_we = 0;

// Read both memories
activation_raddr = 8'd5;
weight_raddr = 8'd5;

check_results(25, 10);

// Change only activation memory
@(negedge clk);
activation_we = 1;
activation_waddr = 8'd5;
activation_wdata = 8'd40;

@(posedge clk);
#1;

@(negedge clk);
activation_we = 0;

check_results(40, 10);

// Change only weight memory
@(negedge clk);
weight_we = 1;
weight_waddr = 8'd5;
weight_wdata = -8'sd7;

@(posedge clk);
#1;

@(negedge clk);
weight_we = 0;

check_results(40, -7);

if (errors == 0)
$display("\nALL SCRATCHPAD SUBSYSTEM TESTS PASSED");
else
$display("\nSCRATCHPAD SUBSYSTEM TEST FAILED: %0d errors", errors);

$finish;
end

initial begin

    $dumpfile("tb_scratchpad_subsystem.vcd");
    $dumpvars(0,tb_scratchpad_subsystem);

end


endmodule
