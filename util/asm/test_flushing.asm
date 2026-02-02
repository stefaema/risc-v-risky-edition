# ------------------------------------------------------------------------------
# Test 4: Control Hazard & Flushing
# Verifies that speculative instructions are killed on a taken branch.
# ------------------------------------------------------------------------------

main:
    addi x1, x0, 1       # x1 = 1
    addi x2, x0, 1       # x2 = 1
    
    # 1. Conditional Branch (Taken)
    beq  x1, x2, target  # 1 == 1, Branch Taken
    
    # --- FLUSH ZONE ---
    # These instructions enter the pipeline but should be flushed!
    addi x3, x0, 0xBAD   # Should NOT execute
    addi x3, x0, 0xDAD   # Should NOT execute
    
target:
    # 2. Execution resumes here
    addi x4, x0, 0xACE   # x4 = 0xACE
    
    ecall
