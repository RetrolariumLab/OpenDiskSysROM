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

; Reads the next byte of the block being transferred. Like XferByte, but it
; does not touch $4024, and the end of the disk ends the disk call with
; EOF_READ instead of waiting for a byte that will not come: $4030 bit 6 says so
; on some drives, $4032 bit 1 (not ready) once the drive has stopped at the end
; on others. Reading $4030 clears the byte transfer flag, so each byte is taken
; once.
; Returns: A = byte read
; Affects: A
ReadByte:
@wait:
	LDA DISKSTATUS
	AND #%01000010		; bit 1: a byte is there, bit 6: end of the disk
	BNE @status
	LDA DRIVESTATUS
	AND #%00000010		; bit 1: the drive stopped
	BEQ @wait
	BNE @end
@status:
	AND #%00000010
	BEQ @end
	LDA READDATA
	RTS
@end:
	LDA #EOF_READ
	JMP DiskExit
