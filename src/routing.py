from nicegui import ui
from state import app_state

@ui.refreshable
def drawer_menu(ROUTES):
    with ui.list().classes('w-full text-white'):
        for route, (icon, label, _) in ROUTES.items():
            # Define access logic
            is_enabled = True
            
            if route in ['/instructions', '/data']:
                is_enabled = app_state.is_ready_for_upload()
            elif route in ['/continuous', '/pre_step']:
                is_enabled = app_state.is_ready_for_execution()
            
            if (icon, label) == (None, None):
                # Don't render a menu item for routes without an icon/label (like the step-debug route)
                continue

            # Render item based on status
            if is_enabled:
                with ui.item(on_click=lambda r=route: ui.navigate.to(r)).props('clickable v-ripple').classes('py-4 border-b border-slate-700'):
                    with ui.item_section().props('avatar'):
                        ui.icon(icon).classes('text-5xl text-white')
                    with ui.item_section():
                        ui.label(label).classes('text-xl font-medium')
            else:
                # Disabled look: No click handler, lower opacity
                with ui.item().classes('py-4 border-b border-slate-700 opacity-30 cursor-not-allowed'):
                    with ui.item_section().props('avatar'):
                        ui.icon(icon, color='grey').classes('text-5xl')
                    with ui.item_section():
                        ui.label(f"{label} (Bloqueado)").classes('text-xl font-medium text-gray-500')
