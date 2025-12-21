# SnapZX

<p align="center">
  <img src="images/logo.png" alt="SnapZX Logo" width="640" />
</p>

> **Current Version:** Release 1.0 "Onyx Edition"
>
> *Spanish version: [READMEsp.md](READMEsp.md)*

**SnapZX** is a streamlined Wi-Fi transfer system designed to **upload `.SNA` snapshots** from a PC to a **ZX Spectrum (48K/128K)** and **execute them automatically**. It utilizes an **ESP-12** module connected via the **AY-3-8912** sound chip (bit-banged UART) and a custom server optimized for **ESXDOS**.

Built with a "Select → Send → Play" philosophy, it eliminates the friction of development cycles and daily usage (no more audio cables, no more manual loading).

## ⚡ Key Features

* **Standalone Client:** A single `SnapZX.exe` file. No installation required, no dependencies.
* **Smart Auto-Run:** The server receives the file, saves it to the SD card, and immediately launches it using `snapload`.
* **Robust Protocol:** Features chunked transfer, strict validation, and automatic cleanup of corrupted/partial files upon connection loss.
* **Real-time Feedback:** Visual progress bars on both the PC and the Spectrum screen.
* **State-Aware:** The PC client actively monitors the connection status, distinguishing between "Offline", "Port Closed", and "Ready".

## 🛠️ Requirements

### On the ZX Spectrum
* **ESXDOS** (DivMMC, DivMMC Enjoy, or compatible interface).
* **AY-3-8912** interface wired to an ESP-12 module (standard wiring used by drivers in `server/drivers/ay.asm`).
* **ESP-12** module with AT firmware capable of `AT+CIPSERVER`.

### On the PC
* Windows 10 or 11.
* Wi-Fi/Network connection on the same subnet as the Spectrum.

## 📦 Installation

### Spectrum Side (Server)
1.  Copy the file `server/snapzx` to your SD card (typically in `/BIN` or root).
2.  Run it from ESXDOS:
    ```basic
    .snapzx
    ```

### PC Side (Client)
1.  Download `SnapZX.exe` from the latest release.
2.  Run it.

## 🚀 Quick Start

1.  **Spectrum:** Run `.snapzx`. Note the IP address displayed on the screen.
2.  **PC:** Launch `SnapZX.exe`.
3.  Enter the Spectrum's IP. The indicator should turn **Green** (Ready).
4.  Drag & Drop a `.SNA` file into the window.
5.  Click **SEND**.
6.  **Play:** The game will load automatically in seconds.

## 📜 Credits

* **(C) 2025 M. Ignacio Monge García**: Complete refactoring, robust Windows Forms client (v4.0), protocol hardening, UI/UX redesign, and standalone compilation.
* Based on original work **LAIN** by **(C) 2022 Alex Nihirash**.
* Developed with the assistance of **AI** (Chat-GPT, DeepSeek, and Gemini) for Z80 assembly optimization and advanced PowerShell scripting.