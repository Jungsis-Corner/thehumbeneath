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
;
; Test switches (vasm -D..., e.g. ./tools/emu.sh -DSTARTX=5 -DSTARTDIR=2):
;   STARTLV         first level (default 0, the test level)
;   STARTX, STARTY  start cell instead of the one in the level file
;   STARTDIR        start facing 0 N, 1 E, 2 S, 3 W
;   DEBUG=1         position and render time (frames of 1/50 s) in the panel
;   HPTEST          start with reduced hit points (to see the bar colours)
;   BLEEDTEST       start with bleeding cats (Scratch, Gash, Deep Wound)
;   XPTEST          every cat starts with 38 XP (the next rank needs 40)
;   ITEMTEST        the pack starts with some items (see item_test)
;   QUICKSTART      no title, names or intro: straight into the first level
;   NOENEMY         levels without enemy groups (to test the levels)
;   ANGRYTEST       the party has attacked a calm Pale One (Elder Pale test)
;   SEED=n          the places of things in this game (see lv_shuffle)
;   HEALERDOWN      the healer starts fallen (Starfolk wake her after a fight)
;   MAPALL          the map shows the whole level, groups and items too
;=====================================================================

        include 'textid.inc'    ; T_... text ids         (tools/textc.py)
        include 'levels.inc'    ; level layout, CT_...   (tools/levelc.py)
        include 'walls.inc'     ; view geometry, wall set layout (tools/gfxc.py)
        include 'party.inc'     ; party layout, rules       (tools/datac.py)

    ifnd DEBUG
DEBUG   equ     0
    endc

;---------------------------------------------------------------------
; Hardware / screen layout
;---------------------------------------------------------------------
SCREEN  equ     $20000
LINEB   equ     128             ; bytes per screen line
VIEWB   equ     VIEW_W*2        ; bytes per line of the view buffer
PANEL_X equ     48              ; party panel: first word column
PANEL_W equ     16              ; party panel width in words (64 px)
SEP_Y   equ     128             ; separator between view and messages
SEP_H   equ     8
MAP_X   equ     8               ; debug map: first word column (32 cells x 4 px)

; enemies
HUNT_RANGE equ  6               ; hunters follow the party within this distance

; items and menus
PACK_SLOTS equ  12              ; kinds of items in the party pack
PACK_MAX   equ  99              ; items of one kind
MENU_MAX   equ  16              ; menu lines
MENU_LEN   equ  40              ; bytes per menu line (zero-terminated)
MENU_W     equ  24              ; menu box width in words (at least; longer
                                ; lines make it wider, see menu_width)
PF_POISON  equ  0               ; p_flags: poisoned
PF_FEAR    equ  2               ; p_flags: afraid (Wraith Owls; ends with the fight)
PF_FEATHER equ  3               ; p_flags: the feather was used on this level
SF_SPARED  equ  0               ; v_story: the Elder Pale was spared
SF_PFOUGHT equ  1               ; v_story: the party fought Pale Ones
SF_PATTACK equ  2               ; v_story: it chose to attack calm Pale Ones
NOISE_STEP equ  3               ; a normal step wakes listeners this near
NOISE_LOUD equ  6               ; a noise event wakes listeners this near
HUM_STEPS  equ  10              ; Hum levels: a pulse every 10 actions

; level memory and saving
LVSLOTS    equ  10              ; levels 0-9 can be kept
LVDELTA    equ  384             ; what changed in a kept level (see state.asm):
LVD_DOORS  equ  128             ;   0: cells seen, 1 bit each; doors: count.w,
LVD_NDOORS equ  40              ;   up to 40 cells.w; events: count.w, up to
LVD_EVENTS equ  LVD_DOORS+2+2*LVD_NDOORS ; 64 flags; marks found.w, bosses
LVD_MARKS  equ  LVD_EVENTS+2+64 ;   beaten.w; the group table (16 groups + end)
LVD_BOSSES equ  LVD_MARKS+2
LVD_GROUPS equ  LVD_BOSSES+2
    ifgt LVD_GROUPS+16*6+1-LVDELTA
    fail "LVDELTA too small"
    endc
NAME_LEN   equ  14              ; bytes per cat name in v_cname (12 + 0, even)
NAME_ID    equ  $f000           ; text id NAME_ID+n = name of cat n (v_cname)
SAVE_MISC  equ  14              ; save file: version .. progress
SAVE_HEAD  equ  8+SAVE_MISC     ; save file: magic, length, misc

; input
REP_FIRST equ   12              ; frames until a held key repeats
REP_NEXT  equ   7               ; frames between repeats

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
MT_LPOLL equ    $1c
MT_RPOLL equ    $1d
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
K_SHIFT equ     8               ; from KEYROW(7), added by readkeys
K_MAP   equ     9               ; M (KEYROW(2)): map on/off
K_SHEET equ     10              ; C (KEYROW(2)): party sheet on/off
K_PACK  equ     11              ; I (KEYROW(5)): pack page on/off
K_SNEAK equ     12              ; S (KEYROW(3)): sneak on/off
K_HELP  equ     13              ; H (KEYROW(4)): the keys

; pages shown in the viewport
PG_VIEW  equ    0
PG_MAP   equ    1
PG_SHEET equ    2
PG_PACK  equ    3
PG_HELP  equ    4
K_MOVE  equ     (1<<K_UP)|(1<<K_DOWN)|(1<<K_LEFT)|(1<<K_RIGHT)

;---------------------------------------------------------------------
; Text file hum_txt
;---------------------------------------------------------------------
TXT_MAGIC equ   'HTX2'
TXT_LEN   equ   4               ; offset of length.l (the part kept in memory)
TXT_COUNT equ   8               ; offset of count.w
TXT_SECT  equ   10              ; offset of the level blocks: 10 x (start, length)
TXT_OFFS  equ   10+4*10         ; offset of the offset table
TXT_HEAD  equ   10              ; bytes read before the heap exists
FS_POSAB  equ   $42             ; QDOS: set the file position

NAMEBUF equ     48              ; room for device + file name (QDOS string)
BUFLEN  equ     512             ; formatted text (the intro is long)
ERR_EF  equ     -10             ; QDOS: end of file

;---------------------------------------------------------------------
; Global variables (A5)
;---------------------------------------------------------------------
        rsreset
v_heap  rs.l    1               ; start of the heap block
v_sp    rs.l    1               ; stack pointer at entry
v_mode  rs.w    1               ; 0 = job, 1 = CALL
v_sysv  rs.l    1               ; system variables (MT.INF)
v_msg   rs.l    1               ; message window channel
v_poll  rs.l    2               ; poll list linkage (50 Hz counter)
v_text  rs.l    1               ; text file in memory (0 = not loaded)
v_txtres rs.l   1               ; length of the part in memory
v_lang  rs.w    1               ; language: 0 English, 1 German (hum_cfg:
v_asave rs.w    1               ; autosave: AS_LEVEL.. AS_OFF  these three
v_aslot rs.w    1               ; last auto slot: 0 = slot 0, 1 = AUTO2  words)
v_asteps rs.w   1               ; steps since the last autosave
v_slots rs.b    8               ; slot_menu: the slot of every line
v_ltstart rs.w  1               ; level text block: file offset, length
v_ltlen rs.w    1
v_keys  rs.w    1               ; current keys (KEYROW(1) layout)
v_pkeys rs.w    1               ; keys of the previous poll
v_rep   rs.w    1               ; frames until a held key repeats
v_level rs.w    1               ; current level number
v_wsnum rs.w    1               ; wall set in v_walls (0 = none)
v_dev   rs.w    1               ; device of the game files (see fopen)
v_lvok  rs.w    1               ; bit n: level n kept in v_lvstore
v_inlv  rs.w    1               ; 1 when v_map holds a level
v_full  rs.l    1               ; channel over the whole screen (title texts)
v_sptop rs.l    1               ; stack pointer for the title
v_spgame rs.l   1               ; stack pointer of the running game
v_intitle rs.w  1               ; 1 while the title menu is shown
v_slow  rs.w    1               ; 1: the enemies get one more move (cobwebs)
v_lastdir rs.w  1               ; direction of the party's last step
v_prog  rs.w    5               ; progress: %, depth, explored %, marks, bosses
v_cname rs.b    NPARTY*NAME_LEN ; the cats' names
v_ltext rs.b    (LTEXT_MAX+1)&~1 ; the text block of the current level
v_svn   rs.b    10              ; save file name 'hum_svN' (QDOS string)
v_shdr  rs.b    SAVE_HEAD       ; save file header
v_ssnum rs.w    1               ; sprite set in v_sprites (0 = none)
v_pos   rs.w    1               ; player cell: y*32+x
v_dir   rs.w    1               ; facing: 0 N, 1 E, 2 S, 3 W
v_args  rs.l    6               ; arguments for text_fmt (at most 6)
v_party rs.b    p_size*NPARTY
v_page  rs.w    1               ; PG_VIEW, PG_MAP or PG_SHEET
v_steps rs.w    1               ; steps since the last bleeding tick
v_rand  rs.w    1               ; random number state
v_cgrp  rs.l    1               ; combat: the enemy group
v_cetab rs.l    1               ; combat: its enemy type (enemytab entry)
v_cfoe  rs.w    9               ; combat: hit points of each enemy (0 = down)
v_cact  rs.w    1               ; combat: cat whose turn it is + 1 (0 = none)
v_msel  rs.w    1               ; menu: chosen line
v_mtop  rs.w    1               ; menu: top line of the box on the screen
v_fight rs.w    1               ; 1 while a fight is going on
v_charm rs.w    1               ; rounds of the Starfolk Charm left
v_charmed rs.w  1               ; the charm was used in this fight
v_crev  rs.b    10              ; combat: enemy n got up again (byte n)
v_cchg  rs.b    10              ; combat: enemy n winds up a heavy blow (byte n)
v_echo  rs.w    1               ; combat: damage of the last cat's hit (0 = none)
v_cround rs.w   1               ; combat: rounds (for the Hum pulses)
v_humc  rs.w    1               ; actions since the last Hum pulse
v_regen rs.w    1               ; steps since the last hit point regained
v_pounce rs.w   1               ; combat: the attack is a pounce
v_track rs.w    1               ; steps since the hunter last tracked prey
v_down  rs.w    1               ; steps since a cat fell (outside fights)
v_mute  rs.w    1               ; 1 = sound off
v_fx    rs.w    1               ; enemies drawn as FX_HIT or FX_ATTACK (render)
v_mwait rs.w    1               ; frames until the next note
v_mptr  rs.l    1               ; next note of the tune, 0 = none
v_beep  rs.b    16              ; IPC block of a note
v_mcount rs.w   1               ; menu: number of lines
v_mtxt  rs.b    MENU_MAX*MENU_LEN ; menu: the lines
v_mw    rs.w    1               ; menu: box width in words
v_mwold rs.w    1               ; width of the box drawn before
v_mitem rs.b    MENU_MAX        ; menu: item of each line (pack menus)
v_pack  rs.b    2*PACK_SLOTS    ; party pack: item, count
v_deep  rs.w    1               ; deepest level reached (saved after the pack)
v_story rs.w    1               ; story flags SF_... (saved after v_deep)
v_seed  rs.w    1               ; places of this game (saved after v_story)
v_sneak rs.w    1               ; 1 = the party sneaks (S key)
v_cend  rs.w    1               ; combat: 0 going on, 1 victory, 2 fled
v_cskip rs.w    1               ; combat: the party lost the rest of the round
v_rtime rs.w    1               ; frames the last render took (DEBUG)
v_fdx   rs.w    1               ; one step forward: dx, dy
v_fdy   rs.w    1
v_rdx   rs.w    1               ; one step to the right: dx, dy
v_rdy   rs.w    1
v_vmask rs.l    1               ; cells in view as bits: 1 = wall
v_vtab  rs.b    VIEW_D*VIEW_L   ; cells in view: view class
v_vgrp  rs.b    VIEW_D*VIEW_L   ; cells in view: enemy type + 1 (0 = none)
        rs.w    0
v_name  rs.b    NAMEBUF         ; file name with device
v_buf   rs.b    BUFLEN          ; formatted text
v_map   rs.b    LEVMAX          ; current level file
v_lvstore rs.b  LVSLOTS*LVDELTA ; what changed in the levels visited
v_vbuf  rs.b    VIEWB*VIEW_H    ; view buffer, copied to the screen at once
v_walls rs.b    WALLMAX         ; current wall set (must start below 32K)
v_sprites rs.b  SPRMAX          ; current sprite set (after the walls, beyond
                                ; 32K: reached as v_walls+WALLMAX)
v_size  rs.b    0               ; text file follows directly
        ifgt    v_walls-32767   ; buffers are reached with lea d16(a5)
        fail    "v_walls must start below 32K"
        endc

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
; One heap block for everything: the variables, then the part of the
; text file kept in memory (room for the larger language).
;---------------------------------------------------------------------
        move.l  #v_size+TXT_RESMAX+1,d1
        and.w   #$fffe,d1
        moveq   #MT_ALCHP,d0
        moveq   #-1,d2
        trap    #1
        tst.l   d0
        bne     leave
        move.l  a0,a5
        move.l  a5,a1           ; clear the variables
        move.w  #v_size/2-1,d0
