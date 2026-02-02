// -----------------------------------------------------------------------------
// Module: c2_arbiter
// Description: Central Command & Control Traffic Controller.
//              Manages the UART resource, decodes host commands, grants access
//              to sub-modules (Loader, Debugger), and enforces system cleanup.
// -----------------------------------------------------------------------------

module c2_arbiter (
    input  logic       clk_i,
    input  logic       rst_ni,

    // Physical UART Interface
    input  logic [7:0] uart_rx_data_i,
    input  logic       uart_rx_ready_i,
    output logic [7:0] uart_tx_data_o,
    output logic       uart_tx_start_o,
    input  logic       uart_tx_done_i,

    // Core Control Output
    output logic       soft_reset_o,      // Global Flush: zeroes PC, RegFile, Pipeline regs and Memory Range Tracker

    // Loader Interface
    output logic       grant_loader_o,
    output logic       loader_target_o,   // 0 = IMEM, 1 = DMEM
    input  logic       loader_done_i,
    // Loader UART TX Taps
    input  logic [7:0] loader_tx_data_i,
    input  logic       loader_tx_start_i,

    // Debug Interface (Controls Debug Unit + Dumping Unit)
    output logic       grant_debug_o,
    output logic       debug_exec_mode_o, // 0 = Step, 1 = Continuous
    input  logic       debug_done_i,
    // Dumper UART TX Taps (Dumper operates under Debug Grant)
    input  logic [7:0] dumper_tx_data_i,
    input  logic       dumper_tx_start_i
);

    // -------------------------------------------------------------------------
    // Constants & Parameters
    // -------------------------------------------------------------------------
    localparam logic [7:0] CMD_LOAD_CODE  = 8'h1C;
    localparam logic [7:0] CMD_LOAD_DATA  = 8'h1D;
    localparam logic [7:0] CMD_CONT_EXEC  = 8'hCE;
    localparam logic [7:0] CMD_DEBUG_EXEC = 8'hDE;

    // -------------------------------------------------------------------------
    // FSM State Definition
    // -------------------------------------------------------------------------
    typedef enum logic [2:0] {
        S_IDLE,
        S_ACK_HANDOFF,      // Echo Command & Grant Access
        S_BUSY,             // Wait for Sub-Module Done
        S_CLEANUP,          // Assert Soft Reset
        S_RECOVERY          // De-assert Reset & Grants, Return to Idle
    } state_t;

    state_t state, next_state;

    // -------------------------------------------------------------------------
    // Internal Registers
    // -------------------------------------------------------------------------
    logic [7:0] latched_cmd;
    logic       internal_grant_loader;
    logic       internal_grant_debug;
    
    // Configuration Registers
    logic       reg_loader_target;
    logic       reg_debug_mode;

    // -------------------------------------------------------------------------
    // Sequential Logic
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state           <= S_IDLE;
            latched_cmd     <= 8'h00;
            reg_loader_target <= 1'b0;
            reg_debug_mode    <= 1'b0;
        end else begin
            state <= next_state;

            if (state == S_IDLE && uart_rx_ready_i) begin
                latched_cmd <= uart_rx_data_i;
                case (uart_rx_data_i)
                    CMD_LOAD_CODE:  reg_loader_target <= 1'b0;
                    CMD_LOAD_DATA:  reg_loader_target <= 1'b1;
                    CMD_CONT_EXEC:  reg_debug_mode    <= 1'b1;
                    CMD_DEBUG_EXEC: reg_debug_mode    <= 1'b0;
                endcase
            end
        end
    end

    // -------------------------------------------------------------------------
    // Combinational Logic: Next State & Control Signals
    // -------------------------------------------------------------------------
    always_comb begin

        logic arb_tx_start; 

        // Default Assignments
        next_state            = state;
        internal_grant_loader = 1'b0;
        internal_grant_debug  = 1'b0;
        soft_reset_o          = 1'b0;
        arb_tx_start          = 1'b0;

        case (state)
            S_IDLE: begin
                if (uart_rx_ready_i) begin
                    if (uart_rx_data_i == CMD_LOAD_CODE || 
                        uart_rx_data_i == CMD_LOAD_DATA || 
                        uart_rx_data_i == CMD_CONT_EXEC || 
                        uart_rx_data_i == CMD_DEBUG_EXEC) begin
                        next_state = S_ACK_HANDOFF;
                    end
                end
            end

            S_ACK_HANDOFF: begin
                arb_tx_start = 1'b1;
                if (latched_cmd == CMD_LOAD_CODE || latched_cmd == CMD_LOAD_DATA) begin
                    internal_grant_loader = 1'b1;
                end else begin
                    internal_grant_debug = 1'b1;
                end
                next_state = S_BUSY;
            end

            S_BUSY: begin
                if (latched_cmd == CMD_LOAD_CODE || latched_cmd == CMD_LOAD_DATA) begin
                    internal_grant_loader = 1'b1;
                    if (loader_done_i) next_state = S_CLEANUP;
                end else begin
                    internal_grant_debug = 1'b1;
                    if (debug_done_i) next_state = S_CLEANUP;
                end
            end

            S_CLEANUP: begin
                soft_reset_o = 1'b1;
                next_state = S_RECOVERY;
            end

            S_RECOVERY: begin
                next_state = S_IDLE;
            end

            default: next_state = S_IDLE;
        endcase

        // -----------------------------------------------------------------
        // Output Routing
        // -----------------------------------------------------------------
        grant_loader_o    = internal_grant_loader;
        grant_debug_o     = internal_grant_debug;
        loader_target_o   = reg_loader_target;
        debug_exec_mode_o = reg_debug_mode;

        // UART TX Mux
        if (state == S_ACK_HANDOFF) begin
            uart_tx_data_o  = latched_cmd;
            uart_tx_start_o = arb_tx_start;
        end else if (internal_grant_loader) begin
            uart_tx_data_o  = loader_tx_data_i;
            uart_tx_start_o = loader_tx_start_i;
        end else if (internal_grant_debug) begin
            uart_tx_data_o  = dumper_tx_data_i;
            uart_tx_start_o = dumper_tx_start_i;
        end else begin
            uart_tx_data_o  = 8'h00;
            uart_tx_start_o = 1'b0;
        end
    end

endmodule
