`timescale 1ns / 1ps

module program_counter_tb;

    // TB Constants & ANSI Colors
    localparam string FILE_NAME = "PC Gamer";
    localparam string C_RESET   = "\033[0m";
    localparam string C_RED     = "\033[1;31m";
    localparam string C_GREEN   = "\033[1;32m";
    localparam string C_BLUE    = "\033[1;34m";
    localparam string C_CYAN    = "\033[1;36m";

    // DUT Signals
    logic        clk;
    logic        rst_n;
    logic        stall;
    logic [31:0] pc_in;
    logic [31:0] pc_out;

    // Statistics
    int error_count = 0;
    int test_count = 0;

    // DUT Instantiation
    program_counter dut (
        .clk    (clk),
        .rst_n  (rst_n),
        .stall  (stall),
        .pc_in  (pc_in),
        .pc_out (pc_out)
    );

    // Clock Generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 10ns period
    end

    // Verification Logic
    task check(input logic [31:0] expected, input string test_name);
        test_count++;
        if (pc_out === expected) begin
            $display("%-40s %s[PASS]%s", test_name, C_GREEN, C_RESET);
        end else begin
            $display("%-40s %s[FAIL]%s", test_name, C_RED, C_RESET);
            $display("  Expected: 0x%h", expected);
            $display("  Received: 0x%h", pc_out);
            error_count++;
        end
    endtask

    // Test Stimulus
    initial begin
        // Initialize
        rst_n = 0; // Start in Reset
        stall = 0;
        pc_in = 32'd0;

        // Header
        $display("\n%s=======================================================%s", C_CYAN, C_RESET);
        $display("%s Testbench: %-38s %s", C_CYAN, FILE_NAME, C_RESET);
        $display("%s=======================================================%s\n", C_CYAN, C_RESET);


        // Test 1: Reset Check
        @(posedge clk);
        pc_in = 32'hDEAD_BEEF; // Random input
        rst_n = 0;             // Assert Reset (Active Low)
        #1;                    // Propagate
        check(32'd0, "Reset Asserted");

        // Test 2: Normal Operation
        @(posedge clk);
        rst_n = 1;             // Release Reset
        pc_in = 32'h0000_0004; // Address 4
        
        @(posedge clk);        // Wait for clock edge to capture input
        #1;
        check(32'h0000_0004, "Standard Update");

        // Test 3: Stall Check
        // Setup input for next cycle
        pc_in = 32'h0000_0008; 
        stall = 1; 
        
        @(posedge clk);
        #1;
        check(32'h0000_0004, "Stall Active (Value Held)");

        // Test 4: Release Stall
        stall = 0;
        // pc_in is still 0x8
        
        @(posedge clk);
        #1;
        check(32'h0000_0008, "Stall Released (Value Updated)");

        // Final Summary
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
