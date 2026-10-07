# OpenDiskSysROM

OpenDiskSysROM continues [FreeDiskSysROM](https://github.com/jamesathey/freedisksysrom)
by James Athey, which has not changed since 2020. It keeps that project's
history, goal, rules and license (LGPL-3.0); the work here adds what was
missing to run games: the disk I/O routines and the boot loader. It is
developed for [Retrolarium](https://github.com/Retrolarium), whose studio
plays Famicom Disk System games in MAME without asking for Nintendo's BIOS.

Files James Athey wrote keep his copyright notice; files changed or added
here say so in their header.

This project has one goal - a compatible re-implementation of the Famicom Disk System BIOS under an OSS license. Unlike the Famicom console itself, which has no program ROM built-in, the Famicom Disk System includes an 8 KiB PRG-ROM containing disk I/O routines, VRAM transfer routines, joypad reading code, an animation featuring Mario and Luigi when no disk is present in the drive, and more. The code, data, graphics, music, and animation contained in the original BIOS are copyrighted by Nintendo.

OpenDiskSysROM aims to provide a replacement for the original FDS BIOS that can be freely redistributed and that is capable of running all published FDS software.

# Audience

## Emulators

Famicom and NES emulators historically require a dump of the Famicom Disk System BIOS to be able to emulate FDS titles. Emulators can ship OpenDiskSysROM with their installers instead of requiring end-users to either copy the ROM out of their own FDS hardware or breaking copyright law by downloading a BIOS rip from elsewhere on the Internet.

## Clone hardware

Modern hardware clones of the FDS RAM Adapter or FPGA re-implementations of the entire Famicom Disk System also need a BIOS.

# Status

## APIs

Every documented entry point is implemented. The disk routines boot and run
Super Mario Bros., All Night Nippon Super Mario Bros. and Super Mario Bros. 2
in MAME, and their writes were checked by reading them back.

| Address | Name | # of Games | Implemented |
| ------- | ---- | ------- | ----------- |
| $e149 | Delay131 |  | :white_check_mark: |
| $e153 | Delayms |  | :white_check_mark: |
| $e161 | DisPFObj |  | :white_check_mark: |
| $e16b | EnPFObj |  | :white_check_mark: |
| $e171 | DisObj |  | :white_check_mark: |
| $e178 | EnObj |  | :white_check_mark: |
| $e17e | DisPF |  | :white_check_mark: |
| $e185 | EnPF |  | :white_check_mark: |
| $e18b | NMI |  | :white_check_mark: |
| $e1b2 | VINTWait |  | :white_check_mark: |
| $e1c7 | IRQ |  | :white_check_mark: |
| $e1f8 | LoadFiles |  | :white_check_mark: |
| $e237 | AppendFile |  | :white_check_mark: |
| $e239 | WriteFile |  | :white_check_mark: |
| $e2b7 | CheckFileCount |  | :white_check_mark: |
| $e2bb | AdjustFileCount |  | :white_check_mark: |
| $e301 | SetFileCount1 |  | :white_check_mark: |
| $e305 | SetFileCount |  | :white_check_mark: |
| $e32a | GetDiskInfo |  | :white_check_mark: |
| $e3da | AddYtoPtr0A |  | :white_check_mark: |
| $e3e7 | GetHardCodedPointers |  | :white_check_mark: |
| $e3ea | GetHardCodedPointersWriteProtected |  | :white_check_mark: |
| $e445 | CheckDiskHeader |  | :white_check_mark: |
| $e484 | GetNumFiles |  | :white_check_mark: |
| $e492 | SetNumFiles |  | :white_check_mark: |
| $e4a0 | FileMatchTest | 0 | :white_check_mark: |
| $e4da | SkipFiles | 0 | :white_check_mark: |
| $e4f9 | LoadData |  | :white_check_mark: |
| $e506 | ReadData |  | :white_check_mark: |
| $e5b5 | SaveData |  | :white_check_mark: |
| $e64d | WaitForDriveReady |  | :white_check_mark: |
| $e685 | StopMotor |  | :white_check_mark: |
| $e68f | CheckBlockType |  | :white_check_mark: |
| $e6b0 | WriteBlockType |  | :white_check_mark: |
| $e6e3 | StartXfer |  | :white_check_mark: |
| $e706 | EndOfBlockRead |  | :white_check_mark: |
| $e729 | EndOfBlkWrite |  | :white_check_mark: |
| $e778 | XferDone |  | :white_check_mark: |
| $e794 | Xfer1stByte |  | :white_check_mark: |
| $e7a3 | XferByte |  | :white_check_mark: |
| $e7bb | VRAMStructWrite |  | :white_check_mark: |
| $e844 | FetchDirectPtr |  | :white_check_mark: |
| $e86a | WriteVRAMBuffers |  | :white_check_mark: |
| $e8b3 | ReadIndividualVRAMBytes |  | :white_check_mark: |
| $e8d2 | PrepareVRAMString |  | :white_check_mark: |
| $e8e1 | PrepareVRAMStrings |  | :white_check_mark: |
| $e94f | GetVRAMBufferByte |  | :white_check_mark: |
| $e97d | Pixel2NamConv |  | :white_check_mark: |
| $e997 | Nam2PixelConv |  | :white_check_mark: |
| $e9b1 | Random |  | :white_check_mark: |
| $e9c8 | SpriteDMA |  | :white_check_mark: |
| $e9d3 | CounterLogic |  | :white_check_mark: |
| $e9eb | ReadPads |  | :white_check_mark: |
| $ea1a | ReadDownPads |  | :white_check_mark: |
| $ea1f | ReadOrDownPads |  | :white_check_mark: |
| $ea36 | ReadDownVerifyPads |  | :white_check_mark: |
| $ea4c | ReadOrDownVerifyPads |  | :white_check_mark: |
| $ea68 | ReadDownExpPads |  | :white_check_mark: |
| $ea84 | VRAMFill |  | :white_check_mark: |
| $ead2 | MemFill |  | :white_check_mark: |
| $eaea | SetScroll |  | :white_check_mark: |
| $eafd | JumpEngine |  | :white_check_mark: |
| $eb13 | ReadKeyboard | 0 | :white_check_mark: |
| $ebaf | LoadTileset |  | :white_check_mark: |
| $ec22 | UploadObject |  | :white_check_mark: |
| $ee17 | StartMotor |  | :white_check_mark: |

## Initialization

On a cold start the BIOS clears the console's state and goes to the boot
loader; on a soft reset with a game in RAM ($0102/$0103 = $35/$53 or
$35/$AC) it starts that game through its reset vector again. The boot loader
shows INSERT A DISK in the BIOS font until a disk is in the drive, then loads
every file whose ID is not above the disk's boot file code. A failed load
shows DISK ERROR with the error number for about two seconds and tries again.
There is no animation: the original's Mario and Luigi are Nintendo's.

## Tests

The scripts in `tests/` assemble the BIOS, start MAME's `fds` system with it
from a private ROM path and check what the routines did through MAME's Lua
interface. Each takes a disk image and MAME (`--mame` or the `MAME` variable),
and asm6f (`--asm6f`, the `ASM6F` variable or `asm6f` on PATH):

| Script | Checks |
| ------ | ------ |
| `boot_test.py` | the boot loader puts every boot file in place |
| `loadfiles_test.py` | LoadFiles on a running game, including a wrong disk ID |
| `writefile_test.py` | WriteFile, AppendFile, the file count calls and GetDiskInfo |
| `keyboard_test.py` | ReadKeyboard with and without MAME's Family BASIC keyboard |
| `uploadobject_test.py` | UploadObject against a model of the object structure |

MAME keeps disk writes in memory, so the image is never changed. In a window
(the tests run without one) MAME first asks for a key press, because the BIOS
is not the one it knows.

# Building

To build, use [asm6f](https://github.com/freem/asm6f).

```
asm6f freedisksys.asm build/opendisksys.bin
```

MAME and most emulators look for the BIOS as `disksys.rom` or, in MAME's
`fds` ROM set, `rp2c33a-01a.bin`.

The `-l` flag is very useful for development - it shows the addresses assigned
to each instruction, so you can easily see how much room remains for a given
subroutine.

# Contributing

Rules:

1. Do not even look at a disassembly of the original FDS BIOS.
1. Only contribute code to which you hold the copyright or which is already under a compatible license.

# License

OpenDiskSysROM, like FreeDiskSysROM, is licensed under the GNU LGPL v3. The intent in using this license is to allow anyone to replace the 8 KiB official FDS BIOS with OpenDiskSysROM, whether for commerical or non-commercial purposes, so long as the source of OpenDiskSysROM (including any modifications) is made available to the end-user under the same license.

Although the Famicom does not have an OS or any concept of dynamic linking, the FDS BIOS is analogous to a system library in practice. FDS titles, FDS emulators, and FDS clone systems are all permitted to utilize OpenDiskSysROM without regard to or changes to the licenses of their own code.
