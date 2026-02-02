// -----------------------------------------------------------------------------
// Module: forwarding_unit
// Description: Resolves Read-After-Write (RAW) hazards by controlling the
//              ALU bypass network. Detects dependencies in EX and MEM stages.
// -----------------------------------------------------------------------------

module forwarding_unit (
    // Inputs: Current Requirements (ID/EX Stage)
    input  logic [4:0] rs1_id_ex_i,
    input  logic [4:0] rs2_id_ex_i,

    // Inputs: Stage 3 Producer (EX/MEM Stage)
    input  logic [4:0] rd_ex_mem_i,
    input  logic       reg_write_ex_mem_en,
    input  logic       mem_read_ex_mem_en, // Load indicator

    // Inputs: Stage 4 Producer (MEM/WB Stage)
    input  logic [4:0] rd_mem_wb_i,
    input  logic       reg_write_mem_wb_en,

    // Outputs: Mux Control Signals
    output logic [1:0] forward_a_optn_o, // 00: Reg, 01: WB, 10: ALU
    output logic [1:0] forward_b_optn_o
);

    // -------------------------------------------------------------------------
    // Forwarding Logic for Operand A (RS1)
    // -------------------------------------------------------------------------
    always_comb begin
        // Priority 1: EX Hazard
        // If the previous instruction (in EX/MEM) writes to RS1, is not x0,
        // and is NOT a Load (mem_read == 0).
        if (reg_write_ex_mem_en &&
           (rd_ex_mem_i != 5'b0) &&
           (rd_ex_mem_i == rs1_id_ex_i)) begin
            forward_a_optn_o = 2'b10; // Forward from ALU Result

        // Priority 2: MEM Hazard
        // If the 2nd previous instruction (in MEM/WB) writes to RS1, is not x0.
        // Note: The 'else' ensures we don't double-forward if EX hazard exists.
        end else if (reg_write_mem_wb_en &&
                    (rd_mem_wb_i != 5'b0) &&
                    (rd_mem_wb_i == rs1_id_ex_i)) begin
            forward_a_optn_o = 2'b01; // Forward from Writeback

        // Default: No Hazard
        end else begin
            forward_a_optn_o = 2'b00; // Use Register File value
        end
    end

    // -------------------------------------------------------------------------
    // Forwarding Logic for Operand B (RS2)
    // -------------------------------------------------------------------------
    always_comb begin
        // Priority 1: EX Hazard
        if (reg_write_ex_mem_en &&
           (rd_ex_mem_i != 5'b0) &&
           (rd_ex_mem_i == rs2_id_ex_i)) begin
            forward_b_optn_o = 2'b10; // Forward from ALU Result

        // Priority 2: MEM Hazard
        end else if (reg_write_mem_wb_en &&
                    (rd_mem_wb_i != 5'b0) &&
                    (rd_mem_wb_i == rs2_id_ex_i)) begin
            forward_b_optn_o = 2'b01; // Forward from Writeback

        // Default: No Hazard
        end else begin
            forward_b_optn_o = 2'b00; // Use Register File value
        end
    end

endmodule
