_start:
    # ========================================================================
    # 0. Start & Loop Detection Logic
    # ========================================================================
    # This section detects if we just jumped back from the end via JALR.
    # Instruction at Addr 0
    nop                         
    # Instruction at Addr 4: Increment x20 every time we pass here
    addi x20, x20, 1            
    # Instruction at Addr 8: Compare target
    addi x21, x0, 2             
    # Instruction at Addr 12: If x20 == 2, it means we finished and jumped back
    # Offset to FINISH: +64 bytes (Target Addr 76)
    beq  x20, x21, FINISH       

    # ========================================================================
    # 1. U-Type & S-Type Test (DMEM 4KB)
    # ========================================================================
    # Registers: x10, x11 | DMEM Offset: 0x004
    lui  x10, 0                 # [U-Type] Base 0 for DMEM
    addi x11, x0, 0x55          # [I-Type] Data = 85
    sw   x11, 4(x10)            # [S-Type] Store to DMEM addr 4

    # ========================================================================
    # 2. Data Hazard: Load-Use (Stall)
    # ========================================================================
    # Registers: x12, x13
    # Logic: x13 depends on x12 immediately. Pipeline must stall.
    lw   x12, 4(x10)            # [I-Type Load] Load 0x55
    addi x13, x12, 1            # [Hazard] x13 = 0x55 + 1 = 0x56

    # ========================================================================
    # 3. Data Hazard: Forwarding (EX-EX)
    # ========================================================================
    # Registers: x1, x2, x3
    # Logic: addi to two registers immediately before an add (as requested).
    addi x1, x0, 15             # Set x1 = 15
    addi x2, x0, 25             # Set x2 = 25
    add  x3, x2, x1             # [R-Type Forwarding] x3 = 25 + 15 = 40 (0x28)

    # ========================================================================
    # 4. Control Hazard: Branch (B-Type)
    # ========================================================================
    # Register: x4 (Flush check)
    
    # Case A: Branch Not Taken
    beq  x1, x2, ERROR_TRAP     # 15 != 25. Fall through.
    
    # Case B: Branch Taken (Flush check)
    # Offset to J-TEST: +12 bytes
    beq  x1, x1, J_TEST         
    addi x4, x0, 0xBAD          # [FLUSH ZONE] x4 must remain 0

ERROR_TRAP:
    beq  x0, x0, ERROR_TRAP     # Infinite loop if something is wrong

J_TEST:
    # ========================================================================
    # 5. Control Hazard: Unconditional Jump (J-Type)
    # ========================================================================
    # Register: x5 (Link)
    # Offset to JALR_TEST: +8 bytes
    jal  x5, JALR_TEST          
    addi x4, x0, 0xBAD          # [FLUSH ZONE] Skip

JALR_TEST:
    # ========================================================================
    # 6. Control Hazard: Jump Register (I-Type Jump)
    # ========================================================================
    # Requirement: Use jalr with x0 and imm 0 to send PC back to the beginning.
    # This will trigger the loop detection at the top.
    jalr x0, x0, 0              # [J-Type Jump] Jump to address 0
    addi x4, x0, 0xBAD          # [FLUSH ZONE] Skip

FINISH:
    # ========================================================================
    # 7. Final Halt Section
    # ========================================================================
    # This is reached only when the jalr successfully returns to start and 
    # the beq (x20 == 2) triggers.
    addi x22, x0, 1             # Final indicator x22 = 1
    
HALT:
    ecall

# ============================================================================
# EXPECTED REGISTER FILE CONTENTS (SUCCESS CRITERIA)
# ============================================================================
# When the UART dumps the registers, they must look like this:
#
# x0  = 0x00000000  (Constant Zero)
# x1  = 0x0000000F  (Decimal: 15)  -> Forwarding Source 1
# x2  = 0x00000019  (Decimal: 25)  -> Forwarding Source 2
# x3  = 0x00000028  (Decimal: 40)  -> SUCCESS: Forwarding (x1 + x2)
# x4  = 0x00000000  (Zero)         -> SUCCESS: No Branch/Jump Flushes failed
# x5  = 0x00000044  (Hex Address)  -> SUCCESS: JAL Link (PC+4 of JAL)
# x10 = 0x00000000                 -> SUCCESS: U-Type LUI
# x11 = 0x00000055  (Decimal: 85)  -> SUCCESS: Store Source
# x12 = 0x00000055  (Decimal: 85)  -> SUCCESS: Load Result
# x13 = 0x00000056  (Decimal: 86)  -> SUCCESS: Load-Use Hazard Stall
# x20 = 0x00000002                 -> SUCCESS: Code ran, jumped back, and ended
# x21 = 0x00000002                 -> Loop Comparison Constant
# x22 = 0x00000001                 -> Final Completion Flag
#
# DMEM[4] should contain 0x00000055
# ============================================================================
