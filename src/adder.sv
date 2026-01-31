// -----------------------------------------------------------------------------
// Module: adder
// Description: Combinational logic to calculate a+b = sum.
// -----------------------------------------------------------------------------

module adder (
    input  logic [31:0] adder_op1_i,
    input  logic [31:0] adder_op2_i,
    output logic [31:0] sum_o
);

    always_comb begin
        sum_o = adder_op1_i + adder_op2_i;
    end

endmodule
