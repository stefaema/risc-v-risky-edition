// -----------------------------------------------------------------------------
// Module: hazard_protection_unit
// Description: Resolves Load-Use Hazards.
// -----------------------------------------------------------------------------

module hazard_protection_unit (
    // Inputs from Decode Stage (Current Instruction in ID)
    input  logic [4:0] rs1_id_i,
    input  logic [4:0] rs2_id_i,

    // Inputs from Execute Stage (Previous Instruction)
    input  logic       mem_read_ex_i, // Indicates if EX stage instruction is a load
    input  logic [4:0] rd_ex_i,       // Destination Register: used to see if it matches rs1/rs2 in ID and thus creates a hazard

    //Outputs
    output logic       freeze_o,      // Freeze signal to IF/ID pipeline register
    output logic       force_nop_o    // Force NOP in CU
);

    // Load-Use Hazard Detection
    // FREEZE = FORCE_NOP = (MEM_READ@EX & RD@EX!=0) & (RD@EX==RS1@ID | RD@EX==RS2@ID)
    always_comb begin
        logic hazard_detected;
        
        hazard_detected = mem_read_ex_i && 
                         (rd_ex_i != 5'b0) && 
                         ((rd_ex_i == rs1_id_i) || (rd_ex_i == rs2_id_i));
        
        freeze_o    = hazard_detected;
        force_nop_o = hazard_detected;
    end

endmodule
