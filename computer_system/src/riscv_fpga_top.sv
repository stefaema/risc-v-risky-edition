//THIS WAS MY SALVATION.
// -----------------------------------------------------------------------------
// Module: riscv_fpga_top
// Description: Physical Top-Level Container for the RISC-V Computer System.
//              Integrates Core, C2 Interface, Xilinx BRAM IP, and Clock Wizard.
// -----------------------------------------------------------------------------

module riscv_fpga_top (
    input  logic       sys_clk_i,    // 100 MHz Oscillator 
    input  logic       rst_btn_i,    // CPU_RESET 
    
    // UART (USB)
    input  logic       uart_rx_i,
    output logic       uart_tx_o,

    // Status LEDs
    output logic       led_wait_o,   // C2 Arbiter is waiting for a cmd
    output logic       led_prog_o,   // Loader is Active, doing memory work
    output logic       led_debug_o,  // Debug mode is Active, either CE or DE
    output logic       led_dumping_o // Both in Debug mode and dumping process happening
);

    // -------------------------------------------------------------------------
    // 1. Clocking & Reset Infrastructure
    // -------------------------------------------------------------------------
    logic main_clk;      // The buffered/stable system clock
    logic pll_locked;    // Active High: PLL is stable
    logic pll_reset;     // Active High: Reset the PLL
    logic sys_rst_sys;   // Active High: Global System Reset (Logic)
    logic sys_rst_n;     // Active Low:  Global System Reset (Logic)


    assign pll_reset = rst_btn_i; 

    // Instantiate Xilinx Clock Wizard
    clk_wiz_0 clk_gen_inst (
        .clk_out1 (main_clk),      // Target Frequency (e.g., 50 or 100 MHz)
        .reset    (pll_reset),     // Input Reset for PLL
        .locked   (pll_locked),    // Output Locked Signal
        .clk_in1  (sys_clk_i)      // Input 100MHz
    );

    // "Safe Start" Reset Logic
    // System is in reset if PLL is NOT locked.
    assign sys_rst_sys = !pll_locked;  // Active High for BRAMs/Core
    assign sys_rst_n   = pll_locked;   // Active Low for C2/UART

    // -------------------------------------------------------------------------
    // 2. Interconnect Signals
    // -------------------------------------------------------------------------
    
    // Core -> Memory Signals
    logic [31:0] core_imem_addr;
    logic [31:0] core_imem_data;
    logic [31:0] core_dmem_addr, core_dmem_wdata, core_dmem_rdata;
    logic        core_dmem_we;
    logic [3:0]  core_dmem_byte_mask;
    logic [31:0] core_tracker_min, core_tracker_max;

    // C2 -> Memory Signals
    logic        loader_we;
    logic [31:0] loader_addr;
    logic [31:0] loader_wdata;
    logic        loader_target; 
    
    // C2 -> Core Control
    logic        c2_waiting;
    logic        c2_debug_active;
    logic        c2_debug_stall;
    logic        c2_soft_reset;
    logic [31:0] c2_dmem_snoop_addr;
    logic [31:0] c2_dmem_snoop_data;
    logic        core_halted;

    // Debug Taps (Updated Widths)
    logic [4:0]   rf_dbg_addr;
    logic [31:0]  rf_dbg_data;
    logic [95:0]  if_id_flat;
    logic [163:0] id_ex_flat;  // 164 bits
    logic [108:0] ex_mem_flat; // 109 bits
    logic [103:0] mem_wb_flat; // 104 bits
    logic [15:0]  hazard_status;

    logic         dumping;

    // -------------------------------------------------------------------------
    // 3. Command & Control (C2) Interface Wrapper
    // -------------------------------------------------------------------------
    c2_interface_top #(
        .CLK_FREQ(50_000_000) // MUST MATCH clk_wiz_0 OUTPUT FREQ
    ) c2_inst (
        .clk_i               (main_clk),
        .rst_ni              (sys_rst_n),
        .pll_locked_i        (pll_locked),
        
        .uart_rx_i           (uart_rx_i),
        .uart_tx_o           (uart_tx_o),
        .baud_rate_sel_i     (2'b11), // 115200 baud

        .loader_we_o         (loader_we),
        .loader_addr_o       (loader_addr),
        .loader_wdata_o      (loader_wdata),
        .loader_target_o     (loader_target),

        .debug_mode_active_o (c2_debug_active),
        .debug_stall_o       (c2_debug_stall),
        .soft_reset_o        (c2_soft_reset),
        .core_halted_i       (core_halted),

        .rf_dbg_addr_o       (rf_dbg_addr),
        .rf_dbg_data_i       (rf_dbg_data),
        .if_id_flat_i        (if_id_flat),
        .id_ex_flat_i        (id_ex_flat),
        .ex_mem_flat_i       (ex_mem_flat),
        .mem_wb_flat_i       (mem_wb_flat),
        .hazard_status_i     (hazard_status),
        
        .dmem_addr_o         (c2_dmem_snoop_addr),
        .dmem_data_i         (c2_dmem_snoop_data),
        .dmem_write_en_snoop_i   (core_dmem_we), 
        .dmem_byte_en_snoop_i    (core_dmem_byte_mask),
        .dmem_addr_snoop_i       (core_dmem_addr),
        .dmem_write_data_snoop_i (core_dmem_wdata),
        .min_addr_i              (core_tracker_min),
        .max_addr_i              (core_tracker_max),
        .c2_waiting_o            (c2_waiting),
        .dumping_o               (dumping)
    );

    // -------------------------------------------------------------------------
    // 4. Core Instantiation & Safe Stall Logic
    // -------------------------------------------------------------------------
    logic core_safe_stall;
    assign core_safe_stall = (c2_debug_active) ? c2_debug_stall : 1'b1;

    riscv_core core_inst (
        .clk_i                 (main_clk),
        .rst_ni                (sys_rst_n),
        .global_freeze_i       (core_safe_stall),
        .soft_reset_i          (c2_soft_reset),

        .imem_addr_o           (core_imem_addr),
        .imem_inst_i           (core_imem_data),

        .dmem_addr_o           (core_dmem_addr),
        .dmem_wdata_o          (core_dmem_wdata),
        .dmem_rdata_i          (core_dmem_rdata),
        .dmem_write_en_o       (core_dmem_we),
        .dmem_byte_mask_o      (core_dmem_byte_mask),
        .dmem_min_addr_o       (core_tracker_min),
        .dmem_max_addr_o       (core_tracker_max),

        .core_halted_o         (core_halted),
        .dbg_rf_addr_i         (rf_dbg_addr),
        .dbg_rf_data_o         (rf_dbg_data),
        
        .tap_if_id_o           (if_id_flat),
        .tap_id_ex_o           (id_ex_flat),
        .tap_ex_mem_o          (ex_mem_flat),
        .tap_mem_wb_o          (mem_wb_flat),
        .tap_hazard_o          (hazard_status)
    );


    // -------------------------------------------------------------------------
    // 5. MEMORY GLUE LOGIC (Traffic Cop)
    // -------------------------------------------------------------------------
    
    // --- Instruction Memory Glue ---
    // Port A is shared: Loader Writes vs Core Fetches
    logic [31:0] imem_addr_mux;
    logic [31:0] imem_wdata_mux;
    logic   imem_we_mux;

    always_comb begin
        if (loader_we && (loader_target == 1'b0)) begin
            imem_addr_mux  = loader_addr;
            imem_wdata_mux = loader_wdata;
            imem_we_mux    = 1'b1; 
        end else begin
            imem_addr_mux  = core_imem_addr;
            imem_wdata_mux = 32'b0;
            imem_we_mux    = 1'b0;
        end
    end

    // --- Data Memory Glue ---
    // Port A: Loader Write vs Core Read/Write
    // Port B: C2 Dumper Read (Snoop)
    logic [31:0] dmem_porta_addr;
    logic [31:0] dmem_porta_wdata;
    logic [3:0]  dmem_porta_we;

    always_comb begin
        if (loader_we && (loader_target == 1'b1)) begin
            dmem_porta_addr  = loader_addr;
            dmem_porta_wdata = loader_wdata;
            dmem_porta_we    = 4'b1111;
        end else begin
            dmem_porta_addr  = core_dmem_addr;
            dmem_porta_wdata = core_dmem_wdata;
            dmem_porta_we    = core_dmem_byte_mask; // Use Core's byte mask
        end
    end

    // -------------------------------------------------------------------------
    // 6. Instruction & Data Memory
    // -------------------------------------------------------------------------
    // IP: Distributed Memory Generator
    // Config: Single Port, 32-bit width, 1024 depth
  
        instruction_memory imem_inst (
            .clk   (main_clk),            
            .we    (imem_we_mux),        
            
            // As it's 1024 words deep and uses word addressing, we use 2 to 11 of the 32 bit address.
            .a     (imem_addr_mux[11:2]), 
            
            .d     (imem_wdata_mux),           

            .spo   (core_imem_data)

        );

    // Data Memory (Port A: Core/Loader, Port B: Dumper)
    data_memory dmem_inst (
        
        .clk_i  (main_clk),

        // PORT A (Core Execution / Loader Injection)
        .we_a_i    (dmem_porta_we),
        .addr_a_i  (dmem_porta_addr),
        .data_a_i  (dmem_porta_wdata),
        .data_a_o  (core_dmem_rdata),
        
        // PORT B (C2 Dumper Read-Only Access)
        .addr_b_i (c2_dmem_snoop_addr),
        .data_b_o (c2_dmem_snoop_data)  // Goes to C2 Dumper
    );

    // -------------------------------------------------------------------------
    // 7. Status LEDs
    // -------------------------------------------------------------------------
    assign led_wait_o  = c2_waiting;
    assign led_prog_o  = loader_we; 
    assign led_debug_o = c2_debug_active;
    assign led_dumping_o = dumping;

endmodule
