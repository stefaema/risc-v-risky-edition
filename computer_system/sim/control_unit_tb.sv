// -----------------------------------------------------------------------------
// Module: control_unit_tb
// Description: Testbench for the Main Control Unit.
// -----------------------------------------------------------------------------

module control_unit_tb;

    localparam string FILE_NAME = "Control U-Neat";
    localparam string C_RESET   = "\033[0m";
    localparam string C_RED     = "\033[1;31m";
    localparam string C_GREEN   = "\033[1;32m";
    localparam string C_BLUE    = "\033[1;34m";
    localparam string C_CYAN    = "\033[1;36m";

    // Signals
    logic [6:0] opcode_i;
    logic       is_branch;
    logic       is_jal;
    logic       is_jalr;
    logic       mem_write_en;
    logic       mem_read_en;
    logic       reg_write_en;
    logic [1:0] rd_src_optn;
    logic [1:0] alu_intent;
    logic       alu_src_optn;
    logic       is_halt;  

    // Test counters
    int test_count  = 0;
    int error_count = 0;

    // DUT Instantiation
    control_unit dut (
        .opcode_i     (opcode_i),
        .is_branch    (is_branch),
        .is_jal       (is_jal),
        .is_jalr      (is_jalr),
        .mem_write_en (mem_write_en),
        .mem_read_en  (mem_read_en),
        .reg_write_en (reg_write_en),
        .rd_src_optn  (rd_src_optn),
        .alu_intent   (alu_intent),
        .alu_src_optn (alu_src_optn),
        .is_halt      (is_halt) 
    );

    // --- Main Test Process ---
    initial begin
        // Header
        $display("\n%s=======================================================%s", C_CYAN, C_RESET);
        $display("%s Testbench: %-38s %s", C_CYAN, FILE_NAME, C_RESET);
        $display("%s=======================================================%s\n", C_CYAN, C_RESET);

        // - Test 1: R-Type (ADD, SUB) -
        // Dossier: RegWrite, ALU=RTY(10), Src=Reg(0), WB=ALU(00)
        opcode_i = 7'b0110011;
        #1;
        check("R-Type", 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 2'b00, 2'b10, 1'b0, 1'b0);

        // - Test 2: I-Type (ADDI) -
        // Dossier: RegWrite, ALU=ITY(11), Src=Imm(1), WB=ALU(00)
        opcode_i = 7'b0010011;
        #1;
        check("I-Type", 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 2'b00, 2'b11, 1'b1, 1'b0);

        // - Test 3: Load (LW) -
        // Dossier: RegWrite, MemRead, WB=Mem(10), ALU=Add(00), Src=Imm(1)
        opcode_i = 7'b0000011;
        #1;
        check("Load", 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b1, 2'b10, 2'b00, 1'b1, 1'b0);

        // - Test 4: Store (SW) -
        // Dossier: MemWrite, ALU=Add(00), Src=Imm(1)
        opcode_i = 7'b0100011;
        #1;
        check("Store", 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 2'b00, 2'b00, 1'b1, 1'b0);

        // - Test 5: Branch (BEQ) -
        // Dossier: is_branch, ALU=Sub(01), Src=Reg(0)
        opcode_i = 7'b1100011;
        #1;
        check("Branch", 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 2'b00, 2'b01, 1'b0, 1'b0);

        // - Test 6: JAL -
        // Dossier: is_jal, RegWrite, WB=PC+4(01). 
        opcode_i = 7'b1101111;
        #1;
        check("JAL", 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 2'b01, 2'b00, 1'b0, 1'b0);

        // - Test 7: JALR -
        // Dossier: is_jalr, RegWrite, WB=PC+4(01), ALU=Add(00), Src=Imm(1)
        opcode_i = 7'b1100111;
        #1;
        check("JALR", 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 2'b01, 2'b00, 1'b1, 1'b0);

        // - Test 8: LUI -
        // Dossier: RegWrite, WB=ALU(00), ALU=Add(00), Src=Imm(1)
        opcode_i = 7'b0110111;
        #1;
        check("LUI", 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 2'b00, 2'b00, 1'b1, 1'b0);

        // - Test 9: SYSTEM (ECALL) -
        // Dossier: is_halt = 1. Others 0/Default.
        opcode_i = 7'b1110011;
        #1;
        check("ECALL (Halt)", 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 2'b00, 2'b00, 1'b0, 1'b1);

        // - Test 10: Invalid Opcode_i -
        // Safe defaults (all zero)
        opcode_i = 7'b1111111;
        #1;
        check("Invalid", 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 2'b00, 2'b00, 1'b0, 1'b0);

        // Summary Footer
        $display("\n%s-------------------------------------------------------%s", C_BLUE, C_RESET);
        if (error_count == 0) begin
            $display("Tests: %0d | Errors: %0d -> %sSUCCESS%s", test_count, error_count, C_GREEN, C_RESET);
        end else begin
            $display("Tests: %0d | Errors: %0d -> %sFAILURE%s", test_count, error_count, C_RED, C_RESET);
        end
        $display("%s-------------------------------------------------------%s\n", C_BLUE, C_RESET);

        $finish;
    end

    // -------------------------------------------------------------------------
    // Verification Task
    // -------------------------------------------------------------------------
    task check(
        input string name,
        input logic  e_br,    // is_branch
        input logic  e_jal,   // is_jal
        input logic  e_jalr,  // is_jalr
        input logic  e_mw,    // mem_write_en
        input logic  e_mr,    // mem_read_en
        input logic  e_rw,    // reg_write_en
        input logic [1:0] e_rsrc,  // rd_src_optn
        input logic [1:0] e_aint,  // alu_intent
        input logic  e_asrc,   // alu_src_optn
        input logic  e_halt    // is_halt
    );
        logic mismatch;
        mismatch = 0;
        test_count++;

        if (is_branch    !== e_br)   mismatch = 1;
        if (is_jal       !== e_jal)  mismatch = 1;
        if (is_jalr      !== e_jalr) mismatch = 1;
        if (mem_write_en !== e_mw)   mismatch = 1;
        if (mem_read_en  !== e_mr)   mismatch = 1;
        if (reg_write_en !== e_rw)   mismatch = 1;
        if (rd_src_optn  !== e_rsrc) mismatch = 1;
        if (alu_intent   !== e_aint) mismatch = 1;
        if (alu_src_optn !== e_asrc) mismatch = 1;
        if (is_halt      !== e_halt) mismatch = 1;

        if (mismatch) begin
            error_count++;
            $display("%-20s %s[FAIL]%s", name, C_RED, C_RESET);
            $display("  Exp: {Br:%b Jal:%b Jalr:%b MW:%b MR:%b RW:%b RSrc:%b AInt:%b ASrc:%b Halt:%b}",
                e_br, e_jal, e_jalr, e_mw, e_mr, e_rw, e_rsrc, e_aint, e_asrc, e_halt);
            $display("  Got: {Br:%b Jal:%b Jalr:%b MW:%b MR:%b RW:%b RSrc:%b AInt:%b ASrc:%b Halt:%b}",
                is_branch, is_jal, is_jalr, mem_write_en, mem_read_en, reg_write_en, rd_src_optn, alu_intent, alu_src_optn, is_halt);
        end else begin
            $display("%-20s %s[PASS]%s", name, C_GREEN, C_RESET);
        end
    endtask

endmodule
