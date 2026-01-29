# scripts/program.tcl
open_hw_manager
connect_hw_server
open_hw_target

# Identificar la FPGA
set device [lindex [get_hw_devices] 0]
current_hw_device $device
refresh_hw_device -update_hw_probes false $device

# Cargar el bitstream (ajusta la ruta si cambiaste el nombre del top)
set_property PROGRAM.FILE {./work/basys3_test.runs/impl_1/top.bit} $device

program_hw_device $device
puts "FPGA Programada con éxito"
close_hw_manager
