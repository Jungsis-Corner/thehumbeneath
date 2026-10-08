;=====================================================================
; Title, main menu, names, intro, game over (included by hum.asm)
;
; title_loop shows the title picture (file hum_scr, a raw Mode 8 screen)
; with the main menu: NEW GAME, LOAD GAME, QUIT. A new game lets the
; player rename the cats, shows the intro and starts on the first level.
; Game over shows how far the party came and returns to the title.
;=====================================================================
TITLE_MX  equ   20              ; title menu: first word column
TITLE_MY  equ   254             ; title menu: bottom line
TITLE_TOP equ   180             ; title menu area: first line
TITLE_W   equ   32              ; title menu area: width in words
FULL_COLS equ   42              ; full screen text: columns, rows
FULL_ROWS equ   25
MM_NEW    equ   0               ; main menu lines
MM_LOAD   equ   1
MM_LANG   equ   2
MM_QUIT   equ   3
NAME_MAX  equ   12
KEY_ENTER equ   10              ; QL key codes
KEY_ESC   equ   27
KEY_SPACE equ   32
KEY_LEFT  equ   $c0
KEY_RIGHT equ   $c8
KEY_UP    equ   $d0
KEY_DOWN  equ   $d8
KEY_F1    equ   $e8             ; F1-F5: joystick in CTL2 (left, down,
KEY_F2    equ   $ec             ; right, up, fire)
KEY_F3    equ   $f0
KEY_F4    equ   $f4
KEY_F5    equ   $f8
IO_FBYTE  equ   $01
SD_POS    equ   $10
WHEEL_N   equ   wheel_end-wheel ; characters of the letter wheel

;---------------------------------------------------------------------
; title_loop: never returns; starts a game with game_run
;---------------------------------------------------------------------
title_loop:
        move.l  v_sptop(a5),sp  ; start from a clean stack
        clr.w   v_fight(a5)
        clr.w   v_cact(a5)
        ifd     QUICKSTART      ; tests: straight into the first level
        bsr     new_init
        bra     new_start
        endc
        bsr     title_show
.menu   move.w  #1,v_intitle(a5)
        bsr     menu_clear
        move.w  #T_MM_NEW,d0
        bsr     menu_addt
        move.w  #T_MM_LOAD,d0
        bsr     menu_addt
        move.w  #T_MM_LANG,d0
        bsr     menu_addt
        move.w  #T_MM_QUIT,d0
        bsr     menu_addt
        move.w  #T_TITLE,d0
        bsr     text_get
        bsr     menu_run
        cmp.w   #MM_LOAD,d0
        beq.s   .load
        cmp.w   #MM_QUIT,d0
        beq.s   .quit
        cmp.w   #MM_LANG,d0
        beq.s   .lang
        tst.w   d0
        bmi.s   .menu
        bsr     new_game        ; NEW GAME (returns only when cancelled)
        bra.s   .menu
.load   move.w  #T_GM_LOAD,d0
        bsr     slot_menu
        tst.w   d0
        bmi.s   .menu
        bsr     game_load
        beq.s   .play
        move.w  #T_NO_SAVE,d1   ; no save / damaged: say so in the title
        tst.w   d0
        bpl.s   .say
        move.w  #T_LOAD_FAILED,d1
.say    bsr     title_note
        bra.s   .menu
.play   clr.w   v_intitle(a5)
        bra     game_run
.quit   bra     exit_prog
.lang   bchg    #0,v_lang+1(a5) ; the other language
        bsr     text_load
        beq.s   .lok
        bchg    #0,v_lang+1(a5) ; its file is missing: back
        bsr     text_load
.lok    bsr     cfg_save
        bra     .menu

; title_note: d1 = text id; a line in the title menu area until a key
title_note:
        movem.l d0-d5/a1,-(sp)
        move.w  d1,d5
        moveq   #TITLE_MX,d0
        move.w  #TITLE_TOP,d1
        moveq   #TITLE_W,d2
        move.w  #256-TITLE_TOP,d3
        moveq   #C_BLACK,d4
        bsr     fill_rect
        move.w  d5,d0
        bsr     text_get
        moveq   #TITLE_MX+1,d0
        move.w  #TITLE_TOP+20,d1
        moveq   #C_YEL,d2
        moveq   #C_BLACK,d3
        bsr     pdraw
        bsr     wait_key
        movem.l (sp)+,d0-d5/a1
        rts

