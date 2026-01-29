
# ALU Architecture & Functional Specification

## 1. Overview
The ALU (Arithmetic Logic Unit) is a combinational logic block responsible for performing integer arithmetic, bitwise logic, and shift operations. In the RISC-V pipeline, the ALU executes the "Execute" (EX) stage.

It takes two 32-bit data inputs and a control signal, producing a 32-bit result and a specific "Zero" flag used for branch evaluations.

### Port Interface
| Signal Name | Direction | Width | Description |
| :--- | :---: | :---: | :--- |
| **SrcA** | Input | 32 | First operand (from Register File or PC). |
| **SrcB** | Input | 32 | Second operand (from Register File or Immediate). |
| **ALUControl** | Input | 4 | Selector signal determining the operation. |
| **ALUResult** | Output | 32 | The computation result. |
| **Zero** | Output | 1 | High (`1`) if `ALUResult == 0`. Used for Branches. |


## 2. Arithmetic Operations

### 2.1. Addition (`ADD`)
*   **Operations:** `add`, `addi`, `load`, `store`, `jalr`
*   **Logic:** `Result = SrcA + SrcB`
*   **Usage:**
    *   Standard addition.
    *   **Memory Address Calculation:** For loads/stores, `SrcA` is the base register, `SrcB` is the sign-extended immediate offset.
    *   **Jumps:** For `jalr`, calculates `PC = Rs1 + Imm`.

### 2.2. Subtraction (`SUB`)
*   **Operations:** `sub`, `beq`, `bne`
*   **Logic:** `Result = SrcA - SrcB`
*   **Branching Note:**
    *   The ALU performs subtraction to detect equality.
    *   If `SrcA - SrcB = 0`, the **Zero** flag is set to `1`.
    *   **BEQ** takes the branch if `Zero == 1`.
    *   **BNE** takes the branch if `Zero == 0`.


## 3. Comparison Operations (SLT vs. SLTU)

This section details the specific difference between signed and unsigned comparisons, which is crucial for correct CPU behavior.

### 3.1. Set Less Than (Signed) - `SLT`
*   **Logic:** `Result = (Signed(SrcA) < Signed(SrcB)) ? 1 : 0`
*   **Concept:**
    *   Inputs are treated as **Two's Complement** integers.
    *   The Most Significant Bit (MSB, bit 31) acts as the sign bit. `1` indicates negative, `0` indicates positive.
*   **Example:** Comparing -1 and 5.
    *   `SrcA` (-1) = `0xFFFFFFFF`
    *   `SrcB` (5)  = `0x00000005`
    *   In signed math, -1 is mathematically less than 5.
    *   **Result:** `1` (True).

### 3.2. Set Less Than Unsigned - `SLTU`
*   **Logic:** `Result = (Unsigned(SrcA) < Unsigned(SrcB)) ? 1 : 0`
*   **Concept:**
    *   Inputs are treated as raw binary magnitudes. There are no negative numbers.
    *   Bit 31 is just a very large power of 2 ($2^{31}$), not a sign bit.
*   **Example:** Comparing "Large Number" and 5.
    *   `SrcA` = `0xFFFFFFFF` (Which is 4,294,967,295 in unsigned).
    *   `SrcB` = `0x00000005` (5).
    *   4,294,967,295 is **not** less than 5.
    *   **Result:** `0` (False).

> **Hardware Implementation Note:**
> *   **SLT:** `Result = 1` if (SrcA negative and SrcB positive) OR (Signs are same AND SrcA - SrcB yields negative).
> *   **SLTU:** `Result = 1` if `SrcA < SrcB` (Pure magnitude comparison, often checked via the Carry/Borrow out of a subtractor).


## 4. Shift Operations

RISC-V defines shifts by the lower 5 bits of `SrcB` (shift amount).

### 4.1. Logical Shifts (`SLL`, `SRL`)
*   **Shift Left Logical (SLL):** Shifts bits left. Vacated LSBs are filled with **Zeros**.
    *   `0000 0001` << 1 = `0000 0010`
*   **Shift Right Logical (SRL):** Shifts bits right. Vacated MSBs are filled with **Zeros**.
    *   `1000 0000` >> 1 = `0100 0000`
    *   *Usage:* Unsigned integer division by powers of 2.

### 4.2. Arithmetic Shift (`SRA`)
*   **Shift Right Arithmetic (SRA):** Shifts bits right. Vacated MSBs are filled with the **Sign Bit (MSB)** of the original value.
*   **Why?** This preserves the sign of the number (2's complement).
    *   Example (-4 in 8-bit): `1111 1100` >>> 1
    *   **Result:** `1111 1110` (-2).
    *   If we used SRL, it would become `0111 1110` (positive 126), which would be mathematically incorrect for signed division.


## 5. Logical Operations
These are bitwise operations performed parallelly on every bit position [0 to 31].

*   **AND:** `Result = SrcA & SrcB` (Used to mask bits).
*   **OR:**  `Result = SrcA | SrcB` (Used to set bits).
*   **XOR:** `Result = SrcA ^ SrcB` (Used to toggle bits or check for differences).


