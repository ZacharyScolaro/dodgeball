;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; ;; Second scratchpad to test unrolling jsr's
;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


	PROCESSOR 6502

	include vcs.h
	include macro.h

	SEG.U VARS
	ORG $80

ScanLine:	ds 1		; scanline counter
PlayerY0:	ds 1		; Player Y0
PlayerY1:	ds 1		; Player Y1
BallY0:		ds 1		; ball y0
BallY1:		ds 1		; missile y0
BallY2:		ds 1		; missile y1
Score:		ds 1		; Score
Timer:		ds 1		; Timer
DigitOnes:	ds 2		; Player 0 and 1 digit graphics
DigitTens:	ds 2		; Player 0 and 1 digit graphics
ScoreGfx:	ds 1		; pointers
TimerGfx:	ds 1		; pointers
Temp:		ds 1		; Temp
TempStackPtr:	ds 1		; Temporary Stack Pointer
	
	SEG CODE
	ORG $F800

ColdStart:
	CLEAN_START
	lda #$32
	sta PlayerY0
	sta RESM0
	lda #$50
	sta PlayerY1
	lda #$80
	sta BallY0
	lda #$90
	sta BallY1
	lda #$A0
	sta BallY2
	sta RESBL
	sta RESM1
	lda #$10
	sta NUSIZ0
	sta NUSIZ1

MainLoop:
;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; ;; Vertical Sync
;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

VerticalSync:
	lda #$02		; Get ready to start VSYNC
	ldx #45
	sta WSYNC		; Next line
	sta VSYNC		; Start VSYNC
	stx TIM64T
	sta CTRLPF
	sta WSYNC
	sta WSYNC
	lda #$00
	sta PF0
	sta PF1
	sta PF2
	sta WSYNC
	sta VSYNC
	
;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; ;; Vertical Blank routines.
;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

VerticalBlank:

;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; ;; Process console switches.
;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

ProcessSwitches:
	;; Process start switch
	lda SWCHB
	lsr
	bcs NoNuGam	      ; go to no nu game if not pressed.
	sta RESP0		; Test code, scoot the player 0 to left.
NoNuGam:
	;;  Start switch not pressed
SetTia:
	ldx #$03		; Color register offset
	ldy #$03		; color table offset.
	lda SWCHB		; check B/W switch
	and #$08		; pressed?
	bne SOCloop		; if not pressed, offset is still 0 (or the color table)
SOCloop:
	lda Colors,Y		; Get next color
	sta COLUP0,x		; set color into register
	dey
	dex
	bpl SOCloop		; branch if not end of table.

;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; ;; Calculate digit graphic offsets from score variables
;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	
PrepScoreForDisplay:
	inc Timer		; increment frame timer
	bne PSFDskip
	inc Score		; for now, we increment score.

PSFDskip:
	ldx #1
PSFDloop:
	lda Score,X		; Get next score offset
	and #$0F		; mask off right digit
	sta Temp		; store in temp
	asl			; shift it over
	asl
	adc Temp		; add to temp
	sta DigitOnes,x		; store digit result into digitones for kernel line
	lda Score,x		; get the score offset again
	and #$F0		; mask off the left digit
	lsr			; shift over
	lsr
	sta Temp		; store into temp
	lsr			; 
	lsr			; shift it over
	adc Temp		; store into temp
	sta DigitTens,x		; take the result and store into the tens.
	dex			; next score line to calculate
	bpl PSFDloop		; and loop back around.

;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; ;; The kernel for the visible screen.
;;; ;; at this point, the vblank timer is running out
;;; ;; and the kernel waits for the timer to lapse, bringing it
;;; ;; to the visible section of the screen, and then we start
;;; ;; slamming stuff into registers to clock out the visible
;;; ;; screen, starting with the score, and then the playfield.
;;; ;; The visible kernel is divided into:
;;; ;; * Score
;;; ;; * Top border (PF0, PF1, PF2)
;;; ;; * Playfield (PF1, PF2, P0, P1, M0, M1, BL)
;;; ;; * Bottom Border (PF0, PF1, PF2)
;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

Kernel:
	;; wait for timer to run out
	lda INTIM
	bne Kernel

	;; a is now 0, so turn off vblank, so we can see stuff.
	sta VBLANK
	
	;; Assume scanline 35 once HMOVE happens.
	lda #$23
	sta ScanLine

	;; go to next scanline and thwack HMOVE, to commit the X motion changes.
	sta WSYNC
	sta HMOVE

	;; grab the stack pointer and temporarily store it, for later.
	tsx
	stx TempStackPtr

	;;
	;; two digit score for p0 and p1
	;;

	ldx #$05		; score is 5 lines tall
