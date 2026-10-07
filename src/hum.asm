;=====================================================================
; THE HUM BENEATH - a first-person dungeon crawler for the Sinclair QL
; 68000/68008 assembler, Mode 8 (256x256, 8 colours)
;
; Assembler : vasm  ->  vasmm68k_mot -Fbin -m68000 -o hum_bin hum.asm
; Start     : EXEC_W win1_thehum           (file with job header)
;        or  a=RESPR(n):LBYTES win1_hum_bin,a:CALL a+20
;
; The code is position independent (PIC): all variables live in a
; heap block allocated with MT.ALCHP, base register A5.
; All game strings are in the external file hum_txt (see data/text.txt).
;=====================================================================

;---------------------------------------------------------------------
; Hardware / screen layout
;---------------------------------------------------------------------
SCREEN  equ     $20000
LINEB   equ     128             ; bytes per screen line
VIEW_W  equ     48              ; viewport width in words (192 px)
VIEW_H  equ     128             ; viewport height in lines
PANEL_X equ     48              ; party panel: first word column
PANEL_W equ     16              ; party panel width in words (64 px)
SEP_Y   equ     128             ; separator between view and messages
SEP_H   equ     8

; colours
C_BLACK equ     0
C_BLUE  equ     1
C_RED   equ     2
C_MAG   equ     3
C_GREEN equ     4
C_CYAN  equ     5
C_YEL   equ     6
C_WHITE equ     7

;---------------------------------------------------------------------
; QDOS
;---------------------------------------------------------------------
MT_INF   equ    $00
MT_FRJOB equ    $05
MT_SUSJB equ    $08
MT_DMODE equ    $10
MT_IPCOM equ    $11
MT_ALCHP equ    $18
MT_RECHP equ    $19
IO_OPEN  equ    $01
IO_CLOSE equ    $02
IO_FSTRG equ    $03
IO_SSTRG equ    $07
SD_BORDR equ    $0c
SD_SETPA equ    $27
SD_SETST equ    $28
SD_SETIN equ    $29
SD_SETSZ equ    $2d
SD_CLEAR equ    $20

; KEYROW(1) bits - CTL1 joystick = cursor keys + space
K_ENTER equ     0
K_LEFT  equ     1
K_UP    equ     2
K_ESC   equ     3
K_RIGHT equ     4
K_SPACE equ     6
K_DOWN  equ     7

;---------------------------------------------------------------------
; Text file hum_txt
;---------------------------------------------------------------------
TXT_MAGIC equ   'HTX1'
TXT_LEN   equ   4               ; offset of length.l
TXT_COUNT equ   8               ; offset of count.w
TXT_OFFS  equ   10              ; offset of the offset table
TXT_HEAD  equ   10              ; bytes read before the heap exists

NAMEBUF equ     48              ; room for device + file name (QDOS string)

;---------------------------------------------------------------------
; Global variables (A5)
;---------------------------------------------------------------------
        rsreset
v_heap  rs.l    1               ; start of the heap block
v_sp    rs.l    1               ; stack pointer at entry
v_mode  rs.w    1               ; 0 = job, 1 = CALL
v_sysv  rs.l    1               ; system variables (MT.INF)
v_msg   rs.l    1               ; message window channel
v_text  rs.l    1               ; text file in memory (0 = not loaded)
v_keys  rs.w    1               ; current keys (KEYROW(1) layout)
v_pkeys rs.w    1               ; keys of the previous poll
v_size  rs.b    0               ; text file follows directly

;---------------------------------------------------------------------
; Macros
;---------------------------------------------------------------------
LEAX    macro                   ; PIC lea for targets more than 32K away
.lx\@   lea     .lx\@(pc),\2
        add.l   #\1-.lx\@,\2
        endm

qstr    macro                   ; QDOS string: length word + characters
        dc.w    qe\@-qs\@
qs\@    dc.b    \1
qe\@
        even
        endm

;=====================================================================
; Job header
;=====================================================================
hdr:    bra.w   jobentry
        dc.w    0
        dc.w    $4afb
        dc.w    6
        dc.b    'TheHum'
        dcb.b   20-(*-hdr),0
        ifne    *-hdr-20
        fail    "CALL entry must be at offset 20"
        endc
callentry:                      ; offset 20: entry point for CALL
        movem.l d1-d7/a0-a6,-(sp)
        moveq   #1,d7
        bra.s   common
jobentry:
        moveq   #0,d7
common:
        move.l  sp,a4

