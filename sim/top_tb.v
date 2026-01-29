`timescale 1ns / 1ps

module top_tb();
    // Señales internas del testbench (pueden llamarse como quieras)
    reg btn_test;
    wire [15:0] led_test;

    // Instancia del módulo (AQUÍ ES DONDE DEBEN COINCIDIR)
    top uut (
        .BTN_CTRL(btn_test), // El nombre después del punto (.) debe ser igual al de top.v
        .LED(led_test)       // El nombre después del punto (.) debe ser igual al de top.v
    );

    initial begin
        // Ver texto en la consola de VS Code
        $display("\033[0;36m=======================================\033[0m");
        $display("\033[1;33m[USER]: Initializing simulation\033[0m");
        $monitor("Tiempo: %t | Boton: %b | LEDs: %b", $time, btn_test, led_test);

        // Estímulos
        btn_test = 0;
        #100;
        
        btn_test = 1; // Presionamos el botón
        #100;
        
        btn_test = 0; // Soltamos el botón
        #100;

        $display("\033[1;33m[USER]: Simulation finished\033[0m");
        $display("\033[0;36m=======================================\033[0m");
        $finish;
    end
endmodule
