# Especificación de Implementación de la Microarquitectura Core RISC-V: "Risky-V"

---
## Resumen de la Microarquitectura

Este documento detalla la implementación de un procesador mononúcleo de 32 bits basado en la arquitectura RISC-V (RV32I). El diseño sigue una estructura de **pipeline de 5 etapas** clásica, pero incluye optimizaciones específicas en la etapa de Decodificación (ID) para la resolución temprana de saltos.

### Interconexión y Etapas
La interconexión del sistema, visible en el módulo `riscv_core.sv`, orquesta el flujo de datos de la siguiente manera:

1.  **Instruction Fetch (IF):** El **Program Counter (PC)** direcciona la memoria de instrucciones. Aquí se determina la siguiente dirección a buscar: secuencial (PC+4) o un salto (Target Address).
2.  **Instruction Decode (ID):** Esta es la etapa más densa lógicamente en esta implementación.
    *   La instrucción se decodifica y se leen los operandos del **Register File**.
    *   **Immediate Generator** extiende el signo de los inmediatos.
    *   **Resolución de Saltos:** A diferencia de arquitecturas básicas que resuelven en EX, aquí el **Comparador** y el **Flow Controller** evalúan la condición de salto (`BEQ`, `BNE`, etc.) y calculan la dirección destino dentro de ID. Esto reduce la penalización por salto tomado.
    *   **Forwarding Muxes:** Los multiplexores de adelantamiento se encuentran a la entrada del comparador y de los registros de pipeline hacia EX, permitiendo resolver dependencias de datos tanto para cálculos aritméticos como para la evaluación de condiciones de salto.
    *   El **Mux de PC** (lógicamente controlado desde ID) selecciona si el PC se actualiza secuencialmente o toma la dirección calculada por la lógica de salto.
3.  **Execute (EX):** La **ALU** realiza operaciones aritméticas, lógicas y de desplazamiento. Selecciona entre operandos del registro o inmediatos. También calcula direcciones efectivas para cargas y almacenamientos. Existe además un multiplexor para reemplazar al resultado de la ALU por PC+4, en caso de que sea una instrucción de tiPo `JAL` o `JALR`
4.  **Memory (MEM):** Se accede a la Memoria de Datos. La **Data Memory Interface** gestiona la alineación de bytes/medias palabras y la extensión de signo en las lecturas.
5.  **Writeback (WB):** Se selecciona el resultado final (procedente de la ALU o de la Memoria) para escribirlo en el **Register File** en el flanco de subida del reloj.

### Registros

Existen 32 registros de los cuales uno está siemple clear (`x0`). El resto puede ser modificado sin problemas¹.

> ¹ Ver la especificación del ensamblador implementado en caso de que se halle inconsistencias con respecto al registro `x31`.

---

## Resolución de Hazards

El procesador implementa hardware dedicado para manejar conflictos de datos y control sin detener el pipeline innecesariamente, excepto cuando es inevitable.

### 1. Data Hazards (Forwarding)
Se resuelven mediante la **Forwarding Unit**. Esta unidad detecta dependencias Read-After-Write (RAW) donde una instrucción en ID necesita un dato que está siendo calculado en EX o esperando ser escrito en MEM o WB.

*   **Comportamiento:** Si se detecta una dependencia, los multiplexores en la etapa ID (antes de entrar al registro ID/EX) ignoran el valor leído del Register File y toman el valor adelantado de etapas posteriores (pero de instrucciones anteriores). En la etapa MEM se tuvo que agregar necesariamente un multiplexor para elegir entre el resultado de la ALU y de la lectura de memoria. El resto accede a su dato más reciente tomando el valor que entrará en el registro de Pipeline.

*   **Prioridad:**
    1.  Adelantamiento desde **EX** (Instrucción inmediatamente anterior).
    2.  Adelantamiento desde **MEM** (Segunda instrucción anterior).
    3.  Adelantamiento desde **WB** (Tercera instrucción anterior).

