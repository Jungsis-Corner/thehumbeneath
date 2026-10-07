;=====================================================================
; Level memory, save and load, the game menu (included by hum.asm)
;
; Every level the party has been on is kept in v_lvstore (open doors,
; items taken, groups beaten, ...). A save file hum_svN holds the party,
; the pack, where the party is and every kept level:
;   'HSG1', length.l, SAVE_VER.w, level.w, pos.w, dir.w, steps.w,
;   kept levels.w (bit n = level n), party, pack, the kept levels in
;   ascending order (LEVMAX bytes each)
;=====================================================================
SAVE_VER   equ  1
SAVE_SLOTS equ  3
SAVE_FIX   equ  SAVE_HEAD+NPARTY*p_size+2*PACK_SLOTS
SAVE_MAX   equ  SAVE_FIX+LVSLOTS*LEVMAX
SAVE_MAGIC equ  'HSG1'
IO_DELET   equ  $04
GM_CONTINUE equ 0               ; game menu lines
GM_SAVE    equ  1
GM_LOAD    equ  2
GM_QUIT    equ  3

; lv_slot: d0 = level -> a0 = its place in v_lvstore
lv_slot:
        move.l  d0,-(sp)
        and.l   #$ffff,d0
        mulu    #LEVMAX,d0
        move.l  a5,a0
        add.l   #v_lvstore,a0
        add.l   d0,a0
        move.l  (sp)+,d0
        rts

; lv_copy: a0 = from, a1 = to (LEVMAX bytes)
lv_copy:
        movem.l d0/a0-a1,-(sp)
        move.w  #LEVMAX/4-1,d0
.c      move.l  (a0)+,(a1)+
        dbra    d0,.c
        movem.l (sp)+,d0/a0-a1
        rts

; lv_keep: the level in v_map into v_lvstore
lv_keep:
        movem.l d0-d1/a0-a1,-(sp)
        tst.w   v_inlv(a5)
        beq.s   .e
        move.w  v_level(a5),d0
        bsr.s   lv_slot
        move.l  a0,a1
        lea     v_map(a5),a0
        bsr.s   lv_copy
        move.w  v_lvok(a5),d1   ; level kept
        bset    d0,d1
        move.w  d1,v_lvok(a5)
.e      movem.l (sp)+,d0-d1/a0-a1
        rts

; lv_fetch: d0 = level -> EQ = it was kept and is now in v_map
lv_fetch:
        movem.l d1/a0-a1,-(sp)
        move.w  v_lvok(a5),d1
        btst    d0,d1
        beq.s   .no
        bsr.s   lv_slot
        lea     v_map(a5),a1
        bsr.s   lv_copy
        move.w  d0,v_level(a5)
        movem.l (sp)+,d1/a0-a1
        move    #4,ccr          ; EQ
        rts
.no     movem.l (sp)+,d1/a0-a1
        move    #0,ccr          ; NE
        rts

; lv_count: -> d1 = number of kept levels
lv_count:
        movem.l d0/d2,-(sp)
        moveq   #0,d1
        move.w  v_lvok(a5),d2
        moveq   #15,d0
.l      btst    d0,d2
        beq.s   .n
        addq.w  #1,d1
.n      dbra    d0,.l
        movem.l (sp)+,d0/d2
        rts

; fwrite: a0 = channel, a1 = source, d4.l = number of bytes -> EQ = ok
fwrite:
        movem.l d1-d4/a1-a2,-(sp)
.chunk  move.l  d4,d2
        cmp.l   #$4000,d2
        bls.s   .n
        move.l  #$4000,d2
.n      move.l  a1,a2           ; trap #3 changes a1
        moveq   #IO_SSTRG,d0
        moveq   #-1,d3
        trap    #3
        tst.l   d0
        bne.s   .e
        and.l   #$ffff,d1
        move.l  a2,a1
        add.l   d1,a1
        sub.l   d1,d4
        bne.s   .chunk
.e      movem.l (sp)+,d1-d4/a1-a2
        tst.l   d0
        rts

; save_open: d0 = slot 1-3, d3 = 1 to read, 2 to write a new file
;            -> d0 = error (EQ = ok), a0 = channel
save_open:
        movem.l d1-d4/a1-a3,-(sp)
        lea     svname(pc),a0   ; 'hum_sv0' with the slot as last digit
        lea     v_svn(a5),a2
        move.l  a2,a1
        moveq   #2+7-1,d1
