;=====================================================================
; Skills: the healer's skills and moss for everybody (included by hum.asm)
;
; Mossfern (role healer): Moss Pack, Press and Hold (fight), Herb Chew,
; Starfolk Charm (fight), Gather (not in a fight). The other cats: Apply
; Moss, which only stops Scratch level bleeding (see STORY.md).
;=====================================================================
SK_MOSS_PACK equ 0              ; skill numbers = order of the texts
SK_PRESS     equ 1
SK_HERB      equ 2
SK_CHARM     equ 3
SK_GATHER    equ 4
SK_APPLY     equ 5
SK_POUNCE    equ 6              ; the hunter, in a fight, from the front row
PACK_HEAL    equ 3              ; hit points a Moss Pack gives
CHARM_ROUNDS equ 3              ; rounds of half damage
MOSS_FEN     equ 1              ; moss kinds (as i_value of the moss items)
MOSS_DRY     equ 2
MOSS_GLOW    equ 3

; skill_menu: a2 = cat using a skill -> d0 = skill, -1 = cancelled
;             (the list depends on its role and on v_fight)
skill_menu:
        movem.l d1-d2/a0-a1,-(sp)
        bsr     menu_clear
        lea     v_mitem(a5),a0
        lea     .other(pc),a1
        cmp.w   #T_ROLE_HUNTER,p_role(a2)
        bne.s   .nohunt
        tst.w   v_fight(a5)
        beq.s   .list
        lea     .hunt(pc),a1
        bra.s   .list
.nohunt cmp.w   #T_ROLE_HEALER,p_role(a2)
        bne.s   .list
        lea     .heal(pc),a1
        tst.w   v_fight(a5)
        beq.s   .list
        lea     .fight(pc),a1
.list   moveq   #0,d0
        move.b  (a1)+,d0
        bmi.s   .run
        move.b  d0,(a0)+
        add.w   #T_SK_MOSS_PACK,d0
        bsr     menu_addt
        bra.s   .list
.run    move.w  p_name(a2),d0
        bsr     text_get
        bsr     menu_run
        tst.w   d0
        bmi.s   .e
        lea     v_mitem(a5),a0
        move.b  0(a0,d0.w),d0
.e      movem.l (sp)+,d1-d2/a0-a1
        rts
.fight  dc.b    SK_MOSS_PACK,SK_PRESS,SK_HERB,SK_CHARM,-1
.heal   dc.b    SK_MOSS_PACK,SK_HERB,SK_GATHER,-1
.other  dc.b    SK_APPLY,-1
.hunt   dc.b    SK_POUNCE,SK_APPLY,-1
        even

; use_skill: d0 = skill, a2 = cat using it -> NE = done (a turn used)
;            asks on whom when the skill needs a target
use_skill:
        movem.l d1-d7/a0-a4,-(sp)
        move.w  d0,d7
        cmp.w   #SK_CHARM,d7
        beq     .charm
        cmp.w   #SK_GATHER,d7
        beq     .gather
        cmp.w   #SK_POUNCE,d7
        beq     .pounce
        move.w  #T_MENU_WHO,d0  ; the others need a cat to work on
        bsr     menu_cats       ; -> a3
        tst.w   d0
        bmi     .no
        tst.w   p_hp(a3)
        bgt.s   .alive
        move.w  #T_CANNOT_HELP,d0
        move.w  p_name(a3),d1
        bsr     name_msg
        bra     .no
.alive  cmp.w   #SK_MOSS_PACK,d7
        beq.s   .pack
        cmp.w   #SK_PRESS,d7
        beq     .press
        cmp.w   #SK_HERB,d7
        beq     .herb

        ; Apply Moss: stops Scratch only, any moss
        move.w  p_bleed(a3),d1
        beq     .noneed
        cmp.w   #1,d1
        bne     .weak
        lea     .any(pc),a0
        bsr     moss_take
        bmi     .nomoss
        move.w  #T_PRESSES_MOSS,d0
        move.w  p_name(a2),d1
        bsr     name_msg
        clr.w   p_bleed(a3)
        clr.w   p_press(a3)
        move.w  #T_BLEED_STOPS,d0
        bsr     msg_print
        bra     .done

