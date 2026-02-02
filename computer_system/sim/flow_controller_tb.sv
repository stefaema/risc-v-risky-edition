// -----------------------------------------------------------------------------
// Module: flow_controller_tb
// Description: Verification testbench for the Flow Control Unit.
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
    logic        is_halt_i;    
    logic [2:0]  funct3_i;
    logic        zero_i;
    logic [31:0] pc_imm_target_i;
    logic [31:0] alu_target_i;

    logic        pc_src_optn_o;
    logic        redirect_req_o;  
    logic        halt_detected_o; 
    logic [31:0] final_target_addr_o;

    // Verification Stats
    int test_count = 0;
    int error_count = 0;

    // Device Under Test (DUT)
    flow_controller dut (
        .is_branch_i      (is_branch_i),
        .is_jal_i         (is_jal_i),
        .is_jalr_i        (is_jalr_i),
        .is_halt_i        (is_halt_i),
        .funct3_i         (funct3_i),
        .zero_i           (zero_i),
        .pc_imm_target_i  (pc_imm_target_i),
        .alu_target_i     (alu_target_i),
        .pc_src_optn_o    (pc_src_optn_o),
        .redirect_req_o   (redirect_req_o),
        .halt_detected_o  (halt_detected_o),
        .final_target_addr_o (final_target_addr_o)
    );

    // 2. Visual Structure

    // A. Automated Check Task
    task check(
        input logic        exp_pc_src,
        input logic        exp_redirect,
        input logic        exp_halt,
        input logic [31:0] exp_target,
        input string       test_name
    );
        test_count++;
        if (pc_src_optn_o       === exp_pc_src && 
            redirect_req_o      === exp_redirect && 
            halt_detected_o     === exp_halt &&
            final_target_addr_o === exp_target) begin
            $display("%-40s %s[PASS]%s", test_name, C_GREEN, C_RESET);
        end else begin
            $display("%-40s %s[FAIL]%s", test_name, C_RED, C_RESET);
            $display("   Expected: Src=%b, Redirect=%b, Halt=%b, Addr=0x%h", exp_pc_src, exp_redirect, exp_halt, exp_target);
            $display("   Received: Src=%b, Redirect=%b, Halt=%b, Addr=0x%h", pc_src_optn_o, redirect_req_o, halt_detected_o, final_target_addr_o);
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
        is_branch_i = 0; is_jal_i = 0; is_jalr_i = 0; is_halt_i = 0;
        funct3_i = 3'b000; zero_i = 0;
        pc_imm_target_i = 32'h0000_1000;
        alu_target_i    = 32'h0000_2000;
        #1;
        // 3. Check (No redirect, No halt)
        check(1'b0, 1'b0, 1'b0, 32'h0000_1000, "Sequential Flow");

        // --- Test 2: BEQ - Not Taken (Zero Low) ---
        is_branch_i = 1; 
        funct3_i = 3'b000; // BEQ
        zero_i = 0;        // False
        #1;
        check(1'b0, 1'b0, 1'b0, 32'h0000_1000, "BEQ Not Taken");

        // --- Test 3: BEQ - Taken (Zero High) ---
        is_branch_i = 1;
        funct3_i = 3'b000; // BEQ
        zero_i = 1;        // True
        pc_imm_target_i = 32'hCAFE_BABE;
        #1;
        // Check (Redirect=1, PC_Src=1)
        check(1'b1, 1'b1, 1'b0, 32'hCAFE_BABE, "BEQ Taken");

        // --- Test 4: JAL (Unconditional Jump) ---
        is_branch_i = 0; is_jal_i = 1;
        pc_imm_target_i = 32'hAAAA_5555;
        #1;
        check(1'b1, 1'b1, 1'b0, 32'hAAAA_5555, "JAL Trigger");

        // --- Test 5: SYSTEM HALT (Normal) ---
        is_branch_i = 0; is_jal_i = 0;
        is_halt_i = 1; // ECALL
        #1;
        // Redirect=0, Halt=1, PC_Src=0 (Do not jump, just freeze later)
        check(1'b0, 1'b0, 1'b1, 32'hAAAA_5555, "System Halt (Stand-alone)");

        is_halt_i = 0; is_branch_i = 0;

        // --- Test 6: JALR (Indirect Jump with Alignment) ---
        is_jalr_i = 1;
        alu_target_i = 32'hB00B_1E35; // LSB is 1
        #1;
        // Check (Target comes from ALU, LSB masked to 0) -> 0xB00B_1E34
        check(1'b1, 1'b1, 1'b0, 32'hB00B_1E34, "JALR Trigger (LSB Masked)");

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
