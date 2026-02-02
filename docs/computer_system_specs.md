# FPGA RISC-V Computer System: Core + UART-based C2 Unit

## 1. Document Scope & Overview

### 1.1. Purpose
This document specifies the hardware implementation of the **Command & Control (C2) Interface** and the surrounding infrastructure for the RV32I pipelined processor. It defines the communication protocol, memory loading mechanisms, and debug units required to program, execute, and monitor the processor on an FPGA target without requiring resynthesis.

### 1.2. System Architecture
The system follows a modular design where the RISC-V processor core is encapsulated within a management layer. 
*   **Processor Layer:** The RV32I 5-stage pipeline core.
*   **Memory Layer:** Dual-port or multiplexed RAM blocks for Instructions (IMEM) and Data (DMEM).
*   **C2 Interface Layer:** A collection of modules (Arbiter, Loader, Debugger, Dumper) that interface with a UART Transceiver to provide external control over the system state.

---

## 2. Core Microarchitecture Reference

### 2.1. Note on Processor Core
The internal logic, datapath, and control signals of the RISC-V processor are not covered in this document. For detailed specifications regarding the 5-stage pipeline, hazard handling, and instruction set support, please refer to the **Core Design Document** (`docs/core_microarch_specs.md`). This specification assumes the core provides external access to its stall signals, register file, and pipeline registers for debugging purposes.

---

# 3. FPGA Top-Level Integration (`riscv_fpga_top`)

## 3.1. Module Hierarchy
The `riscv_fpga_top` module serves as the physical container for the entire design. It instantiates the Clock Management features, the Processor Core, the Memory Subsystem, and the C2 Interface Wrapper. It handles the signal routing and arbitration between these sub-systems.

**Sub-Module Instances:**
1.  **`clk_wiz_0`:** Xilinx MMCM/PLL IP for clock synthesis.
2.  **`c2_interface_top`:** The Command & Control Wrapper (Arbiter, UART, Loader, Debugger, Dumper).
3.  **`riscv_core`:** The RV32I Processor Pipeline.
4.  **`bram_imem`:** 4KB Instruction Memory (1024 x 32-bit).
5.  **`bram_dmem`:** 4KB Data Memory (1024 x 32-bit).

## 3.2. Clocking & Reset Strategy
To guarantee system stability during startup and frequency locking, the top level implements a "Safe Reset" logic.
*   **Inputs:** `sys_clk_i` (Physical Oscillator), `rst_btn_i` (Physical Button).
*   **Logic:**
    ```verilog
    assign system_reset = rst_btn_i || !pll_locked;
    ```
*   **Behavior:** The entire system (Core + UART) is held in Hard Reset until the PLL indicates the derived clock is stable (`pll_locked == 1`). This prevents the UART from sampling noise and the Core from executing glitches.

## 3.3. Memory Subsystem Arbitration

Since the architecture guarantees that the Loader, Dumper, and Core never operate simultaneously (enforced by the C2 Arbiter), the memory interfaces are managed via **Combinational Multiplexing**. This separates the Core's PC from the loading process, preventing invalid instruction fetching during code injection.

### 3.3.1. Instruction Memory (IMEM) Mux

* **Master 1:** **Loader Unit** (Active when `c2_loader_active` is High).
* **Address Source:** `loader_addr_o` (Internal counter from Loader).
* **Data Source:** `loader_wdata_o`.
* **Stall Constraint:** The Core is forced into a **Global Stall** by the Top Level logic while the Loader is active.


* **Master 2:** **Core Fetch Stage** (Default).
* **Address Source:** `core_pc_o`.

* **Logic:**
```verilog
assign imem_addr = (c2_loader_active) ? loader_addr_o : core_pc_o;
assign imem_din  = loader_wdata_o;
assign imem_we   = (c2_loader_active && loader_target_o == 0) ? loader_we_o : 1'b0;
```

### 3.3.2. Data Memory (DMEM) Mux (Tri-State Logic)

