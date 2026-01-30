// -----------------------------------------------------------------------------
// Module: program_counter
// Description: 32-bit Program Counter (PC) register.
//              - Updates on positive clock edge.
//              - Asynchronous Active-Low Reset (rst_n).
//              - Holds value if 'stall' is asserted.
// -----------------------------------------------------------------------------

module program_counter (
    input  logic        clk,
    input  logic        rst_n,   // Active Low Reset
    input  logic        stall,   // 1 = Freeze PC
    input  logic [31:0] pc_in,   // Next PC address
    output logic [31:0] pc_out   // Current PC address
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_out <= 32'd0;
        end else if (!stall) begin
            pc_out <= pc_in;
        end
        else begin
            pc_out <= pc_out; // Hold value when stalled
        end
    end

endmodule
