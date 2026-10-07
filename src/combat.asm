;=====================================================================
; Combat (included by hum.asm)
;
; Turn order by speed, highest first; on equal speed the cats act before
; the enemies. A cat chooses Attack, Defend or Flee in a small menu in
; the viewport. Front row cats are attacked more often; back row cats
; deal half damage. Bleeding and poison cost hit points every round.
;=====================================================================
NFOE      equ   9               ; enemies per group at most
CMB_PAUSE equ   25              ; frames after a combat message
FRONT_PCT equ   75              ; chance that an enemy aims at the front row
WOUND_PCT equ   35              ; chance that a hit makes bleed / poisons
GUARD_DEF equ   3               ; extra defence while keeping guard
MENU_Y    equ   VIEW_H-4*LINE_H ; combat menu: first line
MENU_W    equ   11              ; width in words
CM_ATTACK equ   0
CM_DEFEND equ   1
CM_FLEE   equ   2
CM_COUNT  equ   3
CE_VICTORY equ  1               ; v_cend
CE_FLED   equ   2

; combat: a3 = enemy group next to the party, the party faces it
combat:
        movem.l d0-d7/a0-a4,-(sp)
        move.l  a3,v_cgrp(a5)
        lea     enemytab(pc),a4
        moveq   #0,d0
        move.b  G_TYPE(a3),d0
        mulu    #e_size,d0
        add.w   d0,a4
        move.l  a4,v_cetab(a5)
        lea     v_cfoe(a5),a0   ; hit points of every enemy
        moveq   #0,d1
        move.b  G_COUNT(a3),d1
        moveq   #NFOE-1,d0
.init   clr.w   (a0)
        tst.w   d1
        beq.s   .in1
        move.w  e_hp(a4),(a0)
        subq.w  #1,d1
.in1    addq.l  #2,a0
        dbra    d0,.init
        clr.w   v_cend(a5)
        lea     v_party(a5),a0
        moveq   #NPARTY-1,d0
.g0     clr.w   p_guard(a0)
        lea     p_size(a0),a0
        dbra    d0,.g0
        bsr     foes_draw

.round  clr.w   v_cskip(a5)
        moveq   #31,d7          ; speed, highest first
.speed  moveq   #0,d6           ; cats with this speed
        lea     v_party(a5),a2
.cat    tst.w   v_cskip(a5)
        bne.s   .ncat
        cmp.w   p_spd(a2),d7
        bne.s   .ncat
        tst.w   p_hp(a2)
        ble.s   .ncat
        bsr     cat_turn
        tst.w   v_cend(a5)
        bne.s   .done
.ncat   lea     p_size(a2),a2
        addq.w  #1,d6
        cmp.w   #NPARTY,d6
        blo.s   .cat
        move.l  v_cetab(a5),a4  ; then the enemies with this speed
        cmp.w   e_spd(a4),d7
        bne.s   .nfoe
        bsr     foes_turn
.nfoe   dbra    d7,.speed
        bsr     wound_tick      ; end of the round: bleeding, poison
        bsr     party_check
        bra.s   .round

.done   clr.w   v_cact(a5)
        cmp.w   #CE_VICTORY,v_cend(a5)
        bne.s   .e
        bsr     victory
.e      bsr     panel_show
        movem.l (sp)+,d0-d7/a0-a4
        rts

; cat_turn: a2 = cat, d6 = its index
cat_turn:
        movem.l d0-d7/a0-a4,-(sp)
        clr.w   p_guard(a2)
        move.w  d6,d0
        addq.w  #1,d0
        move.w  d0,v_cact(a5)   ; highlighted in the panel
        bsr     panel_show
        move.l  v_cetab(a5),a4
.ask    bsr     combat_menu     ; -> d0
        cmp.w   #CM_DEFEND,d0
        beq.s   .guard
        cmp.w   #CM_FLEE,d0
        beq.s   .flee
        bsr     cat_attack
        bra     .e
.guard  move.w  #1,p_guard(a2)
        moveq   #T_DEFENDS,d0
        move.w  p_name(a2),d1
        bsr     name_msg
        bra     .e
