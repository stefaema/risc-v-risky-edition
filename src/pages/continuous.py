from nicegui import ui, run
from state import app_state, cont_exec_result, data_state
from backend.executor import execute_program
from typing import List, Set, Tuple
from backend.schemes import MemPatch
import logging

# --- Helper Logic for Memory Patching ---

def get_patched_memory(patch: MemPatch) -> Tuple[List[int], Set[int]]:
    """
    Takes an initial zeroed memory (256 words) and applies the MemPatch.
    Returns:
        - The full memory list (integers).
        - A set of indices (word indices) that were modified/patched.
    """

    # 1. Start with a copy of the original memory
    memory = data_state.memory.copy()
    modified_indices = set()

    if not patch:
        return memory, modified_indices

    # 2. Apply patch to get final memory state
    for addr, data in patch.memory_contents:
        word_index = addr // 4
        if 0 <= word_index < len(memory):
            memory[word_index] = data
            modified_indices.add(word_index)
            
    return memory, modified_indices

# --- UI Component Helpers ---

def ui_hex_box(label: str, value: int, highlight: bool = False):
    """Render a small box for a register or memory value."""
    bg_color = 'bg-green-700' if highlight else 'bg-slate-700'
    with ui.column().classes(f'{bg_color} p-2 rounded gap-0 items-center min-w-[80px]'):
        ui.label(label).classes('text-lg text-slate-300')
        ui.label(f'0x{value:08X}').classes('text-lg font-mono text-white font-bold')

def ui_kv_row(key: str, value):
    """Render a clean Key-Value row for pipeline status."""
    with ui.row().classes('w-full justify-between items-center py-1 border-b border-slate-700'):
        ui.label(key).classes('text-slate-400 text-xl')
        # Check if value is one of your Enums or Flags and cast to string
        val_str = str(value).replace('\n', ' ') 
        
        # Simple styling for Boolean/Flags
        color = 'text-green-400' if 'YES' in val_str or 'True' in val_str else 'text-white'
        if 'NO' in val_str: color = 'text-slate-500'
        
        ui.label(val_str).classes(f'font-mono text-lg {color} text-right')


async def start_execution():
    # 1. Provide immediate feedback in the UI
    ui.notify("Started RISC-V Execution")

    # 2. Run your EXISTING function in a separate thread
    port = app_state.port
    
    # run.io_bound runs 'execute_program(port)' in a background thread
    status, mem = await run.io_bound(execute_program, port)

    # 3. Once it returns (program ended), update the UI
    cont_exec_result.executed = True
    cont_exec_result.pipeline_status = status
    cont_exec_result.memory_patch = mem

    ui.notify("Execution Complete!", type='positive')

    main_window.refresh()

