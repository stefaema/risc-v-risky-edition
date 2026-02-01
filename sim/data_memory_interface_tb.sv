// -----------------------------------------------------------------------------
// Module: data_memory_interface_tb
// Description: Testbench for the Memory Interface Unit.
//              Verifies alignment, masking, and sign-extension logic.
// -----------------------------------------------------------------------------

`timescale 1ns / 1ps

module data_memory_interface_tb;

    // -------------------------------------------------------------------------
    // 1. Mandatory Metadata & Color Palette
    // -------------------------------------------------------------------------
    localparam string FILE_NAME = "Date-a Memory Inter-phase";
    
    localparam string C_RESET = "\033[0m";
    localparam string C_RED   = "\033[1;31m";
    localparam string C_GREEN = "\033[1;32m";
    localparam string C_BLUE  = "\033[1;34m";
    localparam string C_CYAN  = "\033[1;36m";

    // -------------------------------------------------------------------------
    // 2. Signals & DUT Instantiation
    // -------------------------------------------------------------------------
    logic       clk;
    
    // Inputs
    logic [2:0]  funct3_i;
    logic [1:0]  alu_result_addr_i;
    logic [31:0] rs2_data_i;
    logic [31:0] raw_read_data_i;
    logic        mem_write_en;

    // Outputs
    logic [3:0]  byte_enable_mask_o;
    logic [31:0] ram_write_data_o;
    logic [31:0] final_read_data_o;

    // Test Variables
    integer test_count = 0;
    integer error_count = 0;

    data_memory_interface dut (
        .funct3_i           (funct3_i),
        .alu_result_addr_i  (alu_result_addr_i),
        .rs2_data_i         (rs2_data_i),
        .raw_read_data_i    (raw_read_data_i),
        .mem_write_en       (mem_write_en),
        .byte_enable_mask_o (byte_enable_mask_o),
        .ram_write_data_o   (ram_write_data_o),
        .final_read_data_o  (final_read_data_o)
    );

    // -------------------------------------------------------------------------
    // 3. Clock Generation
    // -------------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // -------------------------------------------------------------------------
    // 4. Automated Check Tasks
    // -------------------------------------------------------------------------
    
    // Check for 32-bit Data (Read/Write Data)
    task check_data(input logic [31:0] expected, input logic [31:0] observed, input string test_name);
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

    // Check for 4-bit Mask (Byte Enables)
    task check_mask(input logic [3:0] expected, input logic [3:0] observed, input string test_name);
        test_count++;
        if (observed === expected) begin
            $display("%-40s %s[PASS]%s", test_name, C_GREEN, C_RESET);
        end else begin
            $display("%-40s %s[FAIL]%s", test_name, C_RED, C_RESET);
            $display("   Expected: 0b%b", expected);
            $display("   Received: 0b%b", observed);
            error_count++;
        end
    endtask

    // -------------------------------------------------------------------------
    // 5. Main Stimulus
    // -------------------------------------------------------------------------
    initial begin
        // Header
        $display("\n%s=======================================================%s", C_CYAN, C_RESET);
        $display("%s Testbench: %-38s %s", C_CYAN, FILE_NAME, C_RESET);
        $display("%s=======================================================%s\n", C_CYAN, C_RESET);

        // Initialization
        funct3_i = 0;
        alu_result_addr_i = 0;
        rs2_data_i = 0;
        raw_read_data_i = 0;
        mem_write_en = 0;

        // ---------------------------------------------------------------------
        // STORE TESTS (Write Logic)
        // ---------------------------------------------------------------------
        $display("%s--- Store Tests (Masking & Alignment) ---%s", C_BLUE, C_RESET);
        
        // Use a recognizable pattern: 0xAABBCCDD
        // Byte to store: 0xDD
        // Half to store: 0xCCDD
        rs2_data_i = 32'hAABBCCDD;
        mem_write_en = 1;

        // - Test 1: Store Byte (SB) at Offset 0 -
        @(posedge clk);
        funct3_i = 3'b000; // SB
        alu_result_addr_i = 2'b00;
        @(posedge clk); #1;
        check_mask(4'b0001, byte_enable_mask_o, "SB Offset 0: Mask");
        check_data(32'h000000DD, ram_write_data_o, "SB Offset 0: Data");

        // - Test 2: Store Byte (SB) at Offset 1 -
        @(posedge clk);
        alu_result_addr_i = 2'b01;
        @(posedge clk); #1;
        check_mask(4'b0010, byte_enable_mask_o, "SB Offset 1: Mask");
        check_data(32'h0000DD00, ram_write_data_o, "SB Offset 1: Data");

        // - Test 3: Store Byte (SB) at Offset 3 -
        @(posedge clk);
        alu_result_addr_i = 2'b11;
        @(posedge clk); #1;
        check_mask(4'b1000, byte_enable_mask_o, "SB Offset 3: Mask");
        check_data(32'hDD000000, ram_write_data_o, "SB Offset 3: Data");

        // - Test 4: Store Half (SH) at Offset 0 -
        @(posedge clk);
        funct3_i = 3'b001; // SH
        alu_result_addr_i = 2'b00;
        @(posedge clk); #1;
        check_mask(4'b0011, byte_enable_mask_o, "SH Offset 0: Mask");
        check_data(32'h0000CCDD, ram_write_data_o, "SH Offset 0: Data");

        // - Test 5: Store Half (SH) at Offset 2 -
        @(posedge clk);
        alu_result_addr_i = 2'b10; // Corresponds to upper half
        @(posedge clk); #1;
        check_mask(4'b1100, byte_enable_mask_o, "SH Offset 2: Mask");
        check_data(32'hCCDD0000, ram_write_data_o, "SH Offset 2: Data");

        // - Test 6: Store Word (SW) -
        @(posedge clk);
        funct3_i = 3'b010; // SW
        alu_result_addr_i = 2'b00; // Word aligned
        @(posedge clk); #1;
        check_mask(4'b1111, byte_enable_mask_o, "SW Aligned: Mask");
        check_data(32'hAABBCCDD, ram_write_data_o, "SW Aligned: Data");

        // ---------------------------------------------------------------------
        // LOAD TESTS (Read Logic)
        // ---------------------------------------------------------------------
        $display("\n%s--- Load Tests (Extension & Selection) ---%s", C_BLUE, C_RESET);

        // Memory contains: 0xF0 (Negative Byte), 0x70 (Positive Byte)
        // raw_read_data = 0xF070F070
        raw_read_data_i = 32'hF070F070;
        mem_write_en = 0;

        // - Test 7: Load Byte Signed (LB) Positive -
        @(posedge clk);
        funct3_i = 3'b000; // LB
        alu_result_addr_i = 2'b00; // Reads 0x70
        @(posedge clk); #1;
        check_data(32'h00000070, final_read_data_o, "LB Pos (0x70) Sign Ext");

        // - Test 8: Load Byte Signed (LB) Negative -
        @(posedge clk);
        alu_result_addr_i = 2'b01; // Reads 0xF0
        @(posedge clk); #1;
        check_data(32'hFFFFFFF0, final_read_data_o, "LB Neg (0xF0) Sign Ext");

        // - Test 9: Load Byte Unsigned (LBU) Negative -
        @(posedge clk);
        funct3_i = 3'b100; // LBU
        alu_result_addr_i = 2'b01; // Reads 0xF0
        @(posedge clk); #1;
        check_data(32'h000000F0, final_read_data_o, "LBU Neg (0xF0) Zero Ext");

        // - Test 10: Load Half Signed (LH) Negative -
        // Reading lower half: 0xF070 -> Negative (Bit 15 is 1)
        @(posedge clk);
        funct3_i = 3'b001; // LH
        alu_result_addr_i = 2'b00;
        @(posedge clk); #1;
        check_data(32'hFFFFF070, final_read_data_o, "LH Neg (0xF070) Sign Ext");

        // - Test 11: Load Half Unsigned (LHU) Negative -
        @(posedge clk);
        funct3_i = 3'b101; // LHU
        alu_result_addr_i = 2'b00;
        @(posedge clk); #1;
        check_data(32'h0000F070, final_read_data_o, "LHU Neg (0xF070) Zero Ext");

        // - Test 12: Load Word (LW) -
        @(posedge clk);
        funct3_i = 3'b010; // LW
        alu_result_addr_i = 2'b00;
        @(posedge clk); #1;
        check_data(32'hF070F070, final_read_data_o, "LW Full Word");

        // ---------------------------------------------------------------------
        // Summary Footer
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
