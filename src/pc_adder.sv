// -----------------------------------------------------------------------------
// Module: pc_adder
// Description: Combinational logic to calculate Next Sequential PC.
// -----------------------------------------------------------------------------

module pc_adder (
    input  logic [31:0] pc_in,
    output logic [31:0] pc_out
);

    always_comb begin
        pc_out = pc_in + 32'd4;
    end

endmodule
