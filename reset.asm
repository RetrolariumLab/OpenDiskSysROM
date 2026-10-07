; FreeDiskSysROM
; Copyright (c) 2018 James Athey
; Modified for OpenDiskSysROM, Copyright (c) 2026 Daniel Oranguthang
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

;[$0102]/[$0103]: PC action on reset
;($DFFC):         disk game reset vector     (if [$0102] = $35, and [$0103] = $53 or $AC)
RESET_ACTION_1 EQU $0102
RESET_ACTION_2 EQU $0103
DISK_RESET_VEC EQU $DFFC


RESET:
    SEI ; disable interrupts
    CLD ; clear decimal mode flag, which doesn't work on the 2A03 anyway
    LDX #$FF
    TXS ; the stack starts empty

    ; don't allow NMIs until we're ready; the mirror holds its documented
    ; reset value
    LDY #$00
    STY PPUCTRL
    LDA #$10
    STA ZP_PPUCTRL

    ; disable rendering, but enable left 8 pixels
    LDA #$06
    STA ZP_PPUMASK
    STA PPUMASK

    ; disable disk I/O and IRQs
    STY IRQCTRL
    STY MASTERIO

    ; the APU frame counter: 5-step mode, no frame IRQ
    LDA #$C0
    STA $4017

    ; the PPU takes a while to warm up. Wait for at least 2 VBlanks before
    ; trying to set the scroll registers
    LDX #2
@waitForVBL:
    LDA PPUSTATUS
    BPL @waitForVBL
    DEX
    BNE @waitForVBL

    ; clear the scroll registers
    LDA #0
    STA ZP_PPUSCROLL1
    STA PPUSCROLL
    STA ZP_PPUSCROLL2
    STA PPUSCROLL

    ; nothing has been written to the joypads or expansion port
    STA ZP_JOYPAD1

    ; enable the disk and sound registers, then stop the drive
    LDA #$83
    STA MASTERIO
    LDA #$2E
    STA ZP_FDSCTRL
    STA FDSCTRL

    LDA #$FF
    STA ZP_EXTCONN
    STA EXTCONNWR

    ; prepare the VRAM buffer
    LDA #$7D ; initial write buffer found at $302-$37F
    STA $300
    LDA #0
    STA $301
    LDA #$80 ; "end" opcode for the write buffer
    STA $302

    ; NMIs stay off: the game's NMI vectors are not loaded yet.

    ; A reset while a booted game is in RAM restarts the game.
    LDA RESET_ACTION_1
    CMP #$35
    BNE Boot
    LDA RESET_ACTION_2
    CMP #$53
    BEQ @warm
    CMP #$AC
    BNE Boot
@warm:
    LDA #$53
    STA RESET_ACTION_2
    JMP (DISK_RESET_VEC)

; Loads the boot files of the disk in the drive (every file whose ID is not
; above the disk's boot file code) and starts the game through its reset
; vector, with $0102/$0103 telling a later reset that the game is in RAM. The
; NMI and IRQ actions take their reset values before anything loads ($C0: the
; game's third NMI vector, $80: the BIOS acknowledges IRQs): a boot file that
; lands on PPUCTRL and turns NMIs on, as some games do to cut the boot short,
; reaches the game's own NMI handler. Until a disk is in the drive it asks for
; one; a failed load shows its error number for about two seconds and tries
; again. The screen is dark while the files load into the PPU.
Boot:
    LDA #$C0
    STA NMI_ACTION
    LDA #$80
    STA IRQ_ACTION
    JSR BootScreenSetup
@insert:
    LDA DRIVESTATUS
    LSR A ; bit 0: no disk
    BCC @load
    LDX #BOOT_INSERT
    JSR BootScreenMessage
@wait:
    LDA DRIVESTATUS
    LSR A
    BCS @wait
@load:
    JSR BootScreenOff
    JSR LoadFiles
    DW BootDiskId
    DW BootFileList
    BEQ @start
    LDX #BOOT_ERROR
    JSR BootScreenMessage
    LDA #8 ; eight times a quarter of a second
@pause:
    PHA ; Delayms uses X and Y
    LDY #0
    JSR Delayms
    PLA
    SEC
    SBC #1
    BNE @pause
    JSR BootScreenSetup
    JMP @insert
@start:
    LDA #$AC
    STA RESET_ACTION_2
    LDA #$35
    STA RESET_ACTION_1
    CLI
    JMP (DISK_RESET_VEC)

; Any disk, its boot files.
BootDiskId:
    DB $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF
BootFileList:
    DB $FF
