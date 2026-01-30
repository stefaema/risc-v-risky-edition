module temp_test (
    input  logic        BTN_CTRL,  // Central button input
    output logic [15:0] LED       // 16-bit LED bus
);

    // When BTN_CTRL is pressed (1), all 16 LEDs turn on (1)
    // When released (0), all LEDs turn off (0)
    assign LED = {16{BTN_CTRL}};

endmodule