;---------------------------------------------------------------------
; Open the text file and read its header first: its length decides
; the size of the heap block (one block for everything).
;---------------------------------------------------------------------
        lea     -(NAMEBUF+TXT_HEAD+2)(sp),sp
        moveq   #0,d6           ; text length (0 = no text file)
        lea     txtname(pc),a2
        move.l  sp,a3
        bsr     fopen
        bne.s   .notxt
        move.l  a0,a2           ; a2 = channel
        lea     NAMEBUF(sp),a1
        moveq   #TXT_HEAD,d4
        bsr     fread
        bne.s   .badtxt
        lea     NAMEBUF(sp),a1
        cmp.l   #TXT_MAGIC,(a1)
        bne.s   .badtxt
        move.l  TXT_LEN(a1),d6
        cmp.l   #TXT_HEAD,d6
        bhi.s   .alloc
.badtxt move.l  a2,a0
        moveq   #IO_CLOSE,d0
        trap    #2
        moveq   #0,d6
.notxt  sub.l   a2,a2
.alloc  move.l  #v_size+1,d1
        add.l   d6,d1
        and.w   #$fffe,d1
        moveq   #MT_ALCHP,d0
        moveq   #-1,d2
        trap    #1
        tst.l   d0
        bne.s   .nomem
        move.l  a0,a5
        move.l  a5,a1           ; clear the variables
        move.w  #v_size/2-1,d0
.clr    clr.w   (a1)+
        dbra    d0,.clr
        move.l  a5,v_heap(a5)
        move.l  a4,v_sp(a5)
        move.w  d7,v_mode(a5)
        move.l  a2,d0           ; text file open?
        beq.s   .head
        lea     v_size(a5),a1   ; copy the header, read the rest
        move.l  a1,v_text(a5)
        lea     NAMEBUF(sp),a0
        moveq   #TXT_HEAD-1,d0
.cp     move.b  (a0)+,(a1)+
        dbra    d0,.cp
        move.l  a2,a0
        move.l  d6,d4
        sub.l   #TXT_HEAD,d4
        bsr     fread
        beq.s   .close
        clr.l   v_text(a5)      ; read error: treat as missing
.close  move.l  a2,a0
        moveq   #IO_CLOSE,d0
        trap    #2
        bra.s   .head
.nomem  move.l  a2,d1           ; out of memory: close file, leave
        beq.s   .nm2
        move.l  d0,-(sp)
        move.l  a2,a0
        moveq   #IO_CLOSE,d0
        trap    #2
        move.l  (sp)+,d0
.nm2    bra     leave
.head   lea     NAMEBUF+TXT_HEAD+2(sp),sp

        moveq   #MT_INF,d0      ; where are the system variables?
        trap    #1
        move.l  a0,v_sysv(a5)
        moveq   #MT_DMODE,d0    ; Mode 8
        moveq   #8,d1
        moveq   #-1,d2
        trap    #1
        bsr     cls

        lea     msgname(pc),a0
        bsr     opench
        move.l  a0,v_msg(a5)

        tst.l   v_text(a5)
        bne.s   start
        lea     notext(pc),a1   ; the only text not in hum_txt
        move.w  (a1)+,d2
        move.l  v_msg(a5),a0
        moveq   #IO_SSTRG,d0
        bsr     io3
        bsr     wait_esc
        bra     exit_prog

;=====================================================================
; Milestone 1a: screen layout placeholder and some texts
;=====================================================================
start:
        bsr     draw_frame
        moveq   #T_TITLE,d0
        bsr     msg_print
        moveq   #T_ENTRY_1,d0
        bsr     msg_print
        moveq   #T_MARK_1_1,d0
        bsr     msg_print
        moveq   #T_PRESS_ESC,d0
        bsr     msg_print
        bsr     wait_esc

;---------------------------------------------------------------------
; Exit: close channels, Mode 4, free the heap, back to BASIC
;---------------------------------------------------------------------
exit_prog:
        move.l  v_msg(a5),a0
        moveq   #IO_CLOSE,d0
        trap    #2
        moveq   #MT_DMODE,d0
        moveq   #4,d1
        moveq   #-1,d2
        trap    #1
        move.w  v_mode(a5),d7
        move.l  v_sp(a5),a4
        move.l  v_heap(a5),a0
        moveq   #MT_RECHP,d0
        trap    #1
        moveq   #0,d0
leave:                          ; d0 = error code, d7 = mode, a4 = SP
        tst.w   d7
        bne.s   .call
        move.l  d0,d3
        moveq   #MT_FRJOB,d0
        moveq   #-1,d1
        trap    #1
