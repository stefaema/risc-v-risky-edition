from dataclasses import dataclass
from backend.schemes import PipelineStatus, MemPatch, AtomicMemTransaction
from typing import List, Dict, Optional, Tuple
# Main App section

@dataclass
class AppState:
    port = ""
    last_loaded_program: str = ""
    last_loaded_data: str = ""

    def is_ready_for_upload(self):
        return bool(self.port)
    
    def is_ready_for_execution(self):
        return bool(self.port and self.last_loaded_program and self.last_loaded_data)

app_state = AppState()


# Documentation Section

@dataclass
class LoadedDocumentState:
    filename = ""

loaded_document = LoadedDocumentState()

# Program Load Section

class LoadedProgramState:
    filename = ""
    display = ""
    content = "/* Seleccione un archivo */"
    mtime = 0.0
    ready = False
    machine_code = None
    payload = None

loaded_program_state = LoadedProgramState()


# Data Load Section

class DataMemoryState:
    def __init__(self):
        self.filename = ""          # Current filename for saving/loading
        self.memory = [0] * 1024     # The 1024 bytes of data (Integers 0-255)
        self.view_format = 'HEX'    # 'HEX', 'DEC', 'BIN'
        self.ready = False          # Used to toggle views/loading states

    def get_formatted_data(self):
        """Generates row data for the AG Grid based on current format."""
        rows = []
        for addr, val in enumerate(self.memory):
            # Format Address (Always Hex 0x00)
            addr_str = f"0x{addr:02X}"
            
            # Format Data based on selection
            if self.view_format == 'HEX':
                data_str = f"{val:02X}"
            elif self.view_format == 'BIN':
                data_str = f"{val:08b}"
            else: # DEC
                data_str = f"{val}"
            
            rows.append({'address': addr_str, 'data': data_str, 'raw_addr': addr})
        return rows

    def update_byte(self, address, new_value_str):
        """Parses user input string back to integer based on current view format."""
        try:
            val = 0
            clean_str = new_value_str.strip()
            if self.view_format == 'HEX':
                val = int(clean_str, 16)
            elif self.view_format == 'BIN':
                val = int(clean_str, 2)
            else:
                val = int(clean_str)
            
            # Clamp to byte size
            val = max(0, min(255, val))
            self.memory[address] = val
            return True
        except ValueError:
            return False # Invalid input

data_state = DataMemoryState()

# Continuous Execution Section
@dataclass
class ContinuousExecutionResult:
    executed: bool = False
    pipeline_status: PipelineStatus = None
    atomic_mem_transaction: AtomicMemTransaction = None

cont_exec_result = ContinuousExecutionResult()


# Step By Step Execution Section
@dataclass
class StepByStepExecutionState:
    current_step: int = 0
    pipeline_status: PipelineStatus = None
    changed_reg: Optional[tuple[str, str]] = None
    atomic_mem_transaction: Optional[AtomicMemTransaction] = None

    def reset(self):
        self.current_step = 0
        self.pipeline_status = None
        self.changed_reg = None
        self.atomic_mem_transaction = None  

    def update_step(self, new_status: PipelineStatus, transaction: AtomicMemTransaction):
        # Determine register changes
        self.changed_reg = None
        if self.pipeline_status:
            for old_entry, new_entry in zip(self.pipeline_status.register_file.entries, new_status.register_file.entries):
                if old_entry.value != new_entry.value:
                    self.changed_reg = (f"x{old_entry.reg_addr} ", f"changed from 0x{old_entry.value:08X} to 0x{new_entry.value:08X}")
                    break
        self.pipeline_status = new_status
        self.current_step += 1
        self.atomic_mem_transaction = transaction if transaction.occurred else None

step_by_step_state = StepByStepExecutionState()