.pack   lea     .forpoison(pc),a0 ; Moss Pack: the weakest moss that helps
        btst    #PF_POISON,p_flags+1(a3)
        beq.s   .p1
        move.w  #MOSS_GLOW,d0   ; poisoned: glowcap cures it, if there is any
        bsr     moss_has
        bne.s   .p3
.p1     lea     .fordeep(pc),a0
        cmp.w   #3,p_bleed(a3)
        beq.s   .p3
        lea     .any(pc),a0
        tst.w   p_bleed(a3)
        bne.s   .p3
        move.w  p_hp(a3),d0     ; no wound: only when hit points are missing
        cmp.w   p_hpmax(a3),d0
        bge     .noneed
.p3     bsr     moss_take       ; -> d0 = kind
        bmi     .weak
        move.w  d0,d6
        move.w  #T_MOSS_PACK,d0
        move.w  p_name(a2),d1
        bsr     name_msg
        tst.w   p_bleed(a3)
        beq.s   .p4
        clr.w   p_bleed(a3)
        clr.w   p_press(a3)
        move.w  #T_BLEED_STOPS,d0
        bsr     msg_print
.p4     move.w  p_hpbase(a3),p_hpmax(a3) ; a Deep Wound is healed too
        cmp.w   #MOSS_GLOW,d6
        bne.s   .p5
        bclr    #PF_POISON,p_flags+1(a3)
        beq.s   .p5
        move.w  #T_POISON_FADES,d0
        bsr     msg_print
.p5     add.w   #PACK_HEAL,p_hp(a3)
        move.w  p_hpmax(a3),d0
        cmp.w   p_hp(a3),d0
        bge.s   .p6
        move.w  d0,p_hp(a3)
.p6     move.w  #T_HEALED,d0
        move.w  p_name(a3),d1
        bsr     name_msg
        bra     .done

.press  move.w  p_bleed(a3),d0  ; Press and Hold: one level less until the
        beq     .noneed         ; fight is over, no moss needed
        subq.w  #1,p_bleed(a3)
        addq.w  #1,p_press(a3)
        move.w  #T_PRESS_HOLD,d0
        move.w  p_name(a2),d1
        bsr     name_msg
        move.w  #T_BLEED_SLOWS,d0
        tst.w   p_bleed(a3)
        bne.s   .pr1
        move.w  #T_BLEED_STOPS,d0
.pr1    bsr     msg_print
        bra     .done

.herb   btst    #PF_POISON,p_flags+1(a3) ; Herb Chew: one herb cures poison
        beq     .noneed
        move.w  #IT_HERB,d0
        bsr     pack_count
        bne.s   .h1
        move.w  #T_NO_HERB,d0
        bsr     msg_print
        bra     .no
.h1     bsr     pack_take
        move.w  #T_HERB_CHEW,d0
        move.w  p_name(a2),d1
        bsr     name_msg
        bclr    #PF_POISON,p_flags+1(a3)
        move.w  #T_POISON_FADES,d0
        bsr     msg_print
        bra     .done

.charm  tst.w   v_charmed(a5)   ; Starfolk Charm: once per fight
        beq.s   .c1
        move.w  #T_CHARM_USED,d0
        bsr     msg_print
        bra     .no
.c1     move.w  #1,v_charmed(a5)
        move.w  #CHARM_ROUNDS,v_charm(a5)
        move.w  #T_CHARM_ON,d0
        bsr     msg_print
        bra     .done

.gather move.w  v_pos(a5),d0    ; Gather: a spot in this cell, once
        moveq   #EV_GATHER,d1
        bsr     event_at
        cmpa.w  #0,a3
        beq.s   .g0
        bset    #0,EV_FLAGS(a3)
        beq.s   .g1
.g0     move.w  #T_FINDS_NOTHING,d0
        move.w  p_name(a2),d1
        bsr     name_msg
        bra     .done
.g1     moveq   #0,d0
        move.b  EV_PARAM(a3),d0 ; item
        moveq   #0,d1
        move.b  EV_PARAM+1(a3),d1 ; count
        bsr     pack_add
        bne.s   .gok
        bclr    #0,EV_FLAGS(a3) ; no room: the spot stays for later
        bsr     item_rec
        move.w  #T_PACK_FULL,d0
        cmp.w   #IK_MOSS,i_kind(a0)
        bne.s   .gf
        move.w  #T_MOSS_FULL,d0
