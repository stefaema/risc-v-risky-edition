source ./scripts/utils.tcl
lassign $argv prj part top tb mode

log_puts "info" "Hardware Manager: Searching for target..."
open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target

set dev [lindex [get_hw_devices] 0]
current_hw_device $dev

set bit_file "work/$top/$prj.runs/impl_1/${top}.bit"

if {[file exists $bit_file]} {
    set_property PROGRAM.FILE $bit_file $dev
    program_hw_device $dev
    log_puts "success" "FPGA programmed successfully with $bit_file"
} else {
    log_puts "error" "Bitstream file not found: $bit_file"
    exit 1
}
