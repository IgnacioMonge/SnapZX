<p align="center">
  <img src="images/logo.png" alt="SnapZX" width="640" />
</p>

> Spanish translation here. English version: [README.md](README.md)

# SnapZX

**SnapZX** es un sistema de transferencia por Wi‑Fi para **subir snapshots `.SNA`** desde un PC a un **ZX Spectrum (principalmente 128K)** y **ejecutarlos automáticamente** mediante `snapload`, utilizando un **ESP‑12** conectado al bus del **AY‑3‑8912** (UART por bit‑bang) y un servidor orientado a **ESXDOS**.

Está diseñado para un flujo de trabajo “seleccionar → enviar → ejecutar”, reduciendo al mínimo la fricción durante pruebas, desarrollo y uso cotidiano (sin cables de audio, sin cintas y sin pasos manuales intermedios).

## Qué hace

1. En el Spectrum se ejecuta el servidor (`snapzx`) como dot-command de ESXDOS (o como binario en RAM con el loader BASIC).
2. El servidor inicializa UART/Wi‑Fi, muestra la **IP** del ESP‑12 y queda en estado **“Waiting for transfer…”** escuchando en el **puerto TCP 6144**.
3. En el PC se ejecuta el cliente (GUI) y se selecciona un snapshot `.SNA` (48K o 128K). El cliente:
   - valida extensión y tamaño (48K/128K),
   - normaliza el nombre a formato **8.3** seguro,
   - encapsula el envío en un protocolo binario simple.
4. El Spectrum recibe el snapshot en chunks, valida cabeceras, escribe exactamente el número de bytes anunciado al fichero en el **directorio actual** y, al completar con éxito, envía un **ACK de aplicación**.
5. Tras completar, el servidor ejecuta `snapload <FICHERO>` para lanzar el snapshot.

## De dónde viene

SnapZX está **basado en el dot-command LAIN** (C) 2022 Alex Nihirash y mantiene el mismo enfoque de “servidor ligero en Spectrum + cliente en PC”. Sobre esa base, SnapZX incorpora un conjunto de mejoras centradas en dos prioridades:

- **Robustez de transporte** (resincronización estricta de `+IPD`, chunking y timeouts bien definidos).
- **Experiencia de uso** (feedback visual, validación temprana, y comportamiento predecible ante cancelaciones o reinicios).

El propio servidor incluye los créditos en pantalla al arrancar.

## Características principales (y por qué son ventajas)

### Flujo “enviar y ejecutar” sin pasos manuales
- El servidor guarda el `.SNA` recibido y lo ejecuta automáticamente con `snapload`, acelerando pruebas y reduciendo errores operativos.

### Validación estricta y comportamiento determinista
- El cliente valida **extensión `.sna`** y tamaños conocidos (**48K: 49179 bytes**, **128K: 131103 bytes**).
- El servidor valida la cabecera y usa la longitud anunciada para escribir **exactamente** lo esperado (sin “sobrescribir” ni quedarse corto).

### Recuperación limpia ante fallos y cancelaciones
- Si la conexión se cierra antes de completar la transferencia, el servidor **cierra y borra el fichero incompleto**, evitando residuos y estados ambiguos.
- La detección de eventos `CLOSED` y los timeouts de recepción fuerzan una salida segura cuando la conexión no progresa.

### Inicialización “inteligente” del ESP‑12
- El servidor intenta reutilizar el estado existente del ESP (salida de modo transparente, `AT`, comprobación de IP y estado del servidor) antes de aplicar un reset completo, lo que mejora tiempos de arranque cuando el módulo ya está configurado.

### Feedback visual claro en Spectrum
- Mensajes de estado en pantalla (inicio, listo, nombre de fichero, etc.).
- Barra de progreso en pantalla con segmentos UDG en **verde**.
- Señalización visual de actividad en el borde cuando está habilitada (útil para confirmar tráfico/actividad UART sin instrumentación externa).

### Cliente con GUI orientado a estabilidad
- Transferencia **en streaming** (sin cargar el snapshot completo en RAM).
- Ritmo de envío controlado (rate limiting), suavizado de progreso, estadísticas y gestión de reintentos/tiempos de espera.
- Botón de cancelación y finalización robusta incluso si el extremo remoto cierra la conexión.

