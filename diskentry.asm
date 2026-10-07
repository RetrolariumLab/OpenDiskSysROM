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

; The body of GetHardCodedPointers (see gethardcodedpointers.asm), here where
; there is room for it. C = 1 checks the write protection as well.
GetHardCodedPointersImpl:
    STA DISK_PTR2+1     ; -1: two pointers follow the call, else one, and A
    PHP                 ; C: check the write protection too (read back below)
    ; The stack now holds our flags, the return address into the disk API and
    ; the return address into its caller, which points at the last byte of
    ; the caller's JSR: the pointers follow it.
    TSX
    LDA $0104,X
    STA DISK_DEST
    LDA $0105,X
    STA DISK_DEST+1
    LDY #1
    LDA (DISK_DEST),Y
    STA DISK_PTR1
    INY
    LDA (DISK_DEST),Y
    STA DISK_PTR1+1
    LDA DISK_PTR2+1
    CMP #$FF
    BEQ @second
    STA DISK_PTR2       ; one pointer: A is the second parameter
    JMP @skip           ; Y = 2 bytes of parameters
@second:
    INY
    LDA (DISK_DEST),Y
    STA DISK_PTR2
    INY
    LDA (DISK_DEST),Y
    STA DISK_PTR2+1     ; Y = 4 bytes of parameters
@skip:
    ; The caller continues after the parameters.
    TYA
    CLC
    ADC $0104,X
    STA $0104,X
    BCC @saveStack
    INC $0105,X
@saveStack:
    ; Errors return straight to the caller: remember the stack as it is with
    ; only the caller's return address on it.
    TXA
    CLC
    ADC #3
    STA DISK_SAVED_SP
    LDA $0101,X         ; the caller's flags, our PHP has not changed them
    STA DISK_SAVED_P
    SEI                 ; the transfer is paced by polling, not by IRQs
    LDA #0
    STA DISK_LOADED
    PLA                 ; our copy of the flags: PLP would undo the SEI
    LDA DRIVESTATUS
    AND #%00000001      ; bit 0: no disk
    BNE @notSet
    LDA DISK_SAVED_P
    LSR A               ; C as it was on entry: check the write protection
    BCC @ok
    LDA DRIVESTATUS
    AND #%00000100      ; bit 2: write protected
    BEQ @ok
    LDA #WRITE_PROTECTED
    JMP DiskExit
@notSet:
    LDA #DISK_NOT_SET
    JMP DiskExit
@ok:
    LDA #OK
    RTS
