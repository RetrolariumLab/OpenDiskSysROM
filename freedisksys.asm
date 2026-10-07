; FreeDiskSysROM
; Copyright (c) 2018 James Athey
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

; zero-page registers
ZP_PPUCTRL		EQU $FF; value last written to $2000   $10 on reset.
ZP_PPUMASK		EQU $FE; value last written to $2001   $06 on reset
ZP_PPUSCROLL1	EQU $FD; value last written to $2005/1 $00 on reset.
ZP_PPUSCROLL2	EQU $FC; value last written to $2005/2 $00 on reset.
ZP_JOYPAD1		EQU $FB; value last written to $4016   $00 on reset.
ZP_FDSCTRL		EQU $FA; value last written to $4025 $2E on reset.
ZP_EXTCONN		EQU $F9; value last written to $4026 $FF on reset.

; [$0102]/[$0103]: PC action on reset

; PPU registers
PPUCTRL		EQU $2000
PPUMASK		EQU $2001
PPUSTATUS	EQU $2002
OAMADDR		EQU $2003
OAMDATA		EQU $2004
PPUSCROLL	EQU $2005
PPUADDR		EQU $2006
PPUDATA		EQU $2007
OAMDMA		EQU $4014

; undocumented instructions not explicitly supported by asm6f
; TOP (abs)
MACRO TOP address
	DB $0C
	DW #address
ENDM

; Input registers
JOYPAD1 EQU $4016
JOYPAD2 EQU $4017

; FDS registers
IRQLOW		EQU $4020
IRQHIGH		EQU $4021
IRQCTRL		EQU $4022
MASTERIO	EQU $4023
WRITEDATA	EQU $4024
FDSCTRL		EQU $4025
EXTCONNWR	EQU $4026
DISKSTATUS	EQU $4030
READDATA	EQU $4031
DRIVESTATUS	EQU $4032
EXTCONNRD	EQU $4033

; $4025 (FDSCTRL) bits. Bit 3 selects the mirroring and belongs to the game:
; SetDiskControl keeps it as it is.
FDSCTRL_MOTOR	EQU %00000001 ; turn the drive motor on
FDSCTRL_RESET	EQU %00000010 ; reset the transfer timing: the head goes back to the start
FDSCTRL_READ	EQU %00000100 ; 1 = read the disk, 0 = write it
FDSCTRL_MIRROR	EQU %00001000 ; 1 = horizontal mirroring, 0 = vertical
FDSCTRL_CRC		EQU %00010000 ; set while the two CRC bytes of a block pass
FDSCTRL_ONE		EQU %00100000 ; always set
FDSCTRL_START	EQU %01000000 ; start transferring a block
FDSCTRL_IRQ		EQU %10000000 ; raise the byte transfer flag (and the IRQ) for each byte

; Zero page the disk routines work in ($00-$0F belong to the BIOS during a
; disk call, as on the original).
DISK_PTR1		EQU $00 ; first pointer parameter (disk ID, disk info)
DISK_PTR2		EQU $02 ; second pointer parameter (file list, file header), or A
DISK_SAVED_SP	EQU $04 ; stack pointer to return to the caller with, also on errors
DISK_SAVED_P	EQU $05 ; the caller's processor flags (its interrupt disable flag)
DISK_FILE_COUNT	EQU $06 ; files on the disk, or files to skip
DISK_BOOT_CODE	EQU $07 ; boot file code from the disk info block
DISK_TEMP		EQU $08 ; expected block type, then the file ID being read
DISK_MATCH		EQU $09 ; 0 = the file is to be loaded, $FF = skip it
DISK_DEST		EQU $0A ; where the file goes (CPU or PPU address)
DISK_SIZE		EQU $0C ; bytes of file data left
DISK_LOADED		EQU $0E ; files loaded so far (returned in Y)
DISK_FILE_TYPE	EQU $0F ; 0 = program, 1 = character, 2 = nametable

FILE_LIST_LENGTH	EQU 20 ; a file list holds up to 20 IDs
GAP_LENGTH			EQU 122 ; bytes of gap written before a block (976 bits, as on disks)

