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
    input  logic        rst_n,          // Active Low Reset
    input  logic        write_en_i,     // 0 = Keep current PC (Stall)
    input  logic        soft_reset_i,   // Reset PC to 0
    input  logic [31:0] pc_i,           // Next PC address
    output logic [31:0] pc_o            // Current PC address
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin

            pc_o <= {PC_WIDTH{1'b0}};   // Asynchronous Reset

        end else if (soft_reset_i) begin

            pc_o <= {PC_WIDTH{1'b0}};   // Synchronous Reset

        end else if (write_en_i) begin

            pc_o <= pc_i;              // Update if write enabled

        end
        else begin

            pc_o <= pc_o;             // If not writing, hold the value (Stall)

        end
    end

endmodule
