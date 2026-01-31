`timescale 1ns / 1ps

// -----------------------------------------------------------------------------
// Module: adder_tb
// Description: Verification for the 32-bit adder component.
// -----------------------------------------------------------------------------

module adder_tb;

    // --- Mandatory Metadata & Color Palette ---
    localparam string FILE_NAME = "Adder-all";
    localparam string C_RESET = "\033[0m";
    localparam string C_RED   = "\033[1;31m";
    localparam string C_GREEN = "\033[1;32m";
    localparam string C_BLUE  = "\033[1;34m";
    localparam string C_CYAN  = "\033[1;36m";

    // --- DUT Signals ---
    logic [31:0] op1_i;
    logic [31:0] op2_i;
    logic [31:0] observed_signal; // sum_o

    int error_count = 0;
    int test_count  = 0;

    // --- DUT Instantiation ---
    adder dut (
        .adder_op1_i (op1_i),
        .adder_op2_i (op2_i),
        .sum_o       (observed_signal)
    );

    // --- Automated Check Task ---
    task check(input logic [31:0] expected, input string test_name);
        test_count++;
        if (observed_signal === expected) begin
            $display("%-40s %s[PASS]%s", test_name, C_GREEN, C_RESET);
        end else begin
            $display("%-40s %s[FAIL]%s", test_name, C_RED, C_RESET);
            $display("   Expected: 0x%h", expected);
            $display("   Received: 0x%h", observed_signal);
            error_count++;
        end
    endtask

    // --- Main Simulation ---
    initial begin
        // A. Header Block
        $display("\n%s=======================================================%s", C_CYAN, C_RESET);
        $display("%s Testbench: %-38s %s", C_CYAN, FILE_NAME, C_RESET);
        $display("%s=======================================================%s\n", C_CYAN, C_RESET);

        // --- Test Cases ---

        // - Test 1: Simple Addition
        op1_i = 32'd10;
        op2_i = 32'd20;
        #1; // Sampling window for combinational logic
        check(32'd30, "Simple Addition (10 + 20)");

        // - Test 2: PC Increment Simulation
        op1_i = 32'h0000_1000;
        op2_i = 32'd4;
        #1;
        check(32'h0000_1004, "PC Increment (PC + 4)");

        // - Test 3: Large Values (Overflow Wrap)
        op1_i = 32'hFFFF_FFFF; 
        op2_i = 32'd1;
        #1;
        check(32'h0000_0000, "Maximum Wrap-around");

        // - Test 4: Branch Offset Simulation
        op1_i = 32'h0000_2000;
        op2_i = 32'hFFFF_FFFC; // -4 in 2's complement
        #1;
        check(32'h0000_1FFC, "Negative Offset (PC - 4)");

        // - Test 5: Zero Check
        op1_i = 32'd0;
        op2_i = 32'd0;
        #1;
        check(32'd0, "Zero Addition");

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
