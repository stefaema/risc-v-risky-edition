// -----------------------------------------------------------------------------
// Module: riscv_core_tb
// Description: Integration testbench for the RV32I Pipelined Core.
//              Simulates Instruction/Data memory and verifies 5 distinct
//              execution scenarios (Happy Path, Forwarding, Hazards, Flush, Meta).
// -----------------------------------------------------------------------------

module riscv_core_tb;

    // 1. Mandatory Metadata & Color Palette
    localparam string FILE_NAME = "Five Stages of Grief (Processor Test)";
    localparam string C_RESET = "\033[0m";
    localparam string C_RED   = "\033[1;31m";
    localparam string C_GREEN = "\033[1;32m";
    localparam string C_BLUE  = "\033[1;34m";
    localparam string C_CYAN  = "\033[1;36m";

    // -------------------------------------------------------------------------
    // Signal Declarations
    // -------------------------------------------------------------------------
    logic        clk;
    logic        rst_n;
    
    // Flow Control
    logic        global_stall_i;
    logic        global_flush_i;

    // Instruction Memory Interface
    logic [31:0] instr_mem_addr_o;
    logic [31:0] instr_mem_data_i;

    // Data Memory Interface
    logic [31:0] data_mem_addr_o;
    logic [31:0] data_mem_write_data_o;
    logic [31:0] data_mem_read_data_i;
    logic        data_mem_write_en_o;
    logic [3:0]  data_mem_byte_mask_o;
    logic [31:0] data_mem_min_addr_o;
    logic [31:0] data_mem_max_addr_o;

    // Debug Interface
    logic [4:0]  rs_dbg_addr_i;
    logic [31:0] rs_dbg_data_o;
    
    // Core Status
    logic [31:0] core_pc_o;
    logic        core_halted_o;
    
    // Observability (Unused in TB logic but kept for waveform viewing)
    logic [95:0]  if_id_flat_o;
    logic [196:0] id_ex_flat_o;
    logic [109:0] ex_mem_flat_o;
    logic [104:0] mem_wb_flat_o;
    logic [15:0]  hazard_status_o;

    // Simulation Internals
    int test_count = 0;
    int error_count = 0;
    logic [31:0] observed_signal; // For check task sharing

    // -------------------------------------------------------------------------
    // Simulated Memory Models
    // -------------------------------------------------------------------------
    logic [31:0] instr_mem [0:511]; // 2KB Instruction Memory
    logic [31:0] data_mem  [0:511]; // 2KB Data Memory

    // Instruction Fetch
    assign instr_mem_data_i = instr_mem[instr_mem_addr_o[10:2]];

    // Data Memory Access (Synchronous Write, Asynchronous Read)
    assign data_mem_read_data_i = data_mem[data_mem_addr_o[10:2]];

    always_ff @(posedge clk) begin
        if (data_mem_write_en_o) begin
            // Simple word-aligned write for testing
            data_mem[data_mem_addr_o[10:2]] <= data_mem_write_data_o;
        end
    end

    // -------------------------------------------------------------------------
    // DUT Instantiation
    // -------------------------------------------------------------------------
    riscv_core dut (
        .clk_i                 (clk),
        .rst_ni                (rst_n),
        .global_stall_i        (global_stall_i),
        .global_flush_i        (global_flush_i),
        .instr_mem_addr_o      (instr_mem_addr_o),
        .instr_mem_data_i      (instr_mem_data_i),
        .data_mem_addr_o       (data_mem_addr_o),
        .data_mem_write_data_o (data_mem_write_data_o),
        .data_mem_read_data_i  (data_mem_read_data_i),
        .data_mem_write_en_o   (data_mem_write_en_o),
        .data_mem_byte_mask_o  (data_mem_byte_mask_o),
        .data_mem_min_addr_o   (data_mem_min_addr_o),
        .data_mem_max_addr_o   (data_mem_max_addr_o),
        .rs_dbg_addr_i         (rs_dbg_addr_i),
        .rs_dbg_data_o         (rs_dbg_data_o),
        .core_pc_o             (core_pc_o),
        .core_halted_o         (core_halted_o),
        .if_id_flat_o          (if_id_flat_o),
        .id_ex_flat_o          (id_ex_flat_o),
        .ex_mem_flat_o         (ex_mem_flat_o),
        .mem_wb_flat_o         (mem_wb_flat_o),
        .hazard_status_o       (hazard_status_o)
    );

    // -------------------------------------------------------------------------
    // Clock Generation
    // -------------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // -------------------------------------------------------------------------
    // Helper Tasks
    // -------------------------------------------------------------------------

    // 2B. Automated Check Task
    task check(input logic [31:0] expected, input string test_name);
        test_count++;
        if (observed_signal === expected) begin
            $display("%-40s %s[PASS]%s", test_name, C_GREEN, C_RESET);
        end else begin
            $display("%-40s %s[FAIL]%s", test_name, C_RED, C_RESET);
            $display("   Expected: 0x%h", expected);
            $display("   Received: 0x%h", observed_signal);
            error_count++;
        end
    endtask

    // Task to load programs into instruction memory
    task load_test_program(input int test_id);
        integer i;
        // Clear memories
        for (i = 0; i < 512; i++) begin
            instr_mem[i] = 32'h0000_0013; // Fill with NOPs
            data_mem[i]  = 32'h0000_0000;
        end

        case (test_id)
            1: begin // Happy Path
                instr_mem[0] = 32'h00a00093; // addi x1, x0, 10
                instr_mem[1] = 32'h00500113; // addi x2, x0, 5
                instr_mem[2] = 32'h00000013; // nop
                instr_mem[3] = 32'h00000013; // nop
                instr_mem[4] = 32'h00000013; // nop
                instr_mem[5] = 32'h002081b3; // add x3, x1, x2
                instr_mem[6] = 32'h40208233; // sub x4, x1, x2
                instr_mem[7] = 32'h123452b7; // lui x5, 0x12345
                instr_mem[8] = 32'h00000013; // nop
                instr_mem[9] = 32'h00000013; // nop
                instr_mem[10] = 32'h00000013; // nop
                instr_mem[11] = 32'h67828293; // addi x5, x5, 0x678
                instr_mem[12] = 32'h00000073; // ecall
            end
            2: begin // Forwarding
                instr_mem[0] = 32'h00a00093; // addi x1, x0, 10
                instr_mem[1] = 32'h00508113; // addi x2, x1, 5
                instr_mem[2] = 32'h001001b3; // add x3, x0, x1
                instr_mem[3] = 32'h00310233; // add x4, x2, x3
                instr_mem[4] = 32'h00000073; // ecall
            end
            3: begin // Load-Use Hazard
                instr_mem[0] = 32'h0ff00093; // addi x1, x0, 255
                instr_mem[1] = 32'h10000293; // addi x5, x0, 256
                instr_mem[2] = 32'h0012a023; // sw x1, 0(x5)
                instr_mem[3] = 32'h0002a103; // lw x2, 0(x5)
                instr_mem[4] = 32'h00110193; // addi x3, x2, 1
                instr_mem[5] = 32'h00000073; // ecall
            end
            4: begin // Control Hazard & Flushing
                instr_mem[0] = 32'h00100093; // addi x1, x0, 1
                instr_mem[1] = 32'h00100113; // addi x2, x0, 1
                instr_mem[2] = 32'h00208663; // beq x1, x2, target (+12)
                instr_mem[3] = 32'hbad00193; // addi x3, x0, 0xBAD (Should flush)
                instr_mem[4] = 32'hdad00193; // addi x3, x0, 0xDAD (Should flush)
                instr_mem[5] = 32'hace00213; // target: addi x4, x0, 0xACE
                instr_mem[6] = 32'h00000073; // ecall
            end
            5: begin // Meta (ECALL halt)
                instr_mem[0] = 32'h03200093; // addi x1, x0, 50
                instr_mem[1] = 32'h01900113; // addi x2, x0, 25
                instr_mem[2] = 32'h00000013; // nop
                instr_mem[3] = 32'h00000073; // ecall
                instr_mem[4] = 32'h00108093; // addi x1, x1, 1 (Should NOT execute)
                instr_mem[5] = 32'h00108093; // addi x1, x1, 1 (Should NOT execute)
            end
        endcase
    endtask

    // -------------------------------------------------------------------------
    // Main Test Sequence
    // -------------------------------------------------------------------------
    initial begin
        // 2A. Header Block
        $display("\n%s=======================================================%s", C_CYAN, C_RESET);
        $display("%s Testbench: %-38s %s", C_CYAN, FILE_NAME, C_RESET);
        $display("%s=======================================================%s\n", C_CYAN, C_RESET);

        // --- Initialization ---
        rst_n = 0;
        global_stall_i = 0;
        global_flush_i = 0;
        rs_dbg_addr_i = 0;
        #20;
        rst_n = 1;

        // =====================================================================
        // TEST 1: Happy Path
        // =====================================================================
        $display("%s[TEST 1] Happy Path: Basic ALU & Lui%s", C_BLUE, C_RESET);
        
        // 1. Setup
        load_test_program(1);
        rst_n = 0; #10; rst_n = 1; // Reset Core to start fresh
        
        // 2. Trigger (Run until halt or timeout)
        while (!core_halted_o && $time < 1000) @(posedge clk);
        #10; // Wait a few cycles for WB to settle

        // 3. Check (Verify Registers via Debug Port)
        
        // Check x3 (10 + 5 = 15)
        @(posedge clk); rs_dbg_addr_i = 3; 
        @(posedge clk); #1; observed_signal = rs_dbg_data_o;
        check(32'hF, "Reg x3 (ADD Result)");

        // Check x4 (10 - 5 = 5)
        @(posedge clk); rs_dbg_addr_i = 4;
        @(posedge clk); #1; observed_signal = rs_dbg_data_o;
        check(32'h5, "Reg x4 (SUB Result)");

        // Check x5 (0x12345678)
        @(posedge clk); rs_dbg_addr_i = 5;
        @(posedge clk); #1; observed_signal = rs_dbg_data_o;
        check(32'h12345678, "Reg x5 (LUI + ADDI Result)");

        // =====================================================================
        // TEST 2: Data Hazard Forwarding
        // =====================================================================
        $display("\n%s[TEST 2] Forwarding: EX and MEM Hazards%s", C_BLUE, C_RESET);
        
        // 1. Setup
        load_test_program(2);
        rst_n = 0; #10; rst_n = 1;

        // 2. Trigger
        while (!core_halted_o && $time < 2000) @(posedge clk);
        #10;

        // 3. Check
        // Expect x4 = (10+5) + 10 = 25 (0x19)
        @(posedge clk); rs_dbg_addr_i = 4;
        @(posedge clk); #1; observed_signal = rs_dbg_data_o;
        check(32'h19, "Reg x4 (Double Fwd Result)");

        // =====================================================================
        // TEST 3: Load-Use Hazard
        // =====================================================================
        $display("\n%s[TEST 3] Load-Use Hazard: Stall Insertion%s", C_BLUE, C_RESET);

        // 1. Setup
        load_test_program(3);
        rst_n = 0; #10; rst_n = 1;

        // 2. Trigger
        while (!core_halted_o && $time < 3000) @(posedge clk);
        #10;

        // 3. Check
        // Expect x3 = 255 (loaded) + 1 = 256 (0x100)
        @(posedge clk); rs_dbg_addr_i = 3;
        @(posedge clk); #1; observed_signal = rs_dbg_data_o;
        check(32'h100, "Reg x3 (Load-Use Result)");

        // =====================================================================
        // TEST 4: Control Hazard & Flushing
        // =====================================================================
        $display("\n%s[TEST 4] Branch Flushing%s", C_BLUE, C_RESET);

        // 1. Setup
        load_test_program(4);
        rst_n = 0; #10; rst_n = 1;

        // 2. Trigger
        while (!core_halted_o && $time < 4000) @(posedge clk);
        #10;

        // 3. Check
        // Verify x3 was NOT written (Should be 0)
        @(posedge clk); rs_dbg_addr_i = 3;
        @(posedge clk); #1; observed_signal = rs_dbg_data_o;
        check(32'h0, "Reg x3 (Flushed Instr)");

        // Verify x4 executed (Should be 0xACE)
        @(posedge clk); rs_dbg_addr_i = 4;
        @(posedge clk); #1; observed_signal = rs_dbg_data_o;
        check(32'hFFFF_FACE, "Reg x4 (Branch Target)"); // Unfortunatelly, this is Sign-extended

        // =====================================================================
        // TEST 5: Meta & System Halt
        // =====================================================================
        $display("\n%s[TEST 5] System Halt (ECALL)%s", C_BLUE, C_RESET);

        // 1. Setup
        load_test_program(5);
        rst_n = 0; #10; rst_n = 1;

        // 2. Trigger
        // Run slightly longer than needed to see if PC advances past ECALL
        repeat(20) @(posedge clk); 
        #1;

        // 3. Check
        // Verify Core Halted Signal
        observed_signal = {31'b0, core_halted_o};
        check(32'd1, "Core Halted Asserted");

        // Verify Execution stopped at x1 = 50 (Did not increment)
        @(posedge clk); rs_dbg_addr_i = 1;
        @(posedge clk); #1; observed_signal = rs_dbg_data_o;
        check(32'd50, "PC Frozen (Instr after ECALL ignored)");


        // 2C. Summary Footer
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
