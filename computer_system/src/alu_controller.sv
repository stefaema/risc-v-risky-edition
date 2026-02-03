// -----------------------------------------------------------------------------
// Module: alu_controller
// Description: Decodes ALU Intent (from Control Unit) and instruction bits 
//              (funct3/7) to generate specific ALU Control signals.
// -----------------------------------------------------------------------------

module alu_controller (
    input  logic [1:0] alu_intent,   // From Control Unit (00=Add, 01=Sub, 10=R, 11=I)
    input  logic [2:0] funct3_i,       // Instruction bits [14:12]
    input  logic       funct7_bit30_i, // Instruction bit [30] (Add/Sub, Srl/Sra)
    output logic [3:0] alu_operation_o // To ALU
);

    // ALU Operation Encodings (Internal definitions for clarity)
    localparam logic [3:0]
        OP_ADD  = 4'b0000,
        OP_SUB  = 4'b1000,
        OP_SLL  = 4'b0001,
        OP_SLT  = 4'b0010,
        OP_SLTU = 4'b0011,
        OP_XOR  = 4'b0100,
        OP_SRL  = 4'b0101,
        OP_SRA  = 4'b1101,
        OP_OR   = 4'b0110,
        OP_AND  = 4'b0111,
        OP_NOT_USED = 4'b1111; // As some calculations happen outside ALU, we define a NOT_USED code for debugging purposes.

    always_comb begin
        // Default safe assignment
        alu_operation_o = OP_ADD; 

        case (alu_intent)
            // 00: Load, Store -> Force ADD (calc address). Not useful in JMP instr as calculation is done in ID.
            2'b00: alu_operation_o = OP_ADD;

            // 01: Branch -> Force SUB (for comparison)
            2'b01: alu_operation_o = OP_NOT_USED; // Branch comparisons are done in ID.

            // 10 (R-Type) and 11 (I-Type)
            default: begin
                case (funct3_i)
                    // ADD / SUB / ADDI
                    3'b000: begin
                        // Only R-Type (10) uses bit 30 to distinguish SUB.
                        // I-Type (11) ADDI is always ADD, ignoring bit 30.
                        if (alu_intent == 2'b10 && funct7_bit30_i)
                            alu_operation_o = OP_SUB;
                        else
                            alu_operation_o = OP_ADD;
                    end

                    // SLL (Shift Left Logical)
                    3'b001: alu_operation_o = OP_SLL;

                    // SLT (Set Less Than Signed)
                    3'b010: alu_operation_o = OP_SLT;

                    // SLTU (Set Less Than Unsigned)
                    3'b011: alu_operation_o = OP_SLTU;

                    // XOR
                    3'b100: alu_operation_o = OP_XOR;

                    // SRL / SRA (Shift Right)
                    3'b101: begin
                        // Bit 30 distinguishes Logical/Arithmetic for BOTH R-Type and I-Type (SRAI)
                        if (funct7_bit30_i)
                            alu_operation_o = OP_SRA;
                        else
                            alu_operation_o = OP_SRL;
                    end

                    // OR
                    3'b110: alu_operation_o = OP_OR;

                    // AND
                    3'b111: alu_operation_o = OP_AND;

                    default: alu_operation_o = OP_ADD;
                endcase
            end
        endcase
    end

endmodule
