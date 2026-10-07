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

; Writes the drive control bits in A to $4025 and its mirror $FA, keeping the
; mirroring bit the game chose.
; Parameters: A = FDSCTRL_* bits other than FDSCTRL_MIRROR
; Affects: A, $FA
SetDiskControl:
	PHA
	LDA ZP_FDSCTRL
	AND #FDSCTRL_MIRROR
	STA ZP_FDSCTRL
	PLA
	ORA ZP_FDSCTRL
	STA ZP_FDSCTRL
	STA FDSCTRL
	RTS
