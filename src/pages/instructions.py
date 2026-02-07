import os
from nicegui import ui
from utils.file_loader import FileLoader, FileType
from backend.assembler import assemble_file
from backend.loader import upload_to_fpga
from state import loaded_program_state, app_state
from routing import drawer_menu
# --- 1. MINIMAL STATE ---


# --- 2. THE DYNAMIC BLOCK ---
@ui.refreshable
def code_viewer():
    ui.code(loaded_program_state.content, language='asm').classes('w-full h-full text-lg')

# --- 3. THE "STREAM" LOGIC ---
def sync():
    if not loaded_program_state.filename or loaded_program_state.ready: return
    try:
        t = os.path.getmtime(loaded_program_state.filename)
        if t > loaded_program_state.mtime:
            _, loaded_program_state.content = FileLoader.load(loaded_program_state.display)
            loaded_program_state.mtime = t
            code_viewer.refresh() # Update the UI
    except: pass

def load(name):
    _, loaded_program_state.content = FileLoader.load(name)
    loaded_program_state.filename, loaded_program_state.display = name, name
    loaded_program_state.mtime = os.path.getmtime(loaded_program_state.filename)
    loaded_program_state.ready = False
    code_viewer.refresh()

def assemble():
    loaded_program_state.payload, loaded_program_state.machine_code = assemble_file(loaded_program_state.content)
    if loaded_program_state.machine_code:
        loaded_program_state.ready = True
        ui.notify("Success!", type='positive')
    else:
        ui.notify("Assembly failed", type='negative')

def commit_fpga_upload():
    if loaded_program_state.payload:
        upload_to_fpga(loaded_program_state.payload, is_instruction=True)
        ui.notify("Sent to FPGA", type='positive')
        app_state.last_loaded_program = loaded_program_state.filename.split("/")[-1]
        drawer_menu.refresh()
    else:
        ui.notify("No payload to send", type='warning')

# --- 4. THE LAYOUT ---
def content():
    ui.timer(1.0, sync) # Watch for VS Code saves

    with ui.row().classes('w-full h-full no-wrap p-2 gap-4'):
        # LEFT SIDEBAR (Morphing)
        with ui.card().classes('w-1/4 h-full bg-slate-800 border-slate-700'):
            
            # SIDE A: FILE LIST
            with ui.column().classes('w-full h-full overflow-y-auto flex-none').bind_visibility_from(loaded_program_state, 'ready', backward=lambda x: not x):
                ui.label('Programas').classes('text-xl font-bold mb-4')
                for f in FileLoader.list_files(file_source=FileType.INSTRUCTION):
                    with ui.button(on_click=lambda f=f: load(f)).classes('flex-none w-full p-5 justify-start text-lg border').props('flat color=white no-caps'):
                        ui.icon('file_open').classes('mr-2')
                        ui.label(f).classes('text-lg')

            # SIDE B: LOADER
            with ui.column().classes('w-full h-full justify-center items-center gap-4').bind_visibility_from(loaded_program_state, 'ready'):
                ui.icon('memory', color='white').classes("text-9xl")
                ui.button('SEND TO FPGA', on_click=lambda: commit_fpga_upload()).classes('bg-blue-600 w-full text-xl')
                ui.button('Back', on_click=lambda: setattr(loaded_program_state, 'ready', False)).props('flat').classes('text-lg')

        # RIGHT SIDE: EDITOR
        with ui.column().classes('w-3/4 h-full'):
            with ui.card().classes('w-full h-full bg-slate-900 p-0 overflow-hidden'):
                code_viewer() # Initial render
            
            ui.button('Ensamblar', icon='extension', on_click=assemble) \
                .classes('w-full font-bold').props('size=lg')
                
