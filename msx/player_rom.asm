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
CLS:            equ     0x00C3
POSIT:          equ     0x00C6
CHGMOD:         equ     0x005F
ENASLT:         equ     0x0024
RSLREG:         equ     0x0138
GTSTCK:         equ     0x00D5
SNSMAT:         equ     0x0141

PSG_ADDR_PORT:  equ     0xA0
PSG_DATA_PORT:  equ     0xA1
JIFFY:          equ     0xFC9E

FORCLR:         equ     0xF3E9              ; foreground color (system var)
BAKCLR:         equ     0xF3EA              ; background color (system var)
BDRCLR:         equ     0xF3EB              ; border color (system var)

KONAMI_REG3:    equ     0xA000              ; map 8KB bank to 0xA000-0xBFFF
RAM_BASE:       equ     0xC000
MENU_ROW_BASE:  equ     5                   ; first menu item row (1-based)

        db      'A','B'
        dw      init                       ; init routine
        dw      0                          ; statement
        dw      0                          ; device
        dw      0                          ; text

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
        ld      a, 1
        ld      (menu_sel), a
        call    draw_menu_static
        ld      a, (menu_sel)
        call    draw_menu_cursor

menu_loop:
        call    read_nav_event             ; A: 1=up 2=down 3=select 4=quit
        cp      4
        ret     z                          ; quit to BASIC
        cp      1
        jr      z, menu_nav_up
        cp      2
        jr      z, menu_nav_down
        ; select
        ld      a, (menu_sel)
        or      a
        jr      z, menu_play_all
        dec     a                          ; 1..11 -> 0..10
        call    play_index
        call    draw_menu_static
        ld      a, (menu_sel)
        call    draw_menu_cursor
        jr      menu_loop

menu_play_all:
        call    play_all
        call    draw_menu_static
        ld      a, (menu_sel)
        call    draw_menu_cursor
        jr      menu_loop

menu_nav_up:
        ld      a, (menu_sel)
        call    erase_menu_cursor
        ld      a, (menu_sel)
        or      a
        jr      nz, menu_nav_up_dec
        ld      a, SONG_COUNT
        ld      (menu_sel), a
        call    draw_menu_cursor
        jr      menu_loop
menu_nav_up_dec:
        dec     a
        ld      (menu_sel), a
        call    draw_menu_cursor
        jr      menu_loop

menu_nav_down:
        ld      a, (menu_sel)
        call    erase_menu_cursor
        ld      a, (menu_sel)
        cp      SONG_COUNT
        jr      nz, menu_nav_down_inc
        xor     a
        ld      (menu_sel), a
        call    draw_menu_cursor
        jr      menu_loop
menu_nav_down_inc:
        inc     a
        ld      (menu_sel), a
        call    draw_menu_cursor
        jr      menu_loop

draw_menu_static:
        call    CLS
        ld      hl, msg_screen
        call    print0
        ; Help line at last row: H=X(col 1), L=Y(row 23)
        ld      h, 1
        ld      l, 23
        call    POSIT
        ld      hl, msg_help
        call    print0
        ret

; In A = selection 0..11
draw_menu_cursor:
        push    af
        call    menu_pos_for_sel
        ld      a, '>'
        call    CHPUT
        pop     af
        ret

; In A = selection 0..11
erase_menu_cursor:
        push    af
        call    menu_pos_for_sel
        ld      a, ' '
        call    CHPUT
        pop     af
        ret

; In A = selection 0..11
; Out: cursor positioned at left marker column for that row
menu_pos_for_sel:
        add     a, MENU_ROW_BASE
        ld      l, a                        ; L = Y (row)
        ld      h, 1                        ; H = X (col 1, leftmost)
        call    POSIT
        ret

; -----------------------------------------------------------------------------
; Direction/joystick input
; Out A: 1=up 2=down 3=select(right) 4=quit(left)
; -----------------------------------------------------------------------------
read_nav_event:
read_nav_release:
        call    get_nav_state
        or      a
        jr      nz, read_nav_release
read_nav_press:
        call    get_nav_state
        or      a
        jr      z, read_nav_press
        ret

get_nav_state:
        ; Check space bar (keyboard matrix row 8, bit 0)
        ld      e, 8
        call    SNSMAT
        and     1
        jr      nz, get_nav_directions      ; bit=1 means not pressed
        ld      a, 3                        ; space = select/play
        ret