; title_show: the title picture from hum_scr straight into the screen
;             (only the title, in big letters, if there is no picture)
title_show:
        movem.l d0-d4/a0-a3,-(sp)
        bsr     cls
        lea     scrname(pc),a2
        lea     v_name(a5),a3
        bsr     fopen
        bne.s   .none
        lea     SCREEN,a1
        move.l  #32768,d4
        bsr     fread
        moveq   #IO_CLOSE,d0
        trap    #2
        bra.s   .e
.none   move.w  #T_TITLE,d0
        moveq   #8,d1
        moveq   #C_WHITE,d2
        bsr     full_line
.e      movem.l (sp)+,d0-d4/a0-a3
        rts

;---------------------------------------------------------------------
; new_game: names, intro, the first level. Returns only when the player
; cancels the names menu.
;---------------------------------------------------------------------
new_game:
        bsr.s   new_init
        bra.s   new_names

new_init:                       ; a new party, nothing visited
        bsr     party_init      ; party, names, an empty pack
        lea     v_pack(a5),a0
        moveq   #2*PACK_SLOTS/2-1,d0
.pk     clr.w   (a0)+
        dbra    d0,.pk
        ifd     ITEMTEST
        bsr     item_test
        endc
        clr.w   v_lvok(a5)      ; no level kept, nothing loaded
        clr.w   v_inlv(a5)
        clr.w   v_deep(a5)
        clr.w   v_story(a5)
        bsr     rand            ; where things are in this game
        move.w  d0,v_seed(a5)
        ifd     SEED            ; tests: always the same places
        move.w  #SEED,v_seed(a5)
        endc
        ifd     ANGRYTEST       ; as if a calm Pale One had been attacked
        move.w  #1<<SF_PATTACK,v_story(a5)
        endc
        clr.w   v_sneak(a5)
        clr.w   v_humc(a5)
        clr.w   v_steps(a5)
        clr.w   v_page(a5)
        rts

new_names:
.names  bsr     menu_clear      ; "Name your cats.": the four, BEGIN
        lea     v_party(a5),a3
        lea     v_args(a5),a2
        moveq   #NPARTY-1,d4
.cat    move.w  p_name(a3),d0   ; "<name> (<role>)"
        bsr     text_get
        move.l  a1,(a2)
        move.w  p_role(a3),d0
        bsr     text_get
        move.l  a1,4(a2)
        move.w  #T_NAME_LINE,d0
        bsr     text_fmt
        bsr     menu_add
        lea     p_size(a3),a3
        dbra    d4,.cat
        move.w  #T_MM_BEGIN,d0
        bsr     menu_addt
        move.w  #T_NAME_CATS,d0
        bsr     text_get
        bsr     menu_run
        tst.w   d0
        bmi.s   .back
        cmp.w   #NPARTY,d0
        beq.s   .go
        bsr     name_edit       ; d0 = cat
        bra.s   .names
.back   rts
.go     clr.w   v_intitle(a5)
        bsr     intro
new_start:                      ; the first level
        clr.w   v_intitle(a5)
        ifd     STARTLV
        moveq   #STARTLV,d0
        else
        ifd     QUICKSTART
        moveq   #0,d0           ; tests: test level 0
        else
        moveq   #1,d0           ; the game: level 1
        endc
        endc
        bsr     game_screen     ; (first: it clears the message window)
        bsr     enter_level
        bsr     level_start
        lea     v_args(a5),a2   ; "<first cat> leads the way."
        move.w  v_party+p_name(a5),d0
        bsr     text_get
        move.l  a1,(a2)
        move.w  #T_PARTY_LEAD,d0
        bsr     msg_print
        bra     game_play

; game_run: after loading: the game screen, then play
game_run:
        clr.w   v_sneak(a5)     ; (after loading: walking again)
        bsr     game_screen
        move.w  #T_LOADED,d0
        bsr     msg_print
        ; fallthrough
