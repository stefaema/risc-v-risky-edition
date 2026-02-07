from dataclasses import dataclass, field
from typing import Dict, Tuple, Type, Optional

@dataclass
class BaseInstruction:
    """Base class for all RISC-V instructions with disassembly support."""
    word: int
    opcode: int = field(init=False)
    mnemonic: str = "unknown"

    def __post_init__(self):
        self.opcode = self.word & 0b1111111

    def __repr__(self) -> str:
        """Default fallback representation."""
        return f"{self.mnemonic} (raw: {hex(self.word)})"

@dataclass
class RType(BaseInstruction):
    rd: int = field(init=False); funct3: int = field(init=False)
    rs1: int = field(init=False); rs2: int = field(init=False)
    funct7: int = field(init=False)

    def __post_init__(self):
        super().__post_init__()
        self.rd     = (self.word >> 7)  & 0x1F
        self.funct3 = (self.word >> 12) & 0x07
        self.rs1    = (self.word >> 15) & 0x1F
        self.rs2    = (self.word >> 20) & 0x1F
        self.funct7 = (self.word >> 25) & 0x7F

    def __repr__(self) -> str:
        return f"{self.mnemonic:7} x{self.rd}, x{self.rs1}, x{self.rs2}"

@dataclass
class SystemType(BaseInstruction):
    """Refined SystemType to support field-based lookup."""
    funct3: int = field(init=False)
    funct7: int = field(init=False)

    def __post_init__(self):
        super().__post_init__()
        self.funct3 = (self.word >> 12) & 0x07
        self.funct7 = (self.word >> 25) & 0x7F

    def __repr__(self) -> str:
        return f"{self.mnemonic}"

@dataclass
class IType(BaseInstruction):
    rd: int = field(init=False); funct3: int = field(init=False)
    rs1: int = field(init=False); imm: int = field(init=False)

    def __post_init__(self):
        super().__post_init__()
        self.rd     = (self.word >> 7)  & 0x1F
        self.funct3 = (self.word >> 12) & 0x07
        self.rs1    = (self.word >> 15) & 0x1F
        raw_imm     = (self.word >> 20) & 0xFFF
        self.imm    = raw_imm if raw_imm < 0x800 else raw_imm - 0x1000

    def __repr__(self) -> str:
        # Shifts (slli, srli, srai) use only the lower 5 bits of the immediate
        if self.opcode == 0b0010011 and self.funct3 in [0b001, 0b101]:
            shamt = self.word >> 20 & 0x1F
            return f"{self.mnemonic:7} x{self.rd}, x{self.rs1}, {shamt}"
        # Loads
        if self.opcode == 0b0000011:
            return f"{self.mnemonic:7} x{self.rd}, {self.imm}(x{self.rs1})"
        # JALR
        if self.opcode == 0b1100111:
            return f"jalr    x{self.rd}, x{self.rs1}, {self.imm}"
        # Standard arithmetic
        return f"{self.mnemonic:7} x{self.rd}, x{self.rs1}, {self.imm}"

@dataclass
class SType(BaseInstruction):
    funct3: int = field(init=False); rs1: int = field(init=False)
    rs2: int = field(init=False); imm: int = field(init=False)

    def __post_init__(self):
        super().__post_init__()
        self.funct3 = (self.word >> 12) & 0x07
        self.rs1    = (self.word >> 15) & 0x1F
        self.rs2    = (self.word >> 20) & 0x1F
        imm_4_0     = (self.word >> 7)  & 0x1F
        imm_11_5    = (self.word >> 25) & 0x7F
        raw_imm     = (imm_11_5 << 5) | imm_4_0
        self.imm    = raw_imm if raw_imm < 0x800 else raw_imm - 0x1000

    def __repr__(self) -> str:
        return f"{self.mnemonic:7} x{self.rs2}, {self.imm}(x{self.rs1})"

@dataclass
class BType(BaseInstruction):
    funct3: int = field(init=False); rs1: int = field(init=False)
    rs2: int = field(init=False); imm: int = field(init=False)

    def __post_init__(self):
        super().__post_init__()
        self.funct3 = (self.word >> 12) & 0x07
        self.rs1    = (self.word >> 15) & 0x1F
        self.rs2    = (self.word >> 20) & 0x1F
        imm_11      = (self.word >> 7)  & 0x1
        imm_4_1     = (self.word >> 8)  & 0xF
        imm_10_5    = (self.word >> 25) & 0x3F
        imm_12      = (self.word >> 31) & 0x1
        raw_imm     = (imm_12 << 12) | (imm_11 << 11) | (imm_10_5 << 5) | (imm_4_1 << 1)
        self.imm    = raw_imm if raw_imm < 0x1000 else raw_imm - 0x2000

    def __repr__(self) -> str:
        return f"{self.mnemonic:7} x{self.rs1}, x{self.rs2}, {self.imm}"

