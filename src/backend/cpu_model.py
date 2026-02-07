from backend.schemes import *
from dataclasses import dataclass, field
from backend.schemes import AtomicMemTransaction
@dataclass
class SimulatedDataMemory:
    # Using a dict for sparse memory: {word_address: 32_bit_int}
    # This avoids initializing massive arrays.
    memory: dict[int, int] = field(default_factory=dict)
    transactions_history: list[AtomicMemTransaction] = field(default_factory=list)

    def store_data(self, transaction: AtomicMemTransaction):
        """
        Stores data using a 4-bit byte mask (strobe).
        Matches the hardware 'dmem_byte_mask_o'.
        """
        if transaction.occurred and transaction.type != MemoryWriteMask.NONE:
            word_addr = transaction.address & 0xFFFFFFFC
            byte_mask = transaction.type.value
            # Get existing word or 0
            current_word = self.memory.get(word_addr, 0)
            
            new_word = current_word
            for i in range(4):
                if (byte_mask >> i) & 1:
                    # Clear the byte
                    mask = ~(0xFF << (8 * i)) & 0xFFFFFFFF
                    # Insert the new byte from the aligned data
                    new_byte = (transaction.data >> (8 * i)) & 0xFF
                    new_word = (new_word & mask) | (new_byte << (8 * i))
            
            self.memory[word_addr] = new_word
            
            self.transactions_history.append({"addr": transaction.address, "mask": byte_mask, "val": transaction.data})

    def load_data(self, address: int) -> int:
        """
        Returns the raw 32-bit word from the word-aligned address.
        """
        word_addr = address & 0xFFFFFFFC
        return self.memory.get(word_addr, 0)
    
    def get_memory_snapshot(self) -> dict[int, int]:
        """
        Returns a snapshot of the current memory state.
        """
        return self.memory.copy()

