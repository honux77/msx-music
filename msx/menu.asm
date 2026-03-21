; -----------------------------------------------------------------------------
; MSX-DOS MPS Music Player with interactive menu  (MENU.COM)
; -----------------------------------------------------------------------------
; Scans *.MPS files in current directory, shows a-z menu, plays selection.
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
FN_SRCH_FIRST:  equ     0x11
FN_SRCH_NEXT:   equ     0x12

PSG_ADDR_PORT:  equ     0xA0
PSG_DATA_PORT:  equ     0xA1
JIFFY:          equ     0xFC9E

MAX_SONGS:      equ     26
ENTRY_SZ:       equ     11      ; FCB name field (8+3, no dot)

; RAM layout -- all above 0x5000 to avoid conflict with COM code
DTA_BUF:        equ     0x5000  ; 36 bytes  (directory search DTA)
SRCH_FCB:       equ     0x5030  ; 36 bytes  (search FCB)
PLAY_FCB:       equ     0x5060  ; 36 bytes  (playback FCB)
SONG_TBL:       equ     0x5090  ; 26*11=286 bytes (song name table)
SONG_CNT:       equ     0x51B0  ; 1 byte
DISP_BUF:       equ     0x51B2  ; 32 bytes  (filename display buffer)
LOAD_PTR:       equ     0x51D2  ; 2 bytes
DATA_PTR:       equ     0x51D4  ; 2 bytes
LOOP_PTR:       equ     0x51D6  ; 2 bytes
LOOP_SET:       equ     0x51D8  ; 1 byte

LOAD_ADDR:      equ     0x8000
MAX_FILE:       equ     0x7FF0

; =============================================================================
; Entry point
; =============================================================================
start:
        ; Set DTA for directory search
        ld      de, DTA_BUF
        ld      c, FN_SET_DMA
        call    BDOS

        ; Build search FCB: drive=0, "????????MPS"
        ld      hl, SRCH_FCB
        ld      b, 36
        xor     a
.clrfcb:
        ld      (hl), a
        inc     hl
        djnz    .clrfcb

        ld      hl, SRCH_FCB + 1
        ld      b, 8
        ld      a, '?'
.fillq:
        ld      (hl), a
        inc     hl
        djnz    .fillq
        ld      (hl), 'M'
        inc     hl
        ld      (hl), 'P'
        inc     hl
        ld      (hl), 'S'

        ; Scan directory for *.MPS
        xor     a
        ld      (SONG_CNT), a

        ld      de, SRCH_FCB
        ld      c, FN_SRCH_FIRST
        call    BDOS
        or      a
        jp      nz, no_songs

scan_loop:
        ; Copy 11-byte FCB name from DTA+1 to SONG_TBL[SONG_CNT]
        ld      a, (SONG_CNT)
        call    entry_ptr       ; HL = dest slot
        ex      de, hl          ; DE = dest
        ld      hl, DTA_BUF + 1 ; HL = src
        ld      bc, ENTRY_SZ
        ldir

        ld      a, (SONG_CNT)
        inc     a
        ld      (SONG_CNT), a
        cp      MAX_SONGS
        jr      nc, draw_menu   ; table full

        ld      de, SRCH_FCB
        ld      c, FN_SRCH_NEXT
        call    BDOS
        or      a
        jr      z, scan_loop

; =============================================================================
; Menu display
; =============================================================================
draw_menu:
        ; Print a few blank lines to separate from previous output
        ld      a, 3
.crlf:
        push    af
        ld      de, msg_crlf
        ld      c, FN_PRINT
        call    BDOS
        pop     af
        dec     a
        jr      nz, .crlf

        ld      de, msg_title
        ld      c, FN_PRINT
        call    BDOS

        ; List songs a)...
        xor     a
.list_loop:
        ld      b, a
        ld      a, (SONG_CNT)
        cp      b
        jr      z, .list_done
        ld      a, b

        ; print letter
        push    af
        add     a, 'a'
        ld      e, a
        ld      c, FN_CONOUT
        call    BDOS

        ld      de, msg_sep
        ld      c, FN_PRINT
        call    BDOS
        pop     af

        ; print filename
        push    af
        call    print_filename
        pop     af

        inc     a
        jr      .list_loop

.list_done:
        ; Help line: "[a-X] Play  [ESC] Quit"
        ld      de, msg_help1
        ld      c, FN_PRINT
        call    BDOS

        ld      e, 'a'
        ld      c, FN_CONOUT
        call    BDOS

        ld      de, msg_dash
        ld      c, FN_PRINT
        call    BDOS

        ld      a, (SONG_CNT)
        dec     a
        add     a, 'a'
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

        cp      0x1B            ; ESC -> quit
        jr      z, do_exit

        ; normalize to lowercase
        cp      'A'
        jr      c, menu_loop
        cp      'Z' + 1
        jr      nc, .skip_upper
        or      0x20            ; A-Z -> a-z
