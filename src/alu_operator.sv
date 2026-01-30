// -----------------------------------------------------------------------------
// Module: alu_operator
// Description: Decodes ALUOp and instruction bits to generate ALU Control signals.
// -----------------------------------------------------------------------------

module alu_operator (
    input  logic [1:0] alu_op_i,        // From Control Unit (00=Add, 01=Sub, 10=R, 11=I)
    input  logic [2:0] funct3_i,        // Instruction bits [14:12]
    input  logic       funct7_bit30_i,  // Instruction bit [30] (Distinguishes Add/Sub, Srl/Sra)
    output logic [3:0] alu_control_o    // To ALU
);

    always_comb begin
        // Default safe assignment
        alu_control_o = 4'b0000; // ADD

        case (alu_op_i)
            // LW, SW, Jumps (Force ADD)
            2'b00: alu_control_o = 4'b0000;

            // Branches (Force SUB for comparison)
            2'b01: alu_control_o = 4'b1000;

            // R-Type (10) and I-Type (11)
            default: begin
                case (funct3_i)
                    // ADD or SUB
                    3'b000: begin
                        // Only check bit 30 for R-Type. I-Type (ADDI) is always ADD.
                        if (alu_op_i == 2'b10 && funct7_bit30_i)
                            alu_control_o = 4'b1000; // SUB
                        else
                            alu_control_o = 4'b0000; // ADD
                    end

                    // SLL (Shift Left Logical)
                    3'b001: alu_control_o = 4'b0001;

                    // SLT (Set Less Than Signed)
                    3'b010: alu_control_o = 4'b0010;

                    // SLTU (Set Less Than Unsigned)
                    3'b011: alu_control_o = 4'b0011;

                    // XOR
                    3'b100: alu_control_o = 4'b0100;

                    // SRL or SRA (Shift Right)
                    3'b101: begin
                        // Bit 30 distinguishes logical/arithmetic for both R-Type and I-Type
                        if (funct7_bit30_i)
                            alu_control_o = 4'b1101; // SRA
                        else
                            alu_control_o = 4'b0101; // SRL
                    end

                    // OR
                    3'b110: alu_control_o = 4'b0110;

                    // AND
                    3'b111: alu_control_o = 4'b0111;

                    default: alu_control_o = 4'b0000;
                endcase
            end
        endcase
    end

endmodule