## Componentes del repositorio

- `images/logo.png`  
  Logo del proyecto (usado como cabecera de este README).

- `client/`  
  - `SNAPZX.exe`: cliente para Windows listo para ejecutar.
  - `SNAPZX.ps1`: fuente del cliente PowerShell (GUI Windows Forms).

- `server/`  
  - `snapzx`: binario del dot-command (para ejecutarlo como `.snapzx`).
  - `snapzx.bin`: binario para cargar en RAM (ejecución con `RANDOMIZE USR`).
  - `SNAPZX.BAS`: loader BASIC (carga `snapzx.bin` y lo ejecuta).
  - `dot.asm`, `modules/`, `drivers/`: fuentes del servidor (Z80 + módulos).

## Requisitos

### En el Spectrum
- ESXDOS (p. ej. DivMMC/DivMMC Enjoy u otro entorno compatible con dot-commands).
- Hardware que permita usar el AY‑3‑8912 como interfaz para el ESP‑12 (según el driver `server/drivers/ay.asm`).
- ESP‑12 con firmware AT compatible (comandos `AT+RST`, `AT+CIPMUX`, `AT+CIPSERVER`, `AT+CIFSR`, etc.).
- Acceso a una red Wi‑Fi configurada en el ESP‑12.

### En el PC
- Windows con PowerShell (para `SNAPZX.ps1`) o ejecución directa de `SNAPZX.exe`.
- Conectividad IP con el Spectrum/ESP‑12 en la misma red.

## Instalación

### Opción A: dot-command (recomendado)
1. Copia `server/snapzx` a la SD, típicamente en `\BIN\` (o en el directorio desde el que lo vayas a invocar).
2. En ESXDOS, ejecuta el comando:
   - `.snapzx`

### Opción B: binario en RAM + loader BASIC
1. Copia `server/snapzx.bin` y `server/SNAPZX.BAS` a la SD.
2. Ejecuta el loader desde BASIC (el nombre exacto del programa dependerá del sistema de ficheros/ESXDOS):
   - `LOAD "SNAPZX"`, luego `RUN`

## Uso rápido

1. En el Spectrum, ejecuta SnapZX. Anota la IP que se muestra en pantalla.
2. En el PC, abre `client/SNAPZX.exe` (o `client/SNAPZX.ps1`).
3. Introduce la IP del Spectrum/ESP‑12 y selecciona un `.SNA` válido.
4. Pulsa **SEND** y espera a que:
   - el Spectrum muestre el nombre y la barra de progreso,
   - el cliente indique finalización y, cuando aplique, **ACK** recibido,
   - el Spectrum ejecute el snapshot con `snapload`.

## Protocolo de transferencia (resumen)

El servidor espera recibir, dentro del payload binario de `+IPD` del ESP, la siguiente estructura:

- `LAIN` (4 bytes ASCII)
- `snapshot_len` (`uint32_le`)
- `FN` (2 bytes ASCII)
- `name_len` (`uint8`)
- `name` (`name_len` bytes)
- `payload` (`snapshot_len` bytes)

Al completar la recepción y escritura del payload, el servidor envía un **ACK de aplicación** (`OK\r\n`) antes de lanzar `snapload`.

## Integridad y manejo de errores

- **Cierre prematuro / cancelación:** si la conexión se cierra con un fichero parcial abierto, se cierra el handle y se elimina el fichero incompleto.
- **Timeouts de recepción:** si la recepción de un chunk no progresa dentro de la ventana esperada, el servidor aborta y limpia.
- **Resincronización:** el servidor busca de forma estricta `+IPD,` y descarta ruido de stream para volver a un estado consistente.
- **Conexiones “sonda”:** el servidor ignora conexiones que abren y cierran sin enviar un `+IPD` válido, evitando falsos positivos por sondeos del cliente.

## Limitaciones actuales

- El cliente está orientado a snapshots `.SNA` y, por diseño, valida tamaños estándar de 48K/128K.
- El servidor asume el flujo “recibir `.SNA` → `snapload`”. Para otros tipos de fichero o usos (p. ej., “subir sin ejecutar”), sería necesario un modo alternativo.

## Créditos

- (C) 2025 **M. Ignacio Monge García**
- Basado en **LAIN** (C) 2022 **Alex Nihirash**
