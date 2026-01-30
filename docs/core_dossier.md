# Hardware Architecture Dossier: RV32I Pipelined Core

**Version:** 1.0
**Module:** `riscv_core`
**Status:** Architecture Definition
**Target:** FPGA / RTL Simulation

---

## 1. Executive Summary

This document specifies the architectural implementation of the **RISC-V 32-bit (RV32I)** pipelined processor core. This design implements the unprivileged integer instruction set with a classic 5-stage pipeline.

The core is designed as a standalone hardware unit, exposing standard memory interfaces and control signals, decoupled from any debug or communication peripherals. It features full hardware hazard handling (forwarding and stalling) and dynamic branch prediction logic (static-not-taken).

---

## 2. Pipeline Architecture Overview

The processor implements a **Harvard Architecture** with five distinct stages.

| Stage | Description |
| --- | --- |
| **1. Fetch (IF)** | Generates the Program Counter (PC) and retrieves binary instructions from Instruction Memory. |
| **2. Decode (ID)** | Decodes opcodes, reads Register File (`x0-x31`), handles Data Hazards, and generates immediate values. |
| **3. Execute (EX)** | Performs ALU operations, calculates branch targets, resolves branch conditions, and handles Data Forwarding. |
| **4. Memory (MEM)** | Accesses Data Memory for Load/Store operations. |
| **5. Writeback (WB)** | Writes results (from ALU or Memory) back to the Register File. |

---

## 3. Detailed Module Specifications

### 3.1. Stage 1: Instruction Fetch (IF)

#### `program_counter.sv`

* **Function:** Holds the address of the current instruction.
* **Inputs:** `clk`, `reset`, `stall` (from Hazard Unit), `next_pc`.
* **Outputs:** `pc_out` (32-bit).
* **Logic:**
* On `reset`: Sets PC to `0x00000000`.
* On `stall`: Holds current value.
* Otherwise: Updates to `next_pc`.



#### `pc_adder.sv`

* **Function:** Calculates the sequential next instruction address.
* **Logic:** `pc_out + 4`.

#### `pc_mux.sv`

* **Function:** Selects the source of the next PC.
* **Inputs:**
* `seq_pc` (PC+4).
* `branch_target` (PC + Immediate).
* `jump_reg_target` (Register + Immediate).
* `pc_src_sel` (Control Signal).


* **Logic:** Prioritizes Branch/Jump targets over sequential execution when a control transfer occurs.

---

### 3.2. Stage 2: Instruction Decode (ID)

#### `register_file.sv`

* **Standard:** RV32I Base Integer Register File.
* **Storage:** 32 registers of 32-bit width (`x0` - `x31`).
* **Constraint:** `x0` is hardwired to logic `0`. Writes to `x0` are ignored.
* **Ports:**
* 2 Read Ports (`rs1`, `rs2`).
* 1 Write Port (`rd`, `write_data`, `reg_write_en`).


* **Timing:** Reads are asynchronous (or falling-edge optimized); Writes occur on `posedge clk`.

#### `immediate_generator.sv`

* **Function:** Extracts and sign-extends immediates based on instruction type.
* **Logic:** Unscrambles the instruction bits.
* **I-Type:** `{{20{inst[31]}}, inst[31:20]}`
* **S-Type:** `{{20{inst[31]}}, inst[31:25], inst[11:7]}`
* **B-Type:** `{{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0}`
* **U-Type:** `{inst[31:12], 12'b0}`
* **J-Type:** `{{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0}`



#### `control_unit.sv`

* **Function:** Main decoder.
* **Input:** `Opcode` (7 bits).
* **Outputs:**
* `Branch`, `Jump`: Flow control.
* `MemRead`, `MemWrite`: Memory access.
* `RegWrite`: Register file write enable.
* `MemToReg`: Writeback source selection.
* `ALUOp` (2-bit): Encoded signal for ALU Controller.
* `ALUSrc`: Operand B selection (Register vs Immediate).



#### `hazard_detection_unit.sv`

* **Function:** Detects Load-Use hazards.
* **Logic:**
* If `ID/EX.MemRead` is High AND (`ID/EX.rd` == `IF/ID.rs1` OR `ID/EX.rd` == `IF/ID.rs2`):
* Assert `stall` (Freeze PC and IF/ID latch).
* Assert `control_mux_flush` (Inject NOP into ID/EX latch).





---

### 3.3. Stage 3: Execution (EX)

#### `alu_control.sv`

