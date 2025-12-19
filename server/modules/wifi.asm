    MACRO EspSend Text
    ld hl, .txtB
    ld e, (.txtE - .txtB)
    call Wifi.espSend
    jr .txtE
.txtB 
    db Text
.txtE 
    ENDM

    MACRO EspCmd Text
    ld hl, .txtB
    ld e, (.txtE - .txtB)
    call Wifi.espSend
    jr .txtE
.txtB 
    db Text
    db 13, 10 
.txtE
    ENDM

    MACRO EspCmdOkErr text
    EspCmd text
    call Wifi.checkOkErr
    ENDM

    module Wifi

; --- Transfer protocol ---
; PC sends (binary, inside +IPD payload):
;   'L''A''I''N' + uint32_le(snapshot_len) + 'F''N' + uint8(name_len) + name + snapshot bytes
; Spectrum validates header and writes exactly snapshot_len bytes to <FILENAME> in current dir,
; prints the provided filename, then runs: snapload <FILENAME> (via EsxDOS.closeAndRun).
; If transfer fails or is interrupted, the incomplete file is deleted.

; =============================================================================
; Smart initialization: reuses existing ESP state when possible
; =============================================================================
init:
    ; Step 1: Try to exit transparent mode (in case ESP was left in it)
    EspSend "+++"
    ld b, 20              ; 400ms (reduced from 1s)
.wait_exit:
    halt
    djnz .wait_exit

    ; Step 2: Probe ESP with "AT" (short timeout)
    call probeESP
    jp c, .need_full_reset

    ; ESP responded! Now check if we have IP
    call checkHasIP
    jp c, .need_full_reset    ; No IP or error → full reset

    ; We have IP. Check if server is already running on port 6144
    call checkServerStatus
    jr c, .start_server       ; Server not running → start it
    
    ; Server already running! Just get IP and we're done
    call getMyIp
    ret

.start_server:
    ; Configure and start server (ESP already has IP)
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
    ; Full reset path (original behavior)
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

.err
    ld hl, .err_msg
    call Display.putStr
    di
    halt
.err_msg db 13, "ESP error! Halted!", 0

; -----------------------------------------------------------------------------
; probeESP: Quick check if ESP responds to AT
; Returns: CF=0 if OK, CF=1 if no response
; -----------------------------------------------------------------------------
probeESP:
    ; Flush any garbage in UART buffer
    call flushUartQuick
    
    EspCmd "AT"
    ; Wait for OK/ERROR with short timeout
    call checkOkErrTimeout
    ret                       ; CF already set by checkOkErrTimeout

; -----------------------------------------------------------------------------
; checkHasIP: Check if ESP has a valid IP (not 0.0.0.0)
; Returns: CF=0 if has IP, CF=1 if no IP
; -----------------------------------------------------------------------------
checkHasIP:
    call flushUartQuick
    EspCmd "AT+CIFSR"
    
    ; Look for STAIP,"<ip>"
.loop:
    call readByteShortTimeout
    jr nc, .no_ip             ; Timeout
    cp 'S'
    jr nz, .check_ok
    call readByteShortTimeout
    jr nc, .no_ip
    cp 'T'
    jr nz, .loop
    call readByteShortTimeout
    jr nc, .no_ip
    cp 'A'
    jr nz, .loop
    call readByteShortTimeout
    jr nc, .no_ip
    cp 'I'
    jr nz, .loop
    call readByteShortTimeout
    jr nc, .no_ip
    cp 'P'
    jr nz, .loop
    ; Found "STAIP", now find the IP between quotes
    call readByteShortTimeout
    jr nc, .no_ip
    cp ','
    jr nz, .loop
    call readByteShortTimeout
    jr nc, .no_ip
    cp '"'
    jr nz, .loop
    
    ; Read first char of IP
    call readByteShortTimeout
    jr nc, .no_ip
    cp '0'
    jr z, .check_zero_ip      ; Might be 0.0.0.0
    ; Non-zero first digit = valid IP
    call flushToOK
    or a                      ; CF=0, has IP
    ret
    
.check_zero_ip:
    ; Read next char - if it's '.', check for 0.0.0.0
    call readByteShortTimeout
    jr nc, .no_ip
    cp '.'
    jr nz, .has_ip            ; Something like "01.x.x.x" is valid
    ; Could be 0.0.0.0 - assume no IP for safety
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
    ; Saw 'O', might be OK without finding STAIP (error case)
.no_ip:
    scf
    ret

; -----------------------------------------------------------------------------
; checkServerStatus: Check if TCP server is running on port 6144
; Uses AT+CIPSTATUS to check server state
; Returns: CF=0 if server running, CF=1 if not running
; -----------------------------------------------------------------------------
checkServerStatus:
    call flushUartQuick
    EspCmd "AT+CIPSTATUS"
    
    ; Response format:
    ; STATUS:<n>    (2=Got IP no conn, 3=Connected, 4=Disconnected, 5=Not connected)
    ; +CIPSTATUS:... (for each connection)
    ; OK
    ;
    ; If server is listening, STATUS is typically 3 even with no active connections
    ; But more reliable: after starting server, CIPMUX=1 is set
    ; We check if we get OK without errors
    
    ; For simplicity: if CIPSTATUS returns OK and STATUS >= 2, assume we can try
    ; to start server. The server start will fail gracefully if already running.
    
    ; Actually, AT+CIPSERVER=1,6144 returns "no change" if already running,
    ; which checkOkErr treats as OK. So we can just always try to start it.
    ; But to save time, let's check if CIPMUX=1 is set.
    
    call flushToOK            ; Just consume the response
    
    ; Check CIPMUX setting
    call flushUartQuick
    EspCmd "AT+CIPMUX?"
    
    ; Response: +CIPMUX:<n> then OK
.mux_loop:
    call readByteShortTimeout
    jr nc, .no_server
    cp ':'
    jr nz, .mux_loop
    call readByteShortTimeout
    jr nc, .no_server
    cp '1'
    jr nz, .no_server         ; CIPMUX=0, server not configured
    
    ; CIPMUX=1, server likely running
    call flushToOK
    or a                      ; CF=0
    ret

.no_server:
    call flushToOK
    scf                       ; CF=1
    ret

; -----------------------------------------------------------------------------
; fullReset: Complete ESP reset (original behavior)
; Returns: CF=0 on success, CF=1 on timeout
; -----------------------------------------------------------------------------
fullReset:
    EspCmd "AT+RST"
    
    ; Wait for "ready" - use long timeout as reset takes time
