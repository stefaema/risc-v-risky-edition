source ./scripts/utils.tcl
lassign $argv prj part top tb mode

setup_env $prj $part $top $tb

# Step 1: Synthesis
run_step "Synthesis" synth_1

# Step 2: Implementation (Conditional)
if {$mode == "impl" || $mode == "bitstream"} {
    run_step "Implementation" impl_1
    open_run impl_1
    set slack [get_property SLACK [get_timing_paths -setup]]
    log_puts "info" "Timing Closure Slack: ${slack}ns"
}

# Step 3: Bitstream (Conditional)
if {$mode == "bitstream"} {
    log_puts "info" "Generating Bitstream..."
    set_property SEVERITY {Warning} [get_drc_checks {NSTD-1 UCIO-1}]
    launch_runs impl_1 -to_step write_bitstream -jobs 8
    wait_on_run impl_1
}
