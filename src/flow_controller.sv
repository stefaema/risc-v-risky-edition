// -----------------------------------------------------------------------------
// Module: flow_controller
// Description: Execution Stage Flow Control Unit.
//              Implements Static Not-Taken prediction logic, branch condition 
//              evaluation, pipeline flushing, and PC target selection.
// -----------------------------------------------------------------------------

module flow_controller (
    // Control Inputs
    input  logic        is_branch_i,
    input  logic        is_jal_i,
    input  logic        is_jalr_i,

    // Data Inputs
    input  logic [2:0]  funct3_i,
    input  logic        zero_i,

    // Target Address Inputs
    input  logic [31:0] pc_imm_target_i, // From Imm Adder (Branch/JAL)
    input  logic [31:0] alu_target_i,    // From ALU (JALR)

    // Outputs
    output logic        pc_src_optn_o,       // 0: Next Sequential, 1: Redirect
    output logic        flush_req_o,         // Flushes IF/ID and ID/EX
    output logic [31:0] final_target_addr_o  // Address to fetch next
);

    logic branch_condition_met;
    logic do_redirect;

    // 1. Condition Evaluation
    // Based on RISC-V funct3 codes.
    // Note: Dossier specifies 'zero' flag. BEQ/BNE are fully supported.
    // Magnitude comparisons (BLT/BGE) depend on specific ALU implementation
    // regarding the zero flag in this architecture definition.
    always_comb begin
        case (funct3_i)
            3'b000:  branch_condition_met = (zero_i == 1'b1); // BEQ
            3'b001:  branch_condition_met = (zero_i == 1'b0); // BNE
            // Default safe handling for unspecified signed/unsigned comparisons
            // in this simplified dossier context.
            default: branch_condition_met = 1'b0; 
        endcase
    end

    // 2. Prediction Verification (Static Not-Taken)
    // We redirect (Fail Prediction) if it is a Jump or a Taken Branch.
    assign do_redirect = is_jal_i | is_jalr_i | (is_branch_i & branch_condition_met);

    // 3. Output Generation
    assign pc_src_optn_o = do_redirect;
    assign flush_req_o   = do_redirect;

    // 4. Target Selection
    // JALR requires setting the LSB to 0 (Standard RISC-V Spec).
    // All other control transfers use the PC + Immediate calculation.
    always_comb begin
        if (is_jalr_i) begin
            final_target_addr_o = alu_target_i & 32'hFFFF_FFFE;
        end else begin
            final_target_addr_o = pc_imm_target_i;
        end
    end

endmodule
