# ------------------------------------------------------------------------------
# Test: Control Hazard & Flushing
# Verifies that speculative instructions are killed on a taken branch.
# ------------------------------------------------------------------------------

main:
    addi x1, x0, 1       # x1 = 1
    addi x2, x0, 1       # x2 = 1
    
    # 1. Conditional Branch (Taken)
    beq  x1, x2, target  # 1 == 1, Branch Taken.
    
    # --- FLUSH ZONE ---
    # This instruction enters the pipeline but should be flushed!
    addi x3, x0, 0xBAD   # Should NOT execute

    
target:
    # Execution should continue here after the branch.
    lui x4, 0xACE00
    addi x4, x4, 0x0   #
    
    ecall


