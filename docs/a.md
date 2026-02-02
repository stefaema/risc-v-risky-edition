### 3.4: Debug Tapping

The `riscv_core` module exposes a dedicated debug interface to the `c2_interface_top`. This allows the **Dumping Unit** to extract internal state without interrupting the processor's primary datapath logic.

* **Register File Access:** Instead of a flattened bus, the core provides a dedicated asynchronous debug read port from the `register_file`.
    * `rs_dbg_addr_i` (5-bit): Address driven by the Dumping Unit counter.
    * `rs_dbg_data_o` (32-bit): Resulting data.
* **Pipeline Visibility:** The internal states of the IF/ID, ID/EX, EX/MEM, and MEM/WB registers are concatenated into fixed-width buses.
* **Hazard & Flow Status:** Current stall signals, flush flags, and the `is_halt` status from the Writeback stage are exposed for real-time monitoring.


