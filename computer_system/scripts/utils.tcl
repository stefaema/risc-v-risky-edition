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

    # 2. Create or Sync Project
    log_puts "info" "Setting up project environment for $prj"

    if {[file exists $prj_dir/$prj.xpr]} {
        log_puts "info" "Syncing existing project: $prj"
        open_project $prj_dir/$prj.xpr
        
        remove_files [get_files] -quiet
    } else {
        log_puts "info" "Creating fresh project for chip: $part"
        file mkdir $prj_dir
        create_project $prj $prj_dir -part $part -force
    }

    # 3. Add Sources from ./src directory
    log_puts "info" "Adding Sources from ./src"

    if {[file isdirectory "./src"]} { add_files -quiet ./src }
    if {[file isdirectory "./sim"]} { add_files -fileset sim_1 -quiet ./sim }
    
    # 4. Add IP Cores from ./ip directory
    log_puts "info" "Checking for IP Cores in ./ip and adding if present"

    if {[file isdirectory "./ip"]} {
            log_puts "info" "Adding IP Cores from ./ip"
            # Find all .xci files in the ip directory
            set ip_files [glob -nocomplain "./ip/*.xci"]
            
            if {$ip_files != ""} {
                add_files -quiet $ip_files
                
                # Optional: Force generation of IP targets (Synthesis/Simulation products)
                # This ensures the IP is ready for the next steps.
                foreach ip $ip_files {
                    set ip_name [file rootname [file tail $ip]]
                    # Check if the IP is locked (needs upgrade)
                    set locked [get_property IS_LOCKED [get_ips $ip_name]]
                    if {$locked} {
                        log_puts "warn" "Upgrading IP: $ip_name"
                        upgrade_ip [get_ips $ip_name]
                    }
                    # Generate output products (Synthesis, Simulation, Instantiation Template)
                    generate_target all [get_ips $ip_name]
                }
            } else {
                log_puts "warn" "IP directory exists but contains no .xci files."
            }
        }
    

    # 5. Add Simulation sources from ./sim directory
    log_puts "info" "Adding Simulation Sources from ./sim if present"
    if {[file isdirectory "./sim"]} { 
        add_files -fileset sim_1 -quiet ./sim 
    }


    # 6. Add Constraints 
    log_puts "info" "Adding Constraints"
    if {[file exists $specific_xdc]} {
        add_files -quiet $specific_xdc
    }

    # 7. Final Setup
    log_puts "info" "Finalizing Project Setup"
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
