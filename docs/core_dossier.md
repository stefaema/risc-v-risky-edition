# Hardware Architecture Dossier: RV32I Pipelined Core

**Version:** 1.2
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
| **5. Writeback (WB)** | Commits the final result to the Register File. |

---

## 3. Core Datapath & Control Module Specifications

### 3.1. Stage 1: Instruction Fetch (IF)

#### `program_counter_reg`

* **Function:** State register holding the current instruction address.
* **Inputs:** `clk`, `reset`, `stall` (Hazard), `new_pc_in`.
* **Outputs:** `pc_out` (32-bit).
* **Logic:** Synchronous update. Holds value if `stall` is active. Reset sets PC to `0x00000000`.



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

* **Function:** Breaks down the raw 32-bit instruction into constituent fields.
* **Logic:** Combinational slicing.
* `opcode` [6:0]
* `rd` [11:7]
* `funct3`
* `rs1`
* `rs2`
* `funct7`
* **Inputs:** `instruction_word`
* **Outputs:** `opcode`, `rs1`, `rs2`, `rd`



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



#### `register_file`

* **Function:** 32x32-bit storage. `x0` hardwired to 0.
* **Inputs:** `rs1_addr`, `rs2_addr` (Read Addr), `rd_addr` (Write Addr),  `reg_write_en` (from WB),
`rd_data`.
* **Outputs:** `rs1_data`, `rs2_data`.



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

* **Function:** Flow Control Unit implementing **Static Not-Taken Prediction**. Handles condition evaluation, pipeline flushing and target selection.


* **Inputs:**
* Control: `is_branch`, `is_jal`, `is_jalr`.
* Data: `funct3`, `zero` (from `alu`).
* Targets: `pc_imm_target` (from `pc_imm_adder`), `alu_target` (from `alu`, for JALR).


* **Outputs:**
* `pc_src_optn` (Signal to IF Stage Mux).
* `final_target_addr` (Address Data).
* `flush_req` (Signal to Hazard Unit).


* **Logic:**
1. **Condition Evaluation:**
* Checks `funct3` against the `zero` flag (e.g., `BEQ` takes if `zero == 1`, `BNE` takes if `zero == 0`).
* result: `branch_condition_met`.


2. **Prediction Verification (Static Not-Taken):**
* The fetch unit effectively predicts "Not Taken" by default (fetching PC+4).
* A redirection is required if: `is_jal` OR `is_jalr` OR (`is_branch` AND `branch_condition_met`).
* **Signal:** `do_redirect`.


3. **Output Generation:**
* `pc_src_optn` = `do_redirect`.
* `flush_req` = `do_redirect`. (High triggers synchronous clear of **IF/ID** and **ID/EX** pipeline registers, imposing a 2-cycle penalty).


4. **Target Selection:**
* If `is_jalr`: `final_target_addr` = `alu_result` & `0xFFFFFFFE` (Clear LSB).
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


### 3.5. Stage 5: Writeback (WB)

#### `rd_src_selector`

* **Function:** Multiplexer selecting final data to commit to Register File.
* **Control Signal:** `rd_src_optn`.
* **Inputs:**
* `00`: **ALU Result** (Math operations).
* `01`: **PC + 4** (Link address for `JAL`/`JALR`).
* `10`: **Memory Data** (Loads).
* **Outputs:** Selected input signal.

---

## 4. Hazard Management & Pipeline Optimization

This section details the logic required to maintain data integrity and instruction flow when the ideal "happy path" of the pipeline is disrupted. These modules operate in parallel with the main datapath to detect dependencies and correct them via Forwarding, Stalling, or Flushing.

### 4.1. Hazard Theory & Classification

| Hazard Type | Cause | Resolution Mechanism |
| --- | --- | --- |
| **Data Hazard (R-A-W)** | An instruction needs a result that is currently in the **EX** or **MEM** stage (has not reached **WB** yet). | **Forwarding (Bypassing):** Routes the data directly from pipeline latches to the ALU. |
| **Load-Use Hazard** | An instruction needs a result from a `LOAD` instruction that is currently in the **EX** stage. Forwarding is impossible because the data is still in RAM. | **Stalling (Interlock):** Freezes the PC and IF/ID registers for 1 cycle and inserts a bubble (NOP). |
| **Control Hazard** | A Branch or Jump changes the PC, but the pipeline has already fetched the next sequential instructions (Static Not-Taken assumption failed). | **Flushing:** Clears the valid bits of the IF/ID and ID/EX pipeline registers to discard the wrong instructions. |

