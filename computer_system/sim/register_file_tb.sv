`timescale 1ns / 1ps

module register_file_tb;

    // --- Metadata & Constants ---
    localparam string FILE_NAME = "The Register's Gambit";
    localparam string C_RESET    = "\033[0m";
    localparam string C_RED      = "\033[1;31m"; 
    localparam string C_GREEN    = "\033[1;32m"; 
    localparam string C_BLUE     = "\033[1;34m"; 
    localparam string C_CYAN     = "\033[1;36m"; 

    // --- DUT Signals ---
    logic        clk;
    logic        rst_n;
    logic [4:0]  rs1_addr_i, rs2_addr_i, rd_addr_i, rs_dbg_addr_i;
    logic [31:0] write_data_i;
    logic        reg_write_en;
    logic [31:0] rs1_data_o, rs2_data_o, rs_dbg_data_o;

    int test_count = 0;
    int error_count = 0;

    // Explicitly using .* to match DUT ports
    register_file uut (.*); 

    // --- Clock Generation ---
    initial begin
        clk = 0; 
        forever #5 clk = ~clk; 
    end

    // --- Automated Check Task ---
    task check(input logic [31:0] expected, input logic [31:0] actual, input string test_name);
        test_count++;
        if (actual === expected) begin
            $display("%-40s %s[PASS]%s", test_name, C_GREEN, C_RESET);
        end else begin
            $display("%-40s %s[FAIL]%s", test_name, C_RED, C_RESET);
            $display("    Expected: 0x%h", expected);
            $display("    Received: 0x%h", actual);
            error_count++;
        end
    endtask

    // --- Main Stimulus ---
    initial begin
        // Header Block
        $display("\n%s=======================================================%s", C_CYAN, C_RESET);
        $display("%s Testbench: %-38s %s", C_CYAN, FILE_NAME, C_RESET);
        $display("%s=======================================================%s\n", C_CYAN, C_RESET);

        $display("%s[TEST PHASE 1] Initialization & Reset%s", C_BLUE, C_RESET);
        rst_n = 0;
        reg_write_en = 0;
        rs1_addr_i = 0; rs2_addr_i = 0; rd_addr_i = 0; write_data_i = 0;
        rs_dbg_addr_i = 0;
        #15; 
        rst_n = 1;
        
        // - Test 1: Reset State
        rs1_addr_i = 1;
        #1; 
        check(32'h0, rs1_data_o, "Check Reset State (x1)");

        $display("\n%s[TEST PHASE 2] Write & Read Operations%s", C_BLUE, C_RESET);
        
        // - Test 2: Single Write/Read
        // Setup: Prepare write
        @(posedge clk);
        rd_addr_i = 1;
        write_data_i = 32'hDEADBEEF;
        reg_write_en = 1;
        
        // Trigger: Write happens at negedge. Setup Read for next check.
        @(posedge clk); 
        reg_write_en = 0;
        rs1_addr_i = 1; // Set read address NOW
        #1;             // WAIT for logic to settle
        check(32'hDEADBEEF, rs1_data_o, "Read x1 after Write");

        // - Test 3: Dual Port Read
        // Setup: Write second value
        @(posedge clk);
        rd_addr_i = 2;
        write_data_i = 32'hCAFEBABE;
        reg_write_en = 1;

        // Trigger: Wait for write, set up Dual Read
        @(posedge clk);
        reg_write_en = 0;
        rs1_addr_i = 1; // Read Port 1 -> x1 (DEADBEEF)
        rs2_addr_i = 2; // Read Port 2 -> x2 (CAFEBABE)
        #1;             // WAIT for logic to settle
        check(32'hDEADBEEF, rs1_data_o, "Dual Read Port 1 (x1)");
        check(32'hCAFEBABE, rs2_data_o, "Dual Read Port 2 (x2)");

        $display("\n%s[TEST PHASE 3] x0 Invariant Check%s", C_BLUE, C_RESET);
        
        // - Test 4: x0 Hardwired to Zero
        // Setup: Try writing garbage to x0
        @(posedge clk);
        rd_addr_i = 0;
        write_data_i = 32'hFFFFFFFF;
        reg_write_en = 1;
        
        // Trigger: Set read addr to x0
        @(posedge clk);
        reg_write_en = 0;
        rs1_addr_i = 0; // Set read addr to x0
        #1;             // WAIT for logic to settle
        check(32'h0, rs1_data_o, "Write to x0 Ignored");

        // Summary Footer
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