* **Master 1:** **Loader Unit** (Active when `c2_loader_active` is High and `loader_target_o == 1`). Uses `loader_addr_o`.
* **Master 2:** **Dumping Unit** (Active when `dump_active`). Reads memory for serialization.
* **Master 3:** **Core Memory Stage** (Default). Reads/Writes during execution.
* **Logic:**
```verilog
always @(*) begin
    if (c2_loader_active && loader_target_o == 1) begin
        dmem_addr = loader_addr_o;
        dmem_we   = 1;
        dmem_din  = loader_wdata_o;
    end else if (c2_dumper_active) begin
        dmem_addr = dumper_read_addr;
        dmem_we   = 0;
        dmem_din  = 32'b0; // Don't care
    end else begin
        dmem_addr = core_alu_result;
        dmem_we   = core_mem_write;
        dmem_din  = core_store_data;
    end
end
```

### 3.3.2. Data Memory (DMEM) Mux (Tri-State Logic)

* **Master 1:** **Loader Unit** (Active when `c2_loader_active` is High and `loader_target_o == 1`). Uses `loader_addr_o`.
* **Master 2:** **Dumping Unit** (Active when `dump_active`). Reads memory for serialization.
* **Master 3:** **Core Memory Stage** (Default). Reads/Writes during execution.
* **Logic:**
```verilog
always @(*) begin
    if (c2_loader_active && loader_target_o == 1) begin
        dmem_addr = loader_addr_o;
        dmem_we   = 1;
        dmem_din  = loader_wdata_o;
    end else if (c2_dumper_active) begin
        dmem_addr = dumper_read_addr;
        dmem_we   = 0;
        dmem_din  = 32'b0; // Don't care
    end else begin
        dmem_addr = core_alu_result;
        dmem_we   = core_mem_write;
        dmem_din  = core_store_data;
    end
end

```

### 3.4: Debug Tapping

The `riscv_core` module exposes a dedicated debug interface to the `c2_interface_top`. This allows the **Dumping Unit** to extract internal state without interrupting the processor's primary datapath logic.

* **Register File Access:** Instead of a flattened bus, the core provides a dedicated asynchronous debug read port from the `register_file`.
    * `rs_dbg_addr_i` (5-bit): Address driven by the Dumping Unit counter.
    * `rs_dbg_data_o` (32-bit): Resulting data.
* **Pipeline Visibility:** The internal states of the IF/ID, ID/EX, EX/MEM, and MEM/WB registers are concatenated into fixed-width buses.
* **Hazard & Flow Status:** Current stall signals, flush flags, and the `is_halt` status from the Writeback stage are exposed for real-time monitoring.




## 3.5. Physical I/O Mapping
*   **`CLK`**: 100 MHz Oscillator Input.
*   **`RST`**: Push-button (Active High).
*   **`UART_RX`**: Connected to `c2_interface_top.uart_rx_i`.
*   **`UART_TX`**: Connected to `c2_interface_top.uart_tx_o`.

## 3.6. Core Stall Logic

The processor's `global_stall_i` input is managed by a **Safety Multiplexer**. This implements a "Safe by Default" policy where the core is hard-frozen in all system states (Idle, Loading, Dumping) except when explicitly handed over to the Debug Unit for execution.

* **Logic:**
```verilog
// If Debug Mode is active, the Debug Unit controls the stall (Run/Step/Pause).
// Otherwise, the Core is permanently frozen (1).
assign riscv_core_stall = (c2_debug_mode_active) ? debug_stall_o : 1'b1;

```


* **Behavior:**
1. **Loader/Idle/Cleanup States:** `c2_debug_mode_active` is Low. Core Stall is `1`. (Safe).
2. **Continuous Run:** `c2_debug_mode_active` is High. `debug_stall_o` is driven Low by Debug Unit. Core Runs.
3. **Single Step:** `c2_debug_mode_active` is High. `debug_stall_o` pulses Low for 1 cycle.

---

# 4. C2 System Wrapper (`c2_interface_top`)

## 4.1. Functional Responsibilities
The `c2_interface_top` module serves as the hardware encapsulation layer for all Command, Control, and Debug logic. It isolates the complex communication protocols from the `riscv_core`, exposing only a clean, simplified interface for memory injection and processor control. This module is responsible for instantiating the physical UART transceiver, the central Arbiter, and the specialized functional units (Loader, Debugger, Dumper).

## 4.2. Architecture & Interconnects
The module is organized internally as a hub-and-spoke topology with the **UART Transceiver** and **C2 Arbiter** at the center.

