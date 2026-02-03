import serial
import threading
import sys
import time
import struct
from dataclasses import dataclass, field
from typing import List

# --- CONFIGURATION ---
PORT = 'COM12'
BAUD = 115200

# --- PROTOCOL CONSTANTS ---
CMD_DUMP_ALERT = 0xDA
SIZE_REG_FILE  = 128
SIZE_HAZARD    = 4

# Pipeline Sizes (Based on User "Real Content" Packing)
# IF/ID:  PC(4) + Instr(4) + PC4(4) = 12
SIZE_IF_ID     = 12 
# ID/EX:  Ctrl(4) + PC(4) + RS1(4) + RS2(4) + Imm(4) + Meta(4) = 24
SIZE_ID_EX     = 24 
# EX/MEM: CtrlMeta(4) + ALU(4) + Store(4) + PC(4) = 16
SIZE_EX_MEM    = 16 
# MEM/WB: CtrlMeta(4) + Exec(4) + Read(4) + PC(4) = 16
SIZE_MEM_WB    = 16 

SIZE_PIPELINE  = SIZE_HAZARD + SIZE_IF_ID + SIZE_ID_EX + SIZE_EX_MEM + SIZE_MEM_WB

# --- STYLING ---
C_CYAN   = "\033[96m"
C_GREEN  = "\033[92m"
C_RED    = "\033[91m"
C_YELLOW = "\033[93m"
C_RESET  = "\033[0m"
C_BOLD   = "\033[1m"

def fmt_bool(val, true_txt="1", false_txt="0"):
    return f"{C_GREEN}{true_txt}{C_RESET}" if val else f"{C_RED}{false_txt}{C_RESET}"

# ==============================================================================
# 1. DATA STRUCTURES (The Model)
# ==============================================================================

@dataclass
class HazardState:
    # Based on tap_hazard_o = {6'b0, pc_wen, if_wen, ctrl_haz, load_haz, rs2_fwd, rs1_fwd, 3'b0, end}
    pc_write_en: bool
    if_id_write_en: bool
    control_hazard: bool
    load_use_hazard: bool
    enc_rs2_fwd: bool
    enc_rs1_fwd: bool
    program_ended: bool

    def table_row(self):
        # Interpret Write Enables as Stalls for display clarity
        pc_state = f"{C_GREEN}RUN{C_RESET}" if self.pc_write_en else f"{C_RED}STALL{C_RESET}"
        if_state = f"{C_GREEN}RUN{C_RESET}" if self.if_id_write_en else f"{C_RED}STALL{C_RESET}"
        
        flags = []
        if self.control_hazard: flags.append("CTRL_FLUSH")
        if self.load_use_hazard: flags.append("LOAD_STALL")
        if self.program_ended: flags.append(f"{C_RED}HALTED{C_RESET}")
        flag_str = " ".join(flags) if flags else "-"

        fwd_str = ""
        if self.enc_rs1_fwd: fwd_str += "FwdA "
        if self.enc_rs2_fwd: fwd_str += "FwdB"
        if not fwd_str: fwd_str = "-"

        return (f"| PC: {pc_state} | IF/ID: {if_state} | Hazards: {flag_str:12} | Forward: {fwd_str:8} |")

@dataclass
class StageIFID:
    pc: int
    instr: int
    pc4: int
    def __str__(self): return f"{C_GREEN}[IF/ID]{C_RESET}  PC: 0x{self.pc:08X} | Instr: 0x{self.instr:08X}"

@dataclass
class StageIDEX:
    # Control (12 bits)
    reg_write: bool
    mem_write: bool
    mem_read: bool
    alu_src_imm: bool
    alu_intent: int
    rd_src: int
    is_branch: bool
    is_jal: bool
    is_jalr: bool
    is_halt: bool
    
    # Data
    pc: int
    rs1_data: int
    rs2_data: int
    imm: int
    
    # Metadata
    rs1_addr: int
    rs2_addr: int
    rd_addr: int
    funct3: int
    funct7: int

    def table_header(self):
        return "| RegW | MemW | MemR | AluSrc | Intent | RdSrc | Br | Jal | Jalr | HALT |"

    def table_row(self):
        intent_map = {0:"ADD", 1:"SUB", 2:"SLT", 3:"?"} # Example mapping
        vals = [
            fmt_bool(self.reg_write), fmt_bool(self.mem_write), fmt_bool(self.mem_read),
            fmt_bool(self.alu_src_imm, "IMM", "REG"), 
            f"{self.alu_intent:1d}", f"{self.rd_src:1d}",
            fmt_bool(self.is_branch), fmt_bool(self.is_jal), fmt_bool(self.is_jalr), fmt_bool(self.is_halt)
        ]
        row = " | ".join([f"  {v} " for v in vals])
        return f"|{row}|"
    
    def __str__(self):
        return (f"{C_GREEN}[ID/EX]{C_RESET}  PC: 0x{self.pc:08X} | Imm: 0x{self.imm:08X} | "
                f"rs1:x{self.rs1_addr} rs2:x{self.rs2_addr} rd:x{self.rd_addr}")

