// -----------------------------------------------------------------------------
// Module: dumping_unit_tb
// Description: Verification testbench for the State Dumping Unit.
//              Simulates UART reception and Core/Memory interface stimuli.
// -----------------------------------------------------------------------------

`timescale 1ns / 1ps

module dumping_unit_tb;

    // -------------------------------------------------------------------------
    // 0. Constants & Colors
    // -------------------------------------------------------------------------
    localparam string FILE_NAME = "dumping_unit_tb";
    localparam string C_RESET = "\033[0m";
    localparam string C_RED   = "\033[1;31m";
    localparam string C_GREEN = "\033[1;32m";
    localparam string C_BLUE  = "\033[1;34m";
    localparam string C_CYAN  = "\033[1;36m";

    // -------------------------------------------------------------------------
    // 1. Signals & DUT
    // -------------------------------------------------------------------------
    logic clk, rst_n;
    
    // Control
    logic dump_trigger;
    logic dump_mem_mode;
    logic dump_done;

    // UART
    logic [7:0] tx_data;
    logic tx_start;
    logic tx_done;

    // Core Taps
    logic [4:0]  rf_dbg_addr;
    logic [31:0] rf_dbg_data;
    logic [95:0]  if_id_flat;
    logic [196:0] id_ex_flat;
    logic [109:0] ex_mem_flat;
    logic [104:0] mem_wb_flat;
    logic [15:0]  hazard_status;

    // Memory
    logic [31:0] dmem_addr;
    logic [31:0] dmem_data;
    logic        dmem_write_en_snoop;
    logic [31:0] dmem_addr_snoop;
    logic [31:0] dmem_write_data_snoop;
    logic [31:0] min_addr;
    logic [31:0] max_addr;

    // DUT Instance
    dumping_unit dut (
        .clk_i(clk), .rst_ni(rst_n),
        .dump_trigger_i(dump_trigger), .dump_mem_mode_i(dump_mem_mode), .dump_done_o(dump_done),
        .tx_data_o(tx_data), .tx_start_o(tx_start), .tx_done_i(tx_done),
        .rf_dbg_addr_o(rf_dbg_addr), .rf_dbg_data_i(rf_dbg_data),
        .if_id_flat_i(if_id_flat), .id_ex_flat_i(id_ex_flat), 
        .ex_mem_flat_i(ex_mem_flat), .mem_wb_flat_i(mem_wb_flat), .hazard_status_i(hazard_status),
        .dmem_addr_o(dmem_addr), .dmem_data_i(dmem_data),
        .dmem_write_en_snoop_i(dmem_write_en_snoop), .dmem_addr_snoop_i(dmem_addr_snoop),
        .dmem_write_data_snoop_i(dmem_write_data_snoop),
        .min_addr_i(min_addr), .max_addr_i(max_addr)
    );

    // -------------------------------------------------------------------------
    // 2. Simulation Infrastructure
    // -------------------------------------------------------------------------
    int test_count = 0;
    int error_count = 0;

    // Clock Generation
    always #5 clk = ~clk;

    // Check Task
    task check(input logic [31:0] received, input logic [31:0] expected, input string name);
        test_count++;
        if (received === expected) begin
            $display("%-40s %s[PASS]%s", name, C_GREEN, C_RESET);
        end else begin
            $display("%-40s %s[FAIL]%s", name, C_RED, C_RESET);
            $display("   Expected: 0x%h", expected);
            $display("   Received: 0x%h", received);
            error_count++;
        end
    endtask

    // Mock Responders
    always_comb begin
        case (dmem_addr)
            32'h0000_1000: dmem_data = 32'hAAAA_BBBB;
            32'h0000_1004: dmem_data = 32'hCCCC_DDDD;
            default:       dmem_data = 32'hDEAD_BEEF;
        endcase
        rf_dbg_data = {27'b0, rf_dbg_addr}; 
    end

    // -------------------------------------------------------------------------
    // UART Helpers (THE OLD WAY - RESTORED)
    // -------------------------------------------------------------------------

    // 1. Expect Specific Byte
    task expect_uart_byte(input logic [7:0] expected_byte, input string msg);
        // Robust start detection
        if (tx_start !== 1'b1) begin
             @(posedge tx_start);
        end

        check(tx_data, expected_byte, msg);
        
        #20; // Transmission time
        
        tx_done = 1;
        @(posedge clk);
        tx_done = 0;
        
        // Wait for DUT to release busy state
        wait(tx_start === 1'b0);
        #1; 
    endtask

    // 2. Consume Bytes
    task consume_bytes(input int count, input string description);
        $display("   %s>> Fast-forwarding %0d bytes (%s)...%s", C_CYAN, count, description, C_RESET);
        repeat (count) begin
            if (tx_start !== 1'b1) begin
                 @(posedge tx_start);
            end

            #20; 
            
            tx_done = 1;
            @(posedge clk);
            tx_done = 0;
            
            wait(tx_start === 1'b0);
            #1; 
        end
    endtask

    // -------------------------------------------------------------------------
    // 3. Test Cases
    // -------------------------------------------------------------------------
    initial begin
        $display("\n%s=======================================================%s", C_CYAN, C_RESET);
        $display("%s Testbench: %-38s %s", C_CYAN, FILE_NAME, C_RESET);
        $display("%s=======================================================%s\n", C_CYAN, C_RESET);

        // Init
        clk = 0; rst_n = 0; dump_trigger = 0; dump_mem_mode = 0; tx_done = 0;
        if_id_flat = '0; id_ex_flat = '0; ex_mem_flat = '0; mem_wb_flat = '0; hazard_status = '0;
        dmem_write_en_snoop = 0; dmem_addr_snoop = 0; dmem_write_data_snoop = 0;
        min_addr = 0; max_addr = 0;

        @(posedge clk);
        #10 rst_n = 1;

        // ---------------------------------------------------------------------
        // Test 1: Step Mode Header
        // ---------------------------------------------------------------------
        $display("%s--- Test 1: Step Mode Dump (Diff Strategy) ---%s", C_BLUE, C_RESET);
        
        dump_mem_mode = 0; // Step
        dmem_write_en_snoop = 1; 
        dmem_addr_snoop = 32'h0000_8888;
        dmem_write_data_snoop = 32'h1234_5678;

        @(posedge clk);
        dump_trigger = 1; 
        
        expect_uart_byte(8'hDA, "Header: Alert Byte (0xDA)");

        dump_trigger = 0; // Release trigger logic

        expect_uart_byte(8'h00, "Header: Mode Byte (0x00)");

        // ---------------------------------------------------------------------
        // Test 2: Registers
        // ---------------------------------------------------------------------
        $display("%s--- Test 2: Register File Serialization ---%s", C_BLUE, C_RESET);
        
        expect_uart_byte(8'h00, "Reg x0 Byte 0");
        expect_uart_byte(8'h00, "Reg x0 Byte 1");
        expect_uart_byte(8'h00, "Reg x0 Byte 2");
        expect_uart_byte(8'h00, "Reg x0 Byte 3");

        expect_uart_byte(8'h01, "Reg x1 Byte 0");
        expect_uart_byte(8'h00, "Reg x1 Byte 1");
        expect_uart_byte(8'h00, "Reg x1 Byte 2");
        expect_uart_byte(8'h00, "Reg x1 Byte 3");

        consume_bytes((32-2) * 4, "Remaining Registers x2-x31");

        // ---------------------------------------------------------------------
        // Test 3: Pipeline
        // ---------------------------------------------------------------------
        $display("%s--- Test 3: Pipeline Serialization ---%s", C_BLUE, C_RESET);
        
        expect_uart_byte(8'h00, "Hazard Status Byte 0");
        expect_uart_byte(8'h00, "Hazard Status Byte 1");
        expect_uart_byte(8'h00, "Hazard Padding Byte 2");
        expect_uart_byte(8'h00, "Hazard Padding Byte 3");

        consume_bytes(18 * 4, "Remaining Pipeline State");

        // ---------------------------------------------------------------------
        // Test 4: Memory Config (Step)
        // ---------------------------------------------------------------------
        $display("%s--- Test 4: Memory Config (Step Mode) ---%s", C_BLUE, C_RESET);
        
        expect_uart_byte(8'h01, "Step Mode: Flag Byte 0 (0x01)");
        consume_bytes(3, "Flag Padding");

        expect_uart_byte(8'h88, "Step Mode: Addr Byte 0");
        consume_bytes(3, "Addr Remaining");

        expect_uart_byte(8'h78, "Step Mode: Data Byte 0");
        consume_bytes(3, "Data Remaining");

        // Validate Done Signal logic
        if (dump_done !== 1'b1) @(posedge dump_done);
        #1;
        check(dump_done, 1'b1, "Dump Done Asserted (Test 4)");

        // ---------------------------------------------------------------------
        // TRANSITION TO TEST 5 (The Fix)
        // ---------------------------------------------------------------------
        // 1. Ensure Trigger is low from previous test
        dump_trigger = 0;

        // 2. Wait for FSM to actually drop dump_done (return to IDLE)
        //    This is crucial. If we don't wait, T5 starts while FSM is still "Done".
        wait(dump_done === 1'b0);
        #20; // Gap for safety

        // ---------------------------------------------------------------------
        // Test 5: Continuous Mode
        // ---------------------------------------------------------------------
        $display("\n%s--- Test 5: Continuous Mode Dump (Range Strategy) ---%s", C_BLUE, C_RESET);
        
        dump_mem_mode = 1; // Continuous
        min_addr = 32'h0000_1000;
        max_addr = 32'h0000_1004; // Range = 2 words

        @(posedge clk);
        dump_trigger = 1; 
        // Note: Do NOT lower trigger immediately here. Wait until we catch the header.
        // This ensures the FSM has definitely latched the start state.

        expect_uart_byte(8'hDA, "Header: Alert");
        dump_trigger = 0; // Safe to lower now

        expect_uart_byte(8'h01, "Header: Mode (Continuous)");

        // Fast forward Regs + Pipeline
        consume_bytes(128 + 76, "Regs + Pipeline Data");

        // Memory Config: Min Addr (0x0000_1000)
        expect_uart_byte(8'h00, "Cont Mode: MinAddr B0");
        expect_uart_byte(8'h10, "Cont Mode: MinAddr B1");
        consume_bytes(2, "MinAddr Remaining");

        // Memory Config: Max Addr (0x0000_1004)
        expect_uart_byte(8'h04, "Cont Mode: MaxAddr B0");
        expect_uart_byte(8'h10, "Cont Mode: MaxAddr B1");
        consume_bytes(2, "MaxAddr Remaining");

        // Payload: Word 1 (Addr 1000 -> Mock Data AAAA_BBBB)
        expect_uart_byte(8'hBB, "Payload Word 1 B0");
        consume_bytes(3, "Word 1 Remaining");

        // Payload: Word 2 (Addr 1004 -> Mock Data CCCC_DDDD)
        expect_uart_byte(8'hDD, "Payload Word 2 B0");
        consume_bytes(3, "Word 2 Remaining");

        // Verify Completion
        if (dump_done !== 1'b1) @(posedge dump_done);
        #1;
        check(dump_done, 1'b1, "Dump Done (Continuous)");


        // ---------------------------------------------------------------------
        // Final Summary
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
