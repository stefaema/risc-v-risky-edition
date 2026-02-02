# 6. Command & Control Arbiter (`c2_arbiter`)

## 6.1. Functional Overview

The `c2_arbiter` acts as the system's central management unit and "Traffic Controller." Its primary responsibility is to maintain the UART as a critical section, ensuring that only one module at a time has access to the transceiver's serial resources. It interprets high-level commands from the Host and manages the handover of control to the Loader or Debug units.

Additionally, the Arbiter acts as the **System Janitor**. It enforces a strict "Clean Before Use" policy: regardless of whether the previous operation was a Memory Load or a Code Execution, the Arbiter triggers a Soft Reset (`S_CLEANUP`) upon completion. This guarantees that the Core always begins the next operation from a deterministic state (PC=0).

## 6.2. UART Bus Switch (Routing Logic)
The Arbiter implements a combinational routing matrix to isolate sub-modules from the UART signals. This prevents inactive modules from accidentally receiving data or corrupting the transmission line.

* **RX Path Gating:** The `data_ready_pulse` from the `uart_rx` module is gated via a 1-to-Many Demultiplexer. Only the module currently "granted" access by the Arbiter will receive the pulse.
* **TX Path Multiplexing:** The `tx_data` and `tx_start` inputs of the `uart_tx` module are driven by a Many-to-One Multiplexer. The Arbiter selects the active driver based on the current state.
* **Conflict Prevention:** All sub-modules are implicitly denied access to the physical pins unless they hold a valid `grant` signal.

## 6.3. FSM & Interpretation Logic

The Arbiter operates via a Master Finite State Machine designed to ensure protocol stability before handing off control:

1. **IDLE:** Monitors the gated UART RX for a Command Byte.
2. **DECODE:** Identifies the command (`0x1C`, `0x1D`, `0xCE`, `0xDE`) via the `c2_byte_table`.
3. **ACK_TRIGGER:** The Arbiter places the received Command Byte onto the `tx_data` bus and asserts `tx_start` for one cycle.
4. **ACK_WAIT (Blocking):**
    * The Arbiter enters a wait state until `uart_tx_done_i` is asserted by the transceiver.
    * **Crucial:** During this time, **no** grant signals are issued to sub-modules. This prevents the Host from sending payload data (e.g., Size bytes) before the FPGA is fully ready to listen.
5. **SUB_MODULE_BUSY:** Entered immediately after the ACK transmission completes.
    * The specific `grant` signal (Loader or Debugger) is asserted.
    * The Arbiter ignores UART traffic and waits solely for a `done_i` signal from the active sub-module.
6. **S_CLEANUP:** Entered immediately upon receiving `done_i`.
    * **Action:** Asserts `soft_reset_o` (driving `global_flush_i` on the Core).
    * **Goal:** Resets PC to 0 and invalidates pipeline buffers.
7. **RECOVERY:** De-asserts `soft_reset_o` and all `grant` signals, then returns to **IDLE**.
