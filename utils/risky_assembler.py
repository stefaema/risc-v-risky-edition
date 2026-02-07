import sys
import struct
import re
import argparse

# ==============================================================================
# 1. DEBUG LOGGING UTILITY
# ==============================================================================
class Log:
    """Quick boilerplate for clean console debugging."""
    HEADER = '\033[95m'
    BLUE = '\033[94m'
    GREEN = '\033[92m'
    YELLOW = '\033[93m'
    RED = '\033[91m'
    END = '\033[0m'
    BOLD = '\033[1m'

    @staticmethod
    def step(pc, msg):
        print(f"{Log.BLUE}[PC 0x{pc:03X}]{Log.END} {msg}")

    @staticmethod
    def macro(old, new_list):
        print(f"  {Log.YELLOW}↳ Macro Expansion:{Log.END} '{old}' becomes:")
        for n in new_list:
            print(f"    {Log.BOLD}→ {n}{Log.END}")

    @staticmethod
    def encode(val):
        le_bytes = " ".join(f"{b:02x}" for b in struct.pack('<I', val))
        print(f"  {Log.GREEN}✓ Encoded:{Log.END} 0x{val:08x} | Bytes: [{le_bytes}]")

# ==============================================================================
# 2. ARCHITECTURE DEFINITIONS
# ==============================================================================

REGISTERS = {
    'zero': 0, 'ra': 1, 'sp': 2, 'gp': 3, 'tp': 4, 't0': 5, 't1': 6, 't2': 7,
    's0': 8, 'fp': 8, 's1': 9, 'a0': 10, 'a1': 11, 'a2': 12, 'a3': 13, 'a4': 14,
    'a5': 15, 'a6': 16, 'a7': 17, 's2': 18, 's3': 19, 's4': 20, 's5': 21,
    's6': 22, 's7': 23, 's8': 24, 's9': 25, 's10': 26, 's11': 27, 't3': 28,
    't4': 29, 't5': 30, 't6': 31
}
for i in range(32): REGISTERS[f'x{i}'] = i

ASM_TEMP_REG = 't6'

INSTRUCTIONS = {
    'add':  {'type': 'R', 'opcode': 0x33, 'funct3': 0x0, 'funct7': 0x00},
    'sub':  {'type': 'R', 'opcode': 0x33, 'funct3': 0x0, 'funct7': 0x20},
    'sll':  {'type': 'R', 'opcode': 0x33, 'funct3': 0x1, 'funct7': 0x00},
    'slt':  {'type': 'R', 'opcode': 0x33, 'funct3': 0x2, 'funct7': 0x00},
    'sltu': {'type': 'R', 'opcode': 0x33, 'funct3': 0x3, 'funct7': 0x00},
    'xor':  {'type': 'R', 'opcode': 0x33, 'funct3': 0x4, 'funct7': 0x00},
    'srl':  {'type': 'R', 'opcode': 0x33, 'funct3': 0x5, 'funct7': 0x00},
    'sra':  {'type': 'R', 'opcode': 0x33, 'funct3': 0x5, 'funct7': 0x20},
    'or':   {'type': 'R', 'opcode': 0x33, 'funct3': 0x6, 'funct7': 0x00},
    'and':  {'type': 'R', 'opcode': 0x33, 'funct3': 0x7, 'funct7': 0x00},
    'addi': {'type': 'I', 'opcode': 0x13, 'funct3': 0x0},
    'slti': {'type': 'I', 'opcode': 0x13, 'funct3': 0x2},
    'sltiu':{'type': 'I', 'opcode': 0x13, 'funct3': 0x3},
    'xori': {'type': 'I', 'opcode': 0x13, 'funct3': 0x4},
    'ori':  {'type': 'I', 'opcode': 0x13, 'funct3': 0x6},
    'andi': {'type': 'I', 'opcode': 0x13, 'funct3': 0x7},
    'slli': {'type': 'I_SHIFT', 'opcode': 0x13, 'funct3': 0x1, 'funct7': 0x00},
    'srli': {'type': 'I_SHIFT', 'opcode': 0x13, 'funct3': 0x5, 'funct7': 0x00},
    'srai': {'type': 'I_SHIFT', 'opcode': 0x13, 'funct3': 0x5, 'funct7': 0x20},
    'lb':   {'type': 'I_LOAD', 'opcode': 0x03, 'funct3': 0x0},
    'lh':   {'type': 'I_LOAD', 'opcode': 0x03, 'funct3': 0x1},
    'lw':   {'type': 'I_LOAD', 'opcode': 0x03, 'funct3': 0x2},
    'lbu':  {'type': 'I_LOAD', 'opcode': 0x03, 'funct3': 0x4},
    'lhu':  {'type': 'I_LOAD', 'opcode': 0x03, 'funct3': 0x5},
    'jalr': {'type': 'I_LOAD', 'opcode': 0x67, 'funct3': 0x0},
    'sb':   {'type': 'S', 'opcode': 0x23, 'funct3': 0x0},
    'sh':   {'type': 'S', 'opcode': 0x23, 'funct3': 0x1},
    'sw':   {'type': 'S', 'opcode': 0x23, 'funct3': 0x2},
    'beq':  {'type': 'B', 'opcode': 0x63, 'funct3': 0x0},
    'bne':  {'type': 'B', 'opcode': 0x63, 'funct3': 0x1},
    'lui':  {'type': 'U', 'opcode': 0x37},
    'jal':  {'type': 'J', 'opcode': 0x6F},
    'ecall': {'type': 'SYS', 'opcode': 0x73, 'funct3': 0x0, 'funct12': 0x000}
}

