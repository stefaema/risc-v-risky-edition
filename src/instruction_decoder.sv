//-----------------------------------------------------------------------------------
// Module: instruction_decoder
//
// Description: Breaks down the raw 32-bit instruction into constituent fields
//              per the RV32I specification.
//-----------------------------------------------------------------------------------

module instruction_decoder (
    input  logic [31:0] instruction_word_i,
    output logic [6:0]  opcode_o,
    output logic [4:0]  rd_o,
    output logic [2:0]  funct3_o,
    output logic [4:0]  rs1_o,
    output logic [4:0]  rs2_o,
    output logic [6:0]  funct7_o
);

    // Combinational slicing based on standard RISC-V field positions
    assign opcode_o  = instruction_word_i[6:0];
    assign rd_o      = instruction_word_i[11:7];
    assign funct3_o  = instruction_word_i[14:12];
    assign rs1_o     = instruction_word_i[19:15];
    assign rs2_o     = instruction_word_i[24:20];
    assign funct7_o  = instruction_word_i[31:25];

endmodule
