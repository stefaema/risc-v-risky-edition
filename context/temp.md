# Technical Dossier: RISC-V Pipeline Project Analysis & Integration Strategy

**Date:** January 29, 2026
**To:** Lead Engineering Team
**From:** Chief Computer Architect
**Subject:** Analysis of Legacy Codebases (RISC-V vs. MIPS) and Roadmap for RV32I Debug Implementation

## 1. Executive Summary

We have received a project specification for a **RISC-V 32-bit (RV32I) 5-stage Pipelined Processor** featuring Dynamic Programming (UART), a Debug Unit, and Hazard Management.

We currently possess two disparate codebases:
1.  **Codebase A (RISC-V Core):** A 64-bit RISC-V implementation with Hazard detection and Forwarding, but lacking external I/O, UART, or debug capabilities.
2.  **Codebase B (MIPS System):** A MIPS implementation featuring a robust "System Unit of Debug" (SUOD), UART bootloader, and debug instrumentation, but utilizing the wrong ISA.

**Strategic Decision:** The most efficient path to success is to **downscale Codebase A to 32-bit** to match the ISA requirements, and **transplant the SUOD and Memory Architecture from Codebase B** into Codebase A.

---

## 2. Analysis of Codebase A: The RISC-V Core

**File Set:** `2_1mux.sv` through `testbench.sv` (first concatenation).

### 2.1. Architectural Assessment
*   **ISA Compliance:** The current design is **RV64I** (64-bit), indicated by `input [63:0] A,B` in the ALU and Muxes. The project requirement is **RV32I**.
    *   *Impact:* Critical. The datapath width must be reduced from 64 to 32 bits to match the specification and the provided instruction encoding tables.
*   **Pipeline Structure:** Standard 5-stage (IF, ID, EX, MEM, WB).
    *   *Modules:* `IFID`, `IDEX`, `EXMEM`, `MEMWB` are present and correctly structured.
*   **Hazard Management:**
    *   **Forwarding:** Implemented in `ForwardingUnit.sv`. It correctly detects `RS1/RS2` vs `Rd` conflicts in MEM and WB stages.
    *   **Stalling:** Implemented in `hazard_detection_unit.sv`. It correctly handles Load-Use hazards by checking `MemRead`.
    *   **Control Hazards:** `branching_unit.sv` determines branching in the EX stage. `pipeline_flush.sv` exists to flush IF/ID and ID/EX, which is correct for EX-stage branch resolution.

### 2.2. Deficiencies (Gap Analysis)
1.  **No UART/Bootloader:** `instruction_memory.sv` is a Read-Only Memory (ROM) with hardcoded hex values. It cannot be written to dynamically.
2.  **No Debug Unit:** There is no mechanism to pause the clock or read internal registers externally.
3.  **Memory Alignment:** The `data_memory.sv` handles 64-bit words. RV32I requires 32-bit word alignment with byte (`lb`) and half-word (`lh`) support. The current `data_extractor` handles immediates, but load/store masking logic is simplistic.
4.  **Bit Width Mismatch:** The entire datapath (`adder`, `alu_64bit`, `reg_file`) is 64-bit.

---

## 3. Analysis of Codebase B: The MIPS System

**File Set:** `alu_control.v` through `write_back.v` (second concatenation).

### 3.1. Architectural Assessment
*   **ISA:** MIPS32. This logic (`instruction_decode`, `mod_control`) is unusable for the RISC-V project.
*   **System Unit of Debug (SUOD):** This is the high-value asset. `suod.v` implements a finite state machine (FSM) handling:
    *   UART RX/TX parsing (`uart` module inferred).
    *   **Bootloader Mode:** Writes received bytes into instruction memory.
    *   **Debug Mode:** Pauses execution (`i_stall`), reads specific registers/memory addresses, and steps the processor.
*   **Memory Architecture:**
    *   `memoria_de_instruccion.v`: Implements a write port for the bootloader and a read port for the fetch stage.
    *   `memoria_por_byte.v`: Supports byte-granular writes (essential for `sb` instructions).

### 3.2. Assets for Transplantation
The following modules should be extracted and adapted:
1.  **`suod.v`**: The "System Unit of Debug".
2.  **`uart.v` (and `separador_bytes.v`)**: Communication layer.
3.  **`memoria_de_instruccion.v`**: Needs to replace the static RISC-V memory.
4.  **`mask_a_byte.v` & `signador.v`**: Excellent helper modules for handling `lb`, `lhu`, `sb`, `sh` logic which Codebase A lacks.

---

## 4. Integration Roadmap

To fulfill the "RISC-V Pipelined Processor" requirements, follow this step-by-step engineering plan.

### Step 1: Datapath Reduction (RV64 to RV32)
Modify Codebase A to operate on 32-bit widths.
*   **`reg_file.sv`**: Change `reg [63:0] registers [31:0]` to `reg [31:0] registers [31:0]`.
*   **`alu_64bit.sv`**: Rename to `alu_32bit.sv` and change inputs/outputs to `[31:0]`.
*   **`imm_data_extractor.sv`**: Update immediate generation to strictly follow RV32I specifications (Codebase A handles 64-bit sign extension which produces `64'hFFFF...`, we need `32'hFFFF...`).