# ==============================================================================
# 3. HELPER FUNCTIONS
# ==============================================================================

def parse_reg(s):
    s = s.strip().replace(',', '')
    if s in REGISTERS: return REGISTERS[s]
    try:
        if s.startswith('x'): return int(s[1:])
    except: pass
    raise ValueError(f"Unknown register: {s}")

def parse_imm(s):
    s = s.strip().replace(',', '')
    try: return int(s, 0)
    except: raise ValueError(f"Invalid immediate: {s}")

def signed_int(val, bits):
    if val >= (1 << (bits - 1)): val -= (1 << bits)
    return val & ((1 << bits) - 1)

# ==============================================================================
# 4. CORE PROCESSING LOGIC
# ==============================================================================

def expand_macros(raw_lines):
    expanded = []
    for line in raw_lines:
        line = line.split('#')[0].strip()
        if not line: continue
        if line.endswith(':'):
            expanded.append(line)
            continue

        parts = re.split(r'[,\s]+', line)
        mnemonic = parts[0].lower()
        args = [x for x in parts[1:] if x]
        
        new_instrs = []
        if mnemonic == 'nop':
            new_instrs.append("addi x0, x0, 0")
        elif mnemonic == 'mv':
            new_instrs.append(f"addi {args[0]}, {args[1]}, 0")
        elif mnemonic == 'li':
            rd, imm = args[0], parse_imm(args[1])
            if -2048 <= imm <= 2047:
                new_instrs.append(f"addi {rd}, zero, {imm}")
            else:
                lower = imm & 0xFFF
                upper = (imm >> 12) & 0xFFFFF
                if lower & 0x800: upper += 1
                new_instrs.append(f"lui {rd}, {upper}")
                if lower & 0x800: lower -= 4096
                if lower != 0: new_instrs.append(f"addi {rd}, {rd}, {lower}")
        elif mnemonic == 'blt':
            new_instrs.append(f"slt {ASM_TEMP_REG}, {args[0]}, {args[1]}")
            new_instrs.append(f"bne {ASM_TEMP_REG}, zero, {args[2]}")
        else:
            expanded.append(line)
            continue

        Log.macro(line, new_instrs)
        expanded.extend(new_instrs)
    return expanded

