// -----------------------------------------------------------------------------
// Module: register_file
// Description: RV32I Base Integer Register File (x0-x31).
//              - 32-bit width.
//              - x0 hardwired to 0.
//              - 2 Asynchronous Read Ports.
//              - 1 Synchronous Write Port (posedge clk).
// -----------------------------------------------------------------------------

module register_file (
    input  logic        clk,
    input  logic        rst_n,
    
    // Read Ports
    input  logic [4:0]  rs1_addr,
    input  logic [4:0]  rs2_addr,
    output logic [31:0] read_data1,
    output logic [31:0] read_data2,

    // Write Port
    input  logic [4:0]  rd_addr,
    input  logic [31:0] write_data,
    input  logic        reg_write_en
);


    // Signal Declarations
    logic [31:0] reg_file [31:0]; // 32 registers of 32 bits each
    integer i; // Iterator for reset loop

    // Read Logic (Asynchronous)
    // RISC-V Requirement: Register x0 is always 0.
    assign read_data1 = (rs1_addr == 5'b0) ? 32'b0 : reg_file[rs1_addr];
    assign read_data2 = (rs2_addr == 5'b0) ? 32'b0 : reg_file[rs2_addr];

    // Write Logic (Synchronous)
    always_ff @(negedge clk or negedge rst_n) begin // Active low clk in order to avoid data hazards
        if (!rst_n) begin
            // Reset all registers to 0
            for (i = 0; i < 32; i++) begin
                reg_file[i] <= 32'b0;
            end
        end else if (reg_write_en && (rd_addr != 5'b0)) begin
            // Write only if enabled and destination is NOT x0
            reg_file[rd_addr] <= write_data;
        end
    end

endmodule
