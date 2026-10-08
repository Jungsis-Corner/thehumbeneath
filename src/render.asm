;=====================================================================
; First-person view (included by hum.asm)
;
; The wall set hum_wN (tools/gfxc.py) holds the floor/ceiling pattern,
; a draw list (far to near) and pre-drawn wall tiles. render builds a
; table of the cells in view, fills the view buffer with floor and
; ceiling, draws every list entry whose cell is a wall and copies the
; buffer to the screen in one go.
;=====================================================================

; walls_load:   d0 = wall set number   -> EQ = loaded into v_walls
; sprites_load: d0 = sprite set number -> EQ = loaded into v_sprites
walls_load:
        movem.l d1-d3/a0-a1,-(sp)
        lea     wsname(pc),a0
        lea     v_walls(a5),a1
        move.l  #WALLMAX,d2
        move.l  #HW_MAGIC,d3
        bra.s   set_load
sprites_load:
        movem.l d1-d3/a0-a1,-(sp)
        lea     ssname(pc),a0
        lea     v_walls(a5),a1  ; (v_sprites)
        add.l   #WALLMAX,a1
        move.l  #SPRMAX,d2
        move.l  #HS_MAGIC,d3
set_load:                       ; a0 = name 'hum_x0', a1 = buffer, d2 = size,
        movem.l d4/a2-a3,-(sp)  ; d3 = magic; file: magic.l, length.l, data
        lea     v_buf(a5),a2
        move.l  a2,a3
        moveq   #2+6-1,d1
.cp     move.b  (a0)+,(a3)+
        dbra    d1,.cp
        add.b   d0,-1(a3)       ; set number as the last digit
        lea     v_name(a5),a3
        move.l  a1,-(sp)
        bsr     fopen
        move.l  (sp)+,a1
        bne.s   .e
        moveq   #8,d4           ; magic and length first
        bsr     fread
        bne.s   .cl
        moveq   #-1,d0          ; wrong format: "not complete"
        cmp.l   (a1),d3
        bne.s   .cl
        move.l  4(a1),d4
        cmp.l   d2,d4
        bhi.s   .cl
        subq.l  #8,d4
        bls.s   .cl
        addq.l  #8,a1
        bsr     fread
.cl     move.l  d0,d4
        moveq   #IO_CLOSE,d0
        trap    #2
        move.l  d4,d0
.e      movem.l (sp)+,d4/a2-a3
        movem.l (sp)+,d1-d3/a0-a1
        tst.l   d0
        rts

clear_view:                     ; viewport on the screen black
        movem.l d0-d4,-(sp)
        moveq   #0,d0
        moveq   #0,d1
        moveq   #VIEW_W,d2
        move.w  #VIEW_H,d3
        moveq   #C_BLACK,d4
        bsr     fill_rect
        movem.l (sp)+,d0-d4
        rts

render:
        movem.l d0-d7/a0-a6,-(sp)
; --- view class of the cells in view: v_vtab[depth*VIEW_L + lateral+3]
        move.w  v_dir(a5),d0
        lsl.w   #2,d0
        lea     steps(pc),a0
        move.w  0(a0,d0.w),v_fdx(a5)
        move.w  2(a0,d0.w),v_fdy(a5)
        addq.w  #4,d0           ; right = next direction clockwise
        and.w   #15,d0
        move.w  0(a0,d0.w),v_rdx(a5)
        move.w  2(a0,d0.w),v_rdy(a5)
        move.w  v_pos(a5),d4
        moveq   #31,d5
        and.w   d4,d5           ; player x
        lsr.w   #5,d4           ; player y
        lea     v_vtab(a5),a0
        lea     v_map(a5),a1
        lea     cellvc(pc),a2
        moveq   #0,d7           ; depth
.dep    moveq   #-(VIEW_L/2),d6 ; lateral offset
.lat    move.w  d7,d0
        muls    v_fdx(a5),d0
        move.w  d6,d1
        muls    v_rdx(a5),d1
        add.w   d1,d0
        add.w   d5,d0           ; cell x
        move.w  d7,d1
        muls    v_fdy(a5),d1
        move.w  d6,d2
        muls    v_rdy(a5),d2
        add.w   d2,d1
        add.w   d4,d1           ; cell y
        moveq   #VC_WALL,d3     ; outside the map: wall
        cmp.w   #31,d0
        bhi.s   .put
        cmp.w   #31,d1
        bhi.s   .put
        lsl.w   #5,d1
        add.w   d0,d1
        moveq   #CELL_TYPE,d2
        and.b   0(a1,d1.w),d2
        move.b  0(a2,d2.w),d3
