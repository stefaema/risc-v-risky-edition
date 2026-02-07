// -------------------------------------------------------------------------
    // 2. Interconnect Signals (Updated Declarations)
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
    logic        c2_debug_active;
    logic        c2_debug_stall;
    logic        c2_soft_reset;
    logic        c2_dump_needs_mem;
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

    // -------------------------------------------------------------------------
    // 4. Core Instantiation
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
