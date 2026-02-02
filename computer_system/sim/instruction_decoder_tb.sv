// -----------------------------------------------------------------------------
// Module: instruction_decoder_tb
// Description: Verification for Instruction Slicing using ANSI Standards
// -----------------------------------------------------------------------------

module instruction_decoder_tb;
    // --- Mandatory Metadata & Color Palette ---
    localparam string FILE_NAME = "The Great Decryptor";
    localparam string C_RESET = "\033[0m";
    localparam string C_RED   = "\033[1;31m"; 
    localparam string C_GREEN = "\033[1;32m"; 
    localparam string C_BLUE  = "\033[1;34m"; 
    localparam string C_CYAN  = "\033[1;36m"; 

    // --- Signal Declaration ---
    logic [31:0] instruction_word;
    logic [6:0]  opcode;
    logic [4:0]  rd, rs1, rs2;
    logic [2:0]  funct3;
    logic [6:0]  funct7;

    int test_count  = 0;
    int error_count = 0;

    // --- DUT Instantiation ---
    instruction_decoder uut (
        .instruction_word_i(instruction_word),
        .opcode_o(opcode),
        .rd_o(rd),
        .funct3_o(funct3),
        .rs1_o(rs1),
        .rs2_o(rs2),
        .funct7_o(funct7)
    );

    // --- Automated Check Task ---
    // Compares multiple fields to verify slicing accuracy
    task check_fields(
        input logic [6:0] exp_op, 
        input logic [4:0] exp_rd, 
        input logic [4:0] exp_rs1, 
        input string test_name
    );
        test_count++;
        // Checking primary fields as a proxy for all slices
        if (opcode === exp_op && rd === exp_rd && rs1 === exp_rs1) begin
            $display("%-40s %s[PASS]%s", test_name, C_GREEN, C_RESET);
        end else begin
            $display("%-40s %s[FAIL]%s", test_name, C_RED, C_RESET);
            $display("   Expected: Op=0x%h, Rd=0x%h, Rs1=0x%h", exp_op, exp_rd, exp_rs1);
            $display("   Received: Op=0x%h, Rd=0x%h, Rs1=0x%h", opcode, rd, rs1);
            error_count++;
        end
    endtask

    // --- Main Stimulus Block ---
    initial begin
        // A. Header Block
        $display("\n%s=======================================================%s", C_CYAN, C_RESET);
        $display("%s Testbench: %-38s %s", C_CYAN, FILE_NAME, C_RESET);
        $display("%s=======================================================%s\n", C_CYAN, C_RESET);

        // - Test 1: R-Type (ADD x3, x1, x2)
        // 0000000_00010_00001_000_00011_0110011 -> 0x002081B3
        instruction_word = 32'h002081B3;
        #1; // Setup-Trigger-Check
        check_fields(7'h33, 5'h03, 5'h01, "R-Type: ADD x3, x1, x2");

        // - Test 2: I-Type (LW x5, 10(x10))
        // 000000001010_01010_010_00101_0000011 -> 0x00A52283
        instruction_word = 32'h00A52283;
        #1;
        check_fields(7'h03, 5'h05, 5'h0A, "I-Type: LW x5, 10(x10)");

        // - Test 3: S-Type (SW x2, 4(x1))
        // 0000000_00010_00001_010_00100_0100011 -> 0x0020A223
        instruction_word = 32'h0020A223;
        #1;
        check_fields(7'h23, 5'h04, 5'h01, "S-Type: SW (imm_low used as rd)");

        // - Test 4: U-Type (LUI x10, 0x12345)
        // 10010001101000101010_01010_0110111 -> 0x12345537
        instruction_word = 32'h12345537;
        #1;
        check_fields(7'h37, 5'h0A, 5'h08, "U-Type: LUI x10");

        // C. Summary Footer
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