### 2. Load-Use Hazards
Ocurren cuando una instrucción necesita un dato inmediatamente después de una instrucción de carga (`LOAD`). Como el dato no está disponible hasta el final de la etapa MEM, el forwarding no es suficiente.

*   **Fórmula de Detección:**
    ```verilog
    Hazard = (MemRead@EX == 1) AND (RD@EX != 0) AND ((RD@EX == RS1@ID) OR (RD@EX == RS2@ID))
    ```
*   **Acción:** La **Hazard Protection Unit** activa una señal de "freeze".
    *   El **PC** mantiene su valor actual (Stall).
    *   El registro de pipeline **IF/ID** mantiene su valor actual (Stall).
    *   Se fuerza una "burbuja" (NOP) en la etapa ID inyectando ceros en las señales de control hacia el registro **ID/EX**.

### 3. Control Hazards (Branch/Jump)
Debido a la decisión de diseño de resolver saltos en la etapa ID, la penalización por un salto tomado se reduce.

*   **Lógica:** El **Flow Controller** evalúa:
    ```verilog
    BranchTaken = (Es_Branch AND (Zero_Flag XOR Funct3[0])) OR Es_JAL OR Es_JALR
    ```
    > *Nota: `Funct3[0]` diferencia entre BEQ/BNE*.
*   **Acción:** Si `BranchTaken` es verdadero:
    *   Se actualiza el PC inmediatamente a la dirección destino calculada cambiando el selector del Multiplexor que elige entre PC+4 y la salida del Final Target Adder.
    *   Se realiza un **Flush** síncrono del registro de pipeline **IF/ID**  ya que la instrucción no sería válida y correspondería a un flujo incorrecto.

### 4. Halt Hazard (Custom Instruction)
La instrucción `ecall`, por diseño, se utiliza para detener el procesador de forma suave. Es decir: se espera que todas las instrucciones pendientes terminen y recién cuando la flag llega a Writeback se considera que el procesador terminó y por esa razón se conecta la flag en esa etapa a la salida del modulo núcleo.

*   **Acción:** La **Halt Unit** recibe la señal decodificada de parada.
    *   Emite una señal de `freeze` hacia el PC y el registro IF/ID. Como no se fuerza un NOP, la flag de parada se mantiene y por lo tanto es perpetua hasta que una señal externa (global_freeze) resetee el pipeline.
    *   El pipeline se vacía naturalmente a medida que las instrucciones posteriores terminan, pero no entran nuevas instrucciones.
    * Como decisión de diseño, se propaga todas las etapas terminan teniendo la flag encendida al final de la ejecución. Es decir, es como si se replicara la insturcción 5 veces.

---

## Descripción de Módulos

### ALU (`alu.sv`)
*   **Descripción:** Unidad Aritmético Lógica de 32 bits. Ejecuta operaciones matemáticas (suma, resta), lógicas (AND, OR, XOR), desplazamientos (SLL, SRL, SRA) y comparaciones (SLT, SLTU).
*   **Entradas:** Operando A, Operando B, Código de operación (4 bits).
*   **Salidas:** Resultado de 32 bits.

### ALU Controller (``alu_controller.sv``)
*   **Descripción:** Decodifica la intención general de la Control Unit y los campos específicos de la instrucción (`funct3`, `funct7`) para generar el código de operación exacto para la ALU.
*   **Entradas:** Intención de ALU (Add/Sub/R-type/I-type), campos `funct3` y bit 30 de `funct7`.
*   **Salidas:** Código de operación de ALU (4 bits).

### Control Unit (``control_unit.sv``)
*   **Descripción:** Decodificador principal. Traduce el `Opcode` de 7 bits en señales de control para todo el datapath. Maneja la categorización de instrucciones (R-Type, I-Type, Loads, Stores, Branches, Jumps).
*   **Entradas:** Opcode [6:0], Señal de forzado de NOP.
*   **Salidas:** Señales de escritura de registros/memoria, selectores de fuentes de ALU, tipos de salto, señal de Halt.