.gf     bsr     msg_print
        bra     .no
.gok    bsr     item_rec
        move.w  #T_GATHERS_MOSS,d2
        cmp.w   #IK_MOSS,i_kind(a0)
        beq.s   .g2
        move.w  #T_FINDS_HERBS,d2
.g2     move.w  d2,d0
        move.w  p_name(a2),d1
        bsr     name_msg
        bra     .done

.pounce tst.w   p_row(a2)       ; Pounce: twice the damage, less often a
        beq.s   .pc             ; hit; only with room (from the front row)
        move.w  #T_NO_ROOM,d0
        move.w  p_name(a2),d1
        bsr     name_msg
        bra     .no
.pc     move.l  v_cetab(a5),a4
        move.w  #1,v_pounce(a5)
        bsr     cat_attack
        clr.w   v_pounce(a5)
        bra     .done

.noneed move.w  #T_NO_NEED,d0
        move.w  p_name(a3),d1
        bsr     name_msg
        bra.s   .no
.weak   bsr     moss_total      ; no moss at all, or only the wrong kind?
        bne.s   .wk
.nomoss move.w  #T_NO_MOSS,d0
        bsr     msg_print
        bra.s   .no
.wk     move.w  #T_MOSS_WEAK,d0
        bsr     msg_print
.no     movem.l (sp)+,d1-d7/a0-a4
        cmp.w   d0,d0           ; EQ: nothing done
        rts
.done   bsr     panel_show
        movem.l (sp)+,d1-d7/a0-a4
        moveq   #1,d0           ; NE
        rts
.any       dc.b MOSS_DRY,MOSS_FEN,MOSS_GLOW,0 ; moss kinds to try, in order
.fordeep   dc.b MOSS_FEN,MOSS_GLOW,0
.forpoison dc.b MOSS_GLOW,0
        even

; moss_take: a0 = moss kinds to try (zero-terminated), a2 = cat using it;
;            one piece from that cat, else from the others
;            -> d0 = kind taken, MI = none of these kinds
moss_take:
        movem.l d1/a0-a1/a3,-(sp)
.kind   moveq   #0,d0
        move.b  (a0)+,d0
        beq.s   .none
        move.w  d0,d1
        subq.w  #1,d1
        add.w   d1,d1           ; offset from p_fen
        lea     p_fen(a2),a1    ; the user's own moss first
        tst.w   0(a1,d1.w)
        bne.s   .take
        lea     v_party(a5),a3  ; then any other cat's
        moveq   #NPARTY-1,d0
.cat    lea     p_fen(a3),a1
        tst.w   0(a1,d1.w)
        bne.s   .take1
        lea     p_size(a3),a3
        dbra    d0,.cat
        bra.s   .kind
.take1  move.w  d1,d0
        lsr.w   #1,d0
        addq.w  #1,d0
.take   subq.w  #1,0(a1,d1.w)
        move.w  d1,d0
        lsr.w   #1,d0
        addq.w  #1,d0           ; kind (PL)
        bra.s   .e
.none   moveq   #-1,d0
.e      movem.l (sp)+,d1/a0-a1/a3
        tst.w   d0
        rts

; moss_has: d0 = moss kind -> NE if any cat carries it
moss_has:
        movem.l d0-d1/a0,-(sp)
        subq.w  #1,d0
        add.w   d0,d0
        moveq   #0,d1
        lea     v_party+p_fen(a5),a0
        add.w   d0,a0
        moveq   #NPARTY-1,d0
.l      add.w   (a0),d1
        lea     p_size(a0),a0
        dbra    d0,.l
        tst.w   d1
        movem.l (sp)+,d0-d1/a0  ; (keeps the flags)
        rts

; moss_total: -> NE if the party carries any moss at all
moss_total:
        movem.l d0-d1/a0,-(sp)
        moveq   #0,d1
        lea     v_party(a5),a0
        moveq   #NPARTY-1,d0
.l      add.w   p_fen(a0),d1
        add.w   p_dry(a0),d1
        add.w   p_glow(a0),d1
        lea     p_size(a0),a0
        dbra    d0,.l
        tst.w   d1
        movem.l (sp)+,d0-d1/a0
        rts
