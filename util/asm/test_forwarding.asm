# ------------------------------------------------------------------------------
# Test 2: Data Hazard Forwarding
# Tests EX-Hazard and MEM-Hazard bypass paths.
# ------------------------------------------------------------------------------

main:
    addi x1, x0, 10      # x1 = 0xA
    
    # --- EX Hazard ---
    # Result of previous line (x1) is in EX/MEM. 
    # Must forward from ALU_Result_M to ALU_OpA_E.
    addi x2, x1, 5       # x2 = 0xA + 0x5 = 0xF
    
    # --- MEM Hazard ---
    # x1 is now in MEM/WB. Must forward from Writeback_Data_W to ALU_OpB_E.
    add  x3, x0, x1      # x3 = 0 + 0xA = 0xA
    
    # --- Double Forwarding ---
    # x2 (0xF) is in EX/MEM -> Forward to OpA
    # x3 (0xA) is in MEM/WB -> Forward to OpB
    add  x4, x2, x3      # x4 = 0xF + 0xA = 0x19
    
    ecall

    # Should result in:
    # x1 = 0xA
    # x2 = 0xF
    # x3 = 0xA
    # x4 = 0x19