@dataclass
class StageEXMEM:
    # Control
    reg_write: bool
    mem_write: bool
    mem_read: bool
    rd_src: int
    is_halt: bool
    
    # Data
    alu_res: int
    store_data: int
    pc: int
    
    # Meta
    rd_addr: int
    funct3: int

    def __str__(self):
        ctrls = []
        if self.mem_write: ctrls.append(f"{C_RED}MemW{C_RESET}")
        if self.mem_read: ctrls.append(f"{C_CYAN}MemR{C_RESET}")
        ctrl_str = " ".join(ctrls)
        return (f"{C_GREEN}[EX/MEM]{C_RESET} ALU: 0x{self.alu_res:08X} | Store: 0x{self.store_data:08X} | "
                f"Rd: x{self.rd_addr} | {ctrl_str}")

@dataclass
class StageMEMWB:
    # Control
    reg_write: bool
    rd_src: int
    is_halt: bool
    
    # Data
    exec_data: int # ALU result
    read_data: int # Memory read result
    pc: int
    
    # Meta
    rd_addr: int

    def __str__(self):
        # RdSrc mapping: 0=ALU, 1=Mem, 2=PC+4
        src_map = ["ALU", "MEM", "PC+4", "?"]
        src_str = src_map[self.rd_src & 3]
        
        wb_str = f"Write(x{self.rd_addr})={src_str}" if self.reg_write else "NoWrite"
        if self.is_halt: wb_str += f" {C_RED}HALTED{C_RESET}"
        
        val_show = self.read_data if (self.rd_src == 1) else self.exec_data
        
        return f"{C_GREEN}[MEM/WB]{C_RESET} Val: 0x{val_show:08X} | {wb_str}"

@dataclass
class MemoryState:
    mode: int # 0=Step, 1=Cont
    step_write_flag: bool = False
    step_addr: int = 0
    step_data: int = 0
    range_min: int = 0
    range_max: int = 0
    range_words: List[int] = field(default_factory=list)

    def __str__(self):
        out = f"\n{C_YELLOW}► Data Memory{C_RESET}\n"
        if self.mode == 0:
            if self.step_write_flag:
                out += f"  {C_RED}STEP WRITE{C_RESET} -> Addr: 0x{self.step_addr:08X} | Data: 0x{self.step_data:08X}"
            else:
                out += "  No Write in this step."
        else:
            if self.range_min == 0xFFFFFFFF:
                out += "  No memory writes tracked (Empty)."
            else:
                out += f"  {C_GREEN}RANGE SCOOP{C_RESET} [0x{self.range_min:08X} - 0x{self.range_max:08X}]\n"
                curr = self.range_min
                for w in self.range_words:
                    out += f"    0x{curr:08X}: 0x{w:08X}\n"
                    curr += 4
        return out

@dataclass
class RISCVState:
    source_mode: str
    registers: List[int]
    hazard: HazardState
    if_id: StageIFID
    id_ex: StageIDEX
    ex_mem: StageEXMEM
    mem_wb: StageMEMWB
    memory: MemoryState

    def pretty_print(self):
        title = f" FPGA STATE DUMP ({self.source_mode}) "
        print(f"\n{C_BOLD}╔{title:═^60}╗{C_RESET}")
        
        # Registers
        print(f"{C_YELLOW}► Register File{C_RESET}")
        for row in range(8):
            line = ""
            for col in range(4):
                idx = row + (col * 8)
                val = self.registers[idx]
                color = C_CYAN if val != 0 else C_RESET
                line += f" x{idx:<2}: {color}0x{val:08X}{C_RESET}  "
            print(f"  {line}")

        # Pipeline
        print(f"\n{C_YELLOW}► Pipeline State{C_RESET}")
        print(f"  {self.hazard.table_row()}")
        print(f"  {self.if_id}")
        print(f"  {self.id_ex}")
        print(f"  {self.ex_mem}")
        print(f"  {self.mem_wb}")
        
        print(f"\n{C_YELLOW}► ID/EX Control Signals{C_RESET}")
        print(f"  {self.id_ex.table_header()}")
        print(f"  {self.id_ex.table_row()}")

        # Memory
        print(self.memory)
        print(f"{C_BOLD}╚═════════════════════════════════════════════════════════════════╝{C_RESET}")

