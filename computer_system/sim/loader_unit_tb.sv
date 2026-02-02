// -----------------------------------------------------------------------------
// Module: loader_unit_tb
// Description: Testbench for the Loader Unit (DMA Engine).
//              Verifies UART packet reassembly, memory writing, and handshakes.
// -----------------------------------------------------------------------------

module loader_unit_tb;

    // -------------------------------------------------------------------------
    // 1. Mandatory Metadata & Color Palette
    // -------------------------------------------------------------------------
    localparam string FILE_NAME = "Absolute Unit of a Loader";
    localparam string C_RESET   = "\033[0m";
    localparam string C_RED     = "\033[1;31m";
    localparam string C_GREEN   = "\033[1;32m";
    localparam string C_BLUE    = "\033[1;34m";
    localparam string C_CYAN    = "\033[1;36m";

    // -------------------------------------------------------------------------
    // Signal Definitions
    // -------------------------------------------------------------------------
    // Clock & Reset
    logic        clk;
    logic        rst_n;

    // Inputs
    logic        grant_i;
    logic        target_select_i;
    logic [7:0]  rx_data_i;
    logic        rx_ready_i;
    logic        tx_done_i;

    // Outputs
    logic        done_o;
    logic [7:0]  tx_data_o;
    logic        tx_start_o;
    logic        mem_write_enable_o;
    logic [31:0] mem_addr_o;
    logic [31:0] mem_data_o;

    // Test Variables
    int          test_count = 0;
    int          error_count = 0;
    logic [31:0] observed_signal; // Helper for generic checks

    // -------------------------------------------------------------------------
    // DUT Instantiation
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
    // Clock Generation
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk; // 100MHz equivalent (10ns period)

    // -------------------------------------------------------------------------
    // Helper Tasks
    // -------------------------------------------------------------------------

    // Automated Check Task
    task check(input logic [31:0] expected, input logic [31:0] actual, input string test_name);
        test_count++;
        if (actual === expected) begin
            $display("%-40s %s[PASS]%s", test_name, C_GREEN, C_RESET);
        end else begin
            $display("%-40s %s[FAIL]%s", test_name, C_RED, C_RESET);
            $display("   Expected: 0x%h", expected);
            $display("   Received: 0x%h", actual);
            error_count++;
        end
    endtask

    // Simulate Receiving a Byte from UART RX
    task send_rx_byte(input logic [7:0] data);
        @(posedge clk);
        rx_data_i  = data;
        rx_ready_i = 1'b1;
        @(posedge clk);
        rx_ready_i = 1'b0;
        // Wait for logic to process? No, logic is pipelined/state machine based.
        // FSM transitions on rx_ready_i pulse.
    endtask

    // -------------------------------------------------------------------------
    // Main Test Sequence
    // -------------------------------------------------------------------------
    initial begin
        // --- Header Block ---
        $display("\n%s=======================================================%s", C_CYAN, C_RESET);
        $display("%s Testbench: %-38s %s", C_CYAN, FILE_NAME, C_RESET);
        $display("%s=======================================================%s\n", C_CYAN, C_RESET);

        // --- Initialization ---
        rst_n           = 0;
        grant_i         = 0;
        target_select_i = 0;
        rx_data_i       = 0;
        rx_ready_i      = 0;
        tx_done_i       = 0;

        @(posedge clk);
        rst_n = 1;
        #1; // Settling

        // ---------------------------------------------------------------------
        // Test 1: Reset State Check
        // ---------------------------------------------------------------------
        check(1'b0, done_o, "Reset: done_o is 0");
        check(1'b0, mem_write_enable_o, "Reset: mem_we is 0");

        // ---------------------------------------------------------------------
        // Test 2: Activation & Size Header (2 Words)
        // ---------------------------------------------------------------------
        // Scenario: Host wants to load 2 words (8 bytes). 
        // Size = 0x0002.
        
        // 1. Grant the Loader
        @(posedge clk);
        grant_i = 1;
        target_select_i = 0; // IMEM
        #1;

        // 2. Send Size High Byte (0x00)
        send_rx_byte(8'h00);
        
        // 3. Send Size Low Byte (0x02)
        send_rx_byte(8'h02);

        // Check internal counters reset (implicitly checked by success of following tests)
        check(1'b0, done_o, "During Load: done_o is 0");

        // ---------------------------------------------------------------------
        // Test 3: First Word Assembly (0xDEADBEEF)
        // ---------------------------------------------------------------------
        // Sequence: LSB -> MSB (EF, BE, AD, DE)

        send_rx_byte(8'hEF); // Byte 0
        send_rx_byte(8'hBE); // Byte 1
        send_rx_byte(8'hAD); // Byte 2
        send_rx_byte(8'hDE); // Byte 3

        // Logic moves from S_RECEIVE_BYTE to S_WRITE_WORD *after* processing Byte 3.
        // Wait 1 cycle for FSM transition to S_WRITE_WORD
        //@(posedge clk); 
        #1; // Sampling Window

        check(1'b1, mem_write_enable_o, "Word 1: Write Strobe Active");
        check(32'hDEADBEEF, mem_data_o, "Word 1: Data Assembly Correct");
        check(32'd0, mem_addr_o, "Word 1: Address is 0");

        // ---------------------------------------------------------------------
        // Test 4: Second Word Assembly (0xCAFEBABE)
        // ---------------------------------------------------------------------
        // Sequence: LSB -> MSB (BE, BA, FE, CA)

        // Wait one cycle for FSM to return to S_RECEIVE_BYTE (or stay in write for a cycle depending on logic)
        // Implementation: S_WRITE_WORD -> (count check) -> S_RECEIVE_BYTE
        @(posedge clk);

        send_rx_byte(8'hBE); 
        send_rx_byte(8'hBA);
        send_rx_byte(8'hFE);
        send_rx_byte(8'hCA);

        // Wait 1 cycle for FSM transition to S_WRITE_WORD
        //@(posedge clk); 
        #1; 

        check(1'b1, mem_write_enable_o, "Word 2: Write Strobe Active");
        check(32'hCAFEBABE, mem_data_o, "Word 2: Data Assembly Correct");
        check(32'd1, mem_addr_o, "Word 2: Address incremented to 1");

        // ---------------------------------------------------------------------
        // Test 5: Completion Handshake (ACK)
        // ---------------------------------------------------------------------
        // After 2nd word, FSM should go to S_SEND_ACK

        @(posedge clk); // Transition to S_SEND_ACK
        #1;

        check(1'b0, mem_write_enable_o, "Post-Write: Strobe Inactive");
        check(1'b1, tx_start_o, "Handshake: TX Start Pulsed");
        check(8'hF1, tx_data_o, "Handshake: Data is 0xF1");

        // Simulate UART TX Busy time
        @(posedge clk);
        // FSM is now in S_WAIT_ACK
        #1;
        check(1'b0, tx_start_o, "Handshake: TX Start Cleared");
        
        // Signal TX Done
        tx_done_i = 1;
        @(posedge clk);
        tx_done_i = 0;
        #1;

        // FSM should be in S_DONE
        check(1'b1, done_o, "Completion: done_o High");

        // ---------------------------------------------------------------------
        // Test 6: Release Grant
        // ---------------------------------------------------------------------
        @(posedge clk);
        grant_i = 0;
        @(posedge clk); // Transition to S_IDLE
        #1;
        
        check(1'b0, done_o, "Idle: done_o cleared after grant removal");

        // --- Summary Footer ---
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