.clr    clr.w   (a1)+
        dbra    d0,.clr
        move.l  a5,v_heap(a5)
        move.l  a4,v_sp(a5)
        move.w  d7,v_mode(a5)
        bsr     cfg_load        ; the language chosen last time
        bsr     text_load       ; its texts (else the English ones)
        beq.s   .head
        tst.w   v_lang(a5)
        beq.s   .head
        clr.w   v_lang(a5)
        bsr     text_load
.head

        moveq   #MT_INF,d0      ; where are the system variables?
        trap    #1
        move.l  a0,v_sysv(a5)
        moveq   #MT_DMODE,d0    ; Mode 8
        moveq   #8,d1
        moveq   #-1,d2
        trap    #1
        bsr     cls

        lea     fullname(pc),a0 ; a channel over the whole screen
        moveq   #C_BLACK,d5
        bsr     opench
        move.l  a0,v_full(a5)

        lea     v_poll(a5),a0   ; 50 Hz counter via poll list
        lea     pollrt(pc),a1
        move.l  a1,4(a0)
        moveq   #MT_LPOLL,d0
        trap    #1

        lea     msgname(pc),a0
        moveq   #C_BLACK,d5
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
; Milestone 1b: walk through the test level on a 2D debug map
;=====================================================================
start:
        move.l  sp,v_sptop(a5)
        bra     title_loop

mainloop:
        bsr     frame
        bsr     readkeys
        btst    #K_ESC,d0
        bne     .esc
        move.w  v_pkeys(a5),d2  ; M: switch between map and 3D view
        not.w   d2
        and.w   d0,d2
        moveq   #PG_MAP,d1
        btst    #K_MAP,d2
        bne.s   .page
        moveq   #PG_SHEET,d1    ; C: party sheet
        btst    #K_SHEET,d2
        bne.s   .page
        moveq   #PG_PACK,d1     ; I: the pack
        btst    #K_PACK,d2
        bne.s   .page
        moveq   #PG_HELP,d1     ; H: the keys
        btst    #K_HELP,d2
        beq.s   .nomap
.page   cmp.w   v_page(a5),d1   ; the same key again: back to the view
        bne.s   .set
        moveq   #PG_VIEW,d1
.set    move.w  d1,v_page(a5)
        bsr     clear_view
        bsr     redraw
        bra     mainloop
.nomap  btst    #K_SNEAK,d2     ; S: sneak or walk
        beq.s   .nosn
        move.w  #T_SNEAK_OFF,d0
        bchg    #0,v_sneak+1(a5)
        bne.s   .sn1
        move.w  #T_SNEAK_ON,d0
.sn1    bsr     msg_print
        bsr     panel_show
        bra     mainloop
.nosn   btst    #K_SPACE,d2     ; space: party menu
        beq.s   .nomenu
        bsr     wait_free
        bsr     party_menu
        beq.s   .redr
        bsr     groups_act      ; using an item takes time
.redr   bsr     redraw
        bra     mainloop
.nomenu move.w  d0,d1
        and.w   #K_MOVE,d1
        beq.s   .none
        move.w  v_pkeys(a5),d2  ; keys pressed since the last poll
        not.w   d2
        and.w   d1,d2
        bne.s   .new
        subq.w  #1,v_rep(a5)    ; held: repeat after a delay
        bgt     mainloop
        move.w  #REP_NEXT,v_rep(a5)
        move.w  d1,d2
        bra.s   .act
.new    move.w  #REP_FIRST,v_rep(a5)
.act    tst.w   v_page(a5)      ; a page is open: the key closes it, the
        beq.s   .walk           ; party walks only with the view in front
        clr.w   v_page(a5)
        bsr     clear_view
        bsr     redraw
        bsr     wait_free
        bra     mainloop
.walk   bsr     do_keys
        bsr     groups_act
        bsr     hum_tick        ; the Hum may cost the party a turn
        bsr     hazard_warn     ; the scout (or a lantern) sees traps ahead
        bsr     foe_spot        ; ... and the scout enemies
        tst.w   v_sneak(a5)     ; sneaking: the enemies move twice as often
        beq.s   .slw
        bsr     groups_act
.slw
        tst.w   v_slow(a5)      ; cobwebs: the enemies move once more
        beq.s   .rd
        clr.w   v_slow(a5)
        bsr     groups_act
.rd     bsr     redraw
        bra     mainloop
.none   clr.w   v_rep(a5)
        bra     mainloop
.esc    bsr     wait_free       ; ESC: the game menu
        bsr     game_menu
        bra     mainloop

; do_keys: d2 = keys to act on (one action), d0 bit K_SHIFT = strafe
do_keys:
        btst    #K_UP,d2
        beq.s   .n1
        moveq   #0,d1           ; forward
        move.w  #T_STEP,d2
        bra     move_rel
.n1     btst    #K_DOWN,d2
        beq.s   .n2
        moveq   #2,d1           ; back
        move.w  #T_STEP_BACK,d2
        bra     move_rel
.n2     btst    #K_LEFT,d2
        beq.s   .n3
        btst    #K_SHIFT,d0
        beq.s   turn_left
        moveq   #3,d1           ; strafe left
        move.w  #T_STEP_SIDE,d2
        bra     move_rel
.n3     btst    #K_SHIFT,d0
        beq.s   turn_right
        moveq   #1,d1           ; strafe right
        move.w  #T_STEP_SIDE,d2
        bra     move_rel

turn_left:
        subq.w  #1,v_dir(a5)
        move.w  #T_TURN_LEFT,d0
        bra.s   turn
turn_right:
        addq.w  #1,v_dir(a5)
        move.w  #T_TURN_RIGHT,d0
turn:   and.w   #3,v_dir(a5)
        bra     msg_print

;=====================================================================
; Level and movement
;=====================================================================
; level_load: d0 = level number -> EQ = loaded into v_map
level_load:
        movem.l d1-d4/a0-a3,-(sp)
        move.w  d0,v_level(a5)
        lea     v_buf(a5),a2    ; file name 'hum_lN'
        move.l  a2,a0
        lea     lvname(pc),a1
        moveq   #2+6-1,d1
.cp     move.b  (a1)+,(a0)+
        dbra    d1,.cp
        add.b   d0,-1(a0)
        lea     v_name(a5),a3
        bsr     fopen
        bne.s   .e
        lea     v_map(a5),a1
        move.w  #LEVMAX,d2
        moveq   #IO_FSTRG,d0
        moveq   #-1,d3
        trap    #3
        and.l   #$ffff,d1       ; bytes read: only the low word is set
        move.l  d0,d4
        move.l  d1,-(sp)
        moveq   #IO_CLOSE,d0
        trap    #2
        move.l  (sp)+,d1
        move.l  d4,d0
        beq.s   .len
        cmp.l   #ERR_EF,d0      ; shorter than LEVMAX: fine
        bne.s   .e
.len    moveq   #-1,d0
        cmp.l   #LV_EVENT+1,d1  ; at least map, header, end of events
        blo.s   .e
        move.w  v_level(a5),d0  ; and its texts
        bsr     ltext_load
        bsr     lv_shuffle
        ifd     NOENEMY         ; tests: no groups in the level
        move.w  v_map+LV_GROUPS(a5),d0
        lea     v_map(a5),a0
        move.b  #G_END,0(a0,d0.w)
        move.w  #32*32-1,d0
.ng     bclr    #CELL_GROUP,(a0)+
        dbra    d0,.ng
        endc
        moveq   #0,d0
.e      movem.l (sp)+,d1-d4/a0-a3
        tst.l   d0
        rts

; enter_level: d0 = level number; the current level is kept, the new one
;              comes from memory if it was visited, else from its file;
;              then its wall and sprite set. A missing file ends the game.
enter_level:
        movem.l d0-d1/a2,-(sp)
        lea     v_party+p_flags(a5),a2 ; feathers work again on a new level
        moveq   #NPARTY-1,d1
.fe     bclr    #PF_FEATHER,1(a2)
        lea     p_size(a2),a2
        dbra    d1,.fe
        move.w  #TEST_LEVELS,d1 ; the deepest level reached (progress;
        btst    d0,d1           ; test levels do not count)
        bne.s   .dp
        cmp.w   v_deep(a5),d0
        bls.s   .dp
        move.w  d0,v_deep(a5)
.dp     bsr     lv_keep
        bsr     lv_fetch
        beq.s   .sets
        bsr     level_load
        beq.s   .sets
        move.w  #T_NO_LEVEL,d1
        bra.s   level_fatal
.sets   move.w  #1,v_inlv(a5)
        bsr.s   level_sets
        movem.l (sp)+,d0-d1/a2
        rts

; level_sets: the wall and sprite set of the level in v_map, unless they
;             are loaded already
level_sets:
        movem.l d0-d1/a2,-(sp)
        moveq   #0,d0
        move.b  v_map+LV_WALLS(a5),d0
        cmp.w   v_wsnum(a5),d0
        beq.s   .spr
        clr.w   v_wsnum(a5)
        move.w  d0,d1           ; (walls_load keeps d1)
        bsr     walls_load
        bne.s   .nows
        move.w  d1,v_wsnum(a5)
.spr    moveq   #0,d0
        move.b  v_map+LV_SPRITES(a5),d0
        cmp.w   v_ssnum(a5),d0
        beq.s   .e
        clr.w   v_ssnum(a5)
        move.w  d0,d1
        bsr     sprites_load
        bne.s   .noss
        move.w  d1,v_ssnum(a5)
.e      movem.l (sp)+,d0-d1/a2
        rts
.noss   move.w  d1,d0
        move.w  #T_NO_SPRITES,d1
        bra.s   level_fatal
.nows   move.w  d1,d0
        move.w  #T_NO_WALLS,d1
        ; fallthrough

level_fatal:                    ; d0 = number, d1 = "... %d is missing."
        lea     v_args(a5),a2   ; wait for ESC, end
        ext.l   d0
        move.l  d0,(a2)
        move.w  d1,d0
        bsr     msg_print
        bsr     wait_esc
        bra     exit_prog

; txt_file: -> a2 = name of the text file of the language
txt_file:
        lea     txtname(pc),a2
        tst.w   v_lang(a5)
        beq.s   .e
        lea     tdename(pc),a2
.e      rts

; text_load: the text file of the language (v_lang), the part kept in
;            memory -> EQ = loaded (NE: v_text = 0, no texts)
text_load:
        movem.l d1-d4/a0-a3,-(sp)
        clr.l   v_text(a5)
        bsr.s   txt_file
        lea     v_name(a5),a3
        bsr     fopen
        bne.s   .e
        move.w  d4,v_dev(a5)    ; the device the game is on (for saving)
        move.l  a5,a3
        add.l   #v_size,a3
        move.l  a3,a1
        moveq   #TXT_HEAD,d4
        bsr     fread
        bne.s   .cl
        moveq   #-1,d0
        cmp.l   #TXT_MAGIC,(a3)
        bne.s   .cl
        move.l  TXT_LEN(a3),d4
        cmp.l   #TXT_RESMAX,d4
        bhi.s   .cl
        move.l  d4,v_txtres(a5)
        sub.l   #TXT_HEAD,d4
        bls.s   .cl
        lea     TXT_HEAD(a3),a1
        bsr     fread
        bne.s   .cl
        move.l  a3,v_text(a5)
.cl     move.l  d0,d4
        moveq   #IO_CLOSE,d0
        trap    #2
        move.l  d4,d0
.e      movem.l (sp)+,d1-d4/a0-a3
        tst.l   d0
        rts

; cfg_load: the language from hum_cfg (missing: English)
cfg_load:
        movem.l d0-d4/a0-a3,-(sp)
        clr.w   v_lang(a5)
        lea     cfgname(pc),a2
        lea     v_name(a5),a3
        bsr     fopen
        bne.s   .e
        lea     v_lang(a5),a1
        moveq   #2,d4
        bsr     fread
        beq.s   .more
        clr.w   v_lang(a5)
        bra.s   .cl
