// -----------------------------------------------------------------------------
// Module: uart_transceiver
// Description: Wrapper completo para la capa fisica UART (RX + TX + BaudGen)
// -----------------------------------------------------------------------------

module uart_transceiver #(
    parameter int CLK_FREQ = 100_000_000
) (
    input  logic       clk_i,
    input  logic       rst_ni,
    input  logic [1:0] baud_selector_i,

    // RX Interface
    input  logic       rx_i,
    output logic [7:0] rx_data_o,
    output logic       rx_ready_o,
    output logic       rx_error_o,

    // TX Interface
    input  logic [7:0] tx_data_i,
    input  logic       tx_start_i,
    output logic       tx_o,
    output logic       tx_busy_o,
    output logic       tx_done_o
);

    logic tick_16x;

    baud_rate_generator #(.CLK_FREQ(CLK_FREQ)) baud_gen_inst (
        .clk_i(clk_i), .rst_ni(rst_ni), .baud_selector_i(baud_selector_i), .tick_16x_o(tick_16x)
    );

    uart_rx rx_inst (
        .clk_i(clk_i), .rst_ni(rst_ni), .rx_i(rx_i), .tick_16x_i(tick_16x),
        .data_o(rx_data_o), .ready_o(rx_ready_o), .error_o(rx_error_o)
    );

    uart_tx tx_inst (
        .clk_i(clk_i), .rst_ni(rst_ni), .tick_16x_i(tick_16x),
        .data_i(tx_data_i), .start_i(tx_start_i),
        .tx_o(tx_o), .busy_o(tx_busy_o), .done_o(tx_done_o)
    );

endmodule

// -----------------------------------------------------------------------------
// Sub-Module: Baud Rate Generator
// -----------------------------------------------------------------------------
module baud_rate_generator #(parameter int CLK_FREQ)(
    input logic clk_i, rst_ni, 
    input logic [1:0] baud_selector_i, 
    output logic tick_16x_o
);
    // Pre-calculo de divisores
    localparam int DIV_9600   = (CLK_FREQ / (9600   * 16)) - 1;
    localparam int DIV_19200  = (CLK_FREQ / (19200  * 16)) - 1;
    localparam int DIV_57600  = (CLK_FREQ / (57600  * 16)) - 1;
    localparam int DIV_115200 = (CLK_FREQ / (115200 * 16)) - 1;

    logic [$clog2(DIV_9600)-1:0] counter, divisor;
    logic [1:0] baud_sel_d;

    always_comb begin
        case (baud_selector_i)
            2'b00: divisor = DIV_9600;
            2'b01: divisor = DIV_19200;
            2'b10: divisor = DIV_57600;
            2'b11: divisor = DIV_115200;
            default: divisor = DIV_9600;
        endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            counter <= '0; baud_sel_d <= '0;
        end else begin
            if (baud_selector_i != baud_sel_d) begin
                baud_sel_d <= baud_selector_i; counter <= '0;
            end else if (counter == divisor) begin
                counter <= '0;
            end else begin
                counter <= counter + 1;
            end
        end
    end
    assign tick_16x_o = (counter == divisor);
endmodule