ScoreLoop:
	ldy DigitTens		; P0: Get the y offset for the tens digit next score line
	lda DigitGfx,y		; load accumulator with contents of score line
	and #$f0		; mask off left digit
	sta ScoreGfx		; store into score gfx
	ldy DigitOnes		; do the same for the ones
	lda DigitGfx,y		;
	and #$0F		;
	ora ScoreGfx		; merge the ones into the tens
	sta ScoreGfx		; and store into the store graphics
	sta WSYNC		; next line, on your mark... get set...
	;;
	sta PF1			; slam it into PF1
	ldy DigitTens+1		; Now calculate P1 same thing as above.
	lda DigitGfx,y		;
	and #$F0		;
	sta TimerGfx		;
	ldy DigitOnes+1		;
	lda DigitGfx,y		;
	and #$0F		;
	ora TimerGfx		;
	sta TimerGfx		;
	jsr Sleep12		; wait 12 cycles, to put it just before the reflected PF1
	sta PF1			; and slam it out.
	ldy ScoreGfx		;
	sta WSYNC		; next line
	sty PF1			; slam it out.
	inc DigitTens		; TEMP: increment the digits for the next frame.
	inc DigitTens+1		;
	inc DigitOnes		;
	inc DigitOnes+1		;
	jsr Sleep12		; sleep 12 more cycles
	dex
	sta PF1			; at this point the A is 0, clearing out PF1
	bne ScoreLoop		; if we're not done, loop back around.

	;;
	;; Clear the playfield
	;;
ScoreDone:
	sta WSYNC
	lda #$00
	sta PF0
	sta PF1
	sta PF2
	lda ScanLine
	adc #$05
	sta ScanLine
	sta WSYNC
	sta WSYNC

	;;
	;; Set CTRLPF to do a 2 clock ball, and reflective playfield.
	;;
PFReady:	
	lda #$15
	sta CTRLPF

	;;
	;; top border
	;;
topborder:
	ldx #$07		; 8 lines of
	lda #$F0		; a solid 40 pixels of playfield line
	ldy #$FF		;
	sta PF0			; slam it in
	sty PF1			;
	sty PF2			;
toploop:
	sta WSYNC		; loop around waiting for next line
	dex
	bne toploop
	lda ScanLine
	adc #$07
	
	;;
	;; prime Playfield registers to make main pf loop simpler.
	;;
primepf:
	lda #$10		; nice simple left/right border
	sta PF0			;
	lda #$00		; empty middle
	sta PF1			;
	sta PF2			;

	;;
	;; the inner playfield loop
	;; 
vfield:	ldx #$1F		; Place SP over ENABL
	txs			; for the stack trick to be used in a moment.
	;;
	;; handle Player 0
	;; 
	sec			;
	lda PlayerY0		; Where is player0's Y?
	sbc ScanLine		; subtract current scanline
	and #$FE		; quantise to two scanlines
	tax			; move into x register for graphic lookup
	and #$F0		; mask upper 4 bits
	beq vdotank		; if we're 0, we need to do the tank.
	lda #$00		; else don't draw a tank, and....
	beq vnotank		; continue onward.
vdotank:
	lda PLAYER,X		; load the next player graphic line
vnotank:
	sta WSYNC		; go to next scanline
	STA GRP0		; slam player0's graphic into place.
	;;
	;; the combat stack trick. Utilize the fact that the missile and ball enables
	;; are in bit D1, and thus can be strobed in O(1) time if we're on the right
	;; scanline, because A = 0 = Z
	;;
	;; First, do the ball., ENABL
	;; 
	lda BallY2		; Get ball's Y coord
	eor ScanLine		; eor with scanline to flip bits if needed
	and #$FC		; quantise to 4 lines.
	php			; transfer processor flags (we are interested in Z) to where SP is
	;;
	;; Then, missile 1, php caused SP to decrement over to ENAM1
	;; 
	lda BallY1		; Same thing again, just against missile 1
	eor ScanLine		;
	and #$FC		;
	php			;
	;;
	;; Then, missile 0, php caused SP to decrement to ENAM0
	;; 
	lda BallY0		; same thing again, just against missile 0
	eor ScanLine		;
	and #$FC		;
	php			;
	;;
	;; Ok, we're now done with p0, bl, m1, m0, now to precalculate playfield offset.
	;; 
	lda ScanLine		; Get current scanline
	bpl vvrefl		; if we're < 127, then don't reflect.
	eor #$F8		; otherwise flip bits to reflect.
vvrefl:	cmp #$19		; figure out if we're at last playfield line, if so, done.
	bcc vfdone		;
	lsr			; divide the scanline counter by 8.
	lsr			;
	lsr			;
	tay			; transfer to Y for table lookup.
	;;
	;; now deal with Player 1
	;; 
vfdone:	lda PlayerY1		; get player 1's Y coord
	sec			; 
	sbc ScanLine		; subtract it against current scanline
	inc ScanLine		; go ahead and increment scanline in memory (to correct bias)
	nop			; wait a tick...
	ora #$01		; get the next odd bit in player (p0 and p1 graphics are interleaved!)
	tax			; convert to table lookup
	;;
	and #$F0		; mask off top bits (we have 16 possible entries)
	beq vdot1		; do player 1 graphics if we need to, else...
	lda #$00		; write 0's
	beq vnot1		; and slam it to GRP0