.cp     move.b  (a0)+,(a1)+
        dbra    d1,.cp
        add.b   d0,-1(a1)
        move.w  v_dev(a5),d4    ; on the device the game came from
        lea     v_name(a5),a3
        bsr     dev_name
        cmp.w   #2,d3
        bne.s   .open
        moveq   #IO_DELET,d0    ; a new file: away with the old one
        moveq   #-1,d1
        trap    #2
        move.l  a3,a0
        moveq   #2,d3           ; (the trap may change d3)
.open   moveq   #IO_OPEN,d0
        moveq   #-1,d1
        trap    #2
        movem.l (sp)+,d1-d4/a1-a3
        tst.l   d0
        rts

; game_save: d0 = slot -> EQ = saved
game_save:
        movem.l d1-d5/a0-a2,-(sp)
        bsr     lv_keep         ; the current level too
        moveq   #2,d3
        bsr.s   save_open
        bne     .e
        lea     v_shdr(a5),a1   ; header and where the party is
        move.l  #SAVE_MAGIC,(a1)
        bsr     lv_count
        mulu    #LEVMAX,d1
        add.l   #SAVE_FIX,d1
        move.l  d1,4(a1)
        move.w  #SAVE_VER,8(a1)
        move.w  v_level(a5),10(a1)
        move.w  v_pos(a5),12(a1)
        move.w  v_dir(a5),14(a1)
        move.w  v_steps(a5),16(a1)
        move.w  v_lvok(a5),18(a1)
        moveq   #SAVE_HEAD,d4
        bsr     fwrite
        bne.s   .cl
        lea     v_party(a5),a1
        move.l  #NPARTY*p_size,d4
        bsr     fwrite
        bne.s   .cl
        lea     v_pack(a5),a1
        moveq   #2*PACK_SLOTS,d4
        bsr     fwrite
        bne.s   .cl
        moveq   #0,d5           ; the kept levels
.lv     move.w  v_lvok(a5),d1
        btst    d5,d1
        beq.s   .nx
        move.l  a0,a2
        move.w  d5,d0
        bsr     lv_slot
        move.l  a0,a1
        move.l  a2,a0
        move.l  #LEVMAX,d4
        bsr     fwrite
        bne.s   .cl
.nx     addq.w  #1,d5
        cmp.w   #LVSLOTS,d5
        blo.s   .lv
        moveq   #0,d0
.cl     move.l  d0,d4
        moveq   #IO_CLOSE,d0
        trap    #2
        move.l  d4,d0
.e      movem.l (sp)+,d1-d5/a0-a2
        tst.l   d0
        rts

; save_head: d0 = slot -> EQ = v_shdr holds the header of a good save
save_head:
        movem.l d1-d4/a0-a1,-(sp)
        moveq   #1,d3
        bsr     save_open
        bne.s   .e
        lea     v_shdr(a5),a1
        moveq   #SAVE_HEAD,d4
        bsr     fread
        move.l  d0,d4
        moveq   #IO_CLOSE,d0
        trap    #2
        move.l  d4,d0
        bne.s   .e
        moveq   #-1,d0
        lea     v_shdr(a5),a1
        cmp.l   #SAVE_MAGIC,(a1)
        bne.s   .e
        cmp.w   #SAVE_VER,8(a1)
        bne.s   .e
        moveq   #0,d0
.e      movem.l (sp)+,d1-d4/a0-a1
        tst.l   d0
        rts

; game_load: d0 = slot -> d0 = 0 loaded, 1 no save, -1 damaged
game_load:
        movem.l d1-d5/a0-a2,-(sp)
        move.w  d0,d5
        bsr.s   save_head
        beq.s   .open
        moveq   #1,d0           ; no (usable) save
        bra     .e
.open   move.w  d5,d0
        moveq   #1,d3
        bsr     save_open
        bne     .bad
        lea     v_shdr(a5),a1   ; the header once more, then check it
        moveq   #SAVE_HEAD,d4
        bsr     fread
        bne.s   .cl
        moveq   #-1,d0
        move.w  18(a1),d1       ; length must match the kept levels
        move.w  d1,-(sp)
        move.w  v_lvok(a5),-(sp)
        move.w  d1,v_lvok(a5)
        bsr     lv_count
        move.w  (sp)+,v_lvok(a5)
        mulu    #LEVMAX,d1
        add.l   #SAVE_FIX,d1
        move.w  (sp)+,d2        ; kept levels of the save
        cmp.l   4(a1),d1
        bne.s   .cl
        lea     v_party(a5),a1
        move.l  #NPARTY*p_size,d4
        bsr     fread
        bne.s   .cl
        lea     v_pack(a5),a1
        moveq   #2*PACK_SLOTS,d4
        bsr     fread
        bne.s   .cl
        moveq   #0,d5           ; the kept levels