; Error codes:
OK EQU $00 ; no error
DISK_NOT_SET EQU $01 ; disk set, ($4032.0) disk not set
POWER_SUPPLY_FAILURE EQU $02 ; battery, ($4033.7) power supply failure
WRITE_PROTECTED EQU $03 ; ($4032.2) disk is write protected
WRONG_MAKER_ID EQU $04 ; Wrong maker ID
WRONG_GAME EQU $05 ; Wrong game
WRONG_GAME_VER EQU $06 ; Wrong game version
WRONG_SIDE_NUM EQU $07 ; a,b side, wrong side number
WRONG_DISK_NUM EQU $08 ; disk no., wrong disk number
WRONG_ADDL_DISK_ID1 EQU $09 ; wrong additional disk ID 1
WRONG_ADDL_DISK_ID2 EQU $10 ; wrong value in the last disk ID byte (the codes are BCD-like)
APPROVAL_CHECK_FAILED EQU $20 ; disk trouble, approval check failed
WRONG_SIGNATURE EQU $21 ; disk trouble, '*NINTENDO-HVC*' string in block 1 doesn't match
BLOCK_TYPE_1_EXPECTED EQU $22 ; disk trouble, block type 1 expected
BLOCK_TYPE_2_EXPECTED EQU $23 ; disk trouble, block type 2 expected
BLOCK_TYPE_3_EXPECTED EQU $24 ; disk trouble, block type 3 expected
BLOCK_TYPE_4_EXPECTED EQU $25 ; disk trouble, block type 4 expected
BLOCK_FAILED_CRC EQU $27 ;	disk trouble, ($4030.4) block failed CRC
EOF_READ EQU $28 ; disk trouble, ($4030.6) file ends prematurely during read
EOF_WRITE EQU $29 ; disk trouble, ($4030.6) file ends prematurely during write
DISK_FULL EQU $30 ; disk trouble, ($4032.1) disk is full

MACRO API_ENTRYPOINT address
	IF $ > #address
		ERROR "Previous function overflowed into following public API"
	ELSE
		PAD #address
	ENDIF
ENDM

; Fill with a KIL opcode, so we die immediately if we jump into crazytown
FILLVALUE $72

; Start assembling at the beginning of the FDS ROM area
ORG $E000
DB $00

INCLUDE font.asm
INCLUDE delay.asm
INCLUDE ppumask.asm
INCLUDE nmi.asm
INCLUDE irq.asm

; Loads files specified by DiskID into memory from disk. Load addresses are
; decided by the file's header. A failed load is tried once more.
; Parameters: Pointer to Disk ID, Pointer to File List
; Returns: A = error #, Y = # of files loaded
; The two pointers follow the JSR. A file list of just $FF loads the boot files.
API_ENTRYPOINT $e1f8
LoadFiles:
	LDA #$FF
	JSR GetHardCodedPointers
	JSR TwoAttempts
	JSR StartMotor
	JSR WaitForDriveReady
	JSR CheckDiskHeader
	JSR GetNumFiles
	LDA DISK_FILE_COUNT
	BEQ @done
@file:
	JSR LoadData
	DEC DISK_FILE_COUNT
	BNE @file
@done:
	LDA #OK
	JMP DiskExit

; Appends the file data given by DiskID to the disk. This means that the file
; is tacked onto the end of the disk, and the disk file count is incremented.
; The file is then read back to verify the write. If an error occurs during
; verification, the disk's file count is decremented (logically hiding the
; written file).
; Parameters: Pointer to Disk ID, Pointer to File Header
; Returns: A = error #
API_ENTRYPOINT $e237
AppendFile:
	RTS

; Same as "Append File", but instead of writing the file to the end of the
; disk, A specifies the sequential position on the disk to write the file (0
; is the first). This also has the effect of setting the disk's file count to
; the A value, therefore logically hiding any other files that may reside after
; the written one.
; Parameters: Pointer to Disk ID, Pointer to File Header, A = file #
; Returns: A = error #
API_ENTRYPOINT $e239
WriteFile:
	RTS

; Reads in disk's file count, compares it to A, then sets the disk's file count
; to A.
; Parameters: Pointer to Disk ID, A = # to set file count to
; Returns: A = error #
API_ENTRYPOINT $e2b7
CheckFileCount:
	RTS

