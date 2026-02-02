import serial
import sys
import os
import time
import struct

# --- CONFIGURATION ---
PORT = 'COM12'       # Change to your FPGA port
BAUD = 115200
TIMEOUT = 2.0        # Seconds to wait for ACKs

# --- CONSTANTS ---
CMD_LOAD_CODE = 0x1C
CMD_LOAD_DATA = 0x1D
ACK_FINISH    = 0xF1
ECALL_OPCODE  = b'\x73\x00\x00\x00'

def print_status(msg, color="white"):
    colors = {
        "green": "\033[92m",
        "red": "\033[91m",
        "yellow": "\033[93m",
        "cyan": "\033[96m",
        "white": "\033[0m"
    }
    end = colors["white"]
    print(f"{colors.get(color, end)}{msg}{end}")

def validate_binary(data):
    """Checks if data is aligned and ends with ECALL"""
    # 1. Check Alignment
    if len(data) % 4 != 0:
        padding = 4 - (len(data) % 4)
        print_status(f"⚠️  File size {len(data)} is not 4-byte aligned. Padding with {padding} zeros.", "yellow")
        data += b'\x00' * padding
    
    # 2. Check ECALL (Last 4 bytes)
    # Note: Only strict for Code. We warn but allow it.
    last_word = data[-4:]
    if last_word == ECALL_OPCODE:
        print_status("✅ Verification: File ends with ECALL (0x00000073).", "green")
    else:
        print_status(f"⚠️  Warning: File does NOT end with ECALL. Ends with: {last_word.hex()}", "yellow")
        
    return data

def load_file(target_cmd, filename):
    try:
        with open(filename, 'rb') as f:
            raw_data = f.read()
    except FileNotFoundError:
        print_status(f"❌ Error: File '{filename}' not found.", "red")
        return

    print_status(f"📂 Loaded '{filename}' ({len(raw_data)} bytes)", "cyan")
    
    # Validate and Pad
    payload = validate_binary(bytearray(raw_data))
    
    # Calculate Word Count (16-bit)
    word_count = len(payload) // 4
    if word_count > 65535:
        print_status(f"❌ Error: File too large ({word_count} words). Max is 65535.", "red")
        return

    # --- SERIAL TRANSACTION ---
    try:
        ser = serial.Serial(PORT, BAUD, timeout=TIMEOUT)
        # Clear any garbage in buffer
        ser.reset_input_buffer()
        
        # 1. Send Command (1C or 1D)
        cmd_byte = bytes([target_cmd])
        print_status(f"1️⃣  Sending Command: 0x{target_cmd:02X}...", "white")
        ser.write(cmd_byte)

        # 2. Wait for Handshake Echo
        echo = ser.read(1)
        if len(echo) == 0:
            print_status("❌ Timeout: No Echo received from FPGA.", "red")
            return
        
        if echo != cmd_byte:
            print_status(f"❌ Error: Invalid Echo. Expected 0x{target_cmd:02X}, got {echo.hex().upper()}", "red")
            return
        
        print_status(f"   Shape confirmed (Echo received).", "green")

        # 3. Send Word Count (High Byte, Low Byte)
        # Note: Loader expects High Byte first (Big Endian transmission of size)
        size_bytes = struct.pack('>H', word_count) # >H = Big Endian Unsigned Short
        print_status(f"2️⃣  Sending Size: {word_count} words ({size_bytes.hex()})", "white")
        ser.write(size_bytes)

        # 4. Send Payload
        print_status(f"3️⃣  Transmitting {len(payload)} bytes...", "white")
        ser.write(payload)

        # 5. Wait for Final ACK (0xF1)
        ack = ser.read(1)
        if len(ack) == 0:
            print_status("⚠️  Warning: Payload sent, but timed out waiting for completion ACK (0xF1).", "yellow")
        elif ack == b'\xF1':
            print_status("✅ Success! Loader returned ACK_FINISH (0xF1).", "green")
        else:
            print_status(f"❌ Error: Unknown response after load: {ack.hex()}", "red")

    except serial.SerialException as e:
        print_status(f"❌ Serial Error: {e}", "red")
    finally:
        if 'ser' in locals() and ser.is_open:
            ser.close()

# --- MAIN MENU ---
if __name__ == "__main__":
    print("========================================")
    print("   FPGA RISC-V BINARY LOADER")
    print("========================================")
    
    if len(sys.argv) > 1:
        f_path = sys.argv[1]
    else:
        f_path = input("📝 Enter .bin file path: ").strip().replace('"', '')

    print("\nSelect Target Memory:")
    print("  [1] Instruction Memory (IMEM) - 0x1C")
    print("  [2] Data Memory (DMEM)        - 0x1D")
    
    choice = input(">> ").strip()
    
    target = CMD_LOAD_CODE
    if choice == '2':
        target = CMD_LOAD_DATA
        print_status("Selected: DATA MEMORY", "yellow")
    else:
        print_status("Selected: INSTRUCTION MEMORY", "cyan")

    load_file(target, f_path)
