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
    input  logic             flush_i,    // Synchronous Clear (High Priority)
    input  logic             stall_i,    // Write Enable / Freeze (Low Priority)

    // Data Path
    input  logic [WIDTH-1:0] data_i,
    output logic [WIDTH-1:0] data_o
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_o <= {WIDTH{1'b0}}; // Asynchronous Reset
        end
        else if (flush_i) begin
            data_o <= {WIDTH{1'b0}}; // Synchronous Flush (Insert Bubble/NOP)
        end
        else if (!stall_i) begin
            data_o <= data_i;        // Update if NOT Stalled
        end
        // else: Implicitly hold current value (Stall)
    end

endmodule
