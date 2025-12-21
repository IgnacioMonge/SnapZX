# SnapZX

<p align="center">
  <img src="images/logo.png" alt="SnapZX Logo" width="640" />
</p>

> **Versión actual:** Release 1.0 "Onyx Edition"
>
> *English version: [README.md](README.md)*

**SnapZX** es un sistema de transferencia Wi-Fi para **cargar snapshots `.SNA`** desde un PC a un **ZX Spectrum (48K/128K)** y **ejecutarlos automáticamente**, utilizando un módulo **ESP-12** conectado al bus del **AY-3-8912** (UART bit-banged) y un servidor diseñado para **ESXDOS**.

Diseñado bajo la filosofía "Seleccionar → Enviar → Jugar", elimina la fricción en el desarrollo, pruebas o uso diario (adiós cables de audio, adiós cargas manuales).

## ⚡ Características Principales

* **Cliente Autónomo:** Un único archivo `SnapZX.exe` portable. Sin instalación ni dependencias externas.
* **Auto-Arranque Inteligente:** El servidor recibe el archivo, lo guarda en la SD y lanza inmediatamente `snapload`.
* **Protocolo Robusto:** Implementa transferencia por bloques (chunked), validación estricta y limpieza automática de archivos corruptos o parciales si se corta la conexión.
* **Feedback Visual:** Barras de progreso visuales tanto en el PC como en la pantalla del Spectrum.
* **Monitor de Estado:** El cliente de PC monitoriza activamente la conexión, distinguiendo entre "Desconectado", "Puerto Cerrado" y "Listo".

## 🛠️ Requisitos

### En el Spectrum
* **ESXDOS** (DivMMC, DivMMC Enjoy, o interfaz compatible).
* Hardware que permita usar el **AY-3-8912** como interfaz para el ESP-12 (según `server/drivers/ay.asm`).
* Módulo **ESP-12** con firmware AT compatible (`AT+CIPSERVER`, etc.).

### En el PC
* Windows 10 u 11.
* Conectividad IP en la misma red que el Spectrum.

## 📦 Instalación

### Lado Spectrum (Servidor)
1.  Copia el archivo `server/snapzx` a la tarjeta SD, preferiblemente en la carpeta `\BIN\` (o raíz).
2.  Desde ESXDOS, ejecuta:
    ```basic
    .snapzx
    ```
3. También puedes ejecutar el fichero SnapZX.BAS desde el navegador de ficheros de esxDOS. 

### Lado PC (Cliente)
1.  Descarga `SnapZX.exe` de la última release.
2.  Ejecútalo (no requiere instalación).

## 🚀 Guía Rápida

1.  **Spectrum:** Ejecuta `.snapzx`. Verás la IP asignada y el mensaje "Waiting for transfer...".
2.  **PC:** Abre `SnapZX.exe`.
3.  Introduce la IP que muestra el Spectrum. El indicador debería ponerse **Verde** (Ready).
4.  Arrastra un archivo `.SNA` a la ventana.
5.  Pulsa **SEND**.
6.  **A jugar:** El Spectrum recibirá el archivo, mostrará el progreso y ejecutará el juego automáticamente.

## 📜 Créditos

* **(C) 2025 M. Ignacio Monge García**: Refactorización completa, cliente Windows Forms robusto (v4.0), mejoras en protocolo, rediseño UI/UX y compilación autónoma.
* Basado en el trabajo original **LAIN** de **(C) 2022 Alex Nihirash**.
* Desarrollado con la asistencia de **IA** (Chat-GPT, DeepSeek y Gemini) para optimización de ensamblador Z80 y scripting PowerShell avanzado.
