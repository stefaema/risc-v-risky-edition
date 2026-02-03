// -----------------------------------------------------------------------------
// Module: Halt Unit
// Description: Simply redirects CU "is_halt" signal to the freeze signal.
// -----------------------------------------------------------------------------
module halt_unit (
    input  logic is_halt_i,      // Input signal indicating a halt condition from the Control Unit
    output logic freeze_o         // Output freeze signal to IF/ID pipeline register and PC to freeze
);

    // Directly connect the halt signal to the freeze output
    assign freeze_o = is_halt_i;
endmodule