# --- Argument Mapping ---
set project_name [lindex $argv 0]
set tb_top       [lindex $argv 3]
set work_dir     "work"

# --- Helper Procedure for Colored Output ---
proc color_puts {color text} {
    set reset "\033\[0m"
    switch $color {
        "green"  { set col "\033\[0;32m" }
        "blue"   { set col "\033\[0;36m" }
        "yellow" { set col "\033\[1;33m" }
        "red"    { set col "\033\[0;31m" }
        default  { set col "" }
    }
    puts "${col}${text}${reset}"
}

# --- Start Simulation Flow ---
color_puts "blue" "-------------------------------------------------------"
color_puts "blue" " STARTING SIMULATION: $tb_top"
color_puts "blue" "-------------------------------------------------------"

# --- Ignore Part Watnings ---
set_msg_config -id {Board 49-26} -suppress

# 1. Open existing project
if {[file exists ${work_dir}/${project_name}.xpr]} {
    open_project ${work_dir}/${project_name}.xpr
} else {
    color_puts "red" "ERROR: Project not found. Run 'build' first."
    exit 1
}

# 2. Add simulation files
color_puts "yellow" "Updating simulation fileset..."
add_files -fileset sim_1 [glob -nocomplain ./sim/*.v ./sim/*.sv]
update_compile_order -fileset sim_1

# 3. Set Testbench Top
set_property top $tb_top [get_filesets sim_1]

# 4. Launch Simulation
color_puts "yellow" "Launching Behavioral Simulation..."
launch_simulation

# 5. Run simulation (logs will show up in terminal)
color_puts "green" "Running simulation..."
run all

color_puts "blue" "-------------------------------------------------------"
color_puts "blue" " SIMULATION FINISHED"
color_puts "blue" "-------------------------------------------------------"
