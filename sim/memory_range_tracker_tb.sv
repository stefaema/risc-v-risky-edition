// -----------------------------------------------------------------------------
// Module: memory_range_tracker_tb
// Description: Testbench for the dirty memory range tracker.
// -----------------------------------------------------------------------------

`timescale 1ns / 1ps

module memory_range_tracker_tb;

    // 1. Mandatory Metadata & Color Palette
    localparam string FILE_NAME = "The Memory Stalker";
    localparam string C_RESET = "\033[0m";
    localparam string C_RED   = "\033[1;31m"; 
    localparam string C_GREEN = "\033[1;32m"; 
    localparam string C_BLUE  = "\033[1;34m"; 
    localparam string C_CYAN  = "\033[1;36m"; 

    // Test Signals
    logic        clk;
    logic        global_flush_i;
    logic        mem_write_en;
    logic [31:0] addr_in_use_i;
    logic [31:0] min_addr_o;
    logic [31:0] max_addr_o;

    // Benchmarking
    int test_count = 0;
    int error_count = 0;

    // DUT Instantiation
    memory_range_tracker dut (
        .clk(clk),
        .global_flush_i(global_flush_i),
        .mem_write_en(mem_write_en),
        .addr_in_use_i(addr_in_use_i),
        .min_addr_o(min_addr_o),
        .max_addr_o(max_addr_o)
    );

    // --- Clock Generation ---
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // --- Automated Check Task ---
    // Adapted slightly to accept observed signal as an argument 
    // since we need to check two different output ports.
    task check(input logic [31:0] observed, input logic [31:0] expected, input string test_name);
        test_count++;
        if (observed === expected) begin
            $display("%-40s %s[PASS]%s", test_name, C_GREEN, C_RESET);
        end else begin
            $display("%-40s %s[FAIL]%s", test_name, C_RED, C_RESET);
            $display("   Expected: 0x%h", expected);
            $display("   Received: 0x%h", observed);
            error_count++;
        end
    endtask

    // --- Main Test Process ---
    initial begin
        // 2. Visual Structure: Header Block
        $display("\n%s=======================================================%s", C_CYAN, C_RESET);
        $display("%s Testbench: %-38s %s", C_CYAN, FILE_NAME, C_RESET);
        $display("%s=======================================================%s\n", C_CYAN, C_RESET);

        // --- Test 1: Reset Initialization ---
        
        // 1. Setup
        @(posedge clk);
        global_flush_i = 1;
        mem_write_en = 0;
        addr_in_use_i = 32'h0000_0000;

        // 2. Trigger
        @(posedge clk);
        #1; // Wait for settlement

        // 3. Check
        check(min_addr_o, 32'hFFFF_FFFF, "Reset: Min defaults to Max Int");
        check(max_addr_o, 32'h0000_0000, "Reset: Max defaults to 0");
        
        global_flush_i = 0; // Release reset for future tests

        // --- Test 2: First Write (Sets Baseline) ---
        
        // 1. Setup
        @(posedge clk);
        mem_write_en = 1;
        addr_in_use_i = 32'h0000_1000;

        // 2. Trigger
        @(posedge clk);
        #1; 

        // 3. Check
        check(min_addr_o, 32'h0000_1000, "First Write: Min captures value");
        check(max_addr_o, 32'h0000_1000, "First Write: Max captures value");

        // --- Test 3: Write Lower Address (Updates Min) ---
        
        // 1. Setup
        @(posedge clk);
        mem_write_en = 1;
        addr_in_use_i = 32'h0000_0100;

        // 2. Trigger
        @(posedge clk);
        #1; 

        // 3. Check
        check(min_addr_o, 32'h0000_0100, "Lower Write: Min Updates");
        check(max_addr_o, 32'h0000_1000, "Lower Write: Max Hold");

        // --- Test 4: Write Higher Address (Updates Max) ---
        
        // 1. Setup
        @(posedge clk);
        mem_write_en = 1;
        addr_in_use_i = 32'h0000_2000;

        // 2. Trigger
        @(posedge clk);
        #1; 

        // 3. Check
        check(min_addr_o, 32'h0000_0100, "Higher Write: Min Hold");
        check(max_addr_o, 32'h0000_2000, "Higher Write: Max Updates");

        // --- Test 5: Write Within Range (Updates Neither) ---
        
        // 1. Setup
        @(posedge clk);
        mem_write_en = 1;
        addr_in_use_i = 32'h0000_1500;

        // 2. Trigger
        @(posedge clk);
        #1; 

        // 3. Check
        check(min_addr_o, 32'h0000_0100, "Inner Write: Min Hold");
        check(max_addr_o, 32'h0000_2000, "Inner Write: Max Hold");

        // --- Test 6: Write Disabled (Ignored) ---
        
        // 1. Setup
        @(posedge clk);
        mem_write_en = 0;
        addr_in_use_i = 32'hFFFF_0000; // Should trigger Max if enabled

        // 2. Trigger
        @(posedge clk);
        #1; 

        // 3. Check
        check(min_addr_o, 32'h0000_0100, "Disabled: Min Unchanged");
        check(max_addr_o, 32'h0000_2000, "Disabled: Max Unchanged");

        // --- Test 7: Synchronous Reset Check ---
        
        // 1. Setup
        @(posedge clk);
        global_flush_i = 1;
        mem_write_en = 1; // Try to write during reset
        addr_in_use_i = 32'h8000_0000;

        // 2. Trigger
        @(posedge clk);
        #1; 

        // 3. Check
        check(min_addr_o, 32'hFFFF_FFFF, "Sync Reset: Min Reset");
        check(max_addr_o, 32'h0000_0000, "Sync Reset: Max Reset");

        // 2. Visual Structure: Summary Footer
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
