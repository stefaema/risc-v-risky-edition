# ------------------------------------------------------------------------------
# Test 5: System Halt (ECALL)
# Verifies that ECALL freezes the pipeline and stops the PC.
# ------------------------------------------------------------------------------

main:
    addi x1, x0, 50
    addi x2, x0, 25
    nop
    ecall                # Core should assert core_halted_o and freeze PC
    
    # If these execute, the halt logic failed
    addi x1, x1, 1       
    addi x1, x1, 1
