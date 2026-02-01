// -----------------------------------------------------------------------------
// Module: hazard_unit
// Description: Detects Data Hazards (Load-Use) and Control Hazards (Branching).
//              Generates stall and flush signals to coordinate pipeline flow.
// -----------------------------------------------------------------------------

module hazard_unit (
    // Inputs from Decode Stage (Current Instruction in ID)
    input  logic [4:0] rs1_addr_id_i,
    input  logic [4:0] rs2_addr_id_i,

    // Inputs from Execute Stage (Previous Instruction)
    input  logic       id_ex_mem_read_i, // Defines if instr in EX is a Load
    input  logic [4:0] id_ex_rd_i,       // Destination register of instr in EX
    input  logic       flush_req_i,    // High if Branch/Jump is taken (Flush Req)

    // Control Outputs
    output logic       pc_write_en_o,    // 0 = Freeze PC
    output logic       if_id_write_en_o, // 0 = Freeze IF/ID Register
    output logic       if_id_flush_o,    // 1 = Clear IF/ID Register (Branch)
    output logic       id_ex_flush_o     // 1 = Clear ID/EX Register (Branch OR Stall)
);

    logic is_load_use_hazard;

    // -------------------------------------------------------------------------
    // 1. Load-Use Hazard Detection
    // -------------------------------------------------------------------------
    // Logic: If the instruction in EX is a Load, and the instruction in ID
    // depends on the result of that Load (checking RS1 or RS2), we must stall.
    // Note: We strictly check that rd != 0 (x0 is always 0).
    // -------------------------------------------------------------------------
    always_comb begin
        if (id_ex_mem_read_i && (id_ex_rd_i != 5'b0) &&
           ((id_ex_rd_i == rs1_addr_id_i) || (id_ex_rd_i == rs2_addr_id_i))) begin
            is_load_use_hazard = 1'b1;
        end else begin
            is_load_use_hazard = 1'b0;
        end
    end

    // -------------------------------------------------------------------------
    // 2. Output Signal Generation
    // -------------------------------------------------------------------------

    // PC Control: Freeze PC on Load-Use Hazard so we re-fetch the same address later.
    assign pc_write_en_o = ~is_load_use_hazard;

    // IF/ID Control:
    // - Write Enable: Freeze on Load-Use to keep the dependent instruction in ID.
    // - Flush: Clear on Branch Taken (Control Hazard).
    assign if_id_write_en_o = ~is_load_use_hazard;
    assign if_id_flush_o    = flush_req_i;

    // ID/EX Control:
    // - Flush: We must insert a bubble (NOP) if:
    //      1. A Load-Use hazard occurred (Stall logic requires a bubble in EX).
    //      2. A Branch was taken (Control logic requires discarding the speculative instr).
    assign id_ex_flush_o    = is_load_use_hazard | flush_req_i;

endmodule
