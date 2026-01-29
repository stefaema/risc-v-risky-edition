This is a great way to work. Using VS Code with TerosHDL for editing and Vivado’s TCL mode for building gives you a professional, lightweight, and version-control-friendly workflow.

Here is a step-by-step guide to setting up a **Basys 3** project entirely from VS Code and the console.

### 1. Prerequisites
*   **Vivado** installed and in your system `PATH` (so you can type `vivado` in a terminal).
*   **VS Code** installed.
*   **TerosHDL** extension installed in VS Code.

### 2. Folder Structure
Create a clean folder for your project. Do not dump everything in one place. A standard structure looks like this:

```text
/My_Basys3_Project
  ├── /src             # Your Verilog/SystemVerilog/VHDL files
  ├── /constraints     # Your .xdc file (Constraints)
  ├── /scripts         # TCL scripts to build the project
  └── /work            # (Created automatically) Vivado project output
```

### 3. Get the Constraints File
The Basys 3 requires a specific `.xdc` file to map your code to the board's pins (LEDs, switches, etc.).
1.  Download the **Basys-3-Master.xdc** from the [Digilent GitHub](https://github.com/Digilent/Digilent-XDCR/blob/master/Basys-3-Master.xdc).
2.  Place it in your `/constraints` folder.
3.  **Important:** Uncomment the lines for the ports you are using (e.g., `clk`, `led[0]`, etc.) and ensure the names match your top-level module ports.

### 4. The Build Script (`build.tcl`)
Create a file named `build.tcl` inside the `/scripts` folder. This script tells Vivado to create a project, import your files, and generate a bitstream.

Copy and paste this script:

```tcl
# scripts/build.tcl

# 1. Settings
set project_name "basys3_project"
set top_module "top"           ;# Change this to your top module name
set target_dir "work"
set part_name "xc7a35tcpg236-1" ;# Standard Basys 3 Artix-7 Part

# 2. Cleanup (Remove old project)
file delete -force $target_dir

# 3. Create Project
create_project $project_name $target_dir -part $part_name -force

# 4. Add Source Files
# Change *.sv to *.v or *.vhd depending on your language
add_files [glob ../src/*.sv] 

# 5. Add Constraints
add_files -fileset constrs_1 [glob ../constraints/*.xdc]

# 6. Set Top Module
set_property top $top_module [current_fileset]
update_compile_order -fileset sources_1

# 7. Run Synthesis
puts "--- Running Synthesis ---"
launch_runs synth_1 -jobs 4
wait_on_run synth_1

# Check if synthesis failed
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "ERROR: Synthesis failed"
    exit 1
}

# 8. Run Implementation
puts "--- Running Implementation ---"
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

# Check if implementation failed
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "ERROR: Implementation failed"
    exit 1
}

puts "--- Bitstream Generated Successfully ---"
puts "Location: [get_property DIRECTORY [get_runs impl_1]]/${top_module}.bit"
```

### 5. The Programming Script (`program.tcl`)
To program the board without opening the GUI, create `program.tcl` in the `/scripts` folder:

```tcl
# scripts/program.tcl

open_hw_manager
connect_hw_server
open_hw_target

set device [lindex [get_hw_devices] 0]
current_hw_device $device
refresh_hw_device -update_hw_probes false $device

# Point to the bitstream generated in the previous step
# Adjust 'top.bit' to your top module name
set_property PROGRAM.FILE {./work/basys3_project.runs/impl_1/top.bit} $device

program_hw_device $device
close_hw_manager
```

### 6. The Workflow in VS Code
1.  **Edit Code:** Open your folder in VS Code. Use TerosHDL to write your code in `/src`. TerosHDL provides nice linting and error checking while you type.
2.  **Open Terminal:** In VS Code, press `Ctrl + ~` to open the integrated terminal.
3.  **Build:** Run the following command from the project root:
    ```bash
    vivado -mode batch -source scripts/build.tcl
    ```
    *This runs Vivado in the background. You will see the logs scroll by in the terminal.*
4.  **Program:** Once the build finishes successfully, plug in your Basys 3 via USB and run:
    ```bash
    vivado -mode batch -source scripts/program.tcl
    ```

### 7. Optional: Automate with VS Code Tasks
To make it even faster (so you don't have to type the commands), create a `.vscode/tasks.json` file:

```json
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "Build Bitstream",
            "type": "shell",
            "command": "vivado -mode batch -source scripts/build.tcl",
            "group": "build",
            "problemMatcher": []
        },
        {
            "label": "Program Board",
            "type": "shell",
            "command": "vivado -mode batch -source scripts/program.tcl",
            "problemMatcher": []
        }
    ]
}
```
Now you can just press `Ctrl+Shift+B` (or run "Run Task") to build your project instantly.
