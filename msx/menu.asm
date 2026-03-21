; -----------------------------------------------------------------------------
; MSX-DOS MPS Music Player with interactive menu  (MENU.COM)
; -----------------------------------------------------------------------------
; Song list embedded at build time via menu_names.inc (from vgz/ filenames).
; Keys: a-z  select song
;       ESC  quit (also stops playback)
; -----------------------------------------------------------------------------

        ORG     0100h

BDOS:           equ     0x0005

FN_TERM:        equ     0x00
FN_CONOUT:      equ     0x02
FN_CONIN:       equ     0x08
FN_PRINT:       equ     0x09
FN_KBHIT:       equ     0x0B
FN_OPEN:        equ     0x0F
FN_CLOSE:       equ     0x10
FN_READ_SEQ:    equ     0x14
FN_SET_DMA:     equ     0x1A

PSG_ADDR_PORT:  equ     0xA0
PSG_DATA_PORT:  equ     0xA1
JIFFY:          equ     0xFC9E

; RAM layout
PLAY_FCB:       equ     0x5000  ; 36 bytes
LOAD_PTR:       equ     0x5024  ; 2 bytes
DATA_PTR:       equ     0x5026  ; 2 bytes
LOOP_PTR:       equ     0x5028  ; 2 bytes
LOOP_SET:       equ     0x502A  ; 1 byte

LOAD_ADDR:      equ     0x8000
MAX_FILE:       equ     0x7FF0

; =============================================================================
; Entry point / Menu display
; =============================================================================
start:
draw_menu:
        ; Clear screen (VT52 ESC E)
        ld      e, 0x1B
        ld      c, FN_CONOUT
        call    BDOS
        ld      e, 'E'
        ld      c, FN_CONOUT
        call    BDOS

        ld      de, msg_title
        ld      c, FN_PRINT
        call    BDOS

        ; List: a) display name ...
        xor     a
.list_loop:
        cp      MENU_SONG_COUNT
        jr      z, .list_done

        push    af
        add     a, 'a'
        ld      e, a
        ld      c, FN_CONOUT
        call    BDOS

        ld      de, msg_sep
        ld      c, FN_PRINT
        call    BDOS

        pop     af
        push    af
        call    print_name

        pop     af
        inc     a
        jr      .list_loop

.list_done:
        ; Help line: [a-X] Play  [ESC] Quit
        ld      de, msg_help1
        ld      c, FN_PRINT
        call    BDOS

        ld      e, 'a'
        ld      c, FN_CONOUT
        call    BDOS

        ld      de, msg_dash
        ld      c, FN_PRINT
        call    BDOS

        ld      a, MENU_SONG_COUNT + 96 ; 'a' + MENU_SONG_COUNT - 1
        ld      e, a
        ld      c, FN_CONOUT
        call    BDOS

        ld      de, msg_help2
        ld      c, FN_PRINT
        call    BDOS

; =============================================================================
; Menu input loop
; =============================================================================
menu_loop:
        ld      c, FN_CONIN
        call    BDOS

        cp      0x1B
        jr      z, do_exit

        cp      'A'
        jr      c, menu_loop
        cp      'Z' + 1
        jr      nc, .skip_upper
        or      0x20
.skip_upper:
        cp      'a'
        jr      c, menu_loop
        sub     'a'
        cp      MENU_SONG_COUNT
        jr      nc, menu_loop

        call    play_song
        jp      draw_menu

; =============================================================================
; Exit
; =============================================================================
do_exit:
        call    silence_psg
        ld      c, FN_TERM
        call    BDOS

; =============================================================================
; print_name: print display name for song index A (FN_PRINT with CRLF$)
; =============================================================================
print_name:
        add     a, a            ; index * 2
        ld      e, a
        ld      d, 0
        ld      hl, menu_name_table
        add     hl, de
        ld      e, (hl)
        inc     hl
        ld      d, (hl)
        ld      c, FN_PRINT
        call    BDOS
        ret

; =============================================================================
; play_song: load and play song at index A
; =============================================================================
play_song:
        push    af

        ; Zero-fill PLAY_FCB
        ld      hl, PLAY_FCB
        ld      b, 36
        xor     a
.clrp:  ld      (hl), a
        inc     hl
        djnz    .clrp

        ; Copy 11-byte FCB name from menu_fcb_table[index]
        pop     af
        push    af
        ld      hl, menu_fcb_table
        or      a
        jr      z, .fcb_ready
        ld      b, a
        ld      de, 11
.fcb_add:
        add     hl, de
        djnz    .fcb_add
.fcb_ready:
        ld      de, PLAY_FCB + 1
        ld      bc, 11
        ldir

        ; Open file
        ld      de, PLAY_FCB
        ld      c, FN_OPEN
        call    BDOS
        or      a
        jp      nz, .open_err

        ; Load file
        ld      hl, LOAD_ADDR
        ld      (LOAD_PTR), hl
.read_loop:
        ld      de, (LOAD_PTR)
        ld      c, FN_SET_DMA
        call    BDOS
        ld      de, PLAY_FCB
        ld      c, FN_READ_SEQ
        call    BDOS
        or      a
        jr      nz, .read_done

        ld      hl, (LOAD_PTR)
        ld      de, 128
        add     hl, de
        ld      (LOAD_PTR), hl
        ld      de, LOAD_ADDR + MAX_FILE
        xor     a
        sbc     hl, de
        jr      c, .read_loop

