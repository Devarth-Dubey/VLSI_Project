
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


`timescale 1ns/1ps

module tb_activation_unit;

    reg signed [7:0] data_in;
    reg        [1:0] activation_mode;
    reg              valid_in;

    wire signed [7:0] data_out;
    wire              valid_out;

    integer errors;

    activation_unit dut (
        .data_in(data_in),
        .activation_mode(activation_mode),
        .valid_in(valid_in),
        .data_out(data_out),
        .valid_out(valid_out)
    );

    task check_result;
        input signed [7:0] test_input;
        input        [1:0] test_mode;
        input signed [7:0] expected;
        begin
            data_in = test_input;
            activation_mode = test_mode;
            valid_in = 1'b1;

            #10;

            if (data_out !== expected || valid_out !== 1'b1) begin
                $display(
                    "FAIL: input=%0d mode=%b expected=%0d got=%0d",
                    test_input, test_mode, expected, data_out
                );
                errors = errors + 1;
            end
            else begin
                $display(
                    "PASS: input=%0d mode=%b output=%0d",
                    test_input, test_mode, data_out
                );
            end
        end
    endtask

    initial begin
        errors = 0;

        // --------------------------------
        // LINEAR / BYPASS
        // --------------------------------
        check_result( 8'sd10,  2'b00,  8'sd10);
        check_result(-8'sd10,  2'b00, -8'sd10);
        check_result( 8'sd0,   2'b00,  8'sd0);

        // --------------------------------
        // RELU
        // --------------------------------
        check_result( 8'sd10,  2'b01,  8'sd10);
        check_result(-8'sd10,  2'b01,  8'sd0);
        check_result( 8'sd0,   2'b01,  8'sd0);
        check_result(-8'sd128, 2'b01,  8'sd0);
        check_result( 8'sd127, 2'b01,  8'sd127);

        // --------------------------------
        // RELU6
        // --------------------------------
        check_result( 8'sd3,   2'b10,  8'sd3);
        check_result( 8'sd6,   2'b10,  8'sd6);
        check_result( 8'sd10,  2'b10,  8'sd6);
        check_result(-8'sd10,  2'b10,  8'sd0);
        check_result( 8'sd0,   2'b10,  8'sd0);

        // --------------------------------
        // RESERVED MODE: BYPASS
        // --------------------------------
        check_result(-8'sd5, 2'b11, -8'sd5);

        // --------------------------------
        // VALID SIGNAL
        // --------------------------------
        valid_in = 1'b0;
        #10;

        if (valid_out !== 1'b0) begin
            $display("FAIL: valid propagation");
            errors = errors + 1;
        end
        else begin
            $display("PASS: valid propagation");
        end

        if (errors == 0)
            $display("\nALL ACTIVATION TESTS PASSED");
        else
            $display("\nTEST FAILED: %0d errors", errors);

        $finish;
    end
initial begin

    $dumpfile("tb_activation_unit.vcd");
    $dumpvars(0,tb_activation_unit);

end


endmodule
