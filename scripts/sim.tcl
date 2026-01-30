source ./scripts/utils.tcl
lassign $argv prj part top tb mode

setup_env $prj $part $top $tb

log_puts "info" "Launching Simulation for $tb"
set_property top $tb [get_filesets sim_1]
set_msg_config -id {Board 49-26} -suppress

launch_simulation
run all

log_puts "success" "Simulation of $tb finished."
