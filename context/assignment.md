# Final Project: RISC-V Pipelined Processor

## 1. Project Overview
The objective of this project is to implement a 5-stage pipelined processor based on the **RISC-V** architecture. In addition to the hardware core, a **Debug Unit** must be developed to allow communication between the processor and a PC via the **UART** protocol, along with a user interface (CLI, GUI, or TUI) to interact with the system.

## 2. Processor Architecture (Pipeline)

### 2.1. Pipeline Stages
The implementation must follow the classic five-stage model:
1.  **IF (Instruction Fetch):** Retrieve the instruction from program memory.
2.  **ID (Instruction Decode):** Decode the instruction and read from the register file.
3.  **EX (Execute):** Perform the arithmetic/logic operation or calculate addresses.
4.  **MEM (Memory Access):** Read or write data from/to the data memory.
5.  **WB (Write Back):** Write results back into the register file.

### 2.2. Hazard Management
The design must identify and handle the three types of pipeline hazards:
*   **Structural Hazards:** When two instructions attempt to use the same resource in the same cycle.
*   **Data Hazards:** When an instruction depends on the result of a previous instruction that has not yet completed its write-back.
*   **Control Hazards:** When the processor must make a branch decision before the condition is evaluated.

## 3. Instruction Set Architecture (ISA)
The processor must implement the following instructions:

*   **R-Type (Register-to-Register):** `add`, `sub`, `sll`, `srl`, `sra`, `and`, `or`, `xor`, `slt`, `sltu`.
*   **I-Type (Immediate/Load):** 
    *   *Loads:* `lb`, `lh`, `lw`, `lbu`, `lhu`.
    *   *Arithmetic:* `addi`, `andi`, `ori`, `xori`, `slti`, `sltiu`, `slli`, `srli`, `srai`.
    *   *Jump:* `jalr`.
*   **S-Type (Store):** `sb`, `sh`, `sw`.
*   **B-Type (Branch):** `beq`, `bne`.
*   **U-Type (Upper Immediate):** `lui`.
*   **J-Type (Unconditional Jump):** `jal`.
*   **System:** A mandatory `HALT` or `STOP` instruction to terminate program execution.

## 4. Technical Requirements

### 4.1. Dynamic Programming (UART)
*   The processor must be programmable and re-programmable via UART commands.
*   **Important:** Program loading must occur dynamically without the need to re-synthesize the hardware in Vivado.
*   The system must include a mechanism (assembler/translator) to convert assembly code into machine code for transmission.

### 4.2. Debug Unit
The Debug Unit must be able to send the following information to the PC:
*   Content of the **32 general-purpose registers**.
*   Content of the **intermediate pipeline latches**.
*   Content of the **used data memory**.

### 4.3. Clocking and Integration
*   **Clock Gating is forbidden:** Do not intervene in the clock signal using combinational logic. Use **Clock Wizard** IP Cores.
*   Analyze the **critical path** of the system.
*   Check for **Clock Skew** and its consequences.
*   Optimize the operating frequency using Vivado metrics.

## 5. Operation Modes
The system must support two execution modes controlled via the interface:
1.  **Continuous Mode:** The FPGA receives a start command, executes the program until the `HALT` instruction is reached, and then displays the final state.
2.  **Step-by-Step Mode:** Each UART command executes a single clock cycle. The state of registers, latches, and memory must be updated on the display after every step.

*Note: The pipeline must be completely flushed upon finishing execution in both modes.*

## 6. Evaluation Questions
The final documentation must address the following points:
1.  Is it necessary to clear the data memory when loading a new program? What about the registers?
2.  Do the pipeline and program memory need to be cleared/flushed during re-programming?
3.  What happens if there is no `HALT` instruction in the program memory?
4.  What is the critical path of your design and how does it affect the maximum frequency?

## 7. Implementation Tips
*   **Design First:** Sketch and schematize modules and their interactions before writing code.
*   **Use Vivado IP Cores:** Leverage tools like IP Catalog for memories and the Clocking Wizard.
*   **Be Creative:** The quality and originality of the User Interface (GUI/TUI/CLI) and the way data is presented will be evaluated.
