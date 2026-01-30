`timescale 1ns / 1ps

module register_file_tb;


    // Metadata & Constants
    localparam string FILE_NAME = "REGinald file";
    localparam string C_RESET   = "\033[0m";
    localparam string C_RED     = "\033[1;31m";
    localparam string C_GREEN   = "\033[1;32m";
    localparam string C_BLUE    = "\033[1;34m";
    localparam string C_CYAN    = "\033[1;36m";

    // DUT Signals
    logic        clk;
    logic        rst_n;
    logic [4:0]  rs1_addr, rs2_addr, rd_addr;
    logic [31:0] write_data;
    logic        reg_write_en;
    logic [31:0] read_data1, read_data2;

    int test_count = 0;
    int error_count = 0;

    register_file uut (.*); 

    // Clock Generation
    initial begin
        clk = 0; // Starting at 0 to make the first negedge predictable
        forever #5 clk = ~clk; 
    end

    // Verification Task
    task check(input logic [31:0] expected, input logic [31:0] received, input string msg);
        test_count++;
        if (expected === received) begin
            $display("%s[PASS]%s %-30s | Exp: 0x%h | Rec: 0x%h", 
                     C_GREEN, C_RESET, msg, expected, received);
        end else begin
            $display("%s[FAIL]%s %-30s | Exp: 0x%h | Rec: 0x%h", 
                     C_RED, C_RESET, msg, expected, received);
            error_count++;
        end
    endtask

    initial begin

        $display("\n%s=======================================================%s", C_CYAN, C_RESET);
        $display("%s Testbench: %-38s %s", C_CYAN, FILE_NAME, C_RESET);
        $display("%s=======================================================%s\n", C_CYAN, C_RESET);

        $display("%s[TEST PHASE 1] Initialization & Reset%s", C_BLUE, C_RESET);
        rst_n = 0;
        reg_write_en = 0;
        rs1_addr = 0; rs2_addr = 0; rd_addr = 0; write_data = 0;
        #15; // Hold reset across a clock edge
        rst_n = 1;
        #5;
        
        rs1_addr = 1;
        #1;
        check(32'h00000000, read_data1, "Check Reset State (x1)");

        $display("\n%s[TEST PHASE 2] Write & Read Operations%s", C_BLUE, C_RESET);
        
        // --- Write 0xDEADBEEF to x1 ---
        @(posedge clk);
        rd_addr = 1;
        write_data = 32'hDEADBEEF;
        reg_write_en = 1;
        
        // Wait for Negedge (Write occurs) then Posedge (Read is stable)
        @(posedge clk); 
        reg_write_en = 0; // Disable write
        rs1_addr = 1;
        #1; 
        check(32'hDEADBEEF, read_data1, "Read x1 after Write");

        // --- Write 0xCAFEBABE to x2 ---
        @(posedge clk);
        rd_addr = 2;
        write_data = 32'hCAFEBABE;
        reg_write_en = 1;

        // Read both ports
        @(posedge clk);
        reg_write_en = 0;
        rs1_addr = 1;
        rs2_addr = 2;
        #1;
        check(32'hDEADBEEF, read_data1, "Dual Read Port 1 (x1)");
        check(32'hCAFEBABE, read_data2, "Dual Read Port 2 (x2)");

        $display("\n%s[TEST PHASE 3] x0 Invariant Check%s", C_BLUE, C_RESET);
        
        @(posedge clk); // Attempt to write to x0
        rd_addr = 0;
        write_data = 32'hFFFFFFFF;
        reg_write_en = 1;
        
        @(posedge clk); // Check that x0 is still 0
        reg_write_en = 0;
        rs1_addr = 0;
        #1;
        check(32'h00000000, read_data1, "Write to x0 Ignored");

        $display("\n%s=======================================================%s", C_CYAN, C_RESET);
        if (error_count == 0)
            $display(" %sSTATUS: SUCCESS%s", C_GREEN, C_RESET);
        else
            $display(" %sSTATUS: FAILURE%s", C_RED, C_RESET);
        $display("%s=======================================================%s\n", C_CYAN, C_RESET);
        $finish;
    end

endmodule
