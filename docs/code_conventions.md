# Code & Format Conventions

## 1. Source Code (RTL) Standards

### **Logic & Syntax**

* **Data Types:** Always use `logic` for internal signals. Use `wire` only for tri-state nets.
* **Procedural Blocks:**
* Use `always_comb` for combinational logic (decoders, muxes).
* Use `always_ff @(posedge clk or negedge rst_n)` for sequential logic.
* **Clock Gating:** Prohibited. Use enable signals and conditional logic within procedural blocks to manage state updates.


* **Assignments:** Use non-blocking (`<=`) for sequential logic and blocking (`=`) for combinational logic.
* **Interfaces:** Use `logic [31:0]` for standard RV32I data/address buses.

### **Naming Conventions**

* **Modules:** Subject to developer discretion; should be concise and potentially humorous.
* **Ports/Signals:** `snake_case` (e.g., `reg_write_en`).
* **Constants and localparams:** `UPPER_CASE` (e.g., `DATA_WIDTH`).

---

## 2. Testbench (TB) Standards

All testbenches must follow the **ANSI Color-Coded Verification** pattern.

### **Mandatory Metadata**

Every TB must define a `localparam string FILE_NAME` at the top and include the following color definitions:

```systemverilog
localparam string FILE_NAME = "example_tb.sv";
localparam string C_RESET  = "\033[0m";
localparam string C_RED    = "\033[1;31m"; // Error/Fail
localparam string C_GREEN  = "\033[1;32m"; // Success/Pass
localparam string C_BLUE   = "\033[1;34m"; // Section Header
localparam string C_CYAN   = "\033[1;36m"; // TB Header/Footer

```

### **Structure & Logging**

1. **Header:** Display a stylized title:
```
        $display("\n%s=======================================================%s", C_CYAN, C_RESET);
        $display("%s Testbench: %-38s %s", C_CYAN, FILE_NAME, C_RESET);
        $display("%s=======================================================%s\n", C_CYAN, C_RESET);
```
2. **Tasks:** Encapsulate validation logic in a `check` task to automate result comparison and increment `error_count` and `test_count`. Use field widths (`%-15s`) to ensure aligned, scannable logs.
3. **Visual Feedback:**
* `[PASS]` in **Bold Green** for successful assertions.
* `[FAIL]` in **Bold Red** for mismatches, explicitly displaying Expected vs. Received values.


4. **Summary:** A final report in Cyan must provide the total test count and error count, explicitly stating "SUCCESS" or "FAILURE".
5. **Termination:** Explicitly use `$finish` at the end of the `initial` block to prevent simulator hang.

---

## 3. Documentation Standards

### **RTL Comments**
// -----------------------------------------------------------------------------
// Module: [Module_Name]
// Description: [Clear, concise purpose of the module]

// -----------------------------------------------------------------------------

* **Header:** Use the `// ---- \n // \n // ----` format for all module file headers (above). For the rest of comments, the ones that delimit sections or answer a why question, use common one-liners.
* **Commentary:** Focus on the **intent** ("the why") rather than the syntax ("the what").

### **Pipeline Hierarchy**

* Maintain a strict separation between combinational "Logic Clouds" and synchronous "Pipeline Registers" (latches).
* Utilize SystemVerilog `struct packed` to group signals transiting between stages (e.g., `IF_ID_reg`, `ID_EX_reg`) to ensure clean top-level interconnects.