### Step 2: Implement the "Wrapper" (`top.v`)
Create a new `top.v` similar to Codebase B's `top.v`. This module will instantiate:
1.  **Clock Wizard** (as per requirements).
2.  **SUOD** (Adapted from Codebase B).
3.  **RISC-V Processor** (Codebase A).

### Step 3: Hardware Modifications for Debugging
The RISC-V core (Codebase A) must be "opened up" to allow the SUOD to inspect it.

**A. Register File Modification**
*   **Current (A):** 2 Read Ports, 1 Write Port.
*   **Required:** Add a **3rd Read Port** dedicated to Debugging.
    *   *Input:* `[4:0] debug_addr`
    *   *Output:* `[31:0] debug_data`
    *   *Logic:* Combinational read, exactly like Codebase B's `register_file.v` (`i_read_direc_debug`, `o_data_debug`).

**B. Pipeline Registers Inspection**
*   The SUOD needs to see the PC and pipeline states.
*   Route the `PC_out` wire and potentially valid bits from pipeline registers (`IFID`, `IDEX`, etc.) to the `RISC_V_Processor` output ports, so `top.v` can feed them to `suod.v`.

**C. Processor Stalling**
*   Codebase A has `hazard_detection_unit` generating a `stall` signal.
*   You must OR this internal stall with an **external stall** coming from the SUOD.
    *   `Final_Stall = Hazard_Stall | Debug_Stall;`
*   This allows the Debug Unit to freeze the processor for step-by-step execution.

### Step 4: Memory System Overhaul
Replace `instruction_memory.sv` (Codebase A) with the logic from `memoria_de_instruccion.v` (Codebase B).
*   **Write Port:** Connects to SUOD (for bootloading).
*   **Read Port:** Connects to IF stage (PC).
*   **Logic:** Ensure it effectively treats the storage as RAM, not ROM.

### Step 5: Load/Store Logic (LSU) Implementation
Codebase A is weak on sub-word access. Codebase B is strong.
*   **Integration:** In the MEM stage of the RISC-V processor, instantiate logic similar to `mask_a_byte.v` (Codebase B).
*   **Function:**
    *   For `sb` (Store Byte): Use the mask to enable write on specific byte lanes of the BRAM.
    *   For `lb` (Load Byte): Read 32 bits, shift based on address LSBs, and sign-extend (use `signador.v` from Codebase B).

### Step 6: Control Unit Update
Update `control_unit.sv` (Codebase A) to support the specific HALT instruction required.
*   **HALT:** Since RISC-V doesn't have a standard dedicated HALT opcode (usually `ecall` or `ebreak` is used), define a custom signal or use `ecall`.
*   This signal must go to `top.v` to tell the SUOD to switch from "RUN" state to "IDLE" state.

---

## 5. Dossier: Answers to Evaluation Questions (Drafting)

Based on the merged architecture, here are the technical answers for the project documentation:

1.  **Clearing Data Memory/Registers on Load:**
    *   *Registers:* Yes. `suod` should trigger a global `reset` signal before loading a new program. The `reg_file.sv` must handle `reset` by zeroing all registers (except `x0`).
    *   *Data Memory:* It is good practice but not strictly required by hardware *if* the software assumes garbage data. However, for a clean "Restart" command, the SUOD FSM should ideally iterate and zero memory or reliance on a hardware reset signal to the BRAMs is needed.

2.  **Pipeline Flushing:**
    *   Yes. When the `suod` switches from Bootloader to Run mode, or re-starts a program, the pipeline registers (`IDEX`, `EXMEM`, etc.) must be flushed (reset to 0/NOPs) to prevent the execution of residual instructions from a previous run or random noise.

3.  **Missing HALT:**
    *   If the program lacks a `HALT`, the PC will increment indefinitely, fetching empty memory (zeros).
    *   In RISC-V, `0x00000000` is often an illegal instruction or a specific behavior depending on the compressed extension. In this design, `0x00` might be decoded as a valid instruction or create unpredictable behavior. The processor will not stop until manual intervention via the Debug Unit (Stop/Step command).

4.  **Critical Path:**
    *   **Analysis:** The critical path usually lies in the **EX** stage: `Forwarding Mux -> ALU -> Branch Adder -> PC Mux`.
    *   **Impact:** This path determines the minimum clock period ($T_{min}$). The maximum frequency is $f_{max} = 1/T_{min}$. If the ALU is complex (64-bit carry propagation is slower than 32-bit) or the Forwarding Mux is large, frequency drops. Downscaling to 32-bit (Step 1) will improve timing.

## 6. Conclusion

Codebase A provides the correct **Instruction execution logic** (RISC-V), while Codebase B provides the correct **System infrastructure** (UART/Debug). By injecting the SUOD and memory controllers from B into the modified 32-bit core of A, the project requirements will be met with minimal ground-up coding.
