; -----------------------------------------------------------------------------
; MSX ROM PSG Player (Konami mapper, 8KB banks)
; -----------------------------------------------------------------------------
; - Bank 0 (0x4000-0x5FFF): code + menu + song table
; - Data banks are mapped to 0xA000-0xBFFF via Konami register 0xA000
; - Keys: a-z  select/start song; during play: any key=next, ESC=menu
; - Auto-advance every 3 minutes, loops forever until ESC
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

PLAY_TIME:      equ     10800   ; 3 min * 60 fps

; RAM layout
src_ptr:        equ     RAM_BASE + 0    ; 2 bytes
src_bank:       equ     RAM_BASE + 2    ; 1 byte
loop_ptr:       equ     RAM_BASE + 3    ; 2 bytes
loop_bank:      equ     RAM_BASE + 5    ; 1 byte
loop_set:       equ     RAM_BASE + 6    ; 1 byte
play_idx:       equ     RAM_BASE + 7    ; 1 byte  (current song index)
stop_reason:    equ     RAM_BASE + 8    ; 1 byte  (0=ESC, 1=skip/timeout)
frames_left:    equ     RAM_BASE + 9    ; 2 bytes (countdown)

        db      'A','B'
        dw      init
        dw      0
        dw      0
        dw      0

init:
        ei
        call    map_page2_to_cart_slot_bios
        ld      a, 15
        ld      (FORCLR), a
        ld      a, 4
        ld      (BAKCLR), a
        ld      a, 4
        ld      (BDRCLR), a
        ld      a, 1
        call    CHGMOD
        call    psg_selftest

menu_redraw:
        call    draw_menu

menu_loop:
        call    CHGET
        cp      'A'
        jr      c, menu_loop
        cp      'Z' + 1
        jr      nc, .ml_upper_done
        or      0x20
.ml_upper_done:
        cp      'a'
        jr      c, menu_loop
        cp      'z' + 1
        jr      nc, menu_loop
        sub     'a'
        cp      SONG_COUNT
        jr      nc, menu_loop

        ld      (play_idx), a
        call    auto_play_all
        jr      menu_redraw

; -----------------------------------------------------------------------------
; auto_play_all
; -----------------------------------------------------------------------------
auto_play_all:
.apl:
        ld      hl, PLAY_TIME
        ld      (frames_left), hl

        ld      a, (play_idx)
        call    play_song

        ld      a, (stop_reason)
        or      a
        ret     z               ; ESC -> back to menu

        ld      a, (play_idx)
        inc     a
        cp      SONG_COUNT
        jr      c, .apl_next
        xor     a
.apl_next:
        ld      (play_idx), a
        jp      .apl

; -----------------------------------------------------------------------------
; draw_menu
; -----------------------------------------------------------------------------
draw_menu:
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
; play_song: load and play song index A
; -----------------------------------------------------------------------------
play_song:
        push    af
        ld      h, 1
        ld      l, 22
        call    POSIT
        ld      hl, msg_now_playing
        call    print0
        pop     af
        push    af

        ; Print "(X)" where X is the key letter
        add     a, 'a'
        push    af
        ld      a, '('
        call    CHPUT
        pop     af
        call    CHPUT
        ld      a, ')'
        call    CHPUT
        ld      a, ' '
        call    CHPUT
        pop     af

        ; Find song_table entry (3 bytes each)
        ld      hl, song_table
        or      a
        jr      z, .ps_entry
        ld      b, a
        ld      de, 3
.ps_off:
        add     hl, de
        djnz    .ps_off

.ps_entry:
        ld      a, (hl)
        ld      (src_bank), a
        inc     hl
        ld      a, (hl)
        ld      (src_ptr), a
        inc     hl
        ld      a, (hl)
        ld      (src_ptr + 1), a

        ld      a, (src_bank)
        call    set_bank_data

        ; Skip 16-byte MPS header using C counter (NOT djnz -- fetch_byte clobbers B)
        ld      c, 16
