from __future__ import annotations
from backend.instructions import BaseInstruction, InstructionFactory
from dataclasses import dataclass
from typing import List, Tuple, Iterable
import struct
from enum import Enum

WORD_SIZE_BYTES = 4 # 32 bits


def extract_bits(word: int, shift: int, width: int) -> int:
    """Return `width` bits from `word`, starting at `shift`."""
    if width <= 0 or width > 32:
        raise ValueError("width must be between 1 and 32")
    mask = (1 << width) - 1
    return (word >> shift) & mask

class Flag:
    def __init__(self, name: str, value:  bool):
        self.name = name
        self.value = value

    def __str__(self):
        return f"{self.name}: YES" if self.value else f"{self.name}: NO"


class ProgramCounter:
    def __init__(self, value: int):
        self.value = value

    def __str__(self):
        return f"Inst. N°:{self.value//4} (0x{self.value:08X})"


class RegisterFileEntry:
    def __init__(self, reg_addr: int, value: int):
        self.reg_addr = reg_addr
        self.value = value

    def __str__(self):
        return f"x{self.reg_addr}: 0x{self.value:08X}"
    
class RegisterFile:
    def __init__(self, entries: Iterable[RegisterFileEntry]):
        self.entries = list(entries)

    def __str__(self):
        return "\n".join(str(entry) for entry in self.entries)
    

class MemoryDumpMode(Enum):
    RANGE_BASED = 0
    SNOOP_BASED = 1

    def __str__(self):
        if self == MemoryDumpMode.RANGE_BASED:
            return "Range-Based: Memory was scanned using Memory Range from the Memory Range Tracker"
        elif self == MemoryDumpMode.SNOOP_BASED:
            return "Snoop-Based: Memory was scanned as single diff from the last Memory Dump"
        else:
            return "UNKNOWN"

from enum import Enum

class MemoryWriteMask(Enum):
    # No activity
    NONE       = 0x0  # 0000
    
    # Byte Writes
    BYTE_0     = 0x1  # 0001
    BYTE_1     = 0x2  # 0010
    BYTE_2     = 0x4  # 0100
    BYTE_3     = 0x8  # 1000
    
    # Halfword Writes
    HALF_LOWER = 0x3  # 0011 (Bytes 0 and 1)
    HALF_UPPER = 0xC  # 1100 (Bytes 2 and 3)
    
    # Word Write
    WORD       = 0xF  # 1111 (All bytes)

    def __str__(self):
        mapping = {
            MemoryWriteMask.NONE:       "No Write",
            MemoryWriteMask.BYTE_0:     "Byte 0 Write (lsb)",
            MemoryWriteMask.BYTE_1:     "Byte 1 Write",
            MemoryWriteMask.BYTE_2:     "Byte 2 Write",
            MemoryWriteMask.BYTE_3:     "Byte 3 Write (msb)",
            MemoryWriteMask.HALF_LOWER: "Lower Halfword Write",
            MemoryWriteMask.HALF_UPPER: "Upper Halfword Write",
            MemoryWriteMask.WORD:       "Word Write"
        }
        return mapping.get(self, f"INVALID MASK ({bin(self.value)})")

class RSn_Source(Enum):
    REG_FILE_AT_ID = 0
    RD_DATA_AT_EX = 1
    RD_DATA_AT_MEM = 2
    RD_DATA_AT_WB = 3

    def __str__(self):  
        if self == RSn_Source.REG_FILE_AT_ID:
            return "Reg File @ ID out"
        elif self == RSn_Source.RD_DATA_AT_EX:
            return "Rd Data @ EX out"
        elif self == RSn_Source.RD_DATA_AT_MEM:
            return "Rd Data @ MEM out"
        elif self == RSn_Source.RD_DATA_AT_WB:
            return "Rd Data @ WB out"
        else:
            return "UNKNOWN"

class Alu_Src_Optn(Enum):
    REG2_AT_ID = 0
    IMM_AT_ID = 1

    def __str__(self):
        if self == Alu_Src_Optn.REG2_AT_ID:
            return "Reg2 @ ID"
        elif self == Alu_Src_Optn.IMM_AT_ID:
            return "Imm @ ID"
        else:
            return "UNKNOWN"

