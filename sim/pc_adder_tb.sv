`timescale 1ns / 1ps

module pc_adder_tb;

    localparam string FILE_NAME = "PC Add Her";
    localparam string C_RESET   = "\033[0m";
    localparam string C_RED     = "\033[1;31m";
    localparam string C_GREEN   = "\033[1;32m";
    localparam string C_BLUE    = "\033[1;34m";
    localparam string C_CYAN    = "\033[1;36m";

    logic [31:0] pc_in;
    logic [31:0] pc_out;
    int error_count = 0;
    int test_count = 0;

    pc_adder dut (.pc_in(pc_in), .pc_out(pc_out));

    task check(input logic [31:0] expected, input string test_name);
        test_count++;
        if (pc_out === expected) $display("%-40s %s[PASS]%s", test_name, C_GREEN, C_RESET);
        else begin
            $display("%-40s %s[FAIL]%s (Exp: %h, Rec: %h)", test_name, C_RED, C_RESET, expected, pc_out);
            error_count++;
        end
    endtask

    initial begin
        $display("\n%s=== %s ===%s", C_CYAN, FILE_NAME, C_RESET);
        
        pc_in = 32'h0000_0000; #1; check(32'h0000_0004, "Base 0x0");
        pc_in = 32'h0000_1000; #1; check(32'h0000_1004, "Addr 0x1000");
        pc_in = 32'hFFFF_FFFC; #1; check(32'h0000_0000, "Overflow");

        $display("%sTests: %0d | Errors: %0d%s\n", C_BLUE, test_count, error_count, C_RESET);
        $finish;
    end

endmodule