*   **Communication Bus:** The module aggregates the `tx` and `rx` lines from the Loader, Debugger, and Dumper. It connects them to the single `uart_transceiver` instance via the routing logic controlled by the Arbiter's grant signals.
*   **Control Distribution:** It routes the `grant_*` and `done_*` handshake signals between the Arbiter and the sub-modules.
*   **Global Reset Strategy:** The module receives the `clk_wizard_locked` signal from the top level and generates a synchronized internal reset. This ensures that the FSMs (Arbiter, Loader, Debugger) remain in a safe reset state until the clock is stable.

## 4.3. External Interfaces
The wrapper exposes three distinct interfaces to the `riscv_fpga_top`:

### 4.3.1. Physical Interface
*   `uart_rx_i`: Serial input from the FTDI/USB bridge.
*   `uart_tx_o`: Serial output to the FTDI/USB bridge.
*   `sys_clk_i`: Master system clock (post-PLL).
*   `pll_locked_i`: System stability indicator.

### 4.3.2. Memory Control Interface (Loader)
*   `loader_we_o`: Write Enable flag. When High, the memory controller should prioritize the Loader over the CPU.
*   `loader_addr_o`: The 32-bit address pointer for memory writing.
*   `loader_wdata_o`: The 32-bit instruction/data word to be written.
*   `loader_target_o`: Selector bit (0 = Instruction Memory, 1 = Data Memory).

### 4.3.3. Core Control & Debug Interface

* **Control Outputs:**
    * `debug_mode_active_o`: Status flag indicating the Arbiter has granted control to the **Debug Unit**.
        * **0:** System is in Maintenance Mode (Load/Idle/Dump). Force Core Stall.
        * **1:** System is in Execution Mode. Allow `debug_stall_o` to control the Core.

    * `debug_stall_o`: The execution control line from the **Debug Unit**.
        * **0:** Run.
        * **1:** Pause.
        * *Note:* This signal is only "listened to" by the Core when `debug_mode_active_o` is High.

    * `soft_reset_o`: Global flush signal driven by the Arbiter's cleanup state. Connects to the Core's `global_flush_i` input.

* **Status Inputs:**
    * `core_halted_i`: Indicates the processor has committed a `HALT` (ECALL) instruction.

---

# 5. UART Physical Layer (`uart_transceiver`)

## 5.1. Overview and Parameters
The physical layer handles serialization and deserialization over the UART interface using an **8N1** configuration. Due to the integration of a **Clock Wizard** to satisfy the core's critical path ($t_{min}$), the clock frequency is considered a dynamic parameter.

*   **Clock Frequency (`CLK_FREQ`):** Must match the output frequency of the Clock Wizard. If timing analysis requires slowing the system to satisfy the critical path, this parameter must be updated accordingly to maintain baud rate accuracy.
*   **System Stability:** The UART modules must be held in reset until the Clock Wizard's `locked` signal is asserted, ensuring sampling logic operates on a stable frequency.
*   **Baud Rate Selection:** 2-bit `BAUD_SELECTOR` (9600 to 115200).
*   **Oversampling:** Uses a `baud_rate_generator` to produce a `tick_16x` signal for center-aligned sampling.

## 5.2. Transmitter Logic (`uart_tx`)
The transmitter serializes 8-bit data. It includes hardware interlocks to prevent corruption during transmission.

*   **Inputs:** `data_in` (8-bit), `start` (1-cycle pulse).
*   **Outputs:** `serial_out`, `busy`, `tx_done_tick` (1-cycle pulse).
*   **Data Locking:** Upon the assertion of `start`, the module immediately latches `data_in` into an internal buffer. Subsequent changes to the input pins do not affect the current transmission.
*   **Protocol Interlock:** If a `start` pulse is received while `busy` is High, the pulse is ignored.
*   **Completion Signal:** When the Stop bit is finished, the module lowers `busy` and fires `tx_done_tick`. This pulse is the primary trigger for the `dumping_unit` to load the next byte in the stream.

## 5.3. Receiver Logic (`uart_rx`)
The receiver deserializes incoming data and filters out metastability via a double-flop synchronizer.