.more   lea     v_asave(a5),a1  ; autosave setting and slot (since v1.4;
        moveq   #4,d4           ; an older hum_cfg has only the language)
        bsr     fread
        beq.s   .cl
        clr.l   v_asave(a5)
.cl     moveq   #IO_CLOSE,d0
        trap    #2
        and.w   #1,v_lang(a5)
        and.w   #3,v_asave(a5)
        and.w   #1,v_aslot(a5)
.e      movem.l (sp)+,d0-d4/a0-a3
        rts

; cfg_save: language and autosave into hum_cfg (errors are ignored)
cfg_save:
        movem.l d0-d4/a0-a3,-(sp)
        lea     cfgname(pc),a2
        moveq   #2,d3
        bsr     file_open
        bne.s   .e
        lea     v_lang(a5),a1  ; language, autosave setting and slot
        moveq   #6,d4
        bsr     fwrite
        moveq   #IO_CLOSE,d0
        trap    #2
.e      movem.l (sp)+,d0-d4/a0-a3
        rts

; ltext_load: d0 = level; its block of the text file into v_ltext
;             (on any error the level texts are just missing)
ltext_load:
        movem.l d0-d5/a0-a3,-(sp)
        clr.w   v_ltlen(a5)
        move.l  v_text(a5),a1
        lsl.w   #2,d0
        move.w  TXT_SECT(a1,d0.w),d5 ; start
        move.w  TXT_SECT+2(a1,d0.w),d4 ; length
        beq.s   .e
        move.w  d5,v_ltstart(a5)
        bsr     txt_file
        lea     v_name(a5),a3
        move.w  d4,-(sp)
        bsr     fopen
        movem.w (sp)+,d4        ; (movem keeps the flags of fopen)
        bne.s   .e
        moveq   #FS_POSAB,d0
        moveq   #0,d1
        move.w  d5,d1
        moveq   #-1,d3
        trap    #3
        tst.l   d0
        bne.s   .cl
        lea     v_ltext(a5),a1
        and.l   #$ffff,d4
        bsr     fread
        bne.s   .cl
        move.w  d4,v_ltlen(a5)
.cl     moveq   #IO_CLOSE,d0
        trap    #2
.e      movem.l (sp)+,d0-d5/a0-a3
        rts

; lv_shuffle: events and groups of the level in v_map that have other
;             places get one of them (or keep the first); v_seed and the
;             level decide, so the level looks the same at every load.
;             Then the event and group bits of the cells are set anew.
lv_shuffle:
        movem.l d0-d5/a0-a3,-(sp)
        lea     v_map(a5),a0
        move.w  LV_GROUPS(a0),d0
        lea     0(a0,d0.w),a1   ; groups
        move.l  a1,a3
.ge     cmp.b   #G_END,(a1)
        beq.s   .gx
        addq.l  #G_SIZE,a1
        bra.s   .ge
.gx     addq.l  #2,a1           ; the places
        move.w  v_level(a5),d5  ; the generator: seed and level
        mulu    #40503,d5
        add.w   v_seed(a5),d5
.pl     moveq   #0,d0
        move.b  (a1)+,d0        ; kind (0 event, 1 group), $ff = end
        bmi.s   .bits
        moveq   #0,d1
        move.b  (a1)+,d1        ; index
        mulu    #6,d1           ; (EV_SIZE = G_SIZE)
        lea     v_map+LV_EVENT(a5),a2
        tst.b   d0
        beq.s   .ev
        move.l  a3,a2
.ev     add.w   d1,a2
        moveq   #0,d2
        move.b  (a1)+,d2        ; number of other places
        mulu    #25173,d5
        add.w   #13849,d5
        moveq   #0,d3
        move.w  d5,d3
        addq.w  #1,d2
        mulu    d2,d3
        swap    d3              ; 0 = the first place, 1..N another
        subq.w  #1,d2
        add.w   d2,d2
        tst.w   d3
        beq.s   .nx
        add.w   d3,d3
        move.b  -2(a1,d3.w),(a2)+ ; x, y
        move.b  -1(a1,d3.w),(a2)
.nx     add.w   d2,a1
        bra.s   .pl
.bits   move.l  a0,a1           ; event and group bits off
        move.w  #32*32-1,d0
.cl     and.b   #$ff-(1<<CELL_EVENT|1<<CELL_GROUP),(a1)+
        dbra    d0,.cl
        lea     v_map+LV_EVENT(a5),a1 ; and on where they are now
        moveq   #CELL_EVENT,d2
        bsr.s   .set
        move.l  a3,a1
        moveq   #CELL_GROUP,d2
        bsr.s   .set
        movem.l (sp)+,d0-d5/a0-a3
        rts
.set    cmp.b   #$ff,(a1)       ; a1 = table (x, y first, 6 bytes each)
        beq.s   .se
        moveq   #0,d0
        move.b  1(a1),d0
        lsl.w   #5,d0
        moveq   #0,d1
        move.b  (a1),d1
        add.w   d1,d0
        bset    d2,0(a0,d0.w)
        addq.l  #6,a1
        bra.s   .set
.se     rts

; level_start: player to the start cell, show the entry text
level_start:
        lea     v_map(a5),a0
        moveq   #0,d0
        move.b  LV_SY(a0),d0
        ifd     STARTY
        moveq   #STARTY,d0
        endc
        lsl.w   #5,d0
        moveq   #0,d1
        move.b  LV_SX(a0),d1
        ifd     STARTX
        moveq   #STARTX,d1
        endc
        add.w   d1,d0
        move.w  d0,v_pos(a5)
        bset    #CELL_SEEN,0(a0,d0.w)
        moveq   #0,d0
        move.b  LV_DIR(a0),d0
        ifd     STARTDIR
        moveq   #STARTDIR,d0
        endc
        move.w  d0,v_dir(a5)
        move.w  LV_ENTRY(a0),d0
        bra     msg_print

; move_rel: d1 = direction relative to the facing (0 forward, 1 right,
;           2 back, 3 left), d2 = text id shown when the step succeeds.
;           A step forward into a closed door opens it.
move_rel:
        tst.w   v_sneak(a5)     ; sneaking: "You creep on."
        beq.s   .walk
        move.w  #T_CREEP,d2
.walk   move.w  d1,d3           ; relative direction
        add.w   v_dir(a5),d1
        and.w   #3,d1
        move.w  d1,v_lastdir(a5) ; the way the party goes (for slipping)
        add.w   d1,d1
        lea     doff(pc),a0
        move.w  v_pos(a5),d0
        add.w   0(a0,d1.w),d0   ; target cell (border cells always block)
        lea     v_map(a5),a0
        moveq   #CELL_TYPE,d1
        and.b   0(a0,d0.w),d1
        btst    #CELL_GROUP,0(a0,d0.w)
        bne     .group
        lea     celltab(pc),a1
        btst    #0,0(a1,d1.w)   ; CF_BLOCK
        bne.s   .block
        cmp.b   #CT_WATER,d1    ; water: cold and slow
        bne.s   .dry
        move.w  #1,v_slow(a5)
        move.w  v_pos(a5),d1
        moveq   #CELL_TYPE,d3
        and.b   0(a0,d1.w),d3
        cmp.b   #CT_WATER,d3
        beq.s   .dry            ; (already in the water)
        move.w  #T_WATER_COLD,d2
.dry    move.w  d0,v_pos(a5)
        bset    #CELL_SEEN,0(a0,d0.w)
        move.l  d0,-(sp)
        move.w  d2,d0
        bsr     msg_print
        bsr     bleed_step
        tst.w   v_sneak(a5)     ; a normal step can be heard
        bne.s   .quiet
        move.l  (sp),d0         ; (a noise cell is louder: its event)
        moveq   #EV_NOISE,d1
        bsr     event_at
        cmpa.w  #0,a3
        bne.s   .quiet
        moveq   #NOISE_STEP,d1
        bsr     pale_wake
.quiet  move.l  (sp)+,d0
        lea     v_map(a5),a0
        btst    #CELL_EVENT,0(a0,d0.w)
        bne     cell_events
        rts
.block  cmp.b   #CT_DOOR_LOCKED,d1
        beq.s   .locked
        cmp.b   #CT_DOOR,d1
        bne     .wall
        tst.w   d3
        bne.s   .door
        and.b   #~CELL_TYPE,0(a0,d0.w) ; closed -> open door
        or.b    #CT_DOOR_OPEN,0(a0,d0.w)
        moveq   #S_DOOR,d0
        bsr     sound
        move.w  #T_DOOR_OPENS,d0
        bra     msg_print
.door   move.w  #T_DOOR_BLOCKS,d0
        bra     msg_print
.locked move.w  d0,d2           ; a key for this door in the pack?
        moveq   #EV_LOCK,d1
        bsr     event_at
        cmpa.w  #0,a3
        beq.s   .shut
        move.w  EV_PARAM(a3),d0
        cmp.w   #IT_VALVE_WHEEL,d0 ; a door that the valves open
        bne.s   .key
        move.w  #T_DOOR_VALVES,d0
        bra     msg_print
.key
        bsr     pack_count
        beq.s   .shut
        lea     v_args(a5),a2   ; "The <key> fits the lock."
        bsr     item_rec
        move.w  i_name(a0),d0
        bsr     text_get
        move.l  a1,(a2)
        move.w  #T_UNLOCKS,d0
        bsr     msg_print
        lea     v_map(a5),a0
        and.b   #~CELL_TYPE,0(a0,d2.w)
        or.b    #CT_DOOR_OPEN,0(a0,d2.w)
        moveq   #S_DOOR,d0
        bsr     sound
        move.w  #T_DOOR_OPENS,d0
        bra     msg_print
.shut   move.w  #T_DOOR_LOCKED,d0
        bra     msg_print
.wall   moveq   #S_BUMP,d0
        bsr     sound
        move.w  #T_BLOCKED,d0
        bra     msg_print
.group  bsr     group_at        ; walked into an enemy group
        bra     encounter

; hurt_all: d1 = damage for every cat still standing
hurt_all:
        movem.l d0-d3/a0-a3,-(sp)
        moveq   #S_TRAP,d0
        bsr     sound
        lea     v_party(a5),a3
        moveq   #NPARTY-1,d3
.c      tst.w   p_hp(a3)
        ble.s   .n
        sub.w   d1,p_hp(a3)
        movem.l d1,-(sp)
        move.w  d1,d2
        move.w  #T_HIT_FOR,d0
        move.w  p_name(a3),d1
        bsr     name_num_msg
        bsr     fall_check
        movem.l (sp)+,d1
.n      lea     p_size(a3),a3
        dbra    d3,.c
        bsr     panel_show
        bsr     party_check
        movem.l (sp)+,d0-d3/a0-a3
        rts

; rest: every cat is healed in full, wounds and poison are gone, the
;       fallen stand up again
rest:                           ; d0 = text id, 0 = "The glowing pool..."
        movem.l d0-d3/a0-a3,-(sp)
        tst.w   d0
        bne.s   .say
        move.w  #T_REST,d0
.say    bsr     msg_print
        lea     v_party(a5),a3
        moveq   #NPARTY-1,d3
.c      move.w  p_hpbase(a3),p_hpmax(a3)
        move.w  p_hp(a3),d2
        move.w  p_hpmax(a3),p_hp(a3)
        clr.w   p_bleed(a3)
        bclr    #PF_POISON,p_flags+1(a3)
        tst.w   d2
        bgt.s   .n
        move.w  #T_REST_UP,d0
        move.w  p_name(a3),d1
        bsr     name_msg
.n      lea     p_size(a3),a3
        dbra    d3,.c
        bsr     panel_show
        movem.l (sp)+,d0-d3/a0-a3
        rts

; hazard_warn: a standing scout warns of a hazard in the cell ahead; a
;              cat with the Lantern Shard sees two cells ahead. Each
;              hazard is told once (event flag bit 1).
hazard_warn:
        movem.l d0-d5/a0-a3,-(sp)
        lea     v_party(a5),a3  ; who can see it, and how far?
        moveq   #NPARTY-1,d3
        moveq   #0,d4           ; range
        sub.l   a2,a2
.who    tst.w   p_hp(a3)
        ble.s   .wn
        bsr     gear_kind
        cmp.w   #IK_GEAR_LIGHT,d0
        bne.s   .scout
        moveq   #2,d4
        move.l  a3,a2
        bra.s   .look
.scout  cmp.w   #T_ROLE_SCOUT,p_role(a3)
        bne.s   .wn
        tst.w   d4
        bne.s   .wn
        moveq   #1,d4
        move.l  a3,a2
.wn     lea     p_size(a3),a3
        dbra    d3,.who
        tst.w   d4
        beq     .e
.look   lea     doff(pc),a0
        move.w  v_dir(a5),d0
        add.w   d0,d0
        move.w  0(a0,d0.w),d5   ; one cell forward
        move.w  v_pos(a5),d3
        subq.w  #1,d4
.cell   add.w   d5,d3           ; d3 = the cell looked at
        lea     v_map(a5),a0
        moveq   #CELL_TYPE,d0
        and.b   0(a0,d3.w),d0
        lea     celltab(pc),a1
        btst    #0,0(a1,d0.w)   ; a wall: nothing further
        bne.s   .e
        moveq   #31,d1
        and.w   d3,d1           ; x
        move.w  d3,d2
        lsr.w   #5,d2           ; y
        lea     v_map+LV_EVENT(a5),a3
.ev     cmp.b   #EV_END,EV_X(a3)
        beq.s   .nc
        cmp.b   EV_X(a3),d1
        bne.s   .nx
        cmp.b   EV_Y(a3),d2
        bne.s   .nx
        btst    #0,EV_FLAGS(a3) ; (a trap that has gone off: no danger)
        bne.s   .nx
        lea     hazards(pc),a1
        move.b  EV_TYPE(a3),d0
.hz     tst.b   (a1)
        beq.s   .nx
        cmp.b   (a1)+,d0
        bne.s   .hz
        bset    #1,EV_FLAGS(a3) ; told once
        bne.s   .nx
        move.w  #T_WARN,d0
        move.w  p_name(a2),d1
        bsr     name_msg
        bra.s   .e
.nx     addq.l  #EV_SIZE,a3
        bra.s   .ev
.nc     dbra    d4,.cell
.e      movem.l (sp)+,d0-d5/a0-a3
        rts

; foe_spot: the scout (standing) sees an enemy group up to SPOT_RANGE
;           cells straight ahead and says what it is, once per group
SPOT_RANGE equ  2
foe_spot:
        movem.l d0-d5/a0-a3,-(sp)
        lea     v_party(a5),a2
        moveq   #NPARTY-1,d3
.who    tst.w   p_hp(a2)
        ble.s   .wn
        cmp.w   #T_ROLE_SCOUT,p_role(a2)
        beq.s   .look
.wn     lea     p_size(a2),a2
        dbra    d3,.who
        bra     .e
.look   lea     doff(pc),a0
        move.w  v_dir(a5),d0
        add.w   d0,d0
        move.w  0(a0,d0.w),d5   ; one cell forward
        move.w  v_pos(a5),d3
        moveq   #SPOT_RANGE-1,d4
.cell   add.w   d5,d3
        lea     v_map(a5),a0
        moveq   #CELL_TYPE,d0
        and.b   0(a0,d3.w),d0
        lea     celltab(pc),a1
        btst    #0,0(a1,d0.w)   ; a wall or a closed door: no further
        bne.s   .e
        btst    #CELL_GROUP,0(a0,d3.w)
        bne.s   .grp
        dbra    d4,.cell
        bra.s   .e
.grp    move.w  d3,d0
        bsr     group_at        ; -> a3
        move.l  a3,d0
        beq.s   .e
        bset    #GF_SPOT,G_FLAGS(a3)
        bne.s   .e              ; told before
        lea     v_args(a5),a1   ; "<scout> spots something: <n> <enemies>"
        move.w  p_name(a2),d0
        move.l  a1,-(sp)
        bsr     text_get
        move.l  (sp)+,a0
        move.l  a1,(a0)
        moveq   #0,d0
        move.b  G_COUNT(a3),d0
        move.l  d0,4(a0)
        moveq   #0,d1
        move.b  G_TYPE(a3),d1
        mulu    #e_size,d1
        lea     enemytab(pc),a1
        add.w   d1,a1
        move.w  e_plural(a1),d1
        cmp.w   #1,d0
        bne.s   .pl
        move.w  e_name(a1),d1
.pl     move.w  d1,d0
        bsr     text_get
        move.l  a1,8(a0)
        move.l  a0,a2           ; (msg_print: a2 = arguments)
        move.w  #T_SPOTTED,d0
        bsr     msg_print
.e      movem.l (sp)+,d0-d5/a0-a3
        rts

; hum_tick: after an action on a Hum level: a warning two actions
;           before, then a pulse; the party staggers, the enemies move
hum_tick:
        btst    #LF_HUM,v_map+LV_FLAGS(a5)
        beq.s   .e
        move.l  d0,-(sp)
        addq.w  #1,v_humc(a5)
        move.w  v_humc(a5),d0
        cmp.w   #HUM_STEPS-2,d0
        bne.s   .p
        move.w  #T_HUM_WARN,d0
        bsr     msg_print
        bra.s   .x
.p      cmp.w   #HUM_STEPS,d0
        blo.s   .x
        clr.w   v_humc(a5)
        moveq   #S_HUM,d0
        bsr     sound
        move.w  #T_HUM_PULSE,d0
        bsr     msg_print
        bsr     groups_act
.x      move.l  (sp)+,d0
.e      rts

; pale_wake: d1 = range; listening groups that near wake up and hunt
pale_wake:
        movem.l d0-d4/a0,-(sp)
        move.w  v_pos(a5),d3
        moveq   #31,d2
        and.w   d3,d2           ; party x
        lsr.w   #5,d3           ; party y
        moveq   #0,d4           ; woken
        move.w  v_map+LV_GROUPS(a5),d0
        lea     v_map(a5),a0
        add.w   d0,a0
.g      cmp.b   #G_END,G_X(a0)
        beq.s   .e
        btst    #GF_GONE,G_FLAGS(a0)
        bne.s   .n
        cmp.b   #GM_LISTEN,G_MODE(a0)
        bne.s   .n
        moveq   #0,d0
        move.b  G_X(a0),d0
        sub.w   d2,d0
        bpl.s   .x
        neg.w   d0
.x      cmp.w   d1,d0
        bhi.s   .n
        moveq   #0,d0
        move.b  G_Y(a0),d0
        sub.w   d3,d0
        bpl.s   .y
        neg.w   d0
.y      cmp.w   d1,d0
        bhi.s   .n
        move.b  #GM_HUNT,G_MODE(a0)
        bset    #GF_SEEN,G_FLAGS(a0) ; (no "something moves")
        moveq   #1,d4
.n      addq.l  #G_SIZE,a0
        bra.s   .g
.e      tst.w   d4
        beq.s   .q
        move.w  #T_PALE_HEARS,d0
        bsr     msg_print
.q      movem.l (sp)+,d0-d4/a0
        rts

; wake_guards: every guard group of the level hunts now (not the bosses)
wake_guards:
        movem.l d0/a0-a1,-(sp)
        move.w  v_map+LV_GROUPS(a5),d0
        lea     v_map(a5),a0
        add.w   d0,a0
        lea     enemytab(pc),a1
.g      cmp.b   #G_END,G_X(a0)
        beq.s   .e
        cmp.b   #GM_GUARD,G_MODE(a0)
        bne.s   .n
        moveq   #0,d0
        move.b  G_TYPE(a0),d0
        mulu    #e_size,d0
        tst.w   e_boss(a1,d0.w)
        bne.s   .n
        move.b  #GM_HUNT,G_MODE(a0)
.n      addq.l  #G_SIZE,a0
        bra.s   .g
.e      movem.l (sp)+,d0/a0-a1
        rts

; slide: one more cell the way the party went, if it is free
slide:
        movem.l d0-d1/a0,-(sp)
        move.w  v_lastdir(a5),d1
        add.w   d1,d1
        lea     doff(pc),a0
        move.w  v_pos(a5),d0
        add.w   0(a0,d1.w),d0
        lea     v_map(a5),a0
        btst    #CELL_GROUP,0(a0,d0.w)
        bne.s   .e
        moveq   #CELL_TYPE,d1
        and.b   0(a0,d0.w),d1
        lea     celltab(pc),a0
        btst    #0,0(a0,d1.w)   ; CF_BLOCK
        bne.s   .e
        move.w  d0,v_pos(a5)
        lea     v_map(a5),a0
        bset    #CELL_SEEN,0(a0,d0.w)
.e      movem.l (sp)+,d0-d1/a0
        rts

; valve_turn: a3 = valve event; a Valve Wheel from the pack is fitted and
;             turned; when every valve of the level is open, the doors
;             locked with VALVE_WHEEL open
valve_turn:
        movem.l d0-d2/a0-a3,-(sp)
        btst    #0,EV_FLAGS(a3)
        beq.s   .v1
        move.w  #T_VALVE_DONE,d0
        bsr     msg_print
        bra     .e
.v1     move.w  #IT_VALVE_WHEEL,d0
        bsr     pack_count
        bne.s   .v2
        move.w  #T_VALVE_EMPTY,d0
        bsr     msg_print
        bra.s   .e
.v2     bsr     pack_take
        bset    #0,EV_FLAGS(a3)
        move.w  #T_VALVE_TURN,d0
        bsr     msg_print
        lea     v_map+LV_EVENT(a5),a0 ; all valves open?
.all    cmp.b   #EV_END,EV_X(a0)
        beq.s   .open
        cmp.b   #EV_VALVE,EV_TYPE(a0)
        bne.s   .a1
        btst    #0,EV_FLAGS(a0)
        beq.s   .e
.a1     addq.l  #EV_SIZE,a0
        bra.s   .all
.open   lea     v_map+LV_EVENT(a5),a0 ; open the valve doors
        lea     v_map(a5),a1
.d      cmp.b   #EV_END,EV_X(a0)
        beq.s   .said
        cmp.b   #EV_LOCK,EV_TYPE(a0)
        bne.s   .d1
        cmp.w   #IT_VALVE_WHEEL,EV_PARAM(a0)
        bne.s   .d1
        moveq   #0,d0
        move.b  EV_Y(a0),d0
        lsl.w   #5,d0
        moveq   #0,d1
        move.b  EV_X(a0),d1
        add.w   d1,d0
        and.b   #~CELL_TYPE,0(a1,d0.w)
        or.b    #CT_DOOR_OPEN,0(a1,d0.w)
.d1     addq.l  #EV_SIZE,a0
        bra.s   .d
.said   move.w  #T_CISTERN_OPEN,d0
        bsr     msg_print
.e      movem.l (sp)+,d0-d2/a0-a3
        rts

; event_at: d0 = cell, d1 = event type -> a3 = event (0 if none)
event_at:
        movem.l d2-d3,-(sp)
        moveq   #31,d2
        and.w   d0,d2           ; x
        move.w  d0,d3
        lsr.w   #5,d3           ; y
        lea     v_map+LV_EVENT(a5),a3
.l      cmp.b   #EV_END,EV_X(a3)
        beq.s   .none
        cmp.b   EV_X(a3),d2
        bne.s   .nx
        cmp.b   EV_Y(a3),d3
        bne.s   .nx
        cmp.b   EV_TYPE(a3),d1
        beq.s   .e
.nx     addq.l  #EV_SIZE,a3
        bra.s   .l
.none   sub.l   a3,a3
.e      movem.l (sp)+,d2-d3
        rts

; cell_events: the player has entered cell d0, which has events
cell_events:
        movem.l d0-d4/a0-a3,-(sp)
        moveq   #31,d3
        and.w   d0,d3           ; x
        move.w  d0,d4
        lsr.w   #5,d4           ; y
        lea     v_map+LV_EVENT(a5),a3
.ev     move.b  EV_X(a3),d0
        cmp.b   #EV_END,d0
        beq     .e
        cmp.b   d3,d0
        bne     .nx
        cmp.b   EV_Y(a3),d4
        bne     .nx
        move.b  EV_TYPE(a3),d0
        cmp.b   #EV_STAIRS,d0
        beq     .stairs
        cmp.b   #EV_MARK,d0
        beq     .mark
        cmp.b   #EV_TRAP,d0
        beq     .trap
        cmp.b   #EV_ITEM,d0
        beq     .item
        cmp.b   #EV_BOARDS,d0
        beq     .boards
        cmp.b   #EV_COBWEB,d0
        beq     .cobweb
        cmp.b   #EV_EXIT,d0
        beq     .exit
        cmp.b   #EV_ECHO,d0
        beq     .echo
        cmp.b   #EV_SLIP,d0
        beq     .slip
        cmp.b   #EV_VALVE,d0
        beq     .valve
        cmp.b   #EV_RUBBLE,d0
        beq     .rubble
        cmp.b   #EV_HANDCAR,d0
        beq     .handcar
        cmp.b   #EV_SPORES,d0
        beq     .spores
        cmp.b   #EV_SINKHOLE,d0
        beq     .sink
        cmp.b   #EV_REST,d0
        beq     .rest
        cmp.b   #EV_COLLAPSE,d0
        beq     .coll
        cmp.b   #EV_NOISE,d0
        beq     .noise
        cmp.b   #EV_MESSAGE,d0
        bne     .nx             ; gather, lock: not when entering
        bset    #0,EV_FLAGS(a3) ; message: only the first time
        bne.s   .nx
        move.w  EV_PARAM(a3),d0
        bsr     msg_print
        bra.s   .nx
.mark   bset    #0,EV_FLAGS(a3) ; (found: counts for the progress)
        moveq   #S_MARK,d0
        bsr     sound
        move.w  #T_MARK_SEEN,d0 ; Scratch-Mark: the carved text in yellow
        bsr     msg_print
        moveq   #C_YEL,d1
        bsr     msg_ink
        move.w  EV_PARAM(a3),d0
        bsr     msg_print
        moveq   #C_WHITE,d1
        bsr     msg_ink
.nx     addq.l  #EV_SIZE,a3
        bra     .ev
.item   btst    #0,EV_FLAGS(a3) ; item: until it is taken
        bne     .nx
        moveq   #0,d0
        move.b  EV_PARAM(a3),d0 ; item
        moveq   #0,d1
        move.b  EV_PARAM+1(a3),d1 ; count
        move.w  d1,d2
        bsr     pack_add
        bne.s   .took
        bsr     item_rec        ; (pack_add keeps d0 = item)
        move.w  #T_PACK_FULL,d0
        cmp.w   #IK_MOSS,i_kind(a0)
        bne.s   .full
        move.w  #T_MOSS_FULL,d0
.full   bsr     msg_print
        bra     .nx
.took   bset    #0,EV_FLAGS(a3)
        lea     v_args(a5),a2   ; "Found: <item> x<n>."
        move.l  d1,-(sp)
        bsr     item_rec
        move.w  i_name(a0),d0
        bsr     text_get
        move.l  a1,(a2)
        move.l  (sp)+,d1
        move.l  d1,4(a2)
        moveq   #S_FOUND,d0
        bsr     sound
        move.w  #T_FOUND,d0
        bsr     msg_print
        cmp.w   d1,d2           ; not all of the moss found room
        beq     .nx
        move.w  #T_MOSS_FULL,d0
        bsr     msg_print
        bra     .nx
.boards bset    #0,EV_FLAGS(a3) ; loose boards: once, a cat is hurt
        bne     .nx
        move.w  EV_PARAM(a3),d1 ; damage<<12 | text id
        move.w  d1,d0
        and.w   #$fff,d0
        bsr     msg_print
        moveq   #12,d0
        lsr.w   d0,d1
        movem.l a2-a3,-(sp)
        bsr     pick_random     ; -> a3 = a standing cat
        beq.s   .b1
        sub.w   d1,p_hp(a3)
        move.w  d1,d2
        move.w  #T_HIT_FOR,d0
        move.w  p_name(a3),d1
        bsr     name_num_msg
        bsr     fall_check
        bsr     party_check
.b1     movem.l (sp)+,a2-a3
        bra     .nx
.cobweb move.w  EV_PARAM(a3),d0 ; cobwebs: every time, slow
        bsr     msg_print
        move.w  #1,v_slow(a5)
        bra     .nx
.exit   move.w  EV_PARAM(a3),d0 ; stairs that lead nowhere
        bsr     msg_print
        bra     .nx
.echo   bset    #0,EV_FLAGS(a3) ; an echo trap: once, every guard wakes up
        bne     .nx
        move.w  EV_PARAM(a3),d0
        bsr     msg_print
        bsr     wake_guards
        bra     .nx
.slip   move.w  EV_PARAM(a3),d0 ; slippery: slide one more cell
        bsr     msg_print
        bsr     slide
        bra     .e              ; (the party is somewhere else now)
.valve  bsr     valve_turn
        bra     .nx
.rubble bset    #0,EV_FLAGS(a3) ; falling rubble: once, every cat is hit
        bne     .nx
        move.w  EV_PARAM(a3),d1 ; damage<<12 | text id
        move.w  d1,d0
        and.w   #$fff,d0
        bsr     msg_print
        moveq   #12,d0
        lsr.w   d0,d1
        bsr     hurt_all
        bra     .nx
.handcar move.w #IT_HANDCAR_LEVER,d0 ; the handcar: a ride with the lever
        bsr     pack_count
        bne.s   .ride
        move.w  #T_HANDCAR_NO,d0
        bsr     msg_print
        bra     .nx
.ride   bsr     redraw          ; ride? (stepping on the stop is not
        bsr     menu_clear      ; enough: the party may only pass by)
        move.w  #T_YES,d0
        bsr     menu_addt
        move.w  #T_NO,d0
        bsr     menu_addt
        move.w  #T_HANDCAR_ASK,d0
        bsr     text_get
        bsr     menu_run
        tst.w   d0
        bne     .nx             ; no, or cancelled
        move.w  #T_HANDCAR_GO,d0
        bsr     msg_print
        move.w  EV_PARAM(a3),d0 ; y<<5 | x
        move.w  d0,v_pos(a5)
        lea     v_map(a5),a0
        bset    #CELL_SEEN,0(a0,d0.w)
        bra     .e              ; (somewhere else now)
.spores move.w  EV_PARAM(a3),d0 ; spores: every time, a cat may be poisoned
        bsr     msg_print
        bsr     rand
        btst    #8,d0
        beq     .nx
        movem.l a2-a3,-(sp)
        bsr     pick_random     ; -> a3 = a standing cat
        beq.s   .sp1
        bsr     poison_cat
        bsr     panel_show
.sp1    movem.l (sp)+,a2-a3
        bra     .nx
.coll   bset    #0,EV_FLAGS(a3) ; a collapsing floor: once
        bne     .nx
        move.w  #T_COLLAPSE,d0
        bra.s   .fall
.sink   move.w  #T_SINKHOLE,d0  ; a sinkhole: down to the cave below, hurt
.fall   bsr     msg_print
        move.w  EV_PARAM(a3),d0 ; y<<5 | x
        move.w  d0,v_pos(a5)
        lea     v_map(a5),a0
        bset    #CELL_SEEN,0(a0,d0.w)
        moveq   #2,d1
        bsr     hurt_all
        bra     .e              ; (somewhere else now)
.noise  move.w  #T_SOFT,d0      ; something loud underfoot
        tst.w   v_sneak(a5)
        bne.s   .soft
        move.w  EV_PARAM(a3),d0
        bsr     msg_print
        moveq   #NOISE_LOUD,d1
        bsr     pale_wake
        bra     .nx
.soft   bsr     msg_print
        bra     .nx
.rest   move.w  EV_PARAM(a3),d0 ; a resting place (its text, 0: the pool's)
        bsr     rest
        bra     .nx
.trap   bset    #0,EV_FLAGS(a3) ; trap: only the first time
        bne     .nx
        moveq   #S_TRAP,d0
        bsr     sound
        move.w  EV_PARAM(a3),d1 ; bleed<<12 | text id
        move.w  d1,d0
        and.w   #$fff,d0
        bsr     msg_print
        moveq   #12,d0
        lsr.w   d0,d1
        bsr     wound_random
        bra     .nx
.stairs move.w  EV_PARAM(a3),d0 ; level<<10 | y<<5 | x: its file there?
        moveq   #10,d2
        lsr.w   d2,d0
        bsr     level_exists
        beq.s   .go
        move.w  #T_NOT_YET,d0   ; not built yet: the way is blocked
        bsr     msg_print
        bra     .e
.go     moveq   #S_STAIRS,d0
        bsr     sound
        move.w  #T_STAIRS_DOWN,d0
        move.w  v_pos(a5),d1
        lea     v_map(a5),a0
        moveq   #CELL_TYPE,d2
        and.b   0(a0,d1.w),d2
        cmp.b   #CT_STAIRS_DOWN,d2
        beq.s   .down
        move.w  #T_STAIRS_UP,d0
.down   bsr     msg_print
        move.w  EV_PARAM(a3),d1 ; level<<10 | y<<5 | x
        move.w  d1,d0
        moveq   #10,d2
        lsr.w   d2,d0
.there  bsr     enter_level     ; replaces the map: no more events here
        and.w   #$3ff,d1
        move.w  d1,v_pos(a5)
        lea     v_map(a5),a0
        bset    #CELL_SEEN,0(a0,d1.w)
        move.w  LV_ENTRY(a0),d0
        bsr     msg_print
        moveq   #AS_LEVEL,d0    ; a new level: the game is saved
        bsr     autosave
.e      movem.l (sp)+,d0-d4/a0-a3
        rts

; group_at: d0 = cell -> a3 = group standing there (0 if none)
group_at:
        movem.l d1-d2/a0,-(sp)
        moveq   #31,d1
        and.w   d0,d1           ; x
        move.w  d0,d2
        lsr.w   #5,d2           ; y
        move.w  v_map+LV_GROUPS(a5),d0
        lea     v_map(a5),a3
        add.w   d0,a3
.l      cmp.b   #G_END,G_X(a3)
        beq.s   .none
        btst    #GF_GONE,G_FLAGS(a3)
        bne.s   .nx
        cmp.b   G_X(a3),d1
        bne.s   .nx
        cmp.b   G_Y(a3),d2
        beq.s   .e
.nx     addq.l  #G_SIZE,a3
        bra.s   .l
.none   sub.l   a3,a3
.e      movem.l (sp)+,d1-d2/a0
        rts

; groups_act: after every action of the party; hunters within HUNT_RANGE
;             take one step towards the party, a hunter next to it attacks
groups_act:
        movem.l d0-d7/a0-a3,-(sp)
        move.w  v_pos(a5),d6
        moveq   #31,d4
        and.w   d6,d4           ; party x
        lsr.w   #5,d6           ; party y
        move.w  v_map+LV_GROUPS(a5),d0
        lea     v_map(a5),a3
        add.w   d0,a3
.grp    cmp.b   #G_END,G_X(a3)
        beq     .e
        btst    #GF_GONE,G_FLAGS(a3)
        bne     .nx
        cmp.b   #GM_GUARD,G_MODE(a3) ; hunters and swimmers move
        beq     .nx
        cmp.b   #GM_LISTEN,G_MODE(a3)
        beq     .nx
        bsr     .dist           ; d0 = distance, d1 = dx, d2 = dy
        cmp.w   #HUNT_RANGE,d0
        bhi     .nx
        bset    #GF_SEEN,G_FLAGS(a3)
        bne.s   .seen
        move.w  #T_SOMETHING_MOVES,d0
        bsr     msg_print
        bsr     .dist
.seen   cmp.w   #1,d0
        beq     .attack
        bsr.s   .step
        bsr.s   .dist
        cmp.w   #1,d0
        beq.s   .attack
        cmp.b   #GM_FLUTTER,G_MODE(a3) ; flutterers: a second move
        bne.s   .nx
        bsr.s   .step
        bsr.s   .dist
        cmp.w   #1,d0
        beq.s   .attack
.nx     addq.l  #G_SIZE,a3
        bra     .grp
.attack bsr     encounter
.e      movem.l (sp)+,d0-d7/a0-a3
        rts
.step   move.w  d1,d5           ; one step: the longer axis first, then
        bpl.s   .a1             ; the other (flutterers sometimes the
        neg.w   d5              ; other way round: erratic)
.a1     move.w  d2,d7
        bpl.s   .a2
        neg.w   d7
.a2     cmp.b   #GM_FLUTTER,G_MODE(a3)
        bne.s   .a3
        move.w  d0,-(sp)
        bsr     rand100
        cmp.w   #33,d0
        movem.w (sp)+,d0        ; (keeps the flags)
        bhs.s   .a3
        exg     d5,d7
.a3     cmp.w   d7,d5
        blt.s   .ydir
        bsr.s   .stepx
        beq.s   .moved
        bsr.s   .stepy
        bra.s   .moved
.ydir   bsr.s   .stepy
        beq.s   .moved
        bsr.s   .stepx
.moved  rts
.dist   moveq   #0,d1           ; dx = party x - group x, dy likewise
        move.b  G_X(a3),d1
        neg.w   d1
        add.w   d4,d1
        moveq   #0,d2
        move.b  G_Y(a3),d2
        neg.w   d2
        add.w   d6,d2
        move.w  d1,d0
        bpl.s   .d1
        neg.w   d0
.d1     move.w  d2,d3
        bpl.s   .d2
        neg.w   d3
.d2     add.w   d3,d0
        rts
.stepx  moveq   #0,d3           ; one step in x towards the party -> EQ = done
        tst.w   d1
        beq     .no
        moveq   #1,d3
        tst.w   d1
        bpl.s   .try
        moveq   #-1,d3
        bra.s   .try
.stepy  moveq   #0,d3
        tst.w   d2
        beq.s   .no
        moveq   #32,d3
        tst.w   d2
        bpl.s   .try
        moveq   #-32,d3
.try    moveq   #0,d0           ; d3 = map offset of the step
        move.b  G_Y(a3),d0
        lsl.w   #5,d0
        moveq   #0,d5
        move.b  G_X(a3),d5
        add.w   d5,d0           ; group cell
        lea     v_map(a5),a0
        move.w  d0,d5
        add.w   d3,d5           ; target cell
        cmp.w   v_pos(a5),d5
        beq.s   .no
        btst    #CELL_GROUP,0(a0,d5.w)
        bne.s   .no
        moveq   #CELL_TYPE,d7
        and.b   0(a0,d5.w),d7
        lea     celltab(pc),a1
        btst    #0,0(a1,d7.w)   ; CF_BLOCK
        bne.s   .no
        cmp.b   #GM_SWIM,G_MODE(a3) ; swimmers stay in the water
        bne.s   .ok
        cmp.b   #CT_WATER,d7
        bne.s   .no
.ok     bclr    #CELL_GROUP,0(a0,d0.w)
        bset    #CELL_GROUP,0(a0,d5.w)
        moveq   #31,d0
        and.w   d5,d0
        move.b  d0,G_X(a3)
        lsr.w   #5,d5
        move.b  d5,G_Y(a3)
        bsr     .dist
        moveq   #0,d3           ; EQ: moved
        rts
.no     moveq   #1,d3           ; NE: could not move
        rts

; encounter: a3 = group next to the party. The party turns to it,
;            "<enemy> attacks!", then the fight.
encounter:
        movem.l d0-d3/a0-a2,-(sp)
        moveq   #0,d0           ; direction from the party to the group
        move.b  G_Y(a3),d0
        lsl.w   #5,d0
        moveq   #0,d1
        move.b  G_X(a3),d1
        add.w   d1,d0
        sub.w   v_pos(a5),d0    ; -32, 1, 32 or -1
        lea     doff(pc),a0
        moveq   #0,d1
.dir    cmp.w   (a0)+,d0
        beq.s   .face
        addq.w  #1,d1
        cmp.w   #4,d1
        blo.s   .dir
        bra.s   .show
.face   move.w  d1,v_dir(a5)
.show   bsr     redraw          ; the group in front of the party
        lea     enemytab(pc),a0
        moveq   #0,d0
        move.b  G_TYPE(a3),d0
        mulu    #e_size,d0
        add.w   d0,a0
        lea     v_args(a5),a2
        moveq   #0,d3
        move.b  G_COUNT(a3),d3
        cmp.w   #1,d3
        bne.s   .many
        move.w  e_name(a0),d0   ; "<enemy> attacks!"
        bsr     text_get
        move.l  a1,(a2)
        move.w  #T_ATTACKS,d0
        bra.s   .say
.many   move.l  d3,(a2)         ; "<n> <enemies> attack!"
        move.w  e_plural(a0),d0
        bsr     text_get
        move.l  a1,4(a2)
        move.w  #T_GROUP_ATTACKS,d0
.say    move.w  d0,d3           ; ("attacks!")
        move.w  e_trait(a0),d1  ; the Pale Ones: a choice first
        cmp.w   #TR_KEEPER,d1
        beq     .keeper
        cmp.w   #TR_ELDER,d1
        beq.s   .elder
        cmp.w   #TR_PALE,d1
        bne     .fight
        cmp.b   #GM_LISTEN,G_MODE(a3) ; (awake ones just attack)
        bne.s   .pfight
        move.w  #T_PALE_MEET,d0
        move.w  #T_PASS,d1
        bsr     pale_choice
        bne.s   .pchose
        move.w  #T_PALE_PASS,d0
        bra.s   .gone
.pchose bset    #SF_PATTACK,v_story+1(a5) ; a calm Pale One attacked
        bra     .chose
.elder  btst    #SF_PATTACK,v_story+1(a5) ; the party hurt her children:
        beq.s   .eldc           ; no words, no choice
        move.w  #T_ELDER_ANGRY,d0
        bsr     msg_print
        bra     .pfight
.eldc   move.w  #T_ELDER_MEET,d0
        move.w  #T_SPARE,d1
        bsr     pale_choice
        bne.s   .chose
        bset    #SF_SPARED,v_story+1(a5)
        move.w  #IT_HEART_STONE,d0
        moveq   #1,d1
        bsr     pack_add
        move.w  #T_ELDER_SPARE,d0
.gone   bsr     msg_print       ; the group goes away
        bset    #GF_GONE,G_FLAGS(a3)
        moveq   #0,d0
        move.b  G_Y(a3),d0
        lsl.w   #5,d0
        moveq   #0,d1
        move.b  G_X(a3),d1
        add.w   d1,d0
        lea     v_map(a5),a0
        bclr    #CELL_GROUP,0(a0,d0.w)
        bra.s   .e
.chose  move.w  #T_FIGHT_ON,d3  ; (the menu used v_args: no names)
.pfight bset    #SF_PFOUGHT,v_story+1(a5)
.fight  move.w  d3,d0
        bsr     msg_print
        bsr     pause
        bsr     combat
.e      movem.l (sp)+,d0-d3/a0-a2
        rts
.keeper bsr     keeper_meet     ; the end of the way
        beq.s   .e              ; (not reached when it ends the game)
        bsr     pause
        bsr     combat
        cmp.w   #CE_VICTORY,v_cend(a5)
        bne.s   .e
        moveq   #END_B,d0       ; the Keeper is beaten: the Silence
        bra     ending

; keeper_meet: a0 = the Keeper's type. Its words; with the Heart Stone a
;              choice: use it (ending A), lay down (ending C) or fight.
;              -> NE = fight (EQ: the party chose not to; does not happen)
keeper_meet:
        movem.l d0-d2/a0-a1,-(sp)
        move.w  #T_KEEPER_MEET,d0
        bsr     msg_print
        btst    #SF_SPARED,v_story+1(a5) ; the Elder gave the Heart Stone
        bne.s   .ask            ; (counts even when the pack was full)
        move.w  #IT_HEART_STONE,d0
        bsr     pack_count
        beq.s   .fight
.ask    bsr     menu_clear
        move.w  #T_USE_STONE,d0
        bsr     menu_addt
        move.w  #T_LAY_DOWN,d0
        bsr     menu_addt
        move.w  #T_FIGHT,d0
        bsr     menu_addt
        move.l  12(sp),a0
        move.w  e_name(a0),d0
        bsr     text_get
        bsr     menu_run
        tst.w   d0
        bmi.s   .ask
        bsr     view_refresh
        moveq   #END_A,d1       ; 0: the Heart Stone, 1: lay down
        tst.w   d0
        beq.s   .end
        moveq   #END_C,d1
        cmp.w   #1,d0
        beq.s   .end
.fight  move.w  #T_FIGHT_ON,d0
        bsr     msg_print
        movem.l (sp)+,d0-d2/a0-a1
        moveq   #1,d0           ; NE: fight
        rts
.end    move.w  d1,d0
        bra     ending

; pale_choice: d0 = text of the meeting, d1 = text of the peaceful choice
;              -> EQ = the peaceful one, NE = fight
pale_choice:
        movem.l d0-d2/a0-a1,-(sp)
        move.w  d1,d2
        bsr     msg_print
.ask    bsr     menu_clear
        move.w  #T_FIGHT,d0
        bsr     menu_addt
        move.w  d2,d0
        bsr     menu_addt
        move.l  12(sp),a0       ; (the enemy type, kept on the stack)
        move.w  e_name(a0),d0
        bsr     text_get
        bsr     menu_run
        tst.w   d0
        bmi.s   .ask
        bsr     view_refresh
        cmp.w   #1,d0
        movem.l (sp)+,d0-d2/a0-a1
        rts

;---------------------------------------------------------------------
; Exit: close channels, Mode 4, free the heap, back to BASIC
;---------------------------------------------------------------------
exit_prog:
        lea     v_poll(a5),a0
        moveq   #MT_RPOLL,d0
        trap    #1
        move.l  v_msg(a5),a0
        moveq   #IO_CLOSE,d0
        trap    #2
        move.l  v_full(a5),a0
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
;        -> d0 = error (EQ = ok), a0 = channel, d4 = device (0 = default
;           directory, 1-3 = win1_, flp1_, mdv1_)
fopen:
        movem.l d1-d3/a1-a3,-(sp)
        moveq   #0,d4
.try    bsr.s   dev_name
        moveq   #IO_OPEN,d0
        moveq   #-1,d1
        moveq   #1,d3           ; old file, shared
        trap    #2
        tst.l   d0
        beq.s   .ok
        addq.w  #1,d4
        cmp.w   #4,d4
        bne.s   .try
.ok     movem.l (sp)+,d1-d3/a1-a3
        tst.l   d0
        rts

; dev_name: d4 = device (0 = none), a2 = file name, a3 = buffer
;           -> a0 = a3 = device + name as a QDOS string
dev_name:
        movem.l d0-d1/a1,-(sp)
        lea     2(a3),a1
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
        movem.l (sp)+,d0-d1/a1
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
        and.l   #$ffff,d1       ; bytes read: only the low word is set
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
text_get:                       ; (keeps all other registers)
        move.l  d0,-(sp)
        cmp.w   #NAME_ID,d0     ; a cat's name?
        bhs.s   .name
        move.l  v_text(a5),a1
        add.w   d0,d0
        move.w  TXT_OFFS(a1,d0.w),d0
        and.l   #$ffff,d0
        cmp.l   v_txtres(a5),d0 ; in the part kept in memory?
        bhs.s   .level
        add.l   d0,a1
        move.l  (sp)+,d0
        rts
.level  sub.w   v_ltstart(a5),d0 ; in the block of the current level?
        bcs.s   .none
        cmp.w   v_ltlen(a5),d0
        bhs.s   .none
        lea     v_ltext(a5),a1
        add.l   d0,a1
        move.l  (sp)+,d0
        rts
.none   lea     notxt(pc),a1    ; another level's text: not loaded
        move.l  (sp)+,d0
        rts
.name   sub.w   #NAME_ID,d0
        mulu    #NAME_LEN,d0
        lea     v_cname(a5),a1
        add.l   d0,a1
        move.l  (sp)+,d0
        rts

; text_fmt: d0.w = text id, a2 = arguments (one long each: %s = pointer
;           to a zero-terminated string, %d = number in the low word)
;           -> a1 = v_buf, zero-terminated
text_fmt:
        movem.l d0-d3/a0/a2-a3,-(sp)
        bsr.s   text_get
        lea     v_buf(a5),a0
        move.w  #BUFLEN-8,d3    ; room left (a number needs up to 6)
.c      move.b  (a1)+,d0
        beq.s   .end
        cmp.b   #'%',d0
        bne.s   .put
        move.b  (a1)+,d0
        cmp.b   #'s',d0
        beq.s   .str
        cmp.b   #'d',d0
        beq.s   .num
        cmp.b   #'%',d0         ; %%: one percent sign
        beq.s   .put
        subq.l  #1,a1           ; unknown: keep the '%'
        moveq   #'%',d0
.put    move.b  d0,(a0)+
        subq.w  #1,d3
        bgt.s   .c
        bra.s   .end
.str    move.l  (a2)+,a3
.sc     move.b  (a3)+,d0
        beq.s   .c
        move.b  d0,(a0)+
        subq.w  #1,d3
        bgt.s   .sc
        bra.s   .end
.num    move.l  (a2)+,d0
        ext.l   d0
        bpl.s   .pos
        move.b  #'-',(a0)+
        subq.w  #1,d3
        neg.l   d0
.pos    moveq   #0,d1           ; digit count
.div    divu    #10,d0
        swap    d0
        add.b   #'0',d0
        move.b  d0,-(sp)        ; (byte push keeps sp even: one word each)
        clr.w   d0
        swap    d0
        addq.w  #1,d1
        tst.w   d0
        bne.s   .div
.pop    move.b  (sp)+,(a0)+
        subq.w  #1,d3
        subq.w  #1,d1
        bne.s   .pop
        tst.w   d3
        bgt.s   .c
.end    clr.b   (a0)
        lea     v_buf(a5),a1
        movem.l (sp)+,d0-d3/a0/a2-a3
        rts

; print_str: a0 = channel, a1 = zero-terminated string
print_str:
        movem.l d0-d3/a1,-(sp)
        move.l  a1,d1
        moveq   #-1,d2
.len    addq.w  #1,d2
        tst.b   (a1)+
        bne.s   .len
        move.l  d1,a1
        moveq   #IO_SSTRG,d0
        bsr     io3
        movem.l (sp)+,d0-d3/a1
        rts

; msg_ink: d1 = ink colour of the message window
msg_ink:
        movem.l d0-d3/a0-a1,-(sp)
        move.l  v_msg(a5),a0
        moveq   #SD_SETIN,d0
        bsr     io3
        movem.l (sp)+,d0-d3/a0-a1
        rts

; msg_print: d0.w = text id, a2 = arguments
;            printed on a new line of the message window
msg_print:
        movem.l d0-d3/a0-a1,-(sp)
        bsr     text_fmt
        move.l  v_msg(a5),a0
        bsr.s   print_str
        lea     newline(pc),a1  ; QDOS keeps the newline pending: no scroll
        moveq   #1,d2
        moveq   #IO_SSTRG,d0
        bsr     io3
        movem.l (sp)+,d0-d3/a0-a1
        rts

;=====================================================================
; Channels
;=====================================================================
opench:                         ; a0 = name, d5 = paper -> a0 = channel
        moveq   #IO_OPEN,d0
        moveq   #-1,d1
        moveq   #0,d3
        trap    #2
        moveq   #SD_BORDR,d0
        moveq   #0,d1
        moveq   #0,d2
        bsr.s   io3
        moveq   #SD_SETPA,d0
        move.w  d5,d1
        bsr.s   io3
        moveq   #SD_SETST,d0
        move.w  d5,d1
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
        move.w  d1,-(sp)
        lea     kr7(pc),a3      ; shift: strafe
        moveq   #MT_IPCOM,d0
        trap    #1
        move.w  d1,-(sp)
        lea     kr5(pc),a3      ; I: the pack
        moveq   #MT_IPCOM,d0
        trap    #1
        move.w  d1,-(sp)
        lea     kr2(pc),a3      ; M: debug map
        moveq   #MT_IPCOM,d0
        trap    #1
        move.w  d1,d3
        move.w  (sp)+,d2
        btst    #2,d2
        beq.s   .ni
        bset    #8,d3           ; (bit 8 of the row 2 word is free)
.ni             move.w  (sp)+,d2
        move.w  (sp)+,d1
        move.w  (sp)+,d0
        btst    #0,d2
        beq.s   .sh
        bset    #K_SHIFT,d0
.sh     btst    #6,d3
        beq.s   .m
        bset    #K_MAP,d0
.m      btst    #3,d3
        beq.s   .c
        bset    #K_SHEET,d0
.c      btst    #8,d3
        beq.s   .i
        bset    #K_PACK,d0
.i      btst    #1,d1           ; F1 = left
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
.f5     move.w  d0,-(sp)
        lea     kr3(pc),a3      ; S: sneak
        moveq   #MT_IPCOM,d0
        trap    #1
        move.w  d1,-(sp)
        lea     kr4(pc),a3      ; H: the keys
        moveq   #MT_IPCOM,d0
        trap    #1
        move.w  d1,d2
        move.w  (sp)+,d1
        move.w  (sp)+,d0
        btst    #3,d1
        beq.s   .s
        bset    #K_SNEAK,d0
.s      btst    #2,d2
        beq.s   .h
        bset    #K_HELP,d0
.h      move.w  v_keys(a5),v_pkeys(a5)
        move.w  d0,v_keys(a5)
        move.l  v_sysv(a5),a0   ; empty the keyboard queue, so that the keys
        move.l  $4c(a0),d1      ; pressed in the game do not end up in BASIC
        beq.s   .q
        move.l  d1,a0
        move.l  8(a0),12(a0)    ; next out = next in
.q      movem.l (sp)+,d1-d3/a0-a3
        rts

pcount: dc.w    0               ; frames (50 Hz), counted by pollrt

pollrt: move.l  a0,-(sp)        ; called by QDOS 50 times a second
        lea     pcount(pc),a0
        addq.w  #1,(a0)
        move.l  (sp)+,a0
        rts

frame:                          ; give the CPU away for one frame (20 ms)
        movem.l d0-d3/a0-a3,-(sp)
        moveq   #MT_SUSJB,d0
        moveq   #-1,d1
        moveq   #1,d3
        sub.l   a1,a1
        trap    #1
        movem.l (sp)+,d0-d3/a0-a3
        bra     music_tick

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

draw_frame:                     ; placeholder layout: separator line
        moveq   #0,d0
        move.w  #SEP_Y+3,d1
        moveq   #64,d2
        moveq   #2,d3
        moveq   #C_RED,d4
        bra.s   fill_rect

redraw:                         ; after a step or turn
        move.w  #VIEW_H,v_mtop(a5) ; no menu box on the screen any more
        bsr     mark_view
        cmp.w   #PG_MAP,v_page(a5)
        bne.s   .nomap
        bsr     draw_map
        bra     panel_show
.nomap  cmp.w   #PG_SHEET,v_page(a5)
        bne.s   .nosh
        bsr     sheet_show
        bra     panel_show
.nosh   cmp.w   #PG_PACK,v_page(a5)
        bne.s   .nopk
        bsr     pack_show
        bra     panel_show
.nopk   cmp.w   #PG_HELP,v_page(a5)
        bne.s   .view
        bsr     help_show
        bra     panel_show
.view   move.w  pcount(pc),-(sp)
        bsr     render
        move.w  pcount(pc),d0
        sub.w   (sp)+,d0
        move.w  d0,v_rtime(a5)
        bra     panel_show

MAP_ITEM   equ  $2828           ; a dot of 2 pixels: yellow
MAP_VALVE  equ  $2814           ; ... cyan
MAP_TURNED equ  $283c           ; ... white
MAP_HANDCAR equ $003c           ; ... magenta

; draw_map (key M): the automap, the cells the party has seen as 4x4
; pixel cells, visited floor in blue, items yellow, valve sockets cyan
; (turned: white), handcar stops magenta, the player as a yellow arrow;
; no enemies. The party does not walk while it is open.
; mark_view: the open cells the party can see ahead (up to 3, until a
;            wall or closed door) and the open cells left and right of
;            them count as seen (for the map and the progress)
mark_view:
        movem.l d0-d4/a0-a1,-(sp)
        lea     doff(pc),a0
        move.w  v_dir(a5),d0
        add.w   d0,d0
        move.w  0(a0,d0.w),d2   ; one cell forward
        move.w  v_dir(a5),d0
        addq.w  #1,d0
        and.w   #3,d0
        add.w   d0,d0
        move.w  0(a0,d0.w),d3   ; one cell to the right
        lea     v_map(a5),a0
        lea     celltab(pc),a1
        move.w  v_pos(a5),d0
        moveq   #3-1,d4
.fw     add.w   d2,d0
        bsr.s   .open
        beq.s   .e              ; a wall: nothing further is seen
        bset    #CELL_SEEN,0(a0,d0.w)
        move.w  d0,-(sp)
        add.w   d3,d0           ; right
        bsr.s   .open
        beq.s   .l
        bset    #CELL_SEEN,0(a0,d0.w)
.l      move.w  (sp),d0
        sub.w   d3,d0           ; left
        bsr.s   .open
        beq.s   .n
        bset    #CELL_SEEN,0(a0,d0.w)
.n      move.w  (sp)+,d0
        dbra    d4,.fw
.e      movem.l (sp)+,d0-d4/a0-a1
        rts
.open   cmp.w   #1024,d0        ; d0 = cell -> NE = inside and open
        bhs.s   .no
        moveq   #CELL_TYPE,d1
        and.b   0(a0,d0.w),d1
        btst    #0,0(a1,d1.w)   ; CF_BLOCK
        eori.b  #4,ccr          ; (blocking: EQ)
        rts
.no     cmp.w   d0,d0           ; EQ
        rts

; map_known: a1 = map cell, d4 = x, d5 = y -> NE = the party has seen it
;            (walked on it or next to it)
map_known:
        ifd     MAPALL          ; tests: the whole level is known
        moveq   #1,d0           ; (NE; d0 is free here)
        rts
        endc
        btst    #CELL_SEEN,(a1)
        bne.s   .e
        tst.w   d4
        beq.s   .x1
        btst    #CELL_SEEN,-1(a1)
        bne.s   .e
.x1     cmp.w   #31,d4
        beq.s   .y0
        btst    #CELL_SEEN,1(a1)
        bne.s   .e
.y0     tst.w   d5
        beq.s   .y1
        btst    #CELL_SEEN,-32(a1)
        bne.s   .e
.y1     cmp.w   #31,d5
        beq.s   .no
        btst    #CELL_SEEN,32(a1)
.e      rts
.no     moveq   #0,d0           ; (sets EQ; d0 is free here)
        rts

draw_map:
        movem.l d0-d7/a0-a4,-(sp)
        lea     SCREEN+MAP_X*2,a0
        lea     v_map(a5),a1
        lea     colw(pc),a2
        lea     cellcol(pc),a3
        moveq   #31,d7          ; rows
.row    move.l  a0,a4
        moveq   #31,d6          ; cells
.cell   moveq   #31,d4          ; only what the party has seen: the cells
        sub.w   d6,d4           ; it walked on and their neighbours
        moveq   #31,d5
        sub.w   d7,d5
        moveq   #0,d2           ; (unknown: black)
        bsr     map_known
        beq.s   .col
        move.b  (a1),d0
        moveq   #CELL_TYPE,d1
        and.b   d0,d1
        move.b  0(a3,d1.w),d2   ; (no enemies on the map: they are seen in
        tst.b   d2              ; the view, or the scout tells of them)
        bne.s   .col
        btst    #CELL_SEEN,d0
        beq.s   .col
        moveq   #C_BLUE,d2
.col    add.w   d2,d2
        move.w  0(a2,d2.w),d2
        move.w  d2,(a4)
        move.w  d2,LINEB(a4)
        move.w  d2,LINEB*2(a4)
        move.w  d2,LINEB*3(a4)
        addq.l  #2,a4
        addq.l  #1,a1
        dbra    d6,.cell
        lea     LINEB*4(a0),a0
        dbra    d7,.row
        lea     v_map+LV_EVENT(a5),a1 ; items not taken: a yellow dot;
.itm    cmp.b   #EV_END,EV_X(a1)        ; valve sockets: cyan, turned: white
        beq     .iend
        move.w  #MAP_HANDCAR,d3 ; a handcar stop: magenta
        cmp.b   #EV_HANDCAR,EV_TYPE(a1)
        beq.s   .it2
        move.w  #MAP_VALVE,d3
        cmp.b   #EV_VALVE,EV_TYPE(a1)
        bne.s   .it1
        btst    #0,EV_FLAGS(a1)
        beq.s   .it2
        move.w  #MAP_TURNED,d3
        bra.s   .it2
.it1    move.w  #MAP_ITEM,d3
        cmp.b   #EV_ITEM,EV_TYPE(a1)
        bne.s   .inx
        btst    #0,EV_FLAGS(a1)
        bne.s   .inx
.it2    moveq   #0,d5           ; only where the party has been
        move.b  EV_Y(a1),d5
        moveq   #0,d4
        move.b  EV_X(a1),d4
        move.w  d5,d0
        lsl.w   #5,d0
        add.w   d4,d0
        move.l  a1,-(sp)
        lea     v_map(a5),a1
        add.w   d0,a1
        bsr     map_known
        movem.l (sp)+,a1        ; (keeps the flags)
        beq.s   .inx
        moveq   #0,d0
        move.b  EV_Y(a1),d0
        mulu    #LINEB*4,d0
        moveq   #0,d1
        move.b  EV_X(a1),d1
        add.w   d1,d1
        add.w   d1,d0
        lea     SCREEN+MAP_X*2+LINEB,a0
        add.l   d0,a0
        move.w  d3,(a0)
        move.w  d3,LINEB(a0)
.inx    addq.l  #EV_SIZE,a1
        bra     .itm
.iend   move.w  v_pos(a5),d0    ; player
        moveq   #31,d1
        and.w   d0,d1
        lsr.w   #5,d0
        mulu    #LINEB*4,d0
        add.w   d1,d1
        add.w   d1,d0
        lea     SCREEN+MAP_X*2,a0
        add.l   d0,a0
        lea     arrows(pc),a1
        move.w  v_dir(a5),d0
        lsl.w   #3,d0
        add.w   d0,a1
        move.w  (a1)+,(a0)
        move.w  (a1)+,LINEB(a0)
        move.w  (a1)+,LINEB*2(a0)
        move.w  (a1)+,LINEB*3(a0)
        movem.l (sp)+,d0-d7/a0-a4
        rts

        include 'render.asm'    ; first-person view
        include 'hud.asm'       ; party panel, 4 px font
        include 'combat.asm'    ; fights
        include 'items.asm'     ; pack, items, gear, menus
        include 'skills.asm'    ; healer skills, moss
        include 'state.asm'     ; level memory, save, load, game menu
        include 'title.asm'     ; title, names, intro, game over
        include 'sound.asm'     ; IPC beeps and tunes

;=====================================================================
; Party
;=====================================================================
party_init:
        lea     partyinit(pc),a0
        lea     v_party(a5),a1
        moveq   #NPARTY*p_size/2-1,d0
.c      move.w  (a0)+,(a1)+
        dbra    d0,.c
        move.w  pcount(pc),v_rand(a5)
        lea     v_party(a5),a1  ; the names into v_cname, p_name points there
        lea     v_cname(a5),a2
        moveq   #0,d1
.nm     move.w  p_name(a1),d0
        move.l  a1,-(sp)
        bsr     text_get
        move.l  a2,a0
        moveq   #NAME_LEN-2,d0
.nc     move.b  (a1)+,(a0)+
        dbeq    d0,.nc
        clr.b   (a0)
        move.l  (sp)+,a1
        move.w  d1,d0
        add.w   #NAME_ID,d0
        move.w  d0,p_name(a1)
        lea     NAME_LEN(a2),a2
        lea     p_size(a1),a1
        addq.w  #1,d1
        cmp.w   #NPARTY,d1
        blo.s   .nm
        lea     v_party(a5),a1
        ifd     HPTEST          ; Mossfern 5, Quickwhisker 2, Sedgepelt 0 HP
        move.w  #5,p_size+p_hp(a1)
        move.w  #2,2*p_size+p_hp(a1)
        clr.w   3*p_size+p_hp(a1)
        endc
        ifd     HEALERDOWN      ; Mossfern has fallen
        clr.w   p_size+p_hp(a1)
        endc
        ifd     XPTEST
        move.w  #38,p_xp(a1)
        move.w  #38,p_size+p_xp(a1)
        move.w  #38,2*p_size+p_xp(a1)
        move.w  #38,3*p_size+p_xp(a1)
        endc
        ifd     BLEEDTEST       ; Ashclaw Deep Wound, Mossfern Scratch,
        move.w  #3,p_bleed(a1)  ; Quickwhisker Gash
        move.w  #1,p_size+p_bleed(a1)
        move.w  #2,2*p_size+p_bleed(a1)
        endc
        rts

        ifd     ITEMTEST
item_test:                      ; the pack for tests
        lea     v_pack(a5),a0
        move.l  #IT_MARIGOLD_LEAF<<24|2<<16|IT_STARFOLK_FEATHER<<8|1,(a0)+
        move.l  #IT_THISTLE_CHARM<<24|1<<16|IT_COBWEB_WRAP<<8|1,(a0)+
        move.l  #IT_STALE_PREY<<24|1<<16|IT_HERB<<8|2,(a0)+
        move.w  #IT_VALVE_WHEEL<<8|3,(a0)+
        move.w  #IT_HEART_STONE<<8|1,(a0)+
        move.w  #IT_HANDCAR_LEVER<<8|1,(a0)+
        rts
        endc

; rand: -> d0.w random number (16 bit linear congruential generator)
rand:   move.w  v_rand(a5),d0
        mulu    #25173,d0
        add.w   #13849,d0
        move.w  d0,v_rand(a5)
        rts

; pick_random: -> a3 = a random cat that is still standing, EQ = none
pick_random:
        movem.l d0/d2-d3,-(sp)
        lea     v_party(a5),a3
        moveq   #0,d2           ; cats standing
        moveq   #NPARTY-1,d3
.cnt    tst.w   p_hp(a3)
        ble.s   .c1
        addq.w  #1,d2
.c1     lea     p_size(a3),a3
        dbra    d3,.cnt
        tst.w   d2
        beq.s   .e
        bsr     rand            ; pick one of them
        mulu    d2,d0
        swap    d0              ; 0 .. standing-1
        lea     v_party(a5),a3
.find   tst.w   p_hp(a3)
        ble.s   .f1
        subq.w  #1,d0
        bmi.s   .hit
.f1     lea     p_size(a3),a3
        bra.s   .find
.hit    moveq   #1,d2           ; NE
.e      movem.l (sp)+,d0/d2-d3  ; (keeps the flags)
        rts

; level_exists: d0 = level -> EQ = its file can be opened
level_exists:
        movem.l d0-d4/a0-a3,-(sp)
        lea     v_buf(a5),a2    ; file name 'hum_lN'
        move.l  a2,a0
        lea     lvname(pc),a1
        moveq   #2+6-1,d1
.cp     move.b  (a1)+,(a0)+
        dbra    d1,.cp
        add.b   d0,-1(a0)
        lea     v_name(a5),a3
        bsr     fopen
        bne.s   .e
        moveq   #IO_CLOSE,d0
        trap    #2
        moveq   #0,d0
.e      movem.l (sp)+,d0-d4/a0-a3 ; (keeps the flags)
        rts

; wound_random: d1 = bleed level; a random cat that is still standing
;               bleeds at least that much
wound_random:
        movem.l d0-d3/a0-a3,-(sp)
        bsr     pick_random
        beq.s   .e
.hit    cmp.w   p_bleed(a3),d1
        bls.s   .msg
        move.w  d1,p_bleed(a3)
.msg    lea     v_args(a5),a2   ; "%s is bleeding!"
        move.w  p_name(a3),d0
        bsr     text_get
        move.l  a1,(a2)
        move.w  #T_BLEEDING,d0
        bsr     msg_print
.e      movem.l (sp)+,d0-d3/a0-a3
        rts

; bleed_step: after a step; every BLEED_STEPS steps a wound tick
bleed_step:
        lea     v_party+p_wrap(a5),a0 ; wraps last a number of steps
        moveq   #NPARTY-1,d0
.wr     tst.w   (a0)
        beq.s   .wn
        subq.w  #1,(a0)
.wn     lea     p_size(a0),a0
        dbra    d0,.wr
        cmp.w   #AS_STEPS,v_asave(a5) ; autosave every AS_EVERY steps?
        bne.s   .as
        addq.w  #1,v_asteps(a5)
        cmp.w   #AS_EVERY,v_asteps(a5)
        blo.s   .as
        moveq   #AS_STEPS,d0
        bsr     autosave
.as     cmp.w   #TRACK_STEPS,v_track(a5) ; the prey forgets the hunter
        bhs.s   .tr
        addq.w  #1,v_track(a5)
.tr     bsr     get_up          ; the fallen get up after a while
        addq.w  #1,v_regen(a5)  ; resting while walking: a hit point back
        cmp.w   #REGEN_STEPS,v_regen(a5)
        blo.s   .bl
        clr.w   v_regen(a5)
        bsr     regen
.bl     addq.w  #1,v_steps(a5)
        cmp.w   #BLEED_STEPS,v_steps(a5)
        blo.s   .e
        clr.w   v_steps(a5)
        bsr     wound_tick
        bra     party_check
.e      rts

; get_up: after a step; DOWN_STEPS steps after a cat fell it gets up
;         again by itself with 1 HP, worn out: its maximum is a quarter
;         lower until a Moss Pack or a resting place heals it (the quick
;         way up is the healer's Starfolk Call)
DOWN_STEPS equ  60
get_up:
        movem.l d0-d2/a0,-(sp)
        lea     v_party(a5),a0
        moveq   #NPARTY-1,d0
        moveq   #0,d1
.c      tst.w   p_hp(a0)        ; somebody down?
        bgt.s   .n
        moveq   #1,d1
.n      lea     p_size(a0),a0
        dbra    d0,.c
        tst.w   d1
        bne.s   .down
        clr.w   v_down(a5)
        bra.s   .e
.down   addq.w  #1,v_down(a5)
        cmp.w   #DOWN_STEPS,v_down(a5)
        blo.s   .e
        clr.w   v_down(a5)
        lea     v_party(a5),a0
        moveq   #NPARTY-1,d2
.u      tst.w   p_hp(a0)
        bgt.s   .un
        move.w  #1,p_hp(a0)
        move.w  p_hpmax(a0),d0  ; worn out
        lsr.w   #2,d0
        sub.w   d0,p_hpmax(a0)
        move.w  #T_GETS_TIRED,d0 ; "<cat> gets back up, worn out."
        move.w  p_name(a0),d1
        bsr     name_msg
.un     lea     p_size(a0),a0
        dbra    d2,.u
        bsr     panel_show
.e      movem.l (sp)+,d0-d2/a0
        rts

; regen: every standing cat that neither bleeds nor is poisoned gets a hit
;        point back (up to its maximum)
regen:
        movem.l d0-d1/a0,-(sp)
        lea     v_party(a5),a0
        moveq   #NPARTY-1,d0
.c      tst.w   p_hp(a0)
        ble.s   .n
        tst.w   p_bleed(a0)
        bne.s   .n
        btst    #PF_POISON,p_flags+1(a0)
        bne.s   .n
        move.w  p_hp(a0),d1
        cmp.w   p_hpmax(a0),d1
        bge.s   .n
        addq.w  #1,p_hp(a0)
.n      lea     p_size(a0),a0
        dbra    d0,.c
        movem.l (sp)+,d0-d1/a0
        rts

; wound_tick: bleeding cats lose 1-3 hit points (a Deep Wound also lowers
;             the maximum), poisoned cats 1; every BLEED_STEPS steps and
;             every combat round
wound_tick:
        movem.l d0-d3/a0-a3,-(sp)
        lea     v_party(a5),a3
        moveq   #NPARTY-1,d3
.cat    tst.w   p_hp(a3)
        ble.s   .nx
        btst    #0,p_flags+1(a3)
        beq.s   .bleed
        subq.w  #1,p_hp(a3)     ; poison
.bleed  move.w  p_bleed(a3),d1
        beq.s   .fall
        tst.w   p_wrap(a3)      ; a Cobweb Wrap holds the bleeding
        bne.s   .fall
        sub.w   d1,p_hp(a3)
        cmp.w   #3,d1
        bne.s   .cap
        move.w  p_hpbase(a3),d0 ; Deep Wound: max HP down to DEEP_MIN %
        mulu    #DEEP_MIN,d0
        divu    #100,d0
        cmp.w   p_hpmax(a3),d0
        bge.s   .cap
        subq.w  #1,p_hpmax(a3)
.cap    move.w  p_hpmax(a3),d0
        cmp.w   p_hp(a3),d0
        bge.s   .fall
        move.w  d0,p_hp(a3)
.fall   bsr.s   fall_check
.nx     lea     p_size(a3),a3
        dbra    d3,.cat
        bsr     panel_show
        movem.l (sp)+,d0-d3/a0-a3
        rts

; fall_check: a3 = cat; at 0 hit points or less it falls
fall_check:
        tst.w   p_hp(a3)
        bgt.s   .e
        movem.l d0-d1/a1-a2,-(sp)
        bsr     gear_kind       ; a Starfolk Feather: up again once per level
        cmp.w   #IK_GEAR_REVIVE,d0
        bne.s   .fall
        bset    #PF_FEATHER,p_flags+1(a3)
        bne.s   .fall
        move.w  p_hpmax(a3),d0
        lsr.w   #2,d0
        bne.s   .q
        moveq   #1,d0
.q      move.w  d0,p_hp(a3)
        move.w  #T_REVIVE,d0
        move.w  p_name(a3),d1
        bsr     name_msg
        bra.s   .done
.fall
        clr.w   p_hp(a3)
        clr.w   p_bleed(a3)
        and.w   #1<<PF_FEATHER,p_flags(a3)
        lea     v_args(a5),a2   ; "%s falls."
        move.w  p_name(a3),d0
        bsr     text_get
        move.l  a1,(a2)
        moveq   #S_FALL,d0
        bsr     sound
        move.w  #T_FALLS,d0
        bsr     msg_print
.done   movem.l (sp)+,d0-d1/a1-a2
.e      rts

; party_check: when every cat has fallen the game is over
party_check:
        lea     v_party+p_hp(a5),a0
        moveq   #NPARTY-1,d0
.l      tst.w   (a0)
        bgt.s   .e
        lea     p_size(a0),a0
        dbra    d0,.l
        bra     game_over
.e      rts

; cat_status: a3 = cat -> d0 = 0 unhurt, 1-3 bleeding, 4 fallen,
;             5 poisoned (bleeding is shown first)
cat_status:
        moveq   #4,d0
        tst.w   p_hp(a3)
        ble.s   .e
        move.w  p_bleed(a3),d0
        bne.s   .e
        moveq   #5,d0
        btst    #0,p_flags+1(a3)
        bne.s   .e
        moveq   #6,d0           ; afraid
        btst    #PF_FEAR,p_flags+1(a3)
        bne.s   .e
        moveq   #0,d0
.e      rts

;=====================================================================
; Data
;=====================================================================
colw:   dc.w    $0000,$0055,$00aa,$00ff ; colour -> word of 4 pixels
        dc.w    $aa00,$aa55,$aaaa,$aaff ; (G = even bits high, R/B low)
kr1:    dc.b    9,1,0,0,0,0,1,2         ; IPC: KEYROW(1)
kr0:    dc.b    9,1,0,0,0,0,0,2         ; IPC: KEYROW(0)
kr2:    dc.b    9,1,0,0,0,0,2,2         ; IPC: KEYROW(2)
kr5:    dc.b    9,1,0,0,0,0,5,2         ; IPC: KEYROW(5)
kr3:    dc.b    9,1,0,0,0,0,3,2         ; IPC: KEYROW(3)
kr4:    dc.b    9,1,0,0,0,0,4,2         ; IPC: KEYROW(4)
steps:  dc.w    0,-1,1,0,0,1,-1,0       ; dx, dy of one step N, E, S, W
kr7:    dc.b    9,1,0,0,0,0,7,2         ; IPC: KEYROW(7)
doff:   dc.w    -32,1,32,-1             ; map offset of one step N, E, S, W
arrows: dc.w    $2828,$aaaa,$2828,$2828 ; player on the debug map: N
        dc.w    $0808,$aaaa,$0808,$0000 ; E
        dc.w    $2828,$2828,$aaaa,$2828 ; S
        dc.w    $2020,$aaaa,$2020,$0000 ; W
hazards: dc.b   EV_TRAP,EV_BOARDS,EV_RUBBLE,EV_SPORES,EV_SINKHOLE,EV_COLLAPSE
        dc.b    EV_NOISE,0      ; what the scout warns of
newline: dc.b   10
notxt:  dc.b    0
        even
devices: dc.b   'win1_flp1_mdv1_'
        even
txtname: qstr   'hum_txt'
tdename: qstr   'hum_tde'
cfgname: qstr   'hum_cfg'
lvname: qstr    'hum_l0'
wsname: qstr    'hum_w0'
ssname: qstr    'hum_s0'
svname: qstr    'hum_sv0'
msgname: qstr   'con_512x120a0x136'
fullname: qstr  'con_512x256a0x0'
scrname: qstr   'hum_scr'
picname: qstr   'hum_p0'
wheel:  dc.b    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-',39
wheel_end:
        even
notext: qstr    'hum_txt missing'

        include 'leveltab.inc'  ; cell flags, debug colours
        include 'font.inc'      ; panel font (tools/fontc.py)
        include 'partytab.inc'  ; party start values, ranks (tools/datac.py)
