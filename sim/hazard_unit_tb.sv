// -----------------------------------------------------------------------------
// Module: hazard_unit_tb
// Description: Verification for Load-Use detection and Branch flushing logic.
// -----------------------------------------------------------------------------

module hazard_unit_tb;

    // -------------------------------------------------------------------------
    // 1. Metadata & Color Palette
    // -------------------------------------------------------------------------
    localparam string FILE_NAME = "Bubble Wrap";
    localparam string C_RESET = "\033[0m";
    localparam string C_RED   = "\033[1;31m";
    localparam string C_GREEN = "\033[1;32m";
    localparam string C_BLUE  = "\033[1;34m";
    localparam string C_CYAN  = "\033[1;36m";

    // -------------------------------------------------------------------------
    // 2. Signal Declaration
    // -------------------------------------------------------------------------
    // Inputs
    logic [4:0] rs1_addr_id_i;
    logic [4:0] rs2_addr_id_i;
    logic       id_ex_mem_read_i;
    logic [4:0] id_ex_rd_i;
    logic       flush_req_i;

    // Outputs
    logic       pc_write_en_o;
    logic       if_id_write_en_o;
    logic       if_id_flush_o;
    logic       id_ex_flush_o;

    // Testing Variables
    int         test_count = 0;
    int         error_count = 0;

    // -------------------------------------------------------------------------
    // 3. DUT Instantiation
    // -------------------------------------------------------------------------
    hazard_unit dut (
        .rs1_addr_id_i   (rs1_addr_id_i),
        .rs2_addr_id_i   (rs2_addr_id_i),
        .id_ex_mem_read_i(id_ex_mem_read_i),
        .id_ex_rd_i      (id_ex_rd_i),
        .flush_req_i   (flush_req_i),
        .pc_write_en_o   (pc_write_en_o),
        .if_id_write_en_o(if_id_write_en_o),
        .if_id_flush_o   (if_id_flush_o),
        .id_ex_flush_o   (id_ex_flush_o)
    );

    // -------------------------------------------------------------------------
    // 4. Verification Task
    // -------------------------------------------------------------------------
    task check(
        input logic exp_pc_en,
        input logic exp_if_id_en,
        input logic exp_if_id_flush,
        input logic exp_id_ex_flush,
        input string test_name
    );
        logic [3:0] expected_bus;
        logic [3:0] observed_bus;

        // Concatenate signals for cleaner comparison
        expected_bus = {exp_pc_en, exp_if_id_en, exp_if_id_flush, exp_id_ex_flush};
        observed_bus = {pc_write_en_o, if_id_write_en_o, if_id_flush_o, id_ex_flush_o};

        test_count++;
        

        if (observed_bus === expected_bus) begin
            $display("%-40s %s[PASS]%s", test_name, C_GREEN, C_RESET);
        end else begin
            $display("%-40s %s[FAIL]%s", test_name, C_RED, C_RESET);
            $display("   Expected: PC_En=%b | IFID_En=%b | IFID_Flush=%b | IDEX_Flush=%b",
                exp_pc_en, exp_if_id_en, exp_if_id_flush, exp_id_ex_flush);
            $display("   Received: PC_En=%b | IFID_En=%b | IFID_Flush=%b | IDEX_Flush=%b",
                pc_write_en_o, if_id_write_en_o, if_id_flush_o, id_ex_flush_o);
            error_count++;
        end
    endtask

    // -------------------------------------------------------------------------
    // 5. Test Stimulus
    // -------------------------------------------------------------------------
    initial begin
        // Header
        $display("\n%s=======================================================%s", C_CYAN, C_RESET);
        $display("%s Testbench: %-38s %s", C_CYAN, FILE_NAME, C_RESET);
        $display("%s=======================================================%s\n", C_CYAN, C_RESET);

        // --- Test 1: No Hazards (Happy Path) ---
        // Scenario: Standard R-Type instructions, no loads, no branches.
        rs1_addr_id_i    = 5'd1;
        rs2_addr_id_i    = 5'd2;
        id_ex_mem_read_i = 1'b0; // NOT a Load
        id_ex_rd_i       = 5'd3;
        flush_req_i    = 1'b0; // No Branch
        #1;
        // Expect: Enable=1, Flush=0
        check(1'b1, 1'b1, 1'b0, 1'b0, "No Hazard: Normal Operation");


        // --- Test 2: Load-Use Hazard on RS1 ---
        // Scenario:
        // EX Stage: LW x1, 0(x10)  -> id_ex_rd = 1, mem_read = 1
        // ID Stage: ADD x5, x1, x2 -> rs1 = 1
        rs1_addr_id_i    = 5'd1; // Dependency matches EX RD
        rs2_addr_id_i    = 5'd2;
        id_ex_mem_read_i = 1'b1; // Load Instruction
        id_ex_rd_i       = 5'd1; // Writing to x1
        flush_req_i    = 1'b0;
        #1;
        // Expect: Freeze PC/IFID (En=0), Flush IDEX (Bubble=1)
        check(1'b0, 1'b0, 1'b0, 1'b1, "Stall: Load-Use on RS1");


        // --- Test 3: Load-Use Hazard on RS2 ---
        // Scenario:
        // EX Stage: LW x2, 0(x10)
        // ID Stage: ADD x5, x1, x2 -> rs2 = 2
        rs1_addr_id_i    = 5'd1;
        rs2_addr_id_i    = 5'd2; // Dependency matches EX RD
        id_ex_mem_read_i = 1'b1;
        id_ex_rd_i       = 5'd2; // Writing to x2
        flush_req_i    = 1'b0;
        #1;
        // Expect: Freeze PC/IFID (En=0), Flush IDEX (Bubble=1)
        check(1'b0, 1'b0, 1'b0, 1'b1, "Stall: Load-Use on RS2");


        // --- Test 4: False Alarm (Load, but no dependency) ---
        // Scenario:
        // EX Stage: LW x5, ...
        // ID Stage: ADD x3, x1, x2 -> No match with x5
        rs1_addr_id_i    = 5'd1;
        rs2_addr_id_i    = 5'd2;
        id_ex_mem_read_i = 1'b1; // Load
        id_ex_rd_i       = 5'd5; // x5 != x1, x5 != x2
        flush_req_i    = 1'b0;
        #1;
        // Expect: Normal Operation
        check(1'b1, 1'b1, 1'b0, 1'b0, "No Hazard: Independent Load");


        // --- Test 5: x0 Exception (Load to x0) ---
        // Scenario: The load targets x0 (effectively a NOP), should not stall.
        rs1_addr_id_i    = 5'd0; // x0 used?
        rs2_addr_id_i    = 5'd0;
        id_ex_mem_read_i = 1'b1;
        id_ex_rd_i       = 5'd0; // Load to x0
        flush_req_i    = 1'b0;
        #1;
        // Expect: Normal Operation
        check(1'b1, 1'b1, 1'b0, 1'b0, "No Hazard: Load to x0 ignored");


        // --- Test 6: Control Hazard (Branch Taken) ---
        // Scenario: BEQ taken. Must flush pipeline.
        // Stall conditions irrelevant here (usually), but let's assume no load.
        rs1_addr_id_i    = 5'd1;
        rs2_addr_id_i    = 5'd2;
        id_ex_mem_read_i = 1'b0;
        id_ex_rd_i       = 5'd0;
        flush_req_i    = 1'b1; // Branch Taken!
        #1;
        // Expect: PC En=1 (Jump), IFID Flush=1, IDEX Flush=1
        check(1'b1, 1'b1, 1'b1, 1'b1, "Flush: Branch Taken");


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