---

### 4.2. Forwarding Unit

#### `forwarding_unit`

* **Function:** Resolves **Read-After-Write (RAW)** hazards by controlling a bypass network. It detects when an instruction needs a register value that has not yet been committed to the Register File and routes that value directly from the pipeline latches to the ALU.

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

    First, the unit checks for an **EX Hazard** (High Priority). If the instruction in the EX/MEM stage is writing to a needed register—and is *not* a Load instruction—the unit bypasses the Register File to grab data directly from the ALU output. The `mem_read` check is critical here: if the instruction in EX/MEM is a `LOAD`, the unit refuses to forward (as the latch contains an address, not data), forcing the pipeline to wait for the value to arrive from memory via a stall.
    
    $$\text{if } (RegWrite_{EX/MEM} \land (Rd_{EX/MEM} \neq 0) \land (Rd_{EX/MEM} = Rs_{ID/EX}) \land \neg MemRead_{EX/MEM}) \rightarrow 10$$

    If no EX Hazard is detected, the unit checks for a **MEM Hazard** (Low Priority). If the instruction in the MEM/WB stage is writing to a needed register, the unit forwards the data from the Writeback bus. This corrects the "stale read" issue mentioned in the timing note above.
    
    $$\text{else if } (RegWrite_{MEM/WB} \land (Rd_{MEM/WB} \neq 0) \land (Rd_{MEM/WB} = Rs_{ID/EX})) \rightarrow 01$$

    If neither condition is met, the muxes default to `00`, accepting the value originally read from the Register File.

> **Register File Timing Note:** The Register File utilizes **split-cycle timing**: it writes on the **falling edge** of the clock and reads on the **rising edge**. This ensures that instructions in the **ID stage** always receive updated values from instructions in the **WB stage** within the same cycle. Consequently, forwarding is only necessary for instructions already in the **EX stage**, which read their values from the Register File in the previous cycle before the WB commit occurred.

---

### 4.3. Hazard Detection Unit (Stall)

#### `hazard_detection_unit`

* **Function:** Detects **Load-Use** situations where forwarding is insufficient. Since memory reads happen in the 4th stage, the data is not available for an instruction immediately following a Load. The pipeline must "stall" (pause) to allow the Load to complete.
* **Location:** operates in the **ID** stage.
* **Inputs:**
* `mem_read_id_ex`: Indicates if the instruction currently in **EX** is a Load.
* `rd_id_ex`: The destination register of the instruction currently in **EX** (the Load).
* `rs1_if_id`, `rs2_if_id`: The source registers of the instruction currently in **ID**.


* **Outputs:**
* `stall_req`: Master signal used to freeze state.


* **Logic:**
* **Condition:** `if (mem_read_id_ex == 1) AND ((rd_id_ex == rs1_if_id) OR (rd_id_ex == rs2_if_id))`
* **Action (When Condition met):**
1. **Freeze PC:** Disable write enable on `program_counter_reg`.
2. **Freeze IF/ID:** Disable write enable on the IF/ID pipeline register.
3. **Bubble ID/EX:** Force control signals in the ID/EX register to 0 (insert a NOP) for the next cycle.

---

### 4.4. Control Hazard Handling (Flush)

*Note: While the detection logic resides in the `flow_controller` (See Section 3.3), the flushing mechanism is a distinct hazard operation.*

#### `pipeline_flush_mechanism`

* **Function:** Discards instructions that were fetched speculatively but are no longer valid due to a Control Transfer (Branch/Jump).
* **Trigger:** `flush_req` (generated by **EX Stage** `flow_controller` when `do_redirect` is High).
* **Logic:**
* **Synchronous Reset:** When `flush_req` is High, the pipeline registers **IF/ID** and **ID/EX** are synchronously reset to zero/NOP.
* **Penalty:** 2 Cycles (The instruction in Fetch and the instruction in Decode are both discarded).


* **Visual Flow:**
1. **Cycle N:** Branch is in EX. `flow_controller` determines "Taken". Assert `flush_req`.
2. **Cycle N+1:**
* PC is updated to `target_addr`.
* IF/ID Latch becomes NOP (Instruction fetched in Cycle N is killed).
* ID/EX Latch becomes NOP (Instruction decoded in Cycle N is killed).


3. **Cycle N+2:** Correct instruction arrives at Fetch.
