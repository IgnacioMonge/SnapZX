DEVICE ZXSPECTRUM48

    IFDEF DOT
        org #2000
    ELSE
        org #8000
    ENDIF

text:
    jp start
ver:
    db "SnapZX SNA Uploader v"
    include "version.asm"
    db 13
    db "(C) 2025 M. Ignacio Monge Garcia", 13
    db "(C) 2022 Alex Nihirash (LAIN)   ", 0

    include "modules/display.asm"
    include "modules/wifi.asm"    ; <--- RUTA CORREGIDA: modules/
    include "modules/esxdos.asm"

    IFDEF UNO
    include "drivers/zxuno.asm"
    ENDIF

    IFDEF AY
    include "drivers/ay.asm"
    ENDIF

start:
    call ScreenInit
    ld d,0
    ld e,0
    call Display.setPos
    call Display.initBarChars

    printMsg msg_hdr_white
    printMsg ver
    printMsg msg_hdr_yellow
    printMsg msg_line
    printMsg msg_hdr_white

    IFDEF AY
        printMsg msg_uart
        call Uart.init
    ENDIF

    IFDEF UNO
        printMsg msg_uart
        call Uart.init
    ENDIF

    printMsg msg_wifi
    call Wifi.init
    
    printMsg msg_ink_green_dot
    printMsg msg_ready_line
    printMsg msg_ready_pre
    printMsg Wifi.ipAddr
    printMsg msg_ready_port
    printMsg msg_ready_line
    printMsg msg_ink_white_dot

    ; Calcular posición de espera
    ld a, 24
    ld b, a
    ld a, (23689)
    ld c, a
    ld a, b
    sub c
    ld (Wifi.wait_row), a

    printMsg msg_boot
    ei
    jp Wifi.recv

; Mensajes
msg_ready_line db "--------------------------------", 13, 0
msg_ready_pre  db "Ready: ", 0
msg_ready_port db ":6144", 13, 0
msg_boot db "Waiting for transfer...", 13, 0
msg_uart db "Initializing UART...", 13, 0
msg_wifi db "Initializing Wi-Fi module...", 13, 0
msg_ink_green_dot db 16, 4, 0
msg_ink_white_dot db 16, 7, 0
msg_hdr_yellow   db 16, 6, 0
msg_hdr_white    db 16, 7, 0
msg_line db 147,147,147,147,147,147,147,147,147,147,147,147,147,147,147,147
         db 147,147,147,147,147,147,147,147,147,147,147,147,147,147,147,147
         db 13, 13, 0

ScreenInit:
    IFNDEF DOT
        ld a, 2
        call #1601
    ENDIF
    xor a
    ld (23659), a
    ld a, #47
    ld (23693), a
    ld (23695), a
    xor a
    ld (23624), a
    out (#fe), a
    ld a, 12
    rst #10
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
    ld a, 19
    rst #10
    ld a, 1
    rst #10
    ret

    IFDEF DOT
        savebin "snapzx", text, $ - text
    ELSE
        savebin "snapzx.bin", text, $ - text
    ENDIF