// -----------------------------------------------------------------------------
// Module: memory_range_tracker
// Description: Monitors memory write operations to track the minimum and 
//              maximum addresses modified. Used for optimized memory dumps.
// -----------------------------------------------------------------------------

module memory_range_tracker (
    input  logic        clk,
    input  logic        soft_reset_i,
    input  logic        mem_write_en,
    input  logic [31:0] addr_in_use_i,
    output logic [31:0] min_addr_o,
    output logic [31:0] max_addr_o
);

    always_ff @(posedge clk) begin
        if (soft_reset_i) begin
            // Initialize inverted to capture first valid write
            min_addr_o <= 32'hFFFF_FFFF;
            max_addr_o <= 32'h0000_0000;
        end else if (mem_write_en) begin
            // Update Minimum
            if (addr_in_use_i < min_addr_o) begin
                min_addr_o <= addr_in_use_i;
            end
            
            // Update Maximum
            if (addr_in_use_i > max_addr_o) begin
                max_addr_o <= addr_in_use_i;
            end
        end
    end

endmodule