@dataclass
class UType(BaseInstruction):
    rd: int = field(init=False); imm: int = field(init=False)

    def __post_init__(self):
        super().__post_init__()
        self.rd  = (self.word >> 7) & 0x1F
        self.imm = self.word & 0xFFFFF000

    def __repr__(self) -> str:
        return f"{self.mnemonic:7} x{self.rd}, {hex(self.imm)}"

@dataclass
class JType(BaseInstruction):
    rd: int = field(init=False); imm: int = field(init=False)

    def __post_init__(self):
        super().__post_init__()
        self.rd = (self.word >> 7) & 0x1F
        imm_19_12 = (self.word >> 12) & 0xFF
        imm_11    = (self.word >> 20) & 0x1
        imm_10_1  = (self.word >> 21) & 0x3FF
        imm_20    = (self.word >> 31) & 0x1
        raw_imm = (imm_20 << 20) | (imm_19_12 << 12) | (imm_11 << 11) | (imm_10_1 << 1)
        self.imm = raw_imm if raw_imm < 0x100000 else raw_imm - 0x200000

    def __repr__(self) -> str:
        return f"{self.mnemonic:7} x{self.rd}, {self.imm}"


class InstructionFactory:
    # --- OPCODES (Bits 6:0) ---
    OP_R_TYPE   = 0b0110011  # Arithmetic Register-Register
    OP_I_TYPE   = 0b0010011  # Arithmetic Immediate
    OP_LOAD     = 0b0000011  # Load instructions
    OP_STORE    = 0b0100011  # Store instructions
    OP_BRANCH   = 0b1100011  # Conditional branches
    OP_JALR     = 0b1100111  # Jump and Link Register
    OP_JAL      = 0b1101111  # Jump and Link
    OP_LUI      = 0b0110111  # Load Upper Immediate
    OP_SYSTEM   = 0b1110011  # ECALL / Environment calls

    # Map Opcode -> DTO Class
    FORMAT_MAP: Dict[int, Type[BaseInstruction]] = {
        OP_R_TYPE: RType,
        OP_I_TYPE: IType,
        OP_LOAD:   IType,
        OP_STORE:  SType,
        OP_BRANCH: BType,
        OP_JALR:   IType,
        OP_JAL:    JType,
        OP_LUI:    UType,
        OP_SYSTEM: SystemType,  # Now correctly typed
    }

    # MNEMONIC_MAP: (opcode, funct3, funct7) -> mnemonic
    MNEMONIC_MAP: Dict[Tuple[int, Optional[int], Optional[int]], str] = {
        # --- R-Type ---
        (OP_R_TYPE, 0b000, 0b0000000): "add",
        (OP_R_TYPE, 0b000, 0b0100000): "sub",
        (OP_R_TYPE, 0b001, 0b0000000): "sll",
        (OP_R_TYPE, 0b010, 0b0000000): "slt",
        (OP_R_TYPE, 0b011, 0b0000000): "sltu",
        (OP_R_TYPE, 0b100, 0b0000000): "xor",
        (OP_R_TYPE, 0b101, 0b0000000): "srl",
        (OP_R_TYPE, 0b101, 0b0100000): "sra",
        (OP_R_TYPE, 0b110, 0b0000000): "or",
        (OP_R_TYPE, 0b111, 0b0000000): "and",

        # --- I-Type Arithmetic ---
        (OP_I_TYPE, 0b000, None):      "addi",
        (OP_I_TYPE, 0b010, None):      "slti",
        (OP_I_TYPE, 0b011, None):      "sltiu",
        (OP_I_TYPE, 0b100, None):      "xori",
        (OP_I_TYPE, 0b110, None):      "ori",
        (OP_I_TYPE, 0b111, None):      "andi",
        # Special case: Shifts use funct7 to distinguish logic vs arithmetic
        (OP_I_TYPE, 0b001, 0b0000000): "slli",
        (OP_I_TYPE, 0b101, 0b0000000): "srli",
        (OP_I_TYPE, 0b101, 0b0100000): "srai",

        # --- I-Type Loads & JALR ---
        (OP_LOAD,   0b000, None): "lb",
        (OP_LOAD,   0b001, None): "lh",
        (OP_LOAD,   0b010, None): "lw",
        (OP_LOAD,   0b100, None): "lbu",
        (OP_LOAD,   0b101, None): "lhu",
        (OP_JALR,   0b000, None): "jalr",

        # --- S-Type ---
        (OP_STORE,  0b000, None): "sb",
        (OP_STORE,  0b001, None): "sh",
        (OP_STORE,  0b010, None): "sw",

        # --- B-Type ---
        (OP_BRANCH, 0b000, None): "beq",
        (OP_BRANCH, 0b001, None): "bne",

        # --- U-Type & J-Type ---
        (OP_LUI,    None,  None): "lui",
        (OP_JAL,    None,  None): "jal",

        # --- System ---
        (OP_SYSTEM, 0b000, 0b0000000): "ecall",
    }

    @classmethod
    def decode(cls, word: int) -> BaseInstruction:
        opcode = word & 0b1111111
        
        # 1. Instantiate the correct Format DTO
        dto_class = cls.FORMAT_MAP.get(opcode, BaseInstruction)
        instr = dto_class(word)

        # 2. Extract functional fields
        f3 = getattr(instr, 'funct3', None)
        
        # For R-Type AND I-Type shifts, we need bits [31:25] (funct7)
        # Shift instructions (slli, srli, srai) have opcode 0b0010011
        f7 = None
        if opcode in [cls.OP_R_TYPE, cls.OP_I_TYPE, cls.OP_SYSTEM]:
            f7 = (word >> 25) & 0x7F


        for key in [(opcode, f3, f7), (opcode, f3, None), (opcode, None, None)]:
                    if key in cls.MNEMONIC_MAP:
                        instr.mnemonic = cls.MNEMONIC_MAP[key]
                        break
                
        return instr


