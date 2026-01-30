// -----------------------------------------------------------------------------
// Module: ALU_cinate_tb
// Description: Comprehensive Testbench with ANSI Colored Output
// -----------------------------------------------------------------------------

module ALU_cinate_tb;

    // ------------------------------------------------
    // ANSI Color Definitions
    // ------------------------------------------------
    localparam string C_RESET  = "\033[0m";
    localparam string C_RED    = "\033[1;31m"; // Bold Red
    localparam string C_GREEN  = "\033[1;32m"; // Bold Green
    localparam string C_YELLOW = "\033[1;33m"; // Bold Yellow
    localparam string C_BLUE   = "\033[1;34m"; // Bold Blue
    localparam string C_CYAN   = "\033[1;36m"; // Bold Cyan

    // ------------------------------------------------
    // Signal Declaration
    // ------------------------------------------------
    logic [31:0] SrcA, SrcB;
    logic [3:0]  ALUControl;
    logic [31:0] ALUResult;
    logic        Zero;

    // Checking variables
    logic [31:0] ExpectedResult;
    int          error_count = 0;
    int          test_count = 0;

    // Instantiate the DUT
    ALU_cinate dut (
        .SrcA(SrcA),
        .SrcB(SrcB),
        .ALUControl(ALUControl),
        .ALUResult(ALUResult),
        .Zero(Zero)
    );

    // ------------------------------------------------
    // Task: Check Output
    // ------------------------------------------------
    task check(input string op_name, input bit verbose = 1);
        begin
            #1; // Wait for logic
            if (ALUResult !== ExpectedResult) begin
                $display("%s[FAIL]%s %s | A: 0x%h | B: 0x%h | Exp: 0x%h | Got: 0x%h", 
                    C_RED, C_RESET, op_name, SrcA, SrcB, ExpectedResult, ALUResult);
                error_count++;
            end else begin
                if (verbose) begin
                    $display("%s[PASS]%s %s | Result: 0x%h", 
                        C_GREEN, C_RESET, op_name, ALUResult);
                end
            end
            test_count++;
        end
    endtask

    // ------------------------------------------------
    // Main Stimulus
    // ------------------------------------------------
    initial begin
        // Pretty Header
        $display("\n%s=======================================================%s", C_CYAN, C_RESET);
        $display("%s       ALU-cinate Verification Environment             %s", C_CYAN, C_RESET);
        $display("%s=======================================================%s\n", C_CYAN, C_RESET);

        // ------------------------------------
        // 1. ADD Operation
        // ------------------------------------
        $display("%s--- Testing Arithmetic (ADD/SUB) ---%s", C_BLUE, C_RESET);
        
        ALUControl = 4'b0000; // ADD
        SrcA = 32'd10; SrcB = 32'd20; ExpectedResult = 32'd30;
        check("ADD_Simple");

        SrcA = 32'hFFFFFFFF; SrcB = 32'd1; ExpectedResult = 32'd0;
        check("ADD_Overflow");

        // ------------------------------------
        // 2. SUB Operation & Zero Flag
        // ------------------------------------
        ALUControl = 4'b1000; // SUB
        SrcA = 32'd50; SrcB = 32'd50; ExpectedResult = 32'd0;
        check("SUB_Zero  ");
        
        if (Zero !== 1'b1) 
            $display("%s[FAIL]%s Zero Flag Logic | Expected 1, Got %b", C_RED, C_RESET, Zero);
        else 
            $display("%s[PASS]%s Zero Flag Logic | Correctly set High", C_GREEN, C_RESET);

        SrcA = 32'd10; SrcB = 32'd20; ExpectedResult = -32'd10;
        check("SUB_Neg   ");

        // ------------------------------------
        // 3. Logic Operations
        // ------------------------------------
        $display("\n%s--- Testing Logic (AND/OR/XOR) ---%s", C_BLUE, C_RESET);
        SrcA = 32'hF0F0F0F0; SrcB = 32'h0F0F0F0F;
        
        ALUControl = 4'b0111; // AND
        ExpectedResult = 32'h00000000;
        check("AND_Mask  ");

        ALUControl = 4'b0110; // OR
        ExpectedResult = 32'hFFFFFFFF;
        check("OR_Set    ");

        ALUControl = 4'b0100; // XOR
        ExpectedResult = 32'hFFFFFFFF;
        check("XOR_Toggle");

        // ------------------------------------
        // 4. Shift Operations
        // ------------------------------------
        $display("\n%s--- Testing Shifts (SLL/SRL/SRA) ---%s", C_BLUE, C_RESET);
        
        // SLL
        SrcA = 32'h00000001; SrcB = 32'd4; 
        ALUControl = 4'b0001; ExpectedResult = 32'h00000010;
        check("SLL_Shift ");

        // SRL (Logical)
        SrcA = 32'hF0000000; SrcB = 32'd4;
        ALUControl = 4'b0101; ExpectedResult = 32'h0F000000;
        check("SRL_Logic ");

        // SRA (Arithmetic - Sign Extension check)
        SrcA = 32'hF0000000; SrcB = 32'd4;
        ALUControl = 4'b1101; ExpectedResult = 32'hFF000000;
        check("SRA_Arith ");

        // ------------------------------------
        // 5. Comparisons (SLT vs SLTU)
        // ------------------------------------
        $display("\n%s--- Testing Comparisons (SLT/SLTU) ---%s", C_BLUE, C_RESET);
        
        SrcA = 32'hFFFFFFFF; // -1 (Signed) or MaxUInt (Unsigned)
        SrcB = 32'h00000001; //  1

        // SLT (-1 < 1 is True)
        ALUControl = 4'b0010; ExpectedResult = 32'd1;
        check("SLT_Sign  ");

        // SLTU (MaxUInt < 1 is False)
        ALUControl = 4'b0011; ExpectedResult = 32'd0;
        check("SLTU_Unsig");

        // ------------------------------------
        // 6. Randomized Testing
        // ------------------------------------
        $display("\n%s--- Running 1000 Randomized Tests ---%s", C_YELLOW, C_RESET);
        
        repeat (1000) begin
            SrcA = $random;
            SrcB = $random;
            case ($urandom_range(0, 9))
                0: begin ALUControl = 4'b0000; ExpectedResult = SrcA + SrcB; end
                1: begin ALUControl = 4'b1000; ExpectedResult = SrcA - SrcB; end
                2: begin ALUControl = 4'b0001; ExpectedResult = SrcA << SrcB[4:0]; end
                3: begin ALUControl = 4'b0010; ExpectedResult = ($signed(SrcA) < $signed(SrcB)) ? 1 : 0; end
                4: begin ALUControl = 4'b0011; ExpectedResult = (SrcA < SrcB) ? 1 : 0; end
                5: begin ALUControl = 4'b0100; ExpectedResult = SrcA ^ SrcB; end
                6: begin ALUControl = 4'b0101; ExpectedResult = SrcA >> SrcB[4:0]; end
                7: begin ALUControl = 4'b1101; ExpectedResult = $signed(SrcA) >>> SrcB[4:0]; end
                8: begin ALUControl = 4'b0110; ExpectedResult = SrcA | SrcB; end
                9: begin ALUControl = 4'b0111; ExpectedResult = SrcA & SrcB; end
            endcase
            // False = Don't print every PASS, only FAILS
            check("RANDOM", 0); 
        end
        $display("Randomized testing complete.");

        // ------------------------------------
        // Summary
        // ------------------------------------
        $display("\n%s=======================================================%s", C_CYAN, C_RESET);
        if (error_count == 0) begin
            $display("%s        [SUCCESS] All %0d tests passed!             %s", C_GREEN, test_count, C_RESET);
            $display("           Your ALU is officially %sALU-cinating!%s", C_YELLOW, C_RESET);
        end else begin
            $display("%s        [FAILURE] %0d errors found in %0d tests.    %s", C_RED, error_count, test_count, C_RESET);
        end
        $display("%s=======================================================%s\n", C_CYAN, C_RESET);
    end

endmodule
