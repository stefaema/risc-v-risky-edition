// -----------------------------------------------------------------------------
// Module: debug_unit_tb
// Description: Testbench for the Debug & Execution Controller.
//              Verifies Continuous Run, Step-by-Step execution, and Dump Triggers.
// -----------------------------------------------------------------------------

module debug_unit_tb;

    // -------------------------------------------------------------------------
    // Metadata & Color Palette
    // -------------------------------------------------------------------------
    localparam string FILE_NAME = "debug_unit_tb.sv";
    localparam string C_RESET   = "\033[0m";
    localparam string C_RED     = "\033[1;31m";
    localparam string C_GREEN   = "\033[1;32m";
    localparam string C_BLUE    = "\033[1;34m";
    localparam string C_CYAN    = "\033[1;36m";

    // -------------------------------------------------------------------------
    // Signals
    // -------------------------------------------------------------------------
    logic       clk;
    logic       rst_n;

    // DUT Inputs
    logic       grant_i;
    logic       exec_mode_i;
    logic [7:0] rx_data_i;
    logic       rx_ready_i;
    logic       core_halted_i;
    logic       dump_done_i;

    // DUT Outputs
    logic       done_o;
    logic       cpu_stall_o;
    logic       cpu_reset_o;
    logic       dump_trigger_o;
    logic       dump_mem_mode_o;

    // Test Stats
    int test_count  = 0;
    int error_count = 0;

    // -------------------------------------------------------------------------
    // DUT Instantiation
    // -------------------------------------------------------------------------
    debug_unit dut (
        .clk_i           (clk),
        .rst_ni          (rst_n),
        .grant_i         (grant_i),
        .exec_mode_i     (exec_mode_i),
        .done_o          (done_o),
        .rx_data_i       (rx_data_i),
        .rx_ready_i      (rx_ready_i),
        .core_halted_i   (core_halted_i),
        .cpu_stall_o     (cpu_stall_o),
        .cpu_reset_o     (cpu_reset_o),
        .dump_trigger_o  (dump_trigger_o),
        .dump_mem_mode_o (dump_mem_mode_o),
        .dump_done_i     (dump_done_i)
    );

    // -------------------------------------------------------------------------
    // Clock Generation
    // -------------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz equivalent
    end

    // -------------------------------------------------------------------------
    // Helper Tasks
    // -------------------------------------------------------------------------
    
    // Check signal value
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

    // Check 1-bit signal
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

    // Reset Sequence
    task run_reset();
        $display("\n%s[System Reset]%s", C_BLUE, C_RESET);
        rst_n = 0;
        grant_i = 0;
        exec_mode_i = 0;
        rx_data_i = 0;
        rx_ready_i = 0;
        core_halted_i = 0;
        dump_done_i = 0;
        @(posedge clk);
        #1;
        rst_n = 1;
    endtask

    // -------------------------------------------------------------------------
    // Test Scenarios
    // -------------------------------------------------------------------------
    initial begin
        // Header
        $display("\n%s=======================================================%s", C_CYAN, C_RESET);
        $display("%s Testbench: %-38s %s", C_CYAN, FILE_NAME, C_RESET);
        $display("%s=======================================================%s\n", C_CYAN, C_RESET);

        run_reset();

        // ---------------------------------------------------------------------
        // Test 1: Idle State Verification
        // ---------------------------------------------------------------------
        $display("%s--- Test 1: Idle Defaults ---%s", C_BLUE, C_RESET);
        @(posedge clk); #1;
        check_bit(cpu_stall_o, 1'b1, "CPU Stall Default High");
        check_bit(done_o, 1'b0, "Done Low");

        // ---------------------------------------------------------------------
        // Test 2: Continuous Run Mode
        // ---------------------------------------------------------------------
        $display("\n%s--- Test 2: Continuous Run Mode ---%s", C_BLUE, C_RESET);
        
        // 1. Grant Access in Mode 1 (Run)
        @(posedge clk);
        grant_i = 1;
        exec_mode_i = 1;
        @(posedge clk); #1; // Wait for state transition

        check_bit(cpu_stall_o, 1'b0, "CPU Unstalled (Run)");
        check_bit(dump_mem_mode_o, 1'b1, "Dump Mode = Continuous");

        // 2. Simulate Running... then Halt
        @(posedge clk);
        @(posedge clk);
        $display("Simulating Core Halt...");
        core_halted_i = 1; 
        @(posedge clk); #1;

        // 3. Verify Halt Detection & Dump Trigger
        check_bit(cpu_stall_o, 1'b1, "CPU Stalled on Halt");
        check_bit(dump_trigger_o, 1'b1, "Dump Triggered");

        // 4. Trigger Pulse End & Wait State
        @(posedge clk); #1;
        check_bit(dump_trigger_o, 1'b0, "Dump Trigger is Pulse");
        
        // 5. Simulate Dump Done
        dump_done_i = 1;
        @(posedge clk); #1;
        dump_done_i = 0;

        // 6. Verify Exit
        check_bit(done_o, 1'b1, "Done Asserted after Dump");
        
        // 7. Release Grant
        grant_i = 0;
        core_halted_i = 0;
        @(posedge clk); #1;
        check_bit(done_o, 1'b0, "Done Deasserted in Idle");

        // ---------------------------------------------------------------------
        // Test 3: Step-by-Step Mode
        // ---------------------------------------------------------------------
        $display("\n%s--- Test 3: Step-by-Step Mode ---%s", C_BLUE, C_RESET);
        
        // 1. Grant Access in Mode 0 (Step)
        @(posedge clk);
        grant_i = 1;
        exec_mode_i = 0;
        @(posedge clk); #1;

        check_bit(cpu_stall_o, 1'b1, "CPU Stalled (Wait Cmd)");
        check_bit(dump_mem_mode_o, 1'b0, "Dump Mode = Step");

        // 2. Send 'Advance' Command (0xAE)
        $display("Sending CMD_ADVANCE (0xAE)...");
        @(posedge clk);
        rx_data_i = 8'hAE;
        rx_ready_i = 1;
        @(posedge clk); 
        rx_ready_i = 0; // Pulse
        #1;

        // 3. Verify Single Cycle Step
        // State should be S_STEP now
        check_bit(cpu_stall_o, 1'b0, "CPU Unstalled (Step Pulse)");
        
        @(posedge clk); #1; // Transition to S_TRIGGER_DUMP
        
        // 4. Verify Re-freeze and Dump Trigger
        check_bit(cpu_stall_o, 1'b1, "CPU Re-stalled");
        check_bit(dump_trigger_o, 1'b1, "Dump Triggered");

        // 5. Complete Dump
        @(posedge clk); // S_WAIT_DUMP
        dump_done_i = 1;
        @(posedge clk); #1;
        dump_done_i = 0;

        // 6. Verify Return to Wait Cmd (Not Exit, since core didn't halt)
        check_bit(done_o, 1'b0, "Not Done (Still Stepping)");
        check_bit(cpu_stall_o, 1'b1, "Back to Wait Cmd");

        // ---------------------------------------------------------------------
        // Test 4: Step Mode -> Halt
        // ---------------------------------------------------------------------
        $display("\n%s--- Test 4: Step Mode Halt Detection ---%s", C_BLUE, C_RESET);
        
        // 1. Core Signals Halt during the step
        core_halted_i = 1;

        // 2. Send another Advance
        @(posedge clk);
        rx_data_i = 8'hAE;
        rx_ready_i = 1;
        @(posedge clk);
        rx_ready_i = 0;
        
        // Step Pulse
        @(posedge clk); 
        // Trigger Dump
        @(posedge clk);
        // Wait Dump
        dump_done_i = 1;
        @(posedge clk); #1;
        dump_done_i = 0;

        // 3. Verify Exit because Core Halted
        check_bit(done_o, 1'b1, "Done Asserted (Core Halted)");

        // Cleanup
        grant_i = 0;
        @(posedge clk); #1;


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
