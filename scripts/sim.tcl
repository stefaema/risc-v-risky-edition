# scripts/sim.tcl
set project_name "basys3_test"
set work_dir "work"

# 1. Abrir el proyecto existente
open_project ${work_dir}/${project_name}.xpr

# 2. Añadir archivos de simulación al conjunto de archivos de simulación (sim_1)
# Esto asegura que no intenten "cargarse" en la FPGA real
add_files -fileset sim_1 [glob ./sim/*.v]
update_compile_order -fileset sim_1

# 3. Configurar cuál es el testbench principal
set_property top top_tb [get_filesets sim_1]

# 4. Lanzar simulación en modo batch (consola)
launch_simulation

# 5. Correr la simulación
run all
