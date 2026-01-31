// -----------------------------------------------------------------------------
// Testbench: mux4_tb
// Description: Verification for the 4-input parameterizable mux.
// -----------------------------------------------------------------------------

module mux4_tb;

    // --- Parameters and Signals ---
    localparam int WIDTH = 32;
    localparam string FILE_NAME = "Mux: IV Edition";
    
    localparam string C_RESET = "\033[0m";
    localparam string C_RED   = "\033[1;31m";
    localparam string C_GREEN = "\033[1;32m";
    localparam string C_BLUE  = "\033[1;34m";
    localparam string C_CYAN  = "\033[1;36m";

    logic [WIDTH-1:0] d0_i, d1_i, d2_i;
    logic [1:0]       sel_i;
    logic [WIDTH-1:0] observed_signal; // data_o
    
    int test_count = 0;
    int error_count = 0;

    // --- DUT Instantiation ---
    mux4 #(.WIDTH(WIDTH)) dut (
        .d0_i  (d0_i),
        .d1_i  (d1_i),
        .d2_i  (d2_i),
        .sel_i (sel_i),
        .data_o(observed_signal)
    );

    // --- Check Task ---
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
        $display("\n%s=======================================================%s", C_CYAN, C_RESET);
        $display("%s Testbench: %-38s %s", C_CYAN, FILE_NAME, C_RESET);
        $display("%s=======================================================%s\n", C_CYAN, C_RESET);

        // Initialization
        d0_i = 32'h1111_1111;
        d1_i = 32'h2222_2222;
        d2_i = 32'h3333_3333;

        // - Test 1: Select Input 0
        sel_i = 2'b00;
        #1; // Wait for combinational logic
        check(32'h1111_1111, "Select D0 (sel=00)");

        // - Test 2: Select Input 1
        sel_i = 2'b01;
        #1; 
        check(32'h2222_2222, "Select D1 (sel=01)");

        // - Test 3: Select Input 2
        sel_i = 2'b10;
        #1; 
        check(32'h3333_3333, "Select D2 (sel=10)");

        // - Test 4: Default/Safety Case
        sel_i = 2'b11;
        #1; 
        check(32'h0000_0000, "Select Default (sel=11)");

        // --- Summary ---
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
