// -----------------------------------------------------------------------------
// Module: ALU-cinate
// Description: 32-bit Arithmetic Logic Unit for RISC-V integer pipeline.
//              Supports Arithmetic, Logical, Shift, and Comparison operations.
// -----------------------------------------------------------------------------

module ALU_cinate (
    input  logic [31:0] SrcA,       // Operand A (Rs1 or PC)
    input  logic [31:0] SrcB,       // Operand B (Rs2 or Imm)
    input  logic [3:0]  ALUControl, // Operation Selector
    output logic [31:0] ALUResult,  // Computation Result
    output logic        Zero        // Branch Flag (1 if Result == 0)
);

    always_comb begin
        case (ALUControl)
            // Arithmetic Operations
            4'b0000: ALUResult = SrcA + SrcB;       // ADD
            4'b1000: ALUResult = SrcA - SrcB;       // SUB
            
            // Shift Operations (only the lower 5 bits of SrcB are used as you can't shift more than 31)
            4'b0001: ALUResult = SrcA << SrcB[4:0];
            
            4'b0101: ALUResult = SrcA >> SrcB[4:0]; // SRL (Shift Right Logical, lower 5 bits of SrcB as you can't shift more than 31)
            
            // SRA: Arithmetic Shift (Preserves Sign). 

            // Cast SrcA to $signed to force SystemVerilog to use >>> arithmetic shift.
            4'b1101: ALUResult = $signed(SrcA) >>> SrcB[4:0]; 

            // Comparison Operations (Set Less Than)
            
            
            4'b0010: begin
                if ($signed(SrcA) < $signed(SrcB)) // SLT: Checks if SrcA is strictly less than SrcB using 2's complement logic.
                    ALUResult = 32'd1;
                else
                    ALUResult = 32'd0;
            end

            4'b0011: begin
                if (SrcA < SrcB) // SLT Unsigned: Checks magnitude only (as if inputs were pos. ints).
                    ALUResult = 32'd1;
                else
                    ALUResult = 32'd0;
            end

            // Bitwise Logical Operations
            4'b0100: ALUResult = SrcA ^ SrcB;       // XOR
            4'b0110: ALUResult = SrcA | SrcB;       // OR
            4'b0111: ALUResult = SrcA & SrcB;       // AND

            // Default Case
            default: ALUResult = 32'b0;             // Safe default
        endcase
    end

    // Zero Flag Logic
    // Used for BEQ/BNE instructions. 
    // High if the result of the operation is exactly zero.
    assign Zero = (ALUResult == 32'b0);

endmodule
