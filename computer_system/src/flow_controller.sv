// -----------------------------------------------------------------------------
// Module: flow_controller
// Description: Execution Stage Flow Control Unit.
//              Handles Branch/Jump evaluation and Halt propagation.
// -----------------------------------------------------------------------------

module flow_controller (
    // Control Inputs
    input  logic        is_branch_i,
    input  logic        is_jal_i,
    input  logic        is_jalr_i,
    input  logic        is_halt_i,       // From Control Unit (ID/EX)

    // Data Inputs
    input  logic [2:0]  funct3_i,
    input  logic        zero_i,          // From ALU

    // Target Address Inputs
    input  logic [31:0] pc_imm_target_i, // From Imm Adder (Branch/JAL)
    input  logic [31:0] alu_target_i,    // From ALU (JALR)

    // Outputs
    output logic        pc_src_optn_o,       // 0: Next Seq, 1: Redirect
    output logic        redirect_req_o,      // Signal to Hazard Unit to flush
    output logic        halt_detected_o,     // Signal to Hazard Unit that halt detected by CU was valid
    output logic [31:0] final_target_addr_o  // Address to fetch next
);

    logic branch_condition_met;
    logic flow_change_detected;

    // 1. Condition Evaluation (Standard RISC-V BEQ/BNE)
    always_comb begin
        case (funct3_i)
            3'b000:  branch_condition_met = (zero_i == 1'b1); // BEQ
            3'b001:  branch_condition_met = (zero_i == 1'b0); // BNE
            default: branch_condition_met = 1'b0; 
        endcase
    end

    // 2. Flow Change Detection
    // We redirect if it is a Jump OR a Taken Branch
    assign flow_change_detected = is_jal_i | is_jalr_i | (is_branch_i & branch_condition_met);

    // 3. Output Generation
    assign redirect_req_o  = flow_change_detected;
    assign halt_detected_o = is_halt_i;

    // PC Source Logic:
    // We only switch the PC Mux to the Target (1) if we need to redirect 
    // AND we are NOT halting. (Halt takes priority in freezing logic).
    assign pc_src_optn_o   = flow_change_detected && !is_halt_i;

    // 4. Target Selection
    // JALR requires clearing the LSB (Standard RISC-V Spec).
    always_comb begin
        if (is_jalr_i) begin
            final_target_addr_o = alu_target_i & 32'hFFFF_FFFE;
        end else begin
            final_target_addr_o = pc_imm_target_i;
        end
    end

endmodule
