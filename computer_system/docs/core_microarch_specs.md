# Microarchitecture Specification: RV32I Subset Pipelined Core

**Version:** 2.0 (Refactored)
**Module:** `riscv_core`
**Status:** Architecture Definition
**Target:** FPGA / RTL Simulation

---

## 1. Executive Summary

This document specifies the architectural implementation of the **RISC-V 32-bit (RV32I)** pipelined processor core.

---

## 2. Pipeline Architecture Overview

The processor implements a **Harvard Architecture** with five distinct stages.

| Stage | Description |
| --- | --- |
| **1. Fetch (IF)** | Generates PC, retrieves instructions, and handles PC updates from flow control. |
| **2. Decode (ID)** | Decodes opcodes, reads Register File, **resolves Branches/Jumps**, performs **Forwarding**, and detects Hazards. |
| **3. Execute (EX)** | Performs ALU operations and calculates Link Addresses (PC+4). |
| **4. Memory (MEM)** | Interfaces with Data Memory using masking for Byte/Halfword access. |
| **5. Writeback (WB)** | Commits the final result (Memory Read or Execution Result) to the Register File. |

---

## 3. Core Datapath & Control Module Specifications

### 3.1. Stage 1: Instruction Fetch (IF)

#### `program_counter_reg`

* **Function:** State register holding the current instruction address.
* **Inputs:** `clk`, `rst_n` (Async), `write_en` (Stall), `soft_reset`, `pc_i`.
* **Logic:** Updates on positive clock edge. Holds value if `freeze` is active.

#### `fixed_pc_adder_inst_if`

* **Function:** Calculates the sequential next instruction address (`PC + 4`).
* **Usage:** Used as the default next-PC value for the Mux.

#### `pc_src_selector`

* **Function:** 2-to-1 Mux determining the Next PC.
* **Control:** `flow_change` (From **ID Stage** `flow_controller`).
* **Inputs:**
* `0`: `pc_plus_4` (Sequential).
* `1`: `final_target_addr` (Branch/Jump Target from **ID**).



---

### 3.2. Stage 2: Instruction Decode (ID)

*Note: This stage now contains the bulk of the processor's complexity to enable single-cycle branch penalties.*

#### `instruction_decoder`

* **Function:** Slices the 32-bit instruction into `opcode`, `rd`, `funct3`, `rs1`, `rs2`, and `funct7`.
* **LUI Handling:** Forces `rs1` to `0` when Opcode is `LUI`, allowing the ALU to treat `LUI` as `0 + Immediate`.

#### `control_unit`

* **Function:** Decodes Opcode into control signals (`is_branch`, `mem_write`, `alu_intent`, etc.).
* **Input:** `opcode`, `force_nop` (from Hazard Unit).

#### `register_file`

* **Function:** 32x32-bit storage with two asynchronous read ports (`rs1`, `rs2`) and one synchronous write port.

#### `immediate_generator`

* **Function:** Generates sign-extended 32-bit immediates (`I`, `S`, `B`, `U`, `J` types).

#### `forwarding_muxes` (`rs1_data_selector`, `rs2_data_selector`)

* **Function:** 4-to-1 Muxes resolving operands for the ID stage.
* **Control:** `forward_rs1_optn`, `forward_rs2_optn` (from `forwarding_unit`).
* **Inputs:**
* `00`: Register File Output.
* `01`: EX Stage Result (`rd_data_ex`).
* `10`: MEM Stage Result (`rd_data_mem`).
* `11`: WB Stage Result (`rd_data_wb`).



#### `comparator` (Adder)

* **Function:** Performs `RS1 - RS2` to generate the `zero` flag for branch evaluation.
* **Inputs:** Forwarded `rs1_data`, `rs2_data`.

#### `flow_controller`

* **Function:** Evaluates Branch/Jump conditions.
* **Inputs:** `is_branch`, `is_jal`, `is_jalr`, `zero` (from Comparator), `funct3`.
* **Outputs:** `flow_change_o` (Signals IF to take the target; flushes IF/ID).

#### `target_calculation` (`target_base_selector` + `final_target_adder`)

* **Function:** Computes the jump target address.
* **Logic:**
* **JAL/Branch:** `PC + Immediate`.
* **JALR:** `RS1 + Immediate`.


* **Mux:** Selects between `PC` and `RS1` based on `is_jalr`.

#### `hazard_protection_unit`

* **Function:** Detects Load-Use Hazards.
* **Logic:** If `(mem_read_ex == 1)` AND `(rd_ex == rs1_id || rd_ex == rs2_id)`.
* **Action:** Asserts `freeze` (Stalls PC and IF/ID) and `force_nop` (Injects NOP into ID/EX).

---

### 3.3. Stage 3: Execution (EX)

#### `alu_src_selector`