.read_done:
        ld      de, PLAY_FCB
        ld      c, FN_CLOSE
        call    BDOS

        ; Validate "MPSG"
        ld      hl, LOAD_ADDR
        ld      a, (hl)
        cp      'M'
        jr      nz, .bad_fmt
        inc     hl
        ld      a, (hl)
        cp      'P'
        jr      nz, .bad_fmt
        inc     hl
        ld      a, (hl)
        cp      'S'
        jr      nz, .bad_fmt
        inc     hl
        ld      a, (hl)
        cp      'G'
        jr      nz, .bad_fmt

        ld      hl, LOAD_ADDR + 16
        ld      (DATA_PTR), hl
        xor     a
        ld      (LOOP_SET), a
        call    init_psg

.play_loop:
        call    play_frame
        jr      c, .play_done
        jr      .play_loop

.play_done:
        call    silence_psg
        pop     af
        ret

.open_err:
        ld      de, msg_openerr
        ld      c, FN_PRINT
        call    BDOS
        pop     af
        ret

.bad_fmt:
        ld      de, msg_badfmt
        ld      c, FN_PRINT
        call    BDOS
        pop     af
        ret

; =============================================================================
; play_frame
; =============================================================================
play_frame:
.next_cmd:
        ld      hl, (DATA_PTR)
        ld      a, (hl)
        inc     hl
        ld      (DATA_PTR), hl

        cp      0xFE
        jr      z, .song_end
        cp      0xFD
        jr      z, .set_loop
        cp      0xFF
        jr      z, .wait_ext
        cp      0x80
        jr      nc, .wait_short

        ld      e, a
        ld      hl, (DATA_PTR)
        ld      d, (hl)
        inc     hl
        ld      (DATA_PTR), hl
        ld      a, e
        cp      7
        jr      nz, .psg_write
        ld      a, d
        and     0x3F
        or      0x80
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
        sub     0x7F
        call    wait_frames_a
        ret

.wait_ext:
        ld      hl, (DATA_PTR)
        ld      e, (hl)
        inc     hl
        ld      d, (hl)
        inc     hl
        ld      (DATA_PTR), hl
        call    wait_frames_de
        ret

.set_loop:
        ld      a, (LOOP_SET)
        or      a
        jp      nz, .next_cmd
        ld      hl, (DATA_PTR)
        ld      (LOOP_PTR), hl
        ld      a, 1
        ld      (LOOP_SET), a
        jp      .next_cmd

.song_end:
        ld      a, (LOOP_SET)
        or      a
        jr      z, .pf_done
        ld      hl, (LOOP_PTR)
        ld      (DATA_PTR), hl
        jp      .next_cmd
.pf_done:
        scf
        ret

; =============================================================================
; wait_frames_a / wait_frames_de
; =============================================================================
wait_frames_a:
        ld      e, a
        ld      d, 0

wait_frames_de:
        ld      a, d
        or      e
        ret     z

.wait_loop:
        ld      hl, JIFFY
        ld      a, (hl)
.spin:
        ld      hl, JIFFY
        cp      (hl)
        jr      z, .spin

        ld      c, FN_KBHIT
        call    BDOS
        or      a
        jr      z, .no_key

        ld      c, FN_CONIN
        call    BDOS
        scf
        ret                     ; any key -> stop

.no_key:
        dec     de
        ld      a, d
        or      e
        jr      nz, .wait_loop
        or      a
        ret

; =============================================================================
; PSG helpers
; =============================================================================
init_psg:
        ld      b, 14
        xor     a
.loop:
        ld      c, a
        di
        out     (PSG_ADDR_PORT), a
        xor     a
        ei
        out     (PSG_DATA_PORT), a
        ld      a, c
        inc     a
        djnz    .loop
        ld      a, 7
        di
        out     (PSG_ADDR_PORT), a
        ld      a, 0xB8
        ei
        out     (PSG_DATA_PORT), a
        ret

silence_psg:
        ld      a, 7
        di
        out     (PSG_ADDR_PORT), a
        ld      a, 0xBF
        ei
        out     (PSG_DATA_PORT), a
        ld      b, 3
        ld      a, 8
.mute:
        ld      c, a
        di
        out     (PSG_ADDR_PORT), a
        xor     a
        ei
        out     (PSG_DATA_PORT), a
        ld      a, c
        inc     a
        djnz    .mute
        ret

; =============================================================================
; Strings
; =============================================================================
msg_title:
        db      13, 10
        db      " MSX-DOS MPS PLAYER", 13, 10
        db      " ===================", 13, 10
        db      13, 10, "$"

msg_sep:
        db      ") $"

msg_help1:
        db      13, 10
        db      " [", 36

msg_dash:
        db      "-$"

msg_help2:
        db      "] Play  [ESC] Quit", 13, 10, "$"

msg_openerr:
        db      13, 10
        db      "File open error", 13, 10, "$"

msg_badfmt:
        db      13, 10
        db      "Invalid MPS format", 13, 10, "$"

; =============================================================================
; Auto-generated song table (from vgz/ filenames via gen_menu_names.py)
; =============================================================================
        include 'menu_names.inc'