; Reads in disk's file count, decrements it by A, then writes the new value
; back.
; Parameters: Pointer to Disk ID, A = number to reduce current file count by
; Returns: A = error #
API_ENTRYPOINT $e2bb
AdjustFileCount:
	RTS

; Set the file count to A + 1
; Parameters: Pointer to Disk ID, A = file count minus one = # of the last file
; Returns: A = error #
API_ENTRYPOINT $e301
SetFileCount1:
	RTS

; Set the file count to A
; Parameters: Pointer to Disk ID, A = file count
; Returns: A = error #
API_ENTRYPOINT $e305
SetFileCount:
	RTS

; Fills provided DiskInfo structure with data read off the current disk.
; Parameters: Pointer to Disk Info
; Returns: A = error #
API_ENTRYPOINT $e32a
GetDiskInfo:
	RTS

; Adds Y to the 16-bit pointer at $0A-$0B.
; Parameters: Y = amount to add
; Affects: A, $0A, $0B
API_ENTRYPOINT $e3da
AddYtoPtr0A:
	TYA
	CLC
	ADC DISK_DEST
	STA DISK_DEST
	BCC @done
	INC DISK_DEST+1
@done:
	RTS

INCLUDE gethardcodedpointers.asm

; Compares the first 10 bytes on the disk coming after the FDS string, to 10
; bytes pointed to by Ptr($00). To bypass the checking of any byte, a -1 can be
; placed in the equivelant place in the compare string. Otherwise, if the
; comparison fails, an appropriate error will be generated.
; Parameters: Pointer to 10 byte string at $00
; Also keeps the disk's boot file code in $07 for FileMatchTest.
API_ENTRYPOINT $e445
CheckDiskHeader:
	JMP CheckDiskHeaderImpl

; Reads number of files stored on disk, stores the result in $06
; It is the file amount block, which follows the disk info block.
; Affects: A, $06, $08, $FA
API_ENTRYPOINT $e484
GetNumFiles:
	LDA #2
	JSR CheckBlockType
	JSR ReadByte
	STA DISK_FILE_COUNT
	JMP EndOfBlockRead

; Writes new number of files to disk header.
; Parameters: A = number of files
API_ENTRYPOINT $e492
SetNumFiles:
	RTS

; Uses a byte string pointed at by Ptr($02) to tell the disk system which files
; to load. The file ID's number is searched for in the string. If an exact
; match is found, [$09] is 0'd, and [$0E] is incremented. If no matches are
; found after 20 bytes, or a -1 entry is encountered, [$09] is set to -1. If
; the first byte in the string is -1, the BootID number is used for matching
; files (any FileID that is not greater than the BootID qualifies as a match).
; Parameters: Pointer to FileID list at $02, the file's ID in $08, the boot
; file code in $07 (CheckDiskHeader keeps it there)
; Affects: A, Y, $09, $0E
API_ENTRYPOINT $e4a0
FileMatchTest:
	LDY #0
	LDA (DISK_PTR2),Y
	CMP #$FF
	BNE @list
	LDA DISK_BOOT_CODE	; boot files: any ID not above the boot file code
	CMP DISK_TEMP
	BCS @match
	BCC @noMatch
@list:
	LDA (DISK_PTR2),Y
	CMP #$FF
	BEQ @noMatch
	CMP DISK_TEMP
	BEQ @match
	INY
	CPY #FILE_LIST_LENGTH
	BNE @list
@noMatch:
	LDA #$FF
	STA DISK_MATCH
	RTS
@match:
	LDA #0
	STA DISK_MATCH
	INC DISK_LOADED
	RTS

; Skips over specified number of files.
; Parameters: Number of files to skip in $06
; Each file's header and data blocks are read through and nothing is loaded;
; $06 counts down to 0.
; Affects: A, Y, $06, $08-$0F, $FA
API_ENTRYPOINT $e4da
SkipFiles:
	LDA DISK_FILE_COUNT
	BEQ @done
	JSR ReadFileHeader
	LDA #$FF
	STA DISK_MATCH
	JSR ReadData
	DEC DISK_FILE_COUNT
	JMP SkipFiles
@done:
	RTS

