### **Final Project: Processor Pipeline (RISC-V)**

**Assignment Overview**

* Implement the RISC-V processor pipeline.


* Implement a Debug Unit that allows sending and receiving information to the processor via the UART protocol.


* Create an interface to visualize the data and interact with the Debug Unit (CLI, GUI, and/or TUI).



---

### **Theoretical Framework**

**Pipeline Stages**

* 
**IF (Instruction Fetch):** Searching for the instruction in program memory.


* 
**ID (Instruction Decode):** Decoding the instruction and reading registers.


* 
**EX (Execute):** Execution of the instruction itself.


* 
**MEM (Memory Access):** Reading or writing from/to data memory.


* 
**WB (Write back):** Writing results into the registers.



**Hazards (Risks)**

* 
**Structural:** Occur when two instructions try to use the same resource in the same cycle.


* 
**Data:** An attempt is made to use data before it is ready, requiring strict maintenance of read and write order.


* 
**Control:** Attempting to make a decision on a condition not yet evaluated.



---

### **Instruction Sets to Implement**

The instruction fields generally consist of `opcode`, `rd` (destination), `funct3`, `rs1` (source 1), `rs2` (source 2), and `funct7` .

**Instruction Types & Specific Instructions**

* 
**R-type (Register to Register):** Arithmetic and logical operations.


* Instructions: `add`, `sub`, `sll`, `srl`, `sra`, `and`, `or`, `xor`, `slt`, `sltu`.




* 
**I-Type (Immediate/Load):** Immediate operations and loads.


* Instructions: `lb`, `lh`, `lw`, `lbu`, `lhu`.


* 
*Note: The text also lists the following under the B-Type section, though standard RISC-V classifies them as I-Type:* `addi`, `andi`, `ori`, `xori`, `slti`, `sltiu`, `slli`, `srli`, `srai`, `jalr`.




* 
**S-Type (Store):** Store operations.


* Instructions: `sb`, `sh`, `sw`.




* 
**J-Type (Unconditional Jump):** Jump operations where the address is stored in register `rd`.


* Instruction: `jal`.




* 
**B-Type (Conditional Branch):** Jump if a determined condition is met.


* Instructions: `beq`, `bne`.




* 
**U-Type (Upper Immediate):** Characterized by using a 20-bit immediate to load the most significant (upper) part of a value or address.


* Instruction: `lui` (load upper immediate).





---

### **System Requirements**

**General Requirements**

* The processor must be capable of being programmed and reprogrammed via UART commands.


* The clock must not be intervened with in any part of the project.


* Document your decisions and the reasoning behind elements that require ingenuity.


* Be creative when displaying data and interacting with it (GUI, TUI, CLI).



**Debug Unit**
The following must be sent to the PC via UART:

* The content of the 32 registers.


* The content of the intermediate latches.


* The content of the used data memory.



**Program Loading**

* 
**The Program:** Must be written in assembly and have a mechanism to translate instructions to machine language to be sent to the processor . It must include a HALT or stop instruction.


* 
**The System:** Must allow programming the processor by writing to program memory via software. It must allow dynamic reprogramming.


* 
**Important:** Program loading must occur via UART communication without resynthesizing the processor.



**Questions to Answer regarding Loading:**

* Is it necessary to empty the memory?.


* What about the registers?.


* Is it necessary to empty the pipeline?.


* And the program memory?.



---

### **Modes of Operation**

The system must support two modes:

1. 
**Continuous:** A command is sent to the FPGA via UART, and it initiates program execution until the end. Upon reaching that point, all indicated values are shown on the screen.


2. 
**Step-by-Step:** By sending a command via UART, one clock cycle is executed. The indicated values must be shown at each step.



**Conditions:**

* In both cases, the pipeline must be empty at the moment execution finishes.


* 
**Question to Answer:** What happens if there is no stop instruction in my memory?.



---

### **Clock & Optimization**

Upon integration, you must address the following:

* What is the critical path of my system?.


* Does this critical path generate Skew in my system, and what are the consequences?.


* If Skew is found:
* Find the optimal operating frequency for the system.


* Generate performance metrics using Vivado tools.


* Apply the operating frequency to the system.





---

### **Tips**

1. Do not copy; be inspired.


2. Investigate tools provided by Vivado (IP Cores for memories, Clock Wizard).


3. Before writing the first line:
* Design, draw, and scheme.


* Imagine the modules and how they interact.


* Think about how to test them.


* Consider existing tools you can utilize.




4. Consider how you will interact with the system and interpret its current state during use.


5. Everything asked of you has been implemented 1000 times; ensure yours is unique.


6. Enjoy it.
