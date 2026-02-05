# ------------------------------------------------------------------------------
# Test: Load-Use Hazard
# Verifies hardware stall (bubble insertion) when LW is followed by a USE.
# ------------------------------------------------------------------------------

main:
    # Setup: Assume the value 0x40 is at address x0 already stored
    addi x1, x0, 256     # x1 = 0x100



    # 1. Load the value
    lb   x2, 0(x0)       # x2 = 0x40
    
    # 2. Immediate Use
    # Hardware MUST stall PC/IF/ID and insert NOP in EX.
    add x3, x2, x1       # x3 = 0x40 + 0x100 = 0x140
    
    ecall

# Should result in:
# x1 = 0x100
# x2 = 0x40
# x3 = 0x140