### Register File (``register_file.sv``)
*   **Descripción:** Banco de registros estándar RV32I con 32 registros de 32 bits. El registro `x0` está cableado a tierra. Posee dos puertos de lectura asíncronos y un puerto de escritura síncrono.
*   **Entradas:** Direcciones de lectura (RS1, RS2), Dirección de escritura (RD), Dato a escribir, Habilitación de escritura, Reloj, Reset.
*   **Salidas:** Datos leídos de RS1 y RS2.

### Immediate Generator (``immediate_generator.sv``)
*   **Descripción:** Extrae y reconstruye el valor inmediato embebido en la instrucción. Realiza la extensión de signo adecuada dependiendo del tipo de instrucción (I, S, B, U, J) para producir un valor de 32 bits.
*   **Entradas:** Palabra de instrucción completa (32 bits).
*   **Salidas:** Inmediato extendido (32 bits).

### Data Memory Interface (``data_memory_interface.sv``)
*   **Descripción:** Interfaz entre el Core y la RAM de datos. Maneja la lógica de acceso a nivel de byte (`LB`, `SB`), media palabra (`LH`, `SH`) y palabra (`LW`, `SW`). Realiza el enmascaramiento para escrituras y la extensión de signo/cero para lecturas.
*   **Entradas:** `funct3` (ancho de acceso), dirección (LSBs para alineación), dato a escribir, dato leído crudo de RAM.
*   **Salidas:** Máscara de escritura de 4 bits, dato alineado para escritura, dato final extendido para el Core.

### Forwarding Unit (``forwarding_unit.sv``)
*   **Descripción:** Detecta dependencias de datos y controla los multiplexores de bypass para alimentar operandos actualizados a la etapa ID.
*   **Entradas:** Direcciones RS1/RS2 actuales (ID), Direcciones RD y señales de escritura de etapas EX, MEM, WB.
*   **Salidas:** Señales de selección para los Muxes de forwarding de RS1 y RS2.

### Hazard Protection Unit (``hazard_protection_unit.sv``)
*   **Descripción:** Unidad de seguridad que detecta peligros Load-Use.
*   **Entradas:** Direcciones RS1/RS2 (ID), Dirección RD (EX), señal de lectura de memoria (EX).
*   **Salidas:** Señal de Freeze (para PC e IF/ID), Señal de Force NOP (para Control Unit).

### Flow Controller (``flow_controller.sv``)
*   **Descripción:** Evalúa si un salto condicional o incondicional debe tomarse. Compara las banderas (Zero) con el tipo de salto (`funct3`).
*   **Entradas:** Señales de tipo de salto (Branch, JAL, JALR), bandera Zero, `funct3`.
*   **Salidas:** Señal `flow_change` (indica si se debe redirigir el PC).

### Memory Range Tracker (``memory_range_tracker.sv``)
*   **Descripción:** Módulo auxiliar de **Depuración**. Monitorea las direcciones de memoria escritas para reportar el rango mínimo y máximo modificado. *Nota: No afecta el funcionamiento lógico del procesador.*
*   **Entradas:** Dirección de escritura, Habilitación de escritura.
*   **Salidas:** Dirección mínima modificada, Dirección máxima modificada.

### Pipeline Register (``pipeline_register.sv``)
*   **Descripción:** Registro genérico parametrizable utilizado para separar las etapas del pipeline. Soporta stall (mantener valor) y flush síncrono (limpiar a cero).
*   **Entradas:** Datos, Write Enable (control de flujo), Soft Reset (Flush).
*   **Salidas:** Datos registrados.

---

## Contenido de los Registros de Pipeline

Dado que el diseño abstrae las entradas y salidas de los registros en buses anchos, a continuación se detalla qué información viaja en cada etapa:

### IF / ID Register (96 bits)
Almacena la información cruda de la instrucción traída de memoria.
1.  **PC:** Dirección actual de la instrucción.
2.  **Instruction:** La palabra de 32 bits de la instrucción.
3.  **PC+4:** Dirección de la siguiente instrucción secuencial.

