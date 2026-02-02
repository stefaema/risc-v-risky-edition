// -----------------------------------------------------------------------------
// Module: c2_interface_top
// Description: Top-level wrapper for the Command & Control (C2) Subsystem.
//              Encapsulates the UART Physical Layer, Central Arbiter, and 
//              functional units (Loader, Debugger, Dumper).
// -----------------------------------------------------------------------------

module c2_interface_top #(
    parameter int CLK_FREQ = 100_000_000
) (
    input  logic        clk_i,
    input  logic        rst_ni,
    input  logic        pll_locked_i,

    // Physical UART Interface
    input  logic        uart_rx_i,
    output logic        uart_tx_o,
    input  logic [1:0]  baud_rate_sel_i,

    // Loader Interface (To Memory Mux)
    output logic        loader_we_o,
    output logic [31:0] loader_addr_o,
    output logic [31:0] loader_wdata_o,
    output logic        loader_target_o, // 0=IMEM, 1=DMEM

    // Core Control Interface
    output logic        dump_needs_mem_o,
    output logic        debug_mode_active_o, // 1 = Debugger has control
    output logic        debug_stall_o,       // 0 = Run, 1 = Pause
    output logic        soft_reset_o,        // System Flush/PC Reset
    input  logic        core_halted_i,       // From WB Stage

    // Debug Taps (To/From Core & Dumping Unit)
    // Register File Access
    output logic [4:0]  rf_dbg_addr_o,
    input  logic [31:0] rf_dbg_data_i,
    // Pipeline Flat Buses
    input  logic [95:0]  if_id_flat_i,
    input  logic [196:0] id_ex_flat_i,
    input  logic [109:0] ex_mem_flat_i,
    input  logic [104:0] mem_wb_flat_i,
    input  logic [15:0]  hazard_status_i,
    // Memory Snooping & Dump Interface
    output logic [31:0] dmem_addr_o,
    input  logic [31:0] dmem_data_i,
    input  logic        dmem_write_en_snoop_i,
    input  logic [31:0] dmem_addr_snoop_i,
    input  logic [31:0] dmem_write_data_snoop_i,
    input  logic [31:0] min_addr_i,
    input  logic [31:0] max_addr_i
);

    // -------------------------------------------------------------------------
    // Signal Definitions
    // -------------------------------------------------------------------------

    // Global Safe Reset (Gated by PLL Lock)
    logic c2_rst_n;
    assign c2_rst_n = rst_ni && pll_locked_i;

    // UART Internal Signals
    logic [7:0] uart_rx_data;
    logic       uart_rx_ready;
    logic       uart_rx_error; // Unused in current arbiter logic, but available
    
    logic [7:0] uart_tx_data;
    logic       uart_tx_start;
    logic       uart_tx_busy;
    logic       uart_tx_done;

    // Arbiter <-> Sub-Module Handshakes
    logic grant_loader, grant_debug;
    logic loader_done, debug_done; // Debug done comes from debug_unit
    logic arbiter_loader_target;   // Config from Arbiter
    logic arbiter_debug_mode;      // Config from Arbiter

    // Loader Signals
    logic [7:0] loader_tx_data;
    logic       loader_tx_start;

    // Debugger Signals
    logic       debug_unit_done; // Signal from Debug Unit -> Arbiter
    
    // Dumper Signals
    logic       dump_trigger;
    logic       dump_mem_mode;
    logic       dump_done;
    logic [7:0] dumper_tx_data;
    logic       dumper_tx_start;

    // RX Gating Signals
    logic loader_rx_ready;
    logic debug_rx_ready;

    // -------------------------------------------------------------------------
    // 1. UART Physical Layer
    // -------------------------------------------------------------------------
    uart_transceiver #(
        .CLK_FREQ(CLK_FREQ)
    ) uart_phy_inst (
        .clk_i           (clk_i),
        .rst_ni          (c2_rst_n),
        .baud_selector_i (baud_rate_sel_i),
        
        // RX
        .rx_i            (uart_rx_i),
        .rx_data_o       (uart_rx_data),
        .rx_ready_o      (uart_rx_ready),
        .rx_error_o      (uart_rx_error),

        // TX
        .tx_data_i       (uart_tx_data),
        .tx_start_i      (uart_tx_start),
        .tx_o            (uart_tx_o),
        .tx_busy_o       (uart_tx_busy),
        .tx_done_o       (uart_tx_done)
    );

    // -------------------------------------------------------------------------
    // 2. RX Path Gating (Demultiplexer)
    // -------------------------------------------------------------------------
    // Isolate sub-modules from RX traffic unless they are granted control.
    // The Arbiter always sees the RX ready signal to detect initial commands.
    
    always_comb begin
        loader_rx_ready = 1'b0;
        debug_rx_ready  = 1'b0;

        if (grant_loader) begin
            loader_rx_ready = uart_rx_ready;
        end
        
        if (grant_debug) begin
            debug_rx_ready = uart_rx_ready;
        end
    end

    // -------------------------------------------------------------------------
    // 3. Command & Control Arbiter
    // -------------------------------------------------------------------------
    // Manages the TX Mux internally and handles module handoffs.

    c2_arbiter arbiter_inst (
        .clk_i             (clk_i),
        .rst_ni            (c2_rst_n),

        // UART Interface
        .uart_rx_data_i    (uart_rx_data),
        .uart_rx_ready_i   (uart_rx_ready), // Arbiter monitors this in S_IDLE
        .uart_tx_data_o    (uart_tx_data),
        .uart_tx_start_o   (uart_tx_start),
        .uart_tx_done_i    (uart_tx_done),

        // Core Control Output
        .soft_reset_o      (soft_reset_o),

        // Loader Interface
        .grant_loader_o    (grant_loader),
        .loader_target_o   (arbiter_loader_target),
        .loader_done_i     (loader_done),
        .loader_tx_data_i  (loader_tx_data),
        .loader_tx_start_i (loader_tx_start),

        // Debug Interface
        .grant_debug_o     (grant_debug),
        .debug_exec_mode_o (arbiter_debug_mode),
        .debug_done_i      (debug_unit_done),

        // Dumper TX Taps (Dumper operates under Debug Grant)
        .dumper_tx_data_i  (dumper_tx_data),
        .dumper_tx_start_i (dumper_tx_start)
    );

    // Output Assignments
    assign debug_mode_active_o = grant_debug;
    assign loader_target_o     = arbiter_loader_target;

    // -------------------------------------------------------------------------
    // 4. Loader Unit
    // -------------------------------------------------------------------------
    loader_unit loader_inst (
        .clk_i              (clk_i),
        .rst_ni             (c2_rst_n),
        
        // Control
        .grant_i            (grant_loader),
        .target_select_i    (arbiter_loader_target),
        .done_o             (loader_done),

        // UART (Gated RX, Direct TX)
        .rx_data_i          (uart_rx_data),
        .rx_ready_i         (loader_rx_ready),
        .tx_data_o          (loader_tx_data),
        .tx_start_o         (loader_tx_start),
        .tx_done_i          (uart_tx_done),

        // Memory Write Interface
        .mem_write_enable_o (loader_we_o),
        .mem_addr_o         (loader_addr_o),
        .mem_data_o         (loader_wdata_o)
    );

    // -------------------------------------------------------------------------
    // 5. Debug Unit
    // -------------------------------------------------------------------------
    debug_unit debug_inst (
        .clk_i           (clk_i),
        .rst_ni          (c2_rst_n),

        // Control
        .grant_i         (grant_debug),
        .exec_mode_i     (arbiter_debug_mode),
        .done_o          (debug_unit_done),

        // UART (Gated RX)
        .rx_data_i       (uart_rx_data),
        .rx_ready_i      (debug_rx_ready),

        // Processor Control
        .core_halted_i   (core_halted_i),
        .cpu_stall_o     (debug_stall_o),
        .cpu_reset_o     (), // Unused, driven by Arbiter soft_reset_o

        // Dumper Interface
        .dump_trigger_o  (dump_trigger),
        .dump_mem_mode_o (dump_mem_mode),
        .dump_done_i     (dump_done)
    );

    // -------------------------------------------------------------------------
    // 6. Dumping Unit (State Serializer)
    // -------------------------------------------------------------------------
    dumping_unit dumper_inst (
        .clk_i                   (clk_i),
        .rst_ni                  (c2_rst_n),

        // Control
        .dump_trigger_i          (dump_trigger),
        .dump_mem_mode_i         (dump_mem_mode),
        .dump_done_o             (dump_done),
        .dump_needs_mem_o        (dump_needs_mem_o),
        // UART (TX Master)
        .tx_data_o               (dumper_tx_data),
        .tx_start_o              (dumper_tx_start),
        .tx_done_i               (uart_tx_done),

        // Core Taps - Register File
        .rf_dbg_addr_o           (rf_dbg_addr_o),
        .rf_dbg_data_i           (rf_dbg_data_i),

        // Core Taps - Pipeline
        .if_id_flat_i            (if_id_flat_i),
        .id_ex_flat_i            (id_ex_flat_i),
        .ex_mem_flat_i           (ex_mem_flat_i),
        .mem_wb_flat_i           (mem_wb_flat_i),
        .hazard_status_i         (hazard_status_i),

        // Core Taps - Memory
        .dmem_addr_o             (dmem_addr_o),
        .dmem_data_i             (dmem_data_i),
        .dmem_write_en_snoop_i   (dmem_write_en_snoop_i),
        .dmem_addr_snoop_i       (dmem_addr_snoop_i),
        .dmem_write_data_snoop_i (dmem_write_data_snoop_i),
        .min_addr_i              (min_addr_i),
        .max_addr_i              (max_addr_i)
    );

endmodule
