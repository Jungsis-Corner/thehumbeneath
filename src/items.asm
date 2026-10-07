;=====================================================================
; Items, the party pack, gear and menus (included by hum.asm)
;
; The pack holds PACK_SLOTS kinds of items with a count each. Moss is
; not kept in the pack but in the cats' own moss (see STORY.md). Each
; cat can wear one piece of gear.
;=====================================================================

; item_rec: d0 = item -> a0 = its itemtab entry
item_rec:
        move.l  d0,-(sp)
        lea     itemtab-i_size(pc),a0
        mulu    #i_size,d0
        add.w   d0,a0
        move.l  (sp)+,d0
        rts

; pack_add: d0 = item, d1 = count -> d1 = count taken, NE = nothing taken
pack_add:
        movem.l d0/d2-d3/a0-a1,-(sp)
        bsr.s   item_rec
        cmp.w   #IK_MOSS,i_kind(a0)
        bne.s   .pack
        move.w  i_value(a0),d2
        bsr     moss_add
        bra.s   .e
.pack   lea     v_pack(a5),a1   ; the same kind already in the pack?
        moveq   #PACK_SLOTS-1,d2
.same   cmp.b   (a1),d0
        beq.s   .add
        addq.l  #2,a1
        dbra    d2,.same
        lea     v_pack(a5),a1   ; else an empty slot
        moveq   #PACK_SLOTS-1,d2
.free   tst.b   (a1)
        beq.s   .new
        addq.l  #2,a1
        dbra    d2,.free
        moveq   #0,d1           ; pack full
        bra.s   .e
.new    move.b  d0,(a1)
        clr.b   1(a1)
.add    moveq   #0,d3
        move.b  1(a1),d3
        add.w   d1,d3
        cmp.w   #PACK_MAX,d3
        bls.s   .ok
        moveq   #PACK_MAX,d3
.ok     move.b  d3,1(a1)
.e      movem.l (sp)+,d0/d2-d3/a0-a1
        tst.w   d1
        rts

; moss_add: d2 = moss kind (1 fen, 2 dry, 3 glowcap), d1 = count
;           -> d1 = count taken; each piece goes to the cat with most room
moss_add:
        movem.l d0/d2-d6/a0-a1,-(sp)
        move.w  d1,d6           ; still to place
        moveq   #0,d1           ; placed
        subq.w  #1,d2
        add.w   d2,d2           ; offset from p_fen
.piece  tst.w   d6
        beq.s   .e
        sub.l   a1,a1           ; cat with the most room
        moveq   #0,d5
        lea     v_party(a5),a0
        moveq   #NPARTY-1,d4
.cat    move.w  p_mosscap(a0),d3
        sub.w   p_fen(a0),d3
        sub.w   p_dry(a0),d3
        sub.w   p_glow(a0),d3
        cmp.w   d5,d3
        ble.s   .nx
        move.w  d3,d5
        move.l  a0,a1
.nx     lea     p_size(a0),a0
        dbra    d4,.cat
        move.l  a1,d0
        beq.s   .e              ; nobody has room
        lea     p_fen(a1),a1
        addq.w  #1,0(a1,d2.w)
        addq.w  #1,d1
        subq.w  #1,d6
        bra.s   .piece
.e      movem.l (sp)+,d0/d2-d6/a0-a1
        rts

; pack_count: d0 = item -> d1 = how many are in the pack (EQ = none)
pack_count:
        move.l  a1,-(sp)
        moveq   #0,d1
        bsr.s   pack_slot
        cmpa.w  #0,a1
        beq.s   .e
        move.b  1(a1),d1
.e      move.l  (sp)+,a1
        tst.w   d1
        rts

; pack_slot: d0 = item -> a1 = its slot (0 if not in the pack)
pack_slot:
        move.l  d1,-(sp)
        lea     v_pack(a5),a1
        moveq   #PACK_SLOTS-1,d1
.l      cmp.b   (a1),d0
        beq.s   .e
        addq.l  #2,a1
        dbra    d1,.l
        sub.l   a1,a1
.e      move.l  (sp)+,d1
        rts

; pack_take: d0 = item; one less in the pack
pack_take:
        move.l  a1,-(sp)
        bsr.s   pack_slot
        cmpa.w  #0,a1
        beq.s   .e
        subq.b  #1,1(a1)
        bne.s   .e
        clr.b   (a1)            ; slot empty