; Reads one file: its header block, then its data block, loading the data
; when the file list at ($02) asks for the file (see FileMatchTest).
; Affects: A, Y, $08-$0F, $FA
API_ENTRYPOINT $e4f9
LoadData:
	JSR ReadFileHeader
	JSR FileMatchTest
	JMP ReadData

; Reads a file data block. Program files go to CPU memory at $0A-$0B,
; character and nametable files to PPU memory there (written through $2007
; with the address incrementing by 1, so rendering must be off). The bytes are
; read past instead when $09 is not 0 (the file was not asked for) or when a
; program file would go below $0200: zero page and the stack belong to the
; BIOS and its caller.
; Parameters: $09 = 0 to load, $0A-$0B = address, $0C-$0D = size, $0F = type
; Affects: A, Y, $08, $0A-$0D, $FA
API_ENTRYPOINT $e506
ReadData:
	LDA #4
	JSR CheckBlockType
	LDA DISK_MATCH
	BNE @skip
	LDA DISK_FILE_TYPE
	BNE @ppu
	LDA DISK_DEST+1
	CMP #$02
	BCC @skip
	LDY #0
@cpu:
	JSR CountDataByte
	BEQ @done
	JSR ReadByte
	STA (DISK_DEST),Y
	INC DISK_DEST
	BNE @cpu
	INC DISK_DEST+1
	JMP @cpu
@ppu:
	LDA PPUSTATUS		; the next $2006 write is the high byte
	LDA DISK_DEST+1
	STA PPUADDR
	LDA DISK_DEST
	STA PPUADDR
	LDA ZP_PPUCTRL
	AND #%11111011		; increment the address by 1
	STA PPUCTRL
@ppuLoop:
	JSR CountDataByte
	BEQ @ppuDone
	JSR ReadByte
	STA PPUDATA
	JMP @ppuLoop
@ppuDone:
	LDA ZP_PPUCTRL
	STA PPUCTRL
	JMP @done
@skip:
	JSR CountDataByte
	BEQ @done
	JSR ReadByte
	JMP @skip
@done:
	JMP EndOfBlockRead

; Counts one byte off the file data left in $0C-$0D.
; Returns: Z set when there was none left
; Affects: A
CountDataByte:
	LDA DISK_SIZE
	ORA DISK_SIZE+1
	BEQ @none
	LDA DISK_SIZE
	BNE @low
	DEC DISK_SIZE+1
@low:
	DEC DISK_SIZE
	LDA #1
@none:
	RTS

API_ENTRYPOINT $e5b5
SaveData:
	RTS

; Waits until the drive, spun up by StartMotor, has its head at the start of
; the disk ($4032 bit 1 clear). The battery is measured first, while the motor
; runs, which is the only time $4033 bit 7 tells; bit 7 of the expansion port
; output ($4026) is raised for that, since it shares the line.
; Fails with POWER_SUPPLY_FAILURE on a low battery and DISK_NOT_SET when the
; disk is taken out while waiting.
; Affects: A, $F9
API_ENTRYPOINT $e64d
WaitForDriveReady:
	LDA ZP_EXTCONN
	ORA #%10000000
	STA ZP_EXTCONN
	STA EXTCONNWR
	LDA EXTCONNRD
	BPL @battery		; bit 7: 1 = the battery is good
@wait:
	LDA DRIVESTATUS
	LSR A				; bit 0: no disk
	BCS @notSet
	LSR A				; bit 1: the head is not at the start yet
	BCS @wait
	RTS
@battery:
	LDA #POWER_SUPPLY_FAILURE
	JMP DiskExit
@notSet:
	LDA #DISK_NOT_SET
	JMP DiskExit

; Stops the drive the way the BIOS leaves it after reset: motor off, transfer
; reset held, read mode, no block transfer and no byte IRQ. Reading $4030 then
; drops a byte transfer flag (and its IRQ) that may still be pending, so a game
; that enables interrupts afterwards does not take a stray disk IRQ.
; Affects: A, $FA
API_ENTRYPOINT $e685
StopMotor:
	LDA #FDSCTRL_ONE | FDSCTRL_READ | FDSCTRL_RESET
	JSR SetDiskControl
	LDA DISKSTATUS
	RTS

