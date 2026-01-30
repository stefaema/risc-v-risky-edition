// -----------------------------------------------------------------------------
// Module: alu_tb
// Description: Final Comprehensive Verification for the ALU-cinate.
//              Tests all RV32I-required arithmetic and logical operations.
// -----------------------------------------------------------------------------

module alu_tb;

    // FILE_NAME Metadata
    localparam string FILE_NAME = "ALU-cinate";

    // ANSI Colors
    localparam string C_RESET  = "\033[0m";
    localparam string C_RED    = "\033[1;31m";
    localparam string C_GREEN  = "\033[1;32m";
    localparam string C_YELLOW = "\033[1;33m";
    localparam string C_BLUE   = "\033[1;34m";
    localparam string C_CYAN   = "\033[1;36m";

    // Signals
    logic [31:0] SrcA, SrcB;
    logic [3:0]  ALUControl;
    logic [31:0] ALUResult;
    logic        Zero;

    logic [31:0] ExpectedResult;
    int          error_count = 0;
    int          test_count  = 0;

    // DUT Instance
    alu dut (.*);

    // Assertion Task
    task check(input string op_name);
        begin
            #5; 
            if (ALUResult !== ExpectedResult) begin
                $display("%s[FAIL]%s [%0t] %-15s | A: 0x%h | B: 0x%h | Exp: 0x%h | Got: 0x%h", 
                    C_RED, C_RESET, $time, op_name, SrcA, SrcB, ExpectedResult, ALUResult);
                error_count++;
            end else begin
                $display("%s[PASS]%s [%0t] %-15s | Result: 0x%h | Zero: %b", 
                    C_GREEN, C_RESET, $time, op_name, ALUResult, Zero);
            end
            test_count++;
        end
    endtask

    initial begin
        $display("\n%s=======================================================%s", C_CYAN, C_RESET);
        $display("%s Testbench: %-38s %s", C_CYAN, FILE_NAME, C_RESET);
        $display("%s=======================================================%s\n", C_CYAN, C_RESET);

        // --- 1. Arithmetic ---
        $display("%s>>> Testing Arithmetic (ADD/SUB) <<< %s", C_BLUE, C_RESET);
        ALUControl = 4'b0000; SrcA = 32'd50;  SrcB = 32'd25; ExpectedResult = 32'd75; check("ADD_Simple");
        ALUControl = 4'b0000; SrcA = 32'hFFFFFFFF; SrcB = 32'd1; ExpectedResult = 32'd0; check("ADD_Wrap");
        ALUControl = 4'b1000; SrcA = 32'd100; SrcB = 32'd30; ExpectedResult = 32'd70; check("SUB_Simple");
        ALUControl = 4'b1000; SrcA = 32'd10;  SrcB = 32'd10; ExpectedResult = 32'd0;  check("SUB_Zero");

        // --- 2. Logic Gates ---
        $display("\n%s>>> Testing Logic Gates (AND/OR/XOR) <<< %s", C_BLUE, C_RESET);
        ALUControl = 4'b0111; SrcA = 32'hF0F0F0F0; SrcB = 32'h0F0F0F0F; ExpectedResult = 32'h00000000; check("AND_Logic");
        ALUControl = 4'b0110; SrcA = 32'hF0F0F0F0; SrcB = 32'h0F0F0F0F; ExpectedResult = 32'hFFFFFFFF; check("OR_Logic");
        ALUControl = 4'b0100; SrcA = 32'hFFFFFFFF; SrcB = 32'hFFFFFFFF; ExpectedResult = 32'h00000000; check("XOR_Logic");

        // --- 3. Shift Operations ---
        $display("\n%s>>> Testing Shifts (SLL/SRL/SRA) <<< %s", C_BLUE, C_RESET);
        ALUControl = 4'b0001; SrcA = 32'h00000001; SrcB = 32'd4; ExpectedResult = 32'h00000010; check("SLL_4");
        ALUControl = 4'b0101; SrcA = 32'h80000000; SrcB = 32'd1; ExpectedResult = 32'h40000000; check("SRL_Logic");
        ALUControl = 4'b1101; SrcA = 32'h80000000; SrcB = 32'd1; ExpectedResult = 32'hC0000000; check("SRA_Arith");

        // --- 4. Comparisons ---
        $display("\n%s>>> Testing Comparisons (SLT/SLTU) <<< %s", C_BLUE, C_RESET);
        // Signed Comparison: -1 vs 1
        ALUControl = 4'b0010; SrcA = 32'hFFFFFFFF; SrcB = 32'h00000001; ExpectedResult = 32'd1; check("SLT_Signed");
        // Unsigned Comparison: MaxUInt vs 1
        ALUControl = 4'b0011; SrcA = 32'hFFFFFFFF; SrcB = 32'h00000001; ExpectedResult = 32'd0; check("SLTU_Unsign");

        // --- Final Summary ---
        $display("\n%s=======================================================%s", C_CYAN, C_RESET);
        if (error_count == 0) begin
            $display("%s   [SUCCESS] All %0d ALU tests passed! %s", C_GREEN, test_count, C_RESET);
            $display("   Project Status: %sALU-CINATION COMPLETE%s", C_YELLOW, C_RESET);
        end else begin
            $display("%s   [FAILURE] %0d errors found in %0d tests. %s", C_RED, error_count, test_count, C_RESET);
        end
        $display("%s=======================================================%s\n", C_CYAN, C_RESET);

        $finish; 
    end
endmodule