* **Function:** Generates the specific 4-bit ALU operation code.
* **Inputs:** `ALUOp` (from Control Unit), `Funct3`, `Funct7` (from Instruction).
* **Mapping:**
* Translates RISC-V specific funct codes (e.g., `SUB` vs `ADD` differentiation via `Funct7[5]`).



#### `alu.sv` (Arithmetic Logic Unit)

* **Function:** Performs 32-bit arithmetic and logic.
* **Operations:** `ADD`, `SUB`, `SLL`, `SLT`, `SLTU`, `XOR`, `SRL`, `SRA`, `OR`, `AND`.
* **Output:** `ALU_Result`, `Zero_Flag`.

#### `branch_comparator.sv`

* **Function:** Resolves Branch conditions (moved to EX stage for timing stability).
* **Inputs:** `Operand_A`, `Operand_B`, `Funct3`.
* **Logic:** Supports `BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU`.
* **Output:** `branch_taken`. If High, triggers a **Flush** of IF/ID and ID/EX pipelines.

#### `forwarding_unit.sv`

* **Function:** Solves Data Hazards (Read-After-Write).
* **Logic:**
* Compares `ID/EX.rs1` and `ID/EX.rs2` against `EX/MEM.rd` and `MEM/WB.rd`.
* **Priority:** EX/MEM (Most recent) > MEM/WB.
* **Output:** Controls `ForwardA` and `ForwardB` multiplexers to bypass Register File outputs and feed ALU directly.



---

### 3.4. Stage 4: Memory (MEM)

#### `data_memory_interface.sv`

* **Function:** Handles byte-addressing logic for the Data RAM.
* **Inputs:** `ALU_Result` (Address), `Write_Data`, `Funct3` (Width/Sign), `MemRead`, `MemWrite`.
* **Logic:**
* **Store:** Masks data for `SB` (Byte), `SH` (Half), `SW` (Word).
* **Load:** Reads word and applies sign/zero extension for `LB`, `LBU`, `LH`, `LHU`.



---

### 3.5. Stage 5: Writeback (WB)

#### `writeback_mux.sv`

* **Function:** Final data selection.
* **Inputs:** `ALU_Result`, `Read_Data` (Memory), `PC+4` (for JAL/JALR linking).
* **Output:** `Result_to_RegFile`.

---

## 4. Pipeline Register Definitions

State registers separate the logic clouds. All trigger on `posedge clk`.

| Register | Key Signals Passed |
| --- | --- |
| **IF/ID** | `PC`, `Instruction` |
| **ID/EX** | `PC`, `ReadData1`, `ReadData2`, `Immediate`, `rs1`, `rs2`, `rd`, `Funct3/7`, `ControlSignals` |
| **EX/MEM** | `ALU_Result`, `WriteData` (Register B), `rd`, `ControlSignals` (MemWrite, RegWrite, etc.) |
| **MEM/WB** | `ReadData` (from Mem), `ALU_Result`, `rd`, `ControlSignals` (RegWrite, MemToReg) |

---

## 5. Global Signals & Interconnect

This module (`riscv_core`) exposes the following interface for top-level integration:

### 5.1. Inputs

* `clk`: System Clock.
* `rst_n`: Active Low Asynchronous Reset.
* `instr_mem_data` [31:0]: Data read from Instruction Memory.
* `data_mem_read_data` [31:0]: Data read from Data Memory.

### 5.2. Outputs

* `instr_mem_addr` [31:0]: Address pointer for Instruction Memory.
* `data_mem_addr` [31:0]: Address pointer for Data Memory.
* `data_mem_write_data` [31:0]: Data to be written to Data Memory.
* `data_mem_we`: Write Enable for Data Memory.
* `data_mem_re`: Read Enable for Data Memory.
* `data_mem_width` [2:0]: Encodes access size (Byte/Half/Word) based on `Funct3`.

---

## 6. Implementation Notes for Developer

1. **Clock Gating:** Do not use clock gating for pipeline stalls. Use `Enable` signals on the pipeline registers (Flip-Flops).
2. **Reset Logic:** Ensure the `Program Counter` and `Control Signals` in the pipeline registers are synchronously cleared upon Reset to flush unknown states.
3. **Critical Path:** The path through the `Register File Read` -> `Forwarding Mux` -> `ALU` -> `Data Memory Address Setup` is the most time-critical. Optimization here will dictate .
4. **Branch Penalty:** Since branch resolution is in the **EX** stage, a taken branch results in a **2-cycle penalty**. The `branch_comparator` must assert a `flush` signal to both `IF/ID` and `ID/EX` registers.
5. **Remember one-off error in LUI assembly**
