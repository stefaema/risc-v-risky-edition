# ------------------------------------------------------------------------------
# Test: Byte, Halfword, and Word Load/Store Instructions
# Tests LB, LH, LW, LBU, LHU, SB, SH, SW instructions for word = 32 bit.
# ------------------------------------------------------------------------------

main:
    # Setup: Store 0xDEADBEEF at address in x0
    li   x1, 0xDEADBEEF      # x1 = 0xDEADBEEF
    sw    x1, 0(x0)          # Store word at address x0

    # 1. Load Byte (Signed)
    lb    x2, 0(x0)          # x2 = 0xFFFFFFEF (sign-extended)

    # 2. Load Halfword (Signed)
    lh    x3, 0(x0)          # x3 = 0xFFFFBEEF (sign-extended)

    # 3. Load Word
    lw    x4, 0(x0)          # x4 = 0xDEADBEEF

    # 4. Load Byte (Unsigned)
    lbu   x5, 0(x0)          # x5 = 0x000000EF (zero-extended)

    # 5. Load Halfword (Unsigned)
    lhu   x6, 0(x0)          # x6 = 0x0000BEEF (zero-extended)

    # 6. Store Byte
    li     x7, 0xAA          # Use li for safety
    sb     x7, 1(x0)         
    lbu    x8, 1(x0)         # Use lbu if you don't want 0xFFFFFFAA

    # 7. Store Halfword
    li     x9, 0xBBBB        # li will use lui + addi to handle the large value
    sh     x9, 2(x0)         
    lhu    x10, 2(x0)        # Use lhu if you want 0x0000BBBB

    ecall

# This should end-up with 0xBBBBAAEF at address x0
