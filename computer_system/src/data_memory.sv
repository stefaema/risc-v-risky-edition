// Asynchronic Memory
// Supports Bye-enable
module data_memory #(
    parameter int DEPTH = 256
)(
    input  logic        clk_i,
    
    // Port A: Core
    input  logic [3:0]  we_a_i,   
    input  logic [31:0] addr_a_i,
    input  logic [31:0] data_a_i,   
    output logic [31:0] data_a_o,    

    // Puerto B: Dumper (Snoop)
    input  logic [31:0] addr_b_i,    
    output logic [31:0] data_b_o     
);

    // Force VIVADO to use LUTRAM (Distributed RAM).
    (* ram_style = "distributed" *)
    logic [7:0] mem [0:DEPTH-1][0:3];

    // Synchronous Write (Port A)
    always_ff @(posedge clk_i) begin
        if (we_a_i[0]) mem[addr_a_i[11:2]][0] <= data_a_i[7:0];
        if (we_a_i[1]) mem[addr_a_i[11:2]][1] <= data_a_i[15:8];
        if (we_a_i[2]) mem[addr_a_i[11:2]][2] <= data_a_i[23:16];
        if (we_a_i[3]) mem[addr_a_i[11:2]][3] <= data_a_i[31:24];
    end

    // Asynchronous Read
    assign data_a_o = { mem[addr_a_i[11:2]][3], 
                        mem[addr_a_i[11:2]][2], 
                        mem[addr_a_i[11:2]][1], 
                        mem[addr_a_i[11:2]][0] };

    assign data_b_o = { mem[addr_b_i[11:2]][3], 
                        mem[addr_b_i[11:2]][2], 
                        mem[addr_b_i[11:2]][1], 
                        mem[addr_b_i[11:2]][0] };

endmodule
