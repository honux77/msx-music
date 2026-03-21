; -----------------------------------------------------------------------------
; MSX-DOS PSG Player (.COM)
; -----------------------------------------------------------------------------
; Usage:
;   PLAYER TITLE.MPS
;
; File format (MPS):
;   Header 16 bytes:
;     0..3  : "MPSG"
;     4..5  : stream length (LE)
;     6..7  : loop offset in stream (LE, optional)
;     8..15 : reserved
;   Stream:
;     00-0D vv : PSG register write
;     80-FD    : wait 1-126 frames
;     FD       : loop marker
;     FE       : end
;     FF ll hh : extended wait (16-bit frames)
; -----------------------------------------------------------------------------

        ORG     0100h

BDOS:           equ     0x0005

FN_TERM:        equ     0x00
FN_PRINT:       equ     0x09
FN_KBHIT:       equ     0x0B                    ; console status (0xFF=key ready)
FN_CONIN:       equ     0x08                    ; console input (no echo)
FN_OPEN:        equ     0x0F
FN_CLOSE:       equ     0x10
FN_READ_SEQ:    equ     0x14
FN_SET_DMA:     equ     0x1A

FCB_DEFAULT:    equ     0x005C

PSG_ADDR_PORT:  equ     0xA0
PSG_DATA_PORT:  equ     0xA1
JIFFY:          equ     0xFC9E

LOAD_ADDR:      equ     0x8000
MAX_LEN:        equ     0x7FF0                  ; keep below ~0xFFFF

start:
        ld      de, FCB_DEFAULT
        ld      c, FN_OPEN
        call    BDOS
        or      a
        jp      nz, file_open_error

        ld      hl, LOAD_ADDR
        ld      (load_ptr), hl

read_loop:
        ld      de, (load_ptr)
        ld      c, FN_SET_DMA
        call    BDOS

        ld      de, FCB_DEFAULT
        ld      c, FN_READ_SEQ
        call    BDOS
        or      a
        jr      nz, read_done

        ld      hl, (load_ptr)
        ld      de, 128
        add     hl, de
        ld      (load_ptr), hl

        ld      de, LOAD_ADDR + MAX_LEN
        xor     a
        sbc     hl, de
        jr      c, read_loop

        ld      de, msg_too_big
        call    print_msg
        jp      exit_fail

read_done:
        ; read_ptr points to first free byte, compute size = read_ptr - LOAD_ADDR
        ld      hl, (load_ptr)
        ld      de, LOAD_ADDR
        or      a
        sbc     hl, de
        ld      (file_size), hl

        ld      de, FCB_DEFAULT
        ld      c, FN_CLOSE
        call    BDOS

        ; basic header check: "MPSG"
        ld      hl, LOAD_ADDR
        ld      a, (hl)
        cp      'M'
        jr      nz, bad_format
        inc     hl
        ld      a, (hl)
        cp      'P'
        jr      nz, bad_format
        inc     hl
        ld      a, (hl)
        cp      'S'
        jr      nz, bad_format
        inc     hl
        ld      a, (hl)
        cp      'G'
        jr      nz, bad_format

        ; stream ptr = LOAD_ADDR + 16
        ld      hl, LOAD_ADDR + 16
        ld      (data_ptr), hl
        xor     a
        ld      (loop_set), a

        ; Initialize PSG before playback
        call    init_psg

main_loop:
        call    play_frame
        jr      c, done
        jr      main_loop

done:
        call    silence_psg
        ld      de, msg_done
        call    print_msg
        jp      exit_ok

bad_format:
        ld      de, msg_badfmt
        call    print_msg
        jp      exit_fail

file_open_error:
        call    print_banner
        ld      de, msg_openerr
        call    print_msg
        jp      exit_fail

exit_ok:
        ld      c, FN_TERM
        call    BDOS

exit_fail:
        call    silence_psg
        ld      c, FN_TERM
        call    BDOS

; carry set on end
play_frame:
.next_cmd:
        ld      hl, (data_ptr)
        ld      a, (hl)
        inc     hl
        ld      (data_ptr), hl

        cp      0FEh
        jr      z, .song_end
        cp      0FDh
        jr      z, .set_loop
        cp      0FFh
        jr      z, .wait_ext

        cp      80h
        jr      nc, .wait_short

        ; register write: A=reg(0..0Dh), next byte=value
        ld      e, a
        ld      hl, (data_ptr)
        ld      d, (hl)
        inc     hl
        ld      (data_ptr), hl
        ; R7 (mixer): keep lower 6 bits, force IOB=output (bit7=1)
        ld      a, e
        cp      7
        jr      nz, .psg_write
        ld      a, d
        and     3Fh
        or      80h
        ld      d, a
