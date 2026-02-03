// -----------------------------------------------------------------------------
// Module: flow_controller
// Description: ID Stage Flow Control Unit.
//              Handles Branch/Jump evaluation.
// -----------------------------------------------------------------------------

module flow_controller (
    // Control Inputs
    input  logic        is_branch_i,
    input  logic        is_jal_i,
    input  logic        is_jalr_i,
    input  logic        zero_i,         // RS1 == RS2 at Decode Stage
    input  logic [2:0]  funct3_i,       // Branch condition type

    // Outputs
    output logic        flow_change_o    // Indicates a change in control flow (branch/jump taken)
);

    // FLUSH = ((IS_BRANCH) & (ZERO xor FUNCT3)) | IS_JAL | IS_JALR
    always_comb begin
        logic branch_taken;
        
        // ZERO xor FUNCT3[0] determines branch taken condition. (Zero flag and branch type need to differ for taken)
        branch_taken = zero_i ^ funct3_i[0];
        
        flow_change_o = (is_branch_i && branch_taken) || is_jal_i || is_jalr_i;
    end

endmodule