class AluIntent(Enum):
    ADD_NEEDED = 0
    SUB_NEEDED = 1
    DEPENDS_ON_REG_TYPE = 2
    DEPENDS_ON_IMM_TYPE = 3

    def __str__(self):
        if self == AluIntent.ADD_NEEDED:
            return "Add Needed"
        elif self == AluIntent.SUB_NEEDED:
            return "Sub Needed"
        elif self == AluIntent.DEPENDS_ON_REG_TYPE:
            return "Depends on Reg Type"
        elif self == AluIntent.DEPENDS_ON_IMM_TYPE:
            return "Depends on Imm Type"
        else:
            return "UNKNOWN"

class AluOpCode(Enum):
    OP_ADD = int("0x00",16)
    OP_SUB = int("0x08",16)
    OP_SLL = int("0x01",16)
    OP_SLT = int("0x02",16)
    OP_SLTU = int("0x03",16)
    OP_XOR = int("0x04",16)
    OP_SRL = int("0x06",16)
    OP_SRA = int("0x07",16)
    OP_OR  = int("0x06",16)
    OP_AND = int("0x07",16)
    OP_DBG = int("0x0F",16)

    def __str__(self):
        mapping = {
            AluOpCode.OP_ADD: "ADD",
            AluOpCode.OP_SUB: "SUB",
            AluOpCode.OP_SLL: "SLL",
            AluOpCode.OP_SLT: "SLT",
            AluOpCode.OP_SLTU: "SLTU",
            AluOpCode.OP_XOR: "XOR",
            AluOpCode.OP_SRL: "SRL",
            AluOpCode.OP_SRA: "SRA",
            AluOpCode.OP_OR: "OR",
            AluOpCode.OP_AND: "AND",
        }
        return mapping.get(self, f"INVALID ALU OPCODE ({bin(self.value)})")

class RD_Source(Enum):
    EXECUTION_DATA = 0
    MEMORY_DATA = 1

    def __str__(self):
        if self == RD_Source.EXECUTION_DATA:
            return "RD has Execution Data"
        elif self == RD_Source.MEMORY_DATA:
            return "RD has Memory Data"
        else:
            return "UNKNOWN"


class InUseRegisterType(Enum):
    RS1 = 0
    RS2 = 1
    RD = 2

    def __str__(self):
        if self == InUseRegisterType.RS1:
            return "RS1"
        elif self == InUseRegisterType.RS2:
            return "RS2"
        elif self == InUseRegisterType.RD:
            return "RD"
        else:
            return "UNKNOWN"
        
@dataclass(frozen=True)
class InUseRegisterAddress:
    type: InUseRegisterType
    reg_addr: int  # 0..31

    def __str__(self):
        return f"{self.type}: 0x{self.reg_addr}"
    



# Hazard status for the whole system
@dataclass(frozen=True)
class HazardStatus:

    pc_write_en: Flag
    if_id_write_en: Flag
    control_hazard: Flag
    load_use_hazard: Flag
    rs1_data_source: RSn_Source
    rs2_data_source: RSn_Source
    program_ended: Flag

    @staticmethod
    def unpack(word: int) -> "HazardStatus":
        return HazardStatus(
            pc_write_en=Flag("PC Write Enable",extract_bits(word, 11, 1)),
            if_id_write_en=Flag("IF/ID Write Enable",extract_bits(word, 10, 1)),
            control_hazard=Flag("Control Hazard",extract_bits(word, 9, 1)),
            load_use_hazard=Flag("Load Use Hazard",extract_bits(word, 8, 1)),
            rs2_data_source=RSn_Source(extract_bits(word, 6, 2)),
            rs1_data_source=RSn_Source(extract_bits(word, 4, 2)),
            program_ended=Flag("Program Ended",extract_bits(word, 0, 1)),
        )

    def to_list(self) -> List[int]:
        return [
            self.pc_write_en,
            self.if_id_write_en,
            self.control_hazard,
            self.load_use_hazard,
            self.rs1_data_source.value,
            self.rs2_data_source.value,
            self.program_ended,
        ]
    
    def __str__(self):
        return (f"{self.pc_write_en}\n"
                f"{self.if_id_write_en}\n"
                f"{self.control_hazard}\n"
                f"{self.load_use_hazard}\n"
                f"RS1 Data Source: {self.rs1_data_source}\n"
                f"RS2 Data Source: {self.rs2_data_source}\n"
                f"{self.program_ended}")

