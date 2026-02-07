from nicegui import ui, app

def content():
    
    bg_style = (
            'background-image: linear-gradient(rgba(30, 41, 59, 0.8), rgba(30, 41, 59, 0.8)), '
            'url("img/bg-image.jpg"); '
            'background-size: cover; '
            'background-position: center;'
        )    
    with ui.card().classes('w-full h-full p-6 bg-slate-800 shadow-lg').style(bg_style):
        ui.label('1. Elegir Puerto COM UART').classes('text-xl font-bold mb-4 w-full')
        ui.label('Seleccione el puerto COM al que está conectado el dispositivo RISC-V.').classes('text-lg mb-4 w-full')
        
        ui.label('2. Cargue la Memoria de Instrucciones').classes('text-lg font-bold mb-4 w-full mt-8')
        ui.label('Cargue las instrucciones al dispositivo en la sección "cargar instrucciones"').classes('text-lg mb-4 w-full')
        
        ui.label('3. Cargue opcionalmente la Memoria de Datos').classes('text-lg font-bold mb-4 w-full mt-8')
        ui.label('Cargue los datos al dispositivo en la sección "cargar datos"').classes('text-lg mb-4 w-full')
        
        ui.label('4. Inicie la Ejecución').classes('text-lg font-bold mb-4 w-full mt-8')
        ui.label('Eliga el modo de ejecución: continuo o paso a paso.').classes('text-lg mb-4 w-full')
        
        # Spacer to push everything up if you want, or just leave it
        ui.element('div').classes('grow')
