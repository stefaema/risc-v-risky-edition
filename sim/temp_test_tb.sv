`timescale 1ns / 1ps

module temp_test_tb();

    localparam string MODULE_NAME = "temp_test";

    // Color definitions matching your Tcl logic
    localparam string INFO    = "\033[0;36m"; // Cyan
    localparam string SUCCESS = "\033[0;32m"; // Green
    localparam string ERROR   = "\033[0;31m"; // Red
    localparam string RESET   = "\033[0m";

    // Signal declarations
    logic        btn_in;
    logic [15:0] leds_out;

    // Instantiate the Unit Under Test (UUT)
    temp_test uut (
        .BTN_CTRL(btn_in),
        .LED(leds_out)
    );

    // Stimulus process
    initial begin
        // Initialize
        btn_in = 0;
        #10;
        
        // Test Case 1: Button Pressed
        $display("%s[INFO] @ %s: Action: Pressing button...%s", INFO, MODULE_NAME, RESET);
        btn_in = 1;
        #20;
        
        if (leds_out == 16'hFFFF) 
            $display("%s[SUCCESS] @ %s: SUCCESS: All LEDs are ON (State: %b)%s", SUCCESS, MODULE_NAME, leds_out, RESET);
        else 
            $display("%s[ERROR] @ %s: FAILURE: LEDs state: %h%s", ERROR, MODULE_NAME, leds_out, RESET);

        // Test Case 2: Button Released
        $display("%s[INFO] @ %s: Action: Releasing button...%s", INFO, MODULE_NAME, RESET);
        btn_in = 0;
        #20;
        
        if (leds_out == 16'h0000)
            $display("%s[SUCCESS] @ %s: SUCCESS: All LEDs are OFF%s", SUCCESS, MODULE_NAME, RESET);
        else
            $display("%s[ERROR] @ %s: FAILURE: LEDs did not turn off!%s", ERROR, MODULE_NAME, RESET);
        
        $finish;
    end

endmodule
