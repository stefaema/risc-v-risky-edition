// -----------------------------------------------------------------------------
// Module: program_counter_reg
// Description: 32-bit Program Counter (PC) register.
//              - Updates on positive clock edge.
//              - Asynchronous Active-Low Reset (rst_n).
//              - Holds value if 'stall' is asserted.
// -----------------------------------------------------------------------------

module program_counter_reg #(
    parameter int PC_WIDTH = 32
)(
    input  logic        clk,
    input  logic        rst_n,     // Active Low Reset
    input  logic        stall_i,   // 1 = Freeze PC
    input  logic [31:0] pc_i,      // Next PC address
    output logic [31:0] pc_o       // Current PC address
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_o <= 32'd0;
        end else if (!stall_i) begin
            pc_o <= pc_i;
        end
        else begin
            pc_o <= pc_o; // Hold value when stalled
        end
    end

endmodule