.flee   tst.w   e_boss(a4)      ; no way out from a mini-boss
        bne.s   .cannot
        move.w  v_dir(a5),d0    ; the cell behind the party must be free
        add.w   d0,d0
        lea     doff(pc),a0
        move.w  v_pos(a5),d5
        sub.w   0(a0,d0.w),d5
        lea     v_map(a5),a0
        btst    #CELL_GROUP,0(a0,d5.w)
        bne.s   .cannot
        moveq   #CELL_TYPE,d0
        and.b   0(a0,d5.w),d0
        lea     celltab(pc),a0
        btst    #0,0(a0,d0.w)   ; CF_BLOCK
        bne.s   .cannot
        move.w  p_spd(a2),d1    ; chance 50 % + 10 % per speed above the enemy
        sub.w   e_spd(a4),d1
        muls    #10,d1
        add.w   #50,d1
        moveq   #10,d2
        moveq   #90,d3
        bsr     clamp
        bsr     rand100
        cmp.w   d1,d0
        bhs.s   .fail
        move.w  d5,v_pos(a5)
        lea     v_map(a5),a0
        bset    #CELL_SEEN,0(a0,d5.w)
        move.w  #CE_FLED,v_cend(a5)
        moveq   #T_FLEES,d0
        bsr     msg_print
        bra.s   .e
.fail   move.w  #1,v_cskip(a5)  ; the enemies get the rest of the round
        moveq   #T_FLEE_FAILS,d0
        bsr     msg_print
        bra.s   .e
.cannot moveq   #T_CANNOT_FLEE,d0
        bsr     msg_print
        bra     .ask
.e      bsr     pause
        movem.l (sp)+,d0-d7/a0-a4
        rts

; cat_attack: a2 = cat, a4 = enemy type; the first enemy still up
cat_attack:
        moveq   #T_ATTACKS,d0
        move.w  p_name(a2),d1
        bsr     name_msg
        bsr     pause
        lea     v_cfoe(a5),a1
.find   tst.w   (a1)+
        beq.s   .find
        subq.l  #2,a1           ; a1 = its hit points
        move.w  p_atk(a2),d1    ; chance 75 % + 5 % per attack above defence
        sub.w   e_def(a4),d1
        muls    #5,d1
        add.w   #75,d1
        moveq   #20,d2
        moveq   #95,d3
        bsr     clamp
        bsr     rand100
        cmp.w   d1,d0
        bhs.s   .miss
        move.w  p_atk(a2),d1    ; damage 1 + random(attack) - defence/2
        bsr     randn
        addq.w  #1,d0
        move.w  e_def(a4),d1
        lsr.w   #1,d1
        sub.w   d1,d0
        tst.w   p_row(a2)       ; back row: half
        beq.s   .min
        addq.w  #1,d0
        lsr.w   #1,d0
.min    cmp.w   #1,d0
        bge.s   .dmg
        moveq   #1,d0
.dmg    move.w  d0,d2
        sub.w   d2,(a1)
        moveq   #T_HIT_FOR,d0
        move.w  e_name(a4),d1
        bsr     name_num_msg
        tst.w   (a1)
        bgt.s   .draw
        clr.w   (a1)
        moveq   #T_FALLS,d0
        move.w  e_name(a4),d1
        bsr     name_msg
        bsr     foes_left
        bne.s   .draw
        move.w  #CE_VICTORY,v_cend(a5)
.draw   bra     foes_draw
.miss   moveq   #T_MISSES,d0
        move.w  p_name(a2),d1
        bra     name_msg

; foes_turn: every enemy still up attacks
foes_turn:
        movem.l d0-d7/a0-a4,-(sp)
        move.l  v_cetab(a5),a4
        lea     v_cfoe(a5),a0
        moveq   #NFOE-1,d7
.foe    tst.w   (a0)+
        beq.s   .nx
        bsr.s   foe_attack
.nx     dbra    d7,.foe
        movem.l (sp)+,d0-d7/a0-a4
        rts

; foe_attack: a4 = enemy type
foe_attack:
        movem.l d0-d7/a0-a4,-(sp)
        moveq   #T_ATTACKS,d0
        move.w  e_name(a4),d1
        bsr     name_msg
        bsr     pause
        bsr     pick_target     ; -> a3 = cat
        move.w  p_def(a3),d4
        tst.w   p_guard(a3)
        beq.s   .def
        addq.w  #GUARD_DEF,d4
