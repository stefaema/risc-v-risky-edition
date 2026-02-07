### 1. The Core Distinction: HDL vs. RTL

This is the most common point of confusion for beginners.

*   **HDL (Hardware Description Language):** This is the **language** itself (e.g., Verilog, VHDL, SystemVerilog). It is a programming syntax used to describe the behavior or structure of digital systems. HDLs can describe things that **cannot** be built in real life (like an infinite loop or a complex mathematical function that has no hardware equivalent).
*   **RTL (Register Transfer Level):** This is the **coding style or abstraction level** within an HDL. It describes how data moves between registers (Flip-Flops) and how that data is transformed by combinational logic. 
    *   *Key rule:* If your HDL code is "RTL-compliant," it means a compiler (synthesis tool) can actually turn it into physical transistors/gates. If it is "Behavioral" but not RTL, it might only work in a simulator.

---

### 2. Design and Architecture Terms

*   **IP Core (Intellectual Property Core):** A reusable unit of logic. Think of it as a "pre-packaged" circuit.
    *   *Example:* Instead of designing a USB controller from scratch, you buy an "IP Core" from a vendor (like Synopsys or ARM) and drop it into your design.
*   **SoC (System on Chip):** An integrated circuit that integrates all components of a computer or other electronic system into a single chip. It usually contains one or more CPUs, memory, and various IP Cores.
*   **Datapath:** The part of the CPU or logic block that performs the actual operations on data (ALUs, multipliers, registers).
*   **Control Path (Control Unit):** The "brain" that tells the Datapath what to do. It generates the enable signals, mux selects, and operation codes based on the current state.
*   **Glue Logic:** Small amounts of custom logic used to connect different larger blocks or IP cores together.

---

### 3. Synthesis and Physical Implementation

*   **Synthesis:** The process of translating high-level RTL code (SystemVerilog) into a **Netlist**.
*   **Netlist:** A text file listing all the specific gates (AND, OR, NOT) and the wires connecting them. This is the output of the Synthesis tool.
*   **SDC (Synopsys Design Constraints):** A file where the engineer defines the clock speeds, input delays, and output delays. It tells the tool: "This circuit must run at 1GHz."
*   **STA (Static Timing Analysis):** A mathematical method used to verify that all logic signals arrive at their destination registers within the allowed time, without needing to run a simulation.
*   **Place and Route (P&R):** The physical design stage where the tool decides exactly where each gate goes on the silicon and how to route the physical copper wires between them.

---

### 4. Hardware Reliability and Timing

*   **Clock Domain Crossing (CDC):** The act of passing a signal from one part of a chip running at frequency $A$ to another part running at frequency $B$. Doing this incorrectly causes system crashes.
*   **Metastability:** A physical phenomenon where a digital signal gets stuck in an unstable state between '0' and '1'. This usually happens during a CDC if proper synchronizers aren't used.
*   **Setup Time:** The minimum amount of time a data signal must be stable **before** the clock edge.
*   **Hold Time:** The minimum amount of time a data signal must remain stable **after** the clock edge.
*   **Timing Violation:** A failure where the signal is too slow (Setup) or too fast (Hold) for the clock, leading to corrupted data.

---

### 5. Verification Terms

*   **DUT / UUT (Device Under Test / Unit Under Test):** The specific RTL module you are currently testing in your simulation.
*   **Testbench:** A non-synthesizable piece of code used to wrap the DUT, provide input "stimulus," and check if the outputs are correct.
*   **Assertion:** A check embedded in the code that monitors for illegal conditions. 
    *   *Example:* An assertion that triggers an error if two different devices try to write to the same bus at the same time.
*   **Coverage:** A metric that tells you what percentage of your code or logic states have been exercised by your tests. 100% coverage is the goal before "Tape-out."
*   **Tape-out:** The final result of the design process. It is the moment you send the final design files to the foundry (like TSMC or Intel) to actually manufacture the silicon chip.
