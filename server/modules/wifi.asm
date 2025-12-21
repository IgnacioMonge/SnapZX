; =============================================================================
;  MODULES/WIFI.ASM - V13.1 (CORREGIDO + STEP_ACC RESTAURADO)
; =============================================================================

    MACRO EspSend _txt
    ld hl, .txtB
    ld e, .txtE - .txtB
    call Wifi.espSend
    jr .txtE
.txtB: db _txt
.txtE:
    ENDM

    MACRO EspCmd _txt
    ld hl, .txtB
    ld e, .txtE - .txtB
    call Wifi.espSend
    jr .txtE
.txtB: db _txt, 13, 10
.txtE:
    ENDM

    MACRO EspCmdOkErr _txt
    EspCmd _txt
    call Wifi.checkOkErr
    ENDM

    module Wifi

init:
    ei 
    ld a, (wait_row)
    or a
    jr nz, .row_ok
    ld a, 8
    ld (wait_row), a
.row_ok:

    EspSend "+++"
    ld b, 20
.wait_exit:
    halt
    djnz .wait_exit

    call probeESP
    jp c, .need_full_reset
    call checkHasIP
    jp c, .need_full_reset
    call checkServerStatus
    jr c, .start_server
    call getMyIp
    ret

.start_server:
    EspCmdOkErr "ATE0"
    jp c, .err
    EspCmdOkErr "AT+CIPDINFO=0"
    jp c, .err
    EspCmdOkErr "AT+CIPMUX=1"
    jp c, .err
    EspCmdOkErr "AT+CIPSERVER=1,6144"
    jp c, .err
    call getMyIp
    ret

.need_full_reset:
    call fullReset
    jr c, .err
    EspCmdOkErr "ATE0"
    jp c, .err
    EspCmdOkErr "AT+CIPDINFO=0"
    jp c, .err
    EspCmdOkErr "AT+CIPMUX=1"
    jp c, .err
    EspCmdOkErr "AT+CIPSERVER=1,6144"
    jp c, .err
    call getMyIp
    ret

.err:
    ld hl, .err_msg
    call Display.putStr
    di
    halt
.err_msg: db 13, "ESP error! Halted!", 0

probeESP:
    call flushUartQuick
    EspCmd "AT"
    call checkOkErrTimeout
    ret

checkHasIP:
    call flushUartQuick
    EspCmd "AT+CIFSR"
.loop:
    call readByteShortTimeout
    jr nc, .no_ip
    cp 'S'
    jr nz, .check_ok
    call readByteShortTimeout : jr nc, .no_ip : cp 'T' : jr nz, .loop
    call readByteShortTimeout : jr nc, .no_ip : cp 'A' : jr nz, .loop
    call readByteShortTimeout : jr nc, .no_ip : cp 'I' : jr nz, .loop
    call readByteShortTimeout : jr nc, .no_ip : cp 'P' : jr nz, .loop
    call readByteShortTimeout : jr nc, .no_ip : cp ',' : jr nz, .loop
    call readByteShortTimeout : jr nc, .no_ip : cp '"' : jr nz, .loop
    call readByteShortTimeout : jr nc, .no_ip : cp '0' : jr z, .check_zero_ip
    call flushToOK
    or a
    ret
.check_zero_ip:
    call readByteShortTimeout : jr nc, .no_ip : cp '.' : jr nz, .has_ip
    call flushToOK
    scf
    ret
.has_ip:
    call flushToOK
    or a
    ret
.check_ok:
    cp 'O'
    jr nz, .loop
.no_ip:
    scf
    ret

checkServerStatus:
    call flushUartQuick
    EspCmd "AT+CIPSTATUS"
    call flushToOK
    call flushUartQuick
    EspCmd "AT+CIPMUX?"
.mux_loop:
    call readByteShortTimeout : jr nc, .no_server : cp ':' : jr nz, .mux_loop
    call readByteShortTimeout : jr nc, .no_server : cp '1' : jr nz, .no_server
    call flushToOK
    or a
    ret
.no_server:
    call flushToOK
    scf
    ret

fullReset:
    EspCmd "AT+RST"
.wait_ready:
    call readByteTimeout : jr nc, .timeout : cp 'y' : jr nz, .wait_ready
.wait_gotip:
    call readByteTimeout : jr nc, .timeout : cp 'P' : jr nz, .wait_gotip
    or a
    ret
.timeout:
    scf
    ret

readByteShortTimeout:
    ld b, 100
.loop:
    call Uart.uartRead : jr c, .got : djnz .loop
    or a : ret
.got:
    scf : ret

flushUartQuick:
    ld b, 10
.loop:
    call Uart.uartRead : jr nc, .done : djnz .loop
.done:
    ret

flushToOK:
    call readByteShortTimeout : ret nc : cp 'O' : jr nz, flushToOK
    call readByteShortTimeout : ret nc : cp 'K' : jr nz, flushToOK
    ret

checkOkErrTimeout:
    ld c, 0