.wait_ready:
    call Wifi.readByteTimeout
    jr nc, .timeout
    cp 'r'
    jr nz, .wait_ready
    call Wifi.readByteTimeout
    jr nc, .timeout
    cp 'e'
    jr nz, .wait_ready
    call Wifi.readByteTimeout
    jr nc, .timeout
    cp 'a'
    jr nz, .wait_ready
    call Wifi.readByteTimeout
    jr nc, .timeout
    cp 'd'
    jr nz, .wait_ready
    call Wifi.readByteTimeout
    jr nc, .timeout
    cp 'y'
    jr nz, .wait_ready
    
    ; Wait for "GOT IP" (or "WIFI GOT IP")
.wait_gotip:
    call Wifi.readByteTimeout
    jr nc, .timeout
    cp 'G'
    jr nz, .wait_gotip
    call Wifi.readByteTimeout
    jr nc, .timeout
    cp 'O'
    jr nz, .wait_gotip
    call Wifi.readByteTimeout
    jr nc, .timeout
    cp 'T'
    jr nz, .wait_gotip
    call Wifi.readByteTimeout
    jr nc, .timeout
    cp ' '
    jr nz, .wait_gotip
    call Wifi.readByteTimeout
    jr nc, .timeout
    cp 'I'
    jr nz, .wait_gotip
    call Wifi.readByteTimeout
    jr nc, .timeout
    cp 'P'
    jr nz, .wait_gotip
    
    or a                      ; CF=0, success
    ret

.timeout:
    scf
    ret

; -----------------------------------------------------------------------------
; Helper: Read byte with short timeout (for init probing)
; Returns: CF=1 and A=byte on success; CF=0 on timeout
; -----------------------------------------------------------------------------
readByteShortTimeout:
    ld b, 100                 ; Shorter timeout for probing
.loop:
    call Uart.uartRead
    jr c, .got
    djnz .loop
    or a                      ; CF=0, timeout
    ret
.got:
    scf                       ; CF=1, got byte
    ret

; -----------------------------------------------------------------------------
; Helper: Flush UART buffer quickly (discard pending bytes)
; -----------------------------------------------------------------------------
flushUartQuick:
    ld b, 5                   ; Try 5 times
.loop:
    call Uart.uartRead
    jr nc, .done              ; No more data
    djnz .loop
.done:
    ret

; -----------------------------------------------------------------------------
; Helper: Consume bytes until OK or timeout
; -----------------------------------------------------------------------------
flushToOK:
    call readByteShortTimeout
    ret nc                    ; Timeout, done
    cp 'O'
    jr nz, flushToOK
    call readByteShortTimeout
    ret nc
    cp 'K'
    jr nz, flushToOK
    ret

; -----------------------------------------------------------------------------
; checkOkErrTimeout: Like checkOkErr but with timeout
; Returns: CF=0 on OK, CF=1 on ERROR/FAIL/timeout
; -----------------------------------------------------------------------------
checkOkErrTimeout:
    ld c, 0                   ; Retry counter
.loop:
    call readByteShortTimeout
    jr nc, .timeout
    cp 'O'
    jr z, .okStart
    cp 'E'
    jr z, .errStart
    cp 'F'
    jr z, .failStart
    inc c
    ld a, c
    cp 200                    ; Max iterations
    jr c, .loop
.timeout:
    scf
    ret
.okStart:
    call readByteShortTimeout
    jr nc, .timeout
    cp 'K'
    jr nz, .loop
    ; Got "OK"
    or a                      ; CF=0
    ret
.errStart:
.failStart:
    ; Got ERROR or FAIL
    scf
    ret

; Read one byte from UART with bounded retries.
; Returns: CF=1 and A=byte on success; CF=0 on timeout.
readByteTimeout:
    ld b, 200
.rbt_loop
    call Uart.uartRead
    jr c, .rbt_got
    djnz .rbt_loop
    ; Timeout - no visual feedback
    or a
    ret
