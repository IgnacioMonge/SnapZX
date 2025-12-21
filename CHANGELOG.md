\# Changelog



All notable changes to the \*\*SnapZX\*\* project will be documented in this file.



The format is based on \[Keep a Changelog](https://keepachangelog.com/en/1.0.0/),

and this project adheres to \[Semantic Versioning](https://semver.org/spec/v2.0.0.html).



\## \[1.0.0] - "Onyx Edition" - 2025-01-26



\*\*Major Release.\*\* Transition from script-based prototype to standalone application.



\### 🚀 New Features (Client - Windows)

\* \*\*Standalone Executable:\*\* The client is now compiled into a single portable `SnapZX.exe`.

&nbsp;   \* \*\*Embedded Resources:\*\* Logo (`.png`) and Icon (`.ico`) are serialized as Base64 strings and injected directly into the executable. No external asset files are required.

&nbsp;   \* \*\*Startup Speed:\*\* Optimized resource loading from memory streams.

\* \*\*"Onyx" UI Overhaul:\*\*

&nbsp;   \* New black header with branding and branding stripes inspired by ZX Spectrum design.

&nbsp;   \* Main window layout reorganized for better ergonomic flow (Top-to-Bottom: Connection -> File -> Action -> Status).

&nbsp;   \* Progress bar now auto-hides when entering "Waiting for ACK" state to reduce visual confusion.

\* \*\*Advanced Connection Monitoring:\*\*

&nbsp;   \* Implemented a 4-state status indicator with hysteresis to prevent flickering:

&nbsp;       \* 🔴 \*\*Red:\*\* Transfer cancelled by user or critical error.

&nbsp;       \* 🟡 \*\*Yellow:\*\* Host reachable (Ping OK) but TCP port 6144 is closed/unreachable.

&nbsp;       \* 🔵 \*\*Blue:\*\* TCP Port open, but application handshake failed (Server running but not SnapZX).

&nbsp;       \* 🟢 \*\*Green:\*\* Full handshake OK ("Ready").

&nbsp;   \* Real-time status text injected into the connection GroupBox.

\* \*\*Configuration Management:\*\*

&nbsp;   \* Settings (Last IP, Last File) are now saved to `%LocalAppData%\\SnapZX\\config.json` instead of the application directory, compliant with Windows standards.

\* \*\*Smart Validation:\*\*

&nbsp;   \* Automatic detection of 48K vs 128K snapshot files based on exact byte size.

&nbsp;   \* Sanitization of filenames to 8.3 format before transmission.



\### ⚡ Improvements (Server - ZX Spectrum)

\* \*\*Smart Initialization:\*\* The server now probes the ESP-12 status before forcing a reset. If the module is already configured (IP obtained, Server running), initialization is skipped, reducing boot time from ~5s to <1s.

\* \*\*Visual Feedback:\*\*

&nbsp;   \* On-screen progress bar using custom UDGs (Green blocks).

&nbsp;   \* Detailed status messages overwriting the previous line to keep the screen clean.

\* \*\*Robustness:\*\*

&nbsp;   \* Implemented strict `+IPD` stream resynchronization to handle Wi-Fi noise.

&nbsp;   \* Added aggressive receive timeouts.

&nbsp;   \* \*\*Auto-Cleanup:\*\* If a connection drops or is cancelled mid-transfer, the partial file is automatically deleted from the SD card to prevent corruption.



\### 🐛 Bug Fixes

\* Fixed an issue where the "Sending..." status would persist even after the transfer finished.

\* Fixed a race condition in the PowerShell runspace that caused UI freezes during drag-and-drop operations.

\* Fixed `ICON\_FILENAME` and `LOGO\_FILENAME` dependency errors when compiling to EXE.

\* Corrected the "Port open but app silent" message to "Port open but not reachable" for clarity.



---



\## \[0.9.0] - Beta - 2025-01-20

\### Added

\* Initial PowerShell GUI implementation.

\* Basic ESP-12 UART driver implementation (Z80).

\* ESXDOS integration for file writing.

\* Basic `snapload` integration.

