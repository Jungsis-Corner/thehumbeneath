;=====================================================================
; HUD: party panel with the 4 px font (included by hum.asm)
;
; The panel (x 192-255, y 0-127) is drawn straight onto the screen:
; per cat name, role, hit points and a bar, then the facing at the
; bottom. In DEBUG builds a line with position and render time follows.
;=====================================================================
PNL_COL   equ   PANEL_X+1       ; text column (4 px margin)
PNL_Y0    equ   2               ; first line of the first cat
PNL_CAT   equ   28              ; lines per cat
LINE_H    equ   FONT_ROWS+1     ; text line pitch
BAR_W     equ   14              ; hit point bar: segments of 4 px
BAR_H     equ   3
COMPASS_Y equ   PNL_Y0+NPARTY*PNL_CAT
DEBUG_Y   equ   COMPASS_Y+LINE_H

panel_show:
        movem.l d0-d7/a0-a3,-(sp)
        moveq   #PANEL_X,d0
        moveq   #0,d1
        moveq   #PANEL_W,d2
        move.w  #VIEW_H,d3
        moveq   #C_BLUE,d4
        bsr     fill_rect
        lea     v_party(a5),a3
        lea     v_args(a5),a2
        moveq   #PNL_Y0,d6
        moveq   #NPARTY-1,d7
.cat    move.w  p_name(a3),d0   ; name
        bsr     text_get
        moveq   #PNL_COL,d0
        move.w  d6,d1
        moveq   #C_WHITE,d2
        moveq   #C_BLUE,d3
        bsr     pdraw
        move.w  p_role(a3),d0   ; role
        bsr     text_get
        moveq   #PNL_COL,d0
        move.w  d6,d1
        addq.w  #LINE_H,d1
        moveq   #C_CYAN,d2
        bsr     pdraw
        moveq   #0,d0           ; hit points
        move.w  p_hp(a3),d0
        move.l  d0,(a2)
        move.w  p_hpmax(a3),d0
        move.l  d0,4(a2)
        moveq   #T_PANEL_HP,d0
        bsr     text_fmt
        moveq   #PNL_COL,d0
        move.w  d6,d1
        add.w   #2*LINE_H,d1
        moveq   #C_WHITE,d2
        bsr     pdraw
        move.w  d6,d1           ; bar
        add.w   #3*LINE_H+1,d1
        move.w  p_hp(a3),d2
        move.w  p_hpmax(a3),d3
        bsr     hp_bar
        add.w   #PNL_CAT,d6
        lea     p_size(a3),a3
        dbra    d7,.cat

        move.w  v_dir(a5),d0    ; compass
        add.w   #T_COMPASS_N,d0
        bsr     text_get
        moveq   #PNL_COL,d0
        move.w  #COMPASS_Y,d1
        moveq   #C_YEL,d2
        moveq   #C_BLUE,d3
        bsr     pdraw
        ifne    DEBUG
        move.w  v_pos(a5),d0
        moveq   #31,d1
        and.w   d0,d1
        move.l  d1,(a2)         ; x
        lsr.w   #5,d0
        move.l  d0,4(a2)        ; y
        moveq   #0,d0
        move.w  v_rtime(a5),d0
        move.l  d0,8(a2)        ; frames of the last render
        moveq   #T_DEBUG_POS,d0
        bsr     text_fmt
        moveq   #PNL_COL,d0
        move.w  #DEBUG_Y,d1
        moveq   #C_WHITE,d2
        bsr     pdraw
        endc
        movem.l (sp)+,d0-d7/a0-a3
        rts

; hp_bar: d0 = column, d1 = y, d2 = hit points, d3 = maximum
;         green above 1/2, yellow above 1/4, red below
hp_bar:
        movem.l d0-d6,-(sp)
        moveq   #C_RED,d4
        moveq   #0,d6           ; filled segments
        tst.w   d2
        ble.s   .draw
        move.w  d2,d5
        add.w   d5,d5
        cmp.w   d3,d5
        bls.s   .c1
        moveq   #C_GREEN,d4
        bra.s   .c2
.c1     add.w   d5,d5
        cmp.w   d3,d5
        bls.s   .c2
        moveq   #C_YEL,d4
.c2     mulu    #BAR_W,d2       ; segments, rounded up
        moveq   #0,d5
        move.w  d3,d5
        subq.l  #1,d5
        add.l   d5,d2
        divu    d3,d2
        move.w  d2,d6
        cmp.w   #BAR_W,d6
        bls.s   .draw
        moveq   #BAR_W,d6
.draw   moveq   #BAR_H,d3
        move.w  d6,d2
        beq.s   .rest
        bsr     fill_rect
.rest   add.w   d6,d0
        moveq   #BAR_W,d2
        sub.w   d6,d2
        beq.s   .e
        moveq   #C_BLACK,d4
        bsr     fill_rect
.e      movem.l (sp)+,d0-d6
        rts

; pdraw: a1 = zero-terminated string, d0 = column (screen word), d1 = y,
;        d2 = ink, d3 = paper; one character per word, stops at the
;        right screen edge
pdraw:
        movem.l d0-d7/a0-a3,-(sp)
        lea     colw(pc),a2
        add.w   d2,d2
        move.w  0(a2,d2.w),d2   ; ink word
        add.w   d3,d3
        move.w  0(a2,d3.w),d3   ; paper word
        moveq   #LINEB/2,d7
        sub.w   d0,d7           ; characters until the right edge
        lea     SCREEN,a0
        mulu    #LINEB,d1
        add.l   d1,a0
        add.w   d0,d0
        add.w   d0,a0
        lea     fontexp(pc),a3
.ch     moveq   #0,d4
        move.b  (a1)+,d4
        beq.s   .e
        subq.w  #1,d7
        bmi.s   .e
        sub.w   #32,d4
        bcs.s   .unk
        cmp.w   #95,d4
        blo.s   .ok
.unk    moveq   #'?'-32,d4
.ok     mulu    #FONT_ROWS,d4
        lea     font(pc),a2
        add.w   d4,a2
        moveq   #FONT_ROWS-1,d5
.row    moveq   #0,d4
        move.b  (a2)+,d4
        add.w   d4,d4
        move.w  0(a3,d4.w),d4   ; pixel mask of the glyph row
        move.w  d4,d6
        and.w   d2,d6
        not.w   d4
        and.w   d3,d4
        or.w    d6,d4
        move.w  d4,(a0)
        lea     LINEB(a0),a0
        dbra    d5,.row
        move.w  d3,(a0)         ; empty line below
        lea     2-FONT_ROWS*LINEB(a0),a0
        bra.s   .ch
.e      movem.l (sp)+,d0-d7/a0-a3
        rts