*   **Inputs:** `serial_in`.
*   **Outputs:** `data_out` (8-bit), `data_ready_pulse` (1-cycle pulse), `error_frame`.
*   **Sampling:** Detects the start bit's falling edge and samples at the 8th tick (center). Data bits are sampled at the 16th tick interval thereafter (center of each bit window).
*   **Validation:** If the Stop bit is not High at the sampling point, `error_frame` is asserted and the byte is discarded to prevent the C2 Arbiter from executing malformed commands.

---

# 6. Command & Control Arbiter (`c2_arbiter`)

## 6.1. Functional Overview

The `c2_arbiter` acts as the system's central management unit and "Traffic Controller." Its primary responsibility is to maintain the UART as a critical section, ensuring that only one module at a time has access to the transceiver's serial resources. It interprets high-level commands from the Host and manages the handover of control to the Loader or Debug units.

Additionally, the Arbiter acts as the **System Janitor**. It enforces a strict "Clean Before Use" policy: regardless of whether the previous operation was a Memory Load or a Code Execution, the Arbiter triggers a Soft Reset (`S_CLEANUP`) upon completion. This guarantees that the Core always begins the next operation from a deterministic state (PC=0).

## 6.2. UART Bus Switch (Routing Logic)
The Arbiter implements a combinational routing matrix to isolate sub-modules from the UART signals. This prevents inactive modules from accidentally receiving data or corrupting the transmission line.

*   **RX Path Gating:** The `data_ready_pulse` from the `uart_rx` module is gated via a 1-to-Many Demultiplexer. Only the module currently "granted" access by the Arbiter will receive the pulse.
*   **TX Path Multiplexing:** The `tx_data` and `tx_start` inputs of the `uart_tx` module are driven by a Many-to-One Multiplexer. The Arbiter selects the active driver based on the current state.
*   **Conflict Prevention:** All sub-modules are implicitly denied access to the physical pins unless they hold a valid `grant` signal.

## 6.3. FSM & Interpretation Logic

The Arbiter operates via a Master Finite State Machine designed for low-latency handoffs and automatic system scrubbing:

1. **IDLE:** Monitors the gated UART RX for a Command Byte.
2. **DECODE:** Identifies the command (`0x1C`, `0x1D`, `0xCE`, `0xDE`) via the `c2_byte_table`.
3. **ACK_HANDOFF (Fire & Forget):**
    * **Cycle 0:** The Arbiter places the received Command Byte onto the `tx_data` bus and asserts `tx_start`.
    * **Cycle 1:** The Arbiter immediately asserts the specific `grant` signal for the target sub-module (e.g., `grant_loader_o`) and transitions state. It does **not** wait for the ACK transmission to complete.
    * *Rationale:* This allows the sub-module to catch incoming data packets (like "Size High Byte") that may arrive while the UART TX is still shifting out the ACK.
4. **SUB_MODULE_BUSY:** The Arbiter enters a passive monitoring state. It ignores UART traffic and waits solely for a `done_i` signal from the active sub-module.
5. **S_CLEANUP:** Entered immediately upon receiving `done_i`.
    * **Action:** Asserts `soft_reset_o` (driving `global_flush_i` on the Core).
    * **Goal:** Resets PC to 0 and invalidates pipeline buffers. This removes any residual state from a previous run or jump, ensuring the next `CMD_CONT_EXEC` starts from the reset vector.
6. **RECOVERY:** De-asserts `soft_reset_o` and all `grant` signals, then returns to **IDLE**.

---

# 7. Memory Loader Unit (`loader_unit`)

## 7.1. Functional Overview
The `loader_unit` is a specialized Direct Memory Access (DMA) engine designed for high-speed program and data injection. When granted control by the Arbiter, it bypasses the processor's memory interface to write directly to the BRAM blocks. It manages the reassembly of 8-bit UART packets into 32-bit RISC-V words and handles the addressing logic for sequential writing.

## 7.2. Interface Signals

*   **Arbiter Interface:**
    *   `grant_i`: Enable signal. Starts the Loader FSM.
    *   `target_select_i`: Configuration flag (`0` = Instruction Memory, `1` = Data Memory).
    *   `done_o`: Completion pulse to return control to the Arbiter.

*   **UART Transceiver Interface (Gated/Muxed):**
    *   `rx_data_i`: 8-bit byte from the receiver.
    *   `rx_ready_i`: Pulse indicating new data arrival.
    *   `tx_data_o`: 8-bit byte to be sent (for `0xF1` handshake).
    *   `tx_start_o`: Pulse to trigger transmission.
    *   `tx_done_i`: Pulse indicating the final ACK has been sent.

