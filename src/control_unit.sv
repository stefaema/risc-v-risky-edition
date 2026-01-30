// -----------------------------------------------------------------------------
// Module: control_unit
// Description: Main Decoder for RV32I.
//              Translates the 7-bit Opcode into high-level control signals
//              for the Datapath and ALU Control.
// -----------------------------------------------------------------------------

module control_unit (
    input  logic [6:0] opcode_i,

    // Execution Control
    output logic       branch_o,     // 1 = Conditional Branch (BEQ, BNE)
    output logic       jump_o,       // 1 = Unconditional Jump (JAL, JALR)
    output logic [1:0] alu_opmode_o,     // 00=Add, 01=Sub, 10=R-Type, 11=I-Type
    output logic       alu_src_o,    // 0 = RegB, 1 = Immediate

    // Memory Control
    output logic       mem_read_o,   // 1 = Read from Data Memory
    output logic       mem_write_o,  // 1 = Write to Data Memory

    // Writeback Control
    output logic       reg_write_o,  // 1 = Write to Register File
    output logic       mem_to_reg_o  // 0 = ALU Result, 1 = Memory Data
);

    localparam logic [6:0]
        OP_R_TYPE   = 7'b0110011, // add, sub, sll, etc.
        OP_I_TYPE   = 7'b0010011, // addi, slti, etc.
        OP_LOAD     = 7'b0000011, // lb, lh, lw, etc.
        OP_STORE    = 7'b0100011, // sb, sh, sw
        OP_BRANCH   = 7'b1100011, // beq, bne
        OP_JAL      = 7'b1101111, // jal
        OP_JALR     = 7'b1100111, // jalr
        OP_LUI      = 7'b0110111; // lui (Load Upper Immediate)
    
    localparam logic [1:0]
        ALU_OP_ADD = 2'b00,
        ALU_OP_SUB = 2'b01,
        ALU_OP_RTY = 2'b10,
        ALU_OP_ITY = 2'b11;

    always_comb begin
        // Default: Safety first (Disable all writes/jumps)
        branch_o     = 1'b0;
        jump_o       = 1'b0;
        mem_read_o   = 1'b0;
        mem_write_o  = 1'b0;
        reg_write_o  = 1'b0;
        mem_to_reg_o = 1'b0; 
        alu_src_o    = 1'b0; 
        alu_opmode_o     = ALU_OP_ADD;

        case (opcode_i)
            OP_R_TYPE: begin
                reg_write_o = 1'b1;
                alu_opmode_o    = ALU_OP_RTY; // "Look at Funct3/7"
            end

            OP_I_TYPE: begin
                reg_write_o = 1'b1;
                alu_src_o   = 1'b1;  // Use Immediate
                alu_opmode_o    = ALU_OP_ITY; // "Look at Funct3, Force Add if needed"
            end

            OP_LOAD: begin
                reg_write_o  = 1'b1;
                mem_read_o   = 1'b1;
                mem_to_reg_o = 1'b1; // Select Memory Data
                alu_src_o    = 1'b1; // Calculate Addr: Base + Imm
                alu_opmode_o     = ALU_OP_ADD; // Force ADD
            end

            OP_STORE: begin
                mem_write_o = 1'b1;
                alu_src_o   = 1'b1; // Calculate Addr: Base + Imm
                alu_opmode_o    = ALU_OP_ADD; // Force ADD
            end

            OP_BRANCH: begin
                branch_o = 1'b1;
                alu_opmode_o = ALU_OP_SUB; // Force SUB (Comparison)
            end

            OP_JAL: begin
                jump_o      = 1'b1;
                reg_write_o = 1'b1;
                alu_src_o   = 1'b1; 
                alu_opmode_o    = ALU_OP_ADD; // Force ADD
            end

            OP_JALR: begin
                jump_o      = 1'b1;
                reg_write_o = 1'b1;
                alu_src_o   = 1'b1; // Target = Rs1 + Imm
                alu_opmode_o    = ALU_OP_ADD; // Force ADD
            end

            OP_LUI: begin
                reg_write_o = 1'b1;
                alu_src_o   = 1'b1;  // Pass Immediate
                alu_opmode_o    = ALU_OP_ADD; // Force ADD
            end

            default: begin
                // Maintain default safe state defined at top
            end
        endcase
    end

endmodule