.e      move.l  (sp)+,a1
        rts

; gear_kind: a3 = cat -> d0 = kind of the gear it wears (-1 = none)
gear_kind:
        move.l  a0,-(sp)
        moveq   #-1,d0
        move.w  p_gear(a3),d0
        beq.s   .none
        bsr     item_rec
        move.w  i_kind(a0),d0
        bra.s   .e
.none   moveq   #-1,d0
.e      move.l  (sp)+,a0
        rts

; cat_def: a3 = cat -> d0 = defence with gear
cat_def:
        movem.l d1/a0,-(sp)
        move.w  p_def(a3),d1
        bsr.s   gear_kind
        cmp.w   #IK_GEAR_DEF,d0
        bne.s   .e
        move.w  p_gear(a3),d0
        bsr     item_rec
        add.w   i_value(a0),d1
.e      move.w  d1,d0
        movem.l (sp)+,d1/a0
        rts

; poison_cat: a3 = cat; poisoned unless it wears a Thistle Charm
;             -> NE = newly poisoned
poison_cat:
        movem.l d0-d1,-(sp)
        bsr.s   gear_kind
        cmp.w   #IK_GEAR_POISON,d0
        beq.s   .no
        bset    #PF_POISON,p_flags+1(a3)
        bne.s   .no
        move.w  #T_POISONED,d0
        move.w  p_name(a3),d1
        bsr     name_msg
        moveq   #1,d0           ; NE (movem below keeps the flags)
        movem.l (sp)+,d0-d1
        rts
.no     moveq   #0,d0           ; EQ
        movem.l (sp)+,d0-d1
        rts

; use_item: d0 = item, a3 = cat it is used on -> NE = used up
use_item:
        movem.l d0-d3/a0-a2,-(sp)
        move.w  d0,d3
        bsr     item_rec
        move.w  i_kind(a0),d1
        cmp.w   #IK_GEAR_DEF,d1 ; gear: wear it
        blo.s   .nogear
        cmp.w   #IK_GEAR_LIGHT,d1
        bhi.s   .nogear
        move.w  d3,d0
        bsr     equip           ; (takes it out of the pack itself)
        movem.l (sp)+,d0-d3/a0-a2
        moveq   #1,d0           ; NE: done
        rts
.nogear cmp.w   #IK_HEAL,d1
        beq.s   .heal
        cmp.w   #IK_STALE,d1
        beq.s   .heal
        cmp.w   #IK_WRAP,d1
        beq.s   .wrap
        cmp.w   #IK_CALM,d1
        beq.s   .calm
        move.w  #T_NOT_NOW,d0   ; herb, lure, key: not here
        bsr     msg_print
        bra     .kept
.heal   tst.w   p_hp(a3)
        bgt.s   .h1
        move.w  #T_CANNOT_HELP,d0
        move.w  p_name(a3),d1
        bsr     name_msg
        bra     .kept
.h1     move.w  i_value(a0),d2
        add.w   d2,p_hp(a3)
        move.w  p_hpmax(a3),d2
        cmp.w   p_hp(a3),d2
        bge.s   .h2
        move.w  d2,p_hp(a3)
.h2     move.w  d1,d2
        move.w  #T_HEALED,d0
        move.w  p_name(a3),d1
        bsr     name_msg
        cmp.w   #IK_STALE,d2    ; stale prey may make sick
        bne.s   .used
        bsr     rand100
        cmp.w   #25,d0
        bhs.s   .used
        move.w  #T_STALE_SICK,d0
        bsr     msg_print
        bsr     poison_cat
        bra.s   .used
.wrap   move.w  i_value(a0),p_wrap(a3)
        move.w  #T_WRAPPED,d0
        bsr     msg_print
        bra.s   .used
.calm   bclr    #PF_FEAR,p_flags+1(a3)
        move.w  #T_CALM,d0
        move.w  p_name(a3),d1
        bsr     name_msg
.used   move.w  d3,d0
        bsr     pack_take
        movem.l (sp)+,d0-d3/a0-a2
        moveq   #1,d0           ; NE
        rts