// -----------------------------------------------------------------------------
// Sub-Module: RX 
// -----------------------------------------------------------------------------
module uart_rx (
    input logic clk_i, rst_ni, rx_i, tick_16x_i,
    output logic [7:0] data_o, output logic ready_o, error_o
);
    typedef enum logic [2:0] {S_IDLE, S_START, S_DATA, S_STOP, S_DONE} state_t;
    state_t state, next_state;
    logic [3:0] tick_cnt, next_tick_cnt;
    logic [2:0] bit_idx, next_bit_idx;
    logic [7:0] shift, next_shift;
    logic rx_s1, rx_s2;

    // Synchronization
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin rx_s1 <= 1; rx_s2 <= 1; end
        else begin rx_s1 <= rx_i; rx_s2 <= rx_s1; end
    end

    logic start_detected;
    assign start_detected = (rx_s2 == 1'b1) && (rx_s1 == 1'b0); 

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state <= S_IDLE; tick_cnt <= 0; bit_idx <= 0; shift <= 0; data_o <= 0;
        end else begin
            state <= next_state; tick_cnt <= next_tick_cnt; 
            bit_idx <= next_bit_idx; shift <= next_shift;
            if (state == S_STOP && next_state == S_DONE && rx_s2) data_o <= shift;
        end
    end

    always_comb begin
        next_state = state; next_tick_cnt = tick_cnt; 
        next_bit_idx = bit_idx; next_shift = shift;
        ready_o = 0; error_o = 0;

        case (state)
            S_IDLE: if (start_detected) begin
                next_state = S_START; next_tick_cnt = 0;
            end
            S_START: if (tick_16x_i) begin
                if (tick_cnt == 7) begin
                    next_tick_cnt = 0;
                    // Check if still low at center
                    next_state = (rx_s2 == 0) ? S_DATA : S_IDLE; 
                    next_bit_idx = 0;
                end else next_tick_cnt = tick_cnt + 1;
            end
            S_DATA: if (tick_16x_i) begin
                if (tick_cnt == 15) begin
                    next_tick_cnt = 0;
                    next_shift = {rx_s2, shift[7:1]}; // LSB First
                    if (bit_idx == 7) next_state = S_STOP;
                    else next_bit_idx = bit_idx + 1;
                end else next_tick_cnt = tick_cnt + 1;
            end
            S_STOP: if (tick_16x_i) begin
                if (tick_cnt == 15) begin
                    if (rx_s2) next_state = S_DONE;
                    else begin error_o = 1; next_state = S_IDLE; end
                end else next_tick_cnt = tick_cnt + 1;
            end
            S_DONE: begin ready_o = 1; next_state = S_IDLE; end
        endcase
    end
endmodule

// -----------------------------------------------------------------------------
// Sub-Module: TX
// -----------------------------------------------------------------------------
module uart_tx (
    input logic clk_i, rst_ni, tick_16x_i, [7:0] data_i, input logic start_i,
    output logic tx_o, busy_o, done_o
);
    typedef enum logic [1:0] {S_IDLE, S_START, S_DATA, S_STOP} state_t;
    state_t state, next_state;
    logic [3:0] tick_cnt, next_tick_cnt;
    logic [2:0] bit_idx, next_bit_idx;
    logic [7:0] shift, next_shift;
    logic tx_reg, next_tx_reg;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state <= S_IDLE; tick_cnt <= 0; bit_idx <= 0; shift <= 0; tx_reg <= 1;
        end else begin
            state <= next_state; tick_cnt <= next_tick_cnt; 
            bit_idx <= next_bit_idx; shift <= next_shift; tx_reg <= next_tx_reg;
        end
    end
    assign tx_o = tx_reg;

    always_comb begin
        next_state = state; next_tick_cnt = tick_cnt; next_bit_idx = bit_idx;
        next_shift = shift; next_tx_reg = tx_reg;
        busy_o = 1; done_o = 0;

        case (state)
            S_IDLE: begin
                busy_o = 0; next_tx_reg = 1;
                if (start_i) begin
                    next_shift = data_i; next_state = S_START; 
                    next_tick_cnt = 0; next_tx_reg = 0;
                end
            end
            S_START: if (tick_16x_i) begin
                if (tick_cnt == 15) begin
                    next_tick_cnt = 0; next_state = S_DATA; next_bit_idx = 0;
                    next_tx_reg = shift[0];
                end else next_tick_cnt = tick_cnt + 1;
            end
            S_DATA: if (tick_16x_i) begin
                if (tick_cnt == 15) begin
                    next_tick_cnt = 0;
                    if (bit_idx == 7) begin next_state = S_STOP; next_tx_reg = 1; end
                    else begin
                        next_bit_idx = bit_idx + 1;
                        next_tx_reg = shift[bit_idx + 1];
                    end
                end else next_tick_cnt = tick_cnt + 1;
            end
            S_STOP: if (tick_16x_i) begin
                if (tick_cnt == 15) begin
                    next_state = S_IDLE; done_o = 1; busy_o = 0;
                end else next_tick_cnt = tick_cnt + 1;
            end
        endcase
    end
endmodule
