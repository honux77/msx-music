; -----------------------------------------------------------------------------
; MSX ROM PSG Player (Konami mapper, 8KB banks)
; -----------------------------------------------------------------------------
; - Bank 0 (0x4000-0x5FFF): code + menu + song table
; - Data banks are mapped to 0xA000-0xBFFF via Konami register 0xA000
; - Song data (.MPS) is packed in ROM banks 1..
; -----------------------------------------------------------------------------

        org     0x4000

CHGET:          equ     0x009F
CHPUT:          equ     0x00A2
CHSNS:          equ     0x009C              ; non-blocking key check (Z=no key)
CLS:            equ     0x00C3
POSIT:          equ     0x00C6              ; H=X(col), L=Y(row), 1-based
CHGMOD:         equ     0x005F
ENASLT:         equ     0x0024
RSLREG:         equ     0x0138

PSG_ADDR_PORT:  equ     0xA0
PSG_DATA_PORT:  equ     0xA1
JIFFY:          equ     0xFC9E

FORCLR:         equ     0xF3E9
BAKCLR:         equ     0xF3EA
BDRCLR:         equ     0xF3EB

KONAMI_REG3:    equ     0xA000
RAM_BASE:       equ     0xC000

        db      'A','B'
        dw      init
        dw      0
        dw      0
        dw      0

init:
        ei
        call    map_page2_to_cart_slot_bios
        ; Switch to SCREEN 1: white text on dark blue
        ld      a, 15
        ld      (FORCLR), a
        ld      a, 4
        ld      (BAKCLR), a
        ld      a, 4
        ld      (BDRCLR), a
        ld      a, 1
        call    CHGMOD
        call    psg_selftest
        xor     a
        ld      (play_all_mode), a

menu_redraw:
        call    draw_menu_static

menu_loop:
        call    CHGET
        cp      '0'
        jr      z, menu_key_0
        cp      '1'
        jr      c, menu_loop        ; < '1', ignore
        sub     '1'                 ; convert to 0-based index
        cp      SONG_COUNT
        jr      nc, menu_loop       ; >= SONG_COUNT, ignore
        call    play_index
        jr      menu_redraw

menu_key_0:
        call    play_all
        jr      menu_redraw

; -----------------------------------------------------------------------------
; Menu display
; -----------------------------------------------------------------------------
draw_menu_static:
        call    CLS
        ld      hl, msg_screen
        call    print0
        ld      h, 1
        ld      l, 23
        call    POSIT
        ld      hl, msg_help
        call    print0
        ret

; -----------------------------------------------------------------------------
; Playback
; -----------------------------------------------------------------------------
play_all:
        ld      a, 1
        ld      (play_all_mode), a
        xor     a
        ld      (play_idx), a

play_all_loop:
        ld      a, (play_idx)
        cp      SONG_COUNT
        jr      z, play_all_done
        call    play_index
        ld      a, (play_idx)
        inc     a
        ld      (play_idx), a
        ld      a, (user_stop)
        or      a
        jr      nz, play_all_done
        jr      play_all_loop

play_all_done:
        xor     a
        ld      (play_all_mode), a
        ret

; In A = index 0..SONG_COUNT-1
play_index:
        ; Show now playing
        push    af
        ld      h, 1
        ld      l, 22
        call    POSIT
        ld      hl, msg_now_playing
        call    print0
        pop     af
        push    af
        ld      hl, song_name_table
        add     a, a
        ld      e, a
        ld      d, 0
        add     hl, de
        ld      a, (hl)
        inc     hl
        ld      h, (hl)
        ld      l, a
        call    print0
        pop     af

        ld      hl, song_table
        ld      b, a
        ld      de, 3
play_index_off_loop:
        ld      a, b
        or      a
        jr      z, play_index_entry
        add     hl, de
        dec     b
        jr      play_index_off_loop

play_index_entry:
        ld      a, (hl)
        ld      (src_bank), a
        inc     hl
        ld      a, (hl)
        ld      (src_ptr), a
        inc     hl
        ld      a, (hl)
        ld      (src_ptr+1), a

        ld      a, (src_bank)
        call    set_bank_data

        ; skip 16-byte MPS header
        ld      b, 16
play_skip_header_loop:
        call    fetch_byte
        djnz    play_skip_header_loop

        xor     a
        ld      (loop_set), a
        ld      (user_stop), a

play_stream_loop:
        ; Any key pressed = stop
        call    CHSNS
        jr      z, play_no_stop
        call    CHGET                       ; consume key
        ld      a, 1
        ld      (user_stop), a
        jr      play_done
play_no_stop:
        call    play_frame
        jr      c, play_done
        jr      play_stream_loop

play_done:
        call    silence_psg
        ret

