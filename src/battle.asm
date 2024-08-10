;;; IRQの設定
	.include "./macro.asm"
    .import scroll
    .export _battle_irq_setup
	
    .segment "battle_irq"

    .align 256
_battle_irq_setup:
    irq_set #112

    ;; パレットを書き込む
    lda #$3f
    sta _nes_PPU_ADDR
    lda #$00
    sta _nes_PPU_ADDR

    ldy #00
:   lda _battle_pallet0,y
    sta _nes_PPU_DATA
    iny
    cpy #16
    bne :-

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
    irq_set #51					; 18c

    ;; 画面描画を止める
    lda #0
    sta _nes_PPU_CTRL1
    sta _nes_PPU_CTRL2
    
    ;; CBANKの切り替え
    ldx #(_common_CBANK_FACE+0)
    mmc3_cbank 0
    ldx #(_common_CBANK_FACE+2)
    mmc3_cbank 1

    xwait #2
    
    ;; パレットを書き込む
    lda #$3f
    sta _nes_PPU_ADDR
    lda #$05
    sta _nes_PPU_ADDR

:   lda _battle_pallet1+5
:   ldx _battle_pallet1+6
:   ldy _battle_pallet1+7
    sta _nes_PPU_DATA
    stx _nes_PPU_DATA
    sty _nes_PPU_DATA

    ;; 画面描画を再開する
    lda #%10100000
    sta _nes_PPU_CTRL1
    lda #%00011110
    sta _nes_PPU_CTRL2

    xwait #10
    nop
    nop

    ;; =============================================
    ;; 画面描画を止める
    lda #0
    sta _nes_PPU_CTRL1
    sta _nes_PPU_CTRL2
    
    ;; パレットを書き込む
    lda #$3f
    sta _nes_PPU_ADDR
    lda #$09
    sta _nes_PPU_ADDR

:   lda _battle_pallet1+9
:   ldx _battle_pallet1+10
:   ldy _battle_pallet1+11
    sta _nes_PPU_DATA
    stx _nes_PPU_DATA
    sty _nes_PPU_DATA
    
    ;; 画面描画を再開する
    lda #%10100000
    sta _nes_PPU_CTRL1
    lda #%00011110
    sta _nes_PPU_CTRL2

    xwait #10
    nop
    nop

    ;; =============================================
    ;; 画面描画を止める
    lda #0
    sta _nes_PPU_CTRL1
    sta _nes_PPU_CTRL2
    
    ;; パレットを書き込む
    lda #$3f
    sta _nes_PPU_ADDR
    lda #$0D
    sta _nes_PPU_ADDR

:   lda _battle_pallet1+13
:   ldx _battle_pallet1+14
:   ldy _battle_pallet1+15
    sta _nes_PPU_DATA
    stx _nes_PPU_DATA
    sty _nes_PPU_DATA
    
    ;; 画面描画を再開する
    lda #%10100000
    sta _nes_PPU_CTRL1
    lda #%00011110
    sta _nes_PPU_CTRL2
    
    ;; =============================================
    ;; スクロールする
    ldx #0
    ldy #127
    jsr scroll
    
    loadw _ppu_irq_next, battle_irq_3
    rts

;;; IRQ割り込み(パーティ２列目)
    .align 256
battle_irq_3:
    sta _mmc3_IRQ_DISABLE		; 4c
    xwait #14

    ;; 画面描画を止める
    lda #0
    sta _nes_PPU_CTRL1
    sta _nes_PPU_CTRL2

    ;; パレットを書き込む
    lda #$3f
    sta _nes_PPU_ADDR
    lda #$00
    sta _nes_PPU_ADDR

    ldy #00
:   lda _battle_pallet2,y
    sta _nes_PPU_DATA
    iny
    cpy #16
    bne :-

    ;; スクロールする
    ldx #0
    ldy #176
    jsr scroll

    ;; 画面描画を再開する
    lda #%10100000
    sta _nes_PPU_CTRL1
    lda #%00011110
    sta _nes_PPU_CTRL2
    
    rts
    