.lv     btst    d5,d2
        beq.s   .nx
        move.l  a0,a2
        move.w  d5,d0
        bsr     lv_slot
        move.l  a0,a1
        move.l  a2,a0
        move.l  #LEVMAX,d4
        bsr     fread
        bne.s   .cl
.nx     addq.w  #1,d5
        cmp.w   #LVSLOTS,d5
        blo.s   .lv
        moveq   #0,d0
.cl     move.l  d0,d4
        moveq   #IO_CLOSE,d0
        trap    #2
        move.l  d4,d0
        bne.s   .bad
        lea     v_shdr(a5),a1   ; take over where the party is
        move.w  10(a1),d0
        move.w  12(a1),v_pos(a5)
        move.w  14(a1),v_dir(a5)
        move.w  16(a1),v_steps(a5)
        move.w  d2,v_lvok(a5)
        clr.w   v_inlv(a5)
        bsr     lv_fetch        ; its level into v_map
        move.w  #1,v_inlv(a5)
        clr.w   v_wsnum(a5)     ; and that level's pictures
        clr.w   v_ssnum(a5)
        bsr     level_sets
        clr.w   v_page(a5)
        moveq   #0,d0
        bra.s   .e
.bad    moveq   #-1,d0
.e      movem.l (sp)+,d1-d5/a0-a2
        tst.l   d0
        rts

; slot_menu: d0 = title text id -> d0 = slot 1-3, -1 = cancelled
slot_menu:
        movem.l d1-d5/a0-a2,-(sp)
        move.w  d0,d5
        bsr     menu_clear
        lea     v_args(a5),a2
        moveq   #1,d4
.slot   move.l  d4,(a2)
        move.w  d4,d0
        bsr     save_head
        bne.s   .empty
        moveq   #0,d0
        move.w  v_shdr+10(a5),d0
        move.l  d0,4(a2)
        move.w  #T_SLOT_USED,d0
        bra.s   .add
.empty  move.w  #T_SLOT_EMPTY,d0
.add    bsr     text_fmt
        bsr     menu_add
        addq.w  #1,d4
        cmp.w   #SAVE_SLOTS,d4
        bls.s   .slot
        move.w  d5,d0
        bsr     text_get
        bsr     menu_run
        tst.w   d0
        bmi.s   .e
        addq.w  #1,d0
.e      movem.l (sp)+,d1-d5/a0-a2
        rts

; game_menu: (ESC, or Game in the space menu) continue, save, load, quit
game_menu:
        movem.l d0-d2/a0-a2,-(sp)
.menu   bsr     menu_clear
        move.w  #T_GM_CONTINUE,d0
        bsr     menu_addt
        move.w  #T_GM_SAVE,d0
        bsr     menu_addt
        move.w  #T_GM_LOAD,d0
        bsr     menu_addt
        move.w  #T_GM_QUIT,d0
        bsr     menu_addt
        move.w  #T_TITLE,d0
        bsr     text_get
        bsr     menu_run
        cmp.w   #GM_SAVE,d0
        beq.s   .save
        cmp.w   #GM_LOAD,d0
        beq.s   .load
        cmp.w   #GM_QUIT,d0
        beq     .quit
.e      bsr     redraw
        movem.l (sp)+,d0-d2/a0-a2
        rts
.save   bsr     view_refresh
        move.w  #T_GM_SAVE,d0
        bsr     slot_menu
        tst.w   d0
        bmi.s   .back
        bsr     game_save
        bne.s   .fail
        move.w  #T_SAVED,d0
        bra.s   .say
.fail   move.w  #T_SAVE_FAILED,d0
.say    bsr     msg_print
        bra.s   .e
.back   bsr     view_refresh
        bra     .menu
.load   bsr     view_refresh
        move.w  #T_GM_LOAD,d0
        bsr     slot_menu
        tst.w   d0
        bmi.s   .back
        bsr     game_load
        beq.s   .loaded
        bmi.s   .damaged
        move.w  #T_NO_SAVE,d0
        bsr     msg_print
        bra.s   .back
.damaged move.w #T_LOAD_FAILED,d0
        bsr     msg_print
        bra.s   .e
.loaded move.w  #T_LOADED,d0
        bsr     msg_print
        bra.s   .e
.quit   bsr     view_refresh    ; really?
        bsr     menu_clear
        move.w  #T_NO,d0
        bsr     menu_addt
        move.w  #T_YES,d0
        bsr     menu_addt
        move.w  #T_QUIT_ASK,d0
        bsr     text_get
        bsr     menu_run
        cmp.w   #1,d0
        bne.s   .back
        bra     exit_prog
