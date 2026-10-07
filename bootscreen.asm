; OpenDiskSysROM
; Copyright (c) 2026 Daniel Oranguthang
;
; This program is free software: you can redistribute it and/or modify it under
; the terms of the GNU Lesser General Public License version 3 as published by
; the Free Software Foundation.
;
; This program is distributed in the hope that it will be useful, but WITHOUT
; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
; FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public License for more
; details.
;
; You should have received a copy of the GNU Lesser General Public License
; along with this program. If not, see <https://www.gnu.org/licenses/>.

; The screen the boot loader shows while it waits: the BIOS font in pattern
; table 0, a black backdrop, white text on the middle row of the first
; nametable. Rendering is off while anything is written to the PPU.

FONT			EQU $E001	; 1 bpp, 8 bytes a character: 0-9, A-Z, space, ",", "."
FONT_CHARACTERS	EQU 39
TILE_SPACE		EQU 36
MESSAGE_ROW		= $2000 + 14 * 32	; not EQU, whose text #> would split
BOOT_INSERT		EQU 0		; the messages BootScreenMessage shows
BOOT_ERROR		EQU 1

; Puts the font into pattern table 0 (each byte twice, both bitplanes, so the
; text uses colour 3), clears the first nametable and its attributes and sets
; the background palette.
; Affects: A, X, Y, $00, $01
BootScreenSetup:
	JSR BootScreenOff
	LDA PPUSTATUS
	LDA #0
	STA PPUADDR
	STA PPUADDR
	LDA #<FONT
	STA $00
	LDA #>FONT
	STA $01
	LDX #FONT_CHARACTERS
@character:
	LDY #0
@plane0:
	LDA ($00),Y
	STA PPUDATA
	INY
	CPY #8
	BNE @plane0
	LDY #0
@plane1:
	LDA ($00),Y
	STA PPUDATA
	INY
	CPY #8
	BNE @plane1
	LDA $00
	CLC
	ADC #8
	STA $00
	BCC @next
	INC $01
@next:
	DEX
	BNE @character
	LDA #$20
	STA PPUADDR
	LDA #$00
	STA PPUADDR
	LDA #TILE_SPACE
	LDX #4				; 4 x 240 bytes cover the 960 tiles
@clear:
	LDY #240
@clearTiles:
	STA PPUDATA
	DEY
	BNE @clearTiles
	DEX
	BNE @clear
	LDA #0
	LDY #64				; the attributes: palette 0 everywhere
@clearAttributes:
	STA PPUDATA
	DEY
	BNE @clearAttributes
	LDA #$3F
	STA PPUADDR
	LDA #$00
	STA PPUADDR
	LDA #$0F			; black backdrop
	STA PPUDATA
	STA PPUDATA
	STA PPUDATA
	LDA #$30			; white text
	STA PPUDATA
	RTS

; Shows a message on the middle row: the row is cleared, the message's tiles
; written from its start, then rendering is turned on.
; Parameters: X = message (BOOT_INSERT, BOOT_ERROR), A = error number for
; BOOT_ERROR, shown in hex after the message
; Affects: A, X, Y, $00, $01
BootScreenMessage:
	PHA
	JSR BootScreenOff
	LDA PPUSTATUS
	LDA #>MESSAGE_ROW
	STA PPUADDR
	LDA #<MESSAGE_ROW
	STA PPUADDR
	LDA #TILE_SPACE
	LDY #32
@blank:
	STA PPUDATA
	DEY
	BNE @blank
	LDA #>MESSAGE_ROW
	STA PPUADDR
	LDA BootMessageColumns,X
	STA PPUADDR
	LDA BootMessagesLow,X
	STA $00
	LDA BootMessagesHigh,X
	STA $01
	LDY #0
@text:
	LDA ($00),Y
	BMI @end
	STA PPUDATA
	INY
	BNE @text
@end:
	PLA
	CPX #BOOT_ERROR
	BNE @show
	PHA
	LSR A
	LSR A
	LSR A
	LSR A
	STA PPUDATA			; digits 0-9 and A-F are tiles 0-15
	PLA
	AND #$0F
	STA PPUDATA
@show:
	LDA PPUSTATUS
	LDA #0
	STA PPUSCROLL
	STA PPUSCROLL
	STA PPUCTRL			; NMIs off, background from pattern table 0
	LDA #%00001010		; background on, left column too
	STA PPUMASK
	RTS

; Turns rendering off, as loading into the PPU needs.
; Affects: A
BootScreenOff:
	LDA #0
	STA PPUMASK
	RTS

; "INSERT A DISK", "DISK ERROR " in font tiles, each ended by $FF.
BootInsert:
	DB 18, 23, 28, 14, 27, 29, 36, 10, 36, 13, 18, 28, 20, $FF
BootError:
	DB 13, 18, 28, 20, 36, 14, 27, 27, 24, 27, 36, $FF
BootMessagesLow:
	DB <BootInsert, <BootError
BootMessagesHigh:
	DB >BootInsert, >BootError
BootMessageColumns:
	DB <(MESSAGE_ROW + 9), <(MESSAGE_ROW + 10)
