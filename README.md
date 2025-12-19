<p align="center">
  <img src="images/logo.png" alt="SnapZX" width="640" />
</p>

>Spanish version: [READMEsp.md](READMEsp.md)

# SnapZX

**SnapZX** is a Wi‑Fi transfer system to **upload `.SNA` snapshots** from a PC to a **ZX Spectrum (primarily 128K)** and **run them automatically** via `snapload`, using an **ESP‑12** connected to the **AY‑3‑8912** bus (bit‑banged UART) and a server designed for **ESXDOS**.

It is built around a “select → send → run” workflow, minimizing friction during testing, development, and day‑to‑day use (no audio cables, no tapes, and no manual intermediate steps).

## What it does

1. On the Spectrum, you run the server (`snapzx`) as an ESXDOS dot-command (or as a RAM binary via the BASIC loader).
2. The server initializes UART/Wi‑Fi, displays the ESP‑12 **IP address**, and enters **“Waiting for transfer…”** while listening on **TCP port 6144**.
3. On the PC, you run the GUI client and choose a `.SNA` snapshot (48K or 128K). The client:
   - validates the extension and size (48K/128K),
   - normalizes the filename to a safe **8.3** format,
   - wraps the transfer in a simple binary protocol.
4. The Spectrum receives the snapshot in chunks, validates headers, writes **exactly** the announced number of bytes to a file in the **current directory**, and, on success, sends an **application‑level ACK**.
5. Once complete, the server runs `snapload <FILE>` to launch the snapshot.

## Where it comes from

SnapZX is **based on the LAIN dot-command** (C) 2022 Alex Nihirash and follows the same “lightweight server on the Spectrum + PC client” approach. On top of that baseline, SnapZX adds improvements focused on two priorities:

- **Transport robustness** (strict `+IPD` resynchronization, chunking, and well‑defined timeouts).
- **User experience** (clear visual feedback, early validation, and predictable behavior on cancellations or reboots).

The server also shows credits on screen at startup.

## Key features (and why they are advantages)

### “Send and run” workflow without manual steps
- The server saves the received `.SNA` and automatically runs it with `snapload`, accelerating iterations and reducing operator error.

### Strict validation and deterministic behavior
- The client validates **`.sna` extension** and known sizes (**48K: 49179 bytes**, **128K: 131103 bytes**).
- The server validates the header and uses the advertised length to write **exactly** what is expected (no overruns, no short writes).

### Clean recovery on failures and cancellations
- If the connection closes before the transfer completes, the server **closes and deletes the incomplete file**, preventing leftovers and ambiguous states.
- `CLOSED` detection and receive timeouts force a safe exit whenever the connection stalls.

### “Smart” ESP‑12 initialization
- The server attempts to reuse the ESP’s current state (exit transparent mode, `AT`, IP/server checks) before forcing a full reset, improving startup times when the module is already configured.

### Clear visual feedback on the Spectrum
- On‑screen status messages (startup, ready, filename, etc.).
- On‑screen progress bar with **green** UDG segments.
- Optional border activity signaling when enabled (useful to confirm UART traffic without external instrumentation).

### GUI client designed for stability
- **Streaming transfer** (no need to load the entire snapshot into RAM).
- Controlled send pacing (rate limiting), smoothed progress, statistics, and retry/timeout handling.
- A cancel button and robust shutdown even if the remote end closes the connection.

## Repository contents

- `images/logo.png`  
  Project logo (used as the header of this README).

- `client/`  
  - `SNAPZX.exe`: ready‑to‑run Windows client.
  - `SNAPZX.ps1`: PowerShell client source (Windows Forms GUI).

- `server/`  
  - `snapzx`: dot-command binary (run as `.snapzx`).
  - `snapzx.bin`: RAM-loadable binary (run via `RANDOMIZE USR`).
  - `SNAPZX.BAS`: BASIC loader (loads and runs `snapzx.bin`).
  - `dot.asm`, `modules/`, `drivers/`: server sources (Z80 + modules).

## Requirements

### On the Spectrum
- ESXDOS (e.g., DivMMC/DivMMC Enjoy or any dot-command compatible environment).
- Hardware that allows using the AY‑3‑8912 as the ESP‑12 interface (per `server/drivers/ay.asm`).
- ESP‑12 with compatible AT firmware (`AT+RST`, `AT+CIPMUX`, `AT+CIPSERVER`, `AT+CIFSR`, etc.).
- Access to a configured Wi‑Fi network on the ESP‑12.

### On the PC
- Windows with PowerShell (for `SNAPZX.ps1`) or run `SNAPZX.exe` directly.
- IP connectivity to the Spectrum/ESP‑12 on the same network.

## Installation

### Option A: dot-command (recommended)
1. Copy `server/snapzx` to the SD card, typically into `\BIN\` (or the directory from which you want to invoke it).
2. In ESXDOS, run:
   - `.snapzx`

### Option B: RAM binary + BASIC loader
1. Copy `server/snapzx.bin` and `server/SNAPZX.BAS` to the SD card.
2. Run the loader from +3DOS "SNAPZX.BAS"

## Quick start

1. On the Spectrum, run SnapZX and note the IP shown on screen.
2. On the PC, open `client/SNAPZX.exe` (or `client/SNAPZX.ps1`).
3. Enter the Spectrum/ESP‑12 IP and select a valid `.SNA`.
4. Press **SEND** and wait for:
   - the Spectrum to show the filename and progress bar,
   - the client to report completion and, when applicable, **ACK** received,
   - the Spectrum to launch the snapshot via `snapload`.

## Transfer protocol (summary)

Inside the ESP’s `+IPD` binary payload, the server expects the following structure:

- `LAIN` (4 ASCII bytes)
- `snapshot_len` (`uint32_le`)
- `FN` (2 ASCII bytes)
- `name_len` (`uint8`)
- `name` (`name_len` bytes)
- `payload` (`snapshot_len` bytes)

After successfully receiving and writing the payload, the server sends an **application ACK** (`OK\r\n`) before launching `snapload`.

## Integrity and error handling

- **Early close / cancellation:** if the connection closes while a partial file is open, the handle is closed and the incomplete file is deleted.
- **Receive timeouts:** if a chunk does not progress within the expected window, the server aborts and cleans up.
- **Resynchronization:** the server strictly searches for `+IPD,` and discards stream noise to return to a consistent state.
- **“Probe” connections:** the server ignores connections that open/close without sending a valid `+IPD`, preventing false positives due to client probing.

## Current limitations

- The client is currently focused on `.SNA` snapshots and intentionally validates standard 48K/128K sizes.
- The server assumes the workflow “receive `.SNA` → `snapload`”. For other file types or use cases (e.g., “upload without executing”), an alternative mode would be required.

## Credits

- (C) 2025 **M. Ignacio Monge García**
- Based on **LAIN** (C) 2022 **Alex Nihirash**
- Created with **Chat-GPT**, **DeepSeek** and **Claude**.
