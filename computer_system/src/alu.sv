// -----------------------------------------------------------------------------
// Module: alu
// Description: 32-bit Arithmetic Logic Unit for RISC-V integer pipeline.
//              Supports Arithmetic, Logical, Shift, and Comparison operations.
// -----------------------------------------------------------------------------

module alu (
    input  logic [31:0] alu_op1_i,
    input  logic [31:0] alu_op2_i,
    input  logic [3:0]  alu_operation_i,
    output logic [31:0] alu_result_o
);

    always_comb begin
        case (alu_operation_i)
            // --- Arithmetic Operations ---
            4'b0000: alu_result_o = alu_op1_i + alu_op2_i;         // ADD
            4'b1000: alu_result_o = alu_op1_i - alu_op2_i;           // SUB
            
            // --- Shift Operations ---
            // Only lower 5 bits of op2 are used for 32-bit shifts
            4'b0001: alu_result_o = alu_op1_i << alu_op2_i[4:0];           // SLL
            4'b0101: alu_result_o = alu_op1_i >> alu_op2_i[4:0];           // SRL
            4'b1101: alu_result_o = $signed(alu_op1_i) >>> alu_op2_i[4:0]; // SRA

            // --- Comparison Operations (Set Less Than) ---
            
            // SLT: Signed comparison
            4'b0010: begin
                if ($signed(alu_op1_i) < $signed(alu_op2_i)) 
                    alu_result_o = 32'd1;
                else 
                    alu_result_o = 32'd0;
            end

            // SLTU: Unsigned comparison
            4'b0011: begin
                if (alu_op1_i < alu_op2_i) 
                    alu_result_o = 32'd1;
                else 
                    alu_result_o = 32'd0;
            end

            // --- Bitwise Logical Operations ---
            4'b0100: alu_result_o = alu_op1_i ^ alu_op2_i;       // XOR
            4'b0110: alu_result_o = alu_op1_i | alu_op2_i;       // OR
            4'b0111: alu_result_o = alu_op1_i & alu_op2_i;       // AND
            4'b1111: alu_result_o = 32'hFFFFFFFF;                // We output all ones. This is just useful for debugging.
            // --- Default ---
            default: alu_result_o = 32'b0;
        endcase
    end

endmodule