; Starts reading the next block and checks its first byte, the block type:
; 1 disk info, 2 file amount, 3 file header, 4 file data.
; Parameters: A = expected block type
; Fails with BLOCK_TYPE_1_EXPECTED to BLOCK_TYPE_4_EXPECTED (the type that was
; expected) when another block comes.
; Affects: A, $08, $FA
API_ENTRYPOINT $e68f
CheckBlockType:
	STA DISK_TEMP
	LDA #FDSCTRL_IRQ | FDSCTRL_START | FDSCTRL_ONE | FDSCTRL_READ | FDSCTRL_MOTOR
	JSR SetDiskControl
	JSR ReadByte
	CMP DISK_TEMP
	BNE @wrong
	RTS
@wrong:
	LDA DISK_TEMP
	CLC
	ADC #BLOCK_TYPE_1_EXPECTED - 1
	JMP DiskExit

; Starts writing a block over whatever follows the last block read or written:
; a gap of zeros, the start mark, then the block type in A. The mark goes to
; $4024 while the drive still reads, so the RAM adapter puts it out when the
; start bit is set, and emulators that store every byte written to $4024 in a
; disk image without gaps or marks (MAME) store only the block itself.
; Parameters: A = block type
; Affects: A, X, $FA
API_ENTRYPOINT $e6b0
WriteBlockType:
	PHA
	LDA #$80			; the start mark, latched for later
	STA WRITEDATA
	LDA #FDSCTRL_IRQ | FDSCTRL_ONE | FDSCTRL_MOTOR
	JSR SetDiskControl	; write mode, no block: the adapter writes zeros
	LDX #GAP_LENGTH
@gap:
	LDA DISKSTATUS
	AND #%00000010
	BEQ @gap
	DEX
	BNE @gap
	LDA #FDSCTRL_IRQ | FDSCTRL_START | FDSCTRL_ONE | FDSCTRL_MOTOR
	JSR SetDiskControl	; the mark goes out next
	PLA
	JMP WriteByte

; Starts transferring a block in the mode the drive is in: sets the start and
; byte IRQ bits of $4025, so the RAM adapter waits for the start mark (reading)
; or writes the byte in $4024 next (writing).
; Affects: A, $FA
API_ENTRYPOINT $e6e3
StartXfer:
	LDA ZP_FDSCTRL
	ORA #FDSCTRL_START | FDSCTRL_IRQ
	STA ZP_FDSCTRL
	STA FDSCTRL
	RTS

; Finishes reading a block: reads the two CRC bytes that follow its data with
; the CRC bit of $4025 set, so the RAM adapter checks them, then ends the
; transfer with the motor still running for the next block.
; Fails with BLOCK_FAILED_CRC when the adapter reports a bad CRC ($4030 bit 4).
; Affects: A, $FA
API_ENTRYPOINT $e706
EndOfBlockRead:
	LDA #FDSCTRL_IRQ | FDSCTRL_START | FDSCTRL_CRC | FDSCTRL_ONE | FDSCTRL_READ | FDSCTRL_MOTOR
	JSR SetDiskControl
	JSR ReadByte
	JSR ReadByte
	LDA DISKSTATUS
	AND #%00010000		; bit 4: CRC error
	BNE @crc
	LDA #FDSCTRL_ONE | FDSCTRL_READ | FDSCTRL_MOTOR
	JMP SetDiskControl
@crc:
	LDA #BLOCK_FAILED_CRC
	JMP DiskExit

API_ENTRYPOINT $e729
EndOfBlkWrite:
	RTS

; Ends the transfer of a block: clears the start, CRC and byte IRQ bits of
; $4025 and leaves the motor, mode and mirroring as they are. Reading $4030
; drops a byte transfer flag that may still be pending.
; Affects: A, $FA
API_ENTRYPOINT $e778
XferDone:
	LDA ZP_FDSCTRL
	AND #$FF ^ (FDSCTRL_START | FDSCTRL_CRC | FDSCTRL_IRQ)
	STA ZP_FDSCTRL
	STA FDSCTRL
	LDA DISKSTATUS
	RTS

