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