@dataclass(frozen=True)
class IF_ID_Status:
    incremented_program_counter_if: ProgramCounter
    instruction_if: BaseInstruction
    program_counter_if: ProgramCounter

    @staticmethod
    def unpack(words: List[int]) -> "IF_ID_Status":
        return IF_ID_Status(
            program_counter_if=ProgramCounter(words[0]),         
            instruction_if=InstructionFactory.decode(words[1]),    
            incremented_program_counter_if=ProgramCounter(words[2])
        )

    def to_list(self) -> List[int]:
        return [
            self.incremented_program_counter_if.value,
            self.instruction_if,
            self.program_counter_if.value,
        ]

    def __str__(self):
        return (f"PC @ IF: {self.program_counter_if}\n"
                f"Instruction @ IF: {self.instruction_if}\n"
                f"Incremented PC @ IF: {self.incremented_program_counter_if}")

@dataclass(frozen=True)
class ID_EX_Status:
    reg_write_id: Flag
    mem_write_id: Flag
    mem_read_id: Flag
    alu_src_optn_id: Alu_Src_Optn
    alu_intent_id: AluIntent
    rd_src_id: RD_Source
    is_branch_id: Flag
    is_jal_id: Flag
    is_jalr_id: Flag
    is_halt_id: Flag

    pc_id: ProgramCounter
    rs1_data_id: int
    rs2_data_id: int
    imm_id: int

    rs1_id: InUseRegisterAddress
    rs2_id: InUseRegisterAddress
    rd_id:  InUseRegisterAddress

    funct3_id: int
    funct7_id: int

    @staticmethod
    def unpack(words: List[int]) -> "ID_EX_Status":
        control_word = words[0]
        metadata_word = words[5]
        return ID_EX_Status(
            is_halt_id=Flag("is_halt @ ID", extract_bits(control_word, 0, 1)),
            is_jalr_id=Flag("is_jalr @ ID", extract_bits(control_word, 1, 1)),
            is_jal_id=Flag("is_jal @ ID", extract_bits(control_word, 2, 1)),
            is_branch_id=Flag("is_branch @ ID", extract_bits(control_word, 3, 1)),
            rd_src_id=RD_Source(extract_bits(control_word, 4, 1)),
            alu_intent_id=AluIntent(extract_bits(control_word, 5, 2)),
            alu_src_optn_id=Alu_Src_Optn(extract_bits(control_word, 7, 1)),
            mem_read_id=Flag("mem_read @ ID", extract_bits(control_word, 8, 1)),
            mem_write_id=Flag("mem_write @ ID", extract_bits(control_word, 9, 1)),
            reg_write_id=Flag("reg_write @ ID", extract_bits(control_word, 10, 1)),
            pc_id=ProgramCounter(words[1]),
            rs1_data_id=words[2],
            rs2_data_id=words[3],
            imm_id=words[4],
            funct7_id=extract_bits(metadata_word, 0, 7),
            funct3_id=extract_bits(metadata_word, 7, 3),
            rd_id=InUseRegisterAddress(reg_addr=extract_bits(metadata_word, 10, 5), type=InUseRegisterType.RD),
            rs2_id=InUseRegisterAddress(reg_addr=extract_bits(metadata_word, 15, 5), type=InUseRegisterType.RS2),
            rs1_id=InUseRegisterAddress(reg_addr=extract_bits(metadata_word, 20, 5), type=InUseRegisterType.RS1)
        )

    def __str__(self):
        return (f"PC @ ID: {self.pc_id}\n"
                f"RS1 Data @ ID: 0x{self.rs1_data_id:08X}\n"
                f"RS2 Data @ ID: 0x{self.rs2_data_id:08X}\n"
                f"IMM @ ID: 0x{self.imm_id:08X}\n"
                f"RS1 Addr @ ID: {self.rs1_id}\n"
                f"RS2 Addr @ ID: {self.rs2_id}\n"
                f"RD Addr @ ID: {self.rd_id}\n"
                f"Funct3 @ ID: 0b{self.funct3_id:03b}\n"
                f"Funct7 @ ID: 0b{self.funct7_id:07b}\n"
                f"is_halt @ ID: {self.is_halt_id}\n"
                f"is_jal @ ID: {self.is_jal_id}\n"
                f"is_jalr @ ID: {self.is_jalr_id}\n"
                f"is_branch @ ID: {self.is_branch_id}\n"
                f"RD Source @ ID: {self.rd_src_id}\n"
                f"ALU Intent @ ID: {self.alu_intent_id}\n"
                f"ALU Src Optn @ ID: {self.alu_src_optn_id}\n"
                f"Mem Read @ ID: {self.mem_read_id}\n"
                f"Mem Write @ ID: {self.mem_write_id}\n"
                f"Reg Write @ ID: {self.reg_write_id}")


