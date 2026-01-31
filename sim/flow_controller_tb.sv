// -----------------------------------------------------------------------------
// Module: flow_controller_tb
// Description: Verification testbench for the Flow Control Unit.
//              Tests branch evaluation, JAL/JALR redirection, and flushing.
// -----------------------------------------------------------------------------

module flow_controller_tb;

    // 1. Mandatory Metadata & Color Palette
    localparam string FILE_NAME = "Flow Controller (Traffic Cop)";
    localparam string C_RESET = "\033[0m";
    localparam string C_RED   = "\033[1;31m";
    localparam string C_GREEN = "\033[1;32m";
    localparam string C_BLUE  = "\033[1;34m";
    localparam string C_CYAN  = "\033[1;36m";

    // Signals
    logic        is_branch_i;
    logic        is_jal_i;
    logic        is_jalr_i;
    logic [2:0]  funct3_i;
    logic        zero_i;
    logic [31:0] pc_imm_target_i;
    logic [31:0] alu_target_i;

    logic        pc_src_optn_o;
    logic        flush_req_o;
    logic [31:0] final_target_addr_o;

    // Verification Stats
    int test_count = 0;
    int error_count = 0;

    // Device Under Test (DUT)
    flow_controller dut (
        .is_branch_i      (is_branch_i),
        .is_jal_i         (is_jal_i),
        .is_jalr_i        (is_jalr_i),
        .funct3_i         (funct3_i),
        .zero_i           (zero_i),
        .pc_imm_target_i  (pc_imm_target_i),
        .alu_target_i     (alu_target_i),
        .pc_src_optn_o    (pc_src_optn_o),
        .flush_req_o      (flush_req_o),
        .final_target_addr_o (final_target_addr_o)
    );

    // 2. Visual Structure

    // A. Automated Check Task
    task check(
        input logic        exp_pc_src,
        input logic        exp_flush,
        input logic [31:0] exp_target,
        input string       test_name
    );
        test_count++;
        if (pc_src_optn_o === exp_pc_src && 
            flush_req_o === exp_flush && 
            final_target_addr_o === exp_target) begin
            $display("%-40s %s[PASS]%s", test_name, C_GREEN, C_RESET);
        end else begin
            $display("%-40s %s[FAIL]%s", test_name, C_RED, C_RESET);
            $display("   Expected: Src=%b, Flush=%b, Addr=0x%h", exp_pc_src, exp_flush, exp_target);
            $display("   Received: Src=%b, Flush=%b, Addr=0x%h", pc_src_optn_o, flush_req_o, final_target_addr_o);
            error_count++;
        end
    endtask

    // Main Test Process
    initial begin
        // B. Header Block
        $display("\n%s=======================================================%s", C_CYAN, C_RESET);
        $display("%s Testbench: %-38s %s", C_CYAN, FILE_NAME, C_RESET);
        $display("%s=======================================================%s\n", C_CYAN, C_RESET);

        // --- Test 1: No Control Transfer (Sequential Flow) ---
        
        // 1. Setup
        is_branch_i = 0; is_jal_i = 0; is_jalr_i = 0;
        funct3_i = 3'b000; zero_i = 0;
        pc_imm_target_i = 32'h0000_1000;
        alu_target_i    = 32'h0000_2000;

        // 2. Trigger
        #1;

        // 3. Check (Should not redirect, target doesn't matter much but defaults to pc_imm)
        check(1'b0, 1'b0, 32'h0000_1000, "Sequential Flow (No Branch)");

        // --- Test 2: BEQ - Not Taken (Zero Low) ---

        // 1. Setup
        is_branch_i = 1; 
        funct3_i = 3'b000; // BEQ
        zero_i = 0;        // Condition False

        // 2. Trigger
        #1;

        // 3. Check
        check(1'b0, 1'b0, 32'h0000_1000, "BEQ Not Taken (Pred Correct)");

        // --- Test 3: BEQ - Taken (Zero High) ---

        // 1. Setup
        is_branch_i = 1;
        funct3_i = 3'b000; // BEQ
        zero_i = 1;        // Condition True
        pc_imm_target_i = 32'hCAFE_BABE;

        // 2. Trigger
        #1;

        // 3. Check (Must Redirect and Flush)
        check(1'b1, 1'b1, 32'hCAFE_BABE, "BEQ Taken (Redirect + Flush)");

        // --- Test 4: BNE - Taken (Zero Low) ---

        // 1. Setup
        is_branch_i = 1;
        funct3_i = 3'b001; // BNE
        zero_i = 0;        // Condition True (Not Equal)
        pc_imm_target_i = 32'hDEAD_BEEF;

        // 2. Trigger
        #1;

        // 3. Check
        check(1'b1, 1'b1, 32'hDEAD_BEEF, "BNE Taken (Redirect + Flush)");

        // --- Test 5: BNE - Not Taken (Zero High) ---

        // 1. Setup
        is_branch_i = 1;
        funct3_i = 3'b001; // BNE
        zero_i = 1;        // Condition False (Is Equal)

        // 2. Trigger
        #1;

        // 3. Check
        check(1'b0, 1'b0, 32'hDEAD_BEEF, "BNE Not Taken (Pred Correct)");

        // --- Test 6: JAL (Unconditional Jump) ---

        // 1. Setup
        is_branch_i = 0;
        is_jal_i = 1;
        is_jalr_i = 0;
        pc_imm_target_i = 32'hAAAA_5555;

        // 2. Trigger
        #1;

        // 3. Check
        check(1'b1, 1'b1, 32'hAAAA_5555, "JAL Trigger (Unconditional)");

        // --- Test 7: JALR (Indirect Jump with Alignment) ---

        // 1. Setup
        is_jal_i = 0;
        is_jalr_i = 1;
        alu_target_i = 32'hB00B_1E35; // LSB is 1 (Odd address)
        
        // 2. Trigger
        #1;

        // 3. Check (Target comes from ALU, LSB must be cleared to 0)
        // Expected: 0xB00B_1E34
        check(1'b1, 1'b1, 32'hB00B_1E34, "JALR Trigger (LSB Masked)");


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
