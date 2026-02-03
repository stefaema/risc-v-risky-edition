// -----------------------------------------------------------------------------
// Module: pipeline_register
// Description: Parameterizable pipeline register with flow control logic.
//              Supports Synchronous Flush (High Priority) and Stall (Enable).
// -----------------------------------------------------------------------------

module pipeline_register #(
    parameter int WIDTH = 32
)(
    input  logic             clk,
    input  logic             rst_n,      // Asynchronous Reset (Active Low)

    // Flow Control
    input  logic             soft_reset_i, 
    input  logic             write_en_i,     

    // Data Path
    input  logic [WIDTH-1:0] data_i,
    output logic [WIDTH-1:0] data_o
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_o <= {WIDTH{1'b0}}; // Asynchronous Reset
        end
        else if (soft_reset_i) begin
            data_o <= {WIDTH{1'b0}}; // Synchronous Reset
        end
        else if (write_en_i) begin
            data_o <= data_i;        // Update if write enabled
        end
        else begin 
            data_o <= data_o;        // If not writing, hold the value (Stall)
        end
    end

endmodule
