// -----------------------------------------------------------------------------
// Module: adder
// Description: Combinational logic to calculate a+b = sum or a-b = diff.
// -----------------------------------------------------------------------------

module adder 
#(
    parameter int ADDER_WIDTH = 32,
    parameter logic IS_SUBTRACTER = 1'b0  // 0=Add, 1=Subtract
)(
    input  logic [ADDER_WIDTH-1:0] adder_op1_i,
    input  logic [ADDER_WIDTH-1:0] adder_op2_i,
    output logic [ADDER_WIDTH-1:0] sum_o
);

    always_comb begin
        if (IS_SUBTRACTER)
            sum_o = adder_op1_i - adder_op2_i;
        else
            sum_o = adder_op1_i + adder_op2_i;
    end

endmodule