.skip_upper:
        cp      'a'
        jr      c, menu_loop
        sub     'a'             ; 0-based index

        ld      b, a
        ld      a, (SONG_CNT)
        cp      b
        jr      z, menu_loop    ; == means out of range (0-based)
        jr      c, menu_loop    ; < means out of range
        ld      a, b

        call    play_song
        jp      draw_menu

; =============================================================================
; Exit
; =============================================================================
do_exit:
        call    silence_psg
        ld      c, FN_TERM
        call    BDOS

no_songs:
        ld      de, msg_none
        ld      c, FN_PRINT
        call    BDOS
        ld      c, FN_TERM
        call    BDOS

; =============================================================================
; entry_ptr: HL = &SONG_TBL[A]
; =============================================================================
entry_ptr:
        or      a
        jr      z, .zero
        ld      b, a
        ld      hl, 0
        ld      de, ENTRY_SZ
.mul:
        add     hl, de
        djnz    .mul
        ld      de, SONG_TBL
        add     hl, de
        ret
.zero:
        ld      hl, SONG_TBL
        ret

; =============================================================================
; print_filename: print SONG_TBL[A] as "NAME.EXT\r\n"
; =============================================================================
print_filename:
        call    entry_ptr       ; HL = entry (8-byte name + 3-byte ext)
        ld      de, DISP_BUF

        ; Copy name (8 bytes), stop at space
        ld      b, 8
.nm:
        ld      a, (hl)
        inc     hl
        cp      ' '
        jr      z, .nm_skip
        ld      (de), a
        inc     de
        djnz    .nm
        jr      .dot
.nm_skip:
        ; Skip remaining name bytes (B still holds remaining count)
        dec     b
        jr      z, .dot
.ns:
        inc     hl
        djnz    .ns
.dot:
        ld      a, '.'
        ld      (de), a
        inc     de

        ; Copy ext (3 bytes), stop at space
        ld      b, 3
.ex:
        ld      a, (hl)
        inc     hl
        cp      ' '
        jr      z, .ex_skip
        ld      (de), a
        inc     de
        djnz    .ex
        jr      .fn_done
.ex_skip:
        dec     b
        jr      z, .fn_done
.es:
        inc     hl
        djnz    .es
.fn_done:
        ld      a, 13
        ld      (de), a
        inc     de
        ld      a, 10
        ld      (de), a
        inc     de
        ld      a, 36           ; '$' terminator for FN_PRINT
        ld      (de), a

        ld      de, DISP_BUF
        ld      c, FN_PRINT
        call    BDOS
        ret

; =============================================================================
; play_song: load and play SONG_TBL[A]
; =============================================================================
play_song:
        push    af

        ; Clear PLAY_FCB
        ld      hl, PLAY_FCB
        ld      b, 36
        xor     a
.clrp:
        ld      (hl), a
        inc     hl
        djnz    .clrp

        ; Copy 11-byte name to PLAY_FCB+1
        pop     af
        push    af
        call    entry_ptr       ; HL = &SONG_TBL[A]
        ld      de, PLAY_FCB + 1
        ld      bc, ENTRY_SZ
        ldir

        ; Open file
        ld      de, PLAY_FCB
        ld      c, FN_OPEN
        call    BDOS
        or      a
        jp      nz, .open_err

        ; Load file into LOAD_ADDR
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

        ; Validate "MPSG" header
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

        ; Stream starts at LOAD_ADDR+16
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
; play_frame: process one frame of MPS stream
; carry set = stop (song end or ESC)
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

        ; PSG register write
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
        ret                     ; propagate carry (ESC)

.wait_ext:
        ld      hl, (DATA_PTR)
        ld      e, (hl)
        inc     hl
        ld      d, (hl)
        inc     hl
        ld      (DATA_PTR), hl
        call    wait_frames_de
        ret                     ; propagate carry (ESC)

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
; Returns carry set if ESC pressed
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

        ; Check for ESC
        ld      c, FN_KBHIT
        call    BDOS
        or      a
        jr      z, .no_key
        ld      c, FN_CONIN
        call    BDOS
        cp      0x1B
        scf
        ret     z               ; ESC -> carry = stop

        ; Other key: count tick and continue
        dec     de
        ld      a, d
        or      e
        jr      nz, .wait_loop
        or      a
        ret

.no_key:
        dec     de
        ld      a, d
        or      e
        jr      nz, .wait_loop
        or      a               ; clear carry = done normally
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
msg_crlf:
        db      13, 10, "$"

msg_title:
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

msg_none:
        db      "No MPS files found.", 13, 10, "$"

msg_openerr:
        db      13, 10
        db      "File open error", 13, 10, "$"

msg_badfmt:
        db      13, 10
        db      "Invalid MPS format", 13, 10, "$"
