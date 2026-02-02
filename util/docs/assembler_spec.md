# Risky Assembler Specification (`risky_assembler.py`)

## 1. Overview

The **Risky Assembler** is a custom, lightweight assembler designed specifically for the FPGA-based RV32I Core. It bridges the gap between human-readable assembly code and the raw binary format required by the FPGA's UART Bootloader.

Unlike standard GCC toolchains, this assembler includes a **Macro Expansion Layer** that emulates missing hardware instructions (like `BLT` or `LI`) using the limited instruction set actually implemented in the processor core.

## 2. Usage Guide

### 2.1. Command Line Interface

```bash
python risky_assembler.py <input_file> [-o OUTPUT] [--hex]

```

| Argument | Description | Default |
| --- | --- | --- |
| `input_file` | Path to the source assembly file (`.asm`, `.s`). | (Required) |
| `-o`, `--output` | Path for the generated binary file. | `program.bin` |
| `--hex` | Optional flag. If set, also generates a text-based Hex Dump (`.hex`). | `False` |

### 2.2. Output Formats

1. **Binary (`.bin`):** The primary output. Contains raw 32-bit Little-Endian machine code. This file is intended to be sent over UART to the `loader_unit`.
2. **Hex Dump (`.hex`):** (Optional) A human-readable text file containing the ASCII hexadecimal representation of each instruction (e.g., `00500093`). Used for debugging or Verilog `$readmemh` initialization.

---

## 3. Syntax Reference

### 3.1. General Rules

* **Comments:** Begin with `#`. Everything after the hash is ignored.
* **Labels:** define a jump target. Must end with a colon (`:`). Can be on their own line or preceding an instruction.
* *Example:* `loop:` or `loop: addi x1, x1, 1`

### 3.2. Register Naming

The assembler supports both raw indices and standard RISC-V ABI names.

| Raw | ABI Name | Description |
| --- | --- | --- |
| `x0` | `zero` | Hardwired Zero |
| `x1` | `ra` | Return Address |
| `x2` | `sp` | Stack Pointer |
| `x5` - `x7` | `t0` - `t2` | Temporaries |
| `x8` | `s0` / `fp` | Saved / Frame Pointer |
| `x10` - `x17` | `a0` - `a7` | Arguments / Return Values |
| ... | ... | ... |
| `x31` | `t6` | **Reserved for Assembler Macros** (See Section 4.3) |

### 3.3. Immediate Values

Supports three number formats:

* **Decimal:** `10`, `-5`
* **Hexadecimal:** `0xFF`, `0x1A`
* **Binary:** `0b1010`

---

## 4. Supported Instruction Set

The assembler natively encodes the following instructions which map 1:1 to the hardware implementation.

### 4.1. Native Hardware Instructions

| Category | Mnemonics | format |
| --- | --- | --- |
| **Arithmetic (R)** | `add`, `sub`, `xor`, `or`, `and`, `slt`, `sltu`, `sll`, `srl`, `sra` | `OP rd, rs1, rs2` |
| **Arithmetic (I)** | `addi`, `xori`, `ori`, `andi`, `slti`, `sltiu` | `OP rd, rs1, imm` |
| **Shifts (I)** | `slli`, `srli`, `srai` | `OP rd, rs1, shamt` |
| **Loads** | `lb`, `lh`, `lw`, `lbu`, `lhu` | `OP rd, offset(rs1)` |
| **Stores** | `sb`, `sh`, `sw` | `OP rs2, offset(rs1)` |
| **Branches** | `beq`, `bne` | `OP rs1, rs2, label` |
| **Jumps** | `jal` | `jal rd, label` |
| **Indirect Jump** | `jalr` | `jalr rd, rs1, offset` |
| **System** | `ecall` | `ecall` |
| **Upper Imm** | `lui` | `lui rd, imm` |

### 4.2. Pseudo-Instructions (Macros)

These instructions do not exist in the hardware. The assembler automatically expands them into valid native sequences.

**Note:** Branch macros (`blt`, `bgt`, etc.) utilize the `t6` (`x31`) register as a scratchpad. **Do not rely on `t6` preserving data across these macro calls.**

| Macro | Arguments | Expansion Logic | Description |
| --- | --- | --- | --- |
| **`nop`** | *None* | `addi x0, x0, 0` | No Operation |
| **`mv`** | `rd, rs` | `addi rd, rs, 0` | Copy register |
| **`not`** | `rd, rs` | `xori rd, rs, -1` | Bitwise inversion |
| **`neg`** | `rd, rs` | `sub rd, x0, rs` | Negate (2's complement) |
| **`li`** | `rd, imm` | `addi` (if < 12 bit)<br><br>OR `lui` + `addi` | Load Immediate (Smart expansion) |
| **`j`** | `label` | `jal x0, label` | Unconditional jump |
| **`ret`** | *None* | `jalr x0, ra, 0` | Return from function |
| **`blt`** | `rs1, rs2, label` | `slt t6, rs1, rs2`<br><br>`bne t6, zero, label` | Branch if Less Than |
| **`bgt`** | `rs1, rs2, label` | `slt t6, rs2, rs1`<br><br>`bne t6, zero, label` | Branch if Greater Than |
| **`ble`** | `rs1, rs2, label` | `slt t6, rs2, rs1`<br><br>`beq t6, zero, label` | Branch if Less or Equal |
| **`bge`** | `rs1, rs2, label` | `slt t6, rs1, rs2`<br><br>`beq t6, zero, label` | Branch if Greater or Equal |

---

## 5. Memory & Addressing Constraints

1. **Branch Reach:** B-Type instructions (`beq`, `bne`) have a range of ±4KB from the PC. The assembler checks this limit and will likely error (or fail to fit) if a label is too far.
2. **Jump Reach:** J-Type instructions (`jal`) have a range of ±1MB.
3. **Address 0:** The assembler assumes code execution starts at address `0x00000000`.
4. **Endianness:** The output binary is **Little-Endian**.
* Instruction `0x00500093` (`addi x1, x0, 5`) is stored as bytes: `93`, `00`, `50`, `00`.



## 6. Error Handling

The assembler will terminate with a descriptive error message in the following cases:

* **Unknown Instruction:** Typo or unsupported opcode.
* **Undefined Label:** Jumping to a label that was never declared.
* **Immediate Overflow:** Providing a constant that does not fit in the instruction's bit width (e.g., `addi` with a value > 2047).
* **Syntax Error:** Malformed arguments (e.g., missing commas).
