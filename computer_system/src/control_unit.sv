// -----------------------------------------------------------------------------
// Module: control_unit
// Description: Main Control Unit (Decoder).
//              Translates the 7-bit Opcode into internal control bus signals
//              based on the Core Dossier specifications.
// -----------------------------------------------------------------------------

module control_unit (
    input  logic [6:0] opcode_i,
    input  logic       force_nop_i,   // When high, overrides all outputs to NOPs

    // Flow Control Flags
    output logic       is_halt,      // 1 = Halt Execution (ecall)
    output logic       is_branch,    // 1 = Conditional Branch
    output logic       is_jal,       // 1 = Unconditional Jump (JAL)
    output logic       is_jalr,      // 1 = Jump Register (JALR)

    // Memory Access
    output logic       mem_write_en,    // 1 = Write to Data Memory
    output logic       mem_read_en,     // 1 = Read from Data Memory

    // Writeback Control
    output logic       reg_write_en,    // 1 = Write to Register File
    output logic       rd_src_optn,     // 0=ALU, 1=Mem

    // Execution / ALU Control
    output logic [1:0] alu_intent,   // 00=Add, 01=Sub, 10=R-Type, 11=I-Type
    output logic       alu_src_optn  // 0=RegB, 1=Immediate
);

    // --- Opcode_i Definitions ---
    localparam logic [6:0]
        OP_R_TYPE   = 7'b0110011, // add, sub, sll, etc.
        OP_I_TYPE   = 7'b0010011, // addi, slti, etc.
        OP_LOAD     = 7'b0000011, // lb, lh, lw
        OP_STORE    = 7'b0100011, // sb, sh, sw
        OP_BRANCH   = 7'b1100011, // beq, bne
        OP_JAL      = 7'b1101111, // jal
        OP_JALR     = 7'b1100111, // jalr
        OP_SYSTEM   = 7'b1110011, // ecall
        OP_LUI      = 7'b0110111; // lui

    // --- Control Constants (Dossier Sec 3.3 & 3.5) ---
    // ALU Intent
    localparam logic [1:0]
        ALU_ADD     = 2'b00,
        ALU_SUB     = 2'b01,
        ALU_RTY     = 2'b10,
        ALU_ITY     = 2'b11;

    // Writeback Source
    localparam logic
        WB_ALU      = 1'b00,
        WB_MEM      = 1'b1;

    always_comb begin
        // Default Safety State (NOP behavior)
        is_halt      = 1'b0;
        is_branch    = 1'b0;
        is_jal       = 1'b0;
        is_jalr      = 1'b0;
        mem_write_en = 1'b0;
        mem_read_en  = 1'b0;
        reg_write_en = 1'b0;
        rd_src_optn  = WB_ALU;
        alu_intent   = ALU_ADD;
        alu_src_optn = 1'b0;

        if (!force_nop_i) begin
            case (opcode_i)
                OP_R_TYPE: begin
                    reg_write_en    = 1'b1;
                    alu_intent      = ALU_RTY;
                    rd_src_optn     = WB_ALU;
                    alu_src_optn    = 1'b0;
                end

                OP_I_TYPE: begin
                    reg_write_en    = 1'b1;
                    alu_intent      = ALU_ITY;
                    rd_src_optn     = WB_ALU;
                    alu_src_optn    = 1'b1;
                end

                OP_LOAD: begin
                    reg_write_en    = 1'b1;
                    mem_read_en     = 1'b1;
                    rd_src_optn     = WB_MEM;
                    alu_intent      = ALU_ADD;
                    alu_src_optn    = 1'b1;
                end

                OP_STORE: begin
                    mem_write_en    = 1'b1;
                    alu_intent      = ALU_ADD;
                    alu_src_optn    = 1'b1;
                end

                OP_BRANCH: begin
                    is_branch       = 1'b1;
                    alu_intent      = ALU_SUB;
                    alu_src_optn    = 1'b0;
                end

                OP_JAL: begin
                    is_jal          = 1'b1;
                    reg_write_en    = 1'b1;
                end

                OP_JALR: begin
                    is_jalr         = 1'b1;
                    reg_write_en    = 1'b1;
                    alu_intent      = ALU_ADD;
                    alu_src_optn    = 1'b1;
                end

                OP_LUI: begin
                    reg_write_en    = 1'b1;
                    rd_src_optn     = WB_ALU;
                    alu_intent      = ALU_ADD;
                    alu_src_optn    = 1'b1;
                end

                OP_SYSTEM: begin
                    is_halt         = 1'b1;
                end

                default: begin
                    // Maintain defaults
                end
            endcase
        end
    end
endmodule
