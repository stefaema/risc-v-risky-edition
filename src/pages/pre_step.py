from nicegui import ui, run
from state import app_state
from backend.executor import start_step_by_step_mode

async def handle_start():
    await run.io_bound(start_step_by_step_mode, app_state.port)
    ui.notify("Modo Paso a Paso Iniciado", type='positive')
    ui.navigate.to('/step-debug')

def content():
    with ui.column().classes('w-full h-full items-center justify-start gap-4 py-4'):
        ui.label("Modo Paso a Paso").classes('text-3xl text-slate-300 font-bold')
        ui.label("Instrucción por instrucción, observando el estado de los registros, memoria, pipeline y un modelo del CPU en cada paso.").classes('text-slate-400 text-lg text-center max-w-2xl')
        ui.button("Iniciar Ejecución Paso a Paso", on_click=handle_start).classes('bg-green-600 hover:bg-green-700 text-white text-2xl px-6 py-3 rounded')

