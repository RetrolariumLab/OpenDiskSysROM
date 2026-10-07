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

; The body of GetDiskInfo. The running total of the disk size lives on the
; stack, at $0100 + DISK_SAVED_SP (low) and $00FF + DISK_SAVED_SP (high).
FILE_OVERHEAD	EQU 261 ; what the size adds for each file beyond its data

GetDiskInfoImpl:
	LDA #0						; one pointer, whatever A the caller left
	JSR GetHardCodedPointers	; the structure, at $00
	LDA #0
	PHA
	PHA
	JSR StartMotor
	JSR WaitForDriveReady
	; The disk info block: its mark is checked, its ID copied.
	LDA #1
	JSR CheckBlockType
	LDY #0
@mark:
	JSR ReadByte
	CMP DiskMark,Y
	BEQ @markOk
	JMP @badMark
@markOk:
	INY
	CPY #DISK_MARK_LENGTH
	BNE @mark
	LDY #0
@id:
	JSR ReadByte
	STA (DISK_PTR1),Y
	INY
	CPY #DISK_ID_LENGTH
	BNE @id
	LDY #DISK_INFO_REST + 1	; the boot file code and the rest
@rest:
	JSR ReadByte
	DEY
	BNE @rest
	JSR EndOfBlockRead
	JSR GetNumFiles
	LDY #DISK_ID_LENGTH
	LDA DISK_FILE_COUNT
	STA (DISK_PTR1),Y
	INY
	JSR @advance
	LDA DISK_FILE_COUNT
	BEQ @total
@file:
	LDA #3
	JSR CheckBlockType
	JSR ReadByte		; file number
	LDY #0
@name:
	JSR ReadByte		; file ID, then the name
	STA (DISK_PTR1),Y
	INY
	CPY #9
	BNE @name
	JSR @advance
	JSR ReadByte		; load address
	JSR ReadByte
	JSR ReadByte
	STA DISK_SIZE
	JSR ReadByte
	STA DISK_SIZE+1
	JSR ReadByte		; file type
	JSR EndOfBlockRead
	LDX DISK_SAVED_SP
	CLC
	LDA $0100,X
	ADC DISK_SIZE
	STA $0100,X
	LDA $00FF,X
	ADC DISK_SIZE+1
	STA $00FF,X
	CLC
	LDA $0100,X
	ADC #FILE_OVERHEAD & $FF
	STA $0100,X
	LDA $00FF,X
	ADC #FILE_OVERHEAD >> 8
	STA $00FF,X
	LDA #$FF
	STA DISK_MATCH		; the data block is read past
	JSR ReadData
	DEC DISK_FILE_COUNT
	BNE @file
@total:
	LDX DISK_SAVED_SP
	LDY #0
	LDA $00FF,X
	STA (DISK_PTR1),Y
	INY
	LDA $0100,X
	STA (DISK_PTR1),Y
	LDA #OK
	JMP DiskExit
@badMark:
	LDA #WRONG_SIGNATURE
	JMP DiskExit

; Moves the structure pointer at $00 on by Y bytes.
@advance:
	TYA
	CLC
	ADC DISK_PTR1
	STA DISK_PTR1
	BCC @advanced
	INC DISK_PTR1+1
@advanced:
	RTS