@dataclass(frozen=True)
class EX_MEM_Status:
    reg_write_ex: Flag
    mem_write_ex: Flag
    mem_read_ex: Flag
    rd_src_ex: RD_Source
    is_halt_ex: Flag

    alu_result_ex: int
    store_data_ex: int
    pc_ex: ProgramCounter
    rd_ex: InUseRegisterAddress
    funct3_ex: int


    @staticmethod
    def unpack(words: List[int]) -> "EX_MEM_Status":
        control_word = words[0]
        return EX_MEM_Status(
            funct3_ex=extract_bits(control_word, 0, 3),
            rd_ex=InUseRegisterAddress(reg_addr=extract_bits(control_word, 3, 5), type=InUseRegisterType.RD),
            is_halt_ex=Flag("is_halt @ EX",extract_bits(control_word, 8, 1)),
            rd_src_ex=RD_Source(extract_bits(control_word, 9, 1)),
            mem_read_ex=Flag("mem_read @ EX",extract_bits(control_word, 10, 1)),
            mem_write_ex=Flag("mem_write @ EX",extract_bits(control_word, 11, 1)),
            reg_write_ex=Flag("reg_write @ EX",extract_bits(control_word, 12, 1)),
            pc_ex=ProgramCounter(words[1]),
            store_data_ex=words[2],
            alu_result_ex=words[3]
        )
    
    def __str__(self):
        return (f"PC @ EX: {self.pc_ex}\n"
                f"ALU Result @ EX: 0x{self.alu_result_ex:08X}\n"
                f"Store Data @ EX: 0x{self.store_data_ex:08X}\n"
                f"RD Addr @ EX: {self.rd_ex}\n"
                f"Funct3 @ EX: 0b{self.funct3_ex:03b}\n"
                f"is_halt @ EX: {self.is_halt_ex}\n"
                f"RD Source @ EX: {self.rd_src_ex}\n"
                f"Mem Read @ EX: {self.mem_read_ex}\n"
                f"Mem Write @ EX: {self.mem_write_ex}\n"
                f"Reg Write @ EX: {self.reg_write_ex}")

@dataclass(frozen=True)
class MEM_WB_Status:
    reg_write_mem: Flag
    rd_src_mem: RD_Source
    is_halt_mem: Flag

    memory_data_mem: int
    execution_data_mem: int
    pc_mem: ProgramCounter
    rd_mem: InUseRegisterAddress

    @staticmethod
    def unpack(words: List[int]) -> "MEM_WB_Status":
        control_word = words[0]
        return MEM_WB_Status(
            rd_mem=InUseRegisterAddress(reg_addr=extract_bits(control_word, 0, 5), type=InUseRegisterType.RD),
            is_halt_mem=Flag("is_halt @ MEM",extract_bits(control_word, 5, 1)),
            rd_src_mem=RD_Source(extract_bits(control_word, 6, 1)),
            reg_write_mem=Flag("reg_write @ MEM",extract_bits(control_word, 7, 1)),
            pc_mem=ProgramCounter(words[1]),
            execution_data_mem=words[2],
            memory_data_mem=words[3]    
        )
    
    def __str__(self):
        return (f"PC @ MEM: {self.pc_mem}\n"
                f"Execution Data @ MEM: 0x{self.execution_data_mem:08X}\n"
                f"Memory Data @ MEM: 0x{self.memory_data_mem:08X}\n"
                f"RD Addr @ MEM: {self.rd_mem}\n"
                f"is_halt @ MEM: {self.is_halt_mem}\n"
                f"RD Source @ MEM: {self.rd_src_mem}\n"
                f"Reg Write @ MEM: {self.reg_write_mem}")