.psg_write:
        ld      a, e
        di
        out     (PSG_ADDR_PORT), a
        ld      a, d
        ei
        out     (PSG_DATA_PORT), a
        jr      .next_cmd

.wait_short:
        sub     7Fh                            ; 80h->1 frame ... FDh->126
        call    wait_frames_a
        ret                                    ; propagate carry (key stop)

.wait_ext:
        ld      hl, (data_ptr)
        ld      e, (hl)
        inc     hl
        ld      d, (hl)
        inc     hl
        ld      (data_ptr), hl
        call    wait_frames_de
        ret                                    ; propagate carry (key stop)

.set_loop:
        ld      a, (loop_set)
        or      a
        jr      nz, .next_cmd
        ld      hl, (data_ptr)
        ld      (loop_ptr), hl
        ld      a, 1
        ld      (loop_set), a
        jr      .next_cmd

.song_end:
        ld      a, (loop_set)
        or      a
        jr      z, .end
        ld      hl, (loop_ptr)
        ld      (data_ptr), hl
        jr      .next_cmd

.end:
        scf
        ret

wait_frames_a:
        ld      e, a
        ld      d, 0
        jr      wait_frames_de

wait_frames_de:
        ld      a, d
        or      e
        ret     z                              ; done, no carry

.wait_loop:
        ld      hl, JIFFY
        ld      a, (hl)
.wait_change:
        ld      hl, JIFFY
        cp      (hl)
        jr      z, .wait_change

        ; check for keypress each frame
        ld      c, FN_KBHIT
        call    BDOS
        or      a
        jr      nz, .key_pressed

        dec     de
        ld      a, d
        or      e
        jr      nz, .wait_loop
        or      a                              ; clear carry = done normally
        ret

.key_pressed:
        ld      c, FN_CONIN                    ; read the key
        call    BDOS
        cp      0x1B                           ; ESC?
        scf
        ret     z                              ; ESC -> carry = stop
        ; other key: count this tick and keep playing
        dec     de
        ld      a, d
        or      e
        jr      nz, .wait_loop
        or      a                              ; clear carry, done normally
        ret

silence_psg:
        ; mixer: all channels off, IOB=output (bit7=1)
        ld      a, 7
        di
        out     (PSG_ADDR_PORT), a
        ld      a, 0BFh
        ei
        out     (PSG_DATA_PORT), a

        ; volume A/B/C = 0
        ld      a, 8
        di
        out     (PSG_ADDR_PORT), a
        xor     a
        ei
        out     (PSG_DATA_PORT), a
        ld      a, 9
        di
        out     (PSG_ADDR_PORT), a
        xor     a
        ei
        out     (PSG_DATA_PORT), a
        ld      a, 10
        di
        out     (PSG_ADDR_PORT), a
        xor     a
        ei
        out     (PSG_DATA_PORT), a
        ret

init_psg:
        ; Reset all PSG registers (R0..R13 = 0)
        ld      b, 14
        xor     a
.clear_loop:
        ld      c, a
        di
        out     (PSG_ADDR_PORT), a
        xor     a
        ei
        out     (PSG_DATA_PORT), a
        ld      a, c
        inc     a
        djnz    .clear_loop

        ; Mixer: tone A/B/C on, noise off, IOB=output (bit7=1)
        ld      a, 7
        di
        out     (PSG_ADDR_PORT), a
        ld      a, 0B8h
        ei
        out     (PSG_DATA_PORT), a
        ret

print_banner:
        ld      de, msg_banner

print_msg:
        ld      c, FN_PRINT
        call    BDOS
        ret

msg_banner:
        db "MSX-DOS PSG PLAYER", 13, 10
        db "Usage: MPSPLAY TITLE.MPS", 13, 10, "$"

msg_openerr:
        db "File open error", 13, 10, "$"

msg_badfmt:
        db "Invalid MPS format", 13, 10, "$"

msg_too_big:
        db "File too large", 13, 10, "$"

msg_done:
        db "Done", 13, 10, "$"

load_ptr:       dw 0
file_size:      dw 0
data_ptr:       dw 0
loop_ptr:       dw 0
loop_set:       db 0
