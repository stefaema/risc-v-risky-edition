from pathlib import Path
import sys

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

import logging
from backend.loader import list_serial_ports
from state import app_state
from nicegui import app, ui
from routing import drawer_menu
from pages import home, instructions, data, continuous, step_debug, documentation, pre_step



ROUTES = {
    '/': ('home', 'Inicio', home.content),
    '/instructions': ('upload_file', 'Cargar Instrucciones', instructions.content),
    '/data': ('storage', 'Cargar Datos', data.content),
    '/continuous': ('play_arrow', 'Ejecutar Continuamente', continuous.content),
    '/pre_step': ('bug_report', 'Ejecutar Paso a Paso', pre_step.content),
    '/documentation': ('menu_book', 'Documentación', documentation.content),
    "/step-debug": (None, None, step_debug.content)
}


raw_logger = logging.getLogger('riscv.raw')
clean_logger = logging.getLogger('riscv.clean')

# Ensure they don't propagate to the root logger (prevents double logging to console)
raw_logger.propagate = False
clean_logger.propagate = False

class UiLogHandler(logging.Handler):
    def __init__(self, log_element: ui.log, replace: bool = False):
        super().__init__()
        self.log_element = log_element
        self.replace = replace
        # No timestamps, just the message
        self.setFormatter(logging.Formatter('%(message)s'))

    def emit(self, record):
        msg = self.format(record)
        if self.replace:
            # For "Replace" behavior, we clear and then push
            # Note: ui.log.clear() is available in recent NiceGUI versions
            self.log_element.clear()
            self.log_element.push(msg)
        else:
            # Standard append behavior
            self.log_element.push(msg)



def root():
    app.add_static_files('/img', 'img')
    app.add_static_files('/style', 'style')
    app.add_static_files('/svg','svg')
    ui.add_head_html('<link rel="stylesheet" href="style/patch.css">')

    # --- 1. Header ---
    with ui.header(elevated=False).classes('bg-black items-center justify-between px-6'):
        
        # --- Left Section (Title) ---
        with ui.column().classes('flex-1'):
            ui.label('FPGA RISC-V: CLIENTE').classes('text-xl font-bold tracking-tight')
        
        # --- Middle Section (Select + Icon) ---
        with ui.column().classes('flex-1 items-center'):
            # Group them in a row to keep them together
            with ui.row().classes('items-center gap-3 no-wrap'):
                
                ui.select(
                    options=list_serial_ports(),
                    label='Puerto COM UART',
                    on_change=lambda e: (setattr(app_state, 'port', e.value), drawer_menu.refresh())
                ).props('dark outlined text-xl').style('width: 300px') # Set a specific width so it doesn't stretch the whole page

                # The Info Icon is now right next to the select
                info_icon = ui.icon('info', color='white', size="xl").classes('cursor-help')
                
                @ui.refreshable
                def state_labels():
                    ui.label("COM: " + (app_state.port if app_state.port else "No seleccionado")).classes('text-xl text-gray-400 whitespace-nowrap')
                    ui.label(f'IMEM: {app_state.last_loaded_program}').classes('text-xl text-gray-400 whitespace-nowrap')
                    ui.label(f'DMEM: {app_state.last_loaded_data}').classes('text-xl text-gray-400 whitespace-nowrap')

                info_icon.on('mouseenter', lambda: state_labels.refresh())

                with info_icon:
                    with ui.tooltip().classes('p-2 bg-slate-800'):
                        state_labels()
        
        # --- Right Section (Empty placeholder to keep Middle Section centered) ---
        # We keep an empty flex-1 column so the Middle column stays perfectly centered
        with ui.column().classes('flex-1'):
            pass

    # --- 2. Left Drawer ---
    with ui.left_drawer(value=True).classes('bg-slate-800'):
        drawer_menu(ROUTES)


    # --- 3. Footer (Fixed at bottom) ---
    # We use a fixed height (e.g., 30vh) to ensure the math is stable
    with ui.footer().classes("h-[30vh] bg-slate-900 flex flex-col "):
            with ui.tabs().classes("m-0 p-0") as tabs:
                raw_tab = ui.tab('Raw', icon='sync_alt')
                clean_tab = ui.tab('Clean', icon='terminal')
            
            with ui.tab_panels(tabs, value=clean_tab).classes('w-full flex flex-col grow bg-black font-mono text-xl p-0 m-0 overflow-hidden'):
                with ui.tab_panel(raw_tab):
                    # This log will show Hex/Binary
                    raw_log = ui.log().classes('w-full grow text-green-500 overflow-auto') # Adjust padding to prevent scrollbar overlap
                with ui.tab_panel(clean_tab):
                    # This log will show formatted status
                    clean_log = ui.log().classes('w-full flex flex-col grow text-blue-300 overflow-auto')  # Adjust padding to prevent scrollbar overlap
            
    raw_logger.handlers.clear()
    clean_logger.handlers.clear()
    
    # Raw logger: Append mode
    raw_logger.addHandler(UiLogHandler(raw_log))
    # Clean logger: Append mode (or replace if you preferred)
    clean_logger.addHandler(UiLogHandler(clean_log))
    
    # Ensure levels are set
    raw_logger.setLevel(logging.INFO)
    clean_logger.setLevel(logging.INFO)

    with ui.column().classes('absolute-full bg-rgb(11, 10, 23) p-6 overflow-hidden'):
        # This wrapper takes all space between Header and Footer
        # 'overflow-auto' ensures that only THIS section scrolls if the cards are too many
        ui.sub_pages({route: info[2] for route, info in ROUTES.items()}).classes('w-full h-full overflow-auto')

# Start App
ui.run(root, title="RISC-V FPGA Suite", dark=True)
