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
SIZE_IF_ID     = 12
SIZE_ID_EX     = 28
SIZE_EX_MEM    = 16
SIZE_MEM_WB    = 16
SIZE_PIPELINE  = SIZE_HAZARD + SIZE_IF_ID + SIZE_ID_EX + SIZE_EX_MEM + SIZE_MEM_WB

# --- STYLING ---
C_CYAN   = "\033[96m"
C_GREEN  = "\033[92m"
C_RED    = "\033[91m"
C_YELLOW = "\033[93m"
C_RESET  = "\033[0m"
C_BOLD   = "\033[1m"

def fmt_bool(val):
    return f"{C_GREEN}1{C_RESET}" if val else f"{C_RED}0{C_RESET}"

# ==============================================================================
# 1. DATA STRUCTURES (The Model)
# ==============================================================================

@dataclass
class HazardState:
    pc_stall: bool; id_stall: bool; ex_stall: bool
    if_flush: bool; id_flush: bool
    fwd_a: int; fwd_b: int

    def table_row(self):
        # Explicitly lists all flags even when 0
        return (f"| PC_S:{fmt_bool(self.pc_stall)} | ID_S:{fmt_bool(self.id_stall)} | "
                f"EX_S:{fmt_bool(self.ex_stall)} | IF_F:{fmt_bool(self.if_flush)} | "
                f"ID_F:{fmt_bool(self.id_flush)} | FwdA:{self.fwd_a:02b} | FwdB:{self.fwd_b:02b} |")

@dataclass
class StageIFID:
    pc: int
    instr: int
    pc4: int
    def __str__(self): return f"{C_GREEN}[IF/ID]{C_RESET}  PC: 0x{self.pc:08X} | Instr: 0x{self.instr:08X}"

@dataclass
class StageIDEX:
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
    
    pc: int
    pc4: int
    rs1_data: int
    rs2_data: int
    imm: int
    
    rs1_addr: int
    rs2_addr: int
    rd_addr: int
    funct3: int
    funct7: int

    def table_header(self):
        return "| RegW | MemW | MemR | SrcImm | Br | Jal | Jalr | HALT |"

    def table_row(self):
        vals = [self.reg_write, self.mem_write, self.mem_read, self.alu_src_imm, 
                self.is_branch, self.is_jal, self.is_jalr, self.is_halt]
        row = " | ".join([f"  {fmt_bool(v)} " for v in vals])
        return f"|{row}|"
    
    def __str__(self):
        ctrls = []
        if self.reg_write: ctrls.append("RegW")
        if self.mem_write: ctrls.append("MemW")
        if self.mem_read: ctrls.append("MemR")
        if self.is_branch: ctrls.append("Br")
        if self.is_jal: ctrls.append("Jal")
        if self.is_halt: ctrls.append("HALT")
        ctrl_str = " ".join(ctrls)
        
        meta = f"rs1:x{self.rs1_addr} rs2:x{self.rs2_addr} rd:x{self.rd_addr}"
        return f"{C_GREEN}[ID/EX]{C_RESET}  PC: 0x{self.pc:08X} | Imm: 0x{self.imm:08X} | {ctrl_str} | {meta}"

@dataclass
class StageEXMEM:
    reg_write: bool
    mem_write: bool
    mem_read: bool
    rd_src: int
    is_halt: bool
    
    alu_res: int
    store_val: int
    pc4: int
    
    rd_addr: int
    funct3: int

    def __str__(self):
        ctrls = []
        if self.mem_write: ctrls.append("MemW")
        if self.mem_read: ctrls.append("MemR")
        ctrl_str = " ".join(ctrls)
        return f"{C_GREEN}[EX/MEM]{C_RESET} ALU: 0x{self.alu_res:08X} | Store: 0x{self.store_val:08X} | Rd: x{self.rd_addr} | {ctrl_str}"

