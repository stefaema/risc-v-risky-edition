// -----------------------------------------------------------------------------
// Module: loader_unit
// Description: Direct Memory Access (DMA) engine for program/data injection.
//              Handles reassembly of UART bytes into 32-bit words and writes
//              them to the target memory (Instruction or Data).
// -----------------------------------------------------------------------------

module loader_unit (
    input  logic        clk_i,
    input  logic        rst_ni,

    // Arbiter Interface
    input  logic        grant_i,          // Enable signal from Arbiter
    input  logic        target_select_i,  // 0 = IMEM, 1 = DMEM
    output logic        done_o,           // Completion pulse to Arbiter

    // UART RX Interface (Gated)
    input  logic [7:0]  rx_data_i,
    input  logic        rx_ready_i,

    // UART TX Interface (Multiplexed)
    output logic [7:0]  tx_data_o,
    output logic        tx_start_o,
    input  logic        tx_done_i,

    // Memory Interface
    output logic        mem_write_enable_o,
    output logic [31:0] mem_addr_o,
    output logic [31:0] mem_data_o
);

    // -------------------------------------------------------------------------
    // Constants & Parameters
    // -------------------------------------------------------------------------
    localparam logic [7:0] ACK_FINISH = 8'hF1;

    // -------------------------------------------------------------------------
    // Internal Signals
    // -------------------------------------------------------------------------
    
    // FSM States
    typedef enum logic [2:0] {
        S_IDLE,         // Wait for Grant
        S_INIT,         // Wait for Size High Byte
        S_SIZE_LOW,     // Wait for Size Low Byte
        S_RECEIVE_BYTE, // Accumulate 4 bytes
        S_WRITE_WORD,   // Write 32-bit word to memory
        S_SEND_ACK,     // Send 0xF1 completion handshake
        S_WAIT_ACK,     // Wait for UART TX to finish
        S_DONE          // Pulse done_o and cleanup
    } state_t;

    state_t state, next_state;

    // Data Assembly
    logic [31:0] word_buffer, next_word_buffer;
    logic [1:0]  byte_index, next_byte_index;

    // Counters
    logic [15:0] total_word_count, next_total_word_count;
    logic [15:0] words_processed_count, next_words_processed_count;

    // Memory Logic
    logic [31:0] current_addr, next_addr;

    // -------------------------------------------------------------------------
    // FSM Sequential Logic
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state                 <= S_IDLE;
            word_buffer           <= '0;
            byte_index            <= '0;
            total_word_count      <= '0;
            words_processed_count <= '0;
            current_addr          <= '0;
        end else begin
            state                 <= next_state;
            word_buffer           <= next_word_buffer;
            byte_index            <= next_byte_index;
            total_word_count      <= next_total_word_count;
            words_processed_count <= next_words_processed_count;
            current_addr          <= next_addr;
        end
    end

    // -------------------------------------------------------------------------
    // FSM Combinational Logic
    // -------------------------------------------------------------------------
    always_comb begin
        // Default Assignments
        next_state                 = state;
        next_word_buffer           = word_buffer;
        next_byte_index            = byte_index;
        next_total_word_count      = total_word_count;
        next_words_processed_count = words_processed_count;
        next_addr                  = current_addr;

        // Output Defaults
        mem_write_enable_o = 1'b0;
        done_o             = 1'b0;
        tx_start_o         = 1'b0;
        tx_data_o          = 8'h00; 

        // Memory Output mapping
        mem_addr_o = current_addr;
        mem_data_o = word_buffer;

        case (state)
            // -----------------------------------------------------------------
            // 1. Idle / Wait for Grant
            // -----------------------------------------------------------------
            S_IDLE: begin
                if (grant_i) begin
                    // Reset internal counters when granted
                    next_addr = 32'd0; 
                    next_words_processed_count = 16'd0;
                    next_byte_index = 2'd0;
                    next_state = S_INIT;
                end
            end

            // -----------------------------------------------------------------
            // 2. Initialize / Size Capture
            // -----------------------------------------------------------------
            S_INIT: begin
                // Spec 7.4: "Waits for rx_ready_i (High Byte of Size)"
                if (rx_ready_i) begin
                    next_total_word_count[15:8] = rx_data_i; // Capture High Byte
                    next_state = S_SIZE_LOW;
                end
            end

            S_SIZE_LOW: begin
                // Spec 7.4: "Captures Low Byte of Size"
                if (rx_ready_i) begin
                    next_total_word_count[7:0] = rx_data_i; // Capture Low Byte
                    next_state = S_RECEIVE_BYTE;
                end
            end

            // -----------------------------------------------------------------
            // 3. Payload Assembly (Little Endian)
            // -----------------------------------------------------------------
            S_RECEIVE_BYTE: begin
                if (rx_ready_i) begin
                    // Shift byte into appropriate slot based on index
                    case (byte_index)
                        2'd0: next_word_buffer[7:0]   = rx_data_i;
                        2'd1: next_word_buffer[15:8]  = rx_data_i;
                        2'd2: next_word_buffer[23:16] = rx_data_i;
                        2'd3: next_word_buffer[31:24] = rx_data_i;
                    endcase

                    if (byte_index == 2'd3) begin
                        next_state = S_WRITE_WORD;
                        next_byte_index = 0;
                    end else begin
                        next_byte_index = byte_index + 1;
                    end
                end
            end

            // -----------------------------------------------------------------
            // 4. Memory Write
            // -----------------------------------------------------------------
            S_WRITE_WORD: begin
                // Assert Write Enable for 1 cycle
                mem_write_enable_o = 1'b1;
                
                // Advance Address (Address increments by 4 for 32-bit words)
                next_addr = current_addr + 4;
                
                // Update Progress
                next_words_processed_count = words_processed_count + 1;

                // Check Completion
                if (next_words_processed_count == total_word_count) begin
                    next_state = S_SEND_ACK;
                end else begin
                    next_state = S_RECEIVE_BYTE;
                end
            end

            // -----------------------------------------------------------------
            // 5. Completion Handshake
            // -----------------------------------------------------------------
            S_SEND_ACK: begin
                tx_data_o  = ACK_FINISH; // 0xF1
                tx_start_o = 1'b1;       // Pulse Start
                next_state = S_WAIT_ACK;
            end

            S_WAIT_ACK: begin
                // Maintain data valid until done (optional but safer)
                tx_data_o = ACK_FINISH;
                if (tx_done_i) begin
                    next_state = S_DONE;
                end
            end

            // -----------------------------------------------------------------
            // 6. Cleanup & Release
            // -----------------------------------------------------------------
            S_DONE: begin
                done_o = 1'b1; // Signal Arbiter to release grant
                // Wait for grant to be deasserted to return to IDLE
                if (!grant_i) begin
                    next_state = S_IDLE;
                end
            end

            default: next_state = S_IDLE;
        endcase
    end

endmodule