.put    move.b  d3,(a0)+
        addq.w  #1,d6
        cmp.w   #VIEW_L/2,d6
        ble.s   .lat
        addq.w  #1,d7
        cmp.w   #VIEW_D,d7
        blt.s   .dep
        lea     v_vtab(a5),a0   ; solid cells (wall, door) as bits: bit n = cell n
        moveq   #0,d0
        moveq   #0,d1
        moveq   #VIEW_D*VIEW_L-1,d2
.bits   move.b  (a0)+,d3
        cmp.b   #VC_WALL,d3
        beq.s   .b1
        cmp.b   #VC_DOOR,d3
        beq.s   .b1
        cmp.b   #VC_DECOA,d3    ; walls with a picture
        blo.s   .b0
.b1     bset    d1,d0
.b0     addq.w  #1,d1
        dbra    d2,.bits
        move.l  d0,v_vmask(a5)

; --- enemy groups and items in view: v_vgrp[cell] = enemy type + 1
;     (0 = none), bit 7 = an item lies there
        lea     v_vgrp(a5),a0
        moveq   #VIEW_D*VIEW_L-1,d0
.gclr   clr.b   (a0)+
        dbra    d0,.gclr
        move.w  v_map+LV_GROUPS(a5),d0
        lea     v_map(a5),a1
        lea     0(a1,d0.w),a1   ; group table
.grp    cmp.b   #G_END,G_X(a1)
        beq.s   .gend
        btst    #GF_GONE,G_FLAGS(a1)
        bne.s   .gnx
        move.b  G_X(a1),d0
        move.b  G_Y(a1),d1
        bsr     view_cell
        bmi.s   .gnx
        move.b  G_TYPE(a1),d0
        addq.b  #1,d0
        lea     v_vgrp(a5),a0
        or.b    d0,0(a0,d2.w)
.gnx    addq.l  #G_SIZE,a1
        bra.s   .grp
.gend   lea     v_map+LV_EVENT(a5),a1 ; items not taken yet
.itm    cmp.b   #EV_END,EV_X(a1)
        beq.s   .iend
        cmp.b   #EV_ITEM,EV_TYPE(a1)
        bne.s   .inx
        btst    #0,EV_FLAGS(a1)
        bne.s   .inx
        move.b  EV_X(a1),d0
        move.b  EV_Y(a1),d1
        bsr     view_cell
        bmi.s   .inx
        lea     v_vgrp(a5),a0
        bset    #7,0(a0,d2.w)
.inx    addq.l  #EV_SIZE,a1
        bra.s   .itm
.iend

; --- floor and ceiling: one pattern word per line
        lea     v_walls(a5),a3
        lea     v_vbuf(a5),a0
        lea     HW_BG(a3),a1
        move.w  #VIEW_H-1,d7
.bg     move.w  (a1)+,d0
        move.w  d0,d1
        swap    d0
        move.w  d1,d0
        moveq   #VIEW_W/8-1,d6
.bgl    move.l  d0,(a0)+
        move.l  d0,(a0)+
        move.l  d0,(a0)+
        move.l  d0,(a0)+
        dbra    d6,.bgl
        dbra    d7,.bg

; --- the floor picture: the second one when the party stands on an odd
;     cell, so the checkerboard of the floor stays put in the world
        move.w  v_pos(a5),d0
        move.w  d0,d1
        lsr.w   #5,d1
        add.w   d1,d0           ; x + y
        and.w   #1,d0
        lsl.w   #2,d0
        add.w   #HW_FLOOR,d0
        move.l  0(a3,d0.w),d0
        beq.s   .nofl
        lea     0(a3,d0.l),a1
        moveq   #0,d2
        bsr     draw_front
.nofl

; --- walls, doors, stairs, enemies, far to near. A wall entry is drawn
;     when its class mask has the view class of its cell, an enemy entry
;     when a group stands in the cell; then the occluder sets are checked.
        lea     HW_LIST(a3),a2
