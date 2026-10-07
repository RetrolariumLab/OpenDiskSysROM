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

; The body of WriteFile, in three passes over the disk: the file is written at
; its place, the file count becomes the place + 1, and every file is read back,
; which checks each block's CRC. If the reading back fails, the file count goes
; back to the place, hiding the file, and the call fails with READBACK_FAILED.
; A place past the last file + 1 fails with FILE_COUNT_EXCEEDED, as it would
; leave files nobody wrote.
; A failed call is made once more from the start (TwoAttempts). The place
; lives on the stack, at $0100 + DISK_SAVED_SP, where it outlasts the routines
; that use the zero page.
WriteFileImpl:
	STA DISK_FILE_COUNT	; out of GetHardCodedPointers' way
	LDA #$FF
	JSR GetHardCodedPointersWriteProtected
	LDA DISK_FILE_COUNT
	PHA					; the place as given, for each attempt
	JSR TwoAttempts
	LDX DISK_SAVED_SP
	LDA TRY_PUSHED,X
	PHA
	; Pass 1: write the file at its place.
	JSR StartMotor
	JSR WaitForDriveReady
	JSR CheckDiskHeader
	JSR GetNumFiles
	LDX DISK_SAVED_SP
	LDA $0100,X
	CMP #$FF
	BNE @placed
	LDA DISK_FILE_COUNT	; AppendFile: after the last file
	STA $0100,X
@placed:
	CMP DISK_FILE_COUNT
	BEQ @skip
	BCS @exceeded
@skip:
	STA DISK_FILE_COUNT
	JSR SkipFiles
	LDX DISK_SAVED_SP
	LDA $0100,X
	JSR SaveData
	; Pass 2: the file count.
	JSR StartMotor
	JSR WaitForDriveReady
	JSR CheckDiskHeader
	LDX DISK_SAVED_SP
	LDA $0100,X
	CLC
	ADC #1
	JSR SetNumFiles
	; Pass 3: read everything back. Its failures come back here rather than
	; to the caller: DISK_SAVED_SP and DISK_SAVED_P are swapped for the
	; duration.
	LDA DISK_SAVED_SP
	PHA
	LDA DISK_SAVED_P
	PHA
	JSR @readBack
	TAX					; the result of reading back
	PLA
	STA DISK_SAVED_P
	PLA
	STA DISK_SAVED_SP
	TXA
	BEQ @done
	; Hide the file again.
	JSR StartMotor
	JSR WaitForDriveReady
	JSR CheckDiskHeader
	LDX DISK_SAVED_SP
	LDA $0100,X
	JSR SetNumFiles
	LDA #READBACK_FAILED
	JMP DiskExit
@done:
	LDA #OK
	JMP DiskExit
@exceeded:
	LDA #FILE_COUNT_EXCEEDED
	JMP DiskExit

; Reads every file on the disk. DiskExit returns from here, also on errors,
; with A = error number and interrupts still masked.
@readBack:
	TSX
	STX DISK_SAVED_SP
	PHP
	PLA
	ORA #%00000100		; interrupts stay masked when DiskExit restores the flags
	STA DISK_SAVED_P
	JSR StartMotor
	JSR WaitForDriveReady
	JSR CheckDiskHeader
	JSR GetNumFiles
	JSR SkipFiles
	LDA #OK
	JMP DiskExit
