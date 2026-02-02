// -----------------------------------------------------------------------------
// Module: loader_unit_tb
// Description: Testbench for the DMA Code/Data Injection Engine.
//              Updated for Byte Addressing (+4) and Precise Timing Checks.
// -----------------------------------------------------------------------------

`timescale 1ns / 1ps

module loader_unit_tb;

    // -------------------------------------------------------------------------
    // 1. Mandatory Metadata & Color Palette
    // -------------------------------------------------------------------------
    localparam string FILE_NAME = "Loader Unit Testbench";
    localparam string C_RESET   = "\033[0m";
    localparam string C_RED     = "\033[1;31m";
    localparam string C_GREEN   = "\033[1;32m";
    localparam string C_BLUE    = "\033[1;34m";
    localparam string C_CYAN    = "\033[1;36m";

    // -------------------------------------------------------------------------
    // 2. Signals
    // -------------------------------------------------------------------------
    logic clk;
    logic rst_n;
    
    logic grant_i, target_select_i, done_o;
    logic [7:0] rx_data_i;
    logic       rx_ready_i;
    logic [7:0] tx_data_o;
    logic       tx_start_o, tx_done_i;

    logic        mem_write_enable_o;
    logic [31:0] mem_addr_o;
    logic [31:0] mem_data_o;

    int test_count = 0;
    int error_count = 0;

    // -------------------------------------------------------------------------
    // 3. DUT
    // -------------------------------------------------------------------------
    loader_unit dut (
        .clk_i              (clk),
        .rst_ni             (rst_n),
        .grant_i            (grant_i),
        .target_select_i    (target_select_i),
        .done_o             (done_o),
        .rx_data_i          (rx_data_i),
        .rx_ready_i         (rx_ready_i),
        .tx_data_o          (tx_data_o),
        .tx_start_o         (tx_start_o),
        .tx_done_i          (tx_done_i),
        .mem_write_enable_o (mem_write_enable_o),
        .mem_addr_o         (mem_addr_o),
        .mem_data_o         (mem_data_o)
    );

    // -------------------------------------------------------------------------
    // 4. Clock
    // -------------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk; 
    end

    // -------------------------------------------------------------------------
    // 5. Helpers
    // -------------------------------------------------------------------------
    task check(input logic [31:0] expected, input logic [31:0] observed, input string test_name);
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

    // Normal byte send (with gap delay)
    task send_byte(input logic [7:0] data);
        @(posedge clk);
        rx_data_i  <= data;
        rx_ready_i <= 1'b1;
        @(posedge clk);
        rx_ready_i <= 1'b0;
        repeat(2) @(posedge clk); // Gap
    endtask

    // Trigger byte (Returns IMMEDIATELY after latching)
    // Use this for the 4th byte to catch the Write Pulse in the next cycle.
    task send_last_byte(input logic [7:0] data);
        @(posedge clk);
        rx_data_i  <= data;
        rx_ready_i <= 1'b1;
        @(posedge clk);
        rx_ready_i <= 1'b0;
        // NO DELAY HERE: Return immediately to check S_WRITE_WORD
    endtask

    // -------------------------------------------------------------------------
    // 6. Test Sequence
    // -------------------------------------------------------------------------
    initial begin
        $display("\n%s=======================================================%s", C_CYAN, C_RESET);
        $display("%s Testbench: %-38s %s", C_CYAN, FILE_NAME, C_RESET);
        $display("%s=======================================================%s\n", C_CYAN, C_RESET);

        // Init
        grant_i = 0; target_select_i = 0; rx_data_i = 0; rx_ready_i = 0; tx_done_i = 0; rst_n = 0;
        @(posedge clk); @(posedge clk); rst_n = 1;
        $display("%s[INFO] System Reset Complete%s", C_BLUE, C_RESET);

        // Test 1: Handshake
        @(posedge clk);
        grant_i = 1;
        @(posedge clk); #1; 
        check(0, mem_addr_o, "Addr Reset on Grant");

        // Test 2: Size (2 Words)
        send_byte(8'h00); 
        send_byte(8'h02); 

        // Test 3: Payload 1
        send_byte(8'hAA); 
        send_byte(8'hBB); 
        send_byte(8'hCC); 
        send_last_byte(8'hDD); // Use the new task!

        // Now we are exactly at the start of S_WRITE_WORD
        #1; // Wait for comb logic
        
        check(1, mem_write_enable_o, "Write Enable Asserted (Word 1)");
        check(32'hDDCCBBAA, mem_data_o, "Data Assembly Correct");
        check(32'h00000000, mem_addr_o, "Write Address Correct (0x0)");

        // Test 4: Address Increment (+4 Check)
        @(posedge clk); // Move to next cycle (S_RECEIVE_BYTE)
        #1;
        check(0, mem_write_enable_o, "Write Enable De-asserted");
        check(32'h00000004, mem_addr_o, "Address Incremented by +4");

        // Test 5: Payload 2
        send_byte(8'h44); 
        send_byte(8'h33); 
        send_byte(8'h22); 
        send_last_byte(8'h11); // Trigger again

        #1; // Check write pulse
        check(1, mem_write_enable_o, "Write Enable Asserted (Word 2)");
        check(32'h11223344, mem_data_o, "Data Assembly Correct");
        check(32'h00000004, mem_addr_o, "Write Address Correct (0x4)");

        // Test 6: ACK
        @(posedge clk); // Move to S_SEND_ACK
        #1;
        check(1, tx_start_o, "TX Start Pulse Asserted");
        check(8'hF1, tx_data_o, "TX Data is ACK_FINISH");

        @(posedge clk);
        tx_done_i = 1;
        @(posedge clk);
        tx_done_i = 0;

        // Test 7: Done
        @(posedge clk); #1;
        check(1, done_o, "Done Signal to Arbiter");

        @(posedge clk);
        grant_i = 0;
        @(posedge clk); #1;
        check(0, done_o, "Done Signal Released");

        // Footer
        $display("\n%s-------------------------------------------------------%s", C_BLUE, C_RESET);
        if (error_count == 0) $display("Tests: %0d | Errors: %0d -> %sSUCCESS%s", test_count, error_count, C_GREEN, C_RESET);
        else $display("Tests: %0d | Errors: %0d -> %sFAILURE%s", test_count, error_count, C_RED, C_RESET);
        $display("%s-------------------------------------------------------%s\n", C_BLUE, C_RESET);
        
        $finish;
    end

endmodule
