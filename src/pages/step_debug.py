import json
import os
import re
from nicegui import ui, run, events
from dataclasses import dataclass, field
from typing import List, Tuple, Optional
from state import step_by_step_state as step_state
from state import data_state, app_state
from backend.executor import perform_step as backend_perform_step
from backend.cpu_model import cpu_model
import random
from backend.schemes import PipelineStatus, AtomicMemTransaction, MemoryWriteMask




try:
    with open("svg/risc-v-diagram.svg", 'r', encoding='utf-8') as f:
        svg_content = f.read()
except Exception as e:
    print(f"Error loading SVG: {e}")
    svg_content = '<svg><text x="20" y="20" fill="red">Error loading SVG</text></svg>'


async def perform_step():
    """
    1. Calls the executor in step mode, which returns the new pipeline status and memory transaction.
    2. Updates the simulated Memory, Pipeline Status and Step State accordingly.
    3. Triggers refreshes on the relevant UI components.
    """
    # If first
    if step_state.current_step == 0:
        initial_memory = {addr: val for addr, val in enumerate(data_state.memory)}
        cpu_model.reset(initial_memory=initial_memory)

    # If last
    if step_state.pipeline_status and step_state.pipeline_status.hazard_status.program_ended.value:
        step_state.reset()
        ui.navigate.to('/pre_step')
        return

    pipeline_status, transaction = await run.io_bound(backend_perform_step, app_state.port)
    
    cpu_model.perform_memory_transaction(transaction) # CPU handles un-occured transactions as NOPs, so we can call this every step without checking if it's None.
    step_state.update_step(pipeline_status, transaction)

    if step_state.pipeline_status.hazard_status.program_ended.value:
        ui.notify("Programa ha terminado. Se reiniciará el estado el próximo paso.", color='green')
    else:
        ui.notify("Paso ejecutado. Actualizando estado...", color='blue', position='top-right', timeout=300)

    try:
        group_data = cpu_model.return_group_string_dict(pipeline_status)
        # We push the data to a global window variable named 'svgData'
        ui.run_javascript(f"window.svgData = {json.dumps(group_data)};")
    except Exception as e:
        import traceback
        traceback.print_exc()
        print(f"Error updating SVG data: {e}")
    
    top_bar_info.refresh()
    register_grid.refresh()
    memory_list.refresh()
    pipeline_info.refresh()

# --- UI COMPONENTS ---

def ui_hex_box(label: str, value: int, highlight: bool = False):
    """Render a single register/memory cell."""
    bg_color = 'bg-green-900 border-green-500' if highlight else 'bg-slate-800 border-slate-700'
    text_color = 'text-green-300' if highlight else 'text-slate-400'
    
    with ui.column().classes(f'{bg_color} border p-2 rounded items-center justify-center w-full'):
        ui.label(label).classes(f'{text_color} text-xs uppercase font-bold text-xl')
        ui.label(f'0x{value:08X}').classes('text-white font-mono text-xl')

def ui_kv_row(key: str, value: any):
    """Render a Key-Value row for pipeline details."""
    with ui.row().classes('w-full justify-between items-center border-b border-slate-700 py-1'):
        ui.label(key).classes('text-slate-400 text-lg')
        val_str = str(value).replace('\n', ' ') 
        
        # Simple styling for Boolean/Flags
        color = 'text-green-400' if 'YES' in val_str or 'True' in val_str else 'text-white'
        if 'NO' in val_str: color = 'text-slate-500'
        
        ui.label(val_str).classes(f'font-mono text-lg {color} text-right')

# --- REFRESHABLEs ---

# --- REFRESHABLE COMPONENTS ---

@ui.refreshable
def register_grid():
    with ui.grid(columns=4).classes('w-full gap-3'):
        for i in range(32):
            reg_name = f"x{i}"
            reg_val = step_state.pipeline_status.register_file.entries[i].value if step_state.pipeline_status else 0
            
            # Use .strip().lower() to ensure a clean comparison
            highlight = False
            if step_state.changed_reg:
                clean_changed = str(step_state.changed_reg[0]).strip().lower()
                clean_name = reg_name.strip().lower()
                highlight = clean_changed == clean_name
            
                
            ui_hex_box(reg_name, reg_val, highlight=highlight)