.def    move.w  e_atk(a4),d1
        sub.w   d4,d1
        muls    #5,d1
        add.w   #75,d1
        moveq   #20,d2
        moveq   #95,d3
        bsr     clamp
        bsr     rand100
        cmp.w   d1,d0
        bhs     .miss
        move.w  e_atk(a4),d1
        bsr     randn
        addq.w  #1,d0
        move.w  p_def(a3),d1
        lsr.w   #1,d1
        sub.w   d1,d0
        tst.w   p_guard(a3)     ; keeping guard: half
        beq.s   .min
        addq.w  #1,d0
        lsr.w   #1,d0
.min    cmp.w   #1,d0
        bge.s   .dmg
        moveq   #1,d0
.dmg    move.w  d0,d2
        sub.w   d2,p_hp(a3)
        moveq   #T_HIT_FOR,d0
        move.w  p_name(a3),d1
        bsr     name_num_msg
        tst.w   p_hp(a3)
        ble.s   .fall
        move.w  e_bleed(a4),d2  ; the wound may bleed
        beq.s   .poison
        cmp.w   p_bleed(a3),d2
        bls.s   .poison
        bsr     rand100
        cmp.w   #WOUND_PCT,d0
        bhs.s   .poison
        move.w  d2,p_bleed(a3)
        moveq   #T_BLEEDING,d0
        move.w  p_name(a3),d1
        bsr     name_msg
.poison tst.w   e_poison(a4)    ; or poison
        beq.s   .fall
        btst    #0,p_flags+1(a3)
        bne.s   .fall
        bsr     rand100
        cmp.w   #WOUND_PCT,d0
        bhs.s   .fall
        bset    #0,p_flags+1(a3)
        moveq   #T_POISONED,d0
        move.w  p_name(a3),d1
        bsr     name_msg
.fall   bsr     fall_check
        bsr     panel_show
        bsr     party_check
        bra.s   .e
.miss   moveq   #T_MISSES,d0
        move.w  e_name(a4),d1
        bsr     name_msg
.e      bsr     pause
        movem.l (sp)+,d0-d7/a0-a4
        rts

; pick_target: -> a3 = a standing cat; the front row with FRONT_PCT %
pick_target:
        movem.l d0-d3/a0,-(sp)
        moveq   #0,d2           ; standing cats in front, behind
        moveq   #0,d3
        lea     v_party(a5),a0
        moveq   #NPARTY-1,d0
.cnt    tst.w   p_hp(a0)
        ble.s   .c1
        tst.w   p_row(a0)
        bne.s   .back
        addq.w  #1,d2
        bra.s   .c1
.back   addq.w  #1,d3
.c1     lea     p_size(a0),a0
        dbra    d0,.cnt
        moveq   #0,d1           ; row to aim at: 0 front, 1 back
        tst.w   d3
        beq.s   .row
        moveq   #1,d1
        tst.w   d2
        beq.s   .row
        bsr     rand100
        cmp.w   #FRONT_PCT,d0
        bhs.s   .row
        moveq   #0,d1
        move.w  d2,d3
.row    move.w  d1,-(sp)
        move.w  d3,d1           ; one of the cats in that row
        tst.w   (sp)
        bne.s   .r1
        move.w  d2,d1
.r1     bsr     randn
        move.w  (sp)+,d1
        lea     v_party(a5),a3
.find   tst.w   p_hp(a3)
        ble.s   .nx
        cmp.w   p_row(a3),d1
        bne.s   .nx
        subq.w  #1,d0
        bmi.s   .e
.nx     lea     p_size(a3),a3
        bra.s   .find
.e      movem.l (sp)+,d0-d3/a0
        rts

; victory: XP for every standing cat, ranks, the group is gone
victory:
        movem.l d0-d3/a0-a3,-(sp)
        moveq   #T_VICTORY,d0
        bsr     msg_print
        bsr     pause
        move.l  v_cgrp(a5),a3
        move.l  v_cetab(a5),a0
        moveq   #0,d3           ; XP = enemy XP x count
        move.b  G_COUNT(a3),d3
        mulu    e_xp(a0),d3
        lea     v_args(a5),a2
        move.l  d3,(a2)
        moveq   #T_GAIN_XP,d0
        bsr     msg_print
        lea     v_party(a5),a3
        moveq   #NPARTY-1,d2