.call   move.l  a4,sp
        movem.l (sp)+,d1-d7/a0-a6
        rts

;=====================================================================
; Files
;=====================================================================
; fopen: a2 = QDOS file name without device, a3 = buffer (NAMEBUF)
;        tries the default directory, then win1_, flp1_, mdv1_
;        -> d0 = error (EQ = ok), a0 = channel
fopen:
        movem.l d1-d4/a1-a3,-(sp)
        moveq   #0,d4
.try    lea     2(a3),a1
        moveq   #0,d1
        tst.w   d4
        beq.s   .nopre
        lea     devices(pc),a0
        move.w  d4,d0
        mulu    #5,d0
        lea     -5(a0,d0.w),a0
        moveq   #5-1,d0
.pre    move.b  (a0)+,(a1)+
        dbra    d0,.pre
        moveq   #5,d1
.nopre  move.l  a2,a0
        move.w  (a0)+,d0
        add.w   d0,d1
        subq.w  #1,d0
.name   move.b  (a0)+,(a1)+
        dbra    d0,.name
        move.w  d1,(a3)
        move.l  a3,a0
        moveq   #IO_OPEN,d0
        moveq   #-1,d1
        moveq   #1,d3           ; old file, shared
        trap    #2
        tst.l   d0
        beq.s   .ok
        addq.w  #1,d4
        cmp.w   #4,d4
        bne.s   .try
.ok     movem.l (sp)+,d1-d4/a1-a3
        tst.l   d0
        rts

; fread: a0 = channel, a1 = destination, d4.l = number of bytes
;        -> d0 = error (EQ = ok, all bytes read)
fread:
        movem.l d1-d4/a1-a2,-(sp)
.chunk  move.l  d4,d2
        cmp.l   #$4000,d2
        bls.s   .n
        move.l  #$4000,d2
.n      move.l  a1,a2           ; trap #3 changes a1
        moveq   #IO_FSTRG,d0
        moveq   #-1,d3
        trap    #3
        tst.l   d0
        bne.s   .e
        move.l  a2,a1
        add.l   d1,a1
        sub.l   d1,d4
        bne.s   .chunk
.e      movem.l (sp)+,d1-d4/a1-a2
        tst.l   d0
        rts

;=====================================================================
; Texts
;=====================================================================
; text_get: d0.w = text id -> a1 = zero-terminated string
text_get:
        move.l  v_text(a5),a1
        add.w   d0,d0
        moveq   #0,d1
        move.w  TXT_OFFS(a1,d0.w),d1
        add.l   d1,a1
        rts

; msg_print: d0.w = text id, printed on a new line of the message window
msg_print:
        movem.l d0-d3/a0-a2,-(sp)
        bsr.s   text_get
        move.l  a1,a2           ; trap #3 smashes a1
        moveq   #-1,d2
.len    addq.w  #1,d2
        tst.b   (a1)+
        bne.s   .len
        move.l  v_msg(a5),a0
        move.l  a2,a1
        moveq   #IO_SSTRG,d0
        bsr.s   io3
        lea     newline(pc),a1  ; QDOS keeps the newline pending: no scroll
        moveq   #1,d2
        moveq   #IO_SSTRG,d0
        bsr.s   io3
        movem.l (sp)+,d0-d3/a0-a2
        rts

;=====================================================================
; Channels
;=====================================================================
opench:                         ; a0 = name -> a0 = channel
        moveq   #IO_OPEN,d0
        moveq   #-1,d1
        moveq   #0,d3
        trap    #2
        moveq   #SD_BORDR,d0
        moveq   #0,d1
        moveq   #0,d2
        bsr.s   io3
        moveq   #SD_SETPA,d0
        moveq   #C_BLACK,d1
        bsr.s   io3
        moveq   #SD_SETST,d0
        moveq   #C_BLACK,d1
        bsr.s   io3
        moveq   #SD_SETIN,d0
        moveq   #C_WHITE,d1
        bsr.s   io3
        moveq   #SD_SETSZ,d0    ; 6 px characters: 42 columns
        moveq   #2,d1
        moveq   #0,d2
        bsr.s   io3
        moveq   #SD_CLEAR,d0
        ; fallthrough
io3:    moveq   #-1,d3
        trap    #3
        rts

