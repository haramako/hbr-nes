;;; IRQの設定
    .include "./macro.asm"
    .import scroll
    .export _battle_irq_setup
	
    .segment "battle_irq"

    EMU = 1

    .macro do_scroll SX,SY
    ldx #SX
    ldy #SY
    jsr scroll
    .endmacro

    .macro resume_ppu
    lda #%10100000
    sta _nes_PPU_CTRL1
    lda #%00011110
    sta _nes_PPU_CTRL2
    .endmacro

    .macro stop_ppu
    lda #0
    sta _nes_PPU_CTRL1
    sta _nes_PPU_CTRL2
    .endmacro

    .macro write_pallet _TO,_FROM,_SIZE
    ;; パレットを書き込む
    lda #.HIBYTE(_TO)
    sta _nes_PPU_ADDR
    lda #.LOBYTE(_TO)
    sta _nes_PPU_ADDR

    ldy #0
    :
    lda _FROM,y
    sta _nes_PPU_DATA
    iny
    cpy #_SIZE
    bne :-

    .endmacro

    ;; パレットに3バイト書き込む
    .macro write_pallet3 TO,FROM
    ;; パレットを書き込む
    lda #.HIBYTE(TO)
    sta _nes_PPU_ADDR
    lda #.LOBYTE(TO)
    sta _nes_PPU_ADDR

    lda FROM+0
    ldx FROM+1
    ldy FROM+2
    sta _nes_PPU_DATA
    stx _nes_PPU_DATA
    sty _nes_PPU_DATA
    .endmacro
    
    
    
_battle_irq_setup:
    irq_set #112

    ;; パレットを書き込む
    lda #$3f
    sta _nes_PPU_ADDR
    lda #$00
    sta _nes_PPU_ADDR

    write_pallet $3f00, _battle_pallet0, 16

    ;; スクロールする
    ldx #0
    ldy #0
    jsr scroll

    ldx #(_common_CBANK_TEXT+0)
    mmc3_cbank 0
    ldx #(_common_CBANK_ENEMY01+0)
    mmc3_cbank 1

    loadw _ppu_irq_next, battle_irq_2
    rts

;;; IRQ割り込み(タイトル中央)
;;; ここに入ってくるまでに,24cycle使っている。１回めの h-blank まで 113 - 24 で 89cycle.
battle_irq_1:
    irq_set #63					; 18c
    xwait #8
	
    ldx #(_common_CBANK_TEXT+0)
    mmc3_cbank 0
    ldx #(_common_CBANK_ENEMY01+0)
    mmc3_cbank 1
    
    loadw _ppu_irq_next, battle_irq_2
    rts

;;; IRQ割り込み(パーティ１列目)
battle_irq_2:
    .ifndef EMU
    ;; =============================================
    ;; 実機(or Nestopia)の場合
    irq_set #51					; 18c

    stop_ppu
    
    ;; CBANKの切り替え
    ldx #(_common_CBANK_FACE+0)
    mmc3_cbank 0
    ldx #(_common_CBANK_FACE+2)
    mmc3_cbank 1

    xwait #2
    
    write_pallet3 $3f05, _battle_pallet1+5
    resume_ppu

    xwait #10
    nop
    nop

    stop_ppu
    write_pallet3 $3f09, _battle_pallet1+9
    resume_ppu

    xwait #10
    nop
    nop

    stop_ppu
    write_pallet3 $3f0d, _battle_pallet1+13
    resume_ppu
    
    do_scroll 0,127
    
    .else
    ;; =============================================
    ;; エミュレータの場合
    irq_set #49					; 18c

    stop_ppu
    
    ;; CBANKの切り替え
    ldx #(_common_CBANK_FACE+0)
    mmc3_cbank 0
    ldx #(_common_CBANK_FACE+2)
    mmc3_cbank 1

    write_pallet $3f00,_battle_pallet1,16
    
    resume_ppu
    do_scroll 0,127
    
    .endif
    ;; =============================================
    
    loadw _ppu_irq_next, battle_irq_3
    rts

;;; IRQ割り込み(パーティ２列目)
battle_irq_3:
    sta _mmc3_IRQ_DISABLE		; 4c

    .ifndef EMU
    ;; =============================================
    ;; 実機(or Nestopia)の場合
    xwait #10
    stop_ppu
    
    write_pallet3 $3f05, _battle_pallet2+5
    resume_ppu

    xwait #10
    nop
    nop

    stop_ppu
    write_pallet3 $3f09, _battle_pallet2+9
    resume_ppu

    xwait #10
    nop
    nop

    stop_ppu
    write_pallet3 $3f0d, _battle_pallet2+13
    resume_ppu
    
    do_scroll 0,176
    
    .else
    ;; =============================================
    ;; エミュレータの場合
    stop_ppu
    
    xwait #10

    write_pallet $3f00,_battle_pallet2,16
    
    resume_ppu
    do_scroll 0,175
    
    .endif
    ;; =============================================
    
    rts
    
