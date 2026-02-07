import serial
import serial.tools.list_ports
import struct
import logging
from state import app_state

BAUDRATE = 115200

# List all available serial ports
def list_serial_ports():
    ports = serial.tools.list_ports.comports()
    return [port.device for port in ports]


# --- CONSTANTS ---
CMD_LOAD_CODE = 0x1C
CMD_LOAD_DATA = 0x1D
ACK_FINISH    = 0xF1
ECALL_OPCODE  = b'\x73\x00\x00\x00'
MAX_WORDS     = 256  # Your specific hardware limit

# Connect to the UI logger
clean_out = logging.getLogger('riscv.clean')
raw_out = logging.getLogger('riscv.raw')

class LoaderError(Exception):
    """Custom exception for FPGA loading failures."""
    pass

def validate_payload(data: bytearray, is_instruction: bool):
    """Checks alignment, size, and ECALL requirement."""
    # 1. Size Check
    word_count = len(data) // 4
    if word_count > MAX_WORDS:
        raise LoaderError(f"File too large: {word_count} words. Max allowed is {MAX_WORDS}.")
    else:
        clean_out.info(f"- ✅ Checked file size: {word_count}/{MAX_WORDS} words (OK)")

    # 2. Alignment Check
    if len(data) % 4 != 0:
        padding = 4 - (len(data) % 4)
        clean_out.warning(f"Padding binary with {padding} bytes for alignment.")
        data += b'\x00' * padding
    else:
        clean_out.info("- ✅ File is properly aligned (multiple of 4 bytes).")

    # 3. Instruction strictness: Must end with ECALL
    if is_instruction:
        if data[-4:] != ECALL_OPCODE:
            raise LoaderError("Validation failed: Instruction memory must end with ECALL (0x00000073).")
        else:            
            clean_out.info("- ✅ ECALL check passed: Last instruction is ECALL.")

    return data

def upload_to_fpga(payload: bytes, is_instruction: bool):
    """
    Main API for loading bytes into the FPGA.
    target_cmd should be CMD_LOAD_CODE or CMD_LOAD_DATA.
    """

    logging.getLogger('riscv.raw').handlers[0].log_element.clear()
    logging.getLogger('riscv.clean').handlers[0].log_element.clear()
    if not app_state.port:
        raise LoaderError("No UART port selected in the header.")
    
    target_cmd = CMD_LOAD_CODE if is_instruction else CMD_LOAD_DATA 

    # Convert to bytearray for validation/padding
    data = validate_payload(bytearray(payload), target_cmd == CMD_LOAD_CODE)
    word_count = len(data) // 4

    clean_out.info(f"Connecting to {app_state.port}...")
    
    try:
        with serial.Serial(app_state.port, BAUDRATE, timeout=2.0) as ser:
            ser.reset_input_buffer()
            # 1. Send Command & Wait for Echo
            clean_out.info(f"Sending Command: 0x{target_cmd:02X}")
            ser.write(bytes([target_cmd]))
            raw_out.info(f">> 0x{target_cmd:02X}")
            echo = ser.read(1)
            raw_out.info(f"<< {echo.hex().upper() or 'nothing'}")

            if not echo or echo[0] != target_cmd:
                raise LoaderError(f"Handshake failed. Expected 0x{target_cmd:02X}, got {echo.hex().upper() or 'nothing'}")

            # 2. Send Word Count (Big Endian as per your protocol)
            size_bytes = struct.pack('>H', word_count)
            clean_out.info(f"Sending Word Count: {word_count}")
            ser.write(size_bytes)
            raw_out.info(f">> {size_bytes.hex().upper()}")

            # 3. Send Payload
            clean_out.info(f"Transmitting {len(data)} bytes...")
            ser.write(data)
            
            # Log payload in 64-byte chunks with hex formatting
            for i in range(0, len(data), 64):
                chunk = data[i:i+64]
                hex_str = ' '.join(f'{byte:02X}' for byte in chunk)
                raw_out.info(f">> {hex_str}")

            # 4. Final ACK
            ack = ser.read(1)
            raw_out.info(f"<< {ack.hex().upper() or 'nothing'}")
            if ack == b'\xF1':
                clean_out.info("✅ Load successful! FPGA acknowledged completion.")
                return True
            else:
                raise LoaderError(f"Loading finished but no ACK received. Got: {ack.hex()}")

    except serial.SerialException as e:
        raise LoaderError(f"Serial Port Error: {e}")