game_play:
        move.l  sp,v_spgame(a5) ; game over and quit come back to here
        bsr     redraw
        bra     mainloop

; game_screen: the screen of the game, empty message window
game_screen:
        movem.l d0-d3/a0-a1,-(sp)
        bsr     cls
        bsr     draw_frame
        move.l  v_msg(a5),a0
        moveq   #SD_CLEAR,d0
        bsr     io3
        movem.l (sp)+,d0-d3/a0-a1
        rts

; to_title: leave the game (quit, game over) for the title
to_title:
        move.l  v_spgame(a5),sp
        bra     title_loop

;---------------------------------------------------------------------
; name_edit: d0 = cat. Type letters, or with the joystick: up/down
; change the last letter, right adds one, left deletes; ENTER, space or
; fire end, ESC keeps the old name.
;---------------------------------------------------------------------
name_edit:
        movem.l d0-d7/a0-a4,-(sp)
        move.w  d0,d7
        mulu    #NAME_LEN,d0
        lea     v_cname(a5),a4
        add.w   d0,a4           ; the name
        lea     v_buf(a5),a0    ; keep the old one for ESC
        move.l  a4,a1
        moveq   #NAME_LEN-1,d0
.old    move.b  (a1)+,(a0)+
        dbra    d0,.old
        bsr     kbd_flush
.draw   moveq   #TITLE_MX,d0    ; the edit box in the title menu area
        move.w  #TITLE_TOP,d1
        moveq   #TITLE_W,d2
        move.w  #256-TITLE_TOP,d3
        moveq   #C_BLACK,d4
        bsr     fill_rect
        move.w  #T_NAME_CATS,d0
        move.w  #TITLE_TOP+4,d1
        moveq   #C_YEL,d2
        bsr.s   .line
        move.w  d7,d0           ; the role
        mulu    #p_size,d0
        lea     v_party(a5),a0
        move.w  p_role(a0,d0.w),d0
        move.w  #TITLE_TOP+4+2*LINE_H,d1
        moveq   #C_CYAN,d2
        bsr.s   .line
        move.l  a4,a1           ; the name with a cursor
        lea     v_name(a5),a0
.cpn    move.b  (a1)+,(a0)+
        bne.s   .cpn
        move.b  #'_',-1(a0)
        clr.b   (a0)
        lea     v_name(a5),a1
        moveq   #TITLE_MX+1,d0
        move.w  #TITLE_TOP+4+3*LINE_H,d1
        moveq   #C_WHITE,d2
        moveq   #C_BLACK,d3
        bsr     pdraw
        move.w  #T_NAME_HELP1,d0
        move.w  #TITLE_TOP+4+5*LINE_H,d1
        moveq   #C_CYAN,d2
        bsr.s   .line
        move.w  #T_NAME_HELP2,d0
        move.w  #TITLE_TOP+4+6*LINE_H,d1
        bsr.s   .line
        bra.s   .key
.line   bsr     text_get        ; d0 = text, d1 = y, d2 = ink
        moveq   #TITLE_MX+1,d0
        moveq   #C_BLACK,d3
        bra     pdraw
.key    bsr     get_key         ; -> d1 = key code
        move.l  a4,a0           ; a0 = end of the name, d6 = length
        moveq   #0,d6
.end    tst.b   (a0)
        beq.s   .k0
        addq.l  #1,a0
        addq.w  #1,d6
        bra.s   .end
.k0     cmp.b   #KEY_ENTER,d1
        beq     .done
        cmp.b   #KEY_SPACE,d1
        beq     .done
        cmp.b   #KEY_F5,d1
        beq     .done
        cmp.b   #KEY_ESC,d1
        beq     .cancel
        cmp.b   #KEY_LEFT,d1
        beq.s   .del
        cmp.b   #KEY_F1,d1
        beq.s   .del
        cmp.b   #KEY_RIGHT,d1
        beq.s   .more
        cmp.b   #KEY_F3,d1
        beq.s   .more
        cmp.b   #KEY_UP,d1
        beq.s   .up
        cmp.b   #KEY_F4,d1
        beq.s   .up
        cmp.b   #KEY_DOWN,d1
        beq.s   .down
        cmp.b   #KEY_F2,d1
        beq.s   .down
        move.b  d1,d0           ; a letter, digit, - or '
        bsr     name_char
        bmi     .key
        cmp.w   #NAME_MAX,d6
        bhs     .key
        move.b  d1,(a0)+
        clr.b   (a0)
        bra     .draw
