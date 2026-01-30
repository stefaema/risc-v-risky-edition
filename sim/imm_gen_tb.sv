// -----------------------------------------------------------------------------
// Module: imm_gen_tb
// Description: Immediate Generator Verification with ANSI Colors and Metadata
// -----------------------------------------------------------------------------

module imm_gen_tb;

    // Metadata & Formatting
    localparam string FILE_NAME = "Immediate Gen-Z";
    
    localparam string C_RESET  = "\033[0m";
    localparam string C_RED    = "\033[1;31m"; 
    localparam string C_GREEN  = "\033[1;32m"; 
    localparam string C_YELLOW = "\033[1;33m"; 
    localparam string C_BLUE   = "\033[1;34m"; 
    localparam string C_CYAN   = "\033[1;36m"; 

    // Signal Declaration
    logic [31:0] instr;
    logic [31:0] imm_ext;

    // Checking variables
    logic [31:0] ExpectedImm;
    int          error_count = 0;
    int          test_count  = 0;

    // Instantiate the DUT
    imm_gen uut (
        .instr(instr),
        .imm_ext(imm_ext)
    );

    // Task: Check Output
    task check(input string type_name);
        begin
            #5; // Delay for combinational logic
            if (imm_ext !== ExpectedImm) begin
                $display("%s[FAIL]%s %-15s | Instr: 0x%h | Exp: 0x%h | Got: 0x%h", 
                    C_RED, C_RESET, type_name, instr, ExpectedImm, imm_ext);
                error_count++;
            end else begin
                $display("%s[PASS]%s %-15s | Instr: 0x%h | Imm: 0x%h", 
                    C_GREEN, C_RESET, type_name, instr, imm_ext);
            end
            test_count++;
        end
    endtask

    // Main Stimulus
    initial begin
        // Pretty Header
        $display("\n%s=======================================================%s", C_CYAN, C_RESET);
        $display("%s Testbench: %-38s %s", C_CYAN, FILE_NAME, C_RESET);
        $display("%s=======================================================%s\n", C_CYAN, C_RESET);

        // --- I-Type Tests ---
        $display("%s--- Testing I-Type ---%s", C_BLUE, C_RESET);
        instr = 32'hfff10093; ExpectedImm = 32'hffffffff; check("I_Neg");
        instr = 32'h00a02503; ExpectedImm = 32'h0000000a; check("I_Load");

        // --- S-Type Tests ---
        $display("\n%s--- Testing S-Type ---%s", C_BLUE, C_RESET);
        instr = 32'h00552223; ExpectedImm = 32'h00000004; check("S_Pos");
        instr = 32'hfe552ca3; ExpectedImm = 32'hfffffff9; check("S_Neg");

        // --- B-Type Tests ---
        $display("\n%s--- Testing B-Type ---%s", C_BLUE, C_RESET);
        instr = 32'hfe208ee3; ExpectedImm = 32'hfffffffc; check("B_Neg");
        instr = 32'h00208463; ExpectedImm = 32'h00000008; check("B_Pos");

        // --- U-Type Tests ---
        $display("\n%s--- Testing U-Type ---%s", C_BLUE, C_RESET);
        instr = 32'h12345537; ExpectedImm = 32'h12345000; check("U_LUI");

        // --- J-Type Tests ---
        $display("\n%s--- Testing J-Type ---%s", C_BLUE, C_RESET);
        instr = 32'h0010006f; ExpectedImm = 32'h00000800; check("J_Pos");

        // Summary
        $display("\n%s=======================================================%s", C_CYAN, C_RESET);
        if (error_count == 0) begin
            $display("%s        [SUCCESS] All %0d ImmGen tests passed!       %s", C_GREEN, test_count, C_RESET);
        end else begin
            $display("%s        [FAILURE] %0d errors found in %0d tests.      %s", C_RED, error_count, test_count, C_RESET);
        end
        $display("%s=======================================================%s\n", C_CYAN, C_RESET);
        
        $finish;
    end

endmodule
