//-----------------------------------------------------------------------------------
//  Module: imm_gen
//
//  Description: RV32I Immediate Generator. 
// Extracts and sign-extends immediates from the instruction.
//
//  Bit Mapping Reference:
// I-type: { {20{inst[31]}}, inst[31:20] }
// S-type: { {20{inst[31]}}, inst[31:25], inst[11:7] }
// B-type: { {19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0 }
// U-type: { inst[31:12], 12'b0 }
// J-type: { {11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0 }
//-----------------------------------------------------------------------------------

module imm_gen (
    input  logic [31:0] instr,    // 32-bit raw instruction
    output logic [31:0] imm_ext   // 32-bit sign-extended immediate
);

    // Opcode used to determine formatting
    logic [6:0] opcode;
    assign opcode = instr[6:0];

    always_comb begin
        case (opcode)
            // I-Type: Arithmetic Immediates, Loads, JALR
            7'b0010011, 7'b0000011, 7'b1100111: begin
                imm_ext = { {20{instr[31]}}, instr[31:20] };
            end

            // S-Type: Stores
            7'b0100011: begin
                imm_ext = { {20{instr[31]}}, instr[31:25], instr[11:7] };
            end

            // B-Type: Branches
            7'b1100011: begin
                imm_ext = { {19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0 };
            end

            // U-Type: LUI
            7'b0110111, 7'b0010111: begin
                imm_ext = { instr[31:12], 12'b0 };
            end

            // J-Type: JAL
            7'b1101111: begin
                imm_ext = { {11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0 };
            end

            default: begin
                imm_ext = 32'b0;
            end
        endcase
    end

endmodule
