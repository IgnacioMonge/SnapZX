    device ZXSPECTRUM48

    IFDEF DOT
        org #2000
    ELSE
        org #8000          ; 32768 (FAST RAM)          ; 24576
    ENDIF

text
    jp start
ver:
    db "SnapZX SNA Uploader v"
    include "version.asm"
    db 13
    db "(C) 2025 M. Ignacio Monge Garcia", 13
    db "(C) 2022 Alex Nihirash (LAIN)   ", 0

    include "modules/display.asm"
    include "modules/wifi.asm"
    include "modules/esxdos.asm"

    IFDEF UNO
    include "drivers/zxuno.asm"
    ENDIF

    IFDEF AY
    include "drivers/ay.asm"
    ENDIF

start:
    ; Screen style: BORDER/PAPER black, default INK white (robust: set ATTR_P/ATTR_T then CLS).
    call ScreenInit
    ld d,0
    ld e,0
    call Display.setPos
    call Display.initBarChars

    ; Header (white text)
    printMsg msg_hdr_white
    printMsg ver
    ; Yellow solid line separator
    printMsg msg_hdr_yellow
    printMsg msg_line
    printMsg msg_hdr_white
    printMsg msg_uart
    call Uart.init
    printMsg msg_wifi
    call Wifi.init
    ; Ready banner (green) + Ready line (green) + banner (green)
    printMsg msg_ink_green_dot
    printMsg msg_ready_line
    printMsg msg_ready_pre
    printMsg Wifi.ipAddr
    printMsg msg_ready_port
    printMsg msg_ready_line
    printMsg msg_ink_white_dot

		; Record the line where the "Waiting for transfer..." status is printed so it can be
		; overwritten when the transfer actually starts.
		; S_POSN (23689) stores (24 - line). Convert to line 0..23.
		ld a, 24
		ld b, a
		ld a, (23689)
		ld c, a
		ld a, b
		sub c
		ld (Wifi.wait_row), a

		; Only show the waiting message once UART/Wi-Fi are initialized and we are truly ready.
		printMsg msg_boot
    ei
    jp Wifi.recv

; Ready message separator (small ASCII '-'), full width (32 cols)
; No leading CR to avoid an empty line between "Ready" and the separator.
msg_ready_line db "--------------------------------", 13, 0

msg_ready_pre  db "Ready: ", 0
msg_ready_port db ":6144", 13, 0

msg_boot db "Waiting for transfer...", 13, 0
msg_uart db "Initializing UART...", 13, 0
msg_wifi db "Initializing Wi-Fi module...", 13, 0
msg_ink_green_dot db 16, 4, 0
msg_ink_white_dot db 16, 7, 0

; Screen/control sequences (Spectrum ROM print control codes)
; 12 = CLS
; 17,<n> = PAPER
; 16,<n> = INK
; 19,<n> = BRIGHT
msg_hdr_yellow   db 16, 6, 0
msg_hdr_white    db 16, 7, 0

; 32-column full-width separator (thin line using UDG 'D' = CHR$147)
msg_line db 147,147,147,147,147,147,147,147,147,147,147,147,147,147,147,147
         db 147,147,147,147,147,147,147,147,147,147,147,147,147,147,147,147
         db 13, 13, 0

; ----------------------------
; Helpers
; ----------------------------

ScreenInit:
    ; For standalone (launched via RANDOMIZE USR), force output to the SCREEN channel (stream 2)
    ; so text is printed on the full display, not the BASIC lower screen.
    IFNDEF DOT
        ld a, 2
        call #1601                 ; CHAN_OPEN (ROM)
    ENDIF

    ; Disable BASIC lower screen (DF_SZ=0) for full 24-line display.
    xor a
    ld (23659), a              ; DF_SZ

    ; Set permanent + temporary attributes to: BRIGHT 1, PAPER 0 (black), INK 7 (white)
    ld a, #47
    ld (23693), a              ; ATTR_P
    ld (23695), a              ; ATTR_T

    ; Border color to black
    xor a
    ld (23624), a              ; BORDCR
    out (#fe), a

    ; Clear screen
    ld a, 12
    rst #10                    ; CLS

    ; Force attribute map to black paper/white ink/bright on BOTH possible screens:
    ; normal (#5800) and shadow (#D800). ESXDOS/dot-commands may start with shadow screen active.
    ld a, #47

    ld hl, #5800
    ld de, #5801
    ld bc, 32*24-1
    ld (hl), a
    ldir

    ld hl, #D800
    ld de, #D801
    ld bc, 32*24-1
    ld (hl), a
    ldir

    ; Ensure BRIGHT on for subsequent prints
    ld a, 19
    rst #10
    ld a, 1
    rst #10
    ret


buffer = #C000
     IFDEF DOT
        savebin "snapzx", text, $ - text
    ELSE
        savebin "snapzx.bin", text, $ - text
    ENDIF