*   **Memory Interface Outputs:**
    *   `mem_write_enable_o`: Write strobe signal.
    *   `mem_addr_o`: 32-bit address pointer.
    *   `mem_data_o`: 32-bit assembled data word.

## 7.3. Word Assembly Logic (Endianness)
The module operates on a **Little-Endian** basis to match the RISC-V architecture and standard PC serial transmission (LSB first).
*   **Buffer:** A 32-bit shift register or byte-addressable array `word_buffer`.
*   **Sequence:**
    1.  Byte 0 (LSB) $\rightarrow$ `word_buffer[7:0]`
    2.  Byte 1 $\rightarrow$ `word_buffer[15:8]`
    3.  Byte 2 $\rightarrow$ `word_buffer[23:16]`
    4.  Byte 3 (MSB) $\rightarrow$ `word_buffer[31:24]`
*   **Write Trigger:** Upon receiving the 4th byte (Byte 3), the module asserts `mem_write_enable_o` for one clock cycle to commit the full 32-bit word to memory.

## 7.4. FSM Description
1.  **S_INIT:** Resets address pointers and counters. Waits for `rx_ready_i` (High Byte of Size).
2.  **S_SIZE_LOW:** Captures Low Byte of Size to form `total_word_count`.
3.  **S_RECEIVE_BYTE:** Generic state for payload reception. Increments an internal `byte_index` (0-3).
4.  **S_WRITE_WORD:** Active for 1 cycle after every 4th byte.
    *   Asserts `mem_write_enable_o`.
    *   Increments `mem_addr_o` (by 1, assuming Word-Addressable BRAM).
    *   Increments `words_processed_count`.
    *   Checks if `words_processed_count == total_word_count`.
        *   If **No**: Return to `S_RECEIVE_BYTE`.
        *   If **Yes**: Transition to `S_SEND_ACK`.
5.  **S_SEND_ACK:** Drives `0xF1` onto the UART TX bus and pulses `tx_start`. Waits for `tx_done`.
6.  **S_DONE:** Asserts `done_o` to the Arbiter, releasing control. Maybe should also cleanup (PC to 0 if Inst Mem, revert control of data memory to cpu, etc.)

## 7.5. Safety & Reliability
*   **Silent Operation:** During the data streaming phase, the Loader does not transmit any acknowledgments to the host to maximize throughput (avoiding TX/RX switching latency).
*   **Address Overflow Protection:** (Optional) The logic should saturate or wrap around if the address pointer exceeds the physical memory depth (1024 words), preventing invalid access attempts.

---

# 8. Debug & Execution Controller (`debug_unit`)

## 8.1. Functional Overview
The `debug_unit` manages the run-time operation of the processor. It takes control of the processor's global stall signals to implement two execution paradigms: **Continuous Run** (execute until completion) and **Step-by-Step** (execute one cycle at a time). It also acts as the master trigger for the **Dumping Unit**, orchestrating state serialization after execution events.

## 8.2. Interface Signals

* **Processor Control Interface:**
* `core_halted_i`: Status flag from the Core.
* `cpu_stall_o`: Drives the `debug_stall_o` line.
* **Default State:** `1` (Freeze).
* **Run State:** `0`.
* **Step State:** Pulses `0` for one cycle.

*   **Arbiter Interface:**
    *   `grant_i`: Enable signal. Activates the Debug Unit and drives `debug_mode_active_o` High at the C2 Wrapper level.
    *   `exec_mode_i`: Configuration flag (`1` = Continuous/Run, `0` = Step Mode).
    *   `done_o`: Pulse to release control back to the Arbiter (triggered upon System Halt).

*   **UART RX Interface (Gated):**
    *   `rx_data_i`: 8-bit byte from the receiver.
    *   `rx_ready_i`: Pulse indicating new data. Used to detect the `0xAE` (Advance) command in Step Mode.

*   **Processor Control Interface:**
    *   `core_halted_i`: Status flag from the Core (Writeback stage) indicating a `HALT` instruction has been committed.
    *   `cpu_stall_o`: Global stall signal to freeze the processor pipeline and PC. Drives the `debug_stall_o` line.
        * **Default State:** `1` (Freeze).
        * **Run State:** `0`.
    *   `cpu_reset_o`: Logic to reset the core PC before starting a new run.