.kept   movem.l (sp)+,d0-d3/a0-a2
        cmp.w   d0,d0           ; EQ
        rts

; equip: a3 = cat, d0 = gear item from the pack (0 = take off)
equip:
        movem.l d0-d2/a0-a2,-(sp)
        move.w  d0,d2
        move.w  p_gear(a3),d0   ; what it wore goes back into the pack
        beq.s   .wear
        moveq   #1,d1
        bsr     pack_add
        bne.s   .back
        move.w  #T_PACK_FULL,d0
        bsr     msg_print
        bra.s   .e
.back   lea     v_args(a5),a2   ; "Removed: <item>."
        move.w  p_gear(a3),d0
        bsr     item_rec
        move.w  i_name(a0),d0
        bsr     text_get
        move.l  a1,(a2)
        move.w  #T_TAKES_OFF,d0
        bsr     msg_print
        clr.w   p_gear(a3)
.wear   tst.w   d2
        beq.s   .e
        move.w  d2,d0
        bsr     pack_take
        move.w  d2,p_gear(a3)
        lea     v_args(a5),a2   ; "<cat> wears the <item>."
        move.w  p_name(a3),d0
        bsr     text_get
        move.l  a1,(a2)
        move.w  d2,d0
        bsr     item_rec
        move.w  i_name(a0),d0
        bsr     text_get
        move.l  a1,4(a2)
        move.w  #T_WEARS,d0
        bsr     msg_print
.e      movem.l (sp)+,d0-d2/a0-a2
        rts

;---------------------------------------------------------------------
; Menus: a box at the bottom left of the viewport. Fill it with
; menu_clear and menu_add / menu_addf, then menu_run.
;---------------------------------------------------------------------
menu_clear:
        clr.w   v_mcount(a5)
        rts

; menu_add: a1 = zero-terminated string (cut to MENU_LEN-1 characters)
menu_add:
        movem.l d0/a0-a1,-(sp)
        move.w  v_mcount(a5),d0
        cmp.w   #MENU_MAX,d0
        bhs.s   .e
        addq.w  #1,v_mcount(a5)
        mulu    #MENU_LEN,d0
        lea     v_mtxt(a5),a0
        add.w   d0,a0
        moveq   #MENU_LEN-2,d0
.c      move.b  (a1)+,(a0)+
        dbeq    d0,.c
        clr.b   (a0)
.e      movem.l (sp)+,d0/a0-a1
        rts

; menu_addt: d0 = text id (no placeholders)
menu_addt:
        move.l  a1,-(sp)
        bsr     text_get
        bsr.s   menu_add
        move.l  (sp)+,a1
        rts

; menu_run: a1 = title -> d0 = chosen line, -1 = cancelled
;           up/down choose; space, enter or right confirm; left or ESC
;           cancel (all of it works with the joystick)
menu_run:
        movem.l d1-d7/a0-a3,-(sp)
        move.l  a1,a3
        clr.w   v_msel(a5)
.draw   move.w  v_mcount(a5),d7 ; box height: title + lines
        addq.w  #1,d7
        mulu    #LINE_H,d7
        addq.w  #3,d7
        moveq   #0,d0
        move.w  #VIEW_H,d1
        sub.w   d7,d1
        move.w  d1,d6           ; top of the box
        cmp.w   v_mtop(a5),d1   ; a larger box was here: view first
        bls.s   .box
        bsr     view_refresh
.box    move.w  d6,v_mtop(a5)
        move.w  d6,d1
        moveq   #MENU_W,d2
        move.w  d7,d3
        moveq   #C_BLACK,d4
        bsr     fill_rect
        move.l  a3,a1           ; title
        moveq   #1,d0
        move.w  d6,d1
        addq.w  #2,d1
        moveq   #C_YEL,d2
        moveq   #C_BLACK,d3
        bsr     pdraw
        moveq   #0,d5           ; the lines
        lea     v_mtxt(a5),a2
.line   cmp.w   v_mcount(a5),d5
        bhs.s   .key
        move.w  d5,d1
        addq.w  #1,d1
        mulu    #LINE_H,d1
        add.w   d6,d1
        addq.w  #2,d1
        moveq   #C_CYAN,d2
        cmp.w   v_msel(a5),d5
        bne.s   .l1
        moveq   #C_WHITE,d2     ; the chosen one: white with a marker
        move.w  d1,-(sp)
        move.w  #T_CMB_MARK,d0
        bsr     text_get        ; (changes d1)
        move.w  (sp)+,d1
        moveq   #1,d0
        bsr     pdraw
