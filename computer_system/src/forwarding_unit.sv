// -----------------------------------------------------------------------------
// Module: forwarding_unit
// Description: Resolves Read-After-Write (RAW) hazards by controlling the
//              ALU bypass network. Detects dependencies in EX and MEM stages.
// -----------------------------------------------------------------------------

module forwarding_unit (
    // Inputs from Decode Stage (Current Instruction in ID)
    input  logic [4:0] rs1_id_i,
    input  logic [4:0] rs2_id_i,
    
    // Inputs from Execute Stage (Previous Instruction)
    input  logic       reg_write_ex_i, // Is EX stage instruction writing to a register?
    input  logic [4:0] rd_ex_i,        // Destination Register

    // Inputs from Memory Stage (2nd Previous Instruction)
    input  logic       reg_write_mem_i, // Is MEM stage instruction writing to a register?
    input  logic [4:0] rd_mem_i,        // Destination Register

    // Inputs from Write-Back Stage (3rd Previous Instruction)
    input  logic       reg_write_wb_i, // Is WB stage instruction writing to a register?
    input  logic [4:0] rd_wb_i,        // Destination Register

    // Forwarding Outputs
    output logic [1:0] forward_rs1_o,        // Forwarding control for RS1's bypased data
    output logic [1:0] forward_rs2_o         // Forwarding control for RS2's bypased data
);

    // Forwarding Logic
    always_comb begin
        // Default values
        forward_rs1_o = 2'b00;
        forward_rs2_o = 2'b00;

        // RS1 forwarding
        if (reg_write_ex_i && (rd_ex_i != 5'b0) && (rd_ex_i == rs1_id_i)) begin
            forward_rs1_o = 2'b11; // Forward from EX
        end else if (reg_write_mem_i && (rd_mem_i != 5'b0) && (rd_mem_i == rs1_id_i)) begin
            forward_rs1_o = 2'b01; // Forward from MEM
        end else if (reg_write_wb_i && (rd_wb_i != 5'b0) && (rd_wb_i == rs1_id_i)) begin
            forward_rs1_o = 2'b10; // Forward from WB
        end

        // RS2 forwarding
        if (reg_write_ex_i && (rd_ex_i != 5'b0) && (rd_ex_i == rs2_id_i)) begin
            forward_rs2_o = 2'b01; // Forward from EX
        end else if (reg_write_mem_i && (rd_mem_i != 5'b0) && (rd_mem_i == rs2_id_i)) begin
            forward_rs2_o = 2'b10; // Forward from MEM
        end else if (reg_write_wb_i && (rd_wb_i != 5'b0) && (rd_wb_i == rs2_id_i)) begin
            forward_rs2_o = 2'b11; // Forward from WB
        end
    end

endmodule