.del    tst.w   d6
        beq     .key
        clr.b   -1(a0)
        bra     .draw
.more   cmp.w   #NAME_MAX,d6    ; right: one more letter
        bhs     .key
        move.b  #'a',(a0)+
        clr.b   (a0)
        bra     .draw
.up     moveq   #1,d2           ; up/down: the last letter through the wheel
        bra.s   .wheel
.down   moveq   #-1,d2
.wheel  tst.w   d6
        bne.s   .w1
        move.b  #'A',(a0)       ; empty: start with A
        clr.b   1(a0)
        bra     .draw
.w1     move.b  -1(a0),d0
        bsr     name_char       ; -> d3 = place in the wheel
        bpl.s   .w2
        moveq   #0,d3
.w2     add.w   d2,d3
        bpl.s   .w3
        moveq   #WHEEL_N-1,d3
.w3     cmp.w   #WHEEL_N,d3
        blo.s   .w4
        moveq   #0,d3
.w4     lea     wheel(pc),a1
        move.b  0(a1,d3.w),-1(a0)
        bra     .draw
.cancel lea     v_buf(a5),a1    ; ESC: the old name again
        move.l  a4,a0
        moveq   #NAME_LEN-1,d0
.rs     move.b  (a1)+,(a0)+
        dbra    d0,.rs
.done   tst.b   (a4)            ; an empty name: the old one
        bne.s   .e
        lea     v_buf(a5),a1
        move.l  a4,a0
        moveq   #NAME_LEN-1,d0
.rs2    move.b  (a1)+,(a0)+
        dbra    d0,.rs2
.e      bsr     kbd_flush
        movem.l (sp)+,d0-d7/a0-a4
        rts

; name_char: d0.b = character -> d3 = its place in the wheel, MI = not
;            allowed in a name
name_char:
        movem.l d0/a1,-(sp)
        lea     wheel(pc),a1
        moveq   #0,d3
.l      cmp.b   0(a1,d3.w),d0
        beq.s   .ok
        addq.w  #1,d3
        cmp.w   #WHEEL_N,d3
        blo.s   .l
        moveq   #-1,d3
.ok     movem.l (sp)+,d0/a1
        tst.w   d3
        rts

; get_key: -> d1 = next key code from the keyboard queue (waits)
get_key:
        movem.l d0/d2-d3/a0-a1,-(sp)
.w      move.l  v_msg(a5),a0
        moveq   #IO_FBYTE,d0
        moveq   #-1,d3
        trap    #3
        tst.l   d0
        bne.s   .w
        and.w   #$ff,d1
        movem.l (sp)+,d0/d2-d3/a0-a1
        rts

; kbd_flush: forget typed keys (the same as readkeys does)
kbd_flush:
        movem.l d0/a0,-(sp)
        move.l  v_sysv(a5),a0
        move.l  $4c(a0),d0
        beq.s   .e
        move.l  d0,a0
        move.l  8(a0),12(a0)
.e      movem.l (sp)+,d0/a0
        rts

; wait_key: wait for any newly pressed key (KEYROW)
wait_key:
        movem.l d0-d1,-(sp)
        bsr     wait_free
.w      bsr     frame
        bsr     readkeys
        tst.w   d0
        beq.s   .w
        bsr     wait_free
        movem.l (sp)+,d0-d1
        rts

;---------------------------------------------------------------------
; Full screen text through the channel v_full (6 px characters)
;---------------------------------------------------------------------
; full_clear: the whole screen black
full_clear:
        movem.l d0-d3/a0-a1,-(sp)
        move.l  v_full(a5),a0
        moveq   #SD_CLEAR,d0
        bsr     io3
        movem.l (sp)+,d0-d3/a0-a1
        rts