; -----------------------------------------------------------------------------
; Stream player
; -----------------------------------------------------------------------------
; carry set on end
play_frame:
play_frame_loop:
        call    fetch_byte

        cp      0FEh
        jr      z, play_song_end
        cp      0FDh
        jr      z, play_set_loop
        cp      0FFh
        jr      z, play_wait_ext

        cp      80h
        jr      nc, play_wait_short

        ; register write
        ld      c, a
        call    fetch_byte
        ld      d, a
        ; R7 (mixer): keep lower 6 bits, force IOB=output (bit7=1)
        ld      a, c
        cp      7
        jr      nz, psg_reg_write
        ld      a, d
        and     3Fh
        or      80h
        ld      d, a
psg_reg_write:
        ld      a, c
        di
        out     (PSG_ADDR_PORT), a
        ld      a, d
        ei
        out     (PSG_DATA_PORT), a
        jr      play_frame_loop

play_wait_short:
        sub     7Fh
        call    wait_frames_a
        or      a
        ret

play_wait_ext:
        call    fetch_byte
        ld      e, a
        call    fetch_byte
        ld      d, a
        call    wait_frames_de
        or      a
        ret

play_set_loop:
        ld      a, (loop_set)
        or      a
        jr      nz, play_frame_loop
        ld      a, (src_bank)
        ld      (loop_bank), a
        ld      hl, (src_ptr)
        ld      (loop_ptr), hl
        ld      a, 1
        ld      (loop_set), a
        jr      play_frame_loop

play_song_end:
        ld      a, (loop_set)
        or      a
        jr      z, play_end

        ld      a, (play_all_mode)
        or      a
        jr      nz, play_end

        ld      a, (loop_bank)
        ld      (src_bank), a
        call    set_bank_data
        ld      hl, (loop_ptr)
        ld      (src_ptr), hl
        jr      play_frame_loop

play_end:
        scf
        ret

; Read byte from banked ROM stream
fetch_byte:
        ld      hl, (src_ptr)
        ld      a, (hl)
        ld      b, a

        inc     hl
        ld      (src_ptr), hl
        ld      a, h
        cp      0xC0
        jr      nz, fetch_no_wrap

        ld      hl, 0xA000
        ld      (src_ptr), hl
        ld      a, (src_bank)
        inc     a
        ld      (src_bank), a
        call    set_bank_data

fetch_no_wrap:
        ld      a, b
        ret

set_bank_data:
        ld      (KONAMI_REG3), a
        ret

map_page2_to_cart_slot_bios:
        call    RSLREG
        rrca
        rrca
        and     0x03
        ld      h, 0x80
        call    ENASLT
        ret

set_bank2_logical:
        jp      set_bank_data

wait_frames_a:
        ld      e, a
        ld      d, 0
        jr      wait_frames_de

wait_frames_de:
        ld      a, d
        or      e
        ret     z

wait_frames_loop:
        ld      a, (JIFFY)
        ld      b, a
wait_frames_spin:
        ld      a, (JIFFY)
        cp      b
        jr      z, wait_frames_spin
        dec     de
        ld      a, d
        or      e
        jr      nz, wait_frames_loop
        ret

silence_psg:
        ld      a, 7
        di
        out     (PSG_ADDR_PORT), a
        ld      a, 0xBF
        ei
        out     (PSG_DATA_PORT), a

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

psg_selftest:
        ld      a, 0
        di
        out     (PSG_ADDR_PORT), a
        ld      a, 0xAA
        ei
        out     (PSG_DATA_PORT), a
        ld      a, 1
        di
        out     (PSG_ADDR_PORT), a
        ld      a, 0x01
        ei
        out     (PSG_DATA_PORT), a

        ld      a, 7
        di
        out     (PSG_ADDR_PORT), a
        ld      a, 0xBE
        ei
        out     (PSG_DATA_PORT), a

        ld      a, 8
        di
        out     (PSG_ADDR_PORT), a
        ld      a, 10
        ei
        out     (PSG_DATA_PORT), a

        ld      a, 20
        call    wait_frames_a
        call    silence_psg
        ret

print0:
        ld      a, (hl)
        or      a
        ret     z
        call    CHPUT
        inc     hl
        jr      print0

; -----------------------------------------------------------------------------
; Strings
; -----------------------------------------------------------------------------
msg_now_playing:
        db      ">> Now Playing: ",0

; msg_screen, msg_help, song_name_table, song_name_N -- generated
include "song_table.inc"

; Runtime state (RAM)
src_ptr:        equ     RAM_BASE + 0
src_bank:       equ     RAM_BASE + 2
loop_ptr:       equ     RAM_BASE + 3
loop_bank:      equ     RAM_BASE + 5
loop_set:       equ     RAM_BASE + 6
play_all_mode:  equ     RAM_BASE + 7
play_idx:       equ     RAM_BASE + 8
user_stop:      equ     RAM_BASE + 9
