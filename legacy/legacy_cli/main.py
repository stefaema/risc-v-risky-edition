from nicegui import ui

@ui.page('/')
def main_page():
    # --- Configuration & Theme ---
    # This toggles the Quasar dark mode globally
    ui.dark_mode().enable()

    # Custom Styling (Optional: tweaking the 'dark' background color)
    ui.query('body').style('background-color: #121212; color: #e0e0e0;')

    # --- Header ---
    with ui.header().classes('items-center justify-between bg-slate-900'):
        ui.label('RISC-V Dashboard').classes('text-2xl font-bold')
        with ui.row():
            ui.button(icon='settings', on_click=lambda: left_drawer.toggle()).props('flat color=white')

    # --- Side Drawer ---
    with ui.left_drawer(value=False).classes('bg-slate-800') as left_drawer:
        ui.label('Project Settings').classes('text-lg mb-4')
        ui.switch('Enable Cache Simulation')
        ui.label('Clock Speed (MHz)')
        ui.slider(min=1, max=100, value=100)

    # --- Main Content Area ---
    with ui.column().classes('w-full items-center p-8'):
        with ui.card().classes('w-full max-w-2xl bg-slate-800 border-slate-700'):
            ui.label('System Status').classes('text-xl font-semibold text-blue-400')
            ui.separator().classes('bg-slate-700')
            
            with ui.row().classes('w-full justify-around'):
                with ui.column().classes('items-center'):
                    ui.icon('timer').classes('text-3xl text-white')
                    ui.label('WNS').classes('text-sm text-gray-400')
                    ui.label('0.521 ns').classes('text-lg font-bold text-white')
                with ui.column().classes('items-center'):
                    ui.icon('memory').classes('text-3xl text-white')
                    ui.label('LUTs').classes('text-sm text-gray-400')
                    ui.label('1,240').classes('text-lg font-bold text-white')
                with ui.column().classes('items-center'):
                    ui.icon('lock').classes('text-3xl text-green-400')
                    ui.label('Status').classes('text-sm text-gray-400')
                    ui.label('Locked').classes('text-lg font-bold text-green-400')

        # Example TUI-style terminal log
        with ui.log(max_lines=10).classes('w-full max-w-2xl h-40 bg-black text-green-500 font-mono text-xs mt-4'):
            ui.notify('System initialized at 100MHz')

# Start the server
ui.run(title='RISC-V Dev Tools', port=8080)
