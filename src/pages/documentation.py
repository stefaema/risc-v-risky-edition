from nicegui import ui
from state import loaded_document
from utils.file_loader import FileLoader, FileType

@ui.refreshable
def doc_viewer():
    if not loaded_document.filename:
        ui.label("Seleccione un archivo de la lista").classes('text-2xl p-4')
        return
    with open(loaded_document.filename, 'r', encoding='utf-8') as doc_file:
        content = doc_file.read()
    ui.markdown(content, extras=['mermaid']).classes('w-full h-full text-xl overflow-y-auto p-4 bg-black text-white rounded')


def commit_file_load(filename):
    loaded_document.filename = filename
    doc_viewer.refresh()
    ui.notify(f"Cargado: {filename}", type='positive')

from nicegui import ui

@ui.refreshable
def doc_viewer():
    if not loaded_document.filename:
        ui.label("Seleccione un archivo de la lista").classes('text-2xl p-4 text-white')
        return
    
    try:
        with open(loaded_document.filename, 'r', encoding='utf-8') as doc_file:
            content = doc_file.read()
        
        # Use scroll_area to wrap the markdown. 
        # 'flex-grow' ensures it takes up all available space in the card.
        with ui.scroll_area().classes('w-full flex-grow p-4'):
            ui.markdown(content).classes('text-xl text-white')
            
    except Exception as e:
        ui.label(f"Error al cargar: {e}").classes('text-red-500 p-4')

def content():

    # Use h-screen and overflow-hidden on the main row to prevent the whole page from scrolling
    with ui.row().classes('w-full h-screen no-wrap p-2 gap-4 overflow-hidden'):
        
        # LEFT SIDEBAR
        with ui.card().classes('w-1/4 h-full bg-slate-800 border-slate-700 flex-nowrap'):
            ui.label('Documentos').classes('text-2xl font-bold mb-4 text-white')
            
            # This scroll area handles the file list
            with ui.scroll_area().classes('w-full flex-grow'):
                for f in FileLoader.list_files(file_source=FileType.DOCUMENTATION): 
                    with ui.button(on_click=lambda f=f: commit_file_load(f)).classes('w-full justify-start text-lg border mb-2').props('flat color=white no-caps'):
                        ui.icon('description').classes('mr-2')
                        ui.label(f).classes('text-truncate')

        # RIGHT SIDE: markdown visor
        with ui.column().classes('w-3/4 h-full'):
            # Ensure the card itself is flex-col and overflow-hidden
            with ui.card().classes('w-full h-full bg-slate-900 p-0 overflow-hidden'):
                doc_viewer()