.next   moveq   #0,d0
        move.b  (a2)+,d0        ; cell
        cmp.b   #$ff,d0
        beq     .copy
        move.b  (a2)+,d1        ; kind
        move.w  (a2)+,d4        ; class mask
        move.w  (a2)+,d2        ; shift in words
        move.l  (a2)+,d3        ; tile offset (enemy: depth)
        lea     12(a2),a4       ; next entry
        cmp.b   #2,d1
        beq.s   .enemy
        lea     v_vtab(a5),a1
        move.b  0(a1,d0.w),d5   ; view class of the cell
        btst    d5,d4
        beq     .skip
        lea     0(a3,d3.l),a1   ; tile
        bra.s   .occl
.enemy  lea     v_vgrp(a5),a1
        tst.b   0(a1,d0.w)      ; an enemy or an item in this cell?
        beq     .skip
.occl   move.l  v_vmask(a5),d6
        moveq   #3-1,d7
.occ    move.l  (a2)+,d4        ; occluder set
        beq.s   .draw
        move.l  d4,d5
        and.l   d6,d5
        cmp.l   d4,d5
        beq     .skip           ; all walls: hidden
        dbra    d7,.occ
.draw   move.l  a4,a2
        tst.b   d1
        beq.s   .front
        cmp.b   #2,d1
        beq.s   .spr
        bsr     draw_side
        bra     .next
.front  bsr     draw_front
        bra     .next
.spr    lea     v_vgrp(a5),a1   ; d0 = cell, d3 = depth, d2 = shift
        moveq   #0,d5
        move.b  0(a1,d0.w),d5
        bclr    #7,d5
        beq.s   .foe
        movem.l d2-d3/d5,-(sp)  ; an item: the bundle first
        moveq   #NENEMY,d4
        bsr.s   .pic
        beq.s   .nopic
        bsr     draw_sprite
.nopic  movem.l (sp)+,d2-d3/d5
.foe    tst.w   d5              ; then an enemy standing on it
        beq     .next
        move.w  d5,d4
        subq.w  #1,d4
        bsr.s   .pic
        beq     .next
        bsr     draw_sprite
        bra     .next
.pic    move.w  d4,d5           ; d4 = picture, d3 = depth -> a1, EQ = none
        mulu    #12,d5
        move.w  d3,d4
        subq.w  #1,d4
        lsl.w   #2,d4
        add.w   d4,d5
        lea     v_walls(a5),a1  ; (v_sprites+HS_TABLE)
        add.l   #WALLMAX+HS_TABLE,a1
        move.l  0(a1,d5.w),d4
        beq.s   .pe
        lea     v_walls(a5),a1  ; (v_sprites)
        add.l   #WALLMAX,a1
        add.l   d4,a1
.pe     rts
.skip   move.l  a4,a2
        bra     .next

; --- view buffer to the screen
.copy   lea     v_vbuf(a5),a0
        lea     SCREEN,a1
        move.w  #VIEW_H-1,d7
.cl     moveq   #VIEW_W/8-1,d6
.cw     move.l  (a0)+,(a1)+
        move.l  (a0)+,(a1)+
        move.l  (a0)+,(a1)+
        move.l  (a0)+,(a1)+
        dbra    d6,.cw
        lea     LINEB-VIEWB(a1),a1
        dbra    d7,.cl
        movem.l (sp)+,d0-d7/a0-a6
        rts

; view_cell: d0.b = x, d1.b = y of a map cell, d4 = player y, d5 = player x
;            -> d2 = cell in the view table, MI = not in view
;            (uses d0-d3 and v_fdx..v_rdy of the current render)
view_cell:
        and.w   #$ff,d0
        and.w   #$ff,d1
        sub.w   d5,d0           ; offset from the player: dx, dy
        sub.w   d4,d1
        move.w  d0,d2           ; depth = dx*fdx + dy*fdy
        muls    v_fdx(a5),d2
        move.w  d1,d3
        muls    v_fdy(a5),d3
        add.w   d3,d2
        bmi.s   .out
        cmp.w   #VIEW_D,d2
        bge.s   .out
        muls    v_rdx(a5),d0    ; lateral = dx*rdx + dy*rdy
        muls    v_rdy(a5),d1
        add.w   d1,d0
        add.w   #VIEW_L/2,d0
        cmp.w   #VIEW_L,d0
        bhs.s   .out
        mulu    #VIEW_L,d2
        add.w   d0,d2           ; (PL)
        rts
