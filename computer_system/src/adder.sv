// -----------------------------------------------------------------------------
// Module: adder
// Description: Combinational logic to calculate a+b = sum.
// -----------------------------------------------------------------------------

module adder 
#(
    parameter int ADDER_WIDTH = 32
)(
    input  logic [ADDER_WIDTH-1:0] adder_op1_i,
    input  logic [ADDER_WIDTH-1:0] adder_op2_i,
    output logic [ADDER_WIDTH-1:0] sum_o
);

    always_comb begin
        sum_o = adder_op1_i + adder_op2_i;
    end

endmodule