.rbt_got
    ; Byte received - visual activity feedback: GREEN flash (when enabled)
    push af
    ld a, (visual_feedback_enabled)
    or a
    jr z, .skip_green
    ld a, 4
    out (#fe), a
.skip_green:
    pop af
    scf
    ret


recv:
    ; New transfer session state
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

    ; Enable visual activity feedback (ready for transfer)
    ld a, 1
    ld (visual_feedback_enabled), a

    ; Start waiting for incoming +IPD frames.
    jp .waitIPD

.rxTimeout:
    ; Timeout while receiving payload bytes of an in-progress +IPD chunk.
    jp Wifi_PayloadTimeoutAbort

; (Proto-abort handler moved out of recv scope to avoid breaking local labels.)

.waitIPD:
    ; Strict resync: wait for "+IPD," (ignore other stream noise)
    ; Use a long timeout counter to detect connection loss (~30 seconds)
    ld bc, #A800             ; BC = timeout counter
.waitIPD_loop:
    push bc
    call Wifi.readByteTimeout
    pop bc
    jp c, .waitIPD_gotByte
    ; Timeout - decrement counter (no visual feedback here)
    dec bc
    ld a, b
    or c
    jp nz, .waitIPD_loop
    ; Long timeout expired - if file is open, we lost connection
    ld a, (file_opened)
    or a
    jp nz, Wifi_PayloadTimeoutAbort
    jp .waitIPD              ; No file open, keep waiting

.waitIPD_gotByte:
    ; Got a byte - reset timeout counter
    ld bc, #A800
    
    ; Detect CLOSED notifications opportunistically
    cp 'C'
    jp z, .maybeClosed

    cp '+'
    jp nz, .waitIPD_loop     ; Keep current counter, wait for more

.waitIPD_gotPlus:
    ; Got '+', now look for 'IPD,'
    push bc
    call Wifi.readByteTimeout
    pop bc
    jp nc, .waitIPD_loop
    cp 'I'
    jp nz, .waitIPD_loop

    push bc
    call Wifi.readByteTimeout
    pop bc
    jp nc, .waitIPD_loop
    cp 'P'
    jp nz, .waitIPD_loop

    push bc
    call Wifi.readByteTimeout
    pop bc
    jp nc, .waitIPD_loop
    cp 'D'
    jp nz, .waitIPD_loop

    push bc
    call Wifi.readByteTimeout
    pop bc
    jp nc, .waitIPD_loop
    cp ','
    jp nz, .waitIPD_loop
    ; "+IPD," found

    ; Parse and remember socket id (CIPMUX=1): +IPD,<id>,<len>:
.readSock:
    call Wifi.readByteTimeout
    jp nc, .waitIPD
    cp ','
    jr z, .sockDone
    cp '0'
    jr c, .readSock
    cp '9'+1
    jr nc, .readSock
    ld (socket_id), a
    jr .readSock
.sockDone
    ld hl,0			; count length
.cil1:
    
    push  hl
    call Wifi.readByteTimeout
    jr nc, .lenParseTimeout
    pop hl 
    cp ':'
    jr z, .storeAvail

    ; Validate decimal digit (robustness: reject unexpected characters)
    cp '0'
    jr c, .lenParseInvalid
    cp '9'+1
    jr nc, .lenParseInvalid

    sub '0'
    ld c,l
    ld b,h
    add hl,hl
    add hl,hl
    add hl,bc
    add hl,hl   ; hl = hl*10
    ld c,a
    ld b,0
    add hl,bc
    jr .cil1

.lenParseTimeout
    pop hl                    ; Clean stack before resync
    jp .waitIPD

.lenParseInvalid
    ; Stream not in expected state. Resync to next +IPD.
    jp .waitIPD
.storeAvail
    ld (data_avail), hl
    ; Read +IPD payload in bounded chunks (1024 bytes) to avoid buffer overwrite.
.chunkLoop
    ld hl, (data_avail)
    ld a, h
    or l
    jr nz, .haveData

    ; End of this +IPD payload
    ld a, (xfer_done)
    or a
    jp z, .waitIPD
    call Wifi_Finalize
    call ShowCompleteAndPause
    jp EsxDOS.closeAndRun

.haveData

    ; chunk_len = min(remaining, 8192)
    ld de, #2000
    or a
    sbc hl, de
    jr c, .useRemaining

    ; remaining >= 8192
    ld (data_avail), hl      ; remaining = remaining - 8192
    ld hl, #2000             ; chunk_len = 8192
    jr .readChunk

.useRemaining
    ; remaining < 8192
    ld hl, (data_avail)      ; chunk_len = remaining
    ld de, 0
    ld (data_avail), de      ; remaining = 0

.readChunk
    push hl                  ; save chunk_len for writeChunk
    ld de, buffer
    ; Initialize timeout counter once per chunk
    ld bc, #A800             ; ~30 second timeout per chunk

.loadPacket_loop
    push bc
    push hl
    push de
    call Wifi.readByteTimeout
    jr nc, .loadPacket_timeout
    ; Got byte - store it and continue with same counter
    pop de
    pop hl
    pop bc                   ; restore timeout counter (don't reset)
    ld (de), a
    inc de
    dec hl
    ld a, h
    or l
    jr nz, .loadPacket_loop  ; Continue with preserved BC
    
    ; Chunk complete - discard counter
    pop bc                   ; BC = chunk_len
    call consumeChunk        ; consumes header, writes payload bytes, updates xfer_rem
    jp .chunkLoop

.loadPacket_timeout
    pop de
    pop hl
    pop bc
    ; Decrement timeout counter (no visual feedback here)
    dec bc
    ld a, b
    or c
    jr nz, .loadPacket_loop
    ; Timeout expired - clean up and abort
    pop bc                   ; pop chunk_len from .readChunk
    jp .rxTimeout

.maybeClosed
    ; If the sender closes early, do not snapload a partial file.
    call Wifi.readByteTimeout
    jp nc, .waitIPD
    cp 'L'
    jp nz, .waitIPD
    call Wifi.readByteTimeout
    jp nc, .waitIPD
    cp 'O'
    jp nz, .waitIPD
    call Wifi.readByteTimeout
    jp nc, .waitIPD
    cp 'S'
    jp nz, .waitIPD
    call Wifi.readByteTimeout
    jp nc, .waitIPD
    cp 'E'
    jp nz, .waitIPD
    call Wifi.readByteTimeout
    jp nc, .waitIPD
    cp 'D'
    jp nz, .waitIPD

    ld a, (xfer_done)
    or a
    jr z, .closed_continue
    call Wifi_Finalize
    call ShowCompleteAndPause
    jp EsxDOS.closeAndRun
.closed_continue

    ; Ignore probe connections that connect and close without sending any +IPD payload.
    ld a, (hdr_pos)    
    or a
    jp nz, .closed_abort
    ld a, (hdr_phase)  
    or a
    jp nz, .closed_abort
    ld a, (fn_pos)     
    or a
    jp nz, .closed_abort
    ld a, (name_pos)   
    or a
    jp nz, .closed_abort
    ld a, (file_opened)
    or a
    jp nz, .closed_abort
    jp .waitIPD

.closed_abort:
    ; Disable visual feedback and reset border
    xor a
    ld (visual_feedback_enabled), a
    out (#fe), a
    ; Error beep
    call BeepError
    ; Close and delete incomplete file if it was created.
    printMsg msg_conn_closed
    ld a, (file_opened)
    or a
    jr z, .no_close
    call EsxDOS.closeOnly
    ; Show deletion message after "Connection closed"
    printMsg msg_deleting
    ld hl, EsxDOS.filename
    call Display.putStr
    printMsg msg_newline
    call EsxDOS.deleteFile      ; Delete incomplete file
    xor a
    ld (file_opened), a
.no_close
    call Wifi_FlushSilence
    jp recv

; --- Chunk consumer ---
; In:  BC = bytes in buffer[]
; Out: Updates header state and writes only snapshot bytes to file in current dir.
consumeChunk:
    ; Each +IPD chunk is read into the fixed buffer address. Use a moving
    ; pointer (buf_ptr) to consume bytes without doing memmove/LDIR.
    ld hl, buffer
    ld (buf_ptr), hl
    ld (chunk_work), bc

    ; If transfer already finished, consume and ignore.
    ld a, (xfer_done)
    or a
    ret nz

.loop
    ld bc, (chunk_work)
    ld a, b
    or c
    ret z

    ld a, (hdr_phase)
    or a
    jp z, .phase0
    cp 1
    jp z, .phase1
    cp 2
    jp z, .phase2
    cp 3
    jp z, .phase3
    jp .payload

; Phase 0: read fixed 8-byte header ('LAIN' + uint32_le(snapshot_len))
.phase0
    ld a, (hdr_pos)
    cp 8
    jp nc, .p0_done

    ; need = 8 - hdr_pos
    ld e, a
    ld a, 8
    sub e
    ld e, a

    ; take = min(chunk_work, need)
    ld bc, (chunk_work)
    ld a, b
    or a
    jp nz, .p0_take_need
    ld a, c
    cp e
    jp c, .p0_take_chunk
.p0_take_need
    ld a, e
.p0_take_chunk
    ld (tmp_take), a

    ; Copy take bytes: buffer -> hdr_buf + hdr_pos
    ld a, (hdr_pos)
    ld l, a
    ld h, 0
    ld de, hdr_buf
    add hl, de
    ex de, hl
    ld hl, (buf_ptr)
    ld b, 0
    ld a, (tmp_take)
    ld c, a
    ldir

    ; hdr_pos += take
    ld a, (hdr_pos)
    ld d, a
    ld a, (tmp_take)
    add a, d
    ld (hdr_pos), a

    ; chunk_work -= take
    ld bc, (chunk_work)
    ld a, (tmp_take)
    ld e, a
    ld a, c
    sub e
    ld c, a
    ld a, b
    sbc a, 0
    ld b, a
    ld (chunk_work), bc

    ; Advance buffer pointer by consumed bytes (tmp_take), no memmove.
    ld hl, (buf_ptr)
    ld a, (tmp_take)
    ld e, a
    ld d, 0
    add hl, de
    ld (buf_ptr), hl

.p0_check
    ld a, (hdr_pos)
    cp 8
    ret nz

.p0_done
    ; Validate header and initialize xfer_rem.
    call validateHeader
    jp c, Wifi_ProtoAbort
    ld a, 1
    ld (hdr_phase), a
    jp .loop

; Phase 1: read 'F''N' marker
.phase1
    ld a, (fn_pos)
    cp 2
    jp nc, .p1_done

    ; need = 2 - fn_pos
    ld e, a
    ld a, 2
    sub e
    ld e, a

    ; take = min(chunk_work, need)
    ld bc, (chunk_work)
    ld a, b
    or a
    jp nz, .p1_take_need
    ld a, c
    cp e
    jp c, .p1_take_chunk
.p1_take_need
    ld a, e
.p1_take_chunk
    ld (tmp_take), a

    ; Copy take bytes: buffer -> fn_buf + fn_pos
    ld a, (fn_pos)
    ld l, a
    ld h, 0
    ld de, fn_buf
    add hl, de
    ex de, hl
    ld hl, (buf_ptr)
    ld b, 0
    ld a, (tmp_take)
    ld c, a
    ldir

    ; fn_pos += take
    ld a, (fn_pos)
    ld d, a
    ld a, (tmp_take)
    add a, d
    ld (fn_pos), a

    ; chunk_work -= take
    ld bc, (chunk_work)
    ld a, (tmp_take)
    ld e, a
    ld a, c
    sub e
    ld c, a
    ld a, b
    sbc a, 0
    ld b, a
    ld (chunk_work), bc

    ; Advance buffer pointer by consumed bytes (tmp_take), no memmove.
    ld hl, (buf_ptr)
    ld a, (tmp_take)
    ld e, a
    ld d, 0
    add hl, de
    ld (buf_ptr), hl

.p1_check
    ld a, (fn_pos)
    cp 2
    ret nz

.p1_done
    ld a, (fn_buf)
    cp 'F'
    jp nz, .badFn
    ld a, (fn_buf+1)
    cp 'N'
    jp nz, .badFn

    ld a, 2
    ld (hdr_phase), a
    jp .loop

; Phase 2: read filename length (uint8)
.phase2
    ; need 1 byte
    ld bc, (chunk_work)
    ld a, b
    or c
    jp z, .loop

    ld hl, (buf_ptr)
    ld a, (hl)
    ld (name_len), a
    inc hl
    ld (buf_ptr), hl

    ; chunk_work -= 1
    ld bc, (chunk_work)
    dec bc
    ld (chunk_work), bc

.p2_chk
    ld a, (name_len)
    cp 1
    jp c, .badNameLen
    cp 13
    jp nc, .badNameLen

    xor a
    ld (name_pos), a
    ld a, 3
    ld (hdr_phase), a
    jp .loop

; Phase 3: read filename bytes
.phase3
    ld a, (name_len)
    ld e, a
    ld a, (name_pos)
    ld d, a
    ld a, e
    sub d
    ld e, a              ; E = remaining name bytes
    jp z, .p3_done

    ; take = min(chunk_work, remaining)
    ld bc, (chunk_work)
    ld a, b
    or a
    jp nz, .p3_take_rem
    ld a, c
    cp e
    jp c, .p3_take_chunk
.p3_take_rem
    ld a, e
.p3_take_chunk
    ld (tmp_take), a

    ; Copy take bytes: buffer -> fname_buf + name_pos
    ld a, (name_pos)
    ld l, a
    ld h, 0
    ld de, fname_buf
    add hl, de
    ex de, hl
    ld hl, (buf_ptr)
    ld b, 0
    ld a, (tmp_take)
    ld c, a
    ldir

    ; name_pos += take
    ld a, (name_pos)
    ld d, a
    ld a, (tmp_take)
    add a, d
    ld (name_pos), a

    ; chunk_work -= take
    ld bc, (chunk_work)
    ld a, (tmp_take)
    ld e, a
    ld a, c
    sub e
    ld c, a
    ld a, b
    sbc a, 0
    ld b, a
    ld (chunk_work), bc

    ; Advance buffer pointer by consumed bytes (tmp_take), no memmove.
    ld hl, (buf_ptr)
    ld a, (tmp_take)
    ld e, a
    ld d, 0
    add hl, de
    ld (buf_ptr), hl

.p3_check
    ld a, (name_pos)
    ld b, a
    ld a, (name_len)
    cp b
    ret nz

.p3_done
    ; Null-terminate filename
    ld a, (name_len)
    ld l, a
    ld h, 0
    ld de, fname_buf
    add hl, de
    xor a
    ld (hl), a

    ; Probe mode (len==0): do not create files or draw progress; just ACK and return to wait.
    ld a, (probe_mode)
    or a
    jr z, .p3_normal
    call sendAck
    jp recv
.p3_normal
	    ; Overwrite the "Waiting for transfer..." line with a transfer-status line.
	    ; Printed in white, then continue with the existing FILENAME line (in red).
	    printMsg msg_ink_white
	    ld a, (wait_row)
	    ld d, a
	    ld e, 0
	    call Display.setPos
	    printMsg msg_xfer

    ; Print filename and snapshot kind (single line), then init 1-line progress bar.
    ; Filename line in red to improve visibility.
    printMsg msg_ink_red
    printMsg msg_filename
    ld hl, fname_buf
    call Display.putStr
    printMsg msg_kind_open
    ld a, (sna_kind)
    or a
    jr nz, .p3_kind128
    printMsg msg_kind48
    jr .p3_kind_end
.p3_kind128
    printMsg msg_kind128
.p3_kind_end
    printMsg msg_kind_close

    ; Restore INK white for the rest of the session.
    printMsg msg_ink_white


    ; Build filename and create the destination file now that the name is known.
    call EsxDOS.setFilenameFromWifi
    call EsxDOS.prepareFile
    jp c, .fileCreateFail

    ld a, 1
    ld (file_opened), a



    ; Record bar row (cursor is at start of next line after msg_kind_close).
    ; S_POSN (23689) stores (24 - line). Convert to line 0..23.
    ld a, 24
    ld b, a
    ld a, (23689)
    ; A = (24 - line) => line = 24 - A
    ld c, a
    ld a, b
    sub c
    ; Clamp defensively to 0..23
    cp 24
    jr c, .row_ok
    xor a
.row_ok
    ld (bar_row), a

    ; Immediate visual feedback: draw the first progress segment right away.
    ; This avoids the initial delay caused by threshold-based updates (first column ~= total/32).
    ld d, a
    ld e, 0
    call Display.setPos
    ld a, 16                   ; INK
    rst #10
    ld a, 4                    ; green
    rst #10
    ld a, 144                  ; UDG 'A'
    rst #10
    ld a, 16                   ; INK
    rst #10
    ld a, 7                    ; white
    rst #10
    ; Restore cursor at the start of the bar line.
    ld a, (bar_row)
    ld d, a
    ld e, 0
    call Display.setPos
    ; Progress bar is drawn incrementally during payload reception.
    ; Do not print a 32-char template here (it can delay the receiver and overflow ESP buffers).
    ld a, 1
    ld (bar_ready), a
    ld a, 4
    ld (hdr_phase), a
    jp .loop

; Payload: write snapshot bytes
.payload
    ld bc, (chunk_work)
    ; Sanity: during payload phase, never accept more bytes than remaining payload.
    ; This prevents desynchronization if the sender/ESP reports an inconsistent +IPD length.
    ld hl, (xfer_rem_hi)
    ld a, h
    or l
    jr nz, .payload_ok_len

    ld hl, (xfer_rem_lo)
    or a
    sbc hl, bc
    jr nc, .payload_ok_len
    printMsg msg_ipd_inconsistent
    jp Wifi_ProtoAbort
.payload_ok_len
    call writeData
    ; all bytes in this chunk were either written or ignored
    ld bc, 0
    ld (chunk_work), bc
    ret

.badFn
    printMsg msg_badfn
    jp Wifi_ProtoAbort
.badNameLen
    printMsg msg_badnamelen
    jp Wifi_ProtoAbort

.fileCreateFail
    printMsg msg_file_create_fail
    ld hl, EsxDOS.filename
    call Display.putStr
    printMsg msg_file_create_fail2
    di
    halt



; --- Write up to xfer_rem bytes from buffer to file ---
; In:  BC = bytes available in buffer
; Uses: xfer_rem_lo/hi as remaining payload counter.
writeData:
    ld a, (xfer_done)
    or a
    ret nz

    ld a, b
    or c
    ret z

    ; write_len = min(BC, xfer_rem)
    ld hl, (xfer_rem_hi)
    ld a, h
    or l
    jr nz, .lenReady

    ld hl, (xfer_rem_lo)
    push hl
    or a
    sbc hl, bc
    pop hl
    jr nc, .lenReady
    ld b, h
    ld c, l
.lenReady

    ld a, b
    or c
    jr z, .markDone

    ld hl, (buf_ptr)
    call EsxDOS.writeChunkPtr
    jp c, .fatal
    ; Update progress bar based on bytes written.
    push bc
    call addDoneBC
    call progressMaybe
    pop bc
    ; advance buffer pointer by bytes written
    ld hl, (buf_ptr)
    add hl, bc
    ld (buf_ptr), hl
    call subRemBC

    ; xfer_rem == 0 ?
    ld hl, (xfer_rem_lo)
    ld a, h
    or l
    ret nz
    ld hl, (xfer_rem_hi)
    ld a, h
    or l
    ret nz
.markDone
    ld a, 1
    ld (xfer_done), a
    call progressFillEnd
    ; Send application-level ACK to the PC *before* the TCP connection is closed.
    ; Best-effort and bounded (see sendAck), so it will not stall reception.
    call sendAck
    ret
.fatal
    ; EsxDOS.writeChunk already printed an error.
    di
    halt


; --- 32-bit subtract: xfer_rem -= BC ---
subRemBC:
    ld hl, (xfer_rem_lo)
    or a
    sbc hl, bc
    ld (xfer_rem_lo), hl
    ld hl, (xfer_rem_hi)
    ld de, 0
    sbc hl, de
    ld (xfer_rem_hi), hl
    ret


; --- Validate 8-byte LAIN header and initialize xfer_rem ---
; hdr_buf[0..3] = 'L''A''I''N'
; hdr_buf[4..7] = uint32 little-endian payload length
validateHeader:
    ld hl, hdr_buf
    ld a, (hl)
    cp 'L'
    jr nz, .badHdr
    inc hl
    ld a, (hl)
    cp 'A'
    jr nz, .badHdr
    inc hl
    ld a, (hl)
    cp 'I'
    jr nz, .badHdr
    inc hl
    ld a, (hl)
    cp 'N'
    jr nz, .badHdr

    ; Load payload length into xfer_rem_lo/hi
    ld a, (hdr_buf+4)
    ld l, a
    ld a, (hdr_buf+5)
    ld h, a
    ld (xfer_rem_lo), hl
    ld a, (hdr_buf+6)
    ld l, a
    ld a, (hdr_buf+7)
    ld h, a
    ld (xfer_rem_hi), hl
    ; Probe handshake: allow len==0 (used by PC to confirm .lainzx is running)
    ld hl, (xfer_rem_hi)
    ld a, h
    or l
    jr nz, .notProbe
    ld hl, (xfer_rem_lo)
    ld a, h
    or l
    jr nz, .notProbe
    ld a, 1
    ld (probe_mode), a
    ret
.notProbe


    ; Validate len: 48K (0x0000C01B) or 128K (0x0002001F)
    ld hl, (xfer_rem_hi)
    ld a, h
    or l
    jr nz, .chk128
    ld hl, (xfer_rem_lo)
    ld de, #C01B
    or a
    sbc hl, de
    jr z, .ok
    jr .badLen
.chk128
    ld hl, (xfer_rem_hi)
    ld de, #0002
    or a
    sbc hl, de
    jr nz, .badLen
    ld hl, (xfer_rem_lo)
    ld de, #001F
    or a
    sbc hl, de
    jr z, .ok
.badLen
    printMsg msg_badlen
    scf
    ret
.badHdr
    printMsg msg_badhdr
    scf
    ret
.ok
    xor a
    ld (probe_mode), a
    ; Initialize progress bar scaling using precomputed per-column thresholds.
    ; Also store snapshot kind for the combined "FILENAME" line.
    ld hl, (xfer_rem_hi)
    ld a, h
    or l
    jr nz, .kind128

    xor a
    ld (sna_kind), a           ; 0 = 48K
    ld hl, thr48_tbl
    jr .kindSet

.kind128
    ld a, 1
    ld (sna_kind), a           ; 1 = 128K
    ld hl, thr128_tbl

.kindSet
    ld (thr_ptr), hl           ; pointer to 32x 32-bit thresholds (bytes_done)
    xor a
    ld (prog_units), a         ; 0..32 columns filled

    ld hl, 0
    ld (done_lo), hl
    ld (done_hi), hl
    ret

; --- Progress bar (1 line, full width, file-size independent) ---
; 32 columns. Draws one UDG segment per column when thresholds are crossed.
; Uses UDG 'A' (CHR$144) as a thin "battery" bar element.

; done += BC (32-bit)
addDoneBC:
    ld hl, (done_lo)
    add hl, bc
    ld (done_lo), hl
    ld hl, (done_hi)
    ld de, 0
    adc hl, de
    ld (done_hi), hl
    ret


; Advance progress as far as thresholds allow.
progressMaybe:
    ld a, (bar_ready)
    or a
    ret z

.loop
    ld a, (prog_units)
    cp 32
    ret nc

    ; Load next 32-bit threshold from table: thr_ptr + prog_units*4
    ld a, (prog_units)
    add a, a
    add a, a
    ld e, a
    ld d, 0
    ld hl, (thr_ptr)
    add hl, de

    ; DE = threshold_lo, BC = threshold_hi
    ld e, (hl)
    inc hl
    ld d, (hl)
    inc hl
    ld c, (hl)
    inc hl
    ld b, (hl)

    ; if done < threshold => stop
    ld hl, (done_hi)
    or a
    sbc hl, bc
    jr c, .ret
    jr nz, .advance
    ld hl, (done_lo)
    or a
    sbc hl, de
    jr c, .ret

.advance
    ld a, (prog_units)
    inc a
    ld (prog_units), a
    call drawColA
    jr .loop

.ret
    ret


; Force-fill the bar (used at end of transfer).
progressFillEnd:
    ld a, (bar_ready)
    or a
    ret z
.fill
    ld a, (prog_units)
    cp 32
    ret nc
    inc a
    ld (prog_units), a
    call drawColA
    jr .fill


; In: prog_units = 1..32
drawColA:
    ld a, (prog_units)
    dec a                      ; 0..31
    ld e, a                    ; E = col
    ld a, (bar_row)
    ld d, a
    call Display.setPos
    ; Print the bar segment in green, without affecting subsequent text.
    ld a, 16                   ; INK
    rst #10
    ld a, 4                    ; green
    rst #10
    ld a, 144                  ; UDG 'A'
    rst #10
    ld a, 16                   ; INK
    rst #10
    ld a, 7                    ; white
    rst #10
    ret




; --- Send application-level ACK to the PC ---
; Best-effort: sends "OK" via AT+CIPSEND=<socket_id>,4
; Must never block the main flow if the connection is already closing.
sendAck:
    ; Patch socket id digit in the CIPSEND command
    ld a, (socket_id)
    ld (ack_cipsend_id), a

    ; AT+CIPSEND=<id>,4

    ld hl, ack_cipsend
    call espSendZ

    ; Wait for '>' prompt with a bounded timeout (using Uart.uartRead)
    ld bc, 200
.waitPrompt
    push bc
    call Uart.uartRead
    pop bc
    jr nc, .dec
    cp '>'
    jr z, .sendPayload
    ; Abort quickly on typical failure indications
    cp 'E'
    jr z, .abort        ; ERROR
    cp 'L'
    jr z, .abort        ; link is not valid
    cp 'C'
    jr z, .abort        ; CLOSED
    jr .waitPrompt
.dec
    dec bc
    ld a, b
    or c
    jr nz, .waitPrompt
.abort
    ret

.sendPayload
    ld hl, ack_payload
    call espSendZ
    ret

ack_cipsend:
    db "AT+CIPSEND="
ack_cipsend_id:
    db '0'
    db ",4", 13, 10, 0
ack_payload:
    db "OK", 13, 10, 0


getMyIp:
    EspCmd "AT+CIFSR"
.loop
    call Uart.read
    cp 'P'
    jr z, .infoStart
    jr .loop
.infoStart
    call Uart.read
    cp ','
    jr nz, .loop
    call Uart.read
    cp '"'
    jr nz, .loop
    ld hl, ipAddr
.copyIpLoop
    push hl
    call Uart.read
    pop hl
    cp '"'
    jr z, .finish
    ld (hl), a
    inc hl
    jr .copyIpLoop
.finish
    xor a
    ld (hl), a
    call checkOkErr

    ld hl, ipAddr
    ld de, justZeros
.checkZero    
    ld a, (hl)
    and a
    jr z, .err
    ld b, a
    ld a, (de)
    cp b
    ret nz
    inc hl
    inc de
    jr .checkZero
.err
    ld hl, .err_connect
    call Display.putStr
    jr $
.err_connect db "Use Network Manager and connect to Wifi", 13, "System halted", 0

ipAddr db "000.000.000.000", 0
justZeros db "0.0.0.0", 0

; Send buffer to UART
; HL - buff
; E - count
espSend:
    ld a, (hl) 
    push hl, de
    call Uart.write
    pop de, hl
    inc hl 
    dec e
    jr nz, espSend
    ret

espSendZ:
    ld a, (hl)
    and a
    ret z
    push hl
    call Uart.write
    pop hl
    inc hl
    jr espSendZ

checkOkErr:
    call Uart.read
    cp 'O'
    jr z, .okStart ; OK
    cp 'E'
    jr z, .errStart ; ERROR
    cp 'F'
    jr z, .failStart ; FAIL
    jr checkOkErr
.okStart
    call Uart.read
    cp 'K'
    jr nz, checkOkErr
    call Uart.read
    cp 13 
    jr nz, checkOkErr
    call .flushToLF
    or a
    ret
.errStart
    call Uart.read
    cp 'R'
    jr nz, checkOkErr
    call Uart.read
    cp 'R'
    jr nz, checkOkErr
    call Uart.read
    cp 'O'
    jr nz, checkOkErr
    call Uart.read
    cp 'R'
    jr nz, checkOkErr
    call .flushToLF
    scf 
    ret 
.failStart
    call Uart.read
    cp 'A'
    jr nz, checkOkErr
    call Uart.read
    cp 'I'
    jr nz, checkOkErr
    call Uart.read
    cp 'L'
    jr nz, checkOkErr
    call .flushToLF
    scf
    ret
.flushToLF
    call Uart.read
    cp 10
    jr nz, .flushToLF
    ret


; --- Completion UX ---
; Show final status, bytes received, and wait for a key press before snapload.
ShowCompleteAndPause:
    ; Success beep (high pitch, short)
    call BeepSuccess
    printMsg msg_ink_green
    printMsg msg_xfer_complete
    printMsg msg_bytes_recv
    call PrintDoneBytes
    printMsg new_line_only
    printMsg msg_press_key
    call WaitAnyKey
    printMsg new_line_only
    printMsg msg_ink_white
    ret

; Success beep - two short high-pitched tones
BeepSuccess:
    ld hl, #0100       ; Duration
    ld de, #0030       ; Pitch (high)
    call BeepTone
    ld hl, #0080       ; Short pause
.pause1:
    dec hl
    ld a, h
    or l
    jr nz, .pause1
    ld hl, #0100       ; Duration
    ld de, #0020       ; Pitch (higher)
    call BeepTone
    ret

; Error beep - low pitch, longer
BeepError:
    ld hl, #0300       ; Duration (longer)
    ld de, #0100       ; Pitch (low)
    call BeepTone
    ret

; Generic beep: HL=duration, DE=pitch
BeepTone:
    push bc
    di
.beep_loop:
    xor a
    out (#fe), a
    ld b, e
.delay1:
    djnz .delay1
    ld a, #10
    out (#fe), a
    ld b, e
.delay2:
    djnz .delay2
    dec hl
    ld a, h
    or l
    jr nz, .beep_loop
    ei
    pop bc
    ret

; Print 32-bit done counter (done_hi:done_lo) in decimal.
PrintDoneBytes:
    ld hl, (done_lo)
    ld de, (done_hi)
    call PrintU32Dec
    ret

; Print unsigned 32-bit integer in DE:HL (DE=high16, HL=low16) as decimal.
; Assumes values in this program stay < 1,000,000 (true for 48K/128K payloads).
PrintU32Dec:
    ld (dec_val_lo), hl
    ld (dec_val_hi), de
    xor a
    ld (dec_printed), a

    ; 100000 (0x000186A0)
    ld de, #86A0
    ld bc, #0001
    call DigitSubPrint

    ; 10000
    ld de, #2710
    ld bc, #0000
    call DigitSubPrint

    ; 1000
    ld de, #03E8
    ld bc, #0000
    call DigitSubPrint

    ; 100
    ld de, #0064
    ld bc, #0000
    call DigitSubPrint

    ; 10
    ld de, #000A
    ld bc, #0000
    call DigitSubPrint

    ; 1 (always print at least one digit)
    ld de, #0001
    ld bc, #0000
    call DigitSubPrintLast
    ret

; One decimal digit by repeated subtraction:
; digit = value / divisor (0..9), value := value % divisor
; Inputs: divisor_lo=DE, divisor_hi=BC
DigitSubPrint:
    xor a                      ; digit
.dsp_loop:
    ; if value < divisor => stop
    ld hl, (dec_val_hi)
    or a
    sbc hl, bc
    jr c, .dsp_done
    jr nz, .dsp_ge
    ld hl, (dec_val_lo)
    or a
    sbc hl, de
    jr c, .dsp_done
.dsp_ge:
    ; value -= divisor
    ld hl, (dec_val_lo)
    or a
    sbc hl, de
    ld (dec_val_lo), hl
    ld hl, (dec_val_hi)
    sbc hl, bc
    ld (dec_val_hi), hl
    inc a
    jr .dsp_loop

.dsp_done:
    ; Print digit only if already printed or digit!=0
    ld d, a
    ld a, (dec_printed)
    or a
    jr nz, .dsp_print
    ld a, d
    or a
    ret z
.dsp_print:
    ld a, 1
    ld (dec_printed), a
    ld a, d
    add a, '0'
    rst #10
    ret

DigitSubPrintLast:
    call DigitSubPrint
    ; If nothing printed yet, DigitSubPrint returned early (digit==0). Force '0'.
    ld a, (dec_printed)
    or a
    ret nz
    ld a, '0'
    rst #10
    ld a, 1
    ld (dec_printed), a
    ret

; Wait until any key is pressed.
; IMPORTANT: avoid OUT (#FE),A here because that also drives the BORDER bits.
; We scan rows by placing the row mask on the high byte of the port address
; (B) and reading from port #FE via IN A,(C).
WaitAnyKey:
.wk_scan:
    ld hl, key_rows
    ld e, 8
.wk_row:
    ld b, (hl)          ; keyboard row mask (high byte of port)
    inc hl
    ld c, #FE
    in a, (c)
    and #1F
    cp #1F
    jr nz, .wk_pressed
    dec e
    jr nz, .wk_row
    jr .wk_scan
.wk_pressed:
    ret

key_rows:
    db #FE, #FD, #FB, #F7, #EF, #DF, #BF, #7F

dec_val_lo: dw 0
dec_val_hi: dw 0
dec_printed: db 0

new_line_only db 13, 0

; --- Messages ---
msg_badhdr db 13, "Invalid LAIN header", 13, 0
msg_badlen db 13, "Invalid SNA length", 13, 0
msg_ink_red db 16, 2, 0
msg_ink_green db 16, 4, 0
msg_ink_white db 16, 7, 0
; Transfer status line (printed in white, overwrites "Waiting for transfer...")
; Pad with spaces so any previous longer text is fully cleared.
msg_xfer db "Transfer in progress:", "           ", 13, 0
msg_filename  db "FILENAME: ", 0
msg_kind_open db " (", 0
msg_kind48    db "48K", 0
msg_kind128   db "128K", 0
msg_kind_close db ")", 13, 0
msg_badfn  db 13, "Invalid FN marker", 13, 0
msg_badnamelen db 13, "Invalid filename length", 13, 0
msg_conn_closed db 13, "Connection closed", 13, 0
msg_xfer_timeout db 13, "Transfer interrupted (timeout)", 13, 0
msg_xfer_complete db 13, "Transfer complete", 13, 0
msg_bytes_recv db "Bytes received: ", 0
msg_press_key db "Press a key for loading SNA file", 13, 0
msg_ipd_inconsistent db 13, "Protocol error (IPD length)", 13, 0

msg_file_create_fail  db 13, "ERROR: cannot create ", 0
msg_file_create_fail2 db 13, "System halted", 13, 0
msg_deleting db 13, "Deleting: ", 0
msg_newline db 13, 0


; Flush any residual bytes left in the UART after a connection is closed/cancelled.
; This prevents leftover "+IPD..." fragments from being re-parsed as a new LAIN header.
; Waits for a short "silence" (N consecutive uartRead timeouts).
Wifi_FlushSilence:
    push af
    push bc
    push de
    push hl
    ld b, 3              ; number of consecutive timeouts required
.flush_loop:
    call Uart.uartRead   ; C=1 if byte received, C=0 on timeout
    jr c, .got_byte
    djnz .flush_loop
    pop hl
    pop de
    pop bc
    pop af
    ret
.got_byte:
    ld b, 3
    jr .flush_loop

; --- Transfer state ---
hdr_phase db 0            ; 0..4 (0=LAIN+len,1=FN,2=len,3=name,4=payload)
hdr_pos db 0              ; 0..8
fn_pos db 0               ; 0..2
name_len db 0             ; 1..12
name_pos db 0             ; 0..name_len
wrote_flag db 0           ; set when at least one payload write happened in a chunk
file_opened db 0          ; set after EsxDOS.prepareFile succeeds (file handle valid)
xfer_done db 0            ; 0/1
probe_mode db 0          ; 1 when payload_len==0 probe handshake (no file)
socket_id db '0'        ; ASCII socket id ('0'..'4')
visual_feedback_enabled db 0  ; 0/1, enable border color feedback for activity
bar_ready db 0            ; 0/1, progress bar ready on screen
bar_row db 0              ; screen row where the bar is drawn
wait_row db 0             ; screen row where "Waiting for transfer..." is printed
sna_kind db 0             ; 0=48K, 1=128K
prog_units db 0           ; 0..32 (one per column)
step_acc db 0            ; accumulator for progress (unused, kept for init)
done_lo dw 0              ; bytes written (low 16)
done_hi dw 0              ; bytes written (high 16)
thr_ptr dw 0              ; pointer to threshold table
buf_ptr dw 0              ; current read pointer (set by consumeChunk)
tmp_take db 0             ; bytes consumed from current chunk for header
chunk_work dw 0           ; working chunk length
xfer_rem_lo dw 0          ; remaining payload bytes (low 16)
xfer_rem_hi dw 0          ; remaining payload bytes (high 16)
hdr_buf ds 8              ; 'LAIN' + uint32_le(len)
fn_buf ds 2               ; 'F''N'
fname_buf ds 13           ; up to 12 chars + NUL

; --- Progress threshold tables ---
; Each entry is a 32-bit little-endian value (low word, high word) representing
; the minimum bytes_written at which to draw the next column. 32 entries.
thr48_tbl:
    dw #0600, #0000
    dw #0C01, #0000
    dw #1202, #0000
    dw #1803, #0000
    dw #1E04, #0000
    dw #2405, #0000
    dw #2A05, #0000
    dw #3006, #0000
    dw #3607, #0000
    dw #3C08, #0000
    dw #4209, #0000
    dw #480A, #0000
    dw #4E0B, #0000
    dw #540C, #0000
    dw #5A0D, #0000
    dw #600E, #0000
    dw #660E, #0000
    dw #6C0F, #0000
    dw #7210, #0000
    dw #7811, #0000
    dw #7E12, #0000
    dw #8413, #0000
    dw #8A14, #0000
    dw #9015, #0000
    dw #9616, #0000
    dw #9C17, #0000
    dw #A217, #0000
    dw #A818, #0000
    dw #AE19, #0000
    dw #B41A, #0000
    dw #BA1B, #0000
    dw #C01B, #0000

thr128_tbl:
    dw #1000, #0000
    dw #2001, #0000
    dw #3002, #0000
    dw #4003, #0000
    dw #5004, #0000
    dw #6005, #0000
    dw #7006, #0000
    dw #8007, #0000
    dw #9008, #0000
    dw #A009, #0000
    dw #B00A, #0000
    dw #C00B, #0000
    dw #D00C, #0000
    dw #E00D, #0000
    dw #F00E, #0000
    dw #000F, #0001
    dw #1010, #0001
    dw #2011, #0001
    dw #3012, #0001
    dw #4013, #0001
    dw #5014, #0001
    dw #6015, #0001
    dw #7016, #0001
    dw #8017, #0001
    dw #9018, #0001
    dw #A019, #0001
    dw #B01A, #0001
    dw #C01B, #0001
    dw #D01C, #0001
    dw #E01D, #0001
    dw #F01E, #0001
    dw #001F, #0002

data_avail dw 0

; --- Cleanup: stop TCP server and reset ESP (best effort) ---
; Used to avoid leaving the listening port open on the ESP after the dot-command ends.
cleanupAfterDone:
    ; Stop server (does not block if already stopped)
    EspCmd "AT+CIPSERVER=0"
    ; Reset ESP to clear any lingering state / open port
    EspCmd "AT+RST"
    ret


; --- Recoverable protocol abort ---
; Closes any open file, flushes RX noise, resets minimal state, and returns to recv.
; IMPORTANT: Resets SP to prevent stack overflow after multiple consecutive errors.
Wifi_ProtoAbort:
    ; Reset stack pointer to prevent accumulation from repeated errors
    ld sp, stack_top
    
    ; Disable visual feedback and reset border
    xor a
    ld (visual_feedback_enabled), a
    out (#fe), a
    ; Error beep
    call BeepError
    ld a, (file_opened)
    or a
    jr z, .no_close
    call EsxDOS.closeOnly
    call EsxDOS.deleteFile      ; Delete incomplete file
    xor a
    ld (file_opened), a
.no_close:
    call Wifi_FlushSilence
    xor a
    ld (hdr_phase), a
    ld (probe_mode), a
    ld hl, 0
    ld (buf_ptr), hl
    ld (chunk_work), hl
    jp recv

; --- Payload timeout abort ---
; Invoked when a timeout occurs while reading payload bytes (in-progress transfer).
; Closes any open file, deletes it, flushes RX noise, resets transfer state, and returns to recv.
; IMPORTANT: Resets SP to prevent stack overflow after multiple consecutive errors.
Wifi_PayloadTimeoutAbort:
    ; Reset stack pointer to prevent accumulation from repeated errors
    ld sp, stack_top
    
    ; Disable visual feedback and reset border
    xor a
    ld (visual_feedback_enabled), a
    out (#fe), a
    ; Error beep
    call BeepError
    printMsg msg_xfer_timeout
    ld a, (file_opened)
    or a
    jr z, .no_close
    call EsxDOS.closeOnly
    ; Show deletion message after timeout message
    printMsg msg_deleting
    ld hl, EsxDOS.filename
    call Display.putStr
    printMsg msg_newline
    call EsxDOS.deleteFile      ; Delete incomplete file
    xor a
    ld (file_opened), a
.no_close:
    call Wifi_FlushSilence
    xor a
    ld (xfer_done), a
    ld (hdr_phase), a
    ld hl, 0
    ld (xfer_rem_lo), hl
    ld (xfer_rem_hi), hl
    ld (buf_ptr), hl
    ld (chunk_work), hl
    jp recv


    endmodule


; --- Finalize WiFi server ---
Wifi_Finalize:
    ; Disable visual feedback before cleanup
    xor a
    ld (Wifi.visual_feedback_enabled), a
    out (#fe), a                ; Reset border to black
    EspCmd "AT+CIPSERVER=0"
    ret