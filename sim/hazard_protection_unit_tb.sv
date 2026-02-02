// -----------------------------------------------------------------------------
// Module: hazard_protection_unit_tb
// Description: Verification for the Hazard Protection Unit.
//              Tests the Priority Table: Halt > Redirect > Load-Use.
// -----------------------------------------------------------------------------

module hazard_protection_unit_tb;

    // 1. Metadata & Color Palette
    localparam string FILE_NAME = "Haz-hard Protection";
    localparam string C_RESET = "\033[0m";
    localparam string C_RED   = "\033[1;31m";
    localparam string C_GREEN = "\033[1;32m";
    localparam string C_BLUE  = "\033[1;34m";
    localparam string C_CYAN  = "\033[1;36m";

    // 2. Signal Declaration
    // Inputs
    logic [4:0] rs1_addr_id_i;
    logic [4:0] rs2_addr_id_i;
    logic       id_ex_mem_read_i;
    logic [4:0] id_ex_rd_i;
    logic       redirect_req_i;   // Renamed
    logic       halt_detected_i;  // New

    // Outputs
    logic       pc_write_en_o;
    logic       if_id_write_en_o;
    logic       if_id_flush_o;
    logic       id_ex_write_en_o; // New output control
    logic       id_ex_flush_o;

    // Testing Variables
    int         test_count = 0;
    int         error_count = 0;

    // 3. DUT Instantiation
    hazard_protection_unit dut (
        .rs1_addr_id_i    (rs1_addr_id_i),
        .rs2_addr_id_i    (rs2_addr_id_i),
        .id_ex_mem_read_i (id_ex_mem_read_i),
        .id_ex_rd_i       (id_ex_rd_i),
        .redirect_req_i   (redirect_req_i),
        .halt_detected_i  (halt_detected_i),
        .pc_write_en_o    (pc_write_en_o),
        .if_id_write_en_o (if_id_write_en_o),
        .if_id_flush_o    (if_id_flush_o),
        .id_ex_write_en_o (id_ex_write_en_o),
        .id_ex_flush_o    (id_ex_flush_o)
    );

    // 4. Verification Task
    task check(
        input logic exp_pc_en,
        input logic exp_if_id_en,
        input logic exp_if_id_flush,
        input logic exp_id_ex_en,
        input logic exp_id_ex_flush,
        input string test_name
    );
        logic [4:0] expected_bus;
        logic [4:0] observed_bus;

        // Concatenate signals for cleaner comparison
        expected_bus = {exp_pc_en, exp_if_id_en, exp_if_id_flush, exp_id_ex_en, exp_id_ex_flush};
        observed_bus = {pc_write_en_o, if_id_write_en_o, if_id_flush_o, id_ex_write_en_o, id_ex_flush_o};

        test_count++;
        
        if (observed_bus === expected_bus) begin
            $display("%-40s %s[PASS]%s", test_name, C_GREEN, C_RESET);
        end else begin
            $display("%-40s %s[FAIL]%s", test_name, C_RED, C_RESET);
            $display("   Expected: PC_En:%b | IFID_En:%b | IFID_Flush:%b | IDEX_En:%b | IDEX_Flush:%b",
                exp_pc_en, exp_if_id_en, exp_if_id_flush, exp_id_ex_en, exp_id_ex_flush);
            $display("   Received: PC_En:%b | IFID_En:%b | IFID_Flush:%b | IDEX_En:%b | IDEX_Flush:%b",
                pc_write_en_o, if_id_write_en_o, if_id_flush_o, id_ex_write_en_o, id_ex_flush_o);
            error_count++;
        end
    endtask

    // 5. Test Stimulus
    initial begin
        // Header
        $display("\n%s=======================================================%s", C_CYAN, C_RESET);
        $display("%s Testbench: %-38s %s", C_CYAN, FILE_NAME, C_RESET);
        $display("%s=======================================================%s\n", C_CYAN, C_RESET);

        // --- Test 1: No Hazards (Happy Path) ---
        rs1_addr_id_i    = 5'd1; rs2_addr_id_i = 5'd2;
        id_ex_mem_read_i = 0; id_ex_rd_i = 5'd3;
        redirect_req_i   = 0; halt_detected_i = 0;
        #1;
        // Expect: All Writes Enable=1, All Flushes=0
        check(1'b1, 1'b1, 1'b0, 1'b1, 1'b0, "Normal Operation");

        // --- Test 2: Priority 1 - System Halt ---
        // Scenario: Halt is High. Even if we have a Load-Use (setup below), Halt must win.
        id_ex_mem_read_i = 1; id_ex_rd_i = 5'd1; // Force Load-Use condition
        rs1_addr_id_i    = 5'd1; 
        redirect_req_i   = 1; // Also force Redirect condition
        halt_detected_i  = 1; // HALT ACTIVE
        #1;
        // Expect: PC Freeze(0), IF/ID Write(1) Flush(1-Kill), ID/EX Freeze(0-Lock) Flush(0)
        check(1'b0, 1'b1, 1'b1, 1'b0, 1'b0, "Priority 1: System Halt");

        // --- Test 3: Priority 2 - Branch Redirect ---
        // Scenario: No Halt. Branch Redirect is High. Load-Use is active.
        halt_detected_i  = 0;
        redirect_req_i   = 1;
        id_ex_mem_read_i = 1; id_ex_rd_i = 5'd1; rs1_addr_id_i = 5'd1; // Load-Use Active
        #1;
        // Expect: PC En(1-Jump), IF/ID Write(1) Flush(1), ID/EX Write(1) Flush(1)
        check(1'b1, 1'b1, 1'b1, 1'b1, 1'b1, "Priority 2: Redirect");

        // --- Test 4: Priority 3 - Load-Use Stall ---
        // Scenario: No Halt, No Redirect. Load-Use Active.
        halt_detected_i  = 0;
        redirect_req_i   = 0;
        id_ex_mem_read_i = 1; id_ex_rd_i = 5'd1; rs1_addr_id_i = 5'd1; 
        #1;
        // Expect: PC Freeze(0), IF/ID Freeze(0) Flush(0), ID/EX Write(1) Flush(1-Bubble)
        check(1'b0, 1'b0, 1'b0, 1'b1, 1'b1, "Priority 3: Load-Use Stall");

        // --- Test 5: False Alarm (Load, no dependency) ---
        id_ex_mem_read_i = 1; id_ex_rd_i = 5'd5; // Dependency on x5
        rs1_addr_id_i    = 5'd1; // Requesting x1
        #1;
        check(1'b1, 1'b1, 1'b0, 1'b1, 1'b0, "No Hazard: Independent Load");

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