; Starts the transfer of a block and exchanges its first byte: sets the start
; and byte IRQ bits of $4025, then does what XferByte does. Does not know or
; care whether it's a read or write.
; Parameters: A = byte to write to disk (if this is a write)
; Affects: X, $FA
; Returns: A = byte read from disk (if this is a read)
API_ENTRYPOINT $e794
Xfer1stByte:
	TAX
	LDA ZP_FDSCTRL
	ORA #FDSCTRL_START | FDSCTRL_IRQ
	STA ZP_FDSCTRL
	STA FDSCTRL
	TXA
	JMP XferByte

; Waits for a byte to be transferred between the drive and the RAM adapter,
; then hands it the byte to write and takes the byte read. Does not know or
; care whether it's a read or write. This BIOS waits by polling the byte
; transfer flag in $4030 rather than in an IRQ handler, so it works with
; interrupts disabled; the byte IRQ bit of $4025 must be set, as
; Xfer1stByte sets it, since the flag only follows it.
; Parameters: A = byte to write to disk (if this is a write)
; Affects: X
; Returns: A = byte read from disk (if this is a read)
API_ENTRYPOINT $e7a3
XferByte:
	TAX
@wait:
	LDA DISKSTATUS
	AND #%00000010		; bit 1: byte transfer flag
	BEQ @wait
	STX WRITEDATA
	LDA READDATA
	RTS

