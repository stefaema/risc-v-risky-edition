// -----------------------------------------------------------------------------
// Module: immediate_generator_tb
// Description: ANSI compliant testbench for the RV32I Immediate Generator
// -----------------------------------------------------------------------------

module immediate_generator_tb;
    // --- Mandatory Metadata & Color Palette ---
    localparam string FILE_NAME = "Immediate Gen-Z";
    localparam string C_RESET = "\033[0m";
    localparam string C_RED   = "\033[1;31m"; 
    localparam string C_GREEN = "\033[1;32m"; 
    localparam string C_BLUE  = "\033[1;34m"; 
    localparam string C_CYAN  = "\033[1;36m"; 

    // --- Signal Declaration ---
    logic [31:0] instr;
    logic [31:0] imm_ext;
    int test_count  = 0;
    int error_count = 0;

    // --- DUT Instantiation ---
    immediate_generator uut (
        .instruction_word_i(instr),
        .ext_immediate_o(imm_ext)
    );

    // --- Automated Check Task ---
    task check(input logic [31:0] expected, input string test_name);
        test_count++;
        if (imm_ext === expected) begin
            $display("%-40s %s[PASS]%s", test_name, C_GREEN, C_RESET);
        end else begin
            $display("%-40s %s[FAIL]%s", test_name, C_RED, C_RESET);
            $display("   Expected: 0x%h", expected);
            $display("   Received: 0x%h", imm_ext);
            error_count++;
        end
    endtask

    // --- Main Stimulus Block ---
    initial begin
        // A. Header Block
        $display("\n%s=======================================================%s", C_CYAN, C_RESET);
        $display("%s Testbench: %-38s %s", C_CYAN, FILE_NAME, C_RESET);
        $display("%s=======================================================%s\n", C_CYAN, C_RESET);

        // - Test 1: I-Type (Negative Immediate)
        instr = 32'hfff10093; 
        #1; // Wait for combinational propagation
        check(32'hffffffff, "I-Type: ADDI -1");

        // - Test 2: I-Type (Load Offset)
        instr = 32'h00a02503; 
        #1;
        check(32'h0000000a, "I-Type: LW Offset 10");

        // - Test 3: S-Type (Positive Store)
        instr = 32'h00552223; 
        #1;
        check(32'h00000004, "S-Type: SW Offset 4");

        // - Test 4: S-Type (Negative Store)
        instr = 32'hfe552ca3; 
        #1;
        check(32'hfffffff9, "S-Type: SB Offset -7");

        // - Test 5: B-Type (Backward Branch)
        instr = 32'hfe208ee3; 
        #1;
        check(32'hfffffffc, "B-Type: BEQ -4 bytes");

        // - Test 6: B-Type (Forward Branch)
        instr = 32'h00208463; 
        #1;
        check(32'h00000008, "B-Type: BNE +8 bytes");

        // - Test 7: U-Type (LUI)
        instr = 32'h12345537; 
        #1;
        check(32'h12345000, "U-Type: LUI 0x12345");

        // - Test 8: J-Type (JAL)
        instr = 32'h0010006f; 
        #1;
        check(32'h00000800, "J-Type: JAL +2048");

        // C. Summary Footer
        $display("\n%s-------------------------------------------------------%s", C_BLUE, C_RESET);
        if (error_count == 0) begin
            $display("Tests: %0d | Errors: %0d -> %sSUCCESS%s", test_count, error_count, C_GREEN, C_RESET);
        end else begin
            $display("Tests: %0d | Errors: %0d -> %sFAILURE%s", test_count, error_count, C_RED, C_RESET);
        end
        $display("%s-------------------------------------------------------%s\n", C_BLUE, C_RESET);

        $finish; // Guard against simulator hang
    end

endmodule
