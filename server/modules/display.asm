    module Display
putStr:
    ld a, (hl) : and a : ret z
    push hl
    rst #10
    pop hl
    inc hl
    jr putStr

; Set print position using ROM control code AT.
; In: D=row (0..23), E=col (0..31)
setPos:
    ld a, 22 : rst #10
    ld a, d  : rst #10
    ld a, e  : rst #10
    ret

; Define UDG A as horizontal "battery" bar (thin block).
; Define UDG D as decorative thin line for separators.
; Uses system variable UDG at 23675.
initBarChars:
    ld hl, (23675)      ; UDG base address

    ; UDG 'A' (CHR$144): thin centered bar
    ld b, 8
    ld a, #3C
.aLoop:
    ld (hl), a
    inc hl
    djnz .aLoop

    ; Skip UDG 'B' and 'C' (8+8 bytes) - not used
    ld de, 16
    add hl, de

    ; UDG 'D' (CHR$147): Thin horizontal line (2 pixels high, centered)
    xor a           ; ........
    ld (hl), a
    inc hl
    ld (hl), a      ; ........
    inc hl
    ld (hl), a      ; ........
    inc hl
    ld a, #FF       ; ########
    ld (hl), a
    inc hl
    ld (hl), a      ; ########
    inc hl
    xor a           ; ........
    ld (hl), a
    inc hl
    ld (hl), a      ; ........
    inc hl
    ld (hl), a      ; ........
    inc hl

    ; UDG 'E' (CHR$148): Right arrow head ►
    ld a, #18       ; ...##...
    ld (hl), a
    inc hl
    ld a, #1C       ; ...###..
    ld (hl), a
    inc hl
    ld a, #FE       ; #######.
    ld (hl), a
    inc hl
    ld a, #FF       ; ########
    ld (hl), a
    inc hl
    ld a, #FF       ; ########
    ld (hl), a
    inc hl
    ld a, #FE       ; #######.
    ld (hl), a
    inc hl
    ld a, #1C       ; ...###..
    ld (hl), a
    inc hl
    ld a, #18       ; ...##...
    ld (hl), a
    inc hl

    ; UDG 'F' (CHR$149): Left arrow head ◄
    ld a, #18       ; ...##...
    ld (hl), a
    inc hl
    ld a, #38       ; ..###...
    ld (hl), a
    inc hl
    ld a, #7F       ; .#######
    ld (hl), a
    inc hl
    ld a, #FF       ; ########
    ld (hl), a
    inc hl
    ld a, #FF       ; ########
    ld (hl), a
    inc hl
    ld a, #7F       ; .#######
    ld (hl), a
    inc hl
    ld a, #38       ; ..###...
    ld (hl), a
    inc hl
    ld a, #18       ; ...##...
    ld (hl), a
    inc hl

    ret

    endmodule

    macro printMsg ptr
    ld hl, ptr : call Display.putStr
    endm