.cat    tst.w   p_hp(a3)
        ble.s   .nx
        add.w   d3,p_xp(a3)
.rank   move.w  p_rank(a3),d0   ; next rank reached?
        cmp.w   #NRANKS-1,d0
        bhs.s   .nx
        add.w   d0,d0
        lea     rankxp+2(pc),a0
        move.w  0(a0,d0.w),d1
        cmp.w   p_xp(a3),d1
        bhi.s   .nx
        addq.w  #1,p_rank(a3)
        ifne    UP_HP
        addq.w  #UP_HP,p_hpbase(a3)
        addq.w  #UP_HP,p_hpmax(a3)
        addq.w  #UP_HP,p_hp(a3)
        endc
        ifne    UP_ATK
        addq.w  #UP_ATK,p_atk(a3)
        endc
        ifne    UP_DEF
        addq.w  #UP_DEF,p_def(a3)
        endc
        ifne    UP_SPD
        addq.w  #UP_SPD,p_spd(a3)
        endc
        move.w  p_name(a3),d0   ; "<cat> rises to <rank>."
        bsr     text_get
        move.l  a1,(a2)
        move.w  p_rank(a3),d0
        add.w   d0,d0
        lea     rankname(pc),a0
        move.w  0(a0,d0.w),d0
        bsr     text_get
        move.l  a1,4(a2)
        moveq   #T_RISES,d0
        bsr     msg_print
        bra.s   .rank
.nx     lea     p_size(a3),a3
        dbra    d2,.cat
        move.l  v_cgrp(a5),a3   ; the group is gone
        bset    #GF_GONE,G_FLAGS(a3)
        moveq   #0,d0
        move.b  G_Y(a3),d0
        lsl.w   #5,d0
        moveq   #0,d1
        move.b  G_X(a3),d1
        add.w   d1,d0
        lea     v_map(a5),a0
        bclr    #CELL_GROUP,0(a0,d0.w)
        movem.l (sp)+,d0-d3/a0-a3
        rts

; foes_left: -> d0 = enemies still up, NE if any
foes_left:
        movem.l d1/a0,-(sp)
        lea     v_cfoe(a5),a0
        moveq   #0,d0
        moveq   #NFOE-1,d1
.l      tst.w   (a0)+
        beq.s   .n
        addq.w  #1,d0
.n      dbra    d1,.l
        movem.l (sp)+,d1/a0
        tst.w   d0
        rts

; foes_draw: top left of the viewport: "<n> <enemies>" and a small bar
;            for every enemy of the group
foes_draw:
        movem.l d0-d7/a0-a4,-(sp)
        moveq   #0,d0
        moveq   #0,d1
        moveq   #2*NFOE+2,d2
        moveq   #LINE_H+5,d3
        moveq   #C_BLACK,d4
        bsr     fill_rect
        move.l  v_cetab(a5),a4
        bsr     foes_left
        beq     .e              ; all down: nothing to show
        lea     v_args(a5),a2
        move.l  d0,(a2)
        move.w  e_plural(a4),d1
        cmp.w   #1,d0
        bne.s   .pl
        move.w  e_name(a4),d1
.pl     move.w  d1,d0
        bsr     text_get
        move.l  a1,4(a2)
        moveq   #T_CMB_FOES,d0
        bsr     text_fmt
        moveq   #1,d0
        moveq   #1,d1
        moveq   #C_WHITE,d2
        moveq   #C_BLACK,d3
        bsr     pdraw
        move.l  v_cgrp(a5),a3
        moveq   #0,d7
        move.b  G_COUNT(a3),d7
        subq.w  #1,d7
        lea     v_cfoe(a5),a0
        moveq   #1,d0           ; column
.bar    move.w  (a0)+,d5
        beq.s   .nx
        moveq   #C_RED,d4       ; green above 1/2, yellow above 1/4
        move.w  d5,d6
        add.w   d6,d6
        cmp.w   e_hp(a4),d6
        bls.s   .y
        moveq   #C_GREEN,d4
        bra.s   .put
.y      add.w   d6,d6
        cmp.w   e_hp(a4),d6
        bls.s   .put
        moveq   #C_YEL,d4
.put    moveq   #LINE_H+1,d1
        moveq   #1,d2
        moveq   #2,d3
        bsr     fill_rect
.nx     addq.w  #2,d0
        dbra    d7,.bar