.out    moveq   #-1,d2
        rts

; draw_front: a1 = tile, d2 = shift in words; clipped to the viewport
; Front tiles have an even width and shifts are even, so the visible
; part is copied in long words. (uses d0-d7, a0, a6; keeps a2-a4)
draw_front:
        movem.w (a1),d4-d7      ; x0, y0, w, h
        add.w   d2,d4           ; x = x0 + shift
        moveq   #0,d0           ; first visible column c0
        tst.w   d4
        bpl.s   .l
        move.w  d4,d0
        neg.w   d0
.l      move.w  d6,d1           ; last column + 1: c1
        move.w  d4,d3
        add.w   d6,d3
        sub.w   #VIEW_W,d3
        ble.s   .r
        sub.w   d3,d1
.r      sub.w   d0,d1           ; n = c1 - c0
        ble.s   .e
        lea     v_vbuf(a5),a0
        mulu    #VIEWB,d5
        add.l   d5,a0
        add.w   d0,d4
        add.w   d4,d4
        add.w   d4,a0           ; destination of the first word
        move.w  #VIEWB,d2       ; from the end of a line to the next one
        sub.w   d1,d2
        sub.w   d1,d2
        lsr.w   #1,d1           ; long words
        subq.w  #1,d1
        add.w   d0,d0           ; c0 in bytes
        subq.w  #1,d7
        moveq   #8,d6           ; offset of the first row pointer
.row    moveq   #0,d3
        move.w  0(a1,d6.w),d3
        addq.w  #2,d6
        add.l   d0,d3
        lea     0(a1,d3.l),a6
        move.w  d1,d5
.col    move.l  (a6)+,(a0)+
        dbra    d5,.col
        add.w   d2,a0
        dbra    d7,.row
.e      rts

; draw_sprite: a1 = enemy picture, d2 = shift in words; masked like a side
; tile, clipped like a front tile (uses d0-d7, a0, a6; keeps a2-a4).
; v_fx: FX_HIT draws it white, FX_ATTACK red and ATK_DROP lines lower
; (it leaps at the party)
FX_HIT    equ   1
FX_ATTACK equ   2
ATK_DROP  equ   6
FX_WHITE  equ   $aaff           ; a word of 4 white pixels
FX_RED    equ   $00aa           ; ... of 4 red pixels
draw_sprite:
        movem.w (a1),d4-d7      ; x0, y0, w, h
        cmp.w   #FX_ATTACK,v_fx(a5)
        bne.s   .y
        addq.w  #ATK_DROP,d5
        move.w  #VIEW_H,d0      ; cut off at the bottom of the view
        sub.w   d5,d0
        cmp.w   d0,d7
        bls.s   .y
        move.w  d0,d7
.y        add.w   d2,d4           ; x = x0 + shift
        moveq   #0,d0           ; first visible column c0
        tst.w   d4
        bpl.s   .l
        move.w  d4,d0
        neg.w   d0
.l      move.w  d6,d1           ; last column + 1: c1
        move.w  d4,d3
        add.w   d6,d3
        sub.w   #VIEW_W,d3
        ble.s   .r
        sub.w   d3,d1
.r      sub.w   d0,d1           ; n = c1 - c0
        ble.s   .e
        lea     v_vbuf(a5),a0
        mulu    #VIEWB,d5
        add.l   d5,a0
        add.w   d0,d4
        add.w   d4,d4
        add.w   d4,a0           ; destination of the first word
        move.w  #VIEWB,d2       ; from the end of a line to the next one
        sub.w   d1,d2
        sub.w   d1,d2
        subq.w  #1,d1
        lsl.w   #2,d0           ; c0 in bytes (mask and data per word)
        subq.w  #1,d7
        moveq   #8,d6           ; offset of the first row pointer
.row    moveq   #0,d3
        move.w  0(a1,d6.w),d3
        addq.w  #2,d6
        add.l   d0,d3
        lea     0(a1,d3.l),a6
        move.w  d1,d5
        tst.w   v_fx(a5)
        bne.s   .fx
.col    move.w  (a6)+,d4
        and.w   d4,(a0)
        move.w  (a6)+,d4
        or.w    d4,(a0)+
        dbra    d5,.col
.nx     add.w   d2,a0
        dbra    d7,.row