@dataclass
class StageMEMWB:
    reg_write: bool
    rd_src: int
    is_halt: bool
    
    alu_res: int
    mem_data: int
    pc4: int
    
    rd_addr: int

    def __str__(self):
        src_str = ["ALU", "PC+4", "MEM", "?"][self.rd_src & 3]
        wb_str = f"RegW(x{self.rd_addr})={src_str}" if self.reg_write else "NoWrite"
        if self.is_halt: wb_str += " HALTED"
        return f"{C_GREEN}[MEM/WB]{C_RESET} ALU: 0x{self.alu_res:08X} | Mem: 0x{self.mem_data:08X} | {wb_str}"

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
    source_mode: str  # "STEP" or "CONTINUOUS"
    registers: List[int]
    hazard: HazardState
    if_id: StageIFID
    id_ex: StageIDEX
    ex_mem: StageEXMEM
    mem_wb: StageMEMWB
    memory: MemoryState

    def pretty_print(self):
        # Header now includes the SOURCE MODE
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
        print(f"\n{C_YELLOW}► ID/EX Control Signals{C_RESET}")
        print(f"  {self.id_ex.table_header()}")
        print(f"  {self.id_ex.table_row()}")
        print(f"  {self.ex_mem}")
        print(f"  {self.mem_wb}")

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
            
            if len(self.buffer) < (2 + SIZE_REG_FILE + SIZE_PIPELINE): return 

            mode = self.buffer[1]
            mem_offset = 2 + SIZE_REG_FILE + SIZE_PIPELINE
            
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

            total_size = 2 + SIZE_REG_FILE + SIZE_PIPELINE + mem_size

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
        
        # --- Source Mode Identification ---
        source_str = "STEP" if mode == 0x00 else "CONTINUOUS"

        # --- Registers ---
        regs = [struct.unpack('<I', data[ptr + i*4 : ptr + (i+1)*4])[0] for i in range(32)]
        ptr += SIZE_REG_FILE
        
        # --- Hazard (4B) ---
        h_flags = data[ptr]; ptr += 1
        h_fwd   = data[ptr]; ptr += 3
        hazard = HazardState(
            pc_stall = bool(h_flags & 0x01),
            id_stall = bool(h_flags & 0x02),
            ex_stall = bool(h_flags & 0x04),
            if_flush = bool(h_flags & 0x08),
            id_flush = bool(h_flags & 0x10),
            fwd_a    = (h_fwd >> 2) & 0x03,
            fwd_b    = h_fwd & 0x03
        )

        # --- IF/ID (12B) ---
        if_pc, if_instr, if_pc4 = struct.unpack('<III', data[ptr:ptr+12]); ptr += 12
        stage_if = StageIFID(if_pc, if_instr, if_pc4)

        # --- ID/EX (28B) ---
        id_ctrl, id_pc, id_pc4, id_rs1, id_rs2, id_imm, id_meta = struct.unpack('<H2xIIIIII', data[ptr:ptr+28]); ptr += 28
        stage_id = StageIDEX(
            reg_write = bool((id_ctrl >> 11) & 1),
            mem_write = bool((id_ctrl >> 10) & 1),
            mem_read  = bool((id_ctrl >> 9) & 1),
            alu_src_imm = bool((id_ctrl >> 8) & 1),
            alu_intent = (id_ctrl >> 6) & 0x03,
            rd_src    = (id_ctrl >> 4) & 0x03,
            is_branch = bool((id_ctrl >> 3) & 1),
            is_jal    = bool((id_ctrl >> 2) & 1),
            is_jalr   = bool((id_ctrl >> 1) & 1),
            is_halt   = bool(id_ctrl & 1),
            pc=id_pc, pc4=id_pc4, rs1_data=id_rs1, rs2_data=id_rs2, imm=id_imm,
            rs1_addr = (id_meta >> 20) & 0x1F,
            rs2_addr = (id_meta >> 15) & 0x1F,
            rd_addr  = (id_meta >> 10) & 0x1F,
            funct3   = (id_meta >> 7) & 0x07,
            funct7   = id_meta & 0x7F
        )

        # --- EX/MEM (16B) ---
        ex_packed, ex_alu, ex_store, ex_pc4 = struct.unpack('<H2xIII', data[ptr:ptr+16]); ptr += 16
        ex_ctrl = (ex_packed >> 8) & 0x3F
        ex_meta = ex_packed & 0xFF
        stage_ex = StageEXMEM(
            reg_write = bool((ex_ctrl >> 5) & 1),
            mem_write = bool((ex_ctrl >> 4) & 1),
            mem_read  = bool((ex_ctrl >> 3) & 1),
            rd_src    = (ex_ctrl >> 1) & 0x03,
            is_halt   = bool(ex_ctrl & 1),
            alu_res=ex_alu, store_val=ex_store, pc4=ex_pc4,
            rd_addr   = (ex_meta >> 3) & 0x1F,
            funct3    = ex_meta & 0x07
        )

        # --- MEM/WB (16B) ---
        wb_packed, wb_alu, wb_mem, wb_pc4 = struct.unpack('<H2xIII', data[ptr:ptr+16]); ptr += 16
        wb_ctrl = (wb_packed >> 5) & 0x0F
        wb_meta = wb_packed & 0x1F
        stage_wb = StageMEMWB(
            reg_write = bool((wb_ctrl >> 3) & 1),
            rd_src    = (wb_ctrl >> 1) & 0x03,
            is_halt   = bool(wb_ctrl & 1),
            alu_res=wb_alu, mem_data=wb_mem, pc4=wb_pc4,
            rd_addr   = wb_meta
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