vdot1:	lda PLAYER,X		; load next graphic line
vnot1:	sta GRP1		; slam it into GRP1
	lda PF1_0,Y		; now we have some time to slam PF1 into place
	sta PF1			;
	lda PF2_0,Y		; and PF2.
	sta PF2			;
	inc ScanLine		; increment to next scanline
	lda ScanLine		; get current scanline
	eor #$D8		; are we done?
	bne vfield		; if not, loop around.

	;;
	;; go to next line, to keep things clean.
	;;
	sta WSYNC

	;;
	;;  do the bottom border
	;;
BottomBorder:
	ldx #$06		; border is 7 pixels deep
	lda #$F0		; left/right border is solid
	ldy #$FF		; middle is solid
	sta PF0			; and slam into the playfield registers
	sty PF1			;
	sty PF2			;
botloop:
	sta WSYNC		; wait for next line
	dex			; decrement loop counter
	bne botloop		; if we're down to 0 from 7, go on.

	;;
	;; Bottom of the visible kernel
	;; clean up the visible regsters to prevent messes.
	;;
KernelCleanup:

	;;
	;; put the stack back the way it was.
	;;
	ldx TempStackPtr
	txs
	sta WSYNC		; blank line padding
	lda #$00
	
OverScan:
	sta WSYNC		; next line
	lda #2			; turn back on the vertical blank
	sta VBLANK		; 
	lda #22			; and wait 22*64 cycles
	sta TIM64T		;
OSWait: sta WSYNC		; next scanline
	lda INTIM		; check timer
	bne OSWait		; if we're not done, we loop aroujnd.
	
	jmp MainLoop		; and go back to the top!

;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; ;; Ancilliary subroutines
;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

Sleep12:
	rts			; this takes 6 cycles, the jsr takes 6 cycles.


	
;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; ;; Tables
;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; ;; color table, first 4 bytes are color, next 4 are b/w
;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

Colors:
	.byte $DA
	.byte $8A
	.byte $0E
	.byte $32
	.byte $0e
	.byte $00
	.byte $08
	.byte $04


;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; ;; Playfield data
;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

PF1_0
	.byte $00
	.byte $00
	.byte $00
	.byte $00
	.byte $00
	
	.byte $00
	.byte $00
	.byte $00
	.byte $38
	.byte $00
	.byte $00
	.byte $00
	.byte $60
	.byte $20
	.byte $20
	.byte $23
	
PF2_0
	.byte $00
	.byte $00
	.byte $00
	.byte $00
	.byte $00
	
	.byte $80
	.byte $80
	.byte $00
	.byte $00
	.byte $00
	.byte $1C
	.byte $04
	.byte $00
	.byte $00
	.byte $00
	.byte $00

;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; ;; Player data, p0 and p1 are interleaved.
;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

PLAYER:	.byte $00
	.byte $00
	.byte $00
	.byte $00
	.byte $3C
	.byte $3C
	.byte $3C
	.byte $3C
	.byte $3C
	.byte $3C
	.byte $3C
	.byte $3C
	.byte $00
	.byte $00
	.byte $00
	.byte $00

;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; ;; Score Digit Graphics
;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


	;; Right now, we have hex digits here too to make things easy.
	
DigitGfx:
        .byte %01110111
        .byte %01010101
        .byte %01010101
        .byte %01010101
        .byte %01110111
        
        .byte %00010001
        .byte %00010001
        .byte %00010001
        .byte %00010001        
        .byte %00010001
        
        .byte %01110111
        .byte %00010001
        .byte %01110111
        .byte %01000100
        .byte %01110111
        
        .byte %01110111
        .byte %00010001
        .byte %00110011
        .byte %00010001
        .byte %01110111
        
        .byte %01010101
        .byte %01010101
        .byte %01110111
        .byte %00010001
        .byte %00010001
        
        .byte %01110111
        .byte %01000100
        .byte %01110111
        .byte %00010001
        .byte %01110111
           
        .byte %01110111
        .byte %01000100
        .byte %01110111
        .byte %01010101
        .byte %01110111
        
        .byte %01110111
        .byte %00010001
        .byte %00010001
        .byte %00010001
        .byte %00010001
        
        .byte %01110111
        .byte %01010101
        .byte %01110111
        .byte %01010101
        .byte %01110111
        
        .byte %01110111
        .byte %01010101
        .byte %01110111
        .byte %00010001
        .byte %01110111
        
        .byte %00100010
        .byte %01010101
        .byte %01110111
        .byte %01010101
        .byte %01010101
         
        .byte %01100110
        .byte %01010101
        .byte %01100110
        .byte %01010101
        .byte %01100110
        
        .byte %00110011
        .byte %01000100
        .byte %01000100
        .byte %01000100
        .byte %00110011
        
        .byte %01100110
        .byte %01010101
        .byte %01010101
        .byte %01010101
        .byte %01100110
        
        .byte %01110111
        .byte %01000100
        .byte %01100110
        .byte %01000100
        .byte %01110111
        
        .byte %01110111
        .byte %01000100
        .byte %01100110
        .byte %01000100
        .byte %01000100

;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; ;; Function to check for free space at end of cart.
;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

	echo "------", [$FFFA - *]d, "bytes free before End of Cartridge"
	
	ORG $FFFA
	.WORD ColdStart
	.WORD ColdStart
	.WORD ColdStart