class CPUModel:
    def __init__(self):
        self.data_memory = SimulatedDataMemory()
       
    def reset(self, initial_memory: dict[int, int]):
        self.data_memory = SimulatedDataMemory()
        for addr, val in initial_memory.items():
            self.data_memory.memory[addr] = val

    def perform_memory_transaction(self, transaction: AtomicMemTransaction):
        self.data_memory.store_data(transaction)  
    
    # Functional model of the CPU
    def pc_reg_inst(self, pipeline_status: PipelineStatus, return_str: bool = False):
        """
        Simulates the Program Counter Register.
        In a static snapshot, the 'output' is the current value stored in the PC state.
        """
        # In this snapshot, the register has already latched. 
        # The output is the value currently held in the IF stage status.
        pc_out = pipeline_status.if_id_status.program_counter_if.value
        
        if return_str:
            return f"PC Output: 0x{pc_out:08X}"
        return pc_out

    def fixed_pc_adder_inst_if(self, pipeline_status: PipelineStatus, return_str: bool = False):
        """
        Simulates the PC + 4 Adder in the IF stage.
        """
        # Input is the current PC from the PC Register
        pc_val = self.pc_reg_inst(pipeline_status)
        
        # Logic: Adder
        pc_plus_4 = (pc_val + 4) & 0xFFFFFFFF # Keep it 32-bit
        
        if return_str:
            return (f"Input (PC): 0x{pc_val:08X}\n"
                    f"Output (PC+4): 0x{pc_plus_4:08X}")
        return pc_plus_4

    def decoder_inst(self, pipeline_status: PipelineStatus, return_str: bool = False):
        """
        Simulates the Instruction Decoder.
        Extracts Opcode, RD, RS1, RS2, Funct3, and Funct7 from the instruction word.
        """
        inst_val = pipeline_status.if_id_status.instruction_if.word
        # Logic: Bit Extraction
        opcode = extract_bits(inst_val, 0, 7)
        rd     = extract_bits(inst_val, 7, 5)
        funct3 = extract_bits(inst_val, 12, 3)
        rs1    = extract_bits(inst_val, 15, 5)
        rs2    = extract_bits(inst_val, 20, 5)
        funct7 = extract_bits(inst_val, 25, 7)
        
        outputs = {
            "opcode": opcode,
            "rd": rd,
            "funct3": funct3,
            "rs1": rs1,
            "rs2": rs2,
            "funct7": funct7
        }
        
        if return_str:
            return (f"Input (Inst): 0x{inst_val:08X}\n"
                    f"Opcode: 0b{opcode:07b}\n"
                    f"RD:     x{rd}\n"
                    f"Funct3: 0b{funct3:03b}\n"
                    f"RS1:    x{rs1}\n"
                    f"RS2:    x{rs2}\n"
                    f"Funct7: 0b{funct7:07b}")
        return outputs

    def imm_gen_inst(self, pipeline_status: PipelineStatus, return_str: bool = False):
        inst_val = pipeline_status.if_id_status.instruction_if.word
        
        opcode = extract_bits(inst_val, 0, 7)
        imm = 0
        fmt = "Unknown"

        # I-Type: Arithmetic, Loads, JALR
        if opcode in [0x13, 0x03, 0x67]:
            fmt = "I-Type"
            imm_11_0 = extract_bits(inst_val, 20, 12)
            # Sign extend 12 bits to 32
            imm = (imm_11_0 ^ 0x800) - 0x800 if (imm_11_0 & 0x800) else imm_11_0

        # S-Type: Stores
        elif opcode == 0x23:
            fmt = "S-Type"
            imm_11_5 = extract_bits(inst_val, 25, 7)
            imm_4_0  = extract_bits(inst_val, 7, 5)
            raw_imm = (imm_11_5 << 5) | imm_4_0
            imm = (raw_imm ^ 0x800) - 0x800 if (raw_imm & 0x800) else raw_imm

        # B-Type: Branches
        elif opcode == 0x63:
            fmt = "B-Type"
            imm_12   = extract_bits(inst_val, 31, 1)
            imm_11   = extract_bits(inst_val, 7, 1)
            imm_10_5 = extract_bits(inst_val, 25, 6)
            imm_4_1  = extract_bits(inst_val, 8, 4)
            raw_imm = (imm_12 << 12) | (imm_11 << 11) | (imm_10_5 << 5) | (imm_4_1 << 1)
            imm = (raw_imm ^ 0x1000) - 0x1000 if (raw_imm & 0x1000) else raw_imm

        # U-Type: LUI, AUIPC
        elif opcode in [0x37, 0x17]:
            fmt = "U-Type"
            imm = (extract_bits(inst_val, 12, 20) << 12) & 0xFFFFFFFF

        # J-Type: JAL
        elif opcode == 0x6F:
            fmt = "J-Type"
            imm_20    = extract_bits(inst_val, 31, 1)
            imm_19_12 = extract_bits(inst_val, 12, 8)
            imm_11    = extract_bits(inst_val, 20, 1)
            imm_10_1  = extract_bits(inst_val, 21, 10)
            raw_imm = (imm_20 << 20) | (imm_19_12 << 12) | (imm_11 << 11) | (imm_10_1 << 1)
            imm = (raw_imm ^ 0x100000) - 0x100000 if (raw_imm & 0x100000) else raw_imm

        if return_str:
            return f"Format: {fmt}\nExt. Immediate: 0x{imm & 0xFFFFFFFF:08X} ({imm})"
        return imm & 0xFFFFFFFF

    def forwarding_unit_inst(self, pipeline_status: PipelineStatus, return_str: bool = False):
        hz = pipeline_status.hazard_status
        
        if return_str:
            return (f"RS1 Mux Select: {hz.rs1_data_source}\n"
                    f"RS2 Mux Select: {hz.rs2_data_source}")
        return hz.rs1_data_source, hz.rs2_data_source

    def control_inst(self,pipeline_status: PipelineStatus, return_str: bool = False):
        # Retrieve opcode from our decoder component
        decoded = self.decoder_inst(pipeline_status)
        opcode = decoded["opcode"]
        
        # force_nop logic comes from the hazard unit (e.g., a Load-Use stall)
        # We check if the hazard status indicates we are forcing a bubble
        force_nop = pipeline_status.hazard_status.load_use_hazard.value

        # Default Safety State (NOP behavior)
        res = {
            "is_halt": False, "is_branch": False, "is_jal": False, "is_jalr": False,
            "mem_write_en": False, "mem_read_en": False, "reg_write_en": False,
            "rd_src_optn": 0, "alu_intent": 0, "alu_src_optn": 0
        }

        if not force_nop:
            if opcode == 0x33: # OP_R_TYPE
                res.update({"reg_write_en": True, "alu_intent": 2, "rd_src_optn": 0, "alu_src_optn": 0})
            elif opcode == 0x13: # OP_I_TYPE
                res.update({"reg_write_en": True, "alu_intent": 3, "rd_src_optn": 0, "alu_src_optn": 1})
            elif opcode == 0x03: # OP_LOAD
                res.update({"reg_write_en": True, "mem_read_en": True, "rd_src_optn": 1, "alu_intent": 0, "alu_src_optn": 1})
            elif opcode == 0x23: # OP_STORE
                res.update({"mem_write_en": True, "alu_intent": 0, "alu_src_optn": 1})
            elif opcode == 0x63: # OP_BRANCH
                res.update({"is_branch": True, "alu_intent": 1, "alu_src_optn": 0})
            elif opcode == 0x6F: # OP_JAL
                res.update({"is_jal": True, "reg_write_en": True})
            elif opcode == 0x67: # OP_JALR
                res.update({"is_jalr": True, "reg_write_en": True, "alu_intent": 0, "alu_src_optn": 1})
            elif opcode == 0x37 or opcode == 0x17: # OP_LUI / OP_AUIPC
                res.update({"reg_write_en": True, "rd_src_optn": 0, "alu_intent": 0, "alu_src_optn": 1})
            elif opcode == 0x73: # OP_SYSTEM
                res.update({"is_halt": True})

        if return_str:
            if force_nop:
                return "FORCED NOP (Pipeline Bubble) - No Control Signals Asserted"
            return "\n".join([f"{k.upper()}: {v}" for k, v in res.items()])
        return res

    def reg_file_inst(self, pipeline_status: PipelineStatus, return_str: bool = False):
        decoded = self.decoder_inst(pipeline_status)
        rs1_addr = decoded["rs1"]
        rs2_addr = decoded["rs2"]
        
        # register_file is a RegisterFile object with .entries
        rf = pipeline_status.register_file.entries
        
        # RISC-V: x0 is always 0
        val1 = rf[rs1_addr].value if rs1_addr != 0 else 0
        val2 = rf[rs2_addr].value if rs2_addr != 0 else 0
        
        if return_str:
            return f"x{rs1_addr} (RS1): 0x{val1:08X}\nx{rs2_addr} (RS2): 0x{val2:08X}"
        return val1, val2

    def rs1_data_selector(self, pipeline_status: PipelineStatus, return_str: bool = False):
        # Get raw value from RegFile
        rf_val1, _ = self.reg_file_inst(pipeline_status)
        
        # Get forwarding selection from Hazard Status
        sel = pipeline_status.hazard_status.rs1_data_source # This is an RSn_Source Enum
        
        # Forwarding Sources
        # 0: REG_FILE_AT_ID
        # 1: RD_DATA_AT_EX  (From rd_data_ex)
        # 2: RD_DATA_AT_MEM (From alu_result_mem or rd_data_mem)
        # 3: RD_DATA_AT_WB  (From final_rd_data_wb)
        
        val = rf_val1 # Default
        if sel == RSn_Source.RD_DATA_AT_EX:
            # Note: We'd need to calculate rd_data_ex if not in status, 
            # but usually available from previous cycle data
            val = pipeline_status.ex_mem_status.alu_result_ex 
        elif sel == RSn_Source.RD_DATA_AT_MEM:
            # In Verilog: mem_forwarding_data = (rd_src_optn_mem) ? rd_data_mem : alu_result_mem;
            ex_mem = pipeline_status.ex_mem_status
            val = ex_mem.alu_result_ex # Simplified for this snapshot context
        elif sel == RSn_Source.RD_DATA_AT_WB:
            # final_rd_data_wb: selects between execution_data_mem and memory_data_mem
            wb = pipeline_status.mem_wb_status
            val = wb.memory_data_mem if wb.rd_src_mem.value == 1 else wb.execution_data_mem

        if return_str:
            return f"RS1 Final Data: 0x{val & 0xFFFFFFFF:08X} (Source: {sel})"
        return val & 0xFFFFFFFF

    def rs2_data_selector(self, pipeline_status: PipelineStatus, return_str: bool = False):
        _, rf_val2 = self.reg_file_inst(pipeline_status)
        sel = pipeline_status.hazard_status.rs2_data_source
        
        val = rf_val2
        if sel == RSn_Source.RD_DATA_AT_EX:
            val = pipeline_status.ex_mem_status.alu_result_ex
        elif sel == RSn_Source.RD_DATA_AT_MEM:
            val = pipeline_status.ex_mem_status.alu_result_ex
        elif sel == RSn_Source.RD_DATA_AT_WB:
            wb = pipeline_status.mem_wb_status
            val = wb.memory_data_mem if wb.rd_src_mem.value == 1 else wb.execution_data_mem

        if return_str:
            return f"RS2 Final Data: 0x{val & 0xFFFFFFFF:08X} (Source: {sel})"
        return val & 0xFFFFFFFF

    def forwarding_unit_inst(self, pipeline_status: PipelineStatus, return_str: bool = False):
        hz = pipeline_status.hazard_status
        
        if return_str:
            return (f"RS1 Mux Select: {hz.rs1_data_source}\n"
                    f"RS2 Mux Select: {hz.rs2_data_source}")
        return hz.rs1_data_source, hz.rs2_data_source

    def comparator(self, pipeline_status: PipelineStatus, return_str: bool = False):
        # Retrieve forwarded data from RS selectors
        rs1_val = self.rs1_data_selector(pipeline_status)
        rs2_val = self.rs2_data_selector(pipeline_status)
        
        # Subtraction logic to find difference
        # result = rs1 - rs2
        diff = (rs1_val - rs2_val) & 0xFFFFFFFF
        zero_id = (diff == 0)
        
        if return_str:
            return (f"RS1: 0x{rs1_val:08X}, RS2: 0x{rs2_val:08X}\n"
                    f"Comparison Result: {'MATCH (Zero=1)' if zero_id else 'MISMATCH (Zero=0)'}")
        return zero_id

    def target_base_selector(self, pipeline_status: PipelineStatus, return_str: bool = False):
        controls = self.control_inst(pipeline_status)
        pc_id = pipeline_status.if_id_status.program_counter_if.value
        rs1_val = self.rs1_data_selector(pipeline_status)
        
        # mux2 target_base_selector
        # .d0_i (pc_id), .d1_i (rs1_data_id), .sel_i (is_jalr_id)
        is_jalr = controls["is_jalr"]
        val = rs1_val if is_jalr else pc_id
        
        if return_str:
            source = "RS1 (JALR)" if is_jalr else "PC (JAL/Branch)"
            return f"Target Base: 0x{val:08X} (Source: {source})"
        return val

    def final_target_adder(self, pipeline_status: PipelineStatus, return_str: bool = False):
        # Inputs from previous components
        imm = self.imm_gen_inst(pipeline_status)
        target_base = self.target_base_selector(pipeline_status)
        
        # Check if we are executing a JALR to apply masking
        controls = self.control_inst(pipeline_status)
        is_jalr = controls["is_jalr"]
        
        # Perform addition
        raw_target_addr_id = (imm + target_base) & 0xFFFFFFFF
        
        # JALR Masking Compliance (RISC-V Requirement: Target LSB must be 0)
        # assign final_target_addr_id = (is_jalr_id) ? (raw_target_addr_id & 32'hFFFFFFFE) : raw_target_addr_id;
        final_target = (raw_target_addr_id & 0xFFFFFFFE) if is_jalr else raw_target_addr_id
        
        if return_str:
            type_str = "JALR (Masked)" if is_jalr else "JAL/Branch (Unmasked)"
            return (f"Base: 0x{target_base:08X} + Imm: 0x{imm:08X}\n"
                    f"Target Type: {type_str}\n"
                    f"Output: 0x{final_target:08X}")
        
        return final_target

    def pc_src_selector(self, pipeline_status: PipelineStatus, return_str: bool = False):

        
        # jump/branch target
        jump_target = self.final_target_adder(pipeline_status)
        
        # Selection signal comes from flow_change (control_hazard)
        flow_change = pipeline_status.hazard_status.control_hazard.value
   
        src = "Target Adder (Jump/Branch Taken)" if flow_change else "PC+4 (Sequential)"
        return f"Selected Next PC: via {src}"
        

    def alu_ctrl_inst(self, pipeline_status: PipelineStatus, return_str: bool = False):
        id_ex = pipeline_status.id_ex_status
        intent = id_ex.alu_intent_id.value
        f3 = id_ex.funct3_id
        f7_bit30 = (id_ex.funct7_id >> 5) & 1 # Bit 30 of instruction is bit 5 of funct7

        # Operation codes matching your localparams
        OP_ADD, OP_SUB, OP_SLL, OP_SLT = 0x0, 0x8, 0x1, 0x2
        OP_SLTU, OP_XOR, OP_SRL, OP_SRA = 0x3, 0x4, 0x5, 0xD
        OP_OR, OP_AND, OP_NOT_USED = 0x6, 0x7, 0xF

        alu_op = OP_ADD # Default safe

        if intent == 0:   # 00: Load/Store
            alu_op = OP_ADD
        elif intent == 1: # 01: Branch
            alu_op = OP_NOT_USED
        else:             # 10 (R-Type) or 11 (I-Type)
            if f3 == 0x0: # ADD/SUB
                # Only R-Type (10) distinguishes SUB via bit 30
                alu_op = OP_SUB if (intent == 2 and f7_bit30) else OP_ADD
            elif f3 == 0x1: alu_op = OP_SLL
            elif f3 == 0x2: alu_op = OP_SLT
            elif f3 == 0x3: alu_op = OP_SLTU
            elif f3 == 0x4: alu_op = OP_XOR
            elif f3 == 0x5: # SRL/SRA
                alu_op = OP_SRA if f7_bit30 else OP_SRL
            elif f3 == 0x6: alu_op = OP_OR
            elif f3 == 0x7: alu_op = OP_AND

        if return_str:
            return f"ALU Operation Code: 0b{alu_op:04b} ({AluOpCode(alu_op).name})"
        return alu_op

    def alu_src_selector(self, pipeline_status: PipelineStatus, return_str: bool = False):
        id_ex = pipeline_status.id_ex_status
        
        # .d0_i (rs2_data_ex), .d1_i (imm_ex), .sel_i (alu_src_optn_ex)
        sel = id_ex.alu_src_optn_id.value
        val = id_ex.imm_id if sel == 1 else id_ex.rs2_data_id
        
        if return_str:
            source = "Immediate" if sel == 1 else "Register (RS2)"
            return f"ALU Operand 2: 0x{val & 0xFFFFFFFF:08X} (Source: {source})"
        return val & 0xFFFFFFFF

    def fixed_pc_adder_inst_ex(self, pipeline_status: PipelineStatus, return_str: bool = False):
        pc_ex = pipeline_status.id_ex_status.pc_id.value
        pc_plus_4 = (pc_ex + 4) & 0xFFFFFFFF
        
        if return_str:
            return f"EX Stage PC+4: 0x{pc_plus_4:08X}"
        return pc_plus_4

    def alu_inst(self, pipeline_status: PipelineStatus, return_str: bool = False):
        op1 = pipeline_status.id_ex_status.rs1_data_id
        op2 = self.alu_src_selector(pipeline_status)
        operation = self.alu_ctrl_inst(pipeline_status)

        # Helper for signed interpretation
        def to_signed(n):
            return n - (1 << 32) if n & (1 << 31) else n

        res = 0
        if   operation == 0x0: res = op1 + op2                             # ADD
        elif operation == 0x8: res = op1 - op2                             # SUB
        elif operation == 0x1: res = op1 << (op2 & 0x1F)                   # SLL
        elif operation == 0x5: res = (op1 & 0xFFFFFFFF) >> (op2 & 0x1F)    # SRL
        elif operation == 0xD: res = to_signed(op1) >> (op2 & 0x1F)        # SRA
        elif operation == 0x2: res = 1 if to_signed(op1) < to_signed(op2) else 0 # SLT
        elif operation == 0x3: res = 1 if (op1 & 0xFFFFFFFF) < (op2 & 0xFFFFFFFF) else 0 # SLTU
        elif operation == 0x4: res = op1 ^ op2                             # XOR
        elif operation == 0x6: res = op1 | op2                             # OR
        elif operation == 0x7: res = op1 & op2                             # AND
        elif operation == 0xF: res = 0xFFFFFFFF                            # NOT_USED/DEBUG

        res &= 0xFFFFFFFF # Ensure 32-bit result

        if return_str:
            return f"ALU Result: 0x{res:08X}"
        return res

    def rd_data_ex_selector(self, pipeline_status: PipelineStatus, return_str: bool = False):
        id_ex = pipeline_status.id_ex_status
        
        alu_res = self.alu_inst(pipeline_status)
        pc_plus_4 = self.fixed_pc_adder_inst_ex(pipeline_status)
        
        # assign rd_data_ex = (is_jal_ex | is_jalr_ex) ? pc_plus_4_ex : alu_result_ex;
        sel = id_ex.is_jal_id.value or id_ex.is_jalr_id.value
        val = pc_plus_4 if sel else alu_res
        
        if return_str:
            source = "PC+4 (Jump Link)" if sel else "ALU Result"
            return f"RD Data @ EX Output: 0x{val:08X} (Source: {source})"
        return val

    def dmem_intf_inst(self, pipeline_status: PipelineStatus, return_str: bool = False):
        ex_mem = pipeline_status.ex_mem_status
        
        f3 = ex_mem.funct3_ex
        addr = ex_mem.alu_result_ex
        addr_lsb = addr & 0x3
        rs2_data = ex_mem.store_data_ex

        is_halt = ex_mem.is_halt_ex.value
        mem_write_en = ex_mem.mem_write_ex.value
        mem_read_en = ex_mem.mem_read_ex.value
        pc = ex_mem.pc_ex.value
        rd = ex_mem.rd_ex

        # --- 1. Store Logic (Outputs to RAM) ---
        byte_mask = 0
        ram_wdata = 0

        if f3 == 0b000:   # SB
            byte_mask = 1 << addr_lsb
            ram_wdata = (rs2_data & 0xFF) << (8 * addr_lsb)
        elif f3 == 0b001: # SH
            byte_mask = 0b0011 if addr_lsb < 2 else 0b1100
            ram_wdata = (rs2_data & 0xFFFF) << (16 * (addr_lsb >> 1))
        elif f3 == 0b010: # SW
            byte_mask = 0b1111
            ram_wdata = rs2_data

        # --- 2. Load Logic (Inputs from Simulated RAM) ---
        raw_ram_data = self.data_memory.load_data(addr)
        
        def sign_ext(val, bits):
            return (val ^ (1 << (bits - 1))) - (1 << (bits - 1)) if (val & (1 << (bits - 1))) else val

        final_read = 0
        if f3 == 0b000: # LB
            byte = (raw_ram_data >> (8 * addr_lsb)) & 0xFF
            final_read = sign_ext(byte, 8)
        elif f3 == 0b001: # LH
            half = (raw_ram_data >> (16 * (addr_lsb >> 1))) & 0xFFFF
            final_read = sign_ext(half, 16)
        elif f3 == 0b010: # LW
            final_read = raw_ram_data
        elif f3 == 0b100: # LBU
            final_read = (raw_ram_data >> (8 * addr_lsb)) & 0xFF
        elif f3 == 0b101: # LHU
            final_read = (raw_ram_data >> (16 * (addr_lsb >> 1))) & 0xFFFF

        if return_str:
            if mem_write_en:
                return (f"Writing address: 0x{addr:08X} (Mask: 0b{MemoryWriteMask(byte_mask).name})\n"
                        f"RAM Write Data: 0x{ram_wdata:08X}")
            if mem_read_en:
                return (f"Reading address: 0x{addr:08X} (Mask: 0b{byte_mask:04b})\n"
                        f"RAM Load Data: 0x{raw_ram_data:08X}\n"
                        f"Final Load:    0x{final_read & 0xFFFFFFFF:08X}")
            else:
                return (f"Memory Access Addr: 0x{addr:08X} (No Read/Write Enabled)")

        
        return byte_mask, ram_wdata, final_read & 0xFFFFFFFF

    def not_displayed(self, pipeline_status: PipelineStatus, return_str: bool = False):

        return (f"This component is not displayed in the CPU Model snapshot.\n Either it's only for debugging purposes or is from the IF stage.")


    def rd_fwd_mem_selector(self, pipeline_status: PipelineStatus, return_str: bool = False):
        mem = pipeline_status.ex_mem_status
        
        # We get the load result from the interface this cycle
        _, _, final_load_result = self.dmem_intf_inst(pipeline_status)
        
        # mux2 rd_src_selector
        # .d0_i (exec_data_wb), .d1_i (read_data_wb), .sel_i (rd_src_optn_wb)
        # Note: rd_src_optn_wb comes from the WB latch
        sel = mem.rd_src_ex.value
        
        # Choice between the latched ALU/Link data and the fresh Load data
        final_val = final_load_result if sel == 1 else mem.alu_result_ex
        
        if return_str:
            source = "Simulated RAM (Load)" if sel == 1 else "Latched Exec Data (ALU/Link)"
            return f"Final MEM Result: 0x{final_val & 0xFFFFFFFF:08X} (Source: {source})"
        return final_val & 0xFFFFFFFF
    
    def rd_src_selector(self, pipeline_status: PipelineStatus, return_str: bool = False):
        wb = pipeline_status.mem_wb_status
        
        # final_rd_data_wb: selects between execution_data_mem and memory_data_mem
        sel = wb.rd_src_mem.value
        val = wb.memory_data_mem if sel == 1 else wb.execution_data_mem
        
        if return_str:
            source = "Simulated RAM (Load)" if sel == 1 else "Latched Exec Data (ALU/Link)"
            return f"Final WB Result to RegFile: 0x{val & 0xFFFFFFFF:08X} (Source: {source})"
        return val & 0xFFFFFFFF

    def if_id_reg_status(self, pipeline_status: PipelineStatus, return_str: bool = False):
        hzrd = pipeline_status.hazard_status    
        st = pipeline_status.if_id_status
        
        # Mapping the IF/ID data layout: {pc_if, instr_if, pc_plus_4_if}
        data = {
            "pc_if": st.program_counter_if.value,
            "instr_if": getattr(st.instruction_if, 'mnemonic', 0),
            "pc_plus_4_if": st.incremented_program_counter_if.value
        }
        flush_string = "\nWILL BE FLUSHED" if hzrd.control_hazard.value else ""
        stall_string = "\nSTALLED (Holding Previous State)" if not hzrd.if_id_write_en.value else ""
        if return_str:
            return (f"--- IF/ID Register Status ---\n"
                    f"PC @ IF:         0x{data['pc_if']:08X}\n"
                    f"Instruction @ IF: {data['instr_if']}\n"
                    f"PC+4 @ IF:       0x{data['pc_plus_4_if']:08X}"
                    f"{flush_string}{stall_string}")
        return data

    def id_ex_reg_status(self, pipeline_status: PipelineStatus, return_str: bool = False):
        st = pipeline_status.id_ex_status
        
        # Layout matches Verilog: {Controls, Data, Metadata}
        data = {
            "controls": {
                "reg_write": st.reg_write_id.value,
                "mem_write": st.mem_write_id.value,
                "mem_read":  st.mem_read_id.value,
                "alu_src":   st.alu_src_optn_id,
                "alu_intent": st.alu_intent_id,
                "rd_src":    st.rd_src_id,
                "is_branch": st.is_branch_id.value,
                "is_jal":    st.is_jal_id.value,
                "is_jalr":   st.is_jalr_id.value,
                "is_halt":   st.is_halt_id.value,
            },
            "data": {
                "pc_id": st.pc_id.value,
                "rs1_data": st.rs1_data_id,
                "rs2_data": st.rs2_data_id,
                "imm_id": st.imm_id,
            },
            "metadata": {
                "rs1_addr": st.rs1_id.reg_addr,
                "rs2_addr": st.rs2_id.reg_addr,
                "rd_addr":  st.rd_id.reg_addr,
                "funct3":   st.funct3_id,
                "funct7":   st.funct7_id,
            }
        }

        if return_str:
            ctrls = ", ".join([f"{k}: {int(v.value if hasattr(v, 'value') else v)}" for k, v in data["controls"].items()])
            return (f"--- ID/EX Register Status ---\n"
                    f"PC @ ID:      0x{data['data']['pc_id']:08X}\n"
                    f"RS1/RS2 Data: 0x{data['data']['rs1_data']:08X} / 0x{data['data']['rs2_data']:08X}\n"
                    f"Immediate:    0x{data['data']['imm_id']:08X}\n"
                    f"Reg Addrs:    RS1:x{data['metadata']['rs1_addr']}, RS2:x{data['metadata']['rs2_addr']}, RD:x{data['metadata']['rd_addr']}\n"
                    f"Controls:     {ctrls}")
        return data

    def ex_mem_reg_status(self, pipeline_status: PipelineStatus, return_str: bool = False):
        st = pipeline_status.ex_mem_status
        
        # Layout: {Controls, Results, Metadata}
        data = {
            "controls": {
                "reg_write": st.reg_write_ex.value,
                "mem_write": st.mem_write_ex.value,
                "mem_read":  st.mem_read_ex.value,
                "rd_src":    st.rd_src_ex.value,
                "is_halt":   st.is_halt_ex.value,
            },
            "results": {
                "alu_result": st.alu_result_ex,
                "store_data": st.store_data_ex,
                "pc_ex":      st.pc_ex.value,
            },
            "metadata": {
                "rd_addr": st.rd_ex.reg_addr,
                "funct3":  st.funct3_ex,
            }
        }
   
        try:
            if return_str:
                return (f"--- EX/MEM Register Status ---\n"
                        f"PC @ EX:          0x{data['results']['pc_ex']:08X}\n"
                        f"ALU Result (Addr): 0x{data['results']['alu_result']:08X}\n"
                        f"Store Data:        0x{data['results']['store_data']:08X}\n"
                        f"RD Target:         x{data['metadata']['rd_addr']}\n"
                        f"Mem Write En:      {data['controls']['mem_write']}\n"
                        f"Mem Read En:       {data['controls']['mem_read']}\n")
        except Exception as e:
            return f"Error generating EX/MEM status string: {e}"
        return data

    def mem_wb_reg_status(self, pipeline_status: PipelineStatus, return_str: bool = False):
        st = pipeline_status.mem_wb_status
        
        # Layout: {Controls, Data, Metadata}
        data = {
            "controls": {
                "reg_write": st.reg_write_mem.value,
                "rd_src":    st.rd_src_mem.value,
                "is_halt":   st.is_halt_mem.value,
            },
            "data": {
                "exec_data": st.execution_data_mem,
                "read_data": st.memory_data_mem,
                "pc_mem":    st.pc_mem.value,
            },
            "metadata": {
                "rd_addr": st.rd_mem.reg_addr,
            }
        }

        if return_str:
            src_str = "Memory" if data["controls"]["rd_src"] == 1 else "Execution"
            return (f"--- MEM/WB Register Status ---\n"
                    f"PC @ MEM:       0x{data['data']['pc_mem']:08X}\n"
                    f"Execution Data: 0x{data['data']['exec_data']:08X}\n"
                    f"Read Data:      0x{data['data']['read_data']:08X}\n"
                    f"RD Target:      x{data['metadata']['rd_addr']}\n"
                    f"Reg Write En:   {data['controls']['reg_write']}\n"
                    f"RD Source Sel:  {src_str}")
        return data

    def hazard_protection_unit(self, pipeline_status: PipelineStatus, return_str: bool = False):
        """
        Simulates the Hazard Protection Unit.
        In this design, it primarily detects Load-Use hazards to trigger stalls.
        """
        # Pull directly from the pre-calculated hazard status
        hazard_flag = pipeline_status.hazard_status.load_use_hazard
        is_stalled = hazard_flag.value

        if return_str:
            status_text = "STALL ACTIVE (Bubble Inserted)" if is_stalled else "NO STALL (Normal Flow)"
            return f"Hazard Protection Unit: {status_text}"
        
        return is_stalled

    def flow_controller_inst(self, pipeline_status: PipelineStatus, return_str: bool = False):
        """
        Simulates the Flow Controller.
        Detects if the PC should jump to a target address instead of PC+4.
        """
        # Pull from the control_hazard flag
        flow_change = pipeline_status.hazard_status.control_hazard
        is_taken = flow_change.value

        if return_str:
            status_text = "FLOW CHANGE (Branch/Jump Taken)" if is_taken else "SEQUENTIAL (PC+4)"
            return f"Flow Control Unit: {status_text}"
        
        return is_taken

    def halt_unit_inst(self, pipeline_status: PipelineStatus, return_str: bool = False):
        """
        Simulates the Halt Unit.
        Detects halt signals to freeze the pipeline at the end of the program.
        """
        # We look at the ID_EX status to see if the decoded instruction is a halt
        is_halt = pipeline_status.id_ex_status.is_halt_id
        halt_active = is_halt.value

        if return_str:
            status_text = "HALT SIGNAL DETECTED" if halt_active else "RUNNING"
            return f"Halt Control Unit: {status_text}"
        
        return halt_active

    def return_component_mapping(self):
        return {
            # --- Stage 1: IF ---
            "g203": {"component": "fixed_pc_adder_inst", "function": self.not_displayed},
            "g1050": {"component": "pc_reg_inst", "function": self.not_displayed},
            "g204": {"component": "instruction_memory", "function": self.not_displayed},
            # --- Stage 2: ID ---
            "g352":  {"component": "instruction_decoder", "function": self.decoder_inst},
            "g397":  {"component": "imm_generator", "function": self.imm_gen_inst},
            "g1056": {"component": "register_file", "function": self.reg_file_inst},
            "g1062": {"component": "control_unit", "function": self.control_inst},
            "g1059": {"component": "forwarding_unit", "function": self.forwarding_unit_inst},
            "g1054": {"component": "hazard_protection_unit", "function": self.hazard_protection_unit},
            "g1052": {"component": "flow_ctrl_unit", "function": self.flow_controller_inst},
            "g1051": {"component": "halt_ctrl_unit", "function": self.halt_unit_inst},
            "g1057": {"component": "rs1_source_selector", "function": self.rs1_data_selector},
            "g1058": {"component": "rs2_source_selector", "function": self.rs2_data_selector},
            "g1060": {"component": "base_target_selector", "function": self.target_base_selector},
            "g1055": {"component": "zero_comparator", "function": self.comparator},
            "imm_add": {"component": "imm_target_adder", "function": self.final_target_adder},
            "g1063": {"component": "pc_source_selector", "function": self.pc_src_selector},

            # --- Stage 3: EX ---
            "g527":  {"component": "alu_controller", "function": self.alu_ctrl_inst},
            "g1067": {"component": "alu_src_selector", "function": self.alu_src_selector},
            "g1066": {"component": "alu", "function": self.alu_inst},
            "g1068": {"component": "rd_data_ex_selector", "function": self.rd_data_ex_selector},

            # --- Stage 4: MEM ---
            "g1070": {"component": "data_memory_n_interface", "function": self.dmem_intf_inst},
            "g1069": {"component": "memory_range_tracker", "function": self.not_displayed},
            "g1071": {"component": "mem_selector_4_fwd", "function": self.rd_fwd_mem_selector},
            # --- Stage 5: WB ---
            "g1072": {"component": "wb_selector_4_wb", "function": self.rd_src_selector},

            # --- Pipeline Registers (State Views) ---
            "g1053": {"component": "if_id_reg", "function": self.if_id_reg_status},
            "g1065": {"component": "id_ex_reg", "function": self.id_ex_reg_status},
            "ex_mem": {"component": "ex_mem_reg", "function": self.ex_mem_reg_status},
            "mem_wb": {"component": "mem_wb_reg", "function": self.mem_wb_reg_status}
        }

    def return_group_string_dict(self, pipeline_status: PipelineStatus) -> dict:
            """
            Generates a dictionary mapping SVG group IDs to formatted tooltip strings.
            """
            mapping = self.return_component_mapping()
            group_to_tooltip = {}

            for group_id, details in mapping.items():
                component_name = details['component']
                component_func = details['function']
                
                # Execute the mapped function with the required parameters
                tooltip_text = component_func( pipeline_status, return_str=True)
                
                # Construct the final display string: "Component Name: Status/Value"
                group_to_tooltip[group_id] = f"{component_name}: {tooltip_text}"

            return group_to_tooltip
cpu_model = CPUModel()
