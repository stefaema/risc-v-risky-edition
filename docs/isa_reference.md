# RISC-V Instruction Set Specifications (RV32I) - Functional Reference

This document provides the encoding reference and functional behavior (RTL) for the instructions required by the project.

**Legend:**
*   `R[x]`: Register x
*   `M[addr]`: Memory at address
*   `PC`: Program Counter
*   `Imm`: Immediate value
*   `SE`: Sign-Extend
*   `ZE`: Zero-Extend
*   `&, |, ^`: Bitwise AND, OR, XOR
*   `<<, >>`: Logical Shift
*   `>>>`: Arithmetic Shift

## 1. R-Type (Register-to-Register)

**Format Structure:**
| 31 ... 25 | 24 ... 20 | 19 ... 15 | 14 ... 12 | 11 ... 7 | 6 ... 0 |
|:---:|:---:|:---:|:---:|:---:|:---:|
| **funct7** | **rs2** | **rs1** | **funct3** | **rd** | **opcode** |
k

| Instruction | funct7 | rs2 | rs1 | funct3 | rd | opcode | Functional Description (RTL) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| **add** | `0000000` | src2 | src1 | `000` | dest | `0110011` | `R[rd] = R[rs1] + R[rs2]` |
| **sub** | `0100000` | src2 | src1 | `000` | dest | `0110011` | `R[rd] = R[rs1] - R[rs2]` |
| **sll** | `0000000` | src2 | src1 | `001` | dest | `0110011` | `R[rd] = R[rs1] << R[rs2][4:0]` |
| **slt** | `0000000` | src2 | src1 | `010` | dest | `0110011` | `R[rd] = (R[rs1] < R[rs2]) ? 1 : 0` (Signed) |
| **sltu**| `0000000` | src2 | src1 | `011` | dest | `0110011` | `R[rd] = (R[rs1] < R[rs2]) ? 1 : 0` (Unsigned) |
| **xor** | `0000000` | src2 | src1 | `100` | dest | `0110011` | `R[rd] = R[rs1] ^ R[rs2]` |
| **srl** | `0000000` | src2 | src1 | `101` | dest | `0110011` | `R[rd] = R[rs1] >> R[rs2][4:0]` |
| **sra** | `0100000` | src2 | src1 | `101` | dest | `0110011` | `R[rd] = R[rs1] >>> R[rs2][4:0]` (Sign-extended shift) |
| **or** | `0000000` | src2 | src1 | `110` | dest | `0110011` | `R[rd] = R[rs1] \| R[rs2]` |
| **and** | `0000000` | src2 | src1 | `111` | dest | `0110011` | `R[rd] = R[rs1] & R[rs2]` |


## 2. I-Type (Immediate)

**Format Structure:**
| 31 ... 20 | 19 ... 15 | 14 ... 12 | 11 ... 7 | 6 ... 0 |
|:---:|:---:|:---:|:---:|:---:|
| **imm[11:0]** | **rs1** | **funct3** | **rd** | **opcode** |

### 2.1. Arithmetic & Logic Immediates
**Opcode:** `0010011`

| Instruction | imm[11:0] / funct7 | rs1 | funct3 | rd | opcode | Functional Description (RTL) |
| :--- | :---: | :---: | :---: | :---: | :---: | :--- |
| **addi** | imm[11:0] | src1 | `000` | dest | `0010011` | `R[rd] = R[rs1] + SE(imm)` |
| **slti** | imm[11:0] | src1 | `010` | dest | `0010011` | `R[rd] = (R[rs1] < SE(imm)) ? 1 : 0` (Signed) |
| **sltiu**| imm[11:0] | src1 | `011` | dest | `0010011` | `R[rd] = (R[rs1] < SE(imm)) ? 1 : 0` (Unsigned) |
| **xori** | imm[11:0] | src1 | `100` | dest | `0010011` | `R[rd] = R[rs1] ^ SE(imm)` |
| **ori** | imm[11:0] | src1 | `110` | dest | `0010011` | `R[rd] = R[rs1] \| SE(imm)` |
| **andi** | imm[11:0] | src1 | `111` | dest | `0010011` | `R[rd] = R[rs1] & SE(imm)` |

**Shift Immediates:**
*Shifts use only the lower 5 bits of the immediate for the shift amount (shamt).*

| Instruction | imm[11:5] | imm[4:0] | rs1 | funct3 | rd | opcode | Functional Description (RTL) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| **slli** | `0000000` | shamt | src1 | `001` | dest | `0010011` | `R[rd] = R[rs1] << shamt` |
| **srli** | `0000000` | shamt | src1 | `101` | dest | `0010011` | `R[rd] = R[rs1] >> shamt` |
| **srai** | `0100000` | shamt | src1 | `101` | dest | `0010011` | `R[rd] = R[rs1] >>> shamt` (Arithmetic) |

