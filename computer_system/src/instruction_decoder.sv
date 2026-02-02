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
    assign opcode_o = instruction_word_i[6:0];
    assign rd_o     = instruction_word_i[11:7];
    assign funct3_o = instruction_word_i[14:12];
    assign rs2_o    = instruction_word_i[24:20];
    assign funct7_o = instruction_word_i[31:25];

    // For LUI (U-Type), bits [19:15] are part of the immediate, not a register index.
    // We force RS1 to 0 here. This allows the ALU to perform a standard ADD (0 + Imm)
    // without needing special control signals, and prevents the Forwarding Unit from
    // detecting false hazards on the immediate data bits.
    assign rs1_o    = (opcode_o == 7'b0110111) ? 5'b0 : instruction_word_i[19:15];

endmodule
