// -----------------------------------------------------------------------------
// Module: riscv_core
// Description: Top-level RV32I Pipelined Core.
//              Stitches together Datapath, Control, and Hazard Logic.
// -----------------------------------------------------------------------------

module riscv_core (
    input  logic        clk_i,
    input  logic        rst_ni,

    // Flow Control
    input  logic        global_freeze_i,
    input  logic        soft_reset_i,

    // Instruction Memory Interface
    output logic [31:0] imem_addr_o,
    input  logic [31:0] imem_inst_i,

    // Data Memory Interface
    output logic [31:0] dmem_addr_o,
    output logic [31:0] dmem_wdata_o,
    input  logic [31:0] dmem_rdata_i,
    output logic        dmem_write_en_o,
    output logic [3:0]  dmem_byte_mask_o,
    output logic [31:0] dmem_min_addr_o,
    output logic [31:0] dmem_max_addr_o,

    // Debug Interface (C2)
    input  logic [4:0]  dbg_rf_addr_i,
    output logic [31:0] dbg_rf_data_o,
    
    output logic        core_halted_o,

    // Flattened Debug Taps 
    output logic [95:0]  tap_if_id_o,  // 32+32+32 = 96
    output logic [163:0] tap_id_ex_o,  // 11+128+25 = 164
    output logic [108:0] tap_ex_mem_o, // 5+96+8 = 109
    output logic [103:0] tap_mem_wb_o, // 3+96+5 = 104
    output logic [15:0]  tap_hazard_o
);

    // =========================================================================
    // Internal Signals Definition
    // =========================================================================

    // IF Stage
    logic [31:0] pc_next_if;
    logic [31:0] pc_if;
    logic [31:0] pc_plus_4_if;
    logic [31:0] instr_if;

    // IF/ID Register Output
    logic [31:0] pc_id;
    logic [31:0] instr_id;
    logic [31:0] pc_plus_4_id;

    // ID Stage
    logic [6:0]  opcode_id;
    logic [4:0]  rd_id;
    logic [2:0]  funct3_id;
    logic [4:0]  rs1_id;
    logic [4:0]  rs2_id;
    logic [6:0]  funct7_id;

    // ID Control Signals
    logic        force_nop_id;
    logic        is_halt_id;
    logic        is_branch_id;
    logic        is_jal_id;
    logic        is_jalr_id;
    logic        mem_write_id;
    logic        mem_read_id;
    logic        reg_write_id;
    logic        rd_src_optn_id;
    logic [1:0]  alu_intent_id;
    logic        alu_src_optn_id;

    logic [31:0] rs1_file_data_id;
    logic [31:0] rs2_file_data_id;
    logic [31:0] imm_id;
    logic        data_hzrd_freeze_id;
    logic        zero_id;
    logic        flow_change;
    
    logic [31:0] rs1_data_id; // After Forwarding Mux
    logic [31:0] rs2_data_id; // After Forwarding Mux
    logic [1:0]  forward_rs1_optn;
    logic [1:0]  forward_rs2_optn;
    logic        halt_freeze; // From Halt Unit
    logic [31:0] target_base_id;
    logic [31:0] final_target_addr_id;
    logic [31:0] raw_target_addr_id; // Before masking

    // ID/EX Register Output
    logic        reg_write_ex, mem_write_ex, mem_read_ex;
    logic        alu_src_optn_ex;
    logic [1:0]  alu_intent_ex;
    logic        rd_src_optn_ex;
    logic        is_branch_ex, is_jal_ex, is_jalr_ex, is_halt_ex;
    logic [31:0] pc_ex;
    logic [31:0] rs1_data_ex, rs2_data_ex, imm_ex;
    logic [4:0]  rs1_ex, rs2_ex, rd_ex;
    logic [2:0]  funct3_ex;
    logic [6:0]  funct7_ex;

    // EX Stage
    logic [31:0] alu_op2_ex;
    logic [3:0]  alu_operation_ex;
    logic [31:0] alu_result_ex;
    logic        zero_flag_ex;
    logic [31:0] pc_plus_4_ex;
    logic [31:0] rd_data_ex; // Result of EX stage (ALU or PC+4)

    // EX/MEM Register Output
    logic        reg_write_mem, mem_write_mem, mem_read_mem;
    logic        rd_src_optn_mem;
    logic        is_halt_mem;
    logic [31:0] alu_result_mem;
    logic [31:0] store_data_mem;
    logic [31:0] pc_mem;
    logic [4:0]  rd_mem;
    logic [2:0]  funct3_mem;

    // MEM Stage
    logic [31:0] data_mem_read_data;
    logic [3:0]  data_mem_byte_mask;
    logic [31:0] rd_data_mem; // Result of MEM stage (Load Data)
    logic [31:0] tracker_min_addr, tracker_max_addr;

    // MEM/WB Register Output
    logic        reg_write_wb;
    logic        rd_src_optn_wb;
    logic        is_halt_wb;
    logic [31:0] exec_data_wb; // Passed from EX->MEM->WB
    logic [31:0] read_data_wb; // Loaded data from MEM
    logic [31:0] pc_wb;
    logic [4:0]  rd_wb; 

    // WB Stage
    logic [31:0] final_rd_data_wb;

    // Hazard Status
    logic        program_ended;
    logic        encountered_rs1_forwarding;
    logic        encountered_rs2_forwarding;
    logic        load_use_hazard;
    logic        control_hazard;
    logic        if_id_write_en; 
    logic        pc_write_en;
    logic        if_id_flush;
    logic        id_ex_flush;


    // =========================================================================
    // Hazard & Status Logic
    // =========================================================================

    assign program_ended              = is_halt_wb;
    assign encountered_rs1_forwarding = (forward_rs1_optn != 2'b00);
    assign encountered_rs2_forwarding = (forward_rs2_optn != 2'b00);

    assign load_use_hazard            = data_hzrd_freeze_id && force_nop_id; 
    assign control_hazard             = flow_change;

    assign if_id_flush                = soft_reset_i || flow_change;
    assign id_ex_flush                = soft_reset_i || flow_change || force_nop_id;

    assign if_id_write_en             = !halt_freeze && !data_hzrd_freeze_id && !global_freeze_i;
    assign pc_write_en                = !halt_freeze && !data_hzrd_freeze_id && !global_freeze_i;


    // =========================================================================
    // Stage 1: Instruction Fetch (IF)
    // =========================================================================

    // PC Mux (Next Sequential vs Branch/Jump Target)
    mux2 #(.WIDTH(32)) pc_src_selector (
        .d0_i   (pc_plus_4_if),
        .d1_i   (final_target_addr_id),
        .sel_i  (flow_change),
        .data_o (pc_next_if)
    );

    // Program Counter Register
    program_counter_reg #(.PC_WIDTH(32)) pc_reg_inst (
        .clk             (clk_i),
        .rst_n           (rst_ni),
        .write_en_i      (pc_write_en),
        .soft_reset_i    (soft_reset_i),
        .pc_i            (pc_next_if),
        .pc_o            (pc_if)
    );

    // PC + 4 Adder
    adder fixed_pc_adder_inst_if (
        .adder_op1_i (pc_if),
        .adder_op2_i (32'd4),
        .sum_o       (pc_plus_4_if)
    );

    // Interface Handling
    assign imem_addr_o = pc_if;
    assign instr_if         = imem_inst_i;


    // =========================================================================
    // Pipeline Register: IF -> ID
    // =========================================================================
    
    // Width: PC (32) + Instr (32) + PC+4 (32) = 96 bits
    logic [95:0] if_id_data_in, if_id_data_out;
    assign if_id_data_in = {pc_if, instr_if, pc_plus_4_if};

    pipeline_register #(.WIDTH(96)) if_id_reg (
        .clk             (clk_i),
        .rst_n           (rst_ni),
        .soft_reset_i    (if_id_flush),
        .write_en_i      (if_id_write_en),
        .data_i          (if_id_data_in),
        .data_o          (if_id_data_out)
    );

    // Unpack IF/ID
    assign {pc_id, instr_id, pc_plus_4_id} = if_id_data_out;

    // =========================================================================
    // Stage 2: Instruction Decode (ID)
    // =========================================================================

    instruction_decoder decoder_inst (
        .instruction_word_i (instr_id),
        .opcode_o           (opcode_id),
        .rd_o               (rd_id),
        .funct3_o           (funct3_id),
        .rs1_o              (rs1_id),
        .rs2_o              (rs2_id),
        .funct7_o           (funct7_id)
    );

    control_unit control_inst (
        .opcode_i      (opcode_id),
        .force_nop_i   (force_nop_id),
        .is_halt       (is_halt_id),
        .is_branch     (is_branch_id),
        .is_jal        (is_jal_id),
        .is_jalr       (is_jalr_id),
        .mem_write_en  (mem_write_id),
        .mem_read_en   (mem_read_id),
        .reg_write_en  (reg_write_id),
        .rd_src_optn   (rd_src_optn_id),
        .alu_intent    (alu_intent_id),
        .alu_src_optn  (alu_src_optn_id)
    );

    register_file reg_file_inst (
        .clk             (clk_i),
        .rst_n           (rst_ni),
        .soft_reset_i    (soft_reset_i),
        .rs1_addr_i      (rs1_id),
        .rs2_addr_i      (rs2_id),
        .rs_dbg_addr_i   (dbg_rf_addr_i), 
        .rs1_data_o      (rs1_file_data_id),
        .rs2_data_o      (rs2_file_data_id),
        .rs_dbg_data_o   (dbg_rf_data_o), 
        .rd_addr_i       (rd_wb), // Reg Writes happen at  WB stage
        .write_data_i    (final_rd_data_wb),
        .reg_write_en    (reg_write_wb)
    );

    immediate_generator imm_gen_inst (
        .instruction_word_i (instr_id),
        .ext_immediate_o    (imm_id)
    );

    hazard_protection_unit hazard_unit_inst (
        .rs1_id_i      (rs1_id),
        .rs2_id_i      (rs2_id),
        .mem_read_ex_i (mem_read_ex),
        .rd_ex_i       (rd_ex),
        .freeze_o      (data_hzrd_freeze_id),
        .force_nop_o   (force_nop_id) 
    );

    // Forwarding Muxes (Located in ID for Branch Resolution)
    mux4 rs1_data_selector (
        .d0_i   (rs1_file_data_id),
        .d1_i   (rd_data_ex),
        .d2_i   (rd_data_mem), // Forwarding from MEM stage result (Load or ALU)
        .d3_i   (final_rd_data_wb),
        .sel_i  (forward_rs1_optn),
        .data_o (rs1_data_id)
    );

    mux4 rs2_data_selector (
        .d0_i   (rs2_file_data_id),
        .d1_i   (rd_data_ex),
        .d2_i   (rd_data_mem),
        .d3_i   (final_rd_data_wb),
        .sel_i  (forward_rs2_optn),
        .data_o (rs2_data_id)
    );

    logic [31:0] cmp_result;
    
    // Comparator Logic
    adder #(.IS_SUBTRACTER(1'b1)) comparator (
        .adder_op1_i (rs1_data_id),
        .adder_op2_i (rs2_data_id),
        .sum_o       (cmp_result)
    );
    assign zero_id = (cmp_result == 32'b0);

    flow_controller flow_controller_inst (
        .is_branch_i   (is_branch_id),
        .is_jal_i      (is_jal_id),
        .is_jalr_i     (is_jalr_id),
        .zero_i        (zero_id),
        .funct3_i      (funct3_id),
        .flow_change_o (flow_change)
    );

    forwarding_unit forwarding_unit_inst (
        .rs1_id_i        (rs1_id),
        .rs2_id_i        (rs2_id),
        .reg_write_ex_i  (reg_write_ex),
        .rd_ex_i         (rd_ex),
        .reg_write_mem_i (reg_write_mem),
        .rd_mem_i        (rd_mem),
        .reg_write_wb_i  (reg_write_wb),
        .rd_wb_i         (rd_wb),
        .forward_rs1_o   (forward_rs1_optn),
        .forward_rs2_o   (forward_rs2_optn) 
    );

    halt_unit halt_unit_inst (
        .is_halt_i (is_halt_id),
        .freeze_o  (halt_freeze)
    );

    // Target Calculation
    mux2 target_base_selector (
        .d0_i    (pc_id),
        .d1_i    (rs1_data_id),
        .sel_i   (is_jalr_id),
        .data_o  (target_base_id)
    );

    adder final_target_adder (
        .adder_op1_i   (imm_id),
        .adder_op2_i   (target_base_id),
        .sum_o         (raw_target_addr_id)
    );

    // JALR Masking Compliance (RISC-V Requirement: Target LSB must be 0)
    assign final_target_addr_id = (is_jalr_id) ? (raw_target_addr_id & 32'hFFFFFFFE) : raw_target_addr_id;


    // =========================================================================
    // Pipeline Register: ID -> EX
    // =========================================================================
    
    // Width: 11 Control + 128 Data + 25 Meta = 164 bits
    logic [163:0] id_ex_data_in, id_ex_data_out;
    
    assign id_ex_data_in = {
        // Controls
        reg_write_id, mem_write_id, mem_read_id, alu_src_optn_id, alu_intent_id, rd_src_optn_id, is_branch_id, is_jal_id, is_jalr_id, is_halt_id,
        // Data
        pc_id, rs1_data_id, rs2_data_id, imm_id,
        // Metadata
        rs1_id, rs2_id, rd_id, funct3_id, funct7_id
    };

    pipeline_register #(.WIDTH(164)) id_ex_reg (
        .clk             (clk_i),
        .rst_n           (rst_ni),
        .soft_reset_i    (id_ex_flush),
        .write_en_i      (!global_freeze_i),
        .data_i          (id_ex_data_in),
        .data_o          (id_ex_data_out)
    );

    // Unpack ID/EX
    assign {
        reg_write_ex, mem_write_ex, mem_read_ex, alu_src_optn_ex, alu_intent_ex, rd_src_optn_ex, is_branch_ex, is_jal_ex, is_jalr_ex, is_halt_ex,
        pc_ex, rs1_data_ex, rs2_data_ex, imm_ex,
        rs1_ex, rs2_ex, rd_ex, funct3_ex, funct7_ex
    } = id_ex_data_out;

    // =========================================================================
    // Stage 3: Execution (EX)
    // =========================================================================

    // ALU Source Mux (RS2 vs Immediate)
    mux2 #(.WIDTH(32)) alu_src_selector (
        .d0_i   (rs2_data_ex),
        .d1_i   (imm_ex),
        .sel_i  (alu_src_optn_ex),
        .data_o (alu_op2_ex)
    );

    // ALU Controller
    alu_controller alu_ctrl_inst (
        .alu_intent      (alu_intent_ex),
        .funct3_i        (funct3_ex),
        .funct7_bit30_i  (funct7_ex[5]), 
        .alu_operation_o (alu_operation_ex)
    );

    // ALU
    alu alu_inst (
        .alu_op1_i       (rs1_data_ex),
        .alu_op2_i       (alu_op2_ex),
        .alu_operation_i (alu_operation_ex),
        .alu_result_o    (alu_result_ex),
        .zero_flag_o     (zero_flag_ex)
    );

    // PC+4 Recalculation for Linking
    adder fixed_pc_adder_inst_ex (
        .adder_op1_i  (pc_ex),
        .adder_op2_i  (32'd4),
        .sum_o        (pc_plus_4_ex) 
    );

    // EX Result Mux (ALU Result vs PC+4)
    mux2 rd_data_ex_selector (
        .d0_i    (alu_result_ex),
        .d1_i    (pc_plus_4_ex),
        .sel_i   (is_jal_ex | is_jalr_ex),
        .data_o  (rd_data_ex)
    );


    // =========================================================================
    // Pipeline Register: EX -> MEM
    // =========================================================================
    
    // Width: 5 Control + 96 Data + 8 Meta = 109 bits
    logic [108:0] ex_mem_data_in, ex_mem_data_out;

    assign ex_mem_data_in = {
        reg_write_ex, mem_write_ex, mem_read_ex, rd_src_optn_ex, is_halt_ex,
        rd_data_ex, rs2_data_ex, pc_ex, 
        rd_ex, funct3_ex
    };

    pipeline_register #(.WIDTH(109)) ex_mem_reg (
        .clk             (clk_i),
        .rst_n           (rst_ni),
        .soft_reset_i    (soft_reset_i),
        .write_en_i      (!global_freeze_i), 
        .data_i          (ex_mem_data_in),
        .data_o          (ex_mem_data_out)
    );

    // Unpack EX/MEM
    assign {
        reg_write_mem, mem_write_mem, mem_read_mem, rd_src_optn_mem, is_halt_mem,
        alu_result_mem, store_data_mem, pc_mem,
        rd_mem, funct3_mem
    } = ex_mem_data_out;

    // =========================================================================
    // Stage 4: Memory (MEM)
    // =========================================================================

    assign data_mem_read_data = dmem_rdata_i;

    data_memory_interface dmem_intf_inst (
        .funct3_i            (funct3_mem),
        .alu_result_addr_i   (alu_result_mem[1:0]),
        .rs2_data_i          (store_data_mem),
        .raw_read_data_i     (data_mem_read_data),
        .mem_write_en        (mem_write_mem),
        .byte_enable_mask_o  (data_mem_byte_mask),
        .ram_write_data_o    (dmem_wdata_o),
        .final_read_data_o   (rd_data_mem)
    );

    memory_range_tracker mem_tracker_inst (
        .clk             (clk_i),
        .soft_reset_i    (soft_reset_i),
        .mem_write_en    (mem_write_mem),
        .addr_in_use_i   (alu_result_mem),
        .min_addr_o      (tracker_min_addr),
        .max_addr_o      (tracker_max_addr)
    );

    // Interface Outputs
    assign dmem_addr_o       = {alu_result_mem[31:2], 2'b00}; // Word align
    assign dmem_write_en_o   = mem_write_mem;
    assign dmem_byte_mask_o  = data_mem_byte_mask;
    assign dmem_min_addr_o   = tracker_min_addr;
    assign dmem_max_addr_o   = tracker_max_addr;

    // =========================================================================
    // Pipeline Register: MEM -> WB
    // =========================================================================

    // Width: 3 Control + 96 Data + 5 Meta = 104 bits
    logic [103:0] mem_wb_data_in, mem_wb_data_out;

    assign mem_wb_data_in = {
        reg_write_mem, rd_src_optn_mem, is_halt_mem,
        alu_result_mem, rd_data_mem, pc_mem,
        rd_mem
    };

    pipeline_register #(.WIDTH(104)) mem_wb_reg (
        .clk             (clk_i),
        .rst_n           (rst_ni),
        .soft_reset_i    (soft_reset_i),
        .write_en_i      (!global_freeze_i),
        .data_i          (mem_wb_data_in),
        .data_o          (mem_wb_data_out)
    );

    // Unpack MEM/WB
    assign {
        reg_write_wb, rd_src_optn_wb, is_halt_wb,
        exec_data_wb, read_data_wb, pc_wb,
        rd_wb
    } = mem_wb_data_out;

    // =========================================================================
    // Stage 5: Writeback (WB)
    // =========================================================================

    // WB Mux (Select Final Register Data Src)
    mux2 rd_src_selector (
        .d0_i      (exec_data_wb),
        .d1_i      (read_data_wb),
        .sel_i     (rd_src_optn_wb),
        .data_o    (final_rd_data_wb)
    );
    
    assign core_halted_o = is_halt_wb;

    // =========================================================================
    // Debug Assignments
    // =========================================================================

    // Assignments now map directly without padding
    assign tap_if_id_o  = if_id_data_out; 
    assign tap_id_ex_o  = id_ex_data_out;
    assign tap_ex_mem_o = ex_mem_data_out; 
    assign tap_mem_wb_o = mem_wb_data_out;

    // Hazard Status Output (16 bits)
    assign tap_hazard_o = {
        6'b0,                         // [15:10] Padding
        pc_write_en,                  // [9]     Is PC updating?
        if_id_write_en,               // [8]     Is IF/ID updating?
        control_hazard,               // [7]     Branch/Jump taken?
        load_use_hazard,              // [6]     Stall for Load?
        encountered_rs2_forwarding,   // [5]     Forwarding happened on RS2?
        encountered_rs1_forwarding,   // [4]     Forwarding happened on RS1?
        3'b0,                         // [3:1]   Padding
        program_ended                 // [0]     Halt reached WB?
    };

endmodule