@ui.refreshable
def memory_list():
    # Transform the memory list into the format AG Grid expects
    rows = []
    for addr, val in cpu_model.data_memory.get_memory_snapshot().items():
        rows.append({
            'address': f"0x{addr:08X}", 
            'data': f"0x{val:08X}"  # Formatted as 32-bit hex
        })

    # Contain it in a column and recreate the styling
    with ui.column().classes('w-full h-full p-4'):
        with ui.card().classes('w-full flex-grow flex-col bg-slate-900 p-0 overflow-hidden'):
            ui.aggrid({
                'columnDefs': [
                    {'headerName': 'Address', 'field': 'address', 'sortable': False},
                    {'headerName': 'Data', 'field': 'data', 'editable': False}, # Read-only
                ],
                'rowData': rows,
            }).classes('w-full h-[800px] color-white text-xl')

@ui.refreshable
def pipeline_info():
    # Fetch the current state (assuming status is available globally or via your state object)
    status = step_state.pipeline_status 

    if not status:
        ui.label("No Pipeline Data").classes('text-red-400 p-4')
        return

    # Inner helper to recreate the 'nice' expansion styling
    def pipeline_section(title, data_obj):
        # We use the exact styling and props from your snippet
        expansion = ui.expansion(title, icon='settings_input_component') \
            .classes('w-full bg-slate-800 mb-2 text-white border border-slate-700 text-2xl') \
            .props('default-opened')
        
        with expansion:
            with ui.column().classes('w-full p-4 gap-1'):
                # Iterate over dataclass fields and clean up names
                for field_name, field_value in data_obj.__dict__.items():
                    clean_name = field_name.replace('_', ' ').title()
                    ui_kv_row(clean_name, field_value)

    # Recreate the pipeline hierarchy
    pipeline_section("Hazards Status", status.hazard_status)
    pipeline_section("IF / ID Register", status.if_id_status)
    pipeline_section("ID / EX Register", status.id_ex_status)
    pipeline_section("EX / MEM Register", status.ex_mem_status)
    pipeline_section("MEM / WB Register", status.mem_wb_status)


from nicegui import ui

def processor_model_svg():
    # 1. Prepare SVG
    inner_svg = re.search(r'<svg[^>]*>(.*)</svg>', svg_content, re.DOTALL)
    cleaned_svg = inner_svg.group(1) if inner_svg else svg_content
    cleaned_svg = re.sub(r'<title.*?>.*?</title>', '', cleaned_svg, flags=re.DOTALL)
    # Tooltip element with unique class
    ui.label('').classes(
        'my-custom-tooltip absolute bg-slate-900 text-white p-2 rounded shadow-2xl '
        'border border-blue-500/50 pointer-events-none z-[100] text-md '
        'whitespace-pre-wrap font-mono'
    ).style('display: none; position: fixed;')

    with ui.element('div').classes('w-full h-full overflow-auto bg-black relative p-6'):
        ui.html(f'''
            <svg id="cpu-svg-diagram" viewBox="0 0 842 595" style="width: 120vw; height: auto; display: block;">
                {cleaned_svg}
            </svg>
        ''').classes('w-full')

    # 2. Updated JavaScript Logic
    ui.run_javascript("""
        // We look for the tooltip inside the event to ensure it exists
        const getTooltip = () => document.querySelector('.my-custom-tooltip');

        document.addEventListener('mouseover', (e) => {
            const group = e.target.closest('g');
            const tt = getTooltip();
            
            if (group && tt && window.svgData && window.svgData[group.id]) {
                tt.textContent = window.svgData[group.id];
                tt.style.display = 'block';
                group.style.filter = 'brightness(1.5)';
            }
        });

        document.addEventListener('mousemove', (e) => {
            const tt = getTooltip();
            if (tt && tt.style.display === 'block') {
                tt.style.left = (e.clientX + 20) + 'px';
                tt.style.top = (e.clientY + 20) + 'px';
            }
        });

        document.addEventListener('mouseout', (e) => {
            const group = e.target.closest('g');
            const tt = getTooltip();
            if (group) {
                if (tt) tt.style.display = 'none';
                group.style.filter = '';
            }
        });
    """)