@dataclass(frozen=True)
class AtomicMemTransaction:
    """Single store transaction (diff mode)."""
    occurred: bool
    address: int
    data: int
    type: MemoryWriteMask

    @staticmethod
    def unpack(words: List[int]) -> "AtomicMemTransaction":
        return AtomicMemTransaction(
            occurred=bool(words[0]),
            address=words[1],
            data=words[2],
            type=MemoryWriteMask(words[0])
        )
    def __str__(self):
            if not self.occurred:
                return "No store operation was recorded."
            return f"Store occurred at {self.type} 0x{self.address:08X} with data 0x{self.data:08X}"
    def cmpct_str(self):
        if not self.occurred:
            return "No store"
        return f"{self.type} @ 0x{self.address:08X} <= 0x{self.data:08X}"

@dataclass(frozen=True)
class MemPatch:
    """Range-based memory patch (range mode)."""
    min_address: int
    max_address: int
    memory_contents: List[Tuple[int, int]]  # (address, data) pairs

    @staticmethod
    def unpack(words: List[int]) -> "MemPatch":
        min_addr = words[0]
        max_addr = words[1]
        # Remaining words is the memory contents to patch to the initial state
        contents = [(min_addr + (i-2) * 4, words[i]) for i in range(2, len(words))]
        return MemPatch(
            min_address=min_addr,
            max_address=max_addr,
            memory_contents=contents,
        )
    def __str__(self):

        if self.min_address > self.max_address:
            return "No memory contents were recorded. So nothing to show."
        
        content_str = "\n".join([f"0x{addr:08X}: 0x{data:08X}" for addr, data in self.memory_contents])

        if self.min_address == self.max_address:
            return f"MemPatch only detected a single store:\n{content_str}"

        return f"MemPatch from 0x{self.min_address:08X} to 0x{self.max_address:08X}:\n{content_str}"

@dataclass(frozen=True)       
class PipelineStatus:
    memory_dump_mode: MemoryDumpMode
    register_file: RegisterFile
    hazard_status: HazardStatus
    if_id_status: IF_ID_Status
    id_ex_status: ID_EX_Status
    ex_mem_status: EX_MEM_Status
    mem_wb_status: MEM_WB_Status

    @staticmethod
    def unpack(memory_dump_mode, words: List[int]) -> "PipelineStatus":
        # Check words length
        expected_length = 32 + 1 + 3 + 6 + 4 + 4  # Register file + Hazard + IF/ID + ID/EX + EX/MEM + MEM/WB
        if len(words) != expected_length:
            raise ValueError(f"Expected {expected_length} words, got {len(words)}")
        
        # Unpack Register File
        register_file_entries = []
        for i in range(32):
            reg_addr = i
            value = words[i]
            register_file_entries.append(RegisterFileEntry(reg_addr, value))
        
        detected_register_file = RegisterFile(register_file_entries)
        
        # Reset words index after register file
        words = words[32:]
        
        return PipelineStatus(
            memory_dump_mode=memory_dump_mode,
            register_file= detected_register_file,
            hazard_status=HazardStatus.unpack(words[0]),
            if_id_status=IF_ID_Status.unpack(words[1:4]),
            id_ex_status=ID_EX_Status.unpack(words[4:10]),
            ex_mem_status=EX_MEM_Status.unpack(words[10:14]),
            mem_wb_status=MEM_WB_Status.unpack(words[14:18]),
        )




def unpack_words(data: bytes, word_amount: int, use_little_endian: bool = True) -> List[int]:
    """Unpack N 32-bit words from bytes. Uses little endian as default"""
    if len(data) < word_amount * WORD_SIZE_BYTES:
        raise ValueError(f"Not enough data to unpack the required number of words. Expected at least {word_amount * WORD_SIZE_BYTES} bytes, got {len(data)} bytes.")
    endian_char = "<" if use_little_endian else ">"
    return list(struct.unpack(f"{endian_char}{word_amount}I", data[: word_amount * WORD_SIZE_BYTES]))


# -----------------------------
# Example usage
# -----------------------------


