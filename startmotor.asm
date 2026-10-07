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

; Spins the drive up from the start of the disk: a transfer reset takes the
; head back to the outer edge, then the motor turns in read mode with no block
; transfer started. WaitForDriveReady then waits for the drive.
; Affects: A, $FA
API_ENTRYPOINT $ee17
StartMotor:
	LDA #FDSCTRL_ONE | FDSCTRL_READ | FDSCTRL_RESET | FDSCTRL_MOTOR
	JSR SetDiskControl
	LDA #FDSCTRL_ONE | FDSCTRL_READ | FDSCTRL_MOTOR
	JMP SetDiskControl
