// -----------------------------------------------------------------------------
// Module: pipeline_register_tb
// Description: Verification for the generic pipeline register flow control.
// -----------------------------------------------------------------------------

module pipeline_register_tb;

    // --- Verification Constants ---
    localparam string FILE_NAME = "Pipeline Not-a-Latch";
    localparam string C_RESET = "\033[0m";
    localparam string C_RED   = "\033[1;31m";
    localparam string C_GREEN = "\033[1;32m";
    localparam string C_BLUE  = "\033[1;34m";
    localparam string C_CYAN  = "\033[1;36m";

    // --- DUT Parameters ---
    localparam int WIDTH = 32;

    // --- Signals ---
    logic             clk;
    logic             rst_n;
    logic             flush_i;
    logic             write_en_i;
    logic             global_stall_i;
    logic             global_flush_i;
    logic [WIDTH-1:0] data_i;
    logic [WIDTH-1:0] data_o;

    // --- Statistics ---
    int test_count  = 0;
    int error_count = 0;

    // --- DUT Instantiation ---
    pipeline_register #(
        .WIDTH(WIDTH)
    ) dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .flush_i (flush_i),
        .global_flush_i (global_flush_i),
        .write_en_i (write_en_i),
        .global_stall_i (global_stall_i),
        .data_i  (data_i),
        .data_o  (data_o)
    );

    // --- Clock Generation ---
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 10ns Period
    end

    // --- Check Task ---
    task check(input logic [WIDTH-1:0] expected, input string test_name);
        test_count++;
        if (data_o === expected) begin
            $display("%-40s %s[PASS]%s", test_name, C_GREEN, C_RESET);
        end else begin
            $display("%-40s %s[FAIL]%s", test_name, C_RED, C_RESET);
            $display("   Expected: 0x%h", expected);
            $display("   Received: 0x%h", data_o);
            error_count++;
        end
    endtask

    // --- Test Stimulus ---
    initial begin
        // A. Header Block
        $display("\n%s=======================================================%s", C_CYAN, C_RESET);
        $display("%s Testbench: %-38s %s", C_CYAN, FILE_NAME, C_RESET);
        $display("%s=======================================================%s\n", C_CYAN, C_RESET);

        // --- Test 1: Initialization & Asynchronous Reset ---
        rst_n   = 0;
        flush_i = 0;
        global_stall_i = 0;
        global_flush_i = 0;
        write_en_i = 1;
        data_i  = 32'hDEAD_BEEF;
        
        #1; // Wait for async reset
        check(32'h0000_0000, "Asynchronous Reset State");

        @(posedge clk);
        rst_n = 1;
        #1; // Golden Delta

        // --- Test 2: Standard Write (Happy Path) ---
        // Scenario: No stall, no flush. Data should pass through.
        data_i  = 32'hCAFE_BABE;
        
        @(posedge clk);
        #1;
        check(32'hCAFE_BABE, "Standard Write Operation");

        // --- Test 3: Stall Behavior (Hold State) ---
        // Scenario: Stall is HIGH. Input changes, output should NOT change.
        global_stall_i = 1;         // Freeze!
        data_i  = 32'h1234_5678; // New data trying to enter
        
        @(posedge clk);
        #1;
        check(32'hCAFE_BABE, "Stall Logic (Hold Value)");

        // --- Test 4: Stall Release ---
        // Scenario: Stall released. The pending data (0x12345678) should now load.
        global_stall_i = 0;
        
        @(posedge clk);
        #1;
        check(32'h1234_5678, "Stall Release (Update Value)");

        // --- Test 5: Synchronous Flush ---
        // Scenario: Flush is HIGH. Output should zero out on clock edge.
        flush_i = 1;
        data_i  = 32'hFFFF_FFFF;
        
        @(posedge clk);
        #1;
        check(32'h0000_0000, "Synchronous Flush (Clear)");

        // --- Test 6: Priority Check (Flush vs Stall) ---
        // Scenario: BOTH Flush and Stall are active. Flush should win.
        flush_i = 1;
        global_stall_i = 1;
        data_i  = 32'hAAAA_BBBB;
        
        // First, ensure we have non-zero data to flush
        // Force reset/set logic manually for setup
        rst_n = 0; #1; rst_n = 1; 
        force dut.data_o = 32'h1111_2222; 
        #1;
        release dut.data_o;

        @(posedge clk);
        #1;
        check(32'h0000_0000, "Priority: Flush overrides Stall");

        // --- Cleanup ---
        flush_i = 0;
        global_stall_i = 0;
        @(posedge clk);

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