*   **Dumping Unit Interface:**
    *   `dump_trigger_o`: Signals the Dumper to begin serializing state.
    *   `dump_mem_mode_o`: Configures the Dumper's memory strategy (`1` = Full Scoop via Min/Max, `0` = Differential via Writeback snooping).
    *   `dump_done_i`: Input signal indicating the Dumper has finished its transmission.

## 8.3. Finite State Machine (FSM)
The FSM behavior depends on the `exec_mode_i` latched upon entry.

### 8.3.1. Continuous Mode
1.  **RUN:** De-asserts `cpu_stall_o`, allowing the processor to run at full system speed. Sets `dump_mem_mode_o = 1`.
2.  **MONITOR:** Continuously checks `core_halted_i`.
3.  **HALT_DETECT:** Upon detection of `core_halted_i`:
    *   Asserts `cpu_stall_o` (Freezes state).
    *   Asserts `dump_trigger_o` (Dumps registers, pipeline, and "scooped" memory).
4.  **WAIT_DUMP:** Waits for `dump_done_i`.
5.  **EXIT:** Asserts `done_o` to Arbiter.

### 8.3.2. Step-by-Step Mode
1.  **WAIT_CMD:** Asserts `cpu_stall_o`. Sets `dump_mem_mode_o = 0`. Waits for `rx_ready_i`.
    *   If `rx_data_i == 0xAE` (CMD_ADVANCE): Transition to **STEP**.
2.  **STEP (Pulse):**
    *   De-asserts `cpu_stall_o` for exactly **one clock cycle**.
    *   Re-asserts `cpu_stall_o` immediately after.
3.  **DUMP:** Asserts `dump_trigger_o` to show the new state to the user. 
4.  **WAIT_DUMP:** Waits for `dump_done_i`.
5.  **CHECK_STATUS:**
    *   If `core_halted_i` is High: Transition to **EXIT**.
    *   Else: Return to **WAIT_CMD** for the next step.

---

# 9. State Serialization Unit (`dumping_unit`)

## 9.1. Functional Overview
The `dumping_unit` is a parallel-to-serial converter responsible for extracting the internal state of the processor and transmitting it to the host. It provides visibility into the Register File, Pipeline Registers, and Data Memory. It features a "Smart Dump" optimization for Data Memory to minimize transmission time during single-stepping and sparse memory usage.

## 9.2. Interface Signals
*   **Debug Interface:**
    *   `dump_trigger_i`: Start pulse.
    *   `dump_mem_mode_i`: Strategy selector (`0`=Step/Diff, `1`=Continuous/Range).
    *   `dump_done_o`: Completion pulse.
*   **Core Taps (Inputs):**
    *   **Register File:** `rf_dbg_addr_o` (5-bit), `rf_dbg_data_i` (32-bit). (Uses a dedicated read port or time-multiplexed access).
    *   **Pipeline:** `if_id_flat_i`, `id_ex_flat_i`, `ex_mem_flat_i`, `mem_wb_flat_i` (Flattened buses containing control, data, and metadata).
    *   **Hazards:** `hazard_status_i` (Flattened bus of stall/flush signals).
*   **Memory Interface:**
    *   `dmem_addr_o`: Address pointer for reading RAM.
    *   `dmem_data_i`: Data read from RAM.
    *   `dmem_write_en_snoop`: Input from the Core's MEM stage to detect writes during stepping.
    *   `dmem_addr_snoop`: Input from the Core's MEM stage to capture write addresses.
    *    `min_addr_i`, `max_addr_i`: Inferior and superior limit for the Memory "scoop". This is directly connected to the Core's "Memory Range Tracker" module.


## 9.3. Register File Serialization
To avoid routing 1024 wires (`32 x 32`), this unit iterates sequentially.
*   **Logic:** An internal counter `rf_idx` counts from 0 to 31.
*   **Access:** In each step, `rf_dbg_addr_o` is driven by `rf_idx`.
*   **Transmission:** The 32-bit `rf_dbg_data_i` is split into 4 bytes (LSB first) and sent via UART.
*   **Total Payload:** 128 Bytes.

