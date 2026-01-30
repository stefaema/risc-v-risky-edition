# -----------------------------------------------------------------------------
# Utility Functions for Vivado Automation (Basys3 Optimized)
# -----------------------------------------------------------------------------

proc log_puts {level text} {
    set level_key [string tolower $level]
    set level_display [string toupper $level_key]

    # Define colors
    array set cols {info "0;36" success "0;32" warn "1;33" error "0;31"}
    
    # Get the filename of the current script
    set script_name [file tail [info script]]

    # Format: [level] @ script.tcl:line: msg
    puts "\033\[$cols($level_key)m\[$level_display\] @ $script_name: $text\033\[0m"
}

proc setup_env {prj part top tb} {
    set prj_dir "work/$top"
    set specific_xdc "./constraints/${top}.xdc"

    # 1. Silence the "Board" warnings specifically
    set_msg_config -id {Project 1-5713} -suppress ;# Board part not found
    set_msg_config -id {Board 49-26} -suppress    ;# Board initialization

    if {[file exists $prj_dir/$prj.xpr]} {
        log_puts "info" "Syncing existing project: $prj"
        open_project $prj_dir/$prj.xpr
        
        # This is the "Magic" to stop the Missing File warnings
        # It removes the internal references before we re-add them
        remove_files [get_files] -quiet
    } else {
        log_puts "info" "Creating fresh project for chip: $part"
        file mkdir $prj_dir
        create_project $prj $prj_dir -part $part -force
    }

    # 2. Add Sources
    if {[file isdirectory "./src"]} { add_files -quiet ./src }
    if {[file isdirectory "./sim"]} { add_files -fileset sim_1 -quiet ./sim }
    
    # 3. Add Constraints (This is crucial when not using Board Parts)
    if {[file exists $specific_xdc]} {
        add_files -quiet $specific_xdc
    }

    # 4. Final Setup
    set_property top $top [current_fileset]
    set_property top $tb [get_filesets sim_1]
    update_compile_order -fileset sources_1
}

proc run_step {name run_obj} {
    log_puts "info" "Starting Flow: $name"

    if {[get_runs -quiet $run_obj] != ""} {
        reset_run $run_obj
    }

    launch_runs $run_obj -jobs 8
    wait_on_run $run_obj

    if {[get_property PROGRESS [get_runs $run_obj]] != "100%"} {
        log_puts "error" "$name failed to complete."
        exit 1
    }
    log_puts "success" "$name completed successfully."
}
