## Consigna del Proyecto Final: Procesador Pipeline (RISC-V)

Este proyecto consiste en el diseño e implementación de un procesador con arquitectura **RISC-V** segmentado (pipeline), integrando una unidad de depuración y herramientas de visualización de datos.

---

### **1. Arquitectura del Procesador**

El procesador se basa en un pipeline de **5 etapas** estándar para optimizar la ejecución de instrucciones:

1. **IF (Instruction Fetch):** Obtención de la instrucción desde la memoria de programa.
2. **ID (Instruction Decode):** Decodificación y lectura del banco de registros.
3. **EX (Execute):** Ejecución de la operación en la ALU o cálculo de direcciones.
4. **MEM (Memory Access):** Lectura o escritura en la memoria de datos.
5. **WB (Write Back):** Escritura del resultado final en el banco de registros.

#### **Gestión de Riesgos (Hazards)**

Para el correcto funcionamiento, el diseño debe resolver tres tipos de conflictos:

* **Estructurales:** Uso simultáneo de un recurso por dos instrucciones.
* **De Datos:** Dependencias entre instrucciones donde el dato aún no se ha escrito.
* **De Control:** Decisiones de salto basadas en condiciones no evaluadas.

---

### **2. Set de Instrucciones a Implementar**

Se requiere el soporte de diversos formatos de instrucción RISC-V:

* **Tipo-R:** Operaciones aritmético-lógicas entre registros (`add`, `sub`, `and`, etc.).
* **Tipo-I:** Operaciones con inmediatos y cargas de memoria (`lw`, `addi`, `jalr`, etc.).
* **Tipo-S:** Operaciones de almacenamiento en memoria (`sw`, `sb`, `sh`).
* **Tipo-J:** Saltos incondicionales (`jal`).
* **Tipo-B:** Saltos condicionales (`beq`, `bne`).
* **Tipo-U:** Carga de inmediatos en la parte superior (`lui`).

---

### **3. Unidad de Depuración (Debug Unit) e Interfaz**

La comunicación entre la FPGA y la PC se realiza mediante el protocolo **UART**.

* **Funcionalidad:** Debe permitir la carga y recarga dinámica del programa en la memoria sin necesidad de re-sintetizar el hardware.
* **Visualización:** Se debe desarrollar una interfaz (CLI, TUI o GUI) que muestre:
* Los 32 registros del procesador.
* El contenido de los latches intermedios del pipeline.
* La memoria de datos utilizada.


* **Modos de Ejecución:**
* **Continuo:** Ejecución total hasta encontrar una instrucción de parada (HALT).
* **Paso a paso:** Ejecución de un ciclo de reloj por cada comando recibido.



---

### **4. Requisitos de Carga y Control**

El sistema debe contemplar la traducción de lenguaje ensamblador a código máquina para su envío. Es fundamental definir la lógica de reinicio al cargar un nuevo programa, respondiendo a:

* ¿Es necesario vaciar registros, pipeline o memorias antes de una nueva ejecución?
* ¿Cómo se comporta el sistema si falta la instrucción de parada?

---

### **5. Análisis de Reloj y Optimización**

Una fase crítica es la integración física en la FPGA, donde se debe:

1. Identificar el **camino crítico** (Critical Path) del diseño.
2. Analizar el **Skew** del reloj y sus consecuencias en la estabilidad.
3. Determinar la **frecuencia máxima de operación** óptima.
4. Utilizar herramientas de reporte de Vivado para obtener métricas de performance y aplicar la frecuencia calculada mediante el *Clock Wizard*.

---
