// -----------------------------------------------------------------------------
// Module: hazard_protection_unit
// Description: Central pipeline coordination.
//              Resolves Load-Use Hazards, Control Hazards, and System Halts
//              based on a strict priority table.
// -----------------------------------------------------------------------------

module hazard_protection_unit (
    // Inputs from Decode Stage (Current Instruction in ID)
    input  logic [4:0] rs1_addr_id_i,
    input  logic [4:0] rs2_addr_id_i,

    // Inputs from Execute Stage (Previous Instruction)
    input  logic       id_ex_mem_read_i, // Load Indicator
    input  logic [4:0] id_ex_rd_i,       // Destination Register
    
    // Inputs from Flow Controller
    input  logic       redirect_req_i,   // Branch/Jump taken -> Flush
    input  logic       halt_detected_i,  // ECALL -> System Stop

    // Control Outputs (Enable = !Stall)
    output logic       pc_write_en_o,    
    output logic       if_id_write_en_o, 
    output logic       if_id_flush_o,    
    output logic       id_ex_write_en_o, 
    output logic       id_ex_flush_o     
);

    logic is_load_use_hazard;

    // 1. Load-Use Hazard Detection
    // If instr in EX is Load, and instr in ID needs that data -> Hazard.
    always_comb begin
        if (id_ex_mem_read_i && (id_ex_rd_i != 5'b0) &&
           ((id_ex_rd_i == rs1_addr_id_i) || (id_ex_rd_i == rs2_addr_id_i))) begin
            is_load_use_hazard = 1'b1;
        end else begin
            is_load_use_hazard = 1'b0;
        end
    end

    // 2. Priority Logic Table (Dossier Section 4.2)
    always_comb begin
        // Default: Normal Operation (All systems go)
        pc_write_en_o    = 1'b1;
        if_id_write_en_o = 1'b1;
        if_id_flush_o    = 1'b0;
        id_ex_write_en_o = 1'b1;
        id_ex_flush_o    = 1'b0;

        // Priority 1: System Halt
        // Freeze PC and ID/EX (lock ECALL in EX stage). 
        // Kill IF/ID (instruction behind ECALL).
        if (halt_detected_i) begin
            pc_write_en_o    = 1'b0; // Freeze
            if_id_write_en_o = 1'b1; // Allow flush update
            if_id_flush_o    = 1'b1; // Kill
            id_ex_write_en_o = 1'b0; // Freeze (Lock Halt state)
            id_ex_flush_o    = 1'b0;
        end
        
        // Priority 2: Branch Redirect
        // Kill instructions in ID and IF stages.
        else if (redirect_req_i) begin
            pc_write_en_o    = 1'b1; // Allow jump to new target
            if_id_write_en_o = 1'b1; 
            if_id_flush_o    = 1'b1; // Flush IF/ID
            id_ex_write_en_o = 1'b1; 
            id_ex_flush_o    = 1'b1; // Flush ID/EX
        end

        // Priority 3: Load-Use Stall
        // Freeze PC and IF/ID (retry fetch later). 
        // Insert Bubble in ID/EX.
        else if (is_load_use_hazard) begin
            pc_write_en_o    = 1'b0; // Freeze
            if_id_write_en_o = 1'b0; // Freeze
            if_id_flush_o    = 1'b0; 
            id_ex_write_en_o = 1'b1; 
            id_ex_flush_o    = 1'b1; // Insert Bubble (NOP)
        end
    end

endmodule
