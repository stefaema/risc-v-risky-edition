# Especificación del Ensamblador Risky (`risky_assembler.py`)

## 1. Descripción General
El **Risky Assembler** es un ensamblador ligero diseñado para la implementación "*Risky*" del procesador RV32I en FPGA . Traduce código en lenguaje ensamblador al formato binario requerido por el Loader Unit de la placa.

Incluye una **Capa de Expansión de Macros** que emula instrucciones ausentes en el hardware (como `li` o `blt`) utilizando el conjunto de instrucciones implementado.

---
## 2. Guía de Uso

### 2.1. Interfaz de Línea de Comandos
```bash
python risky_assembler.py <archivo_entrada> [-o SALIDA] [--hex]
```

| Argumento | Descripción | Por defecto |
| --- | --- | --- |
| `archivo_entrada` | Ruta del archivo fuente (`.asm`, `.s`). | (Requerido) |
| `-o`, `--output` | Ruta del archivo binario generado. | `program.bin` |
| `--hex` | Genera un volcado hexadecimal de texto (`.hex`). | `False` |

### 2.2. Formatos de Salida
1. **Binario (`.bin`):** Código de máquina en 32 bits (Little-Endian). Se envía vía UART a la unidad `loader_unit`.
2. **Hexadecimal (`.hex`):** Representación ASCII hexadecimal de cada instrucción. Útil para depuración o inicialización con `$readmemh` en Verilog.

### 2.3. API
También puede ser llamado mediante la función assemble_file(already_read_file), que devuelve directamente el bytearray requerido, que luego podrá ser enviado por UART hacia la placa.

---

## 3. Referencia de Sintaxis

### 3.1. Reglas Generales
* **Comentarios:** Inician con `#`.
* **Etiquetas:** Definen destinos de salto; deben terminar con dos puntos (`:`).
* **Ejemplo:** `loop: addi x1, x1, 1`

### 3.2. Nombres de Registros
Soporta índices numéricos y nombres estándar ABI de RISC-V.

| Raw | ABI | Descripción |
| --- | --- | --- |
| `x0` | `zero` | Cero constante |
| `x1` | `ra` | Dirección de retorno |
| `x2` | `sp` | Puntero de pila |
| `x5` - `x7` | `t0` - `t2` | Temporales |
| `x10` - `x17` | `a0` - `a7` | Argumentos / Retorno |
| `x31` | `t6` | **Reservado para macros del ensamblador** |

### 3.3. Valores Inmediatos
Soporta tres formatos:
* **Decimal:** `10`, `-5`
* **Hexadecimal:** `0xFF`
* **Binario:** `0b1010`

---

## 4. Conjunto de Instrucciones

### 4.1. Instrucciones Nativas (Hardware)
Estas instrucciones se mapean 1:1 con la implementación del procesador.

| Categoría | Nemónicos | Formato |
| --- | --- | --- |
| **Aritmética (R)** | `add`, `sub`, `xor`, `or`, `and`, `slt`, `sltu`, `sll`, `srl`, `sra` | `OP rd, rs1, rs2` |
| **Aritmética (I)** | `addi`, `xori`, `ori`, `andi`, `slti`, `sltiu` | `OP rd, rs1, imm` |
| **Desplazamientos (I)** | `slli`, `srli`, `srai` | `OP rd, rs1, shamt` |
| **Cargas (Loads)** | `lb`, `lh`, `lw`, `lbu`, `lhu` | `OP rd, offset(rs1)` |
| **Almacenamiento** | `sb`, `sh`, `sw` | `OP rs2, offset(rs1)` |
| **Saltos Condicionales**| `beq`, `bne` | `OP rs1, rs2, label` |
| **Saltos Incondicionales**| `jal`, `jalr` | `jal rd, label` / `jalr rd, rs1, off` |
| **Sistema / Superior** | `ecall`, `lui` | `ecall` / `lui rd, imm` |

### 4.2. Pseudo-instrucciones (Macros)
El ensamblador expande estas macros en secuencias nativas.
> **Nota:** Las macros de salto (`blt`, `bge`, etc.) modifican el registro `t6` (`x31`). No preserve datos críticos en `t6` al usarlas.

| Macro | Argumentos | Lógica de Expansión |
| --- | --- | --- |
| **`nop`** | - | `addi x0, x0, 0` |
| **`mv`** | `rd, rs` | `addi rd, rs, 0` |
| **`not`** | `rd, rs` | `xori rd, rs, -1` |
| **`neg`** | `rd, rs` | `sub rd, x0, rs` |
| **`li`** | `rd, imm` | `addi` (12 bits) o `lui` + `addi` (32 bits) |
| **`j`** | `label` | `jal x0, label` |
| **`ret`** | - | `jalr x0, ra, 0` |
| **`blt`** | `rs1, rs2, label` | `slt t6, rs1, rs2` + `bne t6, zero, label` |
| **`bgt`** | `rs1, rs2, label` | `slt t6, rs2, rs1` + `bne t6, zero, label` |

---

## 5. Restricciones de Memoria
1. **Dirección Inicial:** El código comienza siempre en `0x00000000`.
2. **Endianness:** La salida es **Little-Endian**.
   * Ejemplo: `0x00500093` se almacena como los bytes `93 00 50 00`.

## 6. Manejo de Errores
El ensamblador fallará e informará en caso de:
* Instrucciones desconocidas o errores de escritura.
* Etiquetas no definidas o fuera de rango.
* Desbordamiento de inmediatos (valores que exceden los bits permitidos).
* Errores de sintaxis (comas faltantes o argumentos inválidos).
