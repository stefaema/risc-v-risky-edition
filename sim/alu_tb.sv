// -----------------------------------------------------------------------------
// Module: alu_tb
// Description: Final Comprehensive Verification for the ALU.
//              Tests all RV32I-required arithmetic and logical operations.
// -----------------------------------------------------------------------------

module alu_tb;

    // FILE_NAME Metadata
    localparam string FILE_NAME = "ALU-Cinate"; 

    // ANSI Colors
    localparam string C_RESET  = "\033[0m";
    localparam string C_RED    = "\033[1;31m";
    localparam string C_GREEN  = "\033[1;32m";
    localparam string C_BLUE   = "\033[1;34m";
    localparam string C_CYAN   = "\033[1;36m";

    // Signals
    logic [31:0] alu_op1_i, alu_op2_i;
    logic [3:0]  alu_operation_i;
    logic [31:0] alu_result_o;
    logic        zero_flag_o;

    // Testbench Variables
    int error_count = 0;
    int test_count  = 0;

    // DUT Instance
    alu dut (.*);

    // Assertion Task
    task check(input logic [31:0] expected, input string test_name);
        test_count++;
        if (alu_result_o === expected) begin
            $display("%-40s %s[PASS]%s", test_name, C_GREEN, C_RESET);
        end else begin
            $display("%-40s %s[FAIL]%s", test_name, C_RED, C_RESET);
            $display("   Expected: 0x%h", expected);
            $display("   Received: 0x%h", alu_result_o);
            error_count++;
        end
    endtask

    initial begin
        $display("\n%s=======================================================%s", C_CYAN, C_RESET);
        $display("%s Testbench: %-38s %s", C_CYAN, FILE_NAME, C_RESET);
        $display("%s=======================================================%s\n", C_CYAN, C_RESET);

        // --- 1. Arithmetic ---
        $display("%s>>> Testing Arithmetic (ADD/SUB) <<< %s", C_BLUE, C_RESET);
        
        // ADD Simple
        alu_operation_i = 4'b0000; alu_op1_i = 32'd50; alu_op2_i = 32'd25; 
        #1; // Wait for combinational settle
        check(32'd75, "ADD_Simple");

        // ADD Wrap
        alu_operation_i = 4'b0000; alu_op1_i = 32'hFFFFFFFF; alu_op2_i = 32'd1; 
        #1;
        check(32'd0, "ADD_Wrap");

        // SUB Simple
        alu_operation_i = 4'b1000; alu_op1_i = 32'd100; alu_op2_i = 32'd30; 
        #1;
        check(32'd70, "SUB_Simple");

        // SUB Zero
        alu_operation_i = 4'b1000; alu_op1_i = 32'd10; alu_op2_i = 32'd10; 
        #1;
        check(32'd0, "SUB_Zero_Result");
        // Manual check for zero flag for this specific case
        if (zero_flag_o !== 1'b1) begin
             $display("%-40s %s[FAIL - FLAG]%s", "SUB_Zero_Flag", C_RED, C_RESET);
             error_count++;
        end

        // --- 2. Logic Gates ---
        $display("\n%s>>> Testing Logic Gates (AND/OR/XOR) <<< %s", C_BLUE, C_RESET);
        
        // AND
        alu_operation_i = 4'b0111; alu_op1_i = 32'hF0F0F0F0; alu_op2_i = 32'h0F0F0F0F; 
        #1;
        check(32'h00000000, "AND_Logic");

        // OR
        alu_operation_i = 4'b0110; alu_op1_i = 32'hF0F0F0F0; alu_op2_i = 32'h0F0F0F0F; 
        #1;
        check(32'hFFFFFFFF, "OR_Logic");

        // XOR
        alu_operation_i = 4'b0100; alu_op1_i = 32'hFFFFFFFF; alu_op2_i = 32'hFFFFFFFF; 
        #1;
        check(32'h00000000, "XOR_Logic");

        // --- 3. Shift Operations ---
        $display("\n%s>>> Testing Shifts (SLL/SRL/SRA) <<< %s", C_BLUE, C_RESET);
        
        // SLL
        alu_operation_i = 4'b0001; alu_op1_i = 32'h00000001; alu_op2_i = 32'd4; 
        #1;
        check(32'h00000010, "SLL_4");

        // SRL
        alu_operation_i = 4'b0101; alu_op1_i = 32'h80000000; alu_op2_i = 32'd1; 
        #1;
        check(32'h40000000, "SRL_Logic");

        // SRA (Sign Extension)
        alu_operation_i = 4'b1101; alu_op1_i = 32'h80000000; alu_op2_i = 32'd1; 
        #1;
        check(32'hC0000000, "SRA_Arith");

        // --- 4. Comparisons ---
        $display("\n%s>>> Testing Comparisons (SLT/SLTU) <<< %s", C_BLUE, C_RESET);
        
        // Signed Comparison: -1 vs 1 (Expected: 1 because -1 < 1 is True)
        alu_operation_i = 4'b0010; alu_op1_i = 32'hFFFFFFFF; alu_op2_i = 32'h00000001; 
        #1;
        check(32'd1, "SLT_Signed (-1 < 1)");

        // Unsigned Comparison: MaxUInt vs 1 (Expected: 0 because Max > 1)
        alu_operation_i = 4'b0011; alu_op1_i = 32'hFFFFFFFF; alu_op2_i = 32'h00000001; 
        #1;
        check(32'd0, "SLTU_Unsign (Max > 1)");

        // --- Final Summary ---
        $display("\n%s-------------------------------------------------------%s", C_BLUE, C_RESET);
        if (error_count == 0) begin
            $display("Tests: %0d | Errors: %0d -> %sSUCCESS%s", test_count, error_count, C_GREEN, C_RESET);
        end else begin
            $display("Tests: %0d | Errors: %0d -> %sFAILURE%s", test_count, error_count, C_RED, C_RESET);
        end
        $display("%s-------------------------------------------------------%s\n", C_BLUE, C_RESET);

        $finish; 
    end
endmodule
