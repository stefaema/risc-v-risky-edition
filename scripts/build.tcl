# scripts/build.tcl
set project_name "basys3_test"
set part "xc7a35tcpg236-1"
set output_dir "work"

# Crear directorio de trabajo si no existe
file mkdir $output_dir

# Crear proyecto en memoria
create_project $project_name $output_dir -part $part -force

# Añadir archivos (Busca todos los .v en src y .xdc en constraints)
add_files [glob ./src/*.v]
add_files -fileset constrs_1 [glob ./constraints/*.xdc]

# Iniciar Síntesis
launch_runs synth_1 -jobs 4
wait_on_run synth_1

# Iniciar Implementación y Generar Bitstream
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

puts "Bitstream generado con éxito"