.e      rts
.fx     move.l  d0,-(sp)        ; (d0 = c0, needed for every row)
        move.w  #FX_WHITE,d0    ; one colour where the picture is
        cmp.w   #FX_HIT,v_fx(a5)
        beq.s   .fc
        move.w  #FX_RED,d0
.fc     move.w  (a6)+,d4
        and.w   d4,(a0)
        not.w   d4
        and.w   d0,d4
        or.w    d4,(a0)+
        addq.l  #2,a6
        dbra    d5,.fc
        move.l  (sp)+,d0
        bra.s   .nx

; draw_side: a1 = side tile, one run of words per line
; (uses d0-d7, a0, a4, a6; keeps a2-a3)
draw_side:
        movem.w (a1),d4-d7      ; x0, y0, w, h
        lea     v_vbuf(a5),a0
        mulu    #VIEWB,d5
        add.l   d5,a0
        add.w   d4,d4
        add.w   d4,a0           ; start of the first line
        subq.w  #1,d7
        moveq   #8,d4           ; offset of the first row pointer
.row    moveq   #0,d3
        move.w  0(a1,d4.w),d3
        addq.w  #2,d4
        lea     0(a1,d3.l),a6
        move.w  (a6)+,d0        ; skip
        move.w  (a6)+,d5        ; n
        beq.s   .nx
        move.l  (a6)+,d2        ; lmask, rmask
        add.w   d0,d0
        lea     0(a0,d0.w),a4
        swap    d2
        move.w  (a4),d0         ; first word through lmask
        and.w   d2,d0
        or.w    (a6)+,d0
        move.w  d0,(a4)+
        subq.w  #2,d5
        bmi.s   .nx             ; only one word
        beq.s   .last
        subq.w  #1,d5
.mid    move.w  (a6)+,(a4)+
        dbra    d5,.mid
.last   swap    d2              ; last word through rmask
        move.w  (a4),d0
        and.w   d2,d0
        or.w    (a6)+,d0
        move.w  d0,(a4)
.nx     lea     VIEWB(a0),a0
        dbra    d7,.row
        rts

; foe_fx: d0 = FX_HIT or FX_ATTACK, d1 = frames: the enemies in the view
;         drawn that way for a moment, then as before
foe_fx:
        movem.l d0-d1,-(sp)
        move.w  d0,v_fx(a5)
        bsr     render
        subq.w  #1,d1
.w      bsr     frame
        dbra    d1,.w
        clr.w   v_fx(a5)
        bsr     render
        bra.s   fx_foes

; view_shake: the view (v_vbuf) jumps right and left and back: a blow
view_shake:
        movem.l d0-d1,-(sp)
        moveq   #SHAKE_W,d0
        bsr.s   view_copy
        moveq   #1,d1
.a      bsr     frame
        dbra    d1,.a
        moveq   #-SHAKE_W,d0
        bsr.s   view_copy
        moveq   #1,d1
.b      bsr     frame
        dbra    d1,.b
        moveq   #0,d0
        bsr.s   view_copy
fx_foes tst.w   v_fight(a5)     ; in a fight: the enemy line again
        beq.s   .e
        bsr     foes_draw
.e      movem.l (sp)+,d0-d1
        rts
SHAKE_W equ     1               ; words

; view_copy: d0 = shift in words (+ right, - left): v_vbuf to the screen,
;            the uncovered edge black
view_copy:
        movem.l d0-d3/a0-a1,-(sp)
        lea     v_vbuf(a5),a0
        lea     SCREEN,a1
        move.w  #VIEW_H-1,d3
.row    moveq   #VIEW_W-1,d1    ; destination column
        moveq   #0,d2
.col    move.w  d1,d2
        sub.w   d0,d2           ; source column
        bmi.s   .blk
        cmp.w   #VIEW_W,d2
        bhs.s   .blk
        add.w   d2,d2
        move.w  0(a0,d2.w),d2
        bra.s   .put
.blk    moveq   #0,d2
.put    move.w  d1,-(sp)
        add.w   d1,d1
        move.w  d2,0(a1,d1.w)
        move.w  (sp)+,d1
        dbra    d1,.col
        lea     VIEWB(a0),a0
        lea     LINEB(a1),a1
        dbra    d3,.row
        movem.l (sp)+,d0-d3/a0-a1
        rts
