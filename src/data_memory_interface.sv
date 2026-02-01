// -----------------------------------------------------------------------------
// Module: data_memory_interface
// Description: Bridge between the CPU core and Data RAM. Handles sub-word 
//              alignment, masking for stores, and sign/zero extension for loads.
// -----------------------------------------------------------------------------

module data_memory_interface (
    input  logic [2:0]  funct3_i,           // Defines access width (Byte/Half/Word) and ext.
    input  logic [1:0]  alu_result_addr_i,  // Address offset (LSBs) for alignment
    input  logic [31:0] rs2_data_i,         // Data to be stored (Store)
    input  logic [31:0] raw_read_data_i,    // Raw 32-bit word read from memory (Load)
    input  logic        mem_write_en,       // Write Enable from Control Unit

    output logic [3:0]  byte_enable_mask_o, // 4-bit write strobe to RAM
    output logic [31:0] ram_write_data_o,   // Data replicated/aligned for RAM
    output logic [31:0] final_read_data_o   // Final extended data to Writeback
);

    // -------------------------------------------------------------------------
    // 1. Store Logic: Alignment & Masking
    // -------------------------------------------------------------------------
    always_comb begin
        // Default values
        byte_enable_mask_o = 4'b0000;
        ram_write_data_o   = 32'b0;

        if (mem_write_en) begin
            case (funct3_i)
                // --- Store Byte (SB) ---
                3'b000: begin 
                    case (alu_result_addr_i)
                        2'b00: begin
                            byte_enable_mask_o = 4'b0001;
                            ram_write_data_o   = {24'b0, rs2_data_i[7:0]};
                        end
                        2'b01: begin
                            byte_enable_mask_o = 4'b0010;
                            ram_write_data_o   = {16'b0, rs2_data_i[7:0], 8'b0};
                        end
                        2'b10: begin
                            byte_enable_mask_o = 4'b0100;
                            ram_write_data_o   = {8'b0, rs2_data_i[7:0], 16'b0};
                        end
                        2'b11: begin
                            byte_enable_mask_o = 4'b1000;
                            ram_write_data_o   = {rs2_data_i[7:0], 24'b0};
                        end
                    endcase
                end

                // --- Store Half (SH) ---
                3'b001: begin 
                    case (alu_result_addr_i[1]) // Check bit 1 for Half alignment (0 or 2)
                        1'b0: begin
                            byte_enable_mask_o = 4'b0011;
                            ram_write_data_o   = {16'b0, rs2_data_i[15:0]};
                        end
                        1'b1: begin
                            byte_enable_mask_o = 4'b1100;
                            ram_write_data_o   = {rs2_data_i[15:0], 16'b0};
                        end
                    endcase
                end

                // --- Store Word (SW) ---
                3'b010: begin 
                    byte_enable_mask_o = 4'b1111;
                    ram_write_data_o   = rs2_data_i;
                end
                
                default: begin
                    byte_enable_mask_o = 4'b0000;
                end
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // 2. Load Logic: Selection & Extension
    // -------------------------------------------------------------------------
    always_comb begin
        final_read_data_o = 32'b0;

        case (funct3_i)
            // --- Load Byte (LB) - Sign Extended ---
            3'b000: begin 
                case (alu_result_addr_i)
                    2'b00: final_read_data_o = {{24{raw_read_data_i[7]}},  raw_read_data_i[7:0]};
                    2'b01: final_read_data_o = {{24{raw_read_data_i[15]}}, raw_read_data_i[15:8]};
                    2'b10: final_read_data_o = {{24{raw_read_data_i[23]}}, raw_read_data_i[23:16]};
                    2'b11: final_read_data_o = {{24{raw_read_data_i[31]}}, raw_read_data_i[31:24]};
                endcase
            end

            // --- Load Half (LH) - Sign Extended ---
            3'b001: begin 
                case (alu_result_addr_i[1])
                    1'b0: final_read_data_o = {{16{raw_read_data_i[15]}}, raw_read_data_i[15:0]};
                    1'b1: final_read_data_o = {{16{raw_read_data_i[31]}}, raw_read_data_i[31:16]};
                endcase
            end

            // --- Load Word (LW) ---
            3'b010: begin 
                final_read_data_o = raw_read_data_i;
            end

            // --- Load Byte Unsigned (LBU) - Zero Extended ---
            3'b100: begin 
                case (alu_result_addr_i)
                    2'b00: final_read_data_o = {24'b0, raw_read_data_i[7:0]};
                    2'b01: final_read_data_o = {24'b0, raw_read_data_i[15:8]};
                    2'b10: final_read_data_o = {24'b0, raw_read_data_i[23:16]};
                    2'b11: final_read_data_o = {24'b0, raw_read_data_i[31:24]};
                endcase
            end

            // --- Load Half Unsigned (LHU) - Zero Extended ---
            3'b101: begin 
                case (alu_result_addr_i[1])
                    1'b0: final_read_data_o = {16'b0, raw_read_data_i[15:0]};
                    1'b1: final_read_data_o = {16'b0, raw_read_data_i[31:16]};
                endcase
            end

            default: final_read_data_o = 32'b0;
        endcase
    end

endmodule
