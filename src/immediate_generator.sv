//-----------------------------------------------------------------------------------
//  Module: immediate_generator
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

module immediate_generator (
    input  logic [31:0] instruction_word_i,    // 32-bit raw instruction
    output logic [31:0] ext_immediate_o   // 32-bit sign-extended immediate
);

    // Opcode used to determine formatting
    logic [6:0] opcode;
    assign opcode = instruction_word_i[6:0];

    always_comb begin
        case (opcode)
            // I-Type: Arithmetic Immediates, Loads, JALR
            7'b0010011, 7'b0000011, 7'b1100111: begin
                ext_immediate_o = { {20{instruction_word_i[31]}}, instruction_word_i[31:20] };
            end

            // S-Type: Stores
            7'b0100011: begin
                ext_immediate_o = { {20{instruction_word_i[31]}}, instruction_word_i[31:25], instruction_word_i[11:7] };
            end

            // B-Type: Branches
            7'b1100011: begin
                ext_immediate_o = { {19{instruction_word_i[31]}}, instruction_word_i[31], instruction_word_i[7], instruction_word_i[30:25], instruction_word_i[11:8], 1'b0 };
            end

            // U-Type: LUI
            7'b0110111, 7'b0010111: begin
                ext_immediate_o = { instruction_word_i[31:12], 12'b0 };
            end

            // J-Type: JAL
            7'b1101111: begin
                ext_immediate_o = { {11{instruction_word_i[31]}}, instruction_word_i[31], instruction_word_i[19:12], instruction_word_i[20], instruction_word_i[30:21], 1'b0 };
            end

            default: begin
                ext_immediate_o = 32'b0;
            end
        endcase
    end

endmodule
