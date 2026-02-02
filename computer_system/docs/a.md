Understood. By restoring `PC+4` to the Writeback dump and maintaining strict 32-bit word alignment for every section, the total dump size becomes **76 Bytes**.

Here are the updated specification sections.

### 9.4. Pipeline State Serialization

Pipeline registers are packed into fixed-width byte structures within the Dump Unit. To ensure optimal software parsing speed and 32-bit alignment, all payloads are padded to full 32-bit word boundaries.

* **Hazard Flags (4 Bytes):**
* **Byte 0:** `[4]ID_Flush`, `[3]IF_Flush`, `[2]EX_Stall`, `[1]ID_Stall`, `[0]PC_Stall`.
* **Byte 1:** `[3:2]Forward_A_Optn`, `[1:0]Forward_B_Optn`.
* **Bytes 2-3:** Padding (`0x0000`).


* **IF/ID (12 Bytes):**
* Includes `PC` (4B), `Instruction` (4B), and `PC+4` (4B).


* **ID/EX (28 Bytes):**
* Includes `Control_Bus` (2B + 2B Pad), `PC` (4B), `PC+4` (4B), `RS1_Data` (4B), `RS2_Data` (4B), `Immediate` (4B), and `Metadata` (4B).


* **EX/MEM (16 Bytes):**
* Includes `Control_Bus` & `Metadata` (2B + 2B Pad), `ALU_Result` (4B), `RS2_Data` (4B), and `PC+4` (4B).


* **MEM/WB (16 Bytes):**
* Includes `Control_Bus` & `Metadata` (2B + 2B Pad), `ALU_Result` (4B), `Mem_Read_Data` (4B), and `PC+4` (4B).



### 10.5.3. Pipeline Dump (Fixed 76 Bytes)

The following table defines the exact bit-to-byte mapping for the UART serialization stream. All fields are Little-Endian. Every major section starts on a 4-byte boundary.

| Section | Offset | Size | Fields Included (Word-Aligned Mapping) |
| --- | --- | --- | --- |
| **Hazard** | **0x00** | **4 Bytes** | **Byte 0:** Status Flags<br>

<br>**Byte 1:** Forwarding Ops<br>

<br>**Bytes 2-3:** Padding (`0x0000`) |
| **IF/ID** | **0x04** | **12 Bytes** | `PC` (4B), `Inst` (4B), `PC+4` (4B) |
| **ID/EX** | **0x10** | **28 Bytes** | `Ctrl` (2B+Pad), `PC` (4B), `PC+4` (4B), `RS1` (4B), `RS2` (4B), `Imm` (4B), `Meta` (4B) |
| **EX/MEM** | **0x2C** | **16 Bytes** | `Ctrl_Meta` (2B+Pad), `ALU_Res` (4B), `RS2_Data` (4B), `PC+4` (4B) |
| **MEM/WB** | **0x3C** | **16 Bytes** | `Ctrl_Meta` (2B+Pad), `ALU_Res` (4B), `Mem_Data` (4B), `PC+4` (4B) |

**Total Dump Size:** **76 Bytes** (0x00 to 0x4B).

---

I am ready to implement **`src/dumping_unit.sv`** using this 76-byte aligned structure. Shall I proceed?