# ==============================================================================
# 2. THE PARSER
# ==============================================================================

class RISCVDumpParser:
    def __init__(self):
        self.buffer = bytearray()
        self.history: List[RISCVState] = [] 

    def add_data(self, data):
        self.buffer.extend(data)
        self.process_buffer()

    def process_buffer(self):
        while len(self.buffer) > 0:
            if self.buffer[0] != CMD_DUMP_ALERT:
                byte = self.buffer.pop(0)
                sys.stdout.write(f"{C_CYAN}{byte:02X} {C_RESET}")
                sys.stdout.flush()
                continue
            
            # Check for Header + Regs + Pipeline
            # 2 (Alert+Mode) + 128 (Regs) + SIZE_PIPELINE
            header_size = 2 + SIZE_REG_FILE + SIZE_PIPELINE
            if len(self.buffer) < header_size: return 

            mode = self.buffer[1]
            mem_offset = header_size
            
            if len(self.buffer) < mem_offset + 4: return 

            word_count = 0
            if mode == 0x00: # Step
                flag = struct.unpack('<I', self.buffer[mem_offset:mem_offset+4])[0]
                mem_size = 12 if flag == 1 else 4
            else: # Continuous
                if len(self.buffer) < mem_offset + 8: return
                min_a = struct.unpack('<I', self.buffer[mem_offset:mem_offset+4])[0]
                max_a = struct.unpack('<I', self.buffer[mem_offset+4:mem_offset+8])[0]
                
                if min_a == 0xFFFFFFFF or max_a < min_a: word_count = 1
                else: word_count = ((max_a - min_a) // 4) + 1
                mem_size = 8 + (word_count * 4)

            total_size = header_size + mem_size

            if len(self.buffer) >= total_size:
                packet = self.buffer[:total_size]
                del self.buffer[:total_size]
                
                state_obj = self.decode_packet(packet, mode, word_count)
                self.history.append(state_obj)
                state_obj.pretty_print()
                print("\n>> ", end="")
                sys.stdout.flush()
            else:
                return

    def decode_packet(self, data, mode, cont_word_count) -> RISCVState:
        ptr = 2
        source_str = "STEP" if mode == 0x00 else "CONTINUOUS"

        # --- Registers (32 * 4B) ---
        regs = [struct.unpack('<I', data[ptr + i*4 : ptr + (i+1)*4])[0] for i in range(32)]
        ptr += SIZE_REG_FILE
        
        # --- Hazard (4B) ---
        # User defined bits: [9]PC_WE [8]IF_WE [7]Ctrl [6]Load [5]Fwd2 [4]Fwd1 [0]ProgEnd
        h_val = struct.unpack('<I', data[ptr:ptr+4])[0]; ptr += 4
        hazard = HazardState(
            pc_write_en    = bool((h_val >> 9) & 1),
            if_id_write_en = bool((h_val >> 8) & 1),
            control_hazard = bool((h_val >> 7) & 1),
            load_use_hazard= bool((h_val >> 6) & 1),
            enc_rs2_fwd    = bool((h_val >> 5) & 1),
            enc_rs1_fwd    = bool((h_val >> 4) & 1),
            program_ended  = bool((h_val >> 0) & 1)
        )

        # --- IF/ID (12B) ---
        # {pc_id, instr_id, pc_plus_4_id}
        if_pc, if_instr, if_pc4 = struct.unpack('<III', data[ptr:ptr+12]); ptr += 12
        stage_if = StageIFID(if_pc, if_instr, if_pc4)

        # --- ID/EX (24B) ---
        # Fields: Ctrl(4), PC(4), RS1(4), RS2(4), Imm(4), Meta(4)
        id_ctrl, id_pc, id_rs1, id_rs2, id_imm, id_meta = struct.unpack('<IIIIII', data[ptr:ptr+24]); ptr += 24
        
        stage_id = StageIDEX(
            # Control Decoding (12 bits)
            reg_write   = bool((id_ctrl >> 11) & 1),
            mem_write   = bool((id_ctrl >> 10) & 1),
            mem_read    = bool((id_ctrl >> 9) & 1),
            alu_src_imm = bool((id_ctrl >> 8) & 1),
            alu_intent  = (id_ctrl >> 6) & 0x03,
            rd_src      = (id_ctrl >> 4) & 0x03,
            is_branch   = bool((id_ctrl >> 3) & 1),
            is_jal      = bool((id_ctrl >> 2) & 1),
            is_jalr     = bool((id_ctrl >> 1) & 1),
            is_halt     = bool((id_ctrl >> 0) & 1),
            # Data
            pc=id_pc, rs1_data=id_rs1, rs2_data=id_rs2, imm=id_imm,
            # Meta Decoding (25 bits)
            rs1_addr = (id_meta >> 20) & 0x1F,
            rs2_addr = (id_meta >> 15) & 0x1F,
            rd_addr  = (id_meta >> 10) & 0x1F,
            funct3   = (id_meta >> 7) & 0x07,
            funct7   = (id_meta) & 0x7F
        )

        # --- EX/MEM (16B) ---
        # Fields: CtrlMeta(4), ALU(4), Store(4), PC(4)
        ex_cm, ex_alu, ex_store, ex_pc = struct.unpack('<IIII', data[ptr:ptr+16]); ptr += 16
        
        stage_ex = StageEXMEM(
            # Control (High bits of ex_cm)
            reg_write = bool((ex_cm >> 13) & 1),
            mem_write = bool((ex_cm >> 12) & 1),
            mem_read  = bool((ex_cm >> 11) & 1),
            rd_src    = (ex_cm >> 9) & 0x03,
            is_halt   = bool((ex_cm >> 8) & 1),
            # Data
            alu_res=ex_alu, store_data=ex_store, pc=ex_pc,
            # Meta (Low bits)
            rd_addr   = (ex_cm >> 3) & 0x1F,
            funct3    = (ex_cm) & 0x07
        )

        # --- MEM/WB (16B) ---
        # Fields: CtrlMeta(4), Exec(4), Read(4), PC(4)
        wb_cm, wb_exec, wb_read, wb_pc = struct.unpack('<IIII', data[ptr:ptr+16]); ptr += 16
        
        stage_wb = StageMEMWB(
            # Control
            reg_write = bool((wb_cm >> 8) & 1),
            rd_src    = (wb_cm >> 6) & 0x03,
            is_halt   = bool((wb_cm >> 5) & 1),
            # Data
            exec_data=wb_exec, read_data=wb_read, pc=wb_pc,
            # Meta
            rd_addr   = (wb_cm) & 0x1F
        )

        # --- Memory ---
        mem_state = MemoryState(mode=mode)
        if mode == 0:
            flag = struct.unpack('<I', data[ptr:ptr+4])[0]; ptr += 4
            if flag == 1:
                mem_state.step_write_flag = True
                mem_state.step_addr, mem_state.step_data = struct.unpack('<II', data[ptr:ptr+8])
        else:
            mem_state.range_min, mem_state.range_max = struct.unpack('<II', data[ptr:ptr+8]); ptr += 8
            for _ in range(cont_word_count):
                val = struct.unpack('<I', data[ptr:ptr+4])[0]; ptr += 4
                mem_state.range_words.append(val)

        return RISCVState(source_str, regs, hazard, stage_if, stage_id, stage_ex, stage_wb, mem_state)

# ==============================================================================
# 3. MAIN EXECUTION
# ==============================================================================

parser = RISCVDumpParser()

def rx_thread():
    print("   [Listener Started]")
    while True:
        try:
            if ser.in_waiting > 0:
                data = ser.read(ser.in_waiting)
                parser.add_data(data)
        except OSError: break
        time.sleep(0.01)

try:
    ser = serial.Serial(PORT, BAUD, timeout=0.1)
    print(f"✅ Connected to {PORT} at {BAUD}")
except Exception as e:
    print(f"❌ Error: {e}")
    sys.exit(1)

t = threading.Thread(target=rx_thread, daemon=True)
t.start()

print("------------------------------------------------")
print("📝 Commands: 1C (Load), DE (Step), CE (Run)")
print("------------------------------------------------")

try:
    while True:
        inp = input(">> ").strip()
        if inp.lower() in ['exit', 'quit']: break
        if not inp: continue
        try:
            clean = inp.replace(',', '').replace('0x', '').replace(' ', '')
            ser.write(bytes.fromhex(clean))
        except ValueError: print("❌ Invalid Hex")
except KeyboardInterrupt:
    print("\nExiting...")
finally:
    ser.close()