# --- UPDATED REFRESHABLE WRAPPERS ---

@ui.refreshable
def top_bar_info():
    """Refreshes cycle count and the green/yellow badges at the top."""
    with ui.row().classes('items-center gap-4'):  
        # Register Alert
        if step_state.changed_reg:
            with ui.row().classes('items-center gap-2 bg-slate-900 px-3 py-1 rounded border border-slate-600'):
                ui.icon('edit').classes('text-green-400')
                ui.label(str(step_state.changed_reg[0])+" "+step_state.changed_reg[1]).classes('text-green-400 font-mono')
        
        # Memory Alert
        if step_state.atomic_mem_transaction and step_state.atomic_mem_transaction.occurred:
             with ui.row().classes('items-center gap-2 bg-slate-900 px-3 py-1 rounded border border-slate-600'):
                ui.icon('memory').classes('text-blue-400')
                ui.label(step_state.atomic_mem_transaction.cmpct_str()).classes('text-blue-400 font-mono')

        ui.label(f"Ciclo: {step_state.current_step}").classes('text-slate-400 font-mono text-lg px-2')

# --- MAIN PAGE LAYOUT ---

def content():
    """
    Static layout scaffold. 
    This function runs ONCE and defines the UI structure.
    """
    with ui.column().classes('w-full h-screen no-wrap gap-0 overflow-hidden bg-black'):
        
        # 1. HEADER (Static Bar + Dynamic Info)
        with ui.row().classes('w-full h-auto bg-slate-800 border-b border-slate-600 p-2 items-center justify-between'):
            with ui.row().classes('items-center gap-4'):
                # Tabs (Static - we don't want these to reset every step)
                with ui.tabs().classes('text-white bg-slate-700 rounded-lg') as tabs:
                    t_regs = ui.tab('Registros')
                    t_mem = ui.tab('Memoria')
                    t_pipe = ui.tab('Pipeline')
                    t_model = ui.tab('Modelo')
                
                ui.separator().props('vertical')
                
                # Control Button (Static)
                ui.button('Paso Siguiente', icon='play_arrow', on_click=perform_step).props('color=blue')
            
            # Dynamic Alerts (Refreshable)
            top_bar_info()

        # 2. MAIN AREA
        with ui.column().classes('w-full flex-grow bg-black overflow-hidden'):
            with ui.tab_panels(tabs, value=t_regs).classes('w-full h-full bg-transparent text-white'):
                
                # PANEL: REGISTERS
                with ui.tab_panel(t_regs).classes('w-full h-full p-0'):
                    with ui.scroll_area().classes('w-full h-full p-6'):
                        ui.label('Banco de Registros (GPRs)').classes('text-xl text-slate-300 mb-4')
                        register_grid() # Only the grid inside refreshes

                # PANEL: MEMORY
                with ui.tab_panel(t_mem).classes('w-full h-full p-0'):
                    with ui.scroll_area().classes('w-full h-full p-6'):
                        ui.label('Memoria de Datos').classes('text-xl text-slate-300 mb-4')
                        memory_list()

                # PANEL: PIPELINE
                with ui.tab_panel(t_pipe).classes('w-full h-full p-0'):
                    with ui.scroll_area().classes('w-full h-full p-6'):
                        ui.label('Estado de Etapas').classes('text-xl text-slate-300 mb-4')
                        pipeline_info()

                # PANEL: MODEL (SVG)
                with ui.tab_panel(t_model).classes('w-full h-full p-0'):
                    # This only refreshes if you call processor_model_svg.refresh()
                    processor_model_svg()