; full_line: d0 = text id, d1 = row, d2 = ink; every line of the text
;            centred, one row below the other -> d1 = next row
full_line:
        movem.l d0/d2-d7/a0-a3,-(sp)
        move.w  d1,d6           ; row
        move.w  d2,d7
        lea     v_args(a5),a2
        bsr     text_fmt        ; -> a1 = v_buf
        move.l  a1,a3
        move.l  v_full(a5),a0
        move.w  d7,d1
        moveq   #SD_SETIN,d0
        bsr     io3
.ln     move.l  a3,a1           ; length of this line
        moveq   #0,d5
.len    move.b  (a1)+,d0
        beq.s   .put
        cmp.b   #10,d0
        beq.s   .put
        addq.w  #1,d5
        bra.s   .len
.put    moveq   #FULL_COLS,d1   ; centred
        sub.w   d5,d1
        bpl.s   .p1
        moveq   #0,d1
.p1     lsr.w   #1,d1
        move.w  d6,d2
        moveq   #SD_POS,d0
        bsr     io3
        move.w  d5,d2
        beq.s   .nx
        move.l  a3,a1
        moveq   #IO_SSTRG,d0
        bsr     io3
.nx     addq.w  #1,d6
        add.w   d5,a3           ; next line
        tst.b   (a3)+
        bne.s   .ln
        move.w  d6,d1
        movem.l (sp)+,d0/d2-d7/a0-a3
        rts

; intro: the intro text of STORY.md, then a key
intro:
        movem.l d0-d2,-(sp)
        bsr     full_clear
        move.w  #T_INTRO,d0
        moveq   #3,d1
        moveq   #C_WHITE,d2
        bsr     full_line
        move.w  #T_INTRO_END,d0
        addq.w  #1,d1
        moveq   #C_YEL,d2
        bsr     full_line
        move.w  #T_PRESS_KEY,d0
        moveq   #FULL_ROWS-2,d1
        moveq   #C_CYAN,d2
        bsr     full_line
        bsr     wait_key
        movem.l (sp)+,d0-d2
        rts

;---------------------------------------------------------------------
; ending: d0 = END_A, END_B or END_C. The words of the ending (STORY.md)
;         on the full screen, then the title (the stack is reset)
END_A   equ     0               ; the Release: the Heart Stone used
END_B   equ     1               ; the Silence: the Keeper beaten
END_C   equ     2               ; the Stay: laid down at the Heart
ending:
        move.w  d0,d7
        moveq   #S_ENDING,d0
        bsr     sound
        moveq   #100,d1         ; a moment to read the last messages
.w      bsr     frame
        dbra    d1,.w
        bsr     full_clear
        lea     v_args(a5),a2
        move.w  d7,d0
        add.w   #T_END_A_TITLE,d0
        moveq   #3,d1
        moveq   #C_YEL,d2
        bsr     full_line
        addq.w  #1,d1
        move.w  d7,d0
        add.w   #T_END_A,d0
        moveq   #C_WHITE,d2
        bsr     full_line
        addq.w  #2,d1
        move.w  #T_THE_END,d0
        moveq   #C_CYAN,d2
        bsr     full_line
        move.w  #T_PRESS_KEY,d0
        moveq   #FULL_ROWS-2,d1
        moveq   #C_CYAN,d2
        bsr     full_line
        bsr     wait_key
        bra     to_title

;---------------------------------------------------------------------
; game_over: every cat has fallen; how far the party came, then the
; title (from any depth of calls: the stack is reset)
;---------------------------------------------------------------------
game_over:
        bsr     panel_show
        moveq   #S_GAMEOVER,d0
        bsr     sound
        move.w  #T_GAME_OVER,d0
        bsr     msg_print
        moveq   #100,d1         ; a moment to read the last messages
