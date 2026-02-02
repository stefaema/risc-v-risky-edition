# Microarchitecture Specification: RV32I Subset Pipelined Core

**Version:** 1.3
**Module:** `riscv_core`
**Status:** Architecture Definition
**Target:** FPGA / RTL Simulation

---

## 1. Executive Summary

This document specifies the architectural implementation of the **RISC-V 32-bit (RV32I)** pipelined processor core. This design implements the unprivileged integer instruction set with a classic 5-stage pipeline.

The core features a centralized flow control mechanism in the Execution stage, a decoupled memory interface for sub-word alignment, and a robust hardware hazard handling system including a full Forwarding Unit.

---

## 2. Pipeline Architecture Overview

The processor implements a **Harvard Architecture** with five distinct stages.

| Stage | Description |
| --- | --- |
| **1. Fetch (IF)** | Generates the Program Counter (PC) and retrieves binary instructions. |
| **2. Decode (ID)** | Decodes instructions, reads Register File, and generates immediate values. |
| **3. Execute (EX)** | Performs ALU operations, evaluates Branch/Jump conditions, calculates targets, and handles Data Forwarding. |
| **4. Memory (MEM)** | Interfaces with Data Memory using masking for Byte/Halfword access. |
| **5. Writeback (WB)** | Commits the final result to the Register File. Signals when system Halts |

---

## 3. Core Datapath & Control Module Specifications

### 3.1. Stage 1: Instruction Fetch (IF)

#### `program_counter_reg`

* **Function:** State register holding the current instruction address.
* **Inputs:** `clk`, `reset`, `write_en`, `global_stall`, `new_pc_in`.
* **Outputs:** `pc_out` (32-bit).
* **Logic:** Synchronous update. Holds value if `write_enable` is clear or if `global_stall` is set. Reset sets PC to `0x00000000`.



#### `fixed_pc_adder` 

* **Function:** Instance of adder that calculates the sequential next instruction address.
* **Logic:** `PC + 4`.
* **Inputs:** `pc`.
* **Outputs:** `inc_pc`.
* **Note:** This value is passed down the pipeline to the WB stage for `JAL`/`JALR` linking.



#### `pc_src_selector`

* **Function:** Multiplexer Instance selecting the next PC state.
* **Control Signal:** `pc_src_optn` (from **EX Stage** `flow_controller`).
* **Inputs:**
* `0`: `inc_pc` (from `pc_plus_four_module`).
* `1`: `target_addr` (from `flow_controller`).
* **Output:** selected input.



#### `instruction_memory` 

* **Function:** Memory storing binary code.
* **Inputs:** `pc`, `data`, `write_enable` (For future bootloading).
* **Outputs:** `instruction_word` (32-bit).

---

### 3.2. Stage 2: Instruction Decode (ID)

#### `instruction_decoder`

* **Function:** Breaks down the raw 32-bit instruction into constituent fields for downstream processing.
* **Logic:**
* **Standard Slicing:** Extracts `rd`, `funct3`, `rs2`, and `funct7` directly from their architecturally defined bit positions.
* **U-Type Handling (LUI):** The module includes specific decode logic for the `LUI` opcode (`0110111`).
    * **Mechanism:** When `LUI` is detected, the `rs1` output is forced to `0` (referencing `x0`).
    * **Rationale:** In the U-Type format, bits `[19:15]` are part of the immediate value, not a source register. Failing to mask this field would result in the processor interpreting immediate data as a register index. This could trigger false positives in the **Forwarding Unit** (detecting a dependency on a non-existent register) and cause incorrect ALU behavior.
* **Benefit:** By enforcing `rs1 = 0`, the ALU can treat `LUI` as a standard addition (`x0 + Immediate`) without requiring a dedicated "Pass-Through B" operation or additional control multiplexers.




* **Inputs:** `instruction_word`
* **Outputs:** `opcode`, `rs1`, `rs2`, `rd`, `funct3`, `funct7`


#### `control_unit`

