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

; Reads a file header block (16 bytes with its type): the file number, the file
; ID into $08, the 8-byte name, then where the data goes, its size and its type,
; which ReadData uses.
; Affects: A, Y, $08, $0A-$0D, $0F, $FA
ReadFileHeader:
	LDA #3
	JSR CheckBlockType
	JSR ReadByte		; file number
	JSR ReadByte		; file ID
	STA DISK_TEMP
	LDY #8
@name:
	JSR ReadByte
	DEY
	BNE @name
	JSR ReadByte
	STA DISK_DEST
	JSR ReadByte
	STA DISK_DEST+1
	JSR ReadByte
	STA DISK_SIZE
	JSR ReadByte
	STA DISK_SIZE+1
	JSR ReadByte
	STA DISK_FILE_TYPE
	JMP EndOfBlockRead