.e      movem.l (sp)+,d0-d7/a0-a4
        rts

; combat_menu: -> d0 = CM_ATTACK, CM_DEFEND or CM_FLEE (up/down choose,
;               space, enter or right confirm; joystick works the same)
combat_menu:
        movem.l d1-d7/a0-a3,-(sp)
        clr.w   v_csel(a5)
.draw   moveq   #0,d0           ; box bottom left in the viewport
        move.w  #MENU_Y-2,d1
        moveq   #MENU_W,d2
        moveq   #VIEW_H-MENU_Y+2,d3
        moveq   #C_BLACK,d4
        bsr     fill_rect
        move.w  v_cact(a5),d0   ; the cat whose turn it is
        subq.w  #1,d0
        mulu    #p_size,d0
        lea     v_party(a5),a0
        move.w  p_name(a0,d0.w),d0
        bsr     text_get
        moveq   #1,d0
        move.w  #MENU_Y,d1
        moveq   #C_YEL,d2
        moveq   #C_BLACK,d3
        bsr     pdraw
        moveq   #0,d6           ; the choices
.item   move.w  d6,d0
        add.w   #T_CMB_ATTACK,d0
        bsr     text_get
        moveq   #2,d0
        move.w  d6,d1
        addq.w  #1,d1
        mulu    #LINE_H,d1
        add.w   #MENU_Y,d1
        moveq   #C_CYAN,d2
        cmp.w   v_csel(a5),d6
        bne.s   .it1
        moveq   #C_WHITE,d2     ; the chosen one: white with a marker
        move.l  a1,-(sp)
        move.w  d1,-(sp)
        moveq   #T_CMB_MARK,d0
        bsr     text_get        ; (changes d1)
        move.w  (sp)+,d1
        moveq   #1,d0
        bsr     pdraw
        move.l  (sp)+,a1
        moveq   #2,d0
.it1    bsr     pdraw
        addq.w  #1,d6
        cmp.w   #CM_COUNT,d6
        blo.s   .item
.key    bsr     frame           ; wait for a newly pressed key
        bsr     readkeys
        move.w  v_pkeys(a5),d1
        not.w   d1
        and.w   d0,d1
        beq.s   .key
        btst    #K_UP,d1
        beq.s   .k1
        subq.w  #1,v_csel(a5)
        bpl     .draw
        move.w  #CM_COUNT-1,v_csel(a5)
        bra     .draw
.k1     btst    #K_DOWN,d1
        beq.s   .k2
        addq.w  #1,v_csel(a5)
        cmp.w   #CM_COUNT,v_csel(a5)
        blo     .draw
        clr.w   v_csel(a5)
        bra     .draw
.k2     and.w   #(1<<K_SPACE)|(1<<K_ENTER)|(1<<K_RIGHT),d1
        beq.s   .key
        move.w  v_csel(a5),d0
        movem.l (sp)+,d1-d7/a0-a3
        rts

; name_msg:     d0 = message id, d1 = text id of a name for %s
; name_num_msg: the same with d2 = number for %d
name_msg:
name_num_msg:
        movem.l d0-d2/a1-a2,-(sp)
        lea     v_args(a5),a2
        move.w  d0,-(sp)
        move.w  d1,d0
        bsr     text_get
        move.l  a1,(a2)
        ext.l   d2
        move.l  d2,4(a2)
        move.w  (sp)+,d0
        bsr     msg_print
        movem.l (sp)+,d0-d2/a1-a2
        rts

pause:  movem.l d0-d1,-(sp)     ; time to read a combat message
        moveq   #CMB_PAUSE-1,d1
.w      bsr     frame
        dbra    d1,.w
        movem.l (sp)+,d0-d1
        rts

; rand100: -> d0 = 0..99;  randn: d1 = n -> d0 = 0..n-1
rand100:
        move.l  d1,-(sp)
        moveq   #100,d1
        bsr.s   randn
        move.l  (sp)+,d1
        rts
randn:  bsr     rand
        mulu    d1,d0
        clr.w   d0
        swap    d0
        rts

; clamp: d1 limited to d2..d3
clamp:  cmp.w   d2,d1
        bge.s   .lo
        move.w  d2,d1
.lo     cmp.w   d3,d1
        ble.s   .hi
        move.w  d3,d1
.hi     rts
