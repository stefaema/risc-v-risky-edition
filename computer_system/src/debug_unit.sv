// -----------------------------------------------------------------------------
// Module: debug_unit
// Description: Execution Controller for the RV32I Core.
//              Manages Continuous Run vs. Step-by-Step execution paradigms and
//              triggers the Dumping Unit for state serialization.
// -----------------------------------------------------------------------------

module debug_unit (
    input  logic       clk_i,
    input  logic       rst_ni,

    // Arbiter Interface
    input  logic       grant_i,          // Enable signal
    input  logic       exec_mode_i,      // 0 = Step Mode, 1 = Continuous Mode
    output logic       done_o,           // Completion pulse (System Halt)

    // UART RX Interface (Gated)
    input  logic [7:0] rx_data_i,
    input  logic       rx_ready_i,

    // Processor Control Interface
    input  logic       core_halted_i,    // From Core WB Stage
    output logic       cpu_stall_o,      // 1 = Freeze, 0 = Run
    output logic       cpu_reset_o,      // Core PC Reset (Unused in current FSM, tied low)

    // Dumping Unit Interface
    output logic       dump_trigger_o,   // Start serialization
    output logic       dump_mem_mode_o,  // 0 = Step (Diff), 1 = Continuous (Range)
    input  logic       dump_done_i       // Serialization complete
);

    // -------------------------------------------------------------------------
    // Constants & Parameters
    // -------------------------------------------------------------------------
    localparam logic [7:0] CMD_ADVANCE_EXEC = 8'hAE;

    // -------------------------------------------------------------------------
    // FSM State Definition
    // -------------------------------------------------------------------------
    typedef enum logic [3:0] {
        S_IDLE,
        S_RUN,             // Continuous Execution
        S_WAIT_CMD,        // Step Mode: Wait for UART 0xAE
        S_STEP,            // Step Mode: Single Cycle Pulse
        S_TRIGGER_DUMP,    // Assert trigger for Dumping Unit
        S_WAIT_DUMP,       // Wait for Dumping Unit to finish
        S_CHECK_STATUS,    // Step Mode: Check if Core Halted
        S_EXIT             // Signal completion to Arbiter
    } state_t;

    state_t state, next_state;

    // -------------------------------------------------------------------------
    // Internal Registers
    // -------------------------------------------------------------------------
    logic latched_exec_mode; // Stores exec_mode_i upon entry

    // -------------------------------------------------------------------------
    // FSM Sequential Logic
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state        <= S_IDLE;
            latched_exec_mode <= 1'b0;
        end else begin
            state <= next_state;
            // Latch mode only when transitioning from IDLE
            if (state == S_IDLE && grant_i) begin
                latched_exec_mode <= exec_mode_i;
            end
        end
    end

    // -------------------------------------------------------------------------
    // FSM Combinational Logic
    // -------------------------------------------------------------------------
    always_comb begin
        // Default Assignments
        next_state      = state;
        cpu_stall_o     = 1'b1; // Default: Freeze
        cpu_reset_o     = 1'b0; // Not used in current spec flow
        dump_trigger_o  = 1'b0;
        dump_mem_mode_o = 1'b0; // Default: Step Mode
        done_o          = 1'b0;

        case (state)
            // -----------------------------------------------------------------
            // Idle / Entry
            // -----------------------------------------------------------------
            S_IDLE: begin
                if (grant_i) begin
                    if (exec_mode_i) next_state = S_RUN;      // Continuous
                    else             next_state = S_WAIT_CMD; // Step-by-Step
                end
            end

            // -----------------------------------------------------------------
            // Continuous Mode
            // -----------------------------------------------------------------
            S_RUN: begin
                cpu_stall_o     = 1'b0; // Unfreeze Core
                dump_mem_mode_o = 1'b1; // Continuous Dump Mode (Range)

                // Stop if Core reports HALT (ECALL committed in WB)
                if (core_halted_i) begin
                    next_state = S_TRIGGER_DUMP;
                end
            end

            // -----------------------------------------------------------------
            // Step Mode: Wait for Command
            // -----------------------------------------------------------------
            S_WAIT_CMD: begin
                cpu_stall_o     = 1'b1; // Freeze
                dump_mem_mode_o = 1'b0; // Step Dump Mode (Diff)

                // Wait for 'CMD_ADVANCE_EXEC' (0xAE)
                if (rx_ready_i && rx_data_i == CMD_ADVANCE_EXEC) begin
                    next_state = S_STEP;
                end
            end

            // -----------------------------------------------------------------
            // Step Mode: Execute Pulse
            // -----------------------------------------------------------------
            S_STEP: begin
                cpu_stall_o     = 1'b0; // Unfreeze for ONE cycle
                dump_mem_mode_o = 1'b0;
                next_state      = S_TRIGGER_DUMP;
            end

            // -----------------------------------------------------------------
            // Dump Trigger (Common)
            // -----------------------------------------------------------------
            S_TRIGGER_DUMP: begin
                cpu_stall_o     = 1'b1; // Re-freeze immediately
                dump_trigger_o  = 1'b1; // Pulse Trigger

                // Maintain correct mode for Dumper
                if (latched_exec_mode) dump_mem_mode_o = 1'b1;
                else              dump_mem_mode_o = 1'b0;

                next_state = S_WAIT_DUMP;
            end

            // -----------------------------------------------------------------
            // Wait for Dump Completion
            // -----------------------------------------------------------------
            S_WAIT_DUMP: begin
                cpu_stall_o = 1'b1;
                if (latched_exec_mode) dump_mem_mode_o = 1'b1;
                else              dump_mem_mode_o = 1'b0;

                if (dump_done_i) begin
                    if (latched_exec_mode) begin
                        // Continuous Mode: Dump implies we halted -> Exit
                        next_state = S_EXIT;
                    end else begin
                        // Step Mode: Check if we just halted or if we can step again
                        next_state = S_CHECK_STATUS;
                    end
                end
            end

            // -----------------------------------------------------------------
            // Step Mode: Status Check
            // -----------------------------------------------------------------
            S_CHECK_STATUS: begin
                if (core_halted_i) begin
                    next_state = S_EXIT;     // Stop stepping if halted
                end else begin
                    next_state = S_WAIT_CMD; // Wait for next step cmd
                end
            end

            // -----------------------------------------------------------------
            // Cleanup & Exit
            // -----------------------------------------------------------------
            S_EXIT: begin
                done_o = 1'b1; // Signal Arbiter to release grant
                if (!grant_i) begin
                    next_state = S_IDLE;
                end
            end

            default: next_state = S_IDLE;
        endcase
    end

endmodule
