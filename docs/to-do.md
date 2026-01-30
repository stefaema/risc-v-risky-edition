## 🛠️ RV32I Development Roadmap

### Phase 1: The "Easy" Independent Modules

These can be written and unit-tested individually without needing the rest of the pipeline.

* [x] **Implement the Immediate Generator:** Create `immediate_generator.sv`. Use a `case` statement based on the opcode/instruction type to unscramble the bits for I, S, B, U, and J formats.
* [x] **Build the Register File:** Create `register_file.sv`. Remember to hardwire `x0` to zero and ensure your reads are asynchronous (so the data is ready for the ALU in the same cycle during simulation/simple designs).
* [ ] **Create the Program Counter (PC) Logic:** Write the `program_counter.sv` and a simple `pc_adder.sv` (fixed +4).
* [ ] **Design the Branch Comparator:** Create a small module that takes two operands and a `funct3` signal to output a single `branch_taken` bit. Moving this logic out of the ALU makes your control flow cleaner.

---

### Phase 2: Control Logic & Pipeline Registers

Now you start defining how the data moves between the modules you just built.

* [ ] **Develop the Main Control Unit:** Create `control_unit.sv`. Map the 7-bit opcodes to your internal signals (`RegWrite`, `ALUSrc`, `MemRead`, etc.).
* [ ] **Define Pipeline Register Structs (Optional but Recommended):** In SystemVerilog, use `struct packed` to define the interfaces between IF/ID, ID/EX, EX/MEM, and MEM/WB. This makes your top-level file much cleaner.
* [ ] **Implement the Pipeline Latches:** Create the four sets of registers that sit between your stages. Ensure they have a `stall` input and a `flush` (reset) input.

---

### Phase 3: Hazard & Forwarding (The "Brain")

This is the most challenging part of a pipelined core and where most bugs live.

* [ ] **Implement the Forwarding Unit:** Write logic that compares source registers in the **EX** stage with destination registers in the **MEM** and **WB** stages.
* [ ] **Implement the Hazard Detection Unit:** Write logic to detect "Load-Use" dependencies (where you must stall because a load hasn't finished yet).
* [ ] **Integrate the "Top" Module:** Wire all your sub-modules together in `riscv_core.sv`.

---

### Phase 4: Validation

* [ ] **Create a "Top-Level" Testbench:** Instantiate your core and a simple dual-port RAM (one port for Instructions, one for Data).
* [ ] **Write a "Hello World" Assembly Snippet:** Write 4-5 instructions (e.g., `ADDI`, `SW`, `LW`, `ADD`) in assembly, hex-encode them, and load them into your Instruction RAM to see if they flow through the stages correctly.