## 9.4. Pipeline State Serialization
Pipeline registers are packed into fixed-width byte structures. Bit-fields from the `core_microarch_specs` are concatenated and padded to the nearest byte boundary.

*   **IF/ID:** 64 bits $\rightarrow$ 8 Bytes.
*   **ID/EX:** ~167 bits $\rightarrow$ Padded to 21 Bytes. Includes Control Bus, PC, RS1/RS2 Data, Imm, and Metadata.
*   **EX/MEM:** ~110 bits $\rightarrow$ Padded to 14 Bytes. Includes ALU Result, RS2 Data, and PC+4.
*   **MEM/WB:** ~105 bits $\rightarrow$ Padded to 14 Bytes. Includes Final Result and Load Data.
*   **Hazard Flags:** 2 Bytes containing stall, flush, and forwarding status.

## 9.5. Data Memory Optimization
The unit implements two distinct strategies based on `dump_mem_mode_i`.

### 9.5.1. Continuous Mode (Range Scoop)
*   **Tracking:** A hardware monitor tracks the `min_addr` and `max_addr` written to Data Memory during execution.
*   **Protocol:**
    1.  Send `min_addr` (4 bytes).
    2.  Send `max_addr` (4 bytes).
    3.  Loop `addr` from `min` to `max`: Read `dmem_data_i` and transmit 4 bytes.

### 9.5.2. Step Mode (Differential)
*   **Logic:** The unit inspects the **MEM/WB** pipeline register state (specifically `mem_write_en` and `alu_result`).
*   **Protocol:**
    *   If `mem_write_en` is High: Send `Flag=1` (1 Byte), then `Address` (4 Bytes), then `Data` (4 Bytes).
    *   If `mem_write_en` is Low: Send `Flag=0` (1 Byte).
*   **Benefit:** Reduces payload from ~4KB (full RAM) to just 1-9 bytes per step.


## 9.6. Finite State Machine (FSM)
The unit is controlled by a linear sequential FSM:

1.  **S_IDLE:** Waits for `dump_trigger_i`. Upon activation, latches `dump_mem_mode_i`.
2.  **S_SEND_HEADER:** Transmits `0xDA` (Dump Alert) and the Mode Byte.
3.  **S_DUMP_REGS:** Loops `rf_idx` from 0 to 31. Controls UART TX to send 4 bytes per register.
4.  **S_DUMP_PIPELINE:** Sequentially selects the padded slices of the pipeline buses and transmits them byte-by-byte.
5.  **S_DUMP_MEM_CONFIG:**
    *   If Mode is **Continuous**: Transmits `min_addr` and `max_addr`. Initializes `dmem_addr_o = min_addr`.
    *   If Mode is **Step**: Checks `dmem_write_en_snoop`. Transmits the Flag Byte.
6.  **S_DUMP_MEM_PAYLOAD:**
    *   **Continuous:** Loops until `dmem_addr_o > max_addr`. Reads RAM and transmits 4 bytes per word.
    *   **Step:** If Flag was 1, transmits `dmem_addr_snoop` and `dmem_write_data_snoop`.
7.  **S_DONE:** Pulses `dump_done_o` and returns to **S_IDLE**.

---

# 10. Communication Protocol Definition

## 10.1. UART Packet Structure
Standard asynchronous and no parity frame:

|Start |D[0]|D[1]|D[2]|D[3]|D[4]|D[5]|D[6]|D[7]|Stop |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
|0|X|X|X|X|X|X|X|X|1|

## 10.2. Command Byte Reference Table (Host to FPGA)
These commands (except `0xAE` and `0xDA`) are interpreted by the **C2 Arbiter** only when the system is in the IDLE state.

| Hex | Mnemonic | Description |
| :--- | :--- | :--- |
| **0x1C** | `CMD_LOAD_CODE` | Transition to **Loader Unit**. Target: Instruction Memory. |
| **0x1D** | `CMD_LOAD_DATA` | Transition to **Loader Unit**. Target: Data Memory. |
| **0xCE** | `CMD_CONT_EXEC` | Transition to **Debug Unit**. Mode: Continuous until HALT. |
| **0xDE** | `CMD_DEBUG_EXEC` | Transition to **Debug Unit**. Mode: Single-cycle stepping. |
| **0xAE** | `CMD_ADVANCE_EXEC` | Should be sent in Step Mode only. Pulses the core for 1 cycle. (i.e. releases global stall)|

