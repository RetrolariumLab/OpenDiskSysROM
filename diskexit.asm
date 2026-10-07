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

; Ends a disk call, successful or not. The stack goes back to where
; GetHardCodedPointers left it, which drops whatever the routines that failed
; had pushed, the drive stops, and control returns to the program that called
; the disk API (past its pointer parameters) with its interrupt disable flag
; as it was.
; Parameters: A = error number (OK = 0)
; Returns: A = error number with Z and N set from it, Y = files loaded
; Affects: X, $FA
DiskExit:
	LDX DISK_SAVED_SP
	TXS
	TAX
	JSR StopMotor
	LDA DISK_SAVED_P
	PHA
	TXA
	LDY DISK_LOADED
	PLP
	AND #$FF
	RTS

; Runs the rest of the routine that calls it (the code after its JSR
; TwoAttempts, which ends in DiskExit) up to twice: an attempt that fails is
; made once more, as the BIOS does for LoadFiles, WriteFile and AppendFile.
; Each attempt starts with interrupts masked, no files counted as loaded and
; DISK_SAVED_SP set so that DiskExit comes back here; the last result goes to
; the program through DiskExit. A byte the routine pushed just before its JSR
; is at TRY_PUSHED + DISK_SAVED_SP during an attempt.
; Affects: A, X, Y, $08
TRY_PUSHED	EQU $0107

TwoAttempts:
	LDA DISK_SAVED_SP
	PHA					; the program's stack, for the last DiskExit
	LDA #2
	PHA					; attempts left
@attempt:
	LDA #>(@back - 1)
	PHA
	LDA #<(@back - 1)
	PHA
	TSX
	STX DISK_SAVED_SP
	LDA $0106,X			; the attempt starts where JSR TwoAttempts returns to
	PHA
	LDA $0105,X
	PHA
	LDA #0
	STA DISK_LOADED
	SEI
	RTS
@back:
	BEQ @done			; DiskExit set Z from the error number
	TSX
	DEC $0101,X
	BNE @attempt
@done:
	STA DISK_TEMP
	PLA
	PLA
	STA DISK_SAVED_SP
	LDA DISK_TEMP
	JMP DiskExit
