;=====================================================================
; Sound: IPC beeps (included by hum.asm)
;
; sound: d0 = S_... number. Effects are one IPC "initiate sound" block
; each (the IPC plays it on its own); tunes are notes (pitch, frames)
; played one after the other by music_tick, which frame calls 50 times
; a second while the game waits. A new sound stops a tune. Nothing is
; played while the sound is off (game menu, v_mute).
; QL pitch p: about 11065 / (8 + p) Hz (measured in sQLux), so a higher p
; is a lower note.
;=====================================================================
S_BUMP     equ  0               ; effects
S_DOOR     equ  1
S_FOUND    equ  2
S_MARK     equ  3
S_TRAP     equ  4
S_HIT      equ  5               ; a cat hits an enemy
S_HURT     equ  6               ; an enemy hits a cat
S_MISS     equ  7
S_FALL     equ  8               ; a cat or an enemy falls
S_HUM      equ  9               ; a pulse of the Hum
S_TUNES    equ  10              ; tunes from here on
S_STAIRS   equ  10
S_VICTORY  equ  11
S_RANK     equ  12
S_GAMEOVER equ  13
S_ENDING   equ  14

; sound: d0 = S_... (all registers are kept)
sound:
        movem.l d0-d3/a0-a3,-(sp)
        tst.w   v_mute(a5)
        bne.s   .e
        clr.l   v_mptr(a5)
        cmp.w   #S_TUNES,d0
        bhs.s   .tune
        add.w   d0,d0
        lea     sndtab(pc),a3
        add.w   0(a3,d0.w),a3
        moveq   #MT_IPCOM,d0
        trap    #1
.e      movem.l (sp)+,d0-d3/a0-a3
        rts
.tune   sub.w   #S_TUNES,d0
        add.w   d0,d0
        lea     tunetab(pc),a0
        add.w   0(a0,d0.w),a0
        move.l  a0,v_mptr(a5)
        move.w  #1,v_mwait(a5)
        bra.s   .e

; music_tick: one frame of the tune that plays (called by frame)
music_tick:
        movem.l d0-d3/a0-a3,-(sp)
        move.l  v_mptr(a5),d0
        beq.s   .e
        subq.w  #1,v_mwait(a5)
        bgt.s   .e
        move.l  d0,a0
        moveq   #0,d1
        move.b  (a0)+,d1        ; pitch, 0 = end of the tune
        beq.s   .end
        moveq   #0,d2
        move.b  (a0)+,d2        ; frames
        move.l  a0,v_mptr(a5)
        move.w  d2,v_mwait(a5)
        lea     v_beep(a5),a3   ; IPC: initiate sound
        lea     sndnote(pc),a0
        moveq   #16/2-1,d0
.cp     move.w  (a0)+,(a3)+
        dbra    d0,.cp
        lea     -16(a3),a3
        move.b  d1,6(a3)        ; pitch 1 = pitch 2
        move.b  d1,7(a3)
        mulu    #343,d2         ; 3/4 of the note, in units of 43.64 us
        move.b  d2,10(a3)       ; duration, low byte first
        lsr.w   #8,d2
        move.b  d2,11(a3)
        moveq   #MT_IPCOM,d0
        trap    #1
        bra.s   .e
.end    clr.l   v_mptr(a5)
.e      movem.l (sp)+,d0-d3/a0-a3
        rts

; sound_wait: until the tune has ended (at most d1+1 frames)
sound_wait:
        move.l  d1,-(sp)
.w      tst.l   v_mptr(a5)
        beq.s   .e
        bsr     frame
        dbra    d1,.w
.e      move.l  (sp)+,d1
        rts

; IPC blocks: $0a, 8 parameters, mask, pitch 1, pitch 2, x step (lo, hi),
; duration (lo, hi), y step / wrap, fuzz / random, no reply
sndtab: dc.w    sn_bump-sndtab,sn_door-sndtab,sn_found-sndtab,sn_mark-sndtab
        dc.w    sn_trap-sndtab,sn_hit-sndtab,sn_hurt-sndtab,sn_miss-sndtab
        dc.w    sn_fall-sndtab,sn_hum-sndtab
sn_bump:  dc.b  $0a,8,0,0,$aa,$aa,100,100,0,0,$00,$03,$00,$80,1
sn_door:  dc.b  $0a,8,0,0,$aa,$aa,60,90,$10,0,$00,$0c,$f1,$40,1
sn_found: dc.b  $0a,8,0,0,$aa,$aa,30,6,$10,0,$00,$06,$31,$00,1
sn_mark:  dc.b  $0a,8,0,0,$aa,$aa,20,14,$08,0,$00,$0c,$21,$00,1
sn_trap:  dc.b  $0a,8,0,0,$aa,$aa,120,200,$10,0,$00,$08,$f1,$ff,1
sn_hit:   dc.b  $0a,8,0,0,$aa,$aa,8,16,$40,0,$00,$03,$11,$00,1
sn_hurt:  dc.b  $0a,8,0,0,$aa,$aa,50,80,$20,0,$00,$04,$11,$44,1
sn_miss:  dc.b  $0a,8,0,0,$aa,$aa,2,6,$08,0,$00,$02,$00,$88,1
sn_fall:  dc.b  $0a,8,0,0,$aa,$aa,30,90,$40,0,$00,$18,$f1,$00,1
sn_hum:   dc.b  $0a,8,0,0,$aa,$aa,200,230,$04,0,$00,$30,$f1,$22,1
sndnote:  dc.b  $0a,8,0,0,$aa,$aa,0,0,0,0,0,0,0,0,1,0
        even

; tunes: pitch, frames ... 0
; (C3 77, D3 67, E3 59, G3 48, C4 34, D4 30, E4 26, G4 20, C5 13)
tunetab: dc.w   tn_stairs-tunetab,tn_victory-tunetab,tn_rank-tunetab
        dc.w    tn_over-tunetab,tn_ending-tunetab
tn_stairs:  dc.b  20,5,26,5,34,5,48,10,0
tn_victory: dc.b  48,6,34,6,26,6,20,14,0
tn_rank:    dc.b  34,5,26,5,20,5,13,16,0
tn_over:    dc.b  59,12,67,12,77,30,0
tn_ending:  dc.b  34,10,26,10,20,10,26,10,34,30,0
        even
