// -----------------------------------------------------------------------------
// Module: register_file
// Description: RV32I Base Integer Register File (x0-x31).
//              - 32-bit width.
//              - x0 hardwired to 0.
//              - 2 Asynchronous Read Ports.
//              - 1 Synchronous Write Port (posedge clk).
// -----------------------------------------------------------------------------

module register_file #(
    parameter int REG_WIDTH = 32
)(
    input  logic        clk,
    input  logic        rst_n,
    input  logic soft_reset_i,

    // Read Ports
    input  logic [4:0]  rs1_addr_i,
    input  logic [4:0]  rs2_addr_i,

    output logic [REG_WIDTH-1:0] rs1_data_o,
    output logic [REG_WIDTH-1:0] rs2_data_o,

    // For debug purposes
    input  logic [4:0]  rs_dbg_addr_i, 
    output logic [REG_WIDTH-1:0] rs_dbg_data_o,

    // Write Port
    input  logic [4:0]  rd_addr_i,
    input  logic [REG_WIDTH-1:0] write_data_i,
    input  logic        reg_write_en
);


    // Signal Declarations
    logic [REG_WIDTH-1:0] reg_file [31:0]; // 32 registers of 32 bits each
    integer i; // Iterator for reset loop

    // Read Logic (Asynchronous, pure combinational)
    // RISC-V Requirement: Register x0 is always 0.
    assign rs1_data_o = (rs1_addr_i == 5'b0) ? 32'b0 : reg_file[rs1_addr_i];
    assign rs2_data_o = (rs2_addr_i == 5'b0) ? 32'b0 : reg_file[rs2_addr_i];
    assign rs_dbg_data_o = (rs_dbg_addr_i == 5'b0) ? 32'b0 : reg_file[rs_dbg_addr_i];


    // Write Logic (Synchronous)
    always_ff @(negedge clk or negedge rst_n) begin // Active low clk in order to avoid data hazards
        if (!rst_n) begin
            for (i = 0; i < 32; i++) begin
                reg_file[i] <= 32'b0;               // Asynchronous Reset
            end
        end else if (soft_reset_i) begin
            
            for (i = 0; i < 32; i++) begin
                reg_file[i] <= 32'b0;               // Synchronous Reset
            end
        end else if (reg_write_en && (rd_addr_i != 5'b0)) begin

            reg_file[rd_addr_i] <= write_data_i;    // Write Data (if not x0 and write enabled)
        end
    end

endmodule
