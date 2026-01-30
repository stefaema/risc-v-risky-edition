import json, subprocess, sys
class Log:
    RESET, GREEN, YELLOW, RED, CYAN = '\033[0m', '\033[92m', '\033[93m', '\033[91m', '\033[96m'
    LOG_SRC = "manage.py"
    
    @staticmethod
    def info(msg): print(f"{Log.CYAN}[INFO] @ {Log.LOG_SRC}: {msg}{Log.RESET}")
    @staticmethod
    def warn(msg): print(f"{Log.YELLOW}[WARN] @ {Log.LOG_SRC}: {msg}{Log.RESET}")
    @staticmethod
    def error(msg): print(f"{Log.RED}[ERROR] @ {Log.LOG_SRC}: {msg}{Log.RESET}")

def execute_vivado(script, module_name, mode):
    """Lauches Vivado in batch mode with standardized arguments."""
    with open('config.json', 'r') as f: 
        cfg = json.load(f)

    # Arguments passed to TCL: [ProjectName] [Part] [TopModule] [Testbench] [Mode]
    tcl_args = [
        f"prj_{module_name}", 
        cfg['part'], 
        module_name, 
        f"{module_name}_tb", 
        mode
    ]

    log_file = f"{cfg['directories']['build_logs']}/vivado_{module_name}_{mode}.log"
    
    cmd = [
        cfg['vivado_path'], "-mode", "batch", "-notrace",
        "-source", f"scripts/{script}.tcl",
        "-log", log_file,
        "-tclargs", *tcl_args
    ]

    Log.info(f"Executing {script.upper()} | Module: {module_name} | Mode: {mode}")
    return subprocess.run(cmd).returncode == 0

def run_task(command, module):
    """Maps CLI commands to TCL workflow sequences."""
    tasks = {
        "synth":    lambda: execute_vivado("build", module, "synth"),
        "impl":     lambda: execute_vivado("build", module, "impl"),
        "bit":      lambda: execute_vivado("build", module, "bitstream"),
        "sim":      lambda: execute_vivado("sim", module, "synth"),
        "program":  lambda: execute_vivado("program", module, "none"),
    }

    if command == "plugnplay": # Complete flow: synth -> impl -> bit -> program. Needs to run another task.
        if execute_vivado("build", module, "bitstream"):
            return execute_vivado("program", module, "none")
        return False
    
    if command in tasks:
        return tasks[command]()
    
    Log.error(f"Unknown command: {command}")
    return False

if __name__ == "__main__":
    if len(sys.argv) < 3:
        Log.warn("Usage: python manage.py [synth|impl|bit|sim|program|plugnplay] [module_name]")
        sys.exit(1)

    success = run_task(sys.argv[1], sys.argv[2])
    sys.exit(0 if success else 1)