.loop:
    call readByteShortTimeout : jr nc, .timeout
    cp 'O' : jr z, .okStart
    cp 'E' : jr z, .errStart
    inc c : ld a, c : cp 200 : jr c, .loop
.timeout:
    scf : ret
.okStart:
    call readByteShortTimeout : jr nc, .timeout : cp 'K' : jr nz, .loop
    or a : ret
.errStart:
    scf : ret

readByteTimeout:
    ld b, 200
.rbt_loop:
    call Uart.uartRead
    jr c, .rbt_got

    ; Visual Feedback: Negro si espera
    ld a, (visual_feedback_enabled)
    or a
    jr z, .skip_black
    push af
    xor a
    out (#fe), a
    pop af
    
.skip_black:
    djnz .rbt_loop
    or a : ret

.rbt_got:
    ; Visual Feedback: Color si recibe
    push af
    ld a, (visual_feedback_enabled)
    or a
    jr z, .skip_color
    
    cp 1 ; Azul?
    jr z, .set_blue
    ld a, 4 ; Verde
    out (#fe), a
    jr .skip_color
.set_blue:
    ld a, 1
    out (#fe), a
.skip_color:
    pop af
    scf : ret

recv:
    xor a
    ld (hdr_phase), a
    ld (hdr_pos), a
    ld (fn_pos), a
    ld (name_pos), a
    ld (name_len), a
    ld (wrote_flag), a
    ld (file_opened), a
    ld (bar_ready), a
    ld (bar_row), a
    ld (prog_units), a
    ld (step_acc), a
    ld (xfer_done), a
    ld (probe_mode), a
    ld a, '0'
    ld (socket_id), a
    ld hl, 0
    ld (xfer_rem_lo), hl
    ld (xfer_rem_hi), hl
    ld (done_lo), hl
    ld (done_hi), hl
    ld (thr_ptr), hl
    
    ld a, 1
    ld (visual_feedback_enabled), a
    
    ld a, (wait_row) : or a : jr nz, .wait_ok : ld a, 8 : ld (wait_row), a
.wait_ok:
    ld a, 1 : out (#fe), a
    jp .waitIPD

.rxTimeout:
    jp Wifi_PayloadTimeoutAbort

.waitIPD:
    ld bc, #A800 ; Timeout ORIGINAL
.waitIPD_loop:
    push bc
    call Wifi.readByteTimeout
    pop bc
    jp c, .waitIPD_gotByte
    dec bc
    ld a, b
    or c
    jp nz, .waitIPD_loop
    ld a, (file_opened)
    or a
    jp nz, Wifi_PayloadTimeoutAbort
    
    ld a, (visual_feedback_enabled)
    cp 1
    jr nz, .no_idle_blue
    ld a, 1 : out (#fe), a
.no_idle_blue:
    
    jp .waitIPD

.waitIPD_gotByte:
    ld bc, #A800
    cp 'C' : jp z, .maybeClosed
    cp '+' : jp nz, .waitIPD_loop

.waitIPD_gotPlus:
    push bc
    call Wifi.readByteTimeout : pop bc : jp nc, .waitIPD_loop : cp 'I' : jp nz, .waitIPD_loop
    push bc
    call Wifi.readByteTimeout : pop bc : jp nc, .waitIPD_loop : cp 'P' : jp nz, .waitIPD_loop
    push bc
    call Wifi.readByteTimeout : pop bc : jp nc, .waitIPD_loop : cp 'D' : jp nz, .waitIPD_loop
    push bc
    call Wifi.readByteTimeout : pop bc : jp nc, .waitIPD_loop : cp ',' : jp nz, .waitIPD_loop

.readSock:
    call Wifi.readByteTimeout : jp nc, .waitIPD
    cp ',' : jr z, .sockDone
    cp '0' : jr c, .readSock
    cp '9'+1 : jr nc, .readSock
    ld (socket_id), a : jr .readSock
.sockDone:
    ld hl,0
.cil1:
    push hl
    call Wifi.readByteTimeout : jr nc, .lenParseTimeout
    pop hl 
    cp ':' : jr z, .storeAvail
    cp '0' : jr c, .lenParseInvalid
    cp '9'+1 : jr nc, .lenParseInvalid
    sub '0'
    ld c,l : ld b,h
    add hl,hl : add hl,hl : add hl,bc : add hl,hl
    ld c,a : ld b,0
    add hl,bc
    jr .cil1

.lenParseTimeout:
    pop hl : jp .waitIPD
.lenParseInvalid:
    jp .waitIPD
.storeAvail:
    ld (data_avail), hl
.chunkLoop:
    ld hl, (data_avail)
    ld a, h : or l : jr nz, .haveData
    ld a, (xfer_done) : or a : jp z, .waitIPD
    call Wifi_Finalize
    call ShowCompleteAndPause
    jp c, Wifi_CrcAbort
    jp EsxDOS.closeAndRun

.haveData:
    ld de, 2048 ; FIX BUFFER 2K (Evita Invalid Header)
    or a : sbc hl, de : jr c, .useRemaining
    ld (data_avail), hl
    ld hl, 2048
    jr .readChunk
.useRemaining:
    ld hl, (data_avail)
    ld de, 0
    ld (data_avail), de

.readChunk:
    push hl
    ld de, buffer
    ld bc, #A800
.loadPacket_loop:
    push bc : push hl : push de
    call Wifi.readByteTimeout
    jr nc, .loadPacket_timeout
    pop de : pop hl : pop bc
    ld (de), a : inc de : dec hl
    ld a, h : or l : jr nz, .loadPacket_loop
    pop bc
    call consumeChunk
    jp .chunkLoop

.loadPacket_timeout:
    pop de : pop hl : pop bc
    dec bc
    ld a, b : or c : jr nz, .loadPacket_loop
    pop bc
    jp .rxTimeout

.maybeClosed:
    call Wifi.readByteTimeout : jp nc, .waitIPD : cp 'L' : jp nz, .waitIPD
    call Wifi.readByteTimeout : jp nc, .waitIPD : cp 'O' : jp nz, .waitIPD
    call Wifi.readByteTimeout : jp nc, .waitIPD : cp 'S' : jp nz, .waitIPD
    call Wifi.readByteTimeout : jp nc, .waitIPD : cp 'E' : jp nz, .waitIPD
    call Wifi.readByteTimeout : jp nc, .waitIPD : cp 'D' : jp nz, .waitIPD
    ld a, (xfer_done) : or a : jr z, .closed_continue
    call ShowCompleteAndPause : jp c, Wifi_CrcAbort
    call Wifi_Finalize
    jp EsxDOS.closeAndRun
.closed_continue:
    ld a, (hdr_pos) : or a : jp nz, .closed_abort
    ld a, (hdr_phase) : or a : jp nz, .closed_abort
    ld a, (fn_pos) : or a : jp nz, .closed_abort
    ld a, (name_pos) : or a : jp nz, .closed_abort
    ld a, (file_opened) : or a : jp nz, .closed_abort
    jp .waitIPD

.closed_abort:
    ld sp, stack_top
    xor a
    ld (visual_feedback_enabled), a
    out (#fe), a
    call BeepError

    printMsg msg_conn_closed
    ld a, (file_opened)
    or a : jr z, .no_close
    call EsxDOS.closeOnly
    printMsg msg_deleting
    ld hl, EsxDOS.filename
    call Display.putStr
    printMsg msg_newline
    call EsxDOS.deleteFile
    xor a
    ld (file_opened), a
.no_close:
    printMsg msg_press_key_return
    call WaitErrorReset
    call Wifi_ShowResetFeedback
    call Wifi_CloseConn0
    call Wifi_FlushSilence
    call Wifi_UiResetToWaiting
    jp recv

Wifi_CrcAbort:
    ld sp, stack_top
    ld a, (file_opened)
    or a : jr z, .no_close
    call EsxDOS.closeOnly
    call EsxDOS.deleteFile
    xor a
    ld (file_opened), a
.no_close:
    call WaitErrorReset
    call Wifi_ShowResetFeedback
    call Wifi_CloseConn0
    call Wifi_FlushSilence
    call Wifi_UiResetToWaiting
    jp recv

Wifi_ProtoAbort:
    ld sp, stack_top
    xor a
    ld (visual_feedback_enabled), a
    out (#fe), a
    call BeepError
    
    printMsg msg_badhdr
    ld a, (file_opened)
    or a : jr z, .no_file
    call EsxDOS.closeOnly
    printMsg msg_deleting
    ld hl, EsxDOS.filename
    call Display.putStr
    printMsg msg_newline
    call EsxDOS.deleteFile
    xor a
    ld (file_opened), a
.no_file:
    printMsg msg_press_key_return
    call WaitErrorReset
    call Wifi_ShowResetFeedback
    call Wifi_CloseConn0
    call Wifi_FlushSilence
    call Wifi_UiResetToWaiting
    xor a
    ld (hdr_phase), a
    ld hl, 0
    ld (buf_ptr), hl
    ld (chunk_work), hl
    jp recv

Wifi_PayloadTimeoutAbort:
    ld sp, stack_top
    xor a
    ld (visual_feedback_enabled), a
    out (#fe), a
    call BeepError
    
    printMsg msg_xfer_timeout
    ld a, (file_opened)
    or a : jr z, .no_close
    call EsxDOS.closeOnly
    printMsg msg_deleting
    ld hl, EsxDOS.filename
    call Display.putStr
    printMsg msg_newline
    call EsxDOS.deleteFile
    xor a
    ld (file_opened), a
.no_close:
    printMsg msg_press_key_return

    call WaitErrorReset
    call Wifi_ShowResetFeedback
    call Wifi_CloseConn0
    call Wifi_FlushSilence
    call Wifi_UiResetToWaiting
    xor a
    ld (xfer_done), a
    ld (hdr_phase), a
    ld hl, 0
    ld (xfer_rem_lo), hl
    ld (xfer_rem_hi), hl
    ld (buf_ptr), hl
    ld (chunk_work), hl
    jp recv

consumeChunk:
    ld hl, buffer
    ld (buf_ptr), hl
    ld (chunk_work), bc
    ld a, (xfer_done) : or a : ret nz
.loop:
    ld bc, (chunk_work)
    ld a, b : or c : ret z
    ld a, (hdr_phase)
    or a : jp z, .phase0
    cp 1 : jp z, .phase1
    cp 2 : jp z, .phase2
    cp 3 : jp z, .phase3
    jp .payload

.phase0:
    ld a, (hdr_pos) : cp 10 : jp nc, .p0_done
    ld e, a : ld a, 10 : sub e : ld e, a
    ld bc, (chunk_work)
    ld a, b : or a : jp nz, .p0_take_need
    ld a, c : cp e : jp c, .p0_take_chunk
.p0_take_need:
    ld a, e
.p0_take_chunk:
    ld (tmp_take), a
    ld a, (hdr_pos) : ld l, a : ld h, 0
    ld de, hdr_buf : add hl, de : ex de, hl
    ld hl, (buf_ptr) : ld b, 0 : ld a, (tmp_take) : ld c, a : ldir
    ld a, (hdr_pos) : ld d, a : ld a, (tmp_take) : add a, d : ld (hdr_pos), a
    ld bc, (chunk_work)
    ld a, (tmp_take) : ld e, a : ld a, c : sub e : ld c, a
    ld a, b : sbc a, 0 : ld b, a : ld (chunk_work), bc
    ld hl, (buf_ptr) : ld a, (tmp_take) : ld e, a : ld d, 0 : add hl, de : ld (buf_ptr), hl
.p0_check:
    ld a, (hdr_pos) : cp 10 : ret nz
.p0_done:
    call validateHeader : jp c, Wifi_ProtoAbort
    ld a, 1 : ld (hdr_phase), a : jp .loop

.phase1:
    ld a, (fn_pos) : cp 2 : jp nc, .p1_done
    ld e, a : ld a, 2 : sub e : ld e, a
    ld bc, (chunk_work)
    ld a, b : or a : jp nz, .p1_take_need
    ld a, c : cp e : jp c, .p1_take_chunk
.p1_take_need:
    ld a, e
.p1_take_chunk:
    ld (tmp_take), a
    ld a, (fn_pos) : ld l, a : ld h, 0
    ld de, fn_buf : add hl, de : ex de, hl
    ld hl, (buf_ptr) : ld b, 0 : ld a, (tmp_take) : ld c, a : ldir
    ld a, (fn_pos) : ld d, a : ld a, (tmp_take) : add a, d : ld (fn_pos), a
    ld bc, (chunk_work)
    ld a, (tmp_take) : ld e, a : ld a, c : sub e : ld c, a
    ld a, b : sbc a, 0 : ld b, a : ld (chunk_work), bc
    ld hl, (buf_ptr) : ld a, (tmp_take) : ld e, a : ld d, 0 : add hl, de : ld (buf_ptr), hl
.p1_check:
    ld a, (fn_pos) : cp 2 : ret nz
.p1_done:
    ld a, (fn_buf) : cp 'F' : jp nz, .badFn
    ld a, (fn_buf+1) : cp 'N' : jp nz, .badFn
    ld a, 2 : ld (hdr_phase), a : jp .loop

.phase2:
    ld bc, (chunk_work) : ld a, b : or c : jp z, .loop
    ld hl, (buf_ptr) : ld a, (hl) : ld (name_len), a : inc hl : ld (buf_ptr), hl
    ld bc, (chunk_work) : dec bc : ld (chunk_work), bc
.p2_chk:
    ld a, (name_len) : cp 1 : jp c, .badNameLen
    cp 13 : jp nc, .badNameLen
    xor a : ld (name_pos), a
    ld a, 3 : ld (hdr_phase), a : jp .loop

.phase3:
    ld a, (name_len) : ld e, a : ld a, (name_pos) : ld d, a : ld a, e : sub d : ld e, a : jp z, .p3_done
    ld bc, (chunk_work)
    ld a, b : or a : jp nz, .p3_take_rem
    ld a, c : cp e : jp c, .p3_take_chunk
.p3_take_rem:
    ld a, e
.p3_take_chunk:
    ld (tmp_take), a
    ld a, (name_pos) : ld l, a : ld h, 0
    ld de, fname_buf : add hl, de : ex de, hl
    ld hl, (buf_ptr) : ld b, 0 : ld a, (tmp_take) : ld c, a : ldir
    ld a, (name_pos) : ld d, a : ld a, (tmp_take) : add a, d : ld (name_pos), a
    ld bc, (chunk_work)
    ld a, (tmp_take) : ld e, a : ld a, c : sub e : ld c, a
    ld a, b : sbc a, 0 : ld b, a : ld (chunk_work), bc
    ld hl, (buf_ptr) : ld a, (tmp_take) : ld e, a : ld d, 0 : add hl, de : ld (buf_ptr), hl
.p3_check:
    ld a, (name_pos) : ld b, a : ld a, (name_len) : cp b : ret nz
.p3_done:
    ld a, (name_len) : ld l, a : ld h, 0
    ld de, fname_buf : add hl, de : xor a : ld (hl), a
    ld a, (probe_mode) : or a : jr z, .p3_normal
    call sendAck : jp recv
.p3_normal:
    printMsg msg_ink_white
    ld a, (wait_row) : ld d, a : ld e, 0 : call Display.setPos
    printMsg msg_xfer
    printMsg msg_ink_red
    printMsg msg_filename
    ld hl, fname_buf : call Display.putStr
    printMsg msg_kind_open
    ld a, (sna_kind) : or a : jr nz, .p3_kind128
    printMsg msg_kind48 : jr .p3_kind_end
.p3_kind128:
    printMsg msg_kind128
.p3_kind_end:
    printMsg msg_kind_close
    printMsg msg_ink_white
    call EsxDOS.setFilenameFromWifi
    call EsxDOS.prepareFile : jp c, .fileCreateFail
    ld a, 1 : ld (file_opened), a
    ld a, 24 : ld b, a : ld a, (23689) : ld c, a : ld a, b : sub c
    cp 24 : jr c, .row_ok : xor a
.row_ok:
    ld (bar_row), a : ld d, a : ld e, 0 : call Display.setPos
    ld a, 16 : rst #10 : ld a, 4 : rst #10 : ld a, 144 : rst #10 : ld a, 16 : rst #10 : ld a, 7 : rst #10
    ld a, (bar_row) : ld d, a : ld e, 0 : call Display.setPos
    ld a, 1 : ld (bar_ready), a : ld a, 4 : ld (hdr_phase), a 
    
    ld a, 2
    ld (visual_feedback_enabled), a
    
    jp .loop

.payload:
    ld bc, (chunk_work)
    ld hl, (xfer_rem_hi) : ld a, h : or l : jr nz, .lenReady ; FIX 128K
    ld hl, (xfer_rem_lo) : push hl : or a : sbc hl, bc : pop hl
    jr nc, .lenReady
    ld b, h : ld c, l
.lenReady:
    ld a, b : or c : jr z, .mark_done
    ld hl, (buf_ptr) : push hl : push bc
    call CrcUpdateBuf : pop bc : pop hl
    call EsxDOS.writeChunkPtr : jp c, .fatal
    push bc : call addDoneBC : call progressMaybe : pop bc
    ld hl, (buf_ptr) : add hl, bc : ld (buf_ptr), hl
    call subRemBC
    ld hl, (xfer_rem_lo) : ld a, h : or l : ret nz
    ld hl, (xfer_rem_hi) : ld a, h : or l : ret nz
.mark_done:
    call writeData
    ld bc, 0 : ld (chunk_work), bc : ret

.badFn:
    printMsg msg_badfn : jp Wifi_ProtoAbort
.badNameLen:
    printMsg msg_badnamelen : jp Wifi_ProtoAbort
.fileCreateFail:
    printMsg msg_file_create_fail
    ld hl, EsxDOS.filename : call Display.putStr
    printMsg msg_file_create_fail2
    jp Wifi_ProtoAbort
.fatal:
    jp Wifi_ProtoAbort

writeData:
    ld a, (xfer_done) : or a : ret nz
    ld a, b : or c : ret z
    ld a, 1 : ld (xfer_done), a
    call progressFillEnd : call sendAck : ret

subRemBC:
    ld hl, (xfer_rem_lo) : or a : sbc hl, bc : ld (xfer_rem_lo), hl
    ld hl, (xfer_rem_hi) : ld de, 0 : sbc hl, de : ld (xfer_rem_hi), hl
    ret

CrcUpdateBuf:
    push ix : push bc : pop ix : ld de, (crc_cur)
.byte_loop:
    ld a, ixh : or ixl : jr z, .done
    ld a, (hl) : inc hl : xor d : ld d, a : ld b, 8
.bit_loop:
    bit 7, d : jr z, .no_xor
    sla e : rl d : ld a, e : xor #21 : ld e, a : ld a, d : xor #10 : ld d, a : jr .next_bit
.no_xor:
    sla e : rl d
.next_bit:
    djnz .bit_loop
    dec ix : jr .byte_loop
.done:
    ld (crc_cur), de : pop ix : ret

CrcVerify:
    push hl : push de
    ld hl, (crc_cur) : ld de, (expected_crc) : or a : sbc hl, de
    jr z, .ok
    ld a, 1 : ld (crc_bad), a : pop de : pop hl : scf : ret
.ok:
    xor a : ld (crc_bad), a : pop de : pop hl : or a : ret

validateHeader:
    ld hl, hdr_buf
    ld a, (hl) : cp 'L' : jp nz, .badHdr : inc hl
    ld a, (hl) : cp 'A' : jp nz, .badHdr : inc hl
    ld a, (hl) : cp 'I' : jp nz, .badHdr : inc hl
    ld a, (hl) : cp 'N' : jp nz, .badHdr
    ld a, (hdr_buf+4) : ld l, a : ld a, (hdr_buf+5) : ld h, a : ld (xfer_rem_lo), hl
    ld a, (hdr_buf+6) : ld l, a : ld a, (hdr_buf+7) : ld h, a : ld (xfer_rem_hi), hl
    ld a, (hdr_buf+8) : ld l, a : ld a, (hdr_buf+9) : ld h, a : ld (expected_crc), hl
    ld hl, #FFFF : ld (crc_cur), hl
    xor a : ld (crc_bad), a
    ld hl, (xfer_rem_hi) : ld a, h : or l : jr nz, .notProbe
    ld hl, (xfer_rem_lo) : ld a, h : or l : jr nz, .notProbe
    ld a, 1 : ld (probe_mode), a : ret
.notProbe:
    ld hl, (xfer_rem_hi) : ld a, h : or l : jr nz, .chk128
    ld hl, (xfer_rem_lo) : ld de, #C01B : or a : sbc hl, de : jr z, .ok
    jr .badLen
.chk128:
    ld hl, (xfer_rem_hi) : ld de, #0002 : or a : sbc hl, de : jr nz, .badLen
    ld hl, (xfer_rem_lo) : ld de, #001F : or a : sbc hl, de : jr z, .ok
.badLen:
    printMsg msg_badlen : scf : ret
.badHdr:
    printMsg msg_badhdr : scf : ret
.ok:
    xor a : ld (probe_mode), a
    ld hl, (xfer_rem_hi) : ld a, h : or l : jr nz, .kind128
    xor a : ld (sna_kind), a : ld hl, thr48_tbl : jr .kindSet
.kind128:
    ld a, 1 : ld (sna_kind), a : ld hl, thr128_tbl
.kindSet:
    ld (thr_ptr), hl
    xor a : ld (prog_units), a
    ld hl, 0 : ld (done_lo), hl : ld (done_hi), hl
    ret

addDoneBC:
    ld hl, (done_lo) : add hl, bc : ld (done_lo), hl
    ld hl, (done_hi) : ld de, 0 : adc hl, de : ld (done_hi), hl
    ret

progressMaybe:
    ld a, (bar_ready) : or a : ret z
.loop:
    ld a, (prog_units) : cp 32 : ret nc
    ld a, (prog_units) : add a, a : add a, a : ld e, a : ld d, 0
    ld hl, (thr_ptr) : add hl, de
    ld e, (hl) : inc hl : ld d, (hl) : inc hl : ld c, (hl) : inc hl : ld b, (hl)
    ld hl, (done_hi) : or a : sbc hl, bc : jr c, .ret : jr nz, .advance
    ld hl, (done_lo) : or a : sbc hl, de : jr c, .ret
.advance:
    ld a, (prog_units) : inc a : ld (prog_units), a
    call drawColA : jr .loop
.ret:
    ret

progressFillEnd:
    ld a, (bar_ready) : or a : ret z
.fill:
    ld a, (prog_units) : cp 32 : ret nc
    inc a : ld (prog_units), a
    call drawColA : jr .fill

drawColA:
    ld a, (prog_units) : dec a : ld e, a : ld a, (bar_row) : ld d, a : call Display.setPos
    ld a, 16 : rst #10 : ld a, 4 : rst #10 : ld a, 144 : rst #10 : ld a, 16 : rst #10 : ld a, 7 : rst #10 : ret

sendAck:
    ld a, (socket_id) : ld (ack_cipsend_id), a
    ld hl, ack_cipsend : call espSendZ
    ld bc, 200
.waitPrompt:
    push bc
    call Uart.uartRead : pop bc : jr nc, .dec
    cp '>' : jr z, .sendPayload
    cp 'E' : jr z, .abort
    cp 'L' : jr z, .abort
    cp 'C' : jr z, .abort
    jr .waitPrompt
.dec:
    dec bc : ld a, b : or c : jr nz, .waitPrompt
.abort:
    ret
.sendPayload:
    ld hl, ack_payload : call espSendZ
    ret

ack_cipsend: db "AT+CIPSEND="
ack_cipsend_id: db '0', ",4", 13, 10, 0
ack_payload: db "OK", 13, 10, 0

getMyIp:
    EspCmd "AT+CIFSR"
.loop:
    call Uart.read : cp 'P' : jr z, .infoStart : jr .loop
.infoStart:
    call Uart.read : cp ',' : jr nz, .loop
    call Uart.read : cp '"' : jr nz, .loop
    ld hl, ipAddr
.copyIpLoop:
    push hl : call Uart.read : pop hl : cp '"' : jr z, .finish
    ld (hl), a : inc hl : jr .copyIpLoop
.finish:
    xor a : ld (hl), a : call checkOkErr
    ld hl, ipAddr : ld de, justZeros
.checkZero:
    ld a, (hl) : and a : jr z, .err
    ld b, a : ld a, (de) : cp b : ret nz
    inc hl : inc de : jr .checkZero
.err:
    ld hl, .err_connect : call Display.putStr : jr $
.err_connect: db "Use Network Manager and connect to Wifi", 13, "System halted", 0

espSend:
    ld a, (hl) : push hl, de : call Uart.write : pop de, hl : inc hl : dec e : jr nz, espSend : ret

espSendZ:
    ld a, (hl) : and a : ret z : push hl : call Uart.write : pop hl : inc hl : jr espSendZ

checkOkErr:
    call Uart.read : cp 'O' : jr z, .okStart : cp 'E' : jr z, .errStart
    cp 'F' : jr z, .failStart : jr checkOkErr
.okStart:
    call Uart.read : cp 'K' : jr nz, checkOkErr : call Uart.read : cp 13 : jr nz, checkOkErr
    call .flushToLF : or a : ret
.errStart:
    call Uart.read : cp 'R' : jr nz, checkOkErr : call Uart.read : cp 'R' : jr nz, checkOkErr
    call Uart.read : cp 'O' : jr nz, checkOkErr : call Uart.read : cp 'R' : jr nz, checkOkErr
    call .flushToLF : scf : ret 
.failStart:
    call Uart.read : cp 'A' : jr nz, checkOkErr : call Uart.read : cp 'I' : jr nz, checkOkErr
    call Uart.read : cp 'L' : jr nz, checkOkErr : call .flushToLF : scf : ret
.flushToLF:
    call Uart.read : cp 10 : jr nz, .flushToLF : ret

WaitAnyKey:
    ld bc, 15000
.safety: dec bc : ld a, b : or c : jr nz, .safety
.loop:
    call KeyWaitAllReleased
    call KeyAnyPressed : or a : jr z, .loop
    ret

KeyWaitAllReleased:
    call KeyAnyPressed : or a : jr nz, KeyWaitAllReleased
    ret

KeyAnyPressed:
    push bc : push hl : push de
    ld hl, key_rows : ld d, 8
.row:
    ld a, (hl) : inc hl : ld b, a : ld c, #FE : in a, (c) : and #1F : cp #1F : jr nz, .pressed
    dec d : jr nz, .row
    xor a : jr .done
.pressed:
    ld a, 1
.done:
    pop de : pop hl : pop bc : ret

key_rows: db #FE, #FD, #FB, #F7, #EF, #DF, #BF, #7F

WaitErrorReset:
    ; Bucle continuo: Drenar UART + Chequear CUALQUIER tecla
.loop:
    push bc
    call Uart.uartRead ; Drenar buffer para evitar overrun
    pop bc
    
    call KeyAnyPressed
    or a
    jr nz, .pressed

    jr .loop

.pressed:
    ld bc, 20000 ; Pausa de rebote
.wait:
    dec bc
    ld a, b
    or c
    jr nz, .wait
    ret

Wifi_FlushSilence:
    push af : push bc : push de
    ld de, 30000          ; Límite de seguridad
.flush_loop:
    ld a, d : or e : jr z, .timeout
    dec de
    call Uart.uartRead    ; Lee dato
    jr nc, .check_end     ; Si no hay dato, comprobar si llevamos un rato en silencio
    jr .flush_loop        ; Si hay dato, seguir drenando
.check_end:
    pop de : pop bc : pop af : ret
.timeout:
    pop de : pop bc : pop af : ret
    
Wifi_CloseConn0:
    push hl : push de : push bc : push af
    ld hl, msg_at_close0
    ld e, 15 ; longitud
    call Wifi.espSend
    pop af : pop bc : pop de : pop hl
    ret

msg_at_close0: db "AT+CIPCLOSE=0", 13, 10

Wifi_UiResetToWaiting:
    push af : push bc : push de : push hl
    ld a, (wait_row) : cp 8 : jr nc, .row_ok : ld a, 8
.row_ok:
    ld d, a : ld e, 0
    printMsg msg_ink_white

    ; 1. Sobrescribir "Transfer in progress..." con "Waiting..."
    push de
    call Display.setPos
    ld hl, msg_waiting_local
    call Display.putStr
    pop de

    ; 2. Limpiar SOLO hasta la línea 22 para evitar scroll
    inc d
.clear_loop:
    ld a, d
    cp 23 ; Límite seguro (línea 22 inclusive)
    jr nc, .done
    
    push de
    call Display.setPos
    ld hl, msg_clear32 ; Espacios sin salto de línea
    call Display.putStr
    pop de
    
    inc d
    jr .clear_loop

.done:
    pop hl : pop de : pop bc : pop af : ret

Wifi_ShowResetFeedback:
    printMsg msg_ink_red
    ld hl, msg_resetting_now
    call Display.putStr
    printMsg msg_ink_white
    ret

cleanupAfterDone:
    call Wifi_Finalize : ret

Wifi_Finalize:
    EspCmd "AT+CIPSERVER=0"
    ret

; =============================================================================
; VARIABLES Y BUFFERS
; =============================================================================

hdr_phase: db 0
hdr_pos: db 0
fn_pos: db 0
name_len: db 0
name_pos: db 0
wrote_flag: db 0
file_opened: db 0
xfer_done: db 0
probe_mode: db 0
socket_id: db '0'
visual_feedback_enabled: db 0
bar_ready: db 0
bar_row: db 0
wait_row: db 0
sna_kind: db 0

prog_units: db 0
dec_printed: db 0
tmp_take: db 0
crc_bad: db 0
dec_val_lo: dw 0
dec_val_hi: dw 0
done_lo: dw 0
done_hi: dw 0
expected_crc: dw 0
crc_cur: dw 0
thr_ptr: dw 0
buf_ptr: dw 0
chunk_work: dw 0
xfer_rem_lo: dw 0
xfer_rem_hi: dw 0
data_avail: dw 0
step_acc: db 0 ; RESTAURADO PARA LA BARRA DE PROGRESO

hdr_buf: ds 10
fn_buf: ds 2
fname_buf: ds 13
ipAddr: db "000.000.000.000", 0
justZeros: db "0.0.0.0", 0

new_line_only: db 13, 0
msg_badhdr: db 13, "Invalid LAIN header", 13, 0
msg_badlen: db 13, "Invalid SNA length", 13, 0
msg_ink_red: db 16, 2, 0
msg_ink_green: db 16, 4, 0
msg_ink_white: db 16, 7, 0
msg_xfer: db "Transfer in progress:", "           ", 13, 0
msg_filename:  db "Filename: ", 0
msg_kind_open: db " (", 0
msg_kind48:    db "48K", 0
msg_kind128:   db "128K", 0
msg_kind_close: db ")", 13, 0
msg_badfn:  db 13, "Invalid FN marker", 13, 0
msg_badnamelen: db 13, "Invalid filename length", 13, 0
msg_conn_closed: db 13, "Connection closed", 13, 0
msg_xfer_timeout: db 13, "Transfer interrupted (timeout)", 13, 0
msg_xfer_complete: db 13, "Transfer complete", 13, 0
msg_bytes_recv: db "Bytes received: ", 0
msg_crc_ok: db " (CRC OK)", 0
msg_crc_bad: db " (Bad CRC)", 0
msg_press_key_return: db "Press ANY KEY to reset...", 13, 0
msg_press_key: db "Press a key for loading SNA file", 13, 0
msg_ipd_inconsistent: db 13, "Protocol error (IPD length)", 13, 0
msg_file_create_fail:  db 13, "ERROR: cannot create ", 0
msg_file_create_fail2: db 13, "System halted", 13, 0
msg_deleting: db 13, "Deleting: ", 0
msg_newline: db 13, 0
msg_clear32: db "                                ", 0
msg_waiting_local: db "Waiting for transfer...         ", 13, 0
msg_resetting_now: db "RESETTING...", 13, 0

thr48_tbl:
    dw #0600, #0000, #0C01, #0000, #1202, #0000, #1803, #0000, #1E04, #0000
    dw #2405, #0000, #2A05, #0000, #3006, #0000, #3607, #0000, #3607, #0000
    dw #4209, #0000, #480A, #0000, #4E0B, #0000, #540C, #0000, #5A0D, #0000
    dw #600E, #0000, #660E, #0000, #6C0F, #0000, #7210, #0000, #7811, #0000
    dw #7E12, #0000, #8413, #0000, #8A14, #0000, #9015, #0000, #9616, #0000
    dw #9C17, #0000, #A217, #0000, #A818, #0000, #AE19, #0000, #B41A, #0000
    dw #BA1B, #0000, #C01B, #0000

thr128_tbl:
    dw #1000, #0000, #2001, #0000, #3002, #0000, #4003, #0000, #5004, #0000
    dw #6005, #0000, #7006, #0000, #8007, #0000, #9008, #0000, #A009, #0000
    dw #B00A, #0000, #C00B, #0000, #D00C, #0000, #E00D, #0000, #F00E, #0000
    dw #000F, #0001, #1010, #0001, #2011, #0001, #3012, #0001, #4013, #0001
    dw #5014, #0001, #6015, #0001, #7016, #0001, #8017, #0001, #9018, #0001
    dw #A019, #0001, #B01A, #0001, #C01B, #0001, #D01C, #0001, #E01D, #0001
    dw #F01E, #0001, #001F, #0002

; BUFFER DE DATOS Y STACK DE SEGURIDAD
buffer: ds 2048
stack_bot: ds 128
stack_top: equ $ 

    endmodule

Wifi_Finalize:
    EspCmd "AT+CIPSERVER=0"
    ret