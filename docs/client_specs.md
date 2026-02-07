# Especificación del Cliente (Client Specs)

Este documento detalla la operación del cliente software `RISC-V FPGA Suite`, diseñado para interactuar con el sistema de cómputo remoto en FPGA. El cliente actúa como una interfaz gráfica (GUI) sobre una **API de Backend** que gestiona la comunicación serial, el ensamblaje y la decodificación de estados.

## Navegación y Flujo de Trabajo

La interfaz sigue un flujo lineal estricto para garantizar la estabilidad del hardware, reflejando el estado de la máquina de estados del sistema remoto.

### 1. Conexión (Capa Física)
* **Ubicación:** Cabecera Superior (Header).
* **Acción:** Seleccionar el **Puerto COM UART** correspondiente a la FPGA.
* **Paralelismo HW:** Establece el canal físico para que el `SerialManager` (API) pueda iniciar el handshake con el **UART Transceiver** de la FPGA.
* **Restricción:** No se habilitarán las opciones de carga hasta que se seleccione un puerto válido.

### 2. Carga de Instrucciones (Loader - IMEM)
* **Ruta:** `/instructions`
* **Interfaz:** Visor de código Assembly y gestor de archivos.
* **Acciones:**
    1.  **Cargar/Editar:** Escribir código ensamblador o cargar archivos `.s`.
    2.  **Ensamblar:** El backend convierte el código a lenguaje máquina y valida la sintaxis.
    3.  **Enviar a FPGA:** Inyecta el código máquina.
* **Paralelismo HW:** Envía el comando `CMD_LOAD_CODE` y transmite el payload al **Loader Unit**, escribiendo directamente en la **IMEM** del procesador.

### 3. Carga de Datos (Loader - DMEM)
* **Ruta:** `/data`
* **Interfaz:** Editor de memoria tipo hoja de cálculo (Grid) con soporte para vistas HEX, BIN y DEC.
* **Acciones:**
    1.  **Editar:** Modificar bytes individuales en direcciones específicas.
    2.  **Enviar a FPGA:** Transfiere el estado actual de la grilla.
* **Paralelismo HW:** Envía el comando `CMD_LOAD_DATA` al **Loader Unit**, escribiendo en la **DMEM**.

### 4. Ejecución
El cliente ofrece dos modos mutuamente excluyentes que corresponden a los modos de operación del **Debug Unit** del hardware.

#### A. Ejecución Continua
* **Ruta:** `/continuous`
* **Comportamiento:**
    * El cliente envía la señal de arranque y espera a que el programa termine (Halt).
    * Al finalizar, descarga un volcado masivo de la memoria y el estado final.
* **Paralelismo HW:** Activa el `CMD_CONT_EXEC`. El hardware corre a velocidad de reloj (50MHz) y utiliza el **Dumping Unit** en modo **Range** para serializar todo el rango de memoria modificado.
* **Visualización:** Muestra "snapshots" estáticos del Banco de Registros final, el estado final del Pipeline y el dump de Memoria.

#### B. Ejecución Paso a Paso (Debug)
* **Ruta:** `/pre_step` $\rightarrow$ `/step_debug`
* **Comportamiento:**
    * **Control:** Botón "Paso Siguiente" avanza un ciclo de reloj.
    * **Visualización Dinámica:**
        * **SVG Interactivo:** Un diagrama vectorial del procesador se ilumina y actualiza para mostrar el flujo de datos exacto en el ciclo actual.
        * **Registros y Memoria:** Se resaltan en color (verde/azul) los cambios ocurridos en el último ciclo (Diffs).
* **Paralelismo HW:** Activa `CMD_DEBUG_EXEC` y envía `CMD_ADVANCE_EXEC` por cada click. El hardware ejecuta un solo ciclo, pausa, y el **Dumping Unit** opera en modo **Snoop/Diff**, enviando solo los cambios delta para actualizar la UI en tiempo real.

### 5. Consola de Monitoreo (CLI Read-Only)
Ubicada permanentemente en el pie de página, esta herramienta permite visualizar el tráfico UART en tiempo real. Anteriormente una CLI interactiva, ahora funciona como un registro de solo lectura para depuración del protocolo.

* **Pestaña RAW:** Visualiza el flujo crudo de bytes y palabras (en hexadecimal) que entran y salen por el puerto serie. Representa la actividad exacta de la capa física (TX/RX).
* **Pestaña CLEAN:** Visualiza la interpretación formateada y humana de los paquetes decodificados por el backend (e.g., "Handshake ACK", "Pipeline Status Decoded", "Memory Write Transaction").

## API del Backend

El cliente delega la lógica de bajo nivel a tres módulos principales:

1.  **Assembler:** Traduce Assembly a código máquina RISC-V y genera los payloads binarios.
2.  **Loader:** Implementa el protocolo de handshake y segmentación de datos para la transferencia segura a las memorias de la FPGA.
3.  **Executor:**
    * Gestiona la máquina de estados de la conexión serial.
    * Decodifica los paquetes de telemetría (Pipeline Status, Hazard Unit, Memory Transactions) para alimentar la CLI CLEAN.
    * Mantiene la coherencia entre el modelo de software (CPU Model) y el estado real del hardware.