@ui.refreshable
def main_window():
    # 1. State: Empty / Initial
    if not cont_exec_result.executed:
        with ui.column().classes('w-full h-full justify-center items-center'):
            ui.icon('monitor').classes('text-8xl text-slate-700')
            ui.label('Presionar Botón para Ejecutar').classes('text-slate-500 text-5xl')
        return

    # Unpack the results for easier access
    status = cont_exec_result.pipeline_status
    mem_patch = cont_exec_result.memory_patch

    # 2. State: Results Display
    with ui.card().classes('w-full h-full bg-slate-900 border-none no-shadow p-0 flex flex-col'):
        
        # --- TABS HEADER ---
        with ui.tabs().classes('w-full text-white bg-slate-800 text-2xl') as tabs:
            t1 = ui.tab('Archivo de Registros')
            t2 = ui.tab('Estados del Pipeline')
            t3 = ui.tab('Memoria de Datos')

        # --- TAB CONTENTS ---
        with ui.tab_panels(tabs, value=t1).classes('w-full flex-grow bg-slate-900 text-white p-0'):
            
            # --- TAB 1: REGISTER FILE ---
            with ui.tab_panel(t1).classes('w-full h-full p-0'):
                with ui.scroll_area().classes('w-full h-full p-6'):
                    ui.label('Estado Final de Registros (GPRs)').classes('text-2xl mb-4 text-green-400')
                    
                    # Grid Layout for 32 Registers
                    with ui.grid(columns=4).classes('w-full gap-4'):
                        if status and status.register_file:
                            for entry in status.register_file.entries:
                                # Highlight Non-Zero registers for visibility
                                highlight = entry.value != 0
                                ui_hex_box(f"x{entry.reg_addr}", entry.value, highlight)
                        else:
                            ui.label("No Register Data Available").classes('text-red-400')

            # --- TAB 2: PIPELINE REGISTERS ---
            with ui.tab_panel(t2).classes('w-full h-full p-0'):
                 with ui.scroll_area().classes('w-full h-full p-6'):
                    if status:
                        # Helper to create a collapsible section
                        def pipeline_section(title, data_obj):
                            with ui.expansion(title, icon='settings_input_component').classes('w-full bg-slate-800 mb-2 text-white border border-slate-700 text-2xl').props('default-opened'):
                                with ui.column().classes('w-full p-4 gap-1'):
                                    # Iterate over fields in the dataclass
                                    for field_name, field_value in data_obj.__dict__.items():
                                        # Clean up field name (e.g., 'pc_write_en' -> 'Pc Write En')
                                        clean_name = field_name.replace('_', ' ').title()
                                        ui_kv_row(clean_name, field_value)

                        # Render Sections
                        pipeline_section("Hazards Status", status.hazard_status)
                        pipeline_section("IF / ID Register", status.if_id_status)
                        pipeline_section("ID / EX Register", status.id_ex_status)
                        pipeline_section("EX / MEM Register", status.ex_mem_status)
                        pipeline_section("MEM / WB Register", status.mem_wb_status)
                    else:
                        ui.label("No Pipeline Data").classes('text-red-400')

            # --- TAB 3: DATA MEMORY ---
            with ui.tab_panel(t3).classes('w-full h-full p-0'):
                 with ui.scroll_area().classes('w-full h-full p-6'):
                    ui.label('Memoria de Datos (Dump)').classes('text-2xl mb-4 text-blue-400')
                    
                    # 1. Calculate final memory state
                    final_mem, changed_indices = get_patched_memory(mem_patch)

                    # 2. Render Grid
                    # We render 8 words (32 bytes) per row
                    with ui.grid(columns=8).classes('w-full gap-2'):
                        for i, val in enumerate(final_mem):
                            addr = i * 4
                            is_modified = i in changed_indices
                            
                            # Visual Card for Memory Word
                            bg = 'bg-blue-900 border-blue-500' if is_modified else 'bg-slate-800 border-slate-700'
                            
                            with ui.column().classes(f'{bg} border p-2 rounded items-center'):
                                ui.label(f'0x{addr:04X}').classes('text-lg text-slate-400')
                                ui.label(f'{val:08X}').classes('text-lg font-mono text-white font-bold')


def content():
    # Main Container: Column, Full Screen, No Scroll on the body itself
    with ui.column().classes('w-full h-screen no-wrap gap-0 overflow-hidden bg-black'):
        
        # --- TOP SECTION: MAIN WINDOW ---
        # flex-grow: Takes all space NOT used by the bottom panel
        with ui.column().classes('w-full flex-grow overflow-hidden'):
            main_window()

        # --- BOTTOM SECTION: CONTROL PANEL ---
        # Fixed height (auto), different background to separate it visually
        with ui.row().classes('w-full h-auto bg-slate-800 border-t border-slate-600 p-4 items-center gap-4'):
            
            # App State binded Labels
            with ui.row().classes('flex-grow items-center gap-4'):
                ui.label(f"Fuente de Programa: {app_state.last_loaded_program}").classes('text-white text-2xl')
                ui.separator().props('vertical')
                ui.label(f"Fuente de Datos: {app_state.last_loaded_data}").classes('text-white text-2xl')
            # Execute Button
            ui.separator().props('vertical')
            
            with ui.button(on_click=start_execution).props('color=green icon=play_arrow'):
                ui.label('Ejecutar').classes('text-2xl text-white')
