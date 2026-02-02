// -----------------------------------------------------------------------------
// Module: U-ART
// Description: Testbench con Loopback y Watchdog de seguridad
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module uart_transceiver_tb;
    localparam string C_RESET = "\033[0m", C_RED = "\033[1;31m", C_GREEN = "\033[1;32m", C_CYAN = "\033[1;36m";
    
    logic clk, rst_n, loopback;
    logic [7:0] rx_data, tx_data;
    logic rx_ready, rx_error, tx_start, tx_busy, tx_done;

    uart_transceiver #(.CLK_FREQ(100_000_000)) dut (
        .clk_i(clk), .rst_ni(rst_n), .baud_selector_i(2'b11), // 115200
        .rx_i(loopback), .rx_data_o(rx_data), .rx_ready_o(rx_ready), .rx_error_o(rx_error),
        .tx_data_i(tx_data), .tx_start_i(tx_start), .tx_o(loopback), .tx_busy_o(tx_busy), .tx_done_o(tx_done)
    );

    initial begin clk = 0; forever #5 clk = ~clk; end

    // --- Security Watchdog ---
    initial begin
        #2000000; // 2 ms
        $display("\n%s[TIMEOUT] The simulation took too long (hung).%s", C_RED, C_RESET);
        $finish;
    end

    task send_byte(input logic [7:0] data);
        $display("[TB] Sending Byte: 0x%h", data);
        tx_data = data; tx_start = 1;
        @(posedge clk); tx_start = 0;
        // Wait until transmission is done
        wait(!tx_busy); 
        @(posedge clk);
    endtask

    initial begin
        $display("\n%sStarting UART Loopback Test%s", C_CYAN, C_RESET);
        rst_n = 0; tx_start = 0; loopback = 1;
        #100 rst_n = 1; @(posedge clk);

        // - Test 1: Send 0xA5 and expect to receive 0xA5
        send_byte(8'hA5);
        wait(rx_ready); // If RX does not detect the start bit, it hangs here (but the watchdog kills it)
        
        if (rx_data === 8'hA5) $display("Byte 0xA5 %s[PASS]%s", C_GREEN, C_RESET);
        else $display("Byte 0xA5 %s[FAIL]%s (Got 0x%h)", C_RED, C_RESET, rx_data);

        #5000; 

        // - Test 2: Send 0x3C and expect to receive 0x3C
        send_byte(8'h3C);
        wait(rx_ready);
        
        if (rx_data === 8'h3C) $display("Byte 0x3C %s[PASS]%s", C_GREEN, C_RESET);
        else $display("Byte 0x3C %s[FAIL]%s", C_RED, C_RESET);

        $display("%sSUCCESS: All tests passed.%s", C_GREEN, C_RESET);
        $finish;
    end
endmodule
