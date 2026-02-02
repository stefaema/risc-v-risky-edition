// -----------------------------------------------------------------------------
// Module: mux2
// Description: 2-input parameterizable multiplexer.
// -----------------------------------------------------------------------------

module mux2 #(
    parameter int WIDTH = 32
)(
    input  logic [WIDTH-1:0] d0_i, // Selected when sel_i = 0
    input  logic [WIDTH-1:0] d1_i, // Selected when sel_i = 1
    input  logic             sel_i,
    output logic [WIDTH-1:0] data_o
);

    assign data_o = (sel_i) ? d1_i : d0_i;

endmodule
