
# Apéndice A: Decisiones de Diseño y Compromisos de Hardware

Este apartado documenta la racionalización detrás de las decisiones arquitectónicas críticas tomadas durante la fase de síntesis e implementación, específicamente en relación con el compromiso entre **Frecuencia Máxima ()** y **Ciclos por Instrucción (CPI)**.

---

## 1. Identificación del Cuello de Botella

El requerimiento de integrar una **Unidad de Depuración (Debug Unit)** no intrusiva introdujo una restricción física significativa en el diseño.

* **El Problema:** La necesidad de visualizar en tiempo real los 32 registros, los estados intermedios de los 4 registros de pipeline y la memoria de datos requiere redes de multiplexado masivas (High Fan-In/Fan-Out).
* **Impacto:** El análisis de timing preliminar indicó que la lógica de la Debug Unit y el subsistema UART saturarían el camino crítico, limitando la frecuencia operativa máxima de la FPGA (Artix-7/Basys 3) a un rango estimado de **50-60 MHz**, independientemente de la velocidad teórica del núcleo aislado.

## 2. Estrategia de Optimización: CPI sobre Frecuencia

Dado que el techo de frecuencia estaba impuesto por módulos periféricos, se decidió no optimizar el núcleo para alta velocidad (e.g., 100 MHz), sino "gastar" el margen de tiempo (Slack) disponible para maximizar la eficiencia del pipeline (CPI).

### Implementación de Memoria Asíncrona

A diferencia de los diseños estándar que utilizan Block RAM síncrona (lectura en flanco de reloj), este diseño implementa la Memoria de Datos con lectura asíncrona (Distributed RAM).

* **Ventaja Lógica:** El dato leído de memoria está disponible en el mismo ciclo de la etapa MEM, antes del siguiente flanco de reloj.
* **Eliminación de Stalls:** Esto permite que la **Forwarding Unit** inyecte el dato cargado directamente a la etapa ID del ciclo siguiente, eliminando la necesidad de insertar ciclos de espera (Stalls) para riesgos de tipo **Load-Use**.

### Etapa ID Compleja
Se implemnetó una etapa ID más compleja de lo normal siguiendo los lineamientos enunciados en el libro de Patterson & Hennesy (4.8 - Reducing the Delay of Branches), salvando aquellas secciones que han podido ser ignoradas debido al Timing Analysis correspondiente, que ha resultado acorde para la microarquitectura elegida.

### Conclusión

El diseño aprovecha el periodo de reloj de **20ns** (50 MHz) para acomodar un camino lógico combinacional más largo (Memoria + Comparador). Esto resulta en un procesador que, aunque opera a menor frecuencia debido a las limitaciones de depuración, ejecuta más instrucciones por ciclo que una variante estándar, simplificando la lógica de control de riesgos y maximizando el rendimiento efectivo del sistema bajo las restricciones dadas.
