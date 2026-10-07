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

; The disk info block: its mark, the disk ID, and what follows the boot file code.
DISK_MARK_LENGTH EQU 14
DISK_ID_LENGTH EQU 10
DISK_INFO_REST EQU 56 - 1 - DISK_MARK_LENGTH - DISK_ID_LENGTH - 1

; The body of CheckDiskHeader. Reads the whole disk info block (56 bytes with
; its type): the "*NINTENDO-HVC*" mark, the 10-byte disk ID, the boot file
; code, and 30 bytes of manufacturing data this BIOS has no use for.
; Fails with WRONG_SIGNATURE, or with the error of the first ID field that
; differs from the one asked for.
CheckDiskHeaderImpl:
	LDA #1
	JSR CheckBlockType
	LDY #0
@mark:
	JSR ReadByte
	CMP DiskMark,Y
	BNE @badMark
	INY
	CPY #DISK_MARK_LENGTH
	BNE @mark
	LDY #0
@id:
	JSR ReadByte
	STA DISK_TEMP
	LDA (DISK_PTR1),Y
	CMP #$FF			; $FF matches anything
	BEQ @next
	CMP DISK_TEMP
	BNE @badId
@next:
	INY
	CPY #DISK_ID_LENGTH
	BNE @id
	JSR ReadByte
	STA DISK_BOOT_CODE
	LDY #DISK_INFO_REST
@rest:
	JSR ReadByte
	DEY
	BNE @rest
	JMP EndOfBlockRead
@badMark:
	LDA #WRONG_SIGNATURE
	JMP DiskExit
@badId:
	LDA DiskIdErrors,Y
	JMP DiskExit

DiskMark:
	DB "*NINTENDO-HVC*"

; The error for each byte of the disk ID: licensee, game name and type (4),
; version, side, disk number, disk type, and one more byte.
DiskIdErrors:
	DB WRONG_MAKER_ID
	DB WRONG_GAME, WRONG_GAME, WRONG_GAME, WRONG_GAME
	DB WRONG_GAME_VER
	DB WRONG_SIDE_NUM
	DB WRONG_DISK_NUM
	DB WRONG_ADDL_DISK_ID1
	DB WRONG_ADDL_DISK_ID2