get_nav_directions:
        xor     a                           ; cursor keys
        call    GTSTCK
        call    decode_stick
        or      a
        ret     nz
        ld      a, 1                        ; joystick port 1
        call    GTSTCK
        call    decode_stick
        ret

; In A: GTSTCK code (0=center,1..8 directions)
; Out A: 0 none, 1 up, 2 down, 3 select, 4 quit
decode_stick:
        cp      1
        jr      z, decode_up
        cp      2
        jr      z, decode_up
        cp      8
        jr      z, decode_up
        cp      4
        jr      z, decode_down
        cp      5
        jr      z, decode_down
        cp      6
        jr      z, decode_down
        cp      3
        jr      z, decode_select
        cp      7
        jr      z, decode_quit
        xor     a
        ret
decode_up:
        ld      a, 1
        ret
decode_down:
        ld      a, 2
        ret
decode_select:
        ld      a, 3
        ret
decode_quit:
        ld      a, 4
        ret

; -----------------------------------------------------------------------------
; Playback selection
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
        jr      play_all_loop

play_all_done:
        xor     a
        ld      (play_all_mode), a
        ret

; In A = index 0..SONG_COUNT-1
play_index:
        ; Show song name: H=X(col 1), L=Y(row 10)
        push    af
        ld      h, 1
        ld      l, 10
        call    POSIT
        ld      hl, msg_now_playing
        call    print0
        pop     af
        push    af
        ; look up song name from table
        ld      hl, song_name_table
        add     a, a                        ; *2 for 16-bit pointer
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

play_stream_loop:
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
        jr      nz, play_end              ; disable loop in play-all mode

        ld      a, (loop_bank)
        ld      (src_bank), a
        call    set_bank_data
        ld      hl, (loop_ptr)
        ld      (src_ptr), hl
        jr      play_frame_loop

play_end:
        scf
        ret

; Read byte from banked ROM stream, advance pointer and bank when crossing 0xC000.
; Out: A = byte
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

; Map page2 (0x8000-0xBFFF) to the same primary slot as page1 using BIOS.
map_page2_to_cart_slot_bios:
        call    RSLREG                     ; page slots in A
        rrca
        rrca                               ; page1 bits -> bits0-1
        and     0x03                       ; primary slot id
        ld      h, 0x80                    ; page2 address range
        call    ENASLT
        ret

; For Konami in this build, logical bank value is raw 8KB bank number.
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
        ; mixer: all channels off, IOB=output (bit7=1)
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
        ; Channel A tone = fixed beep
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

        ; enable tone A only, IOB=output (bit7=1)
        ld      a, 7
        di
        out     (PSG_ADDR_PORT), a
        ld      a, 0xBE
        ei
        out     (PSG_DATA_PORT), a

        ; volume A = 10
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

; HL -> zero-terminated string
print0:
        ld      a, (hl)
        or      a
        ret     z
        call    CHPUT
        inc     hl
        jr      print0

; CRlf-based screen layout:
;   row 0: blank
;   row 1: title
;   row 2: separator
;   row 3: blank
;   row 4: item 0  <- MENU_ROW_BASE
;   row 5: item 1
;   row 6: item 2
msg_screen:
        db      13,10
        db      " * MSX PSG PLAYER - USAS *",13,10
        db      " ==========================",13,10
        db      13,10
        db      " 0) Play All",13,10
        db      " 1) Mohenjo daro",13,10
        db      " 2) Juba ruins",13,10
        db      0

msg_help:
        db      "SPC:Play UP/DN:Move L:Quit",0

msg_now_playing:
        db      ">> Now Playing: ",0

song_name_table:
        dw      song_name0
        dw      song_name1

song_name0:
        db      "Mohenjo daro",0

song_name1:
        db      "Juba ruins",0

include "song_table.inc"

; Runtime state must live in RAM (ROM is read-only)
src_ptr:        equ     RAM_BASE + 0       ; 2 bytes
src_bank:       equ     RAM_BASE + 2       ; 1 byte
loop_ptr:       equ     RAM_BASE + 3       ; 2 bytes
loop_bank:      equ     RAM_BASE + 5       ; 1 byte
loop_set:       equ     RAM_BASE + 6       ; 1 byte
play_all_mode:  equ     RAM_BASE + 7       ; 1 byte
play_idx:       equ     RAM_BASE + 8       ; 1 byte
menu_sel:       equ     RAM_BASE + 9       ; 1 byte