.l1     move.l  a2,a1
        moveq   #2,d0
        bsr     pdraw
        lea     MENU_LEN(a2),a2
        addq.w  #1,d5
        bra.s   .line
.key    bsr     frame           ; wait for a newly pressed key
        bsr     readkeys
        move.w  v_pkeys(a5),d1
        not.w   d1
        and.w   d0,d1
        beq.s   .key
        btst    #K_UP,d1
        beq.s   .k1
        subq.w  #1,v_msel(a5)
        bpl     .draw
        move.w  v_mcount(a5),d0
        subq.w  #1,d0
        move.w  d0,v_msel(a5)
        bra     .draw
.k1     btst    #K_DOWN,d1
        beq.s   .k2
        addq.w  #1,v_msel(a5)
        move.w  v_mcount(a5),d0
        cmp.w   v_msel(a5),d0
        bhi     .draw
        clr.w   v_msel(a5)
        bra     .draw
.k2     move.w  d1,d0
        and.w   #(1<<K_LEFT)|(1<<K_ESC),d0
        beq.s   .k3
        bsr     wait_free       ; (ESC must not reach the main loop)
        moveq   #-1,d0
        bra.s   .e
.k3     and.w   #(1<<K_SPACE)|(1<<K_ENTER)|(1<<K_RIGHT),d1
        beq.s   .key
        bsr     wait_free
        move.w  v_msel(a5),d0
.e      movem.l (sp)+,d1-d7/a0-a3
        rts

view_refresh:                   ; the view again (and the enemies in a fight)
        movem.l d0-d7/a0-a4,-(sp)       ; (keeps all registers)
        bsr     redraw
        tst.w   v_fight(a5)
        beq.s   .e
        bsr     foes_draw
.e      movem.l (sp)+,d0-d7/a0-a4
        rts

wait_free:                      ; wait until no key is held
        move.l  d0,-(sp)
.w      bsr     frame
        bsr     readkeys
        tst.w   d0
        bne.s   .w
        move.l  (sp)+,d0
        rts

; menu_cats: d0 = title text id -> d0 = cat 0-3, -1 = cancelled; a3 = cat
menu_cats:
        movem.l d1/a1,-(sp)
        move.w  d0,d1
        bsr     menu_clear
        lea     v_party(a5),a3
        moveq   #NPARTY-1,d0
.c      move.l  d0,-(sp)
        move.w  p_name(a3),d0
        bsr     menu_addt
        move.l  (sp)+,d0
        lea     p_size(a3),a3
        dbra    d0,.c
        move.w  d1,d0
        bsr     text_get
        bsr     menu_run
        tst.w   d0
        bmi.s   .e
        move.w  d0,d1
        mulu    #p_size,d1
        lea     v_party(a5),a3
        add.w   d1,a3
.e      movem.l (sp)+,d1/a1
        rts

; menu_pack: a1 = title, d1 = 0 all items, 1 gear only (with "take off"
;            first) -> d0 = item (0 = take off), -1 = cancelled or empty
menu_pack:
        movem.l d1-d4/a0-a3,-(sp)
        move.l  a1,a3
        bsr     menu_clear
        lea     v_mitem(a5),a2  ; item of every menu line
        tst.w   d1
        beq.s   .list
        move.w  d0,-(sp)
        move.w  #T_MENU_REMOVE,d0
        bsr     menu_addt
        move.w  (sp)+,d0
        clr.b   (a2)+
.list   lea     v_pack(a5),a1
        moveq   #PACK_SLOTS-1,d4
.slot   moveq   #0,d0
        move.b  (a1),d0
        beq.s   .nx
        bsr     item_rec
        tst.w   d1              ; gear only?
        beq.s   .add
        cmp.w   #IK_GEAR_DEF,i_kind(a0)
        blo.s   .nx
        cmp.w   #IK_GEAR_LIGHT,i_kind(a0)
        bhi.s   .nx
