// -----------------------------------------------------------------------------
// Module: mux4
// Description: 4-input parameterizable multiplexer.
// -----------------------------------------------------------------------------

module mux4 #(
    parameter int WIDTH = 32
)(
    input  logic [WIDTH-1:0] d0_i, // Selected when sel_i = 00
    input  logic [WIDTH-1:0] d1_i, // Selected when sel_i = 01
    input  logic [WIDTH-1:0] d2_i, // Selected when sel_i = 10
    input  logic [1:0]       sel_i,
    output logic [WIDTH-1:0] data_o
);

    always_comb begin
        case (sel_i)
            2'b00:   data_o = d0_i;
            2'b01:   data_o = d1_i;
            2'b10:   data_o = d2_i;
            default: data_o = {WIDTH{1'b0}}; // Safety default
        endcase
    end

endmodule
