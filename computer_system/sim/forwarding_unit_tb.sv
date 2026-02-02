// -----------------------------------------------------------------------------
// Module: forwarding_unit_tb
// Description: Testbench for the Forwarding Unit verifying RAW hazard resolution,
//              priority logic (EX over MEM), and Load-Use restrictions.
// -----------------------------------------------------------------------------

`timescale 1ns / 1ps

module forwarding_unit_tb;

    // --- Metadata & Colors ---
    localparam string FILE_NAME = "Flash-Forward";
    localparam string C_RESET = "\033[0m";
    localparam string C_RED   = "\033[1;31m";
    localparam string C_GREEN = "\033[1;32m";
    localparam string C_BLUE  = "\033[1;34m";
    localparam string C_CYAN  = "\033[1;36m";

    // --- Signals ---
    // ID/EX inputs
    logic [4:0] rs1_id_ex_i;
    logic [4:0] rs2_id_ex_i;

    // EX/MEM inputs
    logic [4:0] rd_ex_mem_i;
    logic       reg_write_ex_mem_en;
    logic       mem_read_ex_mem_en;

    // MEM/WB inputs
    logic [4:0] rd_mem_wb_i;
    logic       reg_write_mem_wb_en;

    // Outputs
    logic [1:0] forward_a_optn_o;
    logic [1:0] forward_b_optn_o;

    // Benchmarking
    int test_count = 0;
    int error_count = 0;

    // --- DUT Instance ---
    forwarding_unit dut (
        .rs1_id_ex_i        (rs1_id_ex_i),
        .rs2_id_ex_i        (rs2_id_ex_i),
        .rd_ex_mem_i        (rd_ex_mem_i),
        .reg_write_ex_mem_en(reg_write_ex_mem_en),
        .mem_read_ex_mem_en (mem_read_ex_mem_en),
        .rd_mem_wb_i        (rd_mem_wb_i),
        .reg_write_mem_wb_en(reg_write_mem_wb_en),
        .forward_a_optn_o   (forward_a_optn_o),
        .forward_b_optn_o   (forward_b_optn_o)
    );

    // --- Check Task ---
    task check(input logic [1:0] expected_a, input logic [1:0] expected_b, input string test_name);
        test_count++;
        if ((forward_a_optn_o === expected_a) && (forward_b_optn_o === expected_b)) begin
            $display("%-40s %s[PASS]%s", test_name, C_GREEN, C_RESET);
        end else begin
            $display("%-40s %s[FAIL]%s", test_name, C_RED, C_RESET);
            $display("   Expected A: %b, B: %b", expected_a, expected_b);
            $display("   Received A: %b, B: %b", forward_a_optn_o, forward_b_optn_o);
            error_count++;
        end
    endtask

    // --- Simulation Logic ---
    initial begin
        // Header
        $display("\n%s=======================================================%s", C_CYAN, C_RESET);
        $display("%s Testbench: %-38s %s", C_CYAN, FILE_NAME, C_RESET);
        $display("%s=======================================================%s\n", C_CYAN, C_RESET);

        // Initialize
        rs1_id_ex_i = 0; rs2_id_ex_i = 0;
        rd_ex_mem_i = 0; reg_write_ex_mem_en = 0; mem_read_ex_mem_en = 0;
        rd_mem_wb_i = 0; reg_write_mem_wb_en = 0;

        // --- Test 1: No Hazards (Clean Flow) ---
        // Setup
        rs1_id_ex_i = 5'd1; 
        rs2_id_ex_i = 5'd2;
        rd_ex_mem_i = 5'd3; reg_write_ex_mem_en = 0; // No write happening
        rd_mem_wb_i = 5'd4; reg_write_mem_wb_en = 0;
        #1; // Combinational settle
        // Check
        check(2'b00, 2'b00, "No Hazards");

        // --- Test 2: EX Hazard on RS1 (ALU Forwarding) ---
        // Setup
        rs1_id_ex_i = 5'd5;
        rs2_id_ex_i = 5'd6;
        rd_ex_mem_i = 5'd5;      // Dependency on RS1
        reg_write_ex_mem_en = 1; // Writing enabled
        mem_read_ex_mem_en = 0;  // Not a Load
        #1;
        // Check: A should forward (10), B should be reg (00)
        check(2'b10, 2'b00, "EX Hazard on RS1");

        // --- Test 3: MEM Hazard on RS2 (WB Forwarding) ---
        // Setup
        rs1_id_ex_i = 5'd1;
        rs2_id_ex_i = 5'd8;      // Need x8
        // Clear EX stage
        rd_ex_mem_i = 5'd0; reg_write_ex_mem_en = 0; 
        // Set MEM stage
        rd_mem_wb_i = 5'd8;      // Writing x8
        reg_write_mem_wb_en = 1;
        #1;
        // Check: A (00), B (01 - from WB)
        check(2'b00, 2'b01, "MEM Hazard on RS2");

        // --- Test 4: Priority Check (EX vs MEM) ---
        // Setup: Both stages write to x9. RS1 needs x9.
        rs1_id_ex_i = 5'd9;
        // EX Stage (Most recent)
        rd_ex_mem_i = 5'd9; reg_write_ex_mem_en = 1; mem_read_ex_mem_en = 0;
        // MEM Stage (Stale)
        rd_mem_wb_i = 5'd9; reg_write_mem_wb_en = 1;
        #1;
        // Check: Must choose EX (10) over MEM (01)
        check(2'b10, 2'b00, "Priority: EX overrides MEM");

        // --- Test 5: x0 Edge Case ---
        // Setup: Previous instructions write to x0. Current reads x0.
        rs1_id_ex_i = 5'd0;
        rd_ex_mem_i = 5'd0; reg_write_ex_mem_en = 1;
        rd_mem_wb_i = 5'd0; reg_write_mem_wb_en = 1;
        #1;
        // Check: Should never forward x0 (00)
        check(2'b00, 2'b00, "Ignore writes to x0");

        // --- Test 6: Load-Use Restriction in EX ---
        // Setup: EX stage is a LOAD instruction writing to RS1
        rs1_id_ex_i = 5'd10;
        rd_ex_mem_i = 5'd10;
        reg_write_ex_mem_en = 1;
        mem_read_ex_mem_en = 1; // IT IS A LOAD
        #1;
        // Check: Forwarding Unit must NOT forward from EX (00).
        // (The stall unit handles the bubble, but forwarding must not grab ALU address)
        check(2'b00, 2'b00, "Load-Use: No Forward from EX");

        // --- Test 7: Double Hazard with Load in EX ---
        // Setup: EX is Load to x11 (stalled), MEM is math to x11 (valid).
        rs1_id_ex_i = 5'd11;
        // EX is Load (Invalid for forward)
        rd_ex_mem_i = 5'd11; reg_write_ex_mem_en = 1; mem_read_ex_mem_en = 1;
        // MEM is Math (Valid for forward)
        rd_mem_wb_i = 5'd11; reg_write_mem_wb_en = 1;
        #1;
        // Check: Logic falls through EX check (due to !mem_read) and catches MEM hazard.
        // Result: 01. (Note: In reality, Stall unit stops this inst, but logic holds).
        check(2'b01, 2'b00, "Double Hazard w/ Load: Fallback to MEM");

        // Summary
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
