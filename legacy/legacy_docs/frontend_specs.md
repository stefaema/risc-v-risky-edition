Here is the comprehensive **Technical Specification Document** designed to be fed into an AI for code generation. It focuses strictly on design, modularity, and the specific UI/UX flows you requested, utilizing NiceGUI's specific features like `ui.sub_pages`.

---

# Technical Specification: FPGA RISC-V SPA Interface

**Framework:** Python / NiceGUI
**Architecture:** Single Page Application (SPA) using `ui.sub_pages`
**Core Purpose:** GUI for assembling RISC-V code, uploading binaries via UART to FPGA, and debugging execution (Continuous & Step-by-Step).

## 1. Project Structure & Modularity

The project shall be divided into the following file structure to ensure separation of concerns between UI layout, business logic, and backend communication.

```text
/src
 ├── main.py                 # Entry point, App Configuration, CSS injection
 ├── layout.py               # Main Layout (Header, Sidebar, Footer, SubPage container)
 ├── state.py                # Global State Manager (Serial connection, File paths, Sim state)
 ├── router.py               # Definition of sub_page routes
 │
 ├── /pages                  # UI Builders for specific sub-pages
 │   ├── instructions.py     # "Cargar Instrucciones" view
 │   ├── data.py             # "Cargar Datos" view
 │   ├── continuous.py       # "Ejecutar Continuamente" view
 │   └── step_debug.py       # "Ejecutar Paso a Paso" view (SVG logic here)
 │
 ├── /components             # Reusable UI components
 │   ├── console.py          # Dual-tab Serial Console (Raw/Clean)
 │   ├── memory_viewer.py    # Data Memory Table with Radix options
 │   ├── register_viewer.py  # Register File & Pipeline Viewers
 │   └── svg_map.py          # Interactive Datapath SVG Component
 │
 └── /backend                # Logic & Hardware Communication
     ├── assembler.py        # Wrapper for 'Risky Assembler'
     ├── serial_manager.py   # Wrapper for Serial Logic (CMD handling)
     └── simulator.py        # Python-side RISC-V logic for SVG prediction

```

---

## 2. Global State Management (`state.py`)

A Singleton or global module must manage the application state to persist data across sub-page navigation.

* **Serial Connection:** Instance of `SerialManager`.
* **Context Flags:**
* `last_instruction_file`: String (Path).
* `last_data_file`: String (Path).
* `is_connected`: Boolean.


* **Hardware State:**
* `instruction_memory_cache`: Bytes.
* `data_memory_cache`: Bytes (Merged Initial + Patch).
* `register_file_state`: Dict/List.
* `pipeline_regs_state`: Dict.



---

## 3. Main Layout & Navigation (`layout.py`)

The layout acts as the wrapper for all functionality. It initializes the `ui.sub_pages` container.

### 3.1 Header (Fixed Top)

* **Left:** Title: "FPGA RISC-V LOADER".
* **Center/Right Controls:**
* **COM Selector:** Dropdown (dynamically populated).
* **Baud Rate:** Label "115200" (Fixed).
* **Status Hover Icon:** An info icon `(i)`.
* *Hover Tooltip:* Displays "Last IMEM: [filename]", "Last DMEM: [filename]".




* **Styling:** Solid background color, distinct from body.

### 3.2 Sidebar (Collapsible Left Drawer)

* **Behavior:** Icons only by default. Expands to show labels on hover. Everything is disabled except documentation until the UART com port is chosen.
* **Navigation Items (routing to `ui.sub_pages`):**
1. `icon='upload_file'` -> **"Cargar Instrucciones"** (`/instructions`)
2. `icon='storage'` -> **"Cargar Datos"** (`/data`)
3. `icon='play_arrow'` -> **"Ejecutar Continuamente"** (`/continuous`) - *Disabled until Instructions loaded.*
4. `icon='debug'` -> **"Ejecutar Paso a Paso"** (`/step`) - *Disabled until Instructions loaded.*
5. `icon='description'` -> **"Documentación"** (`/docs`)



### 3.3 Footer (Fixed Bottom)

* **Component:** `ConsoleWidget` (See Section 6.1).
* **Height:** Fixed (e.g., 200px), expandable/collapsible.

---

## 4. Sub-Page Specifications

### 4.1 Page: Instruction Loader (`/instructions`)

**Layout:** Split View (Left: File List, Right: Code Visor).

1. **File Explorer (Left):**
* Watches a local directory.
* Lists `.s` or `.asm` files.
* *Action:* Clicking a file loads content into the Visor.


2. **Code Visor (Right):**
* `ui.code` or text area displaying the source.


3. **Action Area (Below Visor):**
* **Button:** "Assemble".
* *On Click:* Calls `Risky Assembler`.
* *Result:*
* **Failure:** `ui.notify` (Error), Console logs error trace.
* **Success:** `ui.notify` (Success), Console logs formatted success msg, Serial Raw tab shows `.bin` content (hex representation).




