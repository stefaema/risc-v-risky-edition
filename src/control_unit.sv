// -----------------------------------------------------------------------------
// Module: control_unit
// Description: Main Control Unit (Decoder).
//              Translates the 7-bit Opcode into internal control bus signals
//              based on the Core Dossier specifications.
// -----------------------------------------------------------------------------

module control_unit (
    input  logic [6:0] opcode_i,

    // Flow Control Flags
    output logic       is_branch,    // 1 = Conditional Branch
    output logic       is_jal,       // 1 = Unconditional Jump (JAL)
    output logic       is_jalr,      // 1 = Jump Register (JALR)

    // Memory Access
    output logic       mem_write_en,    // 1 = Write to Data Memory
    output logic       mem_read_en,     // 1 = Read from Data Memory

    // Writeback Control
    output logic       reg_write_en,    // 1 = Write to Register File
    output logic [1:0] rd_src_optn,  // 00=ALU, 01=PC+4, 10=Mem

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
        OP_LUI      = 7'b0110111; // lui

    // --- Control Constants (Dossier Sec 3.3 & 3.5) ---
    // ALU Intent
    localparam logic [1:0]
        ALU_ADD     = 2'b00,
        ALU_SUB     = 2'b01,
        ALU_RTY     = 2'b10,
        ALU_ITY     = 2'b11;

    // Writeback Source
    localparam logic [1:0]
        WB_ALU      = 2'b00,
        WB_PC_PLUS4 = 2'b01,
        WB_MEM      = 2'b10;

    always_comb begin
        // Default Safety State (NOP behavior)
        is_branch    = 1'b0;
        is_jal       = 1'b0;
        is_jalr      = 1'b0;
        mem_write_en    = 1'b0;
        mem_read_en     = 1'b0;
        reg_write_en    = 1'b0;
        rd_src_optn  = WB_ALU;
        alu_intent   = ALU_ADD;
        alu_src_optn = 1'b0;

        case (opcode_i)
            OP_R_TYPE: begin
                reg_write_en    = 1'b1;
                alu_intent   = ALU_RTY; // Delegate to funct3/7
                rd_src_optn  = WB_ALU;
                alu_src_optn = 1'b0;    // Operand B = Register
            end

            OP_I_TYPE: begin
                reg_write_en    = 1'b1;
                alu_intent   = ALU_ITY; // Delegate to funct3
                rd_src_optn  = WB_ALU;
                alu_src_optn = 1'b1;    // Operand B = Immediate
            end

            OP_LOAD: begin
                reg_write_en    = 1'b1;
                mem_read_en     = 1'b1;
                rd_src_optn  = WB_MEM;  // Select Memory Data
                alu_intent   = ALU_ADD; // Calc Addr: Base + Imm
                alu_src_optn = 1'b1;
            end

            OP_STORE: begin
                mem_write_en    = 1'b1;
                alu_intent   = ALU_ADD; // Calc Addr: Base + Imm
                alu_src_optn = 1'b1;
            end

            OP_BRANCH: begin
                is_branch    = 1'b1;
                alu_intent   = ALU_SUB; // Compare (Rs1 - Rs2)
                alu_src_optn = 1'b0;    // Compare two registers
            end

            OP_JAL: begin
                is_jal       = 1'b1;
                reg_write_en    = 1'b1;
                rd_src_optn  = WB_PC_PLUS4; // Link Register
                // Note: JAL target is calc'd by imm_pc_adder, not ALU.
                // ALU signals are don't care, defaults are safe.
            end

            OP_JALR: begin
                is_jalr      = 1'b1;
                reg_write_en    = 1'b1;
                rd_src_optn  = WB_PC_PLUS4; // Link Register
                alu_intent   = ALU_ADD;     // Target = Rs1 + Imm
                alu_src_optn = 1'b1;
            end

            OP_LUI: begin
                reg_write_en    = 1'b1;
                rd_src_optn  = WB_ALU;
                alu_intent   = ALU_ADD; // Adds Imm to x0 (hardwired 0)
                alu_src_optn = 1'b1;
            end

            default: begin
                // Maintain defaults
            end
        endcase
    end

endmodule
