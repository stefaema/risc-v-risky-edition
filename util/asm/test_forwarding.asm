# ------------------------------------------------------------------------------
# Test 2: Data Hazard Forwarding
# Tests EX-Hazard and MEM-Hazard bypass paths.
# ------------------------------------------------------------------------------

main:
    addi x1, x0, 10      # x1 = 10
    
    # --- EX Hazard ---
    # Result of previous line (x1) is in EX/MEM. 
    # Must forward from ALU_Result_M to ALU_OpA_E.
    addi x2, x1, 5       # x2 = 10 + 5 = 15
    
    # --- MEM Hazard ---
    # x1 is now in MEM/WB. Must forward from Writeback_Data_W to ALU_OpB_E.
    add  x3, x0, x1      # x3 = 0 + 10 = 10
    
    # --- Double Forwarding ---
    # x2 (15) is in EX/MEM -> Forward to OpA
    # x3 (10) is in MEM/WB -> Forward to OpB
    add  x4, x2, x3      # x4 = 15 + 10 = 25 (0x19)
    
    ecall
