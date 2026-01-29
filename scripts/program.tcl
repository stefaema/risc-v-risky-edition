# --- Argument Mapping ---
set project_name [lindex $argv 0]
set top_module   [lindex $argv 2]

# --- Helper Procedure for Colored Output ---
proc color_puts {color text} {
    set reset "\033\[0m"
    switch $color {
        "green"  { set col "\033\[0;32m" }
        "yellow" { set col "\033\[1;33m" }
        "red"    { set col "\033\[0;31m" }
        default  { set col "" }
    }
    puts "${col}${text}${reset}"
}

# --- Start Programming Flow ---
color_puts "yellow" "Connecting to Hardware Server..."

open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target

# Identify the FPGA Device
set device [lindex [get_hw_devices] 0]
current_hw_device $device
refresh_hw_device -update_hw_probes false $device

# Define the bitstream path based on project structure
set bitstream_path "./work/${project_name}.runs/impl_1/${top_module}.bit"

if {[file exists $bitstream_path]} {
    color_puts "yellow" "Programming device with: $bitstream_path"
    set_property PROGRAM.FILE $bitstream_path $device
    program_hw_device $device
    color_puts "green" "-------------------------------------------------------"
    color_puts "green" " SUCCESS: FPGA Programmed successfully."
    color_puts "green" "-------------------------------------------------------"
} else {
    color_puts "red" "ERROR: Bitstream file not found at $bitstream_path"
    exit 1
}

close_hw_manager
