// -----------------------------------------------------------------------------
// Module: dumping_unit
// Description: Parallel-to-Serial State Serialization Unit.
//              Extracts Register File, Pipeline, and Memory state and transmits
//              it via UART for debugging/visualization.
// -----------------------------------------------------------------------------

module dumping_unit (
    input  logic        clk_i,
    input  logic        rst_ni,

    // Arbiter/Debug Interface
    input  logic        dump_trigger_i,
    input  logic        dump_mem_mode_i, // 0 = Step (Diff), 1 = Continuous (Range)
    output logic        dump_done_o,

    // UART TX Interface (Master)
    output logic [7:0]  tx_data_o,
    output logic        tx_start_o,
    input  logic        tx_done_i,

    // Core Taps (Inputs)
    // Register File Access: Address and Data
    output logic [4:0]  rf_dbg_addr_o,
    input  logic [31:0] rf_dbg_data_i,

    // Flattened Pipeline Taps
    input  logic [95:0]  if_id_flat_i,
    input  logic [196:0] id_ex_flat_i,
    input  logic [109:0] ex_mem_flat_i,
    input  logic [104:0] mem_wb_flat_i,
    input  logic [15:0]  hazard_status_i,

    // Memory Interface
    output logic        dump_needs_mem_o,
    output logic [31:0] dmem_addr_o,
    input  logic [31:0] dmem_data_i,
    // Snooping Signals (from MEM stage/Tracker)
    input  logic        dmem_write_en_snoop_i,
    input  logic [31:0] dmem_addr_snoop_i,
    input  logic [31:0] dmem_write_data_snoop_i, // Inferred requirement from Spec 10.5.4
    input  logic [31:0] min_addr_i,
    input  logic [31:0] max_addr_i
);

    // -------------------------------------------------------------------------
    // Constants & Parameters
    // -------------------------------------------------------------------------
    localparam logic [7:0] RSP_DUMP_ALERT = 8'hDA;

    // -------------------------------------------------------------------------
    // Internal Unpacking & Organization
    // -------------------------------------------------------------------------

    // --- 1. Pipeline Unpacking ---
    // Extract fields.

    // IF/ID (96 bits): {pc_f, instr_f, pc_plus_4_f}
    logic [31:0] if_id_pc, if_id_instr, if_id_pc4;
    assign {if_id_pc, if_id_instr, if_id_pc4} = if_id_flat_i;

    // ID/EX (197 bits): {Controls(12), PC(32), PC4(32), RS1(32), RS2(32), Imm(32), Meta(25)}
    logic [11:0] id_ex_ctrl;
    logic [31:0] id_ex_pc, id_ex_pc4, id_ex_rs1, id_ex_rs2, id_ex_imm;
    logic [24:0] id_ex_meta;
    assign {id_ex_ctrl, id_ex_pc, id_ex_pc4, id_ex_rs1, id_ex_rs2, id_ex_imm, id_ex_meta} = id_ex_flat_i;

    // EX/MEM (110 bits): {Ctrl(6), Data(96), Meta(8)} -> {Ctrl, ALU, StoreData, PC4, Meta}
    // Packing in core: {ctrl, alu, store_data, pc_plus_4, meta}
    logic [5:0]  ex_mem_ctrl;
    logic [31:0] ex_mem_alu, ex_mem_store_data, ex_mem_pc4;
    logic [7:0]  ex_mem_meta;
    assign {ex_mem_ctrl, ex_mem_alu, ex_mem_store_data, ex_mem_pc4, ex_mem_meta} = ex_mem_flat_i;

    // MEM/WB (105 bits): {Ctrl(4), Data(96), Meta(5)} -> {Ctrl, ALU, ReadData, PC4, Meta}
    logic [3:0]  mem_wb_ctrl;
    logic [31:0] mem_wb_alu, mem_wb_read_data, mem_wb_pc4;
    logic [4:0]  mem_wb_meta;
    assign {mem_wb_ctrl, mem_wb_alu, mem_wb_read_data, mem_wb_pc4, mem_wb_meta} = mem_wb_flat_i;

    // --- 2. Serialization Array Construction (Spec 10.5.3) ---
    // We map all pipeline data into a uniform 32-bit word array for easier iteration.
    // Total 76 Bytes = 19 Words.

    logic [31:0] pipe_dump_words [0:18];

    always_comb begin
        // Hazard (4 Bytes)
        pipe_dump_words[0]  = {16'h0000, hazard_status_i};

        // IF/ID (12 Bytes)
        pipe_dump_words[1]  = if_id_pc;
        pipe_dump_words[2]  = if_id_instr;
        pipe_dump_words[3]  = if_id_pc4;

        // ID/EX (28 Bytes)
        // Spec: Ctrl (2B + Pad)
        pipe_dump_words[4]  = {16'h0000, 4'b0, id_ex_ctrl}; 
        pipe_dump_words[5]  = id_ex_pc;
        pipe_dump_words[6]  = id_ex_pc4;
        pipe_dump_words[7]  = id_ex_rs1;
        pipe_dump_words[8]  = id_ex_rs2;
        pipe_dump_words[9]  = id_ex_imm;
        pipe_dump_words[10] = {7'b0, id_ex_meta}; // Meta is 25 bits

        // EX/MEM (16 Bytes)
        // Spec: Ctrl_Meta (2B + Pad) -> Ctrl(6) + Meta(8) = 14 bits
        pipe_dump_words[11] = {16'h0000, 2'b0, ex_mem_ctrl, ex_mem_meta};
        pipe_dump_words[12] = ex_mem_alu;
        pipe_dump_words[13] = ex_mem_store_data; // RS2 Data
        pipe_dump_words[14] = ex_mem_pc4;

        // MEM/WB (16 Bytes)
        // Spec: Ctrl_Meta (2B + Pad) -> Ctrl(4) + Meta(5) = 9 bits
        pipe_dump_words[15] = {16'h0000, 7'b0, mem_wb_ctrl, mem_wb_meta};
        pipe_dump_words[16] = mem_wb_alu;
        pipe_dump_words[17] = mem_wb_read_data;
        pipe_dump_words[18] = mem_wb_pc4;
    end

    // -------------------------------------------------------------------------
    // FSM State Definition
    // -------------------------------------------------------------------------
    typedef enum logic [3:0] {
        S_IDLE,
        S_SEND_HEADER_ALERT,
        S_SEND_HEADER_MODE,
        S_DUMP_REGS,
        S_DUMP_PIPELINE,
        S_DUMP_MEM_CONFIG_1, // Min Addr or Flag
        S_DUMP_MEM_CONFIG_2, // Max Addr or Address (if step write)
        S_DUMP_MEM_CONFIG_3, // Data (if step write)
        S_DUMP_MEM_PAYLOAD,
        S_WAIT_TX,           // Generic wait state for UART
        S_DONE
    } state_t;

    state_t state, next_state;
    state_t return_state, next_return_state; // For sub-routine returns

    // -------------------------------------------------------------------------
    // Internal Registers
    // -------------------------------------------------------------------------
    logic [4:0]  rf_idx, next_rf_idx;
    logic [4:0]  pipe_word_idx, next_pipe_word_idx; // 0 to 18
    logic [1:0]  byte_idx, next_byte_idx;           // 0 to 3
    logic [31:0] current_mem_addr, next_mem_addr;
    logic        latched_mode, next_latched_mode;

    // Helper for selected 32-bit word based on phase
    logic [31:0] current_word_to_send;
    logic [7:0]  selected_byte;

    // -------------------------------------------------------------------------
    // Combinational Logic
    // -------------------------------------------------------------------------

    always_comb begin
        current_word_to_send = 32'h0;
        dump_needs_mem_o           = 1'b0; // Default: Release bus

        // 1. Bus Request Logic
        // We request the Data Memory Bus ONLY in Continuous Mode.

        if (latched_mode == 1'b1) begin
            case (state)
                S_DUMP_MEM_CONFIG_1, // Sending Min Addr
                S_DUMP_MEM_CONFIG_2, // Sending Max Addr (Pre-fetch data here)
                S_DUMP_MEM_PAYLOAD:  // Sending Data
                    dump_needs_mem_o = 1'b1;
                default: 
                    dump_needs_mem_o = 1'b0;
            endcase
        end

        // 2. Data Multiplexing (Little Endian Slicing)
        case (state)
            S_DUMP_REGS:     current_word_to_send = rf_dbg_data_i;
            S_DUMP_PIPELINE: current_word_to_send = pipe_dump_words[pipe_word_idx];
            
            // Memory Config Phase
            S_DUMP_MEM_CONFIG_1: begin
                if (latched_mode == 1'b1) current_word_to_send = min_addr_i; // Continuous
                else                      current_word_to_send = {31'b0, dmem_write_en_snoop_i}; // Step Flag
            end
            S_DUMP_MEM_CONFIG_2: begin
                if (latched_mode == 1'b1) current_word_to_send = max_addr_i;
                else                      current_word_to_send = dmem_addr_snoop_i;
            end
            S_DUMP_MEM_CONFIG_3: begin
                 current_word_to_send = dmem_write_data_snoop_i;
            end

            // Memory Payload Phase
            S_DUMP_MEM_PAYLOAD: begin 
                current_word_to_send = dmem_data_i;
            end 
            
            default: current_word_to_send = 32'h0;
        endcase

        // 3. Byte Selection
        case (byte_idx)
            2'd0: selected_byte = current_word_to_send[7:0];
            2'd1: selected_byte = current_word_to_send[15:8];
            2'd2: selected_byte = current_word_to_send[23:16];
            2'd3: selected_byte = current_word_to_send[31:24];
        endcase
    end

    // Address Outputs
    assign rf_dbg_addr_o = rf_idx;
    assign dmem_addr_o   = current_mem_addr;

    // -------------------------------------------------------------------------
    // Sequential Logic
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state            <= S_IDLE;
            return_state     <= S_IDLE;
            rf_idx           <= '0;
            pipe_word_idx    <= '0;
            byte_idx         <= '0;
            current_mem_addr <= '0;
            latched_mode     <= '0;
        end else begin
            state            <= next_state;
            return_state     <= next_return_state;
            rf_idx           <= next_rf_idx;
            pipe_word_idx    <= next_pipe_word_idx;
            byte_idx         <= next_byte_idx;
            current_mem_addr <= next_mem_addr;
            latched_mode     <= next_latched_mode;
        end
    end

    // -------------------------------------------------------------------------
    // FSM Next State Logic
    // -------------------------------------------------------------------------
    always_comb begin
        next_state          = state;
        next_return_state   = return_state;
        next_rf_idx         = rf_idx;
        next_pipe_word_idx  = pipe_word_idx;
        next_byte_idx       = byte_idx;
        next_mem_addr       = current_mem_addr;
        next_latched_mode   = latched_mode;

        // Outputs
        tx_data_o      = 8'h00;
        tx_start_o     = 1'b0;
        dump_done_o    = 1'b0;

        case (state)
            // -------------------------------------------------------------
            // Idle
            // -------------------------------------------------------------
            S_IDLE: begin
                if (dump_trigger_i) begin
                    next_latched_mode = dump_mem_mode_i;
                    next_state = S_SEND_HEADER_ALERT;
                end
            end

            // -------------------------------------------------------------
            // Header
            // -------------------------------------------------------------
            S_SEND_HEADER_ALERT: begin
                tx_data_o = RSP_DUMP_ALERT; // 0xDA
                tx_start_o = 1'b1;
                next_return_state = S_SEND_HEADER_MODE;
                next_state = S_WAIT_TX;
            end

            S_SEND_HEADER_MODE: begin
                tx_data_o = {7'b0, latched_mode};
                tx_start_o = 1'b1;
                next_return_state = S_DUMP_REGS;
                next_state = S_WAIT_TX;
                next_rf_idx = 0;
                next_byte_idx = 0;
            end

            // -------------------------------------------------------------
            // Register File Dump (32 regs * 4 bytes)
            // -------------------------------------------------------------
            S_DUMP_REGS: begin
                tx_data_o = selected_byte;
                tx_start_o = 1'b1;
                next_state = S_WAIT_TX;
                
                // Logic to advance bytes and registers
                if (byte_idx == 3) begin
                    next_byte_idx = 0;
                    if (rf_idx == 31) begin
                        next_return_state = S_DUMP_PIPELINE;
                        next_pipe_word_idx = 0;
                    end else begin
                        next_rf_idx = rf_idx + 1;
                        next_return_state = S_DUMP_REGS;
                    end
                end else begin
                    next_byte_idx = byte_idx + 1;
                    next_return_state = S_DUMP_REGS;
                end
            end

            // -------------------------------------------------------------
            // Pipeline Dump (19 words * 4 bytes)
            // -------------------------------------------------------------
            S_DUMP_PIPELINE: begin
                tx_data_o = selected_byte;
                tx_start_o = 1'b1;
                next_state = S_WAIT_TX;

                if (byte_idx == 3) begin
                    next_byte_idx = 0;
                    if (pipe_word_idx == 18) begin
                        // Done with pipeline, setup Memory phase
                        next_return_state = S_DUMP_MEM_CONFIG_1;
                        next_mem_addr = min_addr_i; // Initialize for continuous
                    end else begin
                        next_pipe_word_idx = pipe_word_idx + 1;
                        next_return_state = S_DUMP_PIPELINE;
                    end
                end else begin
                    next_byte_idx = byte_idx + 1;
                    next_return_state = S_DUMP_PIPELINE;
                end
            end

            // -------------------------------------------------------------
            // Memory Config Phase
            // -------------------------------------------------------------
            S_DUMP_MEM_CONFIG_1: begin
                // Cont: MinAddr (4B), Step: Flag (4B)
                tx_data_o = selected_byte;
                tx_start_o = 1'b1;
                next_state = S_WAIT_TX;

                if (byte_idx == 3) begin
                    next_byte_idx = 0;
                    if (latched_mode == 1'b1) begin
                        // Continuous: Go to MaxAddr
                        next_return_state = S_DUMP_MEM_CONFIG_2;
                    end else begin
                        // Step: Check Flag
                        if (dmem_write_en_snoop_i) next_return_state = S_DUMP_MEM_CONFIG_2; // Send Addr
                        else next_return_state = S_DONE; // Flag was 0, done.
                    end
                end else begin
                    next_byte_idx = byte_idx + 1;
                    next_return_state = S_DUMP_MEM_CONFIG_1;
                end
            end

            S_DUMP_MEM_CONFIG_2: begin
                // Cont: MaxAddr (4B), Step: WriteAddr (4B)
                tx_data_o = selected_byte;
                tx_start_o = 1'b1;
                next_state = S_WAIT_TX;

                if (byte_idx == 3) begin
                    next_byte_idx = 0;
                    if (latched_mode == 1'b1) begin
                        // Continuous: Start Payload
                        next_return_state = S_DUMP_MEM_PAYLOAD;
                        next_mem_addr = min_addr_i; // Ensure start at Min
                    end else begin
                        // Step: Send Data
                        next_return_state = S_DUMP_MEM_CONFIG_3;
                    end
                end else begin
                    next_byte_idx = byte_idx + 1;
                    next_return_state = S_DUMP_MEM_CONFIG_2;
                end
            end

            S_DUMP_MEM_CONFIG_3: begin
                // Step Mode Only: WriteData (4B)
                tx_data_o = selected_byte;
                tx_start_o = 1'b1;
                next_state = S_WAIT_TX;

                if (byte_idx == 3) begin
                    next_byte_idx = 0;
                    next_return_state = S_DONE;
                end else begin
                    next_byte_idx = byte_idx + 1;
                    next_return_state = S_DUMP_MEM_CONFIG_3;
                end
            end

            // -------------------------------------------------------------
            // Memory Payload (Continuous Mode Loop)
            // -------------------------------------------------------------
            S_DUMP_MEM_PAYLOAD: begin

                tx_data_o = selected_byte;
                tx_start_o = 1'b1;
                next_state = S_WAIT_TX;

                if (byte_idx == 3) begin
                    next_byte_idx = 0;
                    if (current_mem_addr >= max_addr_i) begin
                        next_return_state = S_DONE;
                    end else begin
                        next_mem_addr = current_mem_addr + 4; // Word align +4
                        next_return_state = S_DUMP_MEM_PAYLOAD;
                    end
                end else begin
                    next_byte_idx = byte_idx + 1;
                    next_return_state = S_DUMP_MEM_PAYLOAD;
                end
            end

            // -------------------------------------------------------------
            // UART Wait Helper
            // -------------------------------------------------------------
            S_WAIT_TX: begin
                if (tx_done_i) begin
                    next_state = return_state;
                end
            end

            // -------------------------------------------------------------
            // Completion
            // -------------------------------------------------------------
            S_DONE: begin
                dump_done_o = 1'b1;
                if (!dump_trigger_i) begin
                    next_state = S_IDLE;
                end
            end

            default: next_state = S_IDLE;
        endcase
    end

endmodule
