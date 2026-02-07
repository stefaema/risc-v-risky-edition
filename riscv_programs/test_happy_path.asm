# ------------------------------------------------------------------------------
# Test 1: Happy Path Check
# Verifies basic ALU operations and 32-bit constant loading.
# ------------------------------------------------------------------------------

main:
    # 1. Initialize constants
    addi x1, x0, 10      # x1 = 10 (0xA)
    addi x2, x0, 5       # x2 = 5  (0x5)
    
    # 2. Pipeline Clearance (Let registers write back)
    nop                  # addi x0, x0, 0
    nop
    nop
    
    # 3. Basic Arithmetic
    add  x3, x1, x2      # x3 = 15 (0xF)
    sub  x4, x1, x2      # x4 = 5  (0x5)
    
    # 4. Big Number Loading (Isolated)
    # Goal: Load 0x12345678
    lui  x5, 0x12345     # x5 = 0x12345000
    nop                  # Wait for LUI to clear EX/MEM
    nop                  # Wait for LUI to clear MEM/WB
    nop                  # Wait for LUI to write back
    addi x5, x5, 0x678   # x5 = 0x12345678
    
    # 5. Halt
    ecall                # Trigger is_halt signal