4. **Success Overlay (Modal):**
* Appears automatically on successful assembly.
* **Button:** "Transfer to Device".
* *Action:* Calls Backend `CMD_LOAD_CODE`. Updates Global State (`last_instruction_file`).
* *Post-Action:* Enables "Execution" sidebar links (Actually a non None imem file does this).



### 4.2 Page: Data Loader (`/data`)

**Layout:** Similar to Instruction Loader but specialized for Data.

1. **File Explorer:** Lists `.bin` data files, boundd to another directory.
2. **Memory Visor (Right):**
* **Format:** Table view (Address | Value).
* **Controls:** Radio Buttons [Hex | Bin | Dec]. Toggles the display format of the values in the table. You can edit the contents.


3. **Action:**
* **Button:** "Transfer to Device".
* *Action:* Calls Backend `CMD_LOAD_DATA`. Updates Global State (`last_data_file`). Stores this data as the "Initial Memory State" for later diffing and only sends up to the last non-zero value.



### 4.3 Page: Continuous Execution (`/continuous`)

**Layout:** Three tabs.

1. **Main Action:**
* **Button:** "EJECUTAR" (Full width, placed just above the Console Footer).
* *Display:* Shows "Source: [Inst File] | Data: [Data File]".


2. **Execution Logic:**
* Triggers Serial `CMD_MODE_CONT`.
* Waits for completion signal from UART.


3. **Post-Execution Results (Tabs):**
* Appears dynamically after execution finishes.
* **Tab 1: Pipeline Registers:** Shows final state of IF/ID, ID/EX, etc. in a pritty way.
* **Tab 2: Register File:** Grid showing x0-x31. Also has radial buttons for hex, dec and bin.
* **Tab 3: Data Memory:**
* *Logic:* Shows a reconstructed memory.
* *Visuals:* Rows modified by the FPGA (Patches) must be highlighted (e.g., cyan background) to distinguish from Initial Data (black background).





### 4.4 Page: Step Execution (`/step`)

**Layout:** Interactive Visual Debugger.

1. **Central Visual (The Stage):**
* **Component:** Large, Scrollable SVG (Dark Mode Background).
* **Content:** Diagram of the RISC-V Datapath.
* **Interactivity:**
* **Hover:** Hovering over a component (ALU, Mux) shows a tooltip with the *Predicted Value* for the current cycle.
* *Prediction Logic:* Since hardware dumps are partial, use `backend/simulator.py` to calculate wire states based on current Instruction + Reg/Mem state.


2. **Controls (Right Side):**
* **Button:** "Avanzar" (Step Clock).
* **History Log:** Vertical list summarising events (e.g., "Store: 0x55 -> Address 0x10", "x5 Updated -> 10").


3. **Inspectors (Right Side/Overlay):**
* **Buttons:** [Data Memory] [Register File] [Pipeline Regs].
* **Behavior:**
* They are **Closable Windows** (`ui.card` with absolute positioning or fixed overlay) that occupy the svg portion of the page. They work as a checkbox, you can have multiple selected and the state activ remains. Check again to update.
* **Layout Manager:**
* 1 active: Fills whole area.
* 2 active: Split 50/50 vertically (two columns).
* 3 active: Split 33/33/33 vertically (three columns).


* **Content:** Updates after every "Avanzar" click.
* *Data Memory Note:* Must utilize a "Virtual Memory" model (Initial State + Cumulative Diffs from steps).

---

## 5. Backend Logic Requirements

### 5.1 Serial Wrapper

* Must be non-blocking (async) where possible to not freeze the GUI.
* **Streams:**
1. **Raw Stream:** Bytes sent/received.
2. **Clean Stream:** Formatted events (e.g., "Packet received: Hazard Detected").



### 5.2 Python Simulator (Shadow Logic)

* A lightweight Python class replicating the RISC-V logic.
* **Input:** Current Instruction, Register File snapshot, Pipeline Registers snapshot.
* **Output:** State of internal wires (ALU Result, Mux Selectors, PC Next) for the SVG tooltips.

---

## 6. Shared Component Details

### 6.1 Console Footer

* **Tabs:** (Only one open at a time)
* **RAW:** Hex view of byte streams.
* **CLEAN:** Human-readable logs (Appended via API).

Scrollable, dark mode

* **API:** `log_raw(bytes, append bool)`, `log_clean(message, color, append bool (if false everything is cleared))`. 

### 6.2 Notifications

* Use `ui.notify` for transient messages (connection errors, assembly success).
* Use Modal Dialogs for blocking flows (Transfer confirmation).

---

## 7. Implementation Roadmap

1. **Phase 1: Shell & Loader**
* Implement `layout.py` and `state.py`.
* Build `instructions.py` and `data.py` (File picking + Hex Viewing).
* Integrate `assembler.py`.


2. **Phase 2: Serial & Basic Execution**
* Implement `serial_manager.py`.
* Build `continuous.py` (Execute button + Post-run Tabs).


3. **Phase 3: Visual Debugger (Complex)**
* Create `svg_map.py` (Loading SVG, adding ID-based event listeners).
* Implement `simulator.py` (Shadow logic).
* Build `step_debug.py` (Step button -> Serial Step -> Update State -> Update SVG).
