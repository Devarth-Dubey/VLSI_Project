
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



`timescale 1ns/1ps

module tb_quantization_unit;

    reg signed [31:0] data_in;
    reg        [4:0]  quant_shift;
    reg               quant_enable;
    reg               valid_in;

    wire signed [7:0] data_out;
    wire              valid_out;

    integer errors;

    quantization_unit dut (
        .data_in(data_in),
        .quant_shift(quant_shift),
        .quant_enable(quant_enable),
        .valid_in(valid_in),
        .data_out(data_out),
        .valid_out(valid_out)
    );

    task check_result;
        input signed [31:0] test_input;
        input        [4:0]  test_shift;
        input               test_enable;
        input signed [7:0]  expected;
        begin
            data_in      = test_input;
            quant_shift  = test_shift;
            quant_enable = test_enable;
            valid_in     = 1'b1;

            #10;

            if (data_out !== expected || valid_out !== 1'b1) begin
                $display(
                    "FAIL: input=%0d shift=%0d enable=%b expected=%0d got=%0d valid=%b",
                    test_input, test_shift, test_enable,
                    expected, data_out, valid_out
                );
                errors = errors + 1;
            end
            else begin
                $display(
                    "PASS: input=%0d shift=%0d output=%0d",
                    test_input, test_shift, data_out
                );
            end
        end
    endtask

    initial begin
        errors = 0;

        // Positive scaling
        check_result(32'sd256,  5'd8, 1'b1, 8'sd1);
        check_result(32'sd512,  5'd8, 1'b1, 8'sd2);
        check_result(32'sd384,  5'd8, 1'b1, 8'sd2);

        // Negative scaling
        check_result(-32'sd256, 5'd8, 1'b1, -8'sd1);
        check_result(-32'sd384, 5'd8, 1'b1, -8'sd2);

        // Rounding around zero
        check_result(32'sd127,  5'd8, 1'b1, 8'sd0);
        check_result(32'sd128,  5'd8, 1'b1, 8'sd1);
        check_result(-32'sd127, 5'd8, 1'b1, 8'sd0);
        check_result(-32'sd128, 5'd8, 1'b1, -8'sd1);

        // Positive and negative saturation
        check_result(32'sd40000,  5'd0, 1'b1, 8'sd127);
        check_result(-32'sd40000, 5'd0, 1'b1, -8'sd128);

        // INT32 boundary values
        check_result(32'sh7FFFFFFF, 5'd0, 1'b1, 8'sd127);
        check_result(32'sh80000000, 5'd0, 1'b1, -8'sd128);

        // Bypass mode: lowest 8 bits
        check_result(32'sh123456AB, 5'd8, 1'b0, -8'sd85);

        // Valid signal propagation
        valid_in = 1'b0;
        #10;

        if (valid_out !== 1'b0) begin
            $display("FAIL: valid signal did not propagate");
            errors = errors + 1;
        end
        else begin
            $display("PASS: valid signal propagation");
        end

        if (errors == 0)
            $display("\nALL QUANTIZATION TESTS PASSED");
        else
            $display("\nTEST FAILED: %0d errors", errors);

        $finish;
    end

    initial begin

    $dumpfile("tb_quantization_unit.vcd");
    $dumpvars(0,tb_quantization_unit);

end

endmodule
