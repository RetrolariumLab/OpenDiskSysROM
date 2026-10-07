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

; The body of UploadObject. Work area: $02 tile number within the frame, $03
; columns left, $04 rows left, $05 X of the column, $06 Y of the tile, $07
; OAM attributes, $08-$09 tile table (high byte 0: $08 is the first tile
; number), $0A Y of the first row, $0B width, $0C height. X walks the OAM.

OBJECT_RENDER		EQU 0
OBJECT_Y			EQU 1
OBJECT_X			EQU 3
OBJECT_FRAME		EQU 5
OBJECT_TILES		EQU 6
OBJECT_FLAGS		EQU 8
OBJECT_PALETTE		EQU 9
OBJECT_SIZE			EQU 10
OBJECT_OAM			EQU 11
OBJECT_FLIP_X		EQU %00010000
OBJECT_FLIP_Y		EQU %00000001
OAM_FLIP_X			EQU %01000000
OAM_FLIP_Y			EQU %10000000
OAM_BUFFER			EQU $0200
HIDDEN_Y			EQU $F8

UploadObjectImpl:
	LDY #OBJECT_SIZE
	LDA ($00),Y
	AND #$0F
	BEQ @end
	STA $0B
	LDA ($00),Y
	LSR A
	LSR A
	LSR A
	LSR A
	BEQ @end
	STA $0C
	LDY #OBJECT_OAM
	LDA ($00),Y
	ASL A
	ASL A
	TAX
	LDA #0				; the tiles of a frame: width x height
	LDY $0C
@area:
	CLC
	ADC $0B
	DEY
	BNE @area
	STA $02
	LDY #OBJECT_RENDER
	LDA ($00),Y
	BEQ @shown
	BMI @hide
@end:
	RTS
@hide:
	LDY $02
	LDA #HIDDEN_Y
@hideTile:
	STA OAM_BUFFER,X
	INX
	INX
	INX
	INX
	DEY
	BNE @hideTile
	RTS

@shown:
	STA $03				; the frame's first tile: frame x area, shift and add
	STA $08
	STA $09
	LDY #OBJECT_FRAME
	LDA ($00),Y
@multiply:
	CMP #0
	BEQ @multiplied
	LSR A
	BCC @double
	PHA
	CLC
	LDA $08
	ADC $02
	STA $08
	LDA $09
	ADC $03
	STA $09
	PLA
@double:
	ASL $02
	ROL $03
	JMP @multiply
@multiplied:
	LDY #OBJECT_TILES + 1
	LDA ($00),Y
	CLC
	ADC $08
	STA $08
	DEY
	LDA ($00),Y			; the carry stays for the high byte
	BEQ @direct
	ADC $09
	STA $09
	JMP @attributes
@direct:
	STA $09
@attributes:
	LDY #OBJECT_PALETTE
	LDA ($00),Y
	AND #%00000011
	STA $07
	LDY #OBJECT_FLAGS
	LDA ($00),Y
	AND #OBJECT_FLIP_X
	ASL A
	ASL A
	ORA $07
	STA $07
	LDA ($00),Y
	LSR A
	BCC @position
	LDA $07
	ORA #OAM_FLIP_Y
	STA $07
@position:
	LDY #OBJECT_Y		; flipped, the first row or column is the far one
	LDA ($00),Y
	BIT $07
	BPL @top
	LDY $0C
	JSR AddTilesMinusOne
@top:
	STA $0A
	LDY #OBJECT_X
	LDA ($00),Y
	BIT $07
	BVC @left
	LDY $0B
	JSR AddTilesMinusOne
@left:
	STA $05
	LDA #0
	STA $02
	LDA $0B
	STA $03
@column:
	LDA $0A
	STA $06
	LDA $0C
	STA $04
@tile:
	LDA $06
	STA OAM_BUFFER,X
	LDA $09
	BEQ @tileNumber
	LDY $02
	LDA ($08),Y
	JMP @store
@tileNumber:
	LDA $08
	CLC
	ADC $02
@store:
	STA OAM_BUFFER + 1,X
	LDA $07
	STA OAM_BUFFER + 2,X
	LDA $05
	STA OAM_BUFFER + 3,X
	INX
	INX
	INX
	INX
	INC $02
	LDA $06
	BIT $07
	BMI @up
	CLC
	ADC #8
	JMP @nextRow
@up:
	SEC
	SBC #8
@nextRow:
	STA $06
	DEC $04
	BNE @tile
	LDA $05
	BIT $07
	BVS @back
	CLC
	ADC #8
	JMP @nextColumn
@back:
	SEC
	SBC #8
@nextColumn:
	STA $05
	DEC $03
	BNE @column
	RTS

; A + 8 x (Y - 1): the far edge of Y tiles from A.
; Affects: A, Y
AddTilesMinusOne:
	DEY
	BEQ @done
	CLC
	ADC #8
	JMP AddTilesMinusOne
@done:
	RTS