* **Function:** Selects ALU Operand 2.
* **Inputs:** `0`=RS2 Data, `1`=Immediate.

#### `alu` & `alu_controller`

* **Function:** Performs Arithmetic, Logic, and Shift operations.
* **Inputs:** `rs1_data`, `alu_op2`, `alu_operation` (decoded from `funct3/7`).

#### `fixed_pc_adder_inst_ex`

* **Function:** Recalculates `PC + 4` in the EX stage.
* **Rationale:** Used for linking (saving return address) in `JAL`/`JALR` instructions.

#### `rd_data_ex_selector`

* **Function:** 2-to-1 Mux selecting the data meant for the Destination Register (before Memory access).
* **Inputs:**
* `0`: `alu_result` (Standard arithmetic/address).
* `1`: `pc_plus_4` (Return address for Jumps).


* **Control:** `is_jal | is_jalr`.

---

### 3.4. Stage 4: Memory (MEM)

#### `data_memory_interface`

* **Function:** Handles byte-alignment for sub-word accesses.
* **Store Logic:** Generates `byte_enable_mask` and shifts write data based on address LSBs.
* **Load Logic:** Reads `raw_data` and applies Sign/Zero extension based on `funct3`.

#### `memory_range_tracker`

* **Function:** Tracks `min` and `max` addresses written to during execution for debug/dumping purposes.

---

### 3.5. Stage 5: Writeback (WB)

#### `rd_src_selector`

* **Function:** 2-to-1 Mux selecting final Register Write data.
* **Inputs:**
* `0`: `exec_data_wb` (Result from EX stage: ALU output or PC+4).
* `1`: `read_data_wb` (Data read from Memory).


* **Control:** `rd_src_optn` (0=ALU/Link, 1=Mem).

---

## 4. Pipeline Registers

### 4.1. `if_id_reg` (64 bits)

* **Payload:** `pc`, `instruction`.
* **Control:** Flushes on `flow_change` (Branch Taken). Stalls on Hazard.

### 4.2. `id_ex_reg` (197 bits)

* **Payload:**
* **Control:** `reg_write`, `mem_write`, `mem_read`, `alu_src`, `alu_intent`, `rd_src`, `flow_flags` (Branch/Jal/Halt).
* **Data:** `pc`, `rs1_data`, `rs2_data`, `immediate`.
* **Meta:** `rs1_addr`, `rs2_addr`, `rd_addr`, `funct3`, `funct7`.



### 4.3. `ex_mem_reg` (110 bits)

* **Payload:**
* **Control:** `reg_write`, `mem_write`, `mem_read`, `rd_src_optn`, `is_halt`.
* **Data:** `alu_result` (Address/Result), `rs2_data` (Store Data), `pc`.
* **Meta:** `rd_addr`, `funct3`.



### 4.4. `mem_wb_reg` (105 bits)

* **Payload:**
* **Control:** `reg_write`, `rd_src_optn`, `is_halt`.
* **Data:** `alu_result`, `final_read_data` (from Mem), `pc`.
* **Meta:** `rd_addr`.



---

## 5. Hazard Management (Updated)

### 5.1. Forwarding Unit (ID-Stage)

Because branches are resolved in the **ID Stage**, the processor requires operands to be valid *during* Decode. The Forwarding Unit now controls muxes placed **before** the ID/EX pipeline register.

* **Inputs:** `rs1_id`, `rs2_id` (Current) vs `rd_ex`, `rd_mem`, `rd_wb` (Pipeline).
* **Priority:**
1. **Forward from EX:** The previous instruction computed a result (`rd_data_ex_selector` output).
2. **Forward from MEM:** The 2nd previous instruction computed a result (or loaded data).
3. **Forward from WB:** The 3rd previous instruction is writing back.



### 5.2. Load-Use Hazard

Since forwarding cannot happen if the data is currently being retrieved from RAM (Instruction  is LOAD, Instruction  needs data), a stall is required.

* **Detection:** `mem_read_ex_i && ((rd_ex_i == rs1_id_i) || (rd_ex_i == rs2_id_i))`
* **Resolution:**
1. **Freeze PC:** Prevent fetching new instruction.
2. **Freeze IF/ID:** Hold the dependent instruction in Decode.
3. **Force NOP:** Inject a bubble into `id_ex_reg` to allow the LOAD to complete in the next cycle.



### 5.3. Control Hazards (Branch-in-ID)

By moving logic to ID, the branch penalty is reduced to **1 cycle** (the instruction currently in Fetch).

* **Resolution:** When `flow_controller` asserts `flow_change`:
1. **PC Mux:** Selects the calculated `final_target_addr`.
2. **Flush:** The `if_id_reg` is synchronously cleared (Soft Reset) to discard the instruction fetched during the delay slot.