.add    move.b  d0,(a2)+
        move.l  a1,-(sp)        ; "<item> x<n>"
        move.w  d1,-(sp)
        move.w  i_name(a0),d0
        bsr     text_get
        lea     v_args(a5),a0
        move.l  a1,(a0)
        move.l  2(sp),a1
        moveq   #0,d0
        move.b  1(a1),d0
        move.l  d0,4(a0)
        move.l  a2,-(sp)
        lea     v_args(a5),a2
        move.w  #T_MENU_COUNT,d0
        bsr     text_fmt
        move.l  (sp)+,a2
        bsr     menu_add
        move.w  (sp)+,d1
        move.l  (sp)+,a1
.nx     addq.l  #2,a1
        dbra    d4,.slot
        moveq   #-1,d0
        tst.w   v_mcount(a5)
        beq.s   .e
        move.l  a3,a1
        bsr     menu_run
        tst.w   d0
        bmi.s   .e
        lea     v_mitem(a5),a0
        moveq   #0,d1
        move.b  0(a0,d0.w),d1
        move.w  d1,d0
.e      movem.l (sp)+,d1-d4/a0-a3
        rts

; party_menu: (space) Pack, a cat and then Item, Equip or Skill, or Game
;             -> NE = something was done
party_menu:
        movem.l d1-d2/a1-a3,-(sp)
.who    bsr     menu_clear      ; Pack, the four cats
        move.w  #T_MENU_PACK,d0
        bsr     menu_addt
        lea     v_party(a5),a3
        moveq   #NPARTY-1,d1
.c      move.w  p_name(a3),d0
        bsr     menu_addt
        lea     p_size(a3),a3
        dbra    d1,.c
        move.w  #T_MENU_GAME,d0 ; and the game menu (save, load, quit)
        bsr     menu_addt
        move.w  #T_MENU_PARTY,d0
        bsr     text_get
        bsr     menu_run
        tst.w   d0
        bmi     .none
        cmp.w   #NPARTY+1,d0
        bne.s   .nogame
        bsr     view_refresh
        bsr     game_menu
        bra     .none
.nogame tst.w   d0
        bne.s   .cat
        move.w  #PG_PACK,v_page(a5) ; Pack: the pack page (I closes it)
        bra     .none
.cat    subq.w  #1,d0
        mulu    #p_size,d0
        lea     v_party(a5),a3
        add.w   d0,a3
        bsr     redraw
        bsr     menu_clear
        move.w  #T_MENU_ITEM,d0
        bsr     menu_addt
        move.w  #T_MENU_EQUIP,d0
        bsr     menu_addt
        move.w  #T_MENU_SKILL,d0
        bsr     menu_addt
        move.w  p_name(a3),d0
        bsr     text_get
        bsr     menu_run
        tst.w   d0
        bmi     .back
        cmp.w   #2,d0
        beq.s   .skill
        tst.w   d0
        bne.s   .equip
        move.w  p_name(a3),d0   ; Item: used on this cat
        bsr     text_get
        moveq   #0,d1
        bsr     menu_pack
        tst.w   d0
        bgt.s   .use
        bsr.s   .empty
        bra.s   .back
.use    bsr     use_item
        bra.s   .done
.equip  move.w  p_name(a3),d0
        bsr     text_get
        moveq   #1,d1
        bsr     menu_pack
        tst.w   d0
        bmi.s   .back
        bsr     equip
.done   movem.l (sp)+,d1-d2/a1-a3
        moveq   #1,d0           ; NE
        rts
.skill  move.l  a3,a2           ; Skill: this cat uses it
        tst.w   p_hp(a2)
        bgt.s   .sk1
        move.w  #T_NOT_ABLE,d0
        move.w  p_name(a2),d1
        bsr     name_msg
        bra     .back
.sk1    bsr     redraw
        bsr     skill_menu
        tst.w   d0
        bmi     .back
        bsr     use_skill
        bne.s   .done
        bra     .back
.back   bsr     redraw
        bra     .who
.none   bsr     redraw
        movem.l (sp)+,d1-d2/a1-a3
        moveq   #0,d0           ; EQ
        rts
.empty  tst.w   v_mcount(a5)    ; nothing to choose: say so
        bne.s   .e1
        move.w  #T_NOTHING,d0
        bsr     msg_print
.e1     rts
