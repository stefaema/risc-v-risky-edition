#---------------------------------------------
# Test: All I-Type Instructions
# Verifies correct execution of all I-Type instructions.
#---------------------------------------------

main:
    addi x1, x0, 10        # x1 = 10
    slti x2, x1, 15        # x2 = 1 (10 < 15)
    slti x3, x1, 5         # x3 = 0 (10 < 5)
    andi x4, x1, 7         # x4 = 10 & 7 = 2
    ori  x5, x1, 4         # x5 = 10 | 4 = 14
    xori x6, x1, 12        # x6 = 10 ^ 12 = 6
    slli x7, x1, 2         # x7 = 10 << 2 = 40
    srli x8, x1, 1         # x8 = 10 >> 1 = 5
    srai x9, x1, 1         # x9 = 10 >> 1 (arithmetic) = 5

    ecall
