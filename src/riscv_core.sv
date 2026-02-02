// -----------------------------------------------------------------------------
// Module: riscv_core
// Description: Top-level RV32I Pipelined Core.
//              Stitches together Datapath, Control, and Hazard Logic.
// -----------------------------------------------------------------------------

module riscv_core (
    input  logic        clk_i,
    input  logic        rst_ni,

    // Flow Control
    input  logic        global_stall_i,
    input  logic        global_flush_i,

    // Instruction Memory Interface
    output logic [31:0] instr_mem_addr_o,
    input  logic [31:0] instr_mem_data_i,

    // Data Memory Interface
    output logic [31:0] data_mem_addr_o,
    output logic [31:0] data_mem_write_data_o,
    input  logic [31:0] data_mem_read_data_i,
    output logic        data_mem_write_en_o,
    output logic [3:0]  data_mem_byte_mask_o,
    output logic [31:0] data_mem_min_addr_o,
    output logic [31:0] data_mem_max_addr_o,

    // Debug Interface (C2)
    input  logic [4:0]  rs_dbg_addr_i,
    output logic [31:0] rs_dbg_data_o,
    
    output logic [31:0] core_pc_o, // Current PC (Fetch) for Top Level Muxing
    output logic        core_halted_o,

    // Flattened Debug Taps
    output logic [63:0] if_id_flat_o,
    output logic [167:0] id_ex_flat_o,
    output logic [111:0] ex_mem_flat_o,
    output logic [111:0] mem_wb_flat_o,
    output logic [15:0] hazard_status_o
);

    // =========================================================================
    // Internal Signals Definition
    // =========================================================================

    // --- Fetch Stage (IF) ---
    logic [31:0] pc_f;
    logic [31:0] pc_next_f;
    logic [31:0] pc_plus_4_f;
    logic [31:0] instr_f;
    logic        pc_write_en;

    // --- Decode Stage (ID) ---
    logic [31:0] pc_d;
    logic [31:0] instr_d;
    logic [31:0] pc_plus_4_d; // Passed for Linking

    logic [6:0]  opcode_d;
    logic [4:0]  rd_addr_d;
    logic [2:0]  funct3_d;
    logic [4:0]  rs1_addr_d;
    logic [4:0]  rs2_addr_d;
    logic [6:0]  funct7_d;

    logic [31:0] rs1_data_d;
    logic [31:0] rs2_data_d;
    logic [31:0] imm_d;

    // Control Signals (ID)
    logic is_halt_d, is_branch_d, is_jal_d, is_jalr_d;
    logic mem_write_d, mem_read_d, reg_write_d;
    logic [1:0] rd_src_optn_d;
    logic [1:0] alu_intent_d;
    logic alu_src_optn_d;

    // --- Execute Stage (EX) ---
    logic [31:0] pc_e;
    logic [31:0] pc_plus_4_e;
    logic [31:0] rs1_data_e;
    logic [31:0] rs2_data_e;
    logic [31:0] imm_e;
    logic [4:0]  rs1_addr_e;
    logic [4:0]  rs2_addr_e;
    logic [4:0]  rd_addr_e;
    logic [2:0]  funct3_e;
    logic [6:0]  funct7_e;

    // Control Signals (EX)
    logic is_halt_e, is_branch_e, is_jal_e, is_jalr_e;
    logic mem_write_e, mem_read_e, reg_write_e;
    logic [1:0] rd_src_optn_e;
    logic [1:0] alu_intent_e;
    logic alu_src_optn_e;

    // ALU & Flow Logic
    logic [31:0] forward_a_val_e;
    logic [31:0] forward_b_val_e;
    logic [31:0] alu_op2_val_e;
    logic [3:0]  alu_operation_e;
    logic [31:0] alu_result_e;
    logic        zero_flag_e;
    logic [31:0] pc_imm_target_e;
    logic [31:0] final_target_addr_e;
    logic        pc_src_optn_e;
    logic        redirect_req_e;
    logic        halt_detected_e;

    // --- Memory Stage (MEM) ---
    logic [31:0] pc_plus_4_m;
    logic [31:0] alu_result_m;
    logic [31:0] store_data_m; // Forwarded rs2_data
    logic [4:0]  rd_addr_m;
    logic [2:0]  funct3_m;
    
    // Control Signals (MEM)
    logic is_halt_m;
    logic mem_write_m, mem_read_m, reg_write_m;
    logic [1:0] rd_src_optn_m;

    logic [31:0] ram_write_data_m; // Aligned
    logic [31:0] final_read_data_m; // From Mem Interface
    
    // Range Tracker Outputs (Internal to Core wrapper but logic exists)
    logic [31:0] tracker_min_addr;
    logic [31:0] tracker_max_addr;

    // --- Writeback Stage (WB) ---
    logic [31:0] pc_plus_4_w;
    logic [31:0] alu_result_w;
    logic [31:0] final_read_data_w;
    logic [4:0]  rd_addr_w;

    // Control Signals (WB)
    logic is_halt_w;
    logic reg_write_w;
    logic [1:0] rd_src_optn_w;

    logic [31:0] final_rd_data_w; // Data to write to RegFile

    // --- Hazard & Forwarding Signals ---
    logic [1:0] forward_a_optn;
    logic [1:0] forward_b_optn;
    
    logic if_id_write_en;
    logic if_id_flush;
    logic id_ex_write_en;
    logic id_ex_flush;

    // =========================================================================
    // Stage 1: Instruction Fetch (IF)
    // =========================================================================

    // PC Mux (Next Sequential vs Branch/Jump Target)
    mux2 #(.WIDTH(32)) pc_src_selector (
        .d0_i   (pc_plus_4_f),
        .d1_i   (final_target_addr_e),
        .sel_i  (pc_src_optn_e),
        .data_o (pc_next_f)
    );

    // Program Counter Register
    program_counter_reg #(.PC_WIDTH(32)) pc_reg_inst (
        .clk            (clk_i),
        .rst_n          (rst_ni),
        .write_en_i     (pc_write_en),
        .global_stall_i (global_stall_i),
        .global_flush_i (global_flush_i),
        .pc_i           (pc_next_f),
        .pc_o           (pc_f)
    );

    // PC + 4 Adder
    adder #(.ADDER_WIDTH(32)) fixed_pc_adder_inst (
        .adder_op1_i (pc_f),
        .adder_op2_i (32'd4),
        .sum_o       (pc_plus_4_f)
    );

    // Interface Outputs
    assign instr_mem_addr_o = pc_f;
    assign instr_f          = instr_mem_data_i;
    assign core_pc_o        = pc_f; // For Top Level Mux. Review after all codebase done.

    // =========================================================================
    // Pipeline Register: IF -> ID
    // =========================================================================
    
    // Logic to pack IF data
    logic [63:0] if_id_data_in, if_id_data_out;
    assign if_id_data_in = {pc_f, instr_f};

    pipeline_register #(.WIDTH(64)) if_id_reg (
        .clk            (clk_i),
        .rst_n          (rst_ni),
        .flush_i        (if_id_flush),
        .global_flush_i (global_flush_i),
        .write_en_i     (if_id_write_en),
        .global_stall_i (global_stall_i),
        .data_i         (if_id_data_in),
        .data_o         (if_id_data_out)
    );

    // Unpack IF/ID
    assign {pc_d, instr_d} = if_id_data_out;

    // =========================================================================
    // Stage 2: Instruction Decode (ID)
    // =========================================================================

    instruction_decoder decoder_inst (
        .instruction_word_i (instr_d),
        .opcode_o           (opcode_d),
        .rd_o               (rd_addr_d),
        .funct3_o           (funct3_d),
        .rs1_o              (rs1_addr_d),
        .rs2_o              (rs2_addr_d),
        .funct7_o           (funct7_d)
    );

    control_unit control_inst (
        .opcode_i      (opcode_d),
        .is_halt       (is_halt_d),
        .is_branch     (is_branch_d),
        .is_jal        (is_jal_d),
        .is_jalr       (is_jalr_d),
        .mem_write_en  (mem_write_d),
        .mem_read_en   (mem_read_d),
        .reg_write_en  (reg_write_d),
        .rd_src_optn   (rd_src_optn_d),
        .alu_intent    (alu_intent_d),
        .alu_src_optn  (alu_src_optn_d)
    );

    register_file reg_file_inst (
        .clk            (clk_i),
        .rst_n          (rst_ni),
        .rs1_addr_i     (rs1_addr_d),
        .rs2_addr_i     (rs2_addr_d),
        .rs_dbg_addr_i  (rs_dbg_addr_i), // Debug Port Input
        .rs1_data_o     (rs1_data_d),
        .rs2_data_o     (rs2_data_d),
        .rs_dbg_data_o  (rs_dbg_data_o), // Debug Port Output
        .rd_addr_i      (rd_addr_w),
        .write_data_i   (final_rd_data_w),
        .reg_write_en   (reg_write_w)
    );

    immediate_generator imm_gen_inst (
        .instruction_word_i (instr_d),
        .ext_immediate_o    (imm_d)
    );

    hazard_protection_unit hazard_unit_inst (
        .rs1_addr_id_i    (rs1_addr_d),
        .rs2_addr_id_i    (rs2_addr_d),
        .id_ex_mem_read_i (mem_read_e),
        .id_ex_rd_i       (rd_addr_e),
        .redirect_req_i   (redirect_req_e),
        .halt_detected_i  (halt_detected_e),
        .pc_write_en_o    (pc_write_en),
        .if_id_write_en_o (if_id_write_en),
        .if_id_flush_o    (if_id_flush),
        .id_ex_write_en_o (id_ex_write_en),
        .id_ex_flush_o    (id_ex_flush)
    );

    // =========================================================================
    // Pipeline Register: ID -> EX
    // =========================================================================
    
    // Structs would be cleaner, but using packed vectors for portability/style
    // Payload: Controls (13b) + Data (128b) + Metadata (22b) -> Total ~163 bits
    // Control Bus: {is_halt, is_branch, is_jal, is_jalr, mem_we, mem_re, reg_we, rd_src_optn, alu_intent, alu_src_optn}
    
    logic [162:0] id_ex_data_in, id_ex_data_out;
    
    assign id_ex_data_in = {
        // Controls (13 bits)
        is_halt_d, is_branch_d, is_jal_d, is_jalr_d,
        mem_write_d, mem_read_d, reg_write_d,
        rd_src_optn_d, alu_intent_d, alu_src_optn_d,
        // Data (128 bits)
        pc_d, rs1_data_d, rs2_data_d, imm_d,
        // Metadata (22 bits)
        rs1_addr_d, rs2_addr_d, rd_addr_d, funct3_d, funct7_d
    };

    pipeline_register #(.WIDTH(163)) id_ex_reg (
        .clk            (clk_i),
        .rst_n          (rst_ni),
        .flush_i        (id_ex_flush),
        .global_flush_i (global_flush_i),
        .write_en_i     (id_ex_write_en),
        .global_stall_i (global_stall_i),
        .data_i         (id_ex_data_in),
        .data_o         (id_ex_data_out)
    );

    // Unpack ID/EX
    assign {
        is_halt_e, is_branch_e, is_jal_e, is_jalr_e,
        mem_write_e, mem_read_e, reg_write_e,
        rd_src_optn_e, alu_intent_e, alu_src_optn_e,
        pc_e, rs1_data_e, rs2_data_e, imm_e,
        rs1_addr_e, rs2_addr_e, rd_addr_e, funct3_e, funct7_e
    } = id_ex_data_out;

    // =========================================================================
    // Stage 3: Execution (EX)
    // =========================================================================

    // Forwarding Unit
    forwarding_unit fwd_unit_inst (
        .rs1_id_ex_i         (rs1_addr_e),
        .rs2_id_ex_i         (rs2_addr_e),
        .rd_ex_mem_i         (rd_addr_m),
        .reg_write_ex_mem_en (reg_write_m),
        .mem_read_ex_mem_en  (mem_read_m),
        .rd_mem_wb_i         (rd_addr_w),
        .reg_write_mem_wb_en (reg_write_w),
        .forward_a_optn_o    (forward_a_optn),
        .forward_b_optn_o    (forward_b_optn)
    );

    // Operand A Mux (Forwarding)
    mux4 #(.WIDTH(32)) fwd_op_a_selector (
        .d0_i   (rs1_data_e),
        .d1_i   (final_rd_data_w), // WB Forwarding
        .d2_i   (alu_result_m),    // EX/MEM Forwarding
        .sel_i  (forward_a_optn),
        .data_o (forward_a_val_e)
    );

    // Operand B Mux (Forwarding)
    mux4 #(.WIDTH(32)) fwd_op_b_selector (
        .d0_i   (rs2_data_e),
        .d1_i   (final_rd_data_w), // WB Forwarding
        .d2_i   (alu_result_m),    // EX/MEM Forwarding
        .sel_i  (forward_b_optn),
        .data_o (forward_b_val_e)  // NOTE: This is the correct data for STOREs
    );

    // ALU Source Mux (Reg/Fwd vs Immediate)
    mux2 #(.WIDTH(32)) alu_src_selector (
        .d0_i   (forward_b_val_e),
        .d1_i   (imm_e),
        .sel_i  (alu_src_optn_e),
        .data_o (alu_op2_val_e)
    );

    // ALU Controller
    alu_controller alu_ctrl_inst (
        .alu_intent      (alu_intent_e),
        .funct3_i        (funct3_e),
        .funct7_bit30_i  (funct7_e[5]), // Bit 30 is at index 5 of funct7[6:0]
        .alu_operation_o (alu_operation_e)
    );

    // ALU
    alu alu_inst (
        .alu_op1_i       (forward_a_val_e),
        .alu_op2_i       (alu_op2_val_e),
        .alu_operation_i (alu_operation_e),
        .alu_result_o    (alu_result_e),
        .zero_flag_o     (zero_flag_e)
    );

    // Branch Target Adder (PC + Imm)
    adder #(.WIDTH(32)) imm_pc_adder_inst (
        .adder_op1_i (pc_e),
        .adder_op2_i (imm_e),
        .sum_o       (pc_imm_target_e)
    );

    // Flow Controller
    flow_controller flow_ctrl_inst (
        .is_branch_i         (is_branch_e),
        .is_jal_i            (is_jal_e),
        .is_jalr_i           (is_jalr_e),
        .is_halt_i           (is_halt_e),
        .funct3_i            (funct3_e),
        .zero_i              (zero_flag_e),
        .pc_imm_target_i     (pc_imm_target_e),
        .alu_target_i        (alu_result_e),
        .pc_src_optn_o       (pc_src_optn_e),
        .redirect_req_o      (redirect_req_e),
        .halt_detected_o     (halt_detected_e),
        .final_target_addr_o (final_target_addr_e)
    );

    // Helper for linking
    assign pc_plus_4_e = pc_e + 32'd4;

    // =========================================================================
    // Pipeline Register: EX -> MEM
    // =========================================================================
    
    // Payload: Ctrl (5b) + Data (96b) + Meta (8b) -> ~109 bits
    // Ctrl: {is_halt, mem_we, mem_re, reg_we, rd_src}
    
    logic [108:0] ex_mem_data_in, ex_mem_data_out;

    assign ex_mem_data_in = {
        is_halt_e, mem_write_e, mem_read_e, reg_write_e, rd_src_optn_e,
        alu_result_e, forward_b_val_e, pc_plus_4_e, // Store data is fwd_b_val
        rd_addr_e, funct3_e
    };

    pipeline_register #(.WIDTH(109)) ex_mem_reg (
        .clk            (clk_i),
        .rst_n          (rst_ni),
        .flush_i        (1'b0), // No flush logic for EX/MEM
        .global_flush_i (global_flush_i),
        .write_en_i     (1'b1), // Always enabled (except global)
        .global_stall_i (global_stall_i),
        .data_i         (ex_mem_data_in),
        .data_o         (ex_mem_data_out)
    );

    // Unpack EX/MEM
    assign {
        is_halt_m, mem_write_m, mem_read_m, reg_write_m, rd_src_optn_m,
        alu_result_m, store_data_m, pc_plus_4_m,
        rd_addr_m, funct3_m
    } = ex_mem_data_out;

    // =========================================================================
    // Stage 4: Memory (MEM)
    // =========================================================================

    data_memory_interface dmem_intf_inst (
        .funct3_i           (funct3_m),
        .alu_result_addr_i  (alu_result_m[1:0]),
        .rs2_data_i         (store_data_m),
        .raw_read_data_i    (data_mem_read_data_i),
        .mem_write_en       (mem_write_m),
        .byte_enable_mask_o (data_mem_byte_mask_o),
        .ram_write_data_o   (ram_write_data_m),
        .final_read_data_o  (final_read_data_m)
    );

    memory_range_tracker mem_tracker_inst (
        .clk            (clk_i),
        .global_flush_i (global_flush_i),
        .mem_write_en   (mem_write_m),
        .addr_in_use_i  (alu_result_m),
        .min_addr_o     (tracker_min_addr),
        .max_addr_o     (tracker_max_addr)
    );

    // Interface Outputs
    assign data_mem_addr_o       = alu_result_m; // byte-aligned address
    assign data_mem_write_data_o = ram_write_data_m;
    assign data_mem_write_en_o   = mem_write_m;
    assign data_mem_min_addr_o   = tracker_min_addr; // Output from Tracker. Used externally.
    assign data_mem_max_addr_o   = tracker_max_addr;

    // =========================================================================
    // Pipeline Register: MEM -> WB
    // =========================================================================

    // Payload: Ctrl (4b) + Data (96b) + Meta (5b) -> 105 bits
    // Ctrl: {is_halt, reg_we, rd_src}
    
    logic [104:0] mem_wb_data_in, mem_wb_data_out;

    assign mem_wb_data_in = {
        is_halt_m, reg_write_m, rd_src_optn_m,
        alu_result_m, final_read_data_m, pc_plus_4_m,
        rd_addr_m
    };

    pipeline_register #(.WIDTH(105)) mem_wb_reg (
        .clk            (clk_i),
        .rst_n          (rst_ni),
        .flush_i        (1'b0),
        .global_flush_i (global_flush_i),
        .write_en_i     (1'b1),
        .global_stall_i (global_stall_i),
        .data_i         (mem_wb_data_in),
        .data_o         (mem_wb_data_out)
    );

    // Unpack MEM/WB
    assign {
        is_halt_w, reg_write_w, rd_src_optn_w,
        alu_result_w, final_read_data_w, pc_plus_4_w,
        rd_addr_w
    } = mem_wb_data_out;

    // =========================================================================
    // Stage 5: Writeback (WB)
    // =========================================================================

    // WB Mux (Select Final Register Data Src for Writing it back into RegFile)
    mux4 #(.WIDTH(32)) rd_wb_src_selector (
        .d0_i   (alu_result_w),      // 00: ALU
        .d1_i   (pc_plus_4_w),       // 01: PC+4
        .d2_i   (final_read_data_w), // 10: MEM
        .sel_i  (rd_src_optn_w),
        .data_o (final_rd_data_w)
    );

    assign core_halted_o = is_halt_w;

    // =========================================================================
    // Debug & Flattening Assignments
    // =========================================================================

    // IF/ID Flat (8 Bytes): [63:32] Inst, [31:0] PC
    assign if_id_flat_o = {instr_f, pc_f}; 

    // ID/EX Flat (Packed ~21 Bytes)
    // Map based on spec expectations: Ctrl, PC, RS1, RS2, Imm, Meta
    // Control Bus (2B): Pad {is_halt, is_branch, is_jal, is_jalr, mem_we, mem_re, reg_we, rd_src(2), alu_intent(2), alu_src} to 16 bits
    logic [15:0] id_ex_ctrl_flat;
    assign id_ex_ctrl_flat = {3'b0, is_halt_d, is_branch_d, is_jal_d, is_jalr_d, mem_write_d, mem_read_d, reg_write_d, rd_src_optn_d, alu_intent_d, alu_src_optn_d};
    
    // Metadata (3B): rs1(5), rs2(5), rd(5), funct3(3), funct7(7) -> 25 bits. 
    // Truncating upper bit of funct7 or packing tightly? Spec says "Padded to 21 Bytes".
    // Let's pack naturally:
    assign id_ex_flat_o = {
        id_ex_ctrl_flat,    // 16 bits
        pc_d,               // 32 bits
        rs1_data_d,         // 32 bits
        rs2_data_d,         // 32 bits
        imm_d,              // 32 bits
        7'b0,               // Padding
        rs1_addr_d, rs2_addr_d, rd_addr_d, funct3_d, funct7_d[5] // Minimal metadata (using bit 30 of funct7)
    };

    // EX/MEM Flat (14 Bytes)
    // Ctrl(1B), ALU(4B), RS2(4B), PC+4(4B), Meta(1B)
    logic [7:0] ex_mem_ctrl_flat;
    assign ex_mem_ctrl_flat = {3'b0, is_halt_e, mem_write_e, mem_read_e, reg_write_e, rd_src_optn_e}; // 1+1+1+1+2 = 6 bits
    
    assign ex_mem_flat_o = {
        ex_mem_ctrl_flat,   // 8 bits
        alu_result_e,       // 32 bits
        forward_b_val_e,    // 32 bits (Store Data)
        pc_plus_4_e,        // 32 bits
        3'b0, rd_addr_e     // 8 bits
    };

    // MEM/WB Flat (14 Bytes)
    // Ctrl(1B), Final(4B), PC+4(4B), Meta(1B), Padding(4B)
    logic [7:0] mem_wb_ctrl_flat;
    assign mem_wb_ctrl_flat = {4'b0, is_halt_m, reg_write_m, rd_src_optn_m}; // 1+1+2 = 4 bits

    assign mem_wb_flat_o = {
        mem_wb_ctrl_flat,   // 8 bits
        final_rd_data_w,    // 32 bits (Wait, spec says "Final Result") -> Using Mux Output here? No, spec says MEM/WB payload. 
                            // The Pipeline Register carries ALU and MEM Read. 
                            // Spec 10.5.3: "MEM/WB... Final_Data". This usually implies the data AFTER the mux.
                            // But the "Pipeline Register" taps usually show what is IN the register.
                            // I will output what is IN the register (ALU Result) or Construct the final data.
                            // Since it's for Debug Dump, "Final_Data" usually means what was written.
                            // I will connect this to 'final_rd_data_w' which is combinational output of WB stage.
        final_rd_data_w,
        pc_plus_4_m,        // 32 bits
        3'b0, rd_addr_m,    // 8 bits
        32'b0               // Padding
    };

    // Hazard Status (2 Bytes)
    // Byte 0: [4]ID_Flush, [3]IF_Flush, [2]EX_Stall, [1]ID_Stall, [0]PC_Stall
    // Note: My stall signals are enable (1=Run), so Stall = !Enable.
    assign hazard_status_o = {
        6'b0, forward_a_optn, forward_b_optn, // Byte 1
        3'b0, id_ex_flush, if_id_flush, !1'b1, !id_ex_write_en, !pc_write_en // Byte 0 (EX Stall hardwired 0)
    };

endmodule