### ID / EX Register (164 bits)
Contiene la instrucción decodificada y los operandos listos para operar.
1.  **Señales de Control:** Flags para etapas posteriores (RegWrite, MemWrite, MemRead, ALU Control, Branch/Jump types, Halt).
2.  **Datos:** PC actual, Valor de RS1, Valor de RS2, Inmediato extendido.
3.  **Metadatos:** Índices de registros (RS1, RS2, RD) y campos de función (`funct3`, `funct7`) para control fino en EX.

### EX / MEM Register (109 bits)
Lleva el resultado de la ejecución hacia la memoria.
1.  **Señales de Control:** Flags para MEM y WB (RegWrite, MemWrite, MemRead, etc.).
2.  **Datos de Ejecución:** Resultado de la ALU (o dirección de memoria calculada), Dato a almacenar (RS2 para Stores), PC actual.
3.  **Metadatos:** Índice del registro destino (RD), `funct3` (para el tamaño de acceso a memoria).

### MEM / WB Register (104 bits)
Transporta el resultado final listo para ser escrito.
1.  **Señales de Control:** Flags para WB (RegWrite, Fuente de dato).
2.  **Resultados:** Resultado pasante de la ALU, Dato leído de la Memoria (Read Data), PC actual.
3.  **Metadatos:** Índice del registro destino (RD) donde se escribirá el resultado.

---
## Entradas y Salidas del Módulo
Además de tener como salida a todos los registros de pipeline del módulo (Taps de depuración), se introducen las siguientes entradas y salidas fundamentales para la operación del núcleo:

### Señales de Entrada para el Control de Flujo
Se emplea una señal para parar a todo el procesador (``global_freeze_i``) y otra para resetearlo de forma síncrona (``soft_reset_i``).

### Interfaces de Memoria
**Memoria de Instrucciones:**
- Se tiene la dirección de la memoria de instrucción como salida (``imem_addr_o`` / Program Counter).
- Se tiene el resultado de lectura de la memoria de instrucción como entrada (``imem_inst_i`` / Palabra de instrucción).

**Memoria de Datos:**
- Dirección de acceso a datos alineada a palabra (``dmem_addr_o``).
- Dato de escritura hacia la memoria (``dmem_wdata_o``).
- Dato de lectura desde la memoria (``dmem_rdata_i``).
- Habilitación de escritura (``dmem_write_en_o``).
- Máscara de bytes para escrituras parciales (``dmem_byte_mask_o``).

### Contenido de Salida de la Half-Word de Peligros
Además, se decidió incorporar también una salida directa (``tap_hazard_o``) de 16 bits que agrupa señales indicando el estado general del sistema para el módulo de depuración:

- **Bit 11:** Estado de actualización del PC (1 = Actualizando, 0 = Stall/Freeze por Hazard o Halt).
- **Bit 10:** Estado del registro IF/ID (1 = Actualizando, 0 = Stall/Freeze por Hazard o Halt).
- **Bit 9:** Indicador de **Peligro de Control** (Branch/Jump) tomado en la etapa ID.
- **Bit 8:** Indicador de **Peligro de Datos Load-Use** detectado en ID (Stall requerido).
- **Bits 7-6:** Valor del selector de Forwarding para el operando **RS2** (00=RegFile, 01=EX, 10=MEM, 11=WB).
- **Bits 5-4:** Valor del selector de Forwarding para el operando **RS1** (00=RegFile, 01=EX, 10=MEM, 11=WB).
- **Bit 0:** Indicador de fin de programa (Instrucción ``is_halt`` alcanzó la etapa WB).

### Interfaz de Depuración y Command & Control
Por último, se incluye además un puerto más solo de lectura para el archivo de registros, junto con una entrada para que el módulo de depuración pueda elegir cuál leer.

Además, se cuenta con una señal de salida que indica si el núcleo se ha parado completamente, por lo que implicaría que la bandera `is_halt` ha llegado a la etapa WB.
