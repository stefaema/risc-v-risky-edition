// -----------------------------------------------------------------------------
// Module: alu_operator_tb
// Description: Validation testbench for ALU Control signal decoding.
// -----------------------------------------------------------------------------

module alu_operator_tb;

    // Metadata & Colors
    localparam string FILE_NAME = "ALU OPerator";
    localparam string C_RESET   = "\033[0m";
    localparam string C_RED     = "\033[1;31m";
    localparam string C_GREEN   = "\033[1;32m";
    localparam string C_BLUE    = "\033[1;34m";
    localparam string C_CYAN    = "\033[1;36m";

    // Signals
    logic [1:0] alu_op_i;
    logic [2:0] funct3_i;
    logic       funct7_bit30_i;
    logic [3:0] alu_control_o;

    // Counters
    int test_count = 0;
    int error_count = 0;

    // DUT Instantiation
    alu_operator dut (
        .alu_op_i(alu_op_i),
        .funct3_i(funct3_i),
        .funct7_bit30_i(funct7_bit30_i),
        .alu_control_o(alu_control_o)
    );

    // Verification Task
    task check(input logic [3:0] expected, input string name);
        begin
            test_count++;
            #1; // Wait for combinational settling
            if (alu_control_o === expected) begin
                $display("%s[PASS]%s %-25s | Exp: %b | Got: %b", 
                    C_GREEN, C_RESET, name, expected, alu_control_o);
            end else begin
                error_count++;
                $display("%s[FAIL]%s %-25s | Exp: %b | Got: %b", 
                    C_RED, C_RESET, name, expected, alu_control_o);
            end
        end
    endtask

    initial begin
        // Header
        $display("\n%s=======================================================%s", C_CYAN, C_RESET);
        $display("%s Testbench: %-38s %s", C_CYAN, FILE_NAME, C_RESET);
        $display("%s=======================================================%s\n", C_CYAN, C_RESET);

        // 1. Load/Store/Jal Operations (ALUOp = 00)
        alu_op_i = 2'b00; funct3_i = 3'b000; funct7_bit30_i = 1'b1; // Bit30 should be ignored
        check(4'b0000, "LW/SW Force ADD");

        // 2. Branch Operations (ALUOp = 01)
        alu_op_i = 2'b01; funct3_i = 3'b000; funct7_bit30_i = 1'b0;
        check(4'b1000, "Branch Force SUB");

        // 3. R-Type Operations (ALUOp = 10)
        alu_op_i = 2'b10;
        
        funct3_i = 3'b000; funct7_bit30_i = 1'b0; 
        check(4'b0000, "R-Type ADD");

        funct3_i = 3'b000; funct7_bit30_i = 1'b1; 
        check(4'b1000, "R-Type SUB");

        funct3_i = 3'b111; funct7_bit30_i = 1'b0; 
        check(4'b0111, "R-Type AND");

        funct3_i = 3'b110; funct7_bit30_i = 1'b0; 
        check(4'b0110, "R-Type OR");

        funct3_i = 3'b101; funct7_bit30_i = 1'b0;
        check(4'b0101, "R-Type SRL");

        funct3_i = 3'b101; funct7_bit30_i = 1'b1;
        check(4'b1101, "R-Type SRA");

        // 4. I-Type Operations (ALUOp = 11)
        alu_op_i = 2'b11;

        funct3_i = 3'b000; funct7_bit30_i = 1'b0;
        check(4'b0000, "I-Type ADDI");

        // Critical Test: Ensure ADDI ignores bit 30 (unlike SUB)
        funct3_i = 3'b000; funct7_bit30_i = 1'b1; 
        check(4'b0000, "I-Type ADDI (Safe)");

        // I-Type Shifts (Bit 30 is used here for SRAI)
        funct3_i = 3'b101; funct7_bit30_i = 1'b1;
        check(4'b1101, "I-Type SRAI");

        // Summary
        $display("\n%s=======================================================%s", C_CYAN, C_RESET);
        if (error_count == 0)
            $display("%sSUCCESS: All %0d tests passed.%s", C_GREEN, test_count, C_RESET);
        else
            $display("%sFAILURE: %0d/%0d tests failed.%s", C_RED, error_count, test_count, C_RESET);
        $display("%s=======================================================%s\n", C_CYAN, C_RESET);

        $finish;
    end

endmodule
