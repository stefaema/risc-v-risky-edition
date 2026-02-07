import os
from nicegui import ui
from utils.file_loader import FileLoader, FileType # Assuming FileType.DATA exists or we use a generic filter
from backend.loader import upload_to_fpga
from state import data_state, app_state
from routing import drawer_menu

# ---  THE DYNAMIC EDITOR ---
grid: ui.aggrid = None # Forward declaration

def handle_cell_edit(e):
    """Callback when a cell is edited in the grid."""
    row_index = e.args['data']['raw_addr']
    new_value = e.args['newValue']
    
    success = data_state.update_byte(row_index, new_value)
    
    if not success:
        ui.notify(f"Invalid {data_state.view_format} value", type='negative')
        # Revert changes visually by reloading the specific row or whole grid
        update_grid_view() 

def update_grid_view():
    """Refreshes the grid display without losing scroll position."""
    if grid:
        grid.options['rowData'] = data_state.get_formatted_data()
        grid.update()

def change_format(value):
    data_state.view_format = value
    update_grid_view()

# ---  LOGIC & IO ---
def load_file(name):
    """Loads a file from source into the memory state."""
    try:

        content = (FileLoader.load(name)[1])  # Get raw bytes
            
        # Fill memory (truncate or pad to 256)
        for i in range(256):
            if i < len(content):
                data_state.memory[i] = int(content[i]["value"], 16)  # Assuming content is list of dicts with 'value' keys
            else:
                data_state.memory[i] = 0
                
        data_state.filename = name # Auto-fill save name
        data_state.ready = True    # Switch sidebar view if needed
        update_grid_view()
        ui.notify(f"Loaded {name}", type='positive')
    except Exception as e:
        ui.notify(f"Error loading file: {str(e)}", type='negative')

def save_file():
    """Saves current state to a binary file."""
    if not data_state.filename:
        ui.notify("Please enter a filename", type='warning')
        return

    try:
        # Ensure .bin extension
        fname = data_state.filename if data_state.filename.endswith('.bin') else f"{data_state.filename}.bin"
        fname = "riscv_data/"+fname if fname.startswith("riscv_data/") == False else fname
        # Convert to bytearray (Python bytes are already appropriate for 'little endian' byte stream)
        payload = bytearray(data_state.memory)
        
        with open(fname, 'wb') as f:
            f.write(payload)
            
        ui.notify(f"Saved to {fname}", type='positive')
        # Refresh file list logic if needed
    except Exception as e:
        ui.notify(f"Save failed: {str(e)}", type='negative')

def send_to_fpga():
    """Sends the bytearray to the backend."""
    payload = bytearray(data_state.memory)

    result = upload_to_fpga(payload, is_instruction=False) 

    if result and payload and not data_state.filename:
        data_state.filename = "riscv_data/temporal_unsaved_data.bin"
 
    app_state.last_loaded_data = data_state.filename.split('/')[-1]

    drawer_menu.refresh()
    ui.notify("Sent to FPGA", type='positive')


# --- 4. THE LAYOUT ---
def content():
    with ui.row().classes('w-full h-screen no-wrap p-2 gap-4'):
        
        # LEFT SIDEBAR
        with ui.card().classes('w-1/4 h-full bg-slate-800 border-slate-700 column'):
            ui.label('Archivos Binarios').classes('text-2xl font-bold mb-4 text-white')
            
            with ui.scroll_area().classes('w-full flex-grow'):
                for f in FileLoader.list_files(file_source=FileType.DATA): 
                    with ui.button(on_click=lambda f=f: load_file(f)).classes('w-full justify-start text-lg border mb-2').props('flat color=white no-caps'):
                        ui.icon('description').classes('mr-2')
                        ui.label(f).classes('text-truncate')

        # RIGHT SIDE: VISOR & CONTROLS
        with ui.column().classes('w-3/4 h-full'):
            with ui.card().classes('w-full flex-grow flex-col bg-slate-900 p-0 overflow-hidden'):
                global grid
                grid = ui.aggrid({
                    'columnDefs': [
                        {'headerName': 'Address', 'field': 'address'},
                        {'headerName': 'Data', 'field': 'data', 'editable': True},
                    ],
                    'rowData': data_state.get_formatted_data(),

                }).classes('w-full h-full color-white text-xl') \
                  .on('cellValueChanged', handle_cell_edit)

            # CONTROL PANEL
            with ui.card().classes('w-full bg-slate-800 border-slate-700 p-4'):
                with ui.row().classes('w-full items-center justify-between'):
                    
                    # Radials for Format
                    with ui.row().classes('items-center'):
                        ui.label('Display Format:').classes('text-white font-bold mr-2')
                        ui.radio(['HEX', 'BIN', 'DEC'], value=data_state.view_format, on_change=lambda e: change_format(e.value)) \
                            .props('inline color=blue-500 dark')

                    # File Operations
                    with ui.row().classes('items-center gap-4'):
                        name_input = ui.input(label='Filename (.bin)', placeholder='data_mem') \
                            .bind_value(data_state, 'filename') \
                            .props('dark dense outlined') \
                            .classes('w-48')

                        ui.button('GUARDAR ARCHIVO', icon='save', on_click=save_file) \
                            .bind_enabled_from(data_state, 'filename') \
                            .classes('bg-green-600')

                        ui.button('ENVIAR A FPGA', icon='memory', on_click=send_to_fpga) \
                            .classes('bg-blue-600')