.ps_skip:
        call    fetch_byte
        dec     c
        jr      nz, .ps_skip

        xor     a
        ld      (loop_set), a
        ld      (stop_reason), a

.ps_loop:
        call    play_frame
        jr      c, .ps_done
        jr      .ps_loop

.ps_done:
        call    silence_psg
        ret

; -----------------------------------------------------------------------------
; play_frame
; -----------------------------------------------------------------------------
play_frame:
.pf_next:
        call    fetch_byte

        cp      0xFE
        jr      z, .pf_end
        cp      0xFD
        jr      z, .pf_setloop
        cp      0xFF
        jr      z, .pf_ext

        cp      0x80
        jr      nc, .pf_short

        ; register write
        ld      c, a
        call    fetch_byte
        ld      d, a
        ld      a, c
        cp      7
        jr      nz, .pf_psg
        ld      a, d
        and     0x3F
        or      0x80
        ld      d, a
.pf_psg:
        ld      a, c
        di
        out     (PSG_ADDR_PORT), a
        ld      a, d
        ei
        out     (PSG_DATA_PORT), a
        jr      .pf_next

.pf_short:
        sub     0x7F
        call    wait_frames_a
        ret

.pf_ext:
        call    fetch_byte
        ld      e, a
        call    fetch_byte
        ld      d, a
        call    wait_frames_de
        ret

.pf_setloop:
        ld      a, (loop_set)
        or      a
        jr      nz, .pf_next
        ld      a, (src_bank)
        ld      (loop_bank), a
        ld      hl, (src_ptr)
        ld      (loop_ptr), hl
        ld      a, 1
        ld      (loop_set), a
        jr      .pf_next

.pf_end:
        ld      a, (loop_set)
        or      a
        jr      z, .pf_done
        ld      a, (loop_bank)
        ld      (src_bank), a
        call    set_bank_data
        ld      hl, (loop_ptr)
        ld      (src_ptr), hl
        jp      .pf_next
.pf_done:
        scf
        ret

; -----------------------------------------------------------------------------
; wait_frames_a / wait_frames_de
; -----------------------------------------------------------------------------
wait_frames_a:
        ld      e, a
        ld      d, 0

wait_frames_de:
        ld      a, d
        or      e
        ret     z

.wf_loop:
        ld      a, (JIFFY)
        ld      b, a
.wf_spin:
        ld      a, (JIFFY)
        cp      b
        jr      z, .wf_spin

        ; Key check
        call    CHSNS
        jr      z, .wf_no_key

        call    CHGET
        cp      0x1B
        jr      z, .wf_esc
        ld      a, 1
        ld      (stop_reason), a
        scf
        ret
.wf_esc:
        xor     a
        ld      (stop_reason), a
        scf
        ret

.wf_no_key:
        ; FRAMES_LEFT countdown
        ld      hl, (frames_left)
        ld      a, h
        or      l
        jr      z, .wf_de
        dec     hl
        ld      (frames_left), hl
        ld      a, h
        or      l
        jr      nz, .wf_de
        ; Expired -> next song
        ld      a, 1
        ld      (stop_reason), a
        scf
        ret

.wf_de:
        dec     de
        ld      a, d
        or      e
        jp      nz, .wf_loop
        or      a
        ret

; -----------------------------------------------------------------------------
; fetch_byte: read from banked ROM stream, preserves BC
; -----------------------------------------------------------------------------
fetch_byte:
        ld      hl, (src_ptr)
        ld      a, (hl)
        push    af              ; save byte (B not used -- callers may use djnz)

        inc     hl
        ld      (src_ptr), hl
        ld      a, h
        cp      0xC0
        jr      nz, .fb_ok

        ld      hl, 0xA000
        ld      (src_ptr), hl
        ld      a, (src_bank)
        inc     a
        ld      (src_bank), a
        call    set_bank_data

.fb_ok:
        pop     af
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

; -----------------------------------------------------------------------------
; PSG helpers
; -----------------------------------------------------------------------------
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

; -----------------------------------------------------------------------------
; print0: null-terminated string
; -----------------------------------------------------------------------------
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
