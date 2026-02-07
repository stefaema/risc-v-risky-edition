# Coding Conventions

Every testbench in the `riscv_core` project must adhere to the following structural and visual template to ensure consistent verification logs. For non-testbench directives, go to the end.

## 0. File Header
- Make a header with the format:
// -----------------------------------------------------------------------------
// Module:
// Description: 
// -----------------------------------------------------------------------------

## 1. Mandatory Metadata & Color Palette

All testbenches must define a unique `FILE_NAME` and the standard ANSI escape sequences for terminal coloring.

```systemverilog
// localparam string FILE_NAME = "Distinct, Smart and Funny Name"; // e.g., "Adder-all instead of Adder"
localparam string C_RESET = "\033[0m";    // Text Reset
localparam string C_RED   = "\033[1;31m"; // Error/Fail (Bold Red)
localparam string C_GREEN = "\033[1;32m"; // Success/Pass (Bold Green)
localparam string C_BLUE  = "\033[1;34m"; // Section Header (Bold Blue)
localparam string C_CYAN  = "\033[1;36m"; // TB Header/Footer (Bold Cyan)

```

## 2. Visual Structure

### **A. Header Block**

The simulation start must be announced with a stylized Cyan box.

```systemverilog
$display("\n%s=======================================================%s", C_CYAN, C_RESET);
$display("%s Testbench: %-38s %s", C_CYAN, FILE_NAME, C_RESET);
$display("%s=======================================================%s\n", C_CYAN, C_RESET);

```

### **B. Automated Check Task**

Validation logic must be encapsulated in a `check` task. It is responsible for:

1. Incrementing the global `test_count`.
2. Comparing signals using the identity operator (`===`).
3. Printing formatted `[PASS]` or `[FAIL]` status with field-width alignment (`%-40s`).
4. Incrementing `error_count` and providing detailed mismatch info on failure.

```systemverilog
task check(input logic [31:0] expected, input string test_name);
    test_count++;
    if (observed_signal === expected) begin
        $display("%-40s %s[PASS]%s", test_name, C_GREEN, C_RESET);
    end else begin
        $display("%-40s %s[FAIL]%s", test_name, C_RED, C_RESET);
        $display("   Expected: 0x%h", expected);
        $display("   Received: 0x%h", observed_signal);
        error_count++;
    end
endtask

```

### **C. Summary Footer**

Upon completion, the testbench must output a Blue summary line followed by a result status.

* **Success:** Green "SUCCESS" if `error_count == 0`.
* **Failure:** Red "FAILURE" if `error_count > 0`.

```systemverilog
$display("\n%s-------------------------------------------------------%s", C_BLUE, C_RESET);
if (error_count == 0) begin
    $display("Tests: %0d | Errors: %0d -> %sSUCCESS%s", test_count, error_count, C_GREEN, C_RESET);
end else begin
    $display("Tests: %0d | Errors: %0d -> %sFAILURE%s", test_count, error_count, C_RED, C_RESET);
end
$display("%s-------------------------------------------------------%s\n", C_BLUE, C_RESET);

```

## 3. Test Case Anatomy (Stimulus & Timing)

Every test case must follow this **Setup-Trigger-Check** pattern. This structure ensures that signals have settled and prevents simulator race conditions.

```systemverilog
// --- Test N: {Brief Description} ---

// 1. Setup: Drive inputs. Use @(posedge clk) for synchronous logic. Cleanup preivous states.
@(posedge clk);
rst_n = 1;
pc_i  = 32'h0000_0004;

// 2. Trigger: Wait for edge + 1ns "Sampling Window".
@(posedge clk); 
#1; // Critical: Moves sampling point away from the transition edge.

// 3. Check: Validate output.
check(32'h0000_0004, "PC Update to 0x4");


```

* **For Sequential Logic:** Always wait for the active clock edge and add a `#1` delay. This "Golden Delta" mimics real-world hold time and ensures the simulator has finished the non-blocking assignments (`<=`).
* **For Combinational Logic:** Replace the `@(posedge clk)` with a simple `#1;` to allow for gate propagation.
* **The `$finish` Guard:** Always terminate the final `initial` block with `$finish` to prevent simulator hang.

---

## 4. Commenting Convention

To maintain a "clean code" aesthetic, comments should be surgical. Avoid stating the obvious (e.g., `i++; // increment i`).

* **Section/Test Delimiters:
        ** Use a triple-hyphen line to mark the start of a code section. Don't use them too much. Mark initial block and similar. Use only one when delimiting tests.
        * `// --- Clock Generation ---`
        * `// - Test 1: Cold Boot Reset`


* **Explanatory In-lines:** Only use in-line comments to explain the *intent* or a specific hardware quirk that isn't immediately obvious from the signal names.
* `#1; // Wait for non-blocking assignments to settle`


* **Minimalism:** If the code is readable, let it speak. Only comment when a "why" is needed, not a "what."

## 5. Non-testbench Directives
- Make a header with the format:
    // -----------------------------------------------------------------------------
    // Module:
    // Description: 
    // -----------------------------------------------------------------------------

- Naming Conventions 1:

To ensure compatibility with the project's automation scripts (`manage.py`) and Vivado's elaboration flow, all testbenches must follow a strict suffix-based naming convention.

* **Module Name:** The testbench module must be named by appending `_tb` to the name of the Design Under Test (DUT). Also, the source file name is the DUT name ended with .sv.
* **File Name:** The source file should be named identically to the testbench module (e.g., `mux2_tb.sv`).

| Design Module | Testbench Module Name |
| --- | --- |
| `mux2` | `mux2_tb` |
| `alu` | `alu_tb` |
| `riscv_core` | `riscv_core_tb` |


- Naming Conventions 2:

    To maintain a balance between structural clarity and code readability, we apply suffixes selectively. Avoid redundant suffixes (e.g., `_o`) on signals whose names already imply their direction or purpose.

    | Suffix | Category | Requirement | Example |
    | --- | --- | --- | --- |
    | **`_i`** | **Primary Inputs** | Mandatory for raw data or instruction inputs to distinguish them from internal wires. | `opcode_i`, `data_i` |
    | **`_en`** | **Enables/Strobes** | Mandatory for control signals that trigger a write, a read, or a state change. | `reg_write_en`, `mem_en` |
    | **`_optn`** | **Mux Selectors** | Mandatory for signals driving multiplexer select inputs to clarify they are routing options. | `alu_src_optn`, `rd_src_optn` |
    | **`_o`** | **Data Outputs** | Use **only** for ambiguous nouns that could be confused with internal wires or inputs. | `alu_result_o` |

