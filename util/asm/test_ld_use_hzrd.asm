# ------------------------------------------------------------------------------
# Test 3: Load-Use Hazard
# Verifies hardware stall (bubble insertion) when LW is followed by a USE.
# ------------------------------------------------------------------------------

main:
    # Setup: Store a value in memory address 0x100
    addi x1, x0, 255     # x1 = 0xFF
    addi x5, x0, 256     # x5 = 0x100 (Address)
    sw   x1, 0(x5)       # Memory[0x100] = 255
    
    # 1. Load the value
    lw   x2, 0(x5)       # x2 = 255
    
    # 2. Immediate Use
    # Hardware MUST stall PC/IF/ID and insert NOP in EX.
    addi x3, x2, 1       # x3 = 255 + 1 = 256 (0x100)
    
    ecall
