// src/top.v
module top (
    input wire BTN_CTRL,         // Botón central
    output wire [15:0] LED   // Los 16 LEDs de la Basys 3
);
    // Los 8 LEDs de la izquierda (8 a 15) se prenden si presionas BTN_CTRL
    assign LED[15:0] = {16{BTN_CTRL}};

endmodule