def assemble(source_lines):
    """Main internal logic to convert list of strings to binary word list."""
    print(f"{Log.BOLD}--- Phase 1: Macro Expansion ---{Log.END}")
    lines = expand_macros(source_lines)
    
    labels, pc, clean_instrs = {}, 0, []
    
    for line in lines:
        if line.endswith(':'):
            labels[line[:-1].lower()] = pc
            continue
        if ':' in line:
            lbl, rest = line.split(':', 1)
            labels[lbl.strip().lower()] = pc
            line = rest.strip()
        clean_instrs.append((pc, line))
        pc += 4

    print(f"\n{Log.BOLD}--- Phase 2: Instruction Encoding ---{Log.END}")
    binary_code = []
    
    for pc, line in clean_instrs:
        Log.step(pc, f"Parsing: {line}")
        norm_line = line.replace('(', ' ').replace(')', ' ')
        parts = [p for p in re.split(r'[,\s]+', norm_line) if p]
        
        op = parts[0].lower()
        info = INSTRUCTIONS[op]
        val = 0

        # --- Encoding Switch ---
        if info['type'] == 'R':
            rd, rs1, rs2 = parse_reg(parts[1]), parse_reg(parts[2]), parse_reg(parts[3])
            val = (info['funct7'] << 25) | (rs2 << 20) | (rs1 << 15) | (info['funct3'] << 12) | (rd << 7) | info['opcode']
        elif info['type'] == 'I':
            rd, rs1, imm = parse_reg(parts[1]), parse_reg(parts[2]), parse_imm(parts[3])
            val = (signed_int(imm, 12) << 20) | (rs1 << 15) | (info['funct3'] << 12) | (rd << 7) | info['opcode']
        elif info['type'] == 'I_SHIFT':
            rd, rs1, shamt = parse_reg(parts[1]), parse_reg(parts[2]), parse_imm(parts[3]) & 0x1F
            val = (info['funct7'] << 25) | (shamt << 20) | (rs1 << 15) | (info['funct3'] << 12) | (rd << 7) | info['opcode']
        elif info['type'] == 'I_LOAD':
            rd = parse_reg(parts[1])
            if len(parts) == 4 and not parts[2].isdigit() and parts[3].isdigit():
                rs1, imm = parse_reg(parts[2]), parse_imm(parts[3])
            else:
                imm, rs1 = parse_imm(parts[2]), parse_reg(parts[3])
            val = (signed_int(imm, 12) << 20) | (rs1 << 15) | (info['funct3'] << 12) | (rd << 7) | info['opcode']
        elif info['type'] == 'S':
            rs2, imm, rs1 = parse_reg(parts[1]), parse_imm(parts[2]), parse_reg(parts[3])
            imm = signed_int(imm, 12)
            val = (((imm >> 5) & 0x7F) << 25) | (rs2 << 20) | (rs1 << 15) | (info['funct3'] << 12) | ((imm & 0x1F) << 7) | info['opcode']
        elif info['type'] == 'B':
            rs1, rs2, offset = parse_reg(parts[1]), parse_reg(parts[2]), signed_int(labels[parts[3].lower()] - pc, 13)
            val = (((offset >> 12) & 1) << 31) | (((offset >> 5) & 0x3F) << 25) | (rs2 << 20) | (rs1 << 15) | (info['funct3'] << 12) | (((offset >> 1) & 0xF) << 8) | (((offset >> 11) & 1) << 7) | info['opcode']
        elif info['type'] == 'U':
            rd, imm = parse_reg(parts[1]), parse_imm(parts[2])
            val = (imm & 0xFFFFF) << 12 | (rd << 7) | info['opcode']
        elif info['type'] == 'J':
            rd, offset = parse_reg(parts[1]), signed_int(labels[parts[2].lower()] - pc, 21)
            val = (((offset >> 20) & 1) << 31) | (((offset >> 1) & 0x3FF) << 21) | (((offset >> 11) & 1) << 20) | (((offset >> 12) & 0xFF) << 12) | (rd << 7) | info['opcode']
        elif info['type'] == 'SYS':
            val = (info['funct12'] << 20) | (info['funct3'] << 12) | info['opcode']

        Log.encode(val)
        binary_code.append(val)
    return binary_code

# ==============================================================================
# 5. STANDARDIZED API
# ==============================================================================

def assemble_file(input_filepath, output_filepath):
    """
    Standard API: Takes an input assembly file path and produces a binary file.
    """
    try:
        with open(input_filepath, 'r') as f:
            lines = f.readlines()
        
        machine_code = assemble(lines)

        with open(output_filepath, "wb") as f:
            for instr in machine_code:
                f.write(struct.pack('<I', instr))
        
        print(f"\n{Log.GREEN}Success! Output written to {output_filepath}{Log.END}")
        return True
    except Exception as e:
        print(f"\n{Log.RED}Error during assembly: {e}{Log.END}")
        return False

# ==============================================================================
# 6. CLI ENTRY POINT
# ==============================================================================

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="Simple RISC-V Assembler API")
    parser.add_argument('input', help="Input .s or .asm file")
    parser.add_argument('-o', '--output', default='program.bin', help="Output binary file")
    args = parser.parse_args()
    
    assemble_file(args.input, args.output)
