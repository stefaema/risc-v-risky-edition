import serial
import time
import sys
from typing import Tuple, List
import logging

clean_out = logging.getLogger('riscv.clean')
raw_out = logging.getLogger('riscv.raw')

# --- IMPORTS FROM YOUR SCHEMES ---
from backend.schemes import (
    PipelineStatus, 
    MemPatch, 
    AtomicMemTransaction, 
    MemoryDumpMode, 
    unpack_words
)

BAUD_RATE = 115200
# --- PROTOCOL CONSTANTS ---
CMD_DUMP_ALERT = 0xDA
CMD_MODE_CONT  = 0xCE
CMD_MODE_STEP  = 0xDE
CMD_STEP_NEXT  = 0xAE

class SerialManager:
    def __init__(self, port: str, baud: int):
        # timeout=None ensures blocking reads, vital for waiting on sync bytes
        self.ser = serial.Serial(port, baud, timeout=None) 
        self.raw_log_file = "raw_log.txt"
        self.fmt_log_file = "formatted_log.txt"
        self.last_register_file = None
        
        # Clear/Init files on start
        with open(self.raw_log_file, 'w') as f: 
            f.write("--- RAW HEX DUMP ---\n")
        with open(self.fmt_log_file, 'w', encoding="utf-8") as f: 
            f.write("--- FORMATTED DUMP ---\n")

    def log_raw(self, words: List[int], tag: str):
        """Logs raw 32-bit integers to a text file for debugging byte alignment."""
        with open(self.raw_log_file, 'a') as f:
            f.write(f"\n[{tag}] Timestamp: {time.time()}\n")
            for i, w in enumerate(words):
                f.write(f"{i:03}: 0x{w:08X}\n")

    def list_only_diffs(self, current_rf):
        """Compares current register file to last logged one and lists only differences."""
        if self.last_register_file is None:
            return str(current_rf)  # No previous data, return full
        
        output = []
        for i in range(32):
            old_val = self.last_register_file.entries[i].value
            new_val = current_rf.entries[i].value
            if old_val != new_val:
                output.append(f"R{i:02}: 0x{old_val:08X} -> 0x{new_val:08X}")
        
        if not output:
            return "No changes in Register File."
        
        return "\n".join(output)

    def log_formatted(self, status: PipelineStatus, mem_obj, return_string: bool = False) -> str:
        """Logs the human-readable string representation of the objects."""
        output = []
        sep = "=" * 60
        output.append(sep)
        output.append(f"CAPTURE TIMESTAMP: {time.time()}")
        output.append(f"MODE: {status.memory_dump_mode}")
        output.append(sep)
        
        # We rely on the __str__ methods defined in gui/schemes.py


        if status.hazard_status.program_ended.value:
            output.append("\n>>FINAL REGISTER FILE")
            output.append(str(status.register_file))
        else:
            output.append("\n>>REGISTER FILE CHANGES")
            output.append(self.list_only_diffs(status.register_file))
            self.last_register_file = status.register_file
        
        output.append("\n>> HAZARD RELATED STATUS")
        output.append(str(status.hazard_status)) 
        
        output.append("\n>> IF/ID STAGE STATUS")
        output.append(str(status.if_id_status))
        
        output.append("\n>> ID/EX STAGE STATUS")
        output.append(str(status.id_ex_status))
        
        output.append("\n>> EX/MEM STAGE")
        output.append(str(status.ex_mem_status))
        
        output.append("\n>> MEM/WB STAGE STATUS")
        output.append(str(status.mem_wb_status))
        
        output.append("\n>> MEMORY UPDATE STATUS")
        output.append(str(mem_obj))
        
        output.append(sep + "\n\n")
        
        final_str = "\n".join(output)
        
        # 1. Print to Console (Verbose)
        if return_string:
            return final_str
        else:    
            print(final_str)
        
        # 2. Append to Text File
        with open(self.fmt_log_file, 'a', encoding="utf-8") as f:
            f.write(final_str)

    def wait_for_ack(self, expected_byte: int):
        """Blocks until the specific byte is echoed back by the FPGA."""
        print(f"Waiting for ACK (0x{expected_byte:02X})...")
        while True:
            b = self.ser.read(1)
            if b and ord(b) == expected_byte:
                print("✅ ACK Received.")
                return
            
    def read_pipeline_packet(self) -> Tuple[PipelineStatus, object]:
        """
        Waits for 0xDA, reads 50 pipeline words, decodes them, 
        then reads variable length memory words.
        """
        # 1. Wait for Header (DA)
        while True:
            clean_out.info("Waiting for Pipeline Dump Alert (0xDA)...")
            b = self.ser.read(1)
            raw_out.info(f"<< {b.hex().upper() or 'nothing'}")
            if b and ord(b) == CMD_DUMP_ALERT:
                clean_out.info("🚨 Pipeline Dump Alert Received.")
                break
        
        # 2. Read Mode Byte: Step/Snoop (0) or Continuous/Range (1)
        mode_byte = ord(self.ser.read(1))
        dump_mode = MemoryDumpMode.SNOOP_BASED if mode_byte == 0 else MemoryDumpMode.RANGE_BASED
        clean_out.info(f"📦 {dump_mode.name} Pipeline Packet Incoming...")

        # 3. Read 50 Words (RegFile + Pipeline)
        raw_pipe_data = self.ser.read(200)
        clean_out.info("📥 Pipeline Data Received.")

        pipe_words = unpack_words(raw_pipe_data, 50)

        for i in range(0, len(raw_pipe_data), 64):
            chunk = raw_pipe_data[i:i+64]
            hex_str = ' '.join(f'{byte:02X}' for byte in chunk)
            raw_out.info(f"<< {hex_str}")

        # 4. Decode Pipeline Status
        pipeline_status = PipelineStatus.unpack(dump_mode, pipe_words)
        clean_out.info("✅ Pipeline Status Parsed and Decoded.")
        
        raw_mem_flag = self.ser.read(4) # This is a pad word before memory data
        raw_out.info(f"<< {raw_mem_flag.hex().upper()}")
        clean_out.info("📥 Memory Data Incoming...")

        # 5. Read Memory Data Based on Mode. Only updated continuous mode for now.
        if dump_mode == MemoryDumpMode.SNOOP_BASED:

            raw_mem_flag = self.ser.read(4)
            raw_out.info(f"<< {raw_mem_flag.hex().upper()}")

            mem_flag_word = unpack_words(raw_mem_flag, 1)[0]
            

            if mem_flag_word == 0:
                print("ℹ️ No Memory Write in Step/Snoop Mode.")

                return pipeline_status, AtomicMemTransaction.unpack([False, 0, 0])

            else:
                print("📊 Reading Memory Step/Snoop Data...")

                mem_snoop = self.ser.read(8)
                self.log_raw(unpack_words(mem_snoop, 2), "MEMORY_SNOOP")

                mem_atomic_transaction = AtomicMemTransaction.unpack(
                    [mem_flag_word] + unpack_words(mem_snoop, 2)
                )

                return pipeline_status, mem_atomic_transaction
        
        else:

            raw_address_range = self.ser.read(8)
            raw_out.info(f"<< {raw_address_range[0:4].hex().upper()}")
            raw_out.info(f"<< {raw_address_range[4:8].hex().upper()}")
            

            address_range = unpack_words(raw_address_range, 2)
            clean_out.info("📊 Reading Memory Continuous/Range Data...")

            if address_range[0] == 0xFFFFFFFF and address_range[1] == 0x00000000:
                clean_out.info("    ℹ️ No Memory Updates to patch in Continuous/Range Mode.")

                return pipeline_status, MemPatch.unpack([0xFFFFFFFF, 0x00000000, 0x00000000])
            else:
                clean_out.info(f"   ℹ️ Memory Range Minimum Address: 0x{address_range[0]:08X}")
                clean_out.info(f"   ℹ️ Memory Range Maximum Address: 0x{address_range[1]:08X}")
            
            clean_out.info("    ℹ️ Calculating Memory Payload Size...")
            bytes_diff = address_range[1] - address_range[0]

            if bytes_diff == 0:
                num_words = 1
            else:
                num_words = ((bytes_diff - 1) // 4) + 2

            # 3. Calculate total bytes expected
            total_bytes_expected = num_words * 4

            clean_out.info(f"    ℹ️ Range: {address_range[0]:08x} - {address_range[1]:08x}")
            clean_out.info(f"    ℹ️ Expecting {num_words} words ({total_bytes_expected} bytes) of memory payload...")

            # 4. Read Memory Payload
            memory_payload = self.ser.read(total_bytes_expected)

            # 5. Unpack Memory Payload
            mem_payload_words = unpack_words(memory_payload, num_words)

            for i in range(0, len(mem_payload_words), 2):
                pair = mem_payload_words[i:i+2]
                raw_out.info(f"<< {' '.join(f'{word:08X}' for word in pair)}")

            clean_out.info("✅ Memory Payload Received and Parsed.")

            # 6. Rebuild Full MemPatch Object
            full_mem_words = address_range + mem_payload_words
            mem_patch = MemPatch.unpack(full_mem_words)

            return pipeline_status, mem_patch


    def start(self):
        print("--- RISC-V DEBUGGER ---")
        print("Select Mode: 'CE' (Continuous) or 'DE' (Step)")
        
        mode = input(">> ").strip().upper()
        
        if mode == "CE":
            # 1. Send Command
            self.ser.write(bytes([CMD_MODE_CONT]))
            # 2. Wait for Echo
            self.wait_for_ack(CMD_MODE_CONT)
            
            print("Entering Continuous Monitor Loop... (Ctrl+C to Stop)")
            try:
                while True:
                    # CE Mode: FPGA streams packets automatically
                    status, mem = self.read_pipeline_packet()
                    self.log_formatted(status, mem)
                    if status.hazard_status.program_ended.value:
                        print("⚠️ Program has ended. Exiting Continuous Mode.")
                        break
            except KeyboardInterrupt:
                print("\nStopping...")

        elif mode == "DE":
            # 1. Send Command
            self.ser.write(bytes([CMD_MODE_STEP]))
            # 2. Wait for Echo
            self.wait_for_ack(CMD_MODE_STEP)
            
            print("Entering Step Debug Mode.")
            print("Press ENTER (or type AE) to step clock. Ctrl+C to exit.")
            
            try:
                while True:
                    cmd = input("(DE) Next Step? > ")
                    # 3. Send Step Trigger
                    self.ser.write(bytes([CMD_STEP_NEXT])) # 0xAE
                    
                    # 4. Wait for resulting packet
                    status, mem = self.read_pipeline_packet()
                    self.log_formatted(status, mem)
                    if status.hazard_status.program_ended.value:
                        print("⚠️ Program has ended. Exiting Step Mode.")
                        break
            except KeyboardInterrupt:
                print("\nStopping...")
        else:
            print("Invalid Mode. Please restart.")

def execute_program(port: str):
    manager = SerialManager(port, BAUD_RATE)
    manager.ser.write(bytes([CMD_MODE_CONT]))
    raw_out.info(">> CE")
    manager.wait_for_ack(CMD_MODE_CONT)
    raw_out.info("<< CE")
    clean_out.info("Started Continuous Execution Mode via GUI.")
    try:
        while True:
            # CE Mode: FPGA streams packets automatically
            status, mem = manager.read_pipeline_packet()
            message = manager.log_formatted(status, mem, return_string=True)
            if status.hazard_status.program_ended.value:
                clean_out.info("⚠️ Program has ended. Exiting Continuous Mode.")
                break
    except KeyboardInterrupt:
        clean_out.info("Stopping...")
    return status, mem, message