### 2.2. Loads
**Opcode:** `0000011`

| Instruction | imm[11:0] | rs1 | funct3 | rd | opcode | Functional Description (RTL) |
| :--- | :---: | :---: | :---: | :---: | :---: | :--- |
| **lb** | offset | base | `000` | dest | `0000011` | `R[rd] = SE(M[R[rs1] + SE(imm)][7:0])` |
| **lh** | offset | base | `001` | dest | `0000011` | `R[rd] = SE(M[R[rs1] + SE(imm)][15:0])` |
| **lw** | offset | base | `010` | dest | `0000011` | `R[rd] = M[R[rs1] + SE(imm)][31:0]` |
| **lbu**| offset | base | `100` | dest | `0000011` | `R[rd] = ZE(M[R[rs1] + SE(imm)][7:0])` |
| **lhu**| offset | base | `101` | dest | `0000011` | `R[rd] = ZE(M[R[rs1] + SE(imm)][15:0])` |

### 2.3. Jump Indirect
**Opcode:** `1100111`

| Instruction | imm[11:0] | rs1 | funct3 | rd | opcode | Functional Description (RTL) |
| :--- | :---: | :---: | :---: | :---: | :---: | :--- |
| **jalr** | offset | base | `000` | dest | `1100111` | `R[rd] = PC + 4`; `PC = (R[rs1] + SE(imm)) & ~1` |


## 3. S-Type (Store)

**Format Structure:**
| 31 ... 25 | 24 ... 20 | 19 ... 15 | 14 ... 12 | 11 ... 7 | 6 ... 0 |
|:---:|:---:|:---:|:---:|:---:|:---:|
| **imm[11:5]** | **rs2** | **rs1** | **funct3** | **imm[4:0]** | **opcode** |

**Opcode:** `0100011`

| Instruction | imm[11:5] | rs2 | rs1 | funct3 | imm[4:0] | opcode | Functional Description (RTL) |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| **sb** | offset[11:5] | src | base | `000` | offset[4:0] | `0100011` | `M[R[rs1] + SE(imm)] = R[rs2][7:0]` |
| **sh** | offset[11:5] | src | base | `001` | offset[4:0] | `0100011` | `M[R[rs1] + SE(imm)] = R[rs2][15:0]` |
| **sw** | offset[11:5] | src | base | `010` | offset[4:0] | `0100011` | `M[R[rs1] + SE(imm)] = R[rs2][31:0]` |


## 4. B-Type (Branch)

**Format Structure:**
| 31 | 30 ... 25 | 24 ... 20 | 19 ... 15 | 14 ... 12 | 11 ... 8 | 7 | 6 ... 0 |
|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **imm[12]** | **imm[10:5]** | **rs2** | **rs1** | **funct3** | **imm[4:1]** | **imm[11]** | **opcode** |

**Opcode:** `1100011`

| Instruction | funct3 | opcode | Functional Description (RTL) |
| :--- | :---: | :---: | :--- |
| **beq** | `000` | `1100011` | `if (R[rs1] == R[rs2]) PC = PC + SE(imm)` |
| **bne** | `001` | `1100011` | `if (R[rs1] != R[rs2]) PC = PC + SE(imm)` |


## 5. U-Type (Upper Immediate)

**Format Structure:**
| 31 ... 12 | 11 ... 7 | 6 ... 0 |
|:---:|:---:|:---:|
| **imm[31:12]** | **rd** | **opcode** |

**Opcode:** `0110111`

| Instruction | imm[31:12] | rd | opcode | Functional Description (RTL) |
| :--- | :---: | :---: | :--- | :--- |
| **lui** | immediate[31:12] | dest | `0110111` | `R[rd] = imm << 12` (Loads upper 20 bits, lower 12 are 0) |


## 6. J-Type (Unconditional Jump)

**Format Structure:**
| 31 | 30 ... 21 | 20 | 19 ... 12 | 11 ... 7 | 6 ... 0 |
|:---:|:---:|:---:|:---:|:---:|:---:|
| **imm[20]** | **imm[10:1]** | **imm[11]** | **imm[19:12]** | **rd** | **opcode** |

**Opcode:** `1101111`

| Instruction | opcode | Functional Description (RTL) |
| :--- | :---: | :--- |
| **jal** | `1101111` | `R[rd] = PC + 4`; `PC = PC + SE(imm)` |


## 7. System (HALT)

**Format (I-Type Structure):**

| Instruction | imm[11:0] | rs1 | funct3 | rd | opcode | Functional Description (RTL) |
| :--- | :---: | :---: | :---: | :---: | :---: | :--- |
| **ecall** | `000000000000` | `00000` | `000` | `00000` | `1110011` | Raise Environment Call Exception (Control Transfer to Trap Handler) |