## 10.3. Response Codes (FPGA to Host)

| Hex | Mnemonic | Description |
| :--- | :--- | :--- |
| **0xXX** | `ACK_ECHO` | Immediate echo of the received command. |
| **0xF1** | `ACK_FINISH` | Sent by the **Loader** when the word count is reached. |
| **0xDA** | `RSP_DUMP_ALERT` | Sent by the **Dumper** to signal a state stream. |

## 10.4. Loading Protocol (Sequence)
1.  **Command Initiation:** Host sends `0x1C` or `0x1D`.
2.  **Hardware Handoff:** FPGA echoes the command. The Arbiter immediately grants UART control to the **Loader Unit**.
3.  **Size Capture:** Host sends 2 bytes (16-bit word count). The Loader captures these to set the internal loop limit.
4.  **Data Stream:** Host sends `Word_Count * 4` bytes.
    *   The Loader is silent during this phase to maximize throughput.
    *   Words are assembled and written to BRAM in 1 clock cycle per 4 bytes received.
5.  **Closing Handshake:** Once the final word is written, the Loader sends `0xF1` (ACK_FINISHED_LOADING) to the Host.
6.  **Arbiter Recovery:** The Loader asserts `done` to the Arbiter, which returns the system to **S_CLEANUP** and then ultimately to **S_IDLE**.

## 10.5. Dump Stream Protocol
Initiated by `RSP_DUMP_ALERT` (0xDA). All multi-byte values are sent **Little Endian** (LSB first).

### 10.5.1. Header & Configuration
| Offset | Size | Description |
| :--- | :--- | :--- |
| 0x00 | 1 Byte | **Alert Byte:** `0xDA` |
| 0x01 | 1 Byte | **Mode:** `0x00` = Step (Diff), `0x01` = Continuous (Range) |

### 10.5.2. Register File Dump (Fixed 128 Bytes)
| Sequence | Size | Content |
| :--- | :--- | :--- |
| 1 | 4 Bytes | Register x0 (Always 0) |
| 2 | 4 Bytes | Register x1 (ra) |
| ... | ... | ... |
| 32 | 4 Bytes | Register x31 |

### 10.5.3. Pipeline Dump (Fixed 59 Bytes)

| Section | Size | Fields Included (Packed) |
| :--- | :--- | :--- |
| **Hazard** | 2 Bytes | **Byte 0 (Control):** `[4]ID_Flush`, `[3]IF_Flush`, `[2]EX_Stall`, `[1]ID_Stall`, `[0]PC_Stall` <br> **Byte 1 (Forward):** `[3:2]Forward_A_Optn`, `[1:0]Forward_B_Optn` |
| **IF/ID** | 8 Bytes | `Inst` (4B), `PC` (4B) |
| **ID/EX** | 21 Bytes | `Ctrl_Bus` (2B), `PC` (4B), `RS1_Data` (4B), `RS2_Data` (4B), `Imm` (4B), `Metadata` (3B) |
| **EX/MEM** | 14 Bytes | `Ctrl_Bus` (1B), `ALU_Result` (4B), `RS2_Data` (4B), `PC+4` (4B), `Metadata` (1B) |
| **MEM/WB** | 14 Bytes | `Ctrl_Bus` (1B), `Final_Data` (4B), `PC+4` (4B), `Metadata` (1B), `Padding` (4B) |

### 10.5.4. Memory Dump (Variable)

**Case A: Continuous Mode (`Mode == 0x01`)**
| Sequence | Size | Content |
| :--- | :--- | :--- |
| 1 | 4 Bytes | `Min_Address` |
| 2 | 4 Bytes | `Max_Address` |
| 3 | N * 4 Bytes | Memory Words (from Min to Max) |

**Case B: Step Mode (`Mode == 0x00`)**
| Sequence | Size | Content |
| :--- | :--- | :--- |
| 1 | 1 Byte | **Write Flag:** `0x01` if write occurred, `0x00` otherwise. |
| 2 (If Flag=1) | 4 Bytes | `Write_Address` |
| 3 (If Flag=1) | 4 Bytes | `Write_Data` |