; VRAM Buffers
;  The structure of VRAM buffers are as follows:
;
; SIZE   CONTENTS
; 2      VRAM Address (big endian)
; 1      bit 0-5 length of data ($0 means a length of 64)
;        bit 6 : 0 = copy, 1 = fill
;        bit 7 : 0 = increment by 1, 1 = increment by 32
; n      Data to copy to VRAM
; .....  repeated as many times as needed
; 1      $ff
;
; * The main structure is terminated by a byte >= $80 (High address is always
;   supposed to be in $00..$3f range)
; * $4c is a "call" command. The 2 bytes that follow is the address of a sub-
;   VRAM structure. The sub-structure can call another sub-structure and so on.
; * $60 is a "return" command. It will terminate a sub-structure.
; * If Fill mode is used, the routine takes only 1 byte of data which is
;   repeated.
;
; The VRAM buffer is located at $300-$3xx. $300 holds the size of the buffer
; (maximum), and $301 holds the end index of the buffer. The actual buffer lies
; at $302-$3xx, and is of variable length.
;
; * $300 is initialized to the value $7d, effectively making the buffer lie at
;   $300-$37f. It's possible to change the value here to make it bigger or
;   smaller, but the biggest possible value is $fd, making the buffer lie at
;   $300-$3ff.
; * Format of the buffer is equivalent to the VRAM structure above, except that
;   there are no sub-structures, no increment by 32 flag and no fill flag.
; * For this reason, the VRAM buffer at $302 can be used as a sub-structure.
; * A call to WriteVRAMBuffers will execute faster than a call to
;   VRAMStructWrite with $302 as an argument, but both will have the same
;   effect.
;
; The structure of the VRAM read buffer itself is trivial - only single bytes
; are read (there's no runs of data). All reads are mapped to a structure of 3
; bytes in the read buffer:
;
; SIZE   CONTENTS
; 2      VRAM Address (big endian)
; 1      data
;
; Therfore, for each byte which is read from VRAM, 3 bytes have to be reserved
; in the read buffer. Once data from VRAM has been read, if it must be written
; back after a modification, the user need to copy it to the write buffer
; manually.

INCLUDE vramstructwrite.asm
INCLUDE fetchdirectptr.asm
INCLUDE vrambuffers.asm
INCLUDE vramstrings.asm
INCLUDE getvrambufferbyte.asm
INCLUDE nametable.asm
INCLUDE random.asm

; Run Sprite DMA from RAM $200-$2FF
; Affects: A
API_ENTRYPOINT $e9c8
SpriteDMA:
	LDA #0
	STA OAMADDR
	LDA #$02
	STA OAMDMA
	RTS

INCLUDE counterlogic.asm
INCLUDE gamepads.asm
INCLUDE vramfill.asm

; Fill RAM pages with specified value.
; Parameters: A = fill value, X = first page #, Y = last page #
; Affects: A, X, Y, $00, $01
API_ENTRYPOINT $ead2
MemFill:
	; Start from the high end and count down
	; The address of the start of the last page is just the Y register in the high byte of the pointer and 0 in the low byte
	STY $01
@outerloop:
	LDY #0
	STY $00
@loop:
	STA ($00),Y
	INY
	BNE @loop
	DEC $01 ; work on the next page down
	CPX $01
	BMI @outerloop ; cover the X < $01 case
	BEQ @outerloop ; cover the X == $01 case
	RTS

; Set scroll registers according to values in $FC, $FD and $FF.
; Should typically be called in VBlank after VRAM updates
; Parameters: $FC, $FD, $FF
; Affects: A
API_ENTRYPOINT $eaea
SetScroll:
	LDA PPUSTATUS ; reset PPU's "w" register to 0
	LDA ZP_PPUSCROLL1
	STA PPUSCROLL
	LDA ZP_PPUSCROLL2
	STA PPUSCROLL
	LDA ZP_PPUCTRL
	STA PPUCTRL
	RTS

; The instruction calling this is supposed to be followed by a jump table
; (16-bit pointers little endian, up to 128 pointers). A is the entry # to jump
; to, return address on stack is used to get jump table entries.
; Parameters: A = Jump table entry
; Affects: A, X, Y, $00, $01
API_ENTRYPOINT $eafd
JumpEngine:
	; the top of the stack is 1 less than the address of the table
	SEC   ; to rotate a 1 into the LSB, set the carry
	ROL A ; Each entry is 2 bytes, so multiply A by two to get the offset
	TAY   ; now A is freed up and Y has the offset, which will be useful later
; get the address of the jump table
	PLA ; low byte of the jump table address
	STA $00
	PLA ; high byte of the jump table address
	STA $01
; post-indexed indirect load of the entry in the jump table
	LDA ($00),Y
	TAX
	INY
	LDA ($00),Y
	STX $00
	STA $01
; (indirect) jump!
	JMP ($00)

; Read Family Basic Keyboard expansion
API_ENTRYPOINT $eb13
ReadKeyboard:
	RTS

INCLUDE loadtileset.asm

; Some kind of logic that some games use. (detail is under analysis)
; Parameters: $00-$01 Pointer to structure... ?
; Affects: A, X, Y, $02, $03, $04, $05, $06, $07, $08, $09
API_ENTRYPOINT $ec22
unk_EC22:
	RTS

INCLUDE startmotor.asm

; private functions

INCLUDE diskcontrol.asm
INCLUDE diskentry.asm
INCLUDE diskexit.asm
INCLUDE diskbytes.asm
INCLUDE checkdiskheader.asm
INCLUDE readfileheader.asm

; Checks whether the little-endian address provided in ($02) plus the offset in
; $04 is in the range $3Fxx (or one of its mirrors). Checks the current PPU
; increment mode to do the correct arithmetic. If the current PPU address is in
; the palette, reset to $0000. Assumes that the PPUADDR latch is currently
; clear.
; Parameters: $00-$01 = PPU address, $02 = offset
; Affects: A, X, Y
PreventPalettePpuAddr:
	LDA #%00000100 ; increment mode flag bit test
	AND ZP_PPUCTRL
	BEQ @incr1
	LDA $02 ; low address byte
	LDY $03 ; high address byte
	LDX $04 ; offset
	BEQ @check ; if the offset is 0, jump straight to the check
@incr32:
	CLC
	ADC #32 ; for (X = $04; X != 0; X--) $02,$03 += 32;
	BCC @nextiter
	INY
@nextiter:
	DEX
	BNE @incr32
	BEQ @check
@incr1:
	LDA $02  ; low address byte
	LDY $03  ; high address byte
	CLC
	ADC $04  ; add length to low address byte
	BCC @check
	INY ; add C to high address byte
@check:
	TYA
	AND #$3F ; we might be in the mirror $7Fxx range instead of $3Fxx
	CMP #$3F ; now check for exactly $3F
	BNE @done
	LDA #0 ; reset PPUADDR to 0 to get it out of the palette area
	STA PPUADDR
	STA PPUADDR
@done:
	RTS

INCLUDE reset.asm

; the hard-coded interrupt vectors at the end of ROM
API_ENTRYPOINT $fffa
	DW NMI
	DW RESET
	DW IRQ