;=====================================================================
; Input
;=====================================================================
readkeys:                       ; -> d0 = KEYROW(1), CTL2 mapped onto it
        movem.l d1-d3/a0-a3,-(sp)
        lea     kr1(pc),a3
        moveq   #MT_IPCOM,d0
        trap    #1
        and.w   #$ff,d1
        move.w  d1,-(sp)
        lea     kr0(pc),a3      ; CTL2 / F1-F5: MiSTer maps the first pad here
        moveq   #MT_IPCOM,d0
        trap    #1
        move.w  (sp)+,d0
        btst    #1,d1           ; F1 = left
        beq.s   .f1
        bset    #K_LEFT,d0
.f1     btst    #4,d1           ; F3 = right
        beq.s   .f3
        bset    #K_RIGHT,d0
.f3     btst    #0,d1           ; F4 = up
        beq.s   .f4
        bset    #K_UP,d0
.f4     btst    #3,d1           ; F2 = down
        beq.s   .f2
        bset    #K_DOWN,d0
.f2     btst    #5,d1           ; F5 = fire
        beq.s   .f5
        bset    #K_SPACE,d0
.f5     move.w  v_keys(a5),v_pkeys(a5)
        move.w  d0,v_keys(a5)
        move.l  v_sysv(a5),a0   ; empty the keyboard queue, so that the keys
        move.l  $4c(a0),d1      ; pressed in the game do not end up in BASIC
        beq.s   .q
        move.l  d1,a0
        move.l  8(a0),12(a0)    ; next out = next in
.q      movem.l (sp)+,d1-d3/a0-a3
        rts

frame:                          ; give the CPU away for one frame (20 ms)
        movem.l d0-d3/a0-a3,-(sp)
        moveq   #MT_SUSJB,d0
        moveq   #-1,d1
        moveq   #1,d3
        sub.l   a1,a1
        trap    #1
        movem.l (sp)+,d0-d3/a0-a3
        rts

wait_esc:                       ; wait until ESC is pressed and released
.down   bsr.s   frame
        bsr     readkeys
        btst    #K_ESC,d0
        beq.s   .down
.up     bsr.s   frame
        bsr     readkeys
        btst    #K_ESC,d0
        bne.s   .up
        rts

;=====================================================================
; Screen
;=====================================================================
cls:                            ; whole screen black
        lea     SCREEN,a0
        move.w  #32768/16-1,d0
.l      clr.l   (a0)+
        clr.l   (a0)+
        clr.l   (a0)+
        clr.l   (a0)+
        dbra    d0,.l
        rts

; fill_rect: d0 = x in words, d1 = y, d2 = width in words, d3 = height,
;            d4 = colour 0-7
fill_rect:
        movem.l d0-d5/a0-a1,-(sp)
        lea     colw(pc),a1
        add.w   d4,d4
        move.w  0(a1,d4.w),d4
        lea     SCREEN,a0
        mulu    #LINEB,d1
        add.l   d1,a0
        add.w   d0,d0
        add.w   d0,a0
        subq.w  #1,d2
        subq.w  #1,d3
.row    move.l  a0,a1
        move.w  d2,d5
.col    move.w  d4,(a1)+
        dbra    d5,.col
        lea     LINEB(a0),a0
        dbra    d3,.row
        movem.l (sp)+,d0-d5/a0-a1
        rts

draw_frame:                     ; placeholder layout: viewport, panel, separator
        moveq   #0,d0
        moveq   #0,d1
        moveq   #VIEW_W,d2
        move.w  #VIEW_H,d3
        moveq   #C_BLACK,d4
        bsr.s   fill_rect
        moveq   #PANEL_X,d0
        moveq   #PANEL_W,d2
        moveq   #C_BLUE,d4
        bsr.s   fill_rect
        moveq   #0,d0
        move.w  #SEP_Y+3,d1
        moveq   #64,d2
        moveq   #2,d3
        moveq   #C_RED,d4
        bra.s   fill_rect

;=====================================================================
; Data
;=====================================================================
colw:   dc.w    $0000,$0055,$00aa,$00ff ; colour -> word of 4 pixels
        dc.w    $aa00,$aa55,$aaaa,$aaff ; (G = even bits high, R/B low)
kr1:    dc.b    9,1,0,0,0,0,1,2         ; IPC: KEYROW(1)
kr0:    dc.b    9,1,0,0,0,0,0,2         ; IPC: KEYROW(0)
newline: dc.b   10
        even
devices: dc.b   'win1_flp1_mdv1_'
        even
txtname: qstr   'hum_txt'
msgname: qstr   'con_512x120a0x136'
notext: qstr    'hum_txt missing'

        include 'textid.inc'