.w      bsr     frame
        dbra    d1,.w
        bsr     progress        ; -> d0, v_prog
        bsr     full_clear
        lea     v_args(a5),a2
        move.w  #T_GAME_OVER,d0
        moveq   #4,d1
        moveq   #C_RED,d2
        bsr     full_line
        move.w  #T_ALL_FALLEN,d0
        moveq   #C_WHITE,d2
        bsr     full_line
        addq.w  #2,d1
        moveq   #0,d0
        move.w  v_prog(a5),d0
        move.l  d0,(a2)
        move.w  #T_PROGRESS,d0
        moveq   #C_YEL,d2
        bsr     full_line
        addq.w  #1,d1
        moveq   #0,d0           ; depth
        move.w  v_prog+2(a5),d0
        move.l  d0,(a2)
        move.l  #DEPTH_LEVELS,4(a2)
        move.w  #T_PROG_DEPTH,d0
        moveq   #C_CYAN,d2
        bsr     full_line
        moveq   #0,d0           ; explored
        move.w  v_prog+4(a5),d0
        move.l  d0,(a2)
        move.w  #T_PROG_EXPLORED,d0
        bsr     full_line
        moveq   #0,d0           ; story
        move.w  v_prog+6(a5),d0
        move.l  d0,(a2)
        move.l  #TOTAL_MARKS,4(a2)
        move.w  v_prog+8(a5),d0
        move.l  d0,8(a2)
        move.l  #TOTAL_BOSSES,12(a2)
        move.w  #T_PROG_STORY,d0
        bsr     full_line
        move.w  #T_PRESS_KEY,d0
        moveq   #FULL_ROWS-2,d1
        moveq   #C_CYAN,d2
        bsr     full_line
        bsr     wait_key
        bra     to_title

;---------------------------------------------------------------------
; progress: -> d0 = progress in %; v_prog = %, depth, explored %,
;           marks found, guardians beaten (see PLAN.md)
;   50 % depth, 25 % explored cells, 25 % marks and guardians
;---------------------------------------------------------------------
progress:
        movem.l d1-d7/a0-a4,-(sp)
        bsr     lv_keep         ; count the current level too
        moveq   #0,d5           ; cells seen
        moveq   #0,d6           ; marks found
        moveq   #0,d7           ; guardians beaten
        moveq   #0,d4           ; level
.lv     move.w  v_lvok(a5),d0
        btst    d4,d0
        beq.s   .nlv
        move.w  #TEST_LEVELS,d0 ; test levels do not count
        btst    d4,d0
        bne.s   .nlv
        move.w  d4,d0
        bsr     lv_slot         ; a0 = what changed in that level
        moveq   #128-1,d1       ; cells seen: bits set
.byte   move.b  (a0)+,d0
        moveq   #7,d2
.bit    btst    d2,d0
        beq.s   .b0
        addq.l  #1,d5
.b0     dbra    d2,.bit
        dbra    d1,.byte
        move.w  d4,d0
        bsr     lv_slot
        add.w   LVD_MARKS(a0),d6
        add.w   LVD_BOSSES(a0),d7
.nlv    addq.w  #1,d4
        cmp.w   #LVSLOTS,d4
        blo.s   .lv
        lea     v_prog(a5),a3
        move.w  v_deep(a5),d0   ; depth: deepest level, at most DEPTH_LEVELS
        cmp.w   #DEPTH_LEVELS,d0
        bls.s   .d1
        moveq   #DEPTH_LEVELS,d0
.d1     move.w  d0,2(a3)
        mulu    #50,d0
        divu    #DEPTH_LEVELS,d0
        move.w  d0,d4           ; %
        move.l  d5,d0           ; explored
        mulu    #100,d0
        divu    #TOTAL_CELLS,d0
        cmp.w   #100,d0
        bls.s   .x1
        moveq   #100,d0
.x1     move.w  d0,4(a3)
        lsr.w   #2,d0           ; a quarter of it
        add.w   d0,d4
        move.w  d6,6(a3)        ; story
        move.w  d7,8(a3)
        moveq   #0,d0
        move.w  d6,d0
        add.w   d7,d0
        ifne    TOTAL_MARKS+TOTAL_BOSSES
        mulu    #25,d0
        divu    #TOTAL_MARKS+TOTAL_BOSSES,d0
        add.w   d0,d4
        endc
        cmp.w   #100,d4
        bls.s   .p1
        moveq   #100,d4
.p1     move.w  d4,(a3)
        moveq   #0,d0
        move.w  d4,d0
        movem.l (sp)+,d1-d7/a0-a4
        rts
