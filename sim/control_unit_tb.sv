// -----------------------------------------------------------------------------
// Module: control_unit_tb
// Description: Testbench for the Main Control Unit.
//              Verifies signal generation for all RISC-V instruction types.
// -----------------------------------------------------------------------------

module control_unit_tb;

    localparam string FILE_NAME = "CTRL+Unit";
    localparam string C_RESET   = "\033[0m";
    localparam string C_RED     = "\033[1;31m";
    localparam string C_GREEN   = "\033[1;32m";
    localparam string C_BLUE    = "\033[1;34m";
    localparam string C_CYAN    = "\033[1;36m";

    // Signals
    logic [6:0] opcode_i;
    logic       branch_o;
    logic       jump_o;
    logic [1:0] alu_opmode_o;
    logic       alu_src_o;
    logic       mem_read_o;
    logic       mem_write_o;
    logic       reg_write_o;
    logic       mem_to_reg_o;

    // Test counters
    int test_count  = 0;
    int error_count = 0;

    // DUT Instantiation
    control_unit dut (
        .opcode_i     (opcode_i),
        .branch_o     (branch_o),
        .jump_o       (jump_o),
        .alu_opmode_o     (alu_opmode_o),
        .alu_src_o    (alu_src_o),
        .mem_read_o   (mem_read_o),
        .mem_write_o  (mem_write_o),
        .reg_write_o  (reg_write_o),
        .mem_to_reg_o (mem_to_reg_o)
    );

    // Main Test Process
    initial begin
        // Header
        $display("\n%s=======================================================%s", C_CYAN, C_RESET);
        $display("%s Testbench: %-38s %s", C_CYAN, FILE_NAME, C_RESET);
        $display("%s=======================================================%s\n", C_CYAN, C_RESET);

        // 1. Test R-Type (ADD, SUB, XOR, etc.)
        // Expected: RegWrite=1, ALUOp=10 (R-Type), ALUSrc=0 (Reg)
        opcode_i = 7'b0110011;
        #1;
        check("R-Type", 1'b0, 1'b0, 2'b10, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0);

        // 2. Test I-Type (ADDI, SLTI, etc.)
        // Expected: RegWrite=1, ALUOp=11 (I-Type), ALUSrc=1 (Imm)
        opcode_i = 7'b0010011;
        #1;
        check("I-Type", 1'b0, 1'b0, 2'b11, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0);

        // 3. Test Load (LW, LB)
        // Expected: RegWrite=1, MemRead=1, MemToReg=1, ALUSrc=1, ALUOp=00 (Add)
        opcode_i = 7'b0000011;
        #1;
        check("Load", 1'b0, 1'b0, 2'b00, 1'b1, 1'b1, 1'b0, 1'b1, 1'b1);

        // 4. Test Store (SW, SB)
        // Expected: MemWrite=1, ALUSrc=1, ALUOp=00 (Add)
        opcode_i = 7'b0100011;
        #1;
        check("Store", 1'b0, 1'b0, 2'b00, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0);

        // 5. Test Branch (BEQ, BNE)
        // Expected: Branch=1, ALUOp=01 (Sub)
        opcode_i = 7'b1100011;
        #1;
        check("Branch", 1'b1, 1'b0, 2'b01, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);

        // 6. Test JAL (Jump)
        // Expected: Jump=1, RegWrite=1, ALUOp=00, ALUSrc=1
        opcode_i = 7'b1101111;
        #1;
        check("JAL", 1'b0, 1'b1, 2'b00, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0);

        // 7. Test JALR (Jump Register)
        // Expected: Jump=1, RegWrite=1, ALUOp=00, ALUSrc=1
        opcode_i = 7'b1100111;
        #1;
        check("JALR", 1'b0, 1'b1, 2'b00, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0);

        // 8. Test LUI (Load Upper Immediate)
        // Expected: RegWrite=1, ALUOp=00 (Add), ALUSrc=1
        opcode_i = 7'b0110111;
        #1;
        check("LUI", 1'b0, 1'b0, 2'b00, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0);

        // 9. Test Invalid/Unknown Opcode
        // Expected: All Zeros (Safe default)
        opcode_i = 7'b1111111;
        #1;
        check("Invalid", 1'b0, 1'b0, 2'b00, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);

        // Final Report
        $display("\n%s-------------------------------------------------------%s", C_CYAN, C_RESET);
        if (error_count == 0) begin
            $display("%s[SUMMARY] %sSUCCESS: All %0d tests passed.%s", C_BLUE, C_GREEN, test_count, C_RESET);
        end else begin
            $display("%s[SUMMARY] %sFAILURE: %0d/%0d tests failed.%s", C_BLUE, C_RED, error_count, test_count, C_RESET);
        end
        $display("%s-------------------------------------------------------%s\n", C_CYAN, C_RESET);

        $finish;
    end

    // -------------------------------------------------------------------------
    // Verification Task
    // -------------------------------------------------------------------------
    task check(
        input string name,
        input logic  exp_branch,
        input logic  exp_jump,
        input logic [1:0] exp_alu_op,
        input logic  exp_alu_src,
        input logic  exp_mem_read,
        input logic  exp_mem_write,
        input logic  exp_reg_write,
        input logic  exp_mem_to_reg
    );
        logic mismatch;
        mismatch = 0;
        test_count++;

        // Compare all signals
        if (branch_o     !== exp_branch)     mismatch = 1;
        if (jump_o       !== exp_jump)       mismatch = 1;
        if (alu_opmode_o     !== exp_alu_op)     mismatch = 1;
        if (alu_src_o    !== exp_alu_src)    mismatch = 1;
        if (mem_read_o   !== exp_mem_read)   mismatch = 1;
        if (mem_write_o  !== exp_mem_write)  mismatch = 1;
        if (reg_write_o  !== exp_reg_write)  mismatch = 1;
        if (mem_to_reg_o !== exp_mem_to_reg) mismatch = 1;

        if (mismatch) begin
            error_count++;
            $display("%s[FAIL] %-10s %s | Exp: {Br:%b Jmp:%b AOp:%b ASrc:%b MR:%b MW:%b RW:%b M2R:%b} | Got: {Br:%b Jmp:%b AOp:%b ASrc:%b MR:%b MW:%b RW:%b M2R:%b}", 
                C_RED, name, C_RESET,
                exp_branch, exp_jump, exp_alu_op, exp_alu_src, exp_mem_read, exp_mem_write, exp_reg_write, exp_mem_to_reg,
                branch_o, jump_o, alu_opmode_o, alu_src_o, mem_read_o, mem_write_o, reg_write_o, mem_to_reg_o);
        end else begin
            $display("%s[PASS] %-10s %s | Signals verified", C_GREEN, name, C_RESET);
        end
    endtask

endmodule
