# --- Argument Mapping ---
# argv 0: project_name, 1: part, 2: top_module, 3: tb_top
set project_name [lindex $argv 0]
set part         [lindex $argv 1]
set top_module   [lindex $argv 2]
set output_dir   "work"

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

# --- Start Build Flow ---
color_puts "blue" "-------------------------------------------------------"
color_puts "blue" " STARTING BUILD FLOW: $project_name"
color_puts "blue" "-------------------------------------------------------"

# 1. Setup Project
file mkdir $output_dir
create_project $project_name $output_dir -part $part -force

# 2. Add Source Files
color_puts "yellow" "Adding design sources and constraints..."
add_files [glob -nocomplain ./src/*.v ./src/*.sv]
add_files -fileset constrs_1 [glob -nocomplain ./constraints/*.xdc]

# 3. Set Top Module
set_property top $top_module [current_fileset]
update_compile_order -fileset sources_1

# 4. Run Synthesis
color_puts "yellow" "Running Synthesis..."
launch_runs synth_1 -jobs 4
wait_on_run synth_1

if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    color_puts "red" "ERROR: Synthesis failed!"
    exit 1
}

# 5. Run Implementation & Bitstream Generation
color_puts "yellow" "Running Implementation and Generating Bitstream..."
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    color_puts "red" "ERROR: Implementation failed!"
    exit 1
}

color_puts "green" "-------------------------------------------------------"
color_puts "green" " SUCCESS: Bitstream generated successfully."
color_puts "green" "-------------------------------------------------------"
