;;; IRQの設定
	.include "./macro.asm"
	.import scroll
	
.segment "battle"
	
_battle_irq_setup:
	irq_set #63

	ldx #(_common_CBANK_TEXT+0)
	mmc3_cbank 0
	ldx #(_common_CBANK_ENEMY01+0)
	mmc3_cbank 1

	loadw _ppu_irq_next, battle_irq_1
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

;;; IRQ割り込み(タイトル下)
battle_irq_2:
	sta _mmc3_IRQ_DISABLE		; 4c
	xwait #10
	
	ldx #(_common_CBANK_FACE+0)
	mmc3_cbank 0
	ldx #(_common_CBANK_FACE+2)
	mmc3_cbank 1
	
	rts
