Based on the `dumping_unit.sv` (the serializer) and `riscv_core.sv` (the source packer), here is the exact structure of the data stream.

**Protocol Note:** The data is sent **Little Endian**.

1. **Bit 0** of a 32-bit Word is the **Least Significant Bit**.
2. Over UART, **Bits [7:0]** (Byte 0) arrive first, followed by [15:8], etc.

---

### **1. Global Packet Structure**

| Sequence | Size | Description |
| --- | --- | --- |
| **Header** | 2 Bytes | `0xDA` (Alert) + `Mode` (0=Step, 1=Cont) |
| **Registers** | 128 Bytes | 32 x 32-bit Integers (x0 to x31) |
| **Pipeline** | **76 Bytes** | **19 x 32-bit Words** (Detailed below) |
| **Memory** | Variable | Config words + Data payload |

---

### **2. Pipeline Dump Structure (19 Words)**

This section is strictly **19 words (0 to 18)**. All words are 32-bit.

#### **Word 0: Hazard Status**

*Source: `pipe_dump_words[0] = {16'h0000, hazard_status_i}*`

| Bit Range | Field Name | Description |
| --- | --- | --- |
| **[31:16]** | *Padding* | Always `0x0000` |
| **[15:10]** | *Padding* | From core `tap_hazard_o` padding |
| **[9]** | `PC_Write_En` | Is PC updating? |
| **[8]** | `IF/ID_Write_En` | Is IF/ID updating? |
| **[7]** | `Control_Hazard` | Branch/Jump Flush? |
| **[6]** | `Load_Use` | Stall for Load? |
| **[5]** | `Fwd_RS2` | Forwarding on RS2? |
| **[4]** | `Fwd_RS1` | Forwarding on RS1? |
| **[3:1]** | *Padding* | Unused |
| **[0]** | `Prog_End` | Halt reached WB stage? |

---

#### **Words 1-3: IF/ID Stage**

| Word Idx | Content |
| --- | --- |
| **Word 1** | **PC** (Fetch Address) |
| **Word 2** | **Instruction** (Raw Hex) |
| **Word 3** | **PC + 4** |

---

#### **Words 4-10: ID/EX Stage**

**Word 4: ID/EX Control**
*Source: `pipe_dump_words[4] = {16'h0000, 5'b0, id_ex_ctrl}*`
*Packing Order in Core: `{RegW, MemW, MemR, AluSrc, AluIntent(2), RdSrc, Br, Jal, Jalr, Halt}*`

| Bit Range | Field Name |
| --- | --- |
| **[31:11]** | *Padding* (Zeros) |
| **[10]** | `Reg_Write` |
| **[9]** | `Mem_Write` |
| **[8]** | `Mem_Read` |
| **[7]** | `ALU_Src_Optn` (0=Reg, 1=Imm) |
| **[6:5]** | `ALU_Intent` (2 bits) |
| **[4]** | `Rd_Src_Optn` (0=ALU, 1=PC+4) |
| **[3]** | `Is_Branch` |
| **[2]** | `Is_Jal` |
| **[1]** | `Is_Jalr` |
| **[0]** | `Is_Halt` |

**Words 5-9: ID/EX Data**
| Word Idx | Content |
| :--- | :--- |
| **Word 5** | **PC** (Decode) |
| **Word 6** | **PC + 4** (Reconstructed by Dumper) |
| **Word 7** | **RS1 Data** |
| **Word 8** | **RS2 Data** |
| **Word 9** | **Immediate** (Sign Extended) |

**Word 10: ID/EX Metadata**
*Source: `pipe_dump_words[10] = {7'b0, id_ex_meta}*`
*Packing Order in Core: `{rs1, rs2, rd, funct3, funct7}*`

| Bit Range | Field Name |
| --- | --- |
| **[31:25]** | *Padding* |
| **[24:20]** | `RS1_Addr` (5 bits) |
| **[19:15]** | `RS2_Addr` (5 bits) |
| **[14:10]** | `RD_Addr` (5 bits) |
| **[9:7]** | `Funct3` (3 bits) |
| **[6:0]** | `Funct7` (7 bits) |

---

#### **Words 11-14: EX/MEM Stage**

**Word 11: EX/MEM Control & Meta**
*Source: `pipe_dump_words[11] = {16'h0000, 3'b0, ex_mem_ctrl, ex_mem_meta}*`
*Core Control (5 bits): `{RegW, MemW, MemR, RdSrc, Halt}*`
*Core Meta (8 bits): `{RdAddr, Funct3}*`

| Bit Range | Field Name |
| --- | --- |
| **[31:13]** | *Padding* |
| **[12]** | `Reg_Write` |
| **[11]** | `Mem_Write` |
| **[10]** | `Mem_Read` |
| **[9]** | `Rd_Src_Optn` |
| **[8]** | `Is_Halt` |
| **[7:3]** | `RD_Addr` (5 bits) |
| **[2:0]** | `Funct3` (3 bits) |

**Words 12-14: EX/MEM Data**
| Word Idx | Content |
| :--- | :--- |
| **Word 12** | **ALU Result** |
| **Word 13** | **Store Data** (Value of RS2) |
| **Word 14** | **PC + 4** (Reconstructed by Dumper) |

---

#### **Words 15-18: MEM/WB Stage**

**Word 15: MEM/WB Control & Meta**
*Source: `pipe_dump_words[15] = {16'h0000, 8'b0, mem_wb_ctrl, mem_wb_meta}*`
*Core Control (3 bits): `{RegW, RdSrc, Halt}*`
*Core Meta (5 bits): `{RdAddr}*`

| Bit Range | Field Name |
| --- | --- |
| **[31:8]** | *Padding* |
| **[7]** | `Reg_Write` |
| **[6]** | `Rd_Src_Optn` |
| **[5]** | `Is_Halt` |
| **[4:0]** | `RD_Addr` (5 bits) |

**Words 16-18: MEM/WB Data**
| Word Idx | Content |
| :--- | :--- |
| **Word 16** | **ALU Result** (Passed through) |
| **Word 17** | **Read Data** (From RAM) |
| **Word 18** | **PC + 4** (Reconstructed by Dumper) |
