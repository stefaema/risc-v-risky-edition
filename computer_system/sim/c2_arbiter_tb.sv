// -----------------------------------------------------------------------------
// Module: c2_arbiter_tb
// Description: Testbench for the Command & Control Arbiter.
// -----------------------------------------------------------------------------

module c2_arbiter_tb;

    // -------------------------------------------------------------------------
    // Metadata & Color Palette
    // -------------------------------------------------------------------------
    localparam string FILE_NAME = "C2 Arbiter TB";
    localparam string C_RESET   = "\033[0m";
    localparam string C_RED     = "\033[1;31m";
    localparam string C_GREEN   = "\033[1;32m";
    localparam string C_BLUE    = "\033[1;34m";
    localparam string C_CYAN    = "\033[1;36m";

    // -------------------------------------------------------------------------
    // Signals
    // -------------------------------------------------------------------------
    logic        clk;
    logic        rst_n;

    logic [7:0] uart_rx_data_i;
    logic        uart_rx_ready_i;
    logic [7:0] uart_tx_data_o;
    logic        uart_tx_start_o;
    logic        uart_tx_done_i;
    logic        soft_reset_o;
    logic        grant_loader_o;
    logic        loader_target_o;
    logic        loader_done_i;
    logic [7:0] loader_tx_data_i;
    logic        loader_tx_start_i;
    logic        grant_debug_o;
    logic        debug_exec_mode_o;
    logic        debug_done_i;
    logic [7:0] dumper_tx_data_i;
    logic        dumper_tx_start_i;

    int test_count  = 0;
    int error_count = 0;

    // -------------------------------------------------------------------------
    // DUT
    // -------------------------------------------------------------------------
    c2_arbiter dut (
        .clk_i             (clk),
        .rst_ni            (rst_n),
        .uart_rx_data_i    (uart_rx_data_i),
        .uart_rx_ready_i   (uart_rx_ready_i),
        .uart_tx_data_o    (uart_tx_data_o),
        .uart_tx_start_o   (uart_tx_start_o),
        .uart_tx_done_i    (uart_tx_done_i),
        .soft_reset_o      (soft_reset_o),
        .grant_loader_o    (grant_loader_o),
        .loader_target_o   (loader_target_o),
        .loader_done_i     (loader_done_i),
        .loader_tx_data_i  (loader_tx_data_i),
        .loader_tx_start_i (loader_tx_start_i),
        .grant_debug_o     (grant_debug_o),
        .debug_exec_mode_o (debug_exec_mode_o),
        .debug_done_i      (debug_done_i),
        .dumper_tx_data_i  (dumper_tx_data_i),
        .dumper_tx_start_i (dumper_tx_start_i)
    );

    // -------------------------------------------------------------------------
    // Clock
    // -------------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // -------------------------------------------------------------------------
    // Tasks
    // -------------------------------------------------------------------------
    task check(input logic [31:0] observed, input logic [31:0] expected, input string test_name);
        test_count++;
        if (observed === expected) begin
            $display("%-50s %s[PASS]%s", test_name, C_GREEN, C_RESET);
        end else begin
            $display("%-50s %s[FAIL]%s", test_name, C_RED, C_RESET);
            $display("   Expected: 0x%h", expected);
            $display("   Received: 0x%h", observed);
            error_count++;
        end
    endtask

    task check_bit(input logic observed, input logic expected, input string test_name);
        test_count++;
        if (observed === expected) begin
            $display("%-50s %s[PASS]%s", test_name, C_GREEN, C_RESET);
        end else begin
            $display("%-50s %s[FAIL]%s", test_name, C_RED, C_RESET);
            $display("   Expected: %b", expected);
            $display("   Received: %b", observed);
            error_count++;
        end
    endtask

    task send_uart_byte(input logic [7:0] byte_in);
        @(posedge clk);
        uart_rx_data_i  = byte_in;
        uart_rx_ready_i = 1;
        @(posedge clk);
        uart_rx_ready_i = 0;
        #1;
    endtask

    task run_reset();
        $display("\n%s[System Reset]%s", C_BLUE, C_RESET);
        rst_n = 0;
        uart_rx_ready_i = 0;
        uart_tx_done_i  = 0;
        loader_done_i   = 0;
        debug_done_i    = 0;
        loader_tx_start_i = 0;
        dumper_tx_start_i = 0;
        @(posedge clk); #1;
        rst_n = 1;
    endtask

    // -------------------------------------------------------------------------
    // Tests
    // -------------------------------------------------------------------------
    initial begin
        $display("\n%s=======================================================%s", C_CYAN, C_RESET);
        $display("%s Testbench: %-38s %s", C_CYAN, FILE_NAME, C_RESET);
        $display("%s=======================================================%s\n", C_CYAN, C_RESET);

        run_reset();

        // ---------------------------------------------------------------------
        // Test 1: Idle & Garbage Rejection
        // ---------------------------------------------------------------------
        $display("%s--- Test 1: Idle & Garbage Rejection ---%s", C_BLUE, C_RESET);
        send_uart_byte(8'hFF);
        check_bit(grant_loader_o, 0, "No Loader Grant");
        check_bit(grant_debug_o, 0, "No Debug Grant");
        check_bit(uart_tx_start_o, 0, "No Echo TX");

        repeat(5) @(posedge clk); 

        // ---------------------------------------------------------------------
        // Test 2: CMD_LOAD_CODE (0x1C) with Blocking ACK
        // ---------------------------------------------------------------------
        $display("\n%s--- Test 2: Loader Code Handshake (Blocking) ---%s", C_BLUE, C_RESET);
        
        // 1. Send Command
        send_uart_byte(8'h1C); 

        // 2. Verify ACK Trigger
        check_bit(uart_tx_start_o, 1, "Arbiter Triggered ACK");
        check(uart_tx_data_o, 8'h1C, "Arbiter Data is Echo");
        
        // 3. Verify Blocking Wait (BEFORE done_i)
        check_bit(grant_loader_o, 0, "NO Grant yet (Waiting for ACK)");
        
        // 4. Simulate UART Transmission Delay
        repeat(3) @(posedge clk);
        check_bit(grant_loader_o, 0, "Still NO Grant (Delaying)");

        // 5. Assert ACK Done
        uart_tx_done_i = 1;
        @(posedge clk); #1;
        uart_tx_done_i = 0;

        // 6. Verify Grant
        check_bit(grant_loader_o, 1, "Loader Granted After ACK Done");
        check_bit(loader_target_o, 0, "Loader Target = IMEM");

        // 7. Test TX Mux (Loader -> UART)
        loader_tx_data_i  = 8'hF1;
        loader_tx_start_i = 1'b1;
        @(posedge clk); #1;
        
        check(uart_tx_data_o, 8'hF1, "UART Mux Pass-Through (Loader)");
        loader_tx_start_i = 0;

        // 8. Finish & Cleanup
        loader_done_i = 1;
        @(posedge clk); #1;
        loader_done_i = 0;

        check_bit(soft_reset_o, 1, "Soft Reset Asserted");
        
        repeat(5) @(posedge clk); // CRITICAL: Wait for CLEANUP->RECOVERY->IDLE

        // ---------------------------------------------------------------------
        // Test 3: CMD_CONT_EXEC (0xCE) with Blocking ACK
        // ---------------------------------------------------------------------
        $display("\n%s--- Test 3: Debug Continuous Mode (Blocking) ---%s", C_BLUE, C_RESET);
        
        send_uart_byte(8'hCE); 

        check_bit(uart_tx_start_o, 1, "Arbiter Triggered ACK");
        check_bit(grant_debug_o, 0, "NO Grant yet (Waiting for ACK)");
        check_bit(debug_exec_mode_o, 1, "Mode Register Updated Immediately"); 


        // ---------------------------------------------------------------------
        // Summary
        // ---------------------------------------------------------------------
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