if __name__ == "__main__":
    # Test cases: (Raw Word, Expected Mnemonic/Description)
    test_words = [
        # R-Type
        (0x002081B3, "add x3, x1, x2"),
        (0x402081B3, "sub x3, x1, x2"),
        (0x0020C1B3, "xor x3, x1, x2"),
        
        # I-Type (Arithmetic)
        (0x00F00293, "addi x5, x0, 15"),
        (0xFFF00293, "addi x5, x0, -1"),  # Sign-extension test
        (0x4020D293, "srai x5, x1, 2"),   # Shift test
        
        # I-Type (Loads & JALR)
        (0x00452283, "lw x5, 4(x10)"),
        (0xFFF50283, "lb x5, -1(x10)"),
        (0x000500E7, "jalr x1, x10, 0"),
        
        # S-Type
        (0x00552223, "sw x5, 4(x10)"),
        (0xFE552023, "sw x5, -32(x10)"), # Sign-extension test
        
        # B-Type (Conditional Branches)
        (0x00208463, "beq x1, x2, 8"),
        (0xFE208EE3, "beq x1, x2, -4"),  # Scrambled immediate test
        
        # U-Type
        (0x000012B7, "lui x5, 0x1000"),
        
        # J-Type
        (0x00C000EF, "jal x1, 12"),
        (0xFFDFF0EF, "jal x1, -4"),      # Scrambled immediate test
        
        # System
        (0x00000073, "ecall")
    ]

    print(f"{'HEX WORD':<12} | {'ASSEMBLY DISASSEMBLY':<25} | {'TYPE'}")
    print("-" * 55)

    for word, expected in test_words:
        instr = InstructionFactory.decode(word)
        type_name = instr.__class__.__name__
        
        # Use our custom __repr__ for disassembly
        print(f"{hex(word):<12} | {str(instr):<25} | {type_name}")

    # Specific functional validation for a negative immediate
    neg_addi = InstructionFactory.decode(0xFFF00293)
    print(neg_addi)
    print(type(neg_addi))
    assert neg_addi.imm == -1, f"Expected -1, got {neg_addi.imm}"
    
    # Specific functional validation for scrambled B-type
    neg_beq = InstructionFactory.decode(0xFE208EE3)
    assert neg_beq.imm == -4, f"Expected -4, got {neg_beq.imm}"

    print("\n--- All Tests Passed Successfully ---")