* **Function:** Translates Opcode into internal control bus.
* **Inputs:** `opcode`
* **Outputs:**
    * `is_branch`, `is_jal`, `is_jalr` (Flow Flags).
    * `mem_write`, `mem_read`.
    * `reg_write`.
    * `rd_src_optn` (Control for WB Mux).
    * `alu_intent` (Generic ALU mode).
    * `alu_src_optn` (Control for ALU Mux).
    * `is_halt` (1 = `ECALL` / System Stop).


#### `register_file`

* **Function:** 32x32-bit storage. `x0` hardwired to 0.
* **Inputs:** 
    - `rs1_addr` (Read Addr's)
    - `rs2_addr` 
    - `rs_dbg_addr`
    - `rd_addr` (Write Addr)
    - `reg_write_en` (from WB)
    - `rd_data`.
* **Outputs:** `rs1_data`, `rs2_data`,`rs_dbg_data`.



#### `immediate_generator`

* **Function:** Unscrambles instruction bits into 32-bit signed integers.
* **Logic:**
* **I/S/U-Type:** Standard Sign Extension.
* **B/J-Type:** Shifts immediate left by 1 (appends LSB `0`) to reconstruct the even offset.
* **Inputs:** `instruction_word`
* **Outputs:** `ext_immediate`
* **Note:** Has to avoid appending 0 when instruction is JALR.

---

### 3.3. Stage 3: Execution (EX)

#### `alu_controller`

* **Function:** Decodes specific ALU operation.
* **Inputs:** `alu_intent` (from Control), `funct3`, `funct7[30]` (Instruction).
* **Outputs:** 4-bit `alu_operation` signal.



#### `alu_src_selector`

* **Function:** 2-to-1 Multiplexer instance selecting the second operand for the ALU.
* **Control Signal:** `alu_src_optn`.
* **Inputs:**
* `0`: Register Data.
* `1`: Immediate Value.



#### `alu`

* **Function:** Main arithmetic/logic processing.
* **Inputs:** `alu_op1` , `alu_op2`, `alu_operation`.
* **Outputs:** `alu_result`, `zero_flag`.



#### `imm_pc_adder`

* **Function:** Adder instance that calculates PC-Relative Branch/JAL targets.
* **Logic:** `PC_of_current_instr` + `Immediate`.
* **Inputs:** `pc`, `extended_inmediate`
* **Outputs:** `pc_imm_target`


#### `flow_controller`

* **Function:** Flow Control Unit implementing **Static Not-Taken Prediction**. Handles condition evaluation, target selection, and **Halt Logic**.
* **Inputs:**
* Control: `is_branch`, `is_jal`, `is_jalr`, `is_halt_i` (from ID/EX).
* Data: `funct3`, `zero` (from `alu`).
* Targets: `pc_imm_target` (from `pc_imm_adder`), `alu_target` (from `alu`, for JALR).


* **Outputs:**
* `pc_src_optn` (Signal to IF Stage Mux).
* `final_target_addr` (Address Data).
* `redirect_req` (Signal to Hazard Unit indicating a flow change).
* `halt_detected_o` (Signal to Hazard Unit to inititate System Stop).


* **Logic:**
1. **Condition Evaluation:**
* Checks `funct3` against the `zero` flag.
* Result: `branch_condition_met`.


2. **Flow Change Detection:**
* A deviation from sequential flow is detected if: `is_jal` OR `is_jalr` OR (`is_branch` AND `branch_condition_met`).
* **Signal:** `redirect_req` = `flow_change_detected`. (Indicates the instructions currently in Fetch and Decode are invalid).


3. **Halt Handling:**
* `halt_detected_o` = `is_halt_i`.


4. **PC Source & Target Selection:**
* `pc_src_optn` = `redirect_req` AND (NOT `is_halt_i`). (Only redirect if not halting; Halt freezes PC in place).
* If `is_jalr`: `final_target_addr` = `alu_target` & `0xFFFFFFFE` (Clear LSB).
* Else: `final_target_addr` = `pc_imm_target`.


---

### 3.4. Stage 4: Memory (MEM)

#### `data_memory_interface`

* **Function:** The bridge between the CPU core and the Data RAM. It handles alignment, masking for stores, and extension for loads.

* **Inputs:**
* `funct3` (Instruction bits): Defines access width (Byte/Half/Word) and extension (Signed/Unsigned).
* `alu_result` [1:0]: Used as the address offset to select the correct byte/halfword.
* `rs2_data`: The 32-bit data from `rs2` to be stored.
* `raw_read_data`: The full 32-bit word read coming back from the Data Memory.

* **Outputs:**
* **To Data Memory:** `byte_enable_mask` (4-bit write strobe).
* **To Data Memory:** `ram_write_data` (Data replicated/aligned for the specific byte lanes).
* **To Writeback:** `final_read_data` (The requested byte/halfword, sign-extended or zero-extended to 32 bits).

#### `data_memory`

* **Function:** 32-bit wide Random Access Memory.

* **Inputs:**
* `clk`: System clock.
* `addr`: Word-aligned address pointer (typically `alu_result[31:2]`).
* `write_data`: The aligned data from `data_memory_interface`.
* `byte_enable_mask`: Controls which bytes in the word are written (from `data_memory_interface`).

* **Outputs:**
* **To data_memory_interface:** `raw_read_data` (The full 32-bit word at the address).

#### `memory_range_tracker`

* **Function:** Monitors memory write operations to maintain a record of the "dirty" memory range. This allows external Modules to perform optimized memory dumps by only transmitting used addresses.
* **Inputs:**
    * `clk`: System clock.
    * `reset`: Synchronous reset (resets limits to default).
    * `mem_write_en`: Write strobe from the Control Unit (active when a Store instruction is in MEM).
    * `addr_in_use`: The 32-bit memory address being accessed.
* **Outputs:**
    * `min_addr_o`: 32-bit register holding the lowest address written since reset.
    * `max_addr_o`: 32-bit register holding the highest address written since reset.
* **Logic:**
    * Upon **reset**: `min_addr_o` is initialized to `0xFFFFFFFF` and `max_addr_o` to `0x00000000`.
    * On `mem_write_en`:
        * If `alu_result < min_addr_o`, update `min_addr_o` with `alu_result`.
        * If `alu_result > max_addr_o`, update `max_addr_o` with `alu_result`.



### 3.5. Stage 5: Writeback (WB)

#### `rd_src_selector`

* **Function:** Multiplexer selecting final data to commit to Register File.
* **Control Signal:** `rd_src_optn`.
* **Inputs:**
* `00`: **ALU Result** (Math operations).
* `01`: **PC + 4** (Link address for `JAL`/`JALR`).
* `10`: **Memory Data** (Loads).
* **Outputs:** Selected input signal.

## 3.6. Pipeline Registers (registers)

These modules act as the state barriers between the combinational logic stages. They capture the results of a stage on the rising clock edge and hold them stable for the subsequent stage, defining the "context" of the instruction as it moves through the pipeline.

#### `pipeline_register` (Generic Template)

* **Function:** Parameterizable register with flow control capabilities.
* **Inputs:**
* `clk`: System clock.
* `sync_reset`: Synchronous Clear/Flush signal (High priority). Used for Branch Flushing.
* `write_en`: Write Enable/~Stall signal (Low priority). Used for Load-Use Stalls.
* `global_stall`
* `data_i`: Input payload packet.


* **Outputs:**
* `data_o`: Registered output payload.


* **Logic:**
* If `sync_reset` is High: `data_o`  0.
* Else if `enable` is High: `data_o`  `data_i`.
* Else: Hold current value.

---

### Pipeline Register Specifications

#### `if_id_reg` (Fetch → Decode)

* **Control:** 
    * Stallable (Load-Use): Triggered by **Load-Use Stall**
    * Flushable (Branch Taken): Triggered by **Branch Redirect** and/or **SystemHalt**
* **Payload:**
    * `pc_addr`: The address of the instruction (crucial for calculating PC-relative offsets).
    * `instruction_word`: The raw binary fetched from memory.
    * `pc_plus_four`: The result of the fixed adder. It's needed in WB.

* **Bit Size:**
    * 96 bits.
#### `id_ex_reg` (Decode → Execute)

* **Control:**
    * **Flushable** (Sync Reset): Triggered by **Branch Redirect** or **Load-Use Stall** (Bubble insertion).
    * **Stallable** (Write Enable): Triggered by **System Halt** (to lock the `ECALL` in EX).


* **Payload:**
    * **Control Bus:** `reg_write_en`, `mem_write_en`, `mem_read_en`, `alu_src_optn`, `alu_intent`, `rd_src_optn`, `is_branch`, `is_jal`, `is_jalr`, `is_halt`.
    * **Data:** `pc_addr`, `pc_plus_four`, `rs1_data` (Read Port 1), `rs2_data` (Read Port 2), `extended_imm`.
    * **Metadata:** `rs1_addr`, `rs2_addr` (Forwarding), `rd_addr` (Destination), `funct3`, `funct7` (ALU Control).

* **Bit Size:**
    * 12 control bits + 5 * 32 data bits +  25 metadata bits = 197 bits.
#### `ex_mem_reg` (Execute → Memory)

* **Control:** Always Enabled.
* **Payload:**
    * **Control Bus:** `reg_write_en`, `mem_write_en`, `mem_read_en`, `rd_src_optn`, `is_halt`.
    * **Data:** `alu_result` (Address/Result), `rs2_data` (Store Data), `pc_plus_4` (Link Address).
    * **Metadata:** `rd_addr` (Forwarding), `funct3` (Memory Alignment).
* **Bit Size:**
    * 6 control bits + 48 data bits + 8 metadata bits = 110 bits.

#### `mem_wb_reg` (Memory → Writeback)

* **Control:** Always Enabled.
* **Payload:**
    * **Control Bus:** `reg_write_en`, `rd_src_optn`, `is_halt`.
    * **Data:** `alu_result` (Passthrough), `final_read_data` (Load Data), `pc_plus_4` (Link Address).
    * **Metadata:** `rd_addr` (Writeback Target).
* **Bit Size:**
    * 4 control bits + 48 data bits + 5 metadata bits = 105 bits.


---

## 4. Hazard Management & Pipeline Optimization

This section details the logic required to maintain data integrity and instruction flow when the ideal "happy path" of the pipeline is disrupted. These modules operate in parallel with the main datapath to detect dependencies and correct them via Forwarding, Stalling, or Flushing.

### 4.1. Hazard Theory & Classification

| Hazard Type | Cause | Resolution Mechanism |
| --- | --- | --- |
| **Data Hazard (R-A-W)** | An instruction needs a result that is currently in the **EX** or **MEM** stage (has not reached **WB** yet). | **Forwarding (Bypassing):** Routes the data directly from pipeline registers to the ALU. |
| **Load-Use Hazard** | An instruction needs a result from a `LOAD` instruction that is currently in the **EX** stage. Forwarding is impossible because the data is still in RAM. | **Stalling (Interlock):** Freezes the PC and IF/ID registers for 1 cycle and inserts a bubble (NOP). |
| **Control Hazard** | A Branch or Jump changes the PC, but the pipeline has already fetched the next sequential instructions (Static Not-Taken assumption failed). | **Flushing:** Clears the valid bits of the IF/ID and ID/EX pipeline registers to discard the wrong instructions. |

---

### 4.2. Forwarding Unit

#### `forwarding_unit`

* **Function:** Resolves **Read-After-Write (RAW)** hazards by controlling a bypass network. It detects when an instruction needs a register value that has not yet been committed to the Register File and routes that value directly from the pipeline registers to the ALU.

* **Inputs:**
    * **Current Requirements (ID/EX):**
        * `rs1_id_ex`: Source Register 1 address.
        * `rs2_id_ex`: Source Register 2 address.
    * **Stage 3 Producer (EX/MEM):**
        * `rd_ex_mem`: Destination Register address.
        * `reg_write_ex_mem`: Write Enable signal.
        * `mem_read_ex_mem`: Memory Read signal (Load Indicator).
    * **Stage 4 Producer (MEM/WB):**
        * `rd_mem_wb`: Destination Register address.
        * `reg_write_mem_wb`: Write Enable signal.

* **Outputs:**
    * `forward_a_optn` (2-bit): Controls the 3-to-1 Mux for ALU Operand A.
    * `forward_b_optn` (2-bit): Controls the 3-to-1 Mux for ALU Operand B.

* **Behaviour & Justification:**
    The Forwarding Unit functions as a combinational priority selector that governs the ALU's input multiplexers. It continuously compares the source registers of the executing instruction against the destination registers of the two previous instructions residing in the pipeline.

    First, the unit checks for an **EX Hazard** (High Priority). If the instruction in the EX/MEM stage is writing to a needed register—and is *not* a Load instruction—the unit bypasses the Register File to grab data directly from the ALU output. The `mem_read` check is critical here: if the instruction in EX/MEM is a `LOAD`, the unit refuses to forward (as the register contains an address, not data), forcing the pipeline to wait for the value to arrive from memory via a stall.
    
    $$\text{if } (RegWrite_{EX/MEM} \land (Rd_{EX/MEM} \neq 0) \land (Rd_{EX/MEM} = Rs_{ID/EX}) \land \neg MemRead_{EX/MEM}) \rightarrow 10$$

    If no EX Hazard is detected, the unit checks for a **MEM Hazard** (Low Priority). If the instruction in the MEM/WB stage is writing to a needed register, the unit forwards the data from the Writeback bus. This corrects the "stale read" issue mentioned in the timing note above.
    
    $$\text{else if } (RegWrite_{MEM/WB} \land (Rd_{MEM/WB} \neq 0) \land (Rd_{MEM/WB} = Rs_{ID/EX})) \rightarrow 01$$

    If neither condition is met, the muxes default to `00`, accepting the value originally read from the Register File.

> **Register File Timing Note:** The Register File utilizes **split-cycle timing**: it writes on the **falling edge** of the clock and reads on the **rising edge**. This ensures that instructions in the **ID stage** always receive updated values from instructions in the **WB stage** within the same cycle. Consequently, forwarding is only necessary for instructions already in the **EX stage**, which read their values from the Register File in the previous cycle before the WB commit occurred.

---

#### `hazard_protection_unit`

* **Function:** The central nervous system for pipeline flow. It resolves **Load-Use Hazards**, **Control Hazards** (Branch/Jump), and **System Halts** by manipulating the stall (enable) and flush (reset) signals of the pipeline registers and PC.
* **Location:** Operates in the **ID** stage, receiving signals from **ID** and **EX**.
* **Inputs:**
* `mem_read_id_ex`: Indicates if the instruction currently in **EX** is a Load.
* `rd_id_ex`: The destination register of the instruction currently in **EX**.
* `rs1_if_id`, `rs2_if_id`: The source registers of the instruction currently in **ID**.
* `redirect_req_i`: From Flow Controller. Indicates a Branch/Jump is taken.
* `halt_detected_i`: From Flow Controller. Indicates a valid HALT is processing.


* **Outputs:**
* `pc_write_en`: 0 = Freeze PC.
* `if_id_write_en`: 0 = Freeze IF/ID Register.
* `if_id_flush`: 1 = Clear IF/ID Register (Insert NOP).
* `id_ex_write_en`: 0 = Freeze ID/EX Register.
* `id_ex_flush`: 1 = Clear ID/EX Register (Insert NOP).


* **Logic Table:**

| State | Priority | PC Write | IF/ID Write | IF/ID Flush | ID/EX Write | ID/EX Flush | Reasoning |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **System Halt** | 1 (High) | **0** (Freeze) | **1** | **1** (Kill) | **0** (Freeze) | **0** | Lock `ECALL` in EX (to maintain Halt state). Kill instruction in ID. |
| **Branch Redirect** | 2 | **1** | **1** | **1** (Kill) | **1** | **1** (Kill) | Kill both the instruction in Fetch (IF/ID) and Decode (ID/EX). |
| **Load-Use Stall** | 3 | **0** (Freeze) | **0** (Freeze) | **0** | **1** | **1** (Bubble) | Pause Fetch/Decode. Insert NOP into EX to allow Memory stage to finish. |
| **Normal Operation** | 4 (Low) | **1** | **1** | **0** | **1** | **0** | Standard execution flow. |

---
### 5. Miscelaneous
- **Notes:**
    1. Because FPGA-based B-RAM IP modules tend to be Word-Addressable and RISC-V uses a strict Byte-Addressable system, at IF we simply ignore PC[0] and PC[1].

