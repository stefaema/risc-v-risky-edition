import json
import subprocess
import sys
import os

def load_config():
    """
    Loads the configuration from config.json file.
    """
    with open('config.json', 'r') as f:
        return json.load(f)

def run_vivado(action):
    """
    Creates and runs the Vivado command based on the action provided.
    Action can be 'build', 'sim', or 'program'.
    """
    config = load_config()
    
    # Create logs directory if it doesn't exist
    if not os.path.exists(config['directories']['build_logs']):
        os.makedirs(config['directories']['build_logs'])

    # Define the TCL script to run based on action
    script_map = {
        "build": "scripts/build.tcl",
        "sim": "scripts/sim.tcl",
        "program": "scripts/program.tcl"
    }

    if action not in script_map:
        print(f"Error: Action '{action}' not recognized. Use: build, sim, or program.")
        return

    tcl_script = script_map[action]
    
    # Build the command to run Vivado
    # We use -tclargs to pass JSON data to the TCL script
    command = [
        config['vivado_path'],
        "-mode", "batch",
        "-notrace",
        "-source", tcl_script,
        "-log", f"{config['directories']['build_logs']}/vivado_{action}.log",
        "-journal", f"{config['directories']['build_logs']}/vivado_{action}.jou",
        "-tclargs", 
        config['project_name'], 
        config['part'], 
        config['top_module'], 
        config['tb_top']
    ]

    print(f"---> Running {action.upper()} for project {config['project_name']}...")
    
    try:
        subprocess.run(command, check=True)
        print(f"---> {action.upper()} completed successfully.")
    except subprocess.CalledProcessError:
        print(f"---> ERROR in {action.upper()}. Check the logs in the /{config['directories']['build_logs']} folder.")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python manage.py [build|sim|program]")
    else:
        run_vivado(sys.argv[1])
