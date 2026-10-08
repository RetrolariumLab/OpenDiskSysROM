"""Reads a disk through the low-level BIOS calls with interrupts enabled.

    python tests/lowlevel_test.py --mame path/to/mame.exe disk.fds

Some games load with their own loader built from the BIOS's block calls
instead of LoadFiles, and may call them with interrupts enabled. As in
loadfiles_test.py, a program written to RAM runs from the game's first NMI
vector once the disk has booted. It sets the IRQ action to $80 (the BIOS
acknowledges IRQs, its value on reset), clears the interrupt disable flag
and then reads the start of the disk the way such a loader does:
StartMotor, WaitForDriveReady, CheckBlockType for the disk info block,
then XferByte for the 14 bytes of its *NINTENDO-HVC* mark and
EndOfBlockRead. It keeps the BIOS's error exit pointed at itself, so a
failure comes back as an error number instead of returning to the game.
The mark must arrive intact.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from boot_test import assemble  # noqa: E402

STUB = 0x0400
MARK = 0x0500
RESULT = 0x0520     # A, then $5A when done
START_MOTOR, WAIT_READY, CHECK_BLOCK_TYPE = 0xEE17, 0xE64D, 0xE68F
END_OF_BLOCK_READ, XFER_BYTE = 0xE706, 0xE7A3


def word(value: int) -> bytes:
    return value.to_bytes(2, "little")


def stub() -> bytes:
    code = bytearray(b"\xA9\x00\x8D\x00\x20")                  # no NMIs
    code += b"\xA9\x80\x8D\x01\x01"                            # LDA #$80 / STA $0101
    body = STUB + len(code) + 3 + 3 + 5 + 3                    # where @body starts
    code += bytes([0x20]) + word(body)                         # JSR @body
    code += bytes([0x8D]) + word(RESULT)                       # STA result
    code += bytes([0xA9, 0x5A, 0x8D]) + word(RESULT + 1)       # LDA #$5A / STA done
    code += bytes([0x4C]) + word(STUB + len(code))             # JMP to itself
    assert STUB + len(code) == body
    # @body: DiskExit returns from here, with the error number, on a failure.
    code += b"\xBA\x86\x04"                                    # TSX / STX $04 (saved SP)
    code += b"\x58\x08\x68\x85\x05"                            # CLI / PHP / PLA / STA $05 (saved P, I clear)
    code += bytes([0x20]) + word(START_MOTOR)
    code += bytes([0x20]) + word(WAIT_READY)
    code += bytes([0xA9, 0x01, 0x20]) + word(CHECK_BLOCK_TYPE)  # the disk info block
    code += b"\xA0\x00"                                        # LDY #0
    loop = STUB + len(code)
    code += bytes([0x20]) + word(XFER_BYTE)                    # JSR XferByte
    code += bytes([0x99]) + word(MARK)                         # STA mark,Y
    code += b"\xC8\xC0\x0E"                                    # INY / CPY #14
    code += b"\xD0" + bytes([(loop - (STUB + len(code) + 2)) & 0xFF])  # BNE loop
    code += b"\xA9\x00\x60"                                    # LDA #0 / RTS
    return bytes(code)


def lua() -> str:
    return f"""
local cpu = manager.machine.devices[':maincpu']
local p = cpu.spaces['program']
local booted, started, frame = nil, nil, 0
local code = '{stub().hex()}'
tap = p:install_write_tap(0x0102, 0x0102, 'boot', function(o, d, m)
  if d == 0x35 and booted == nil then booted = frame end
  return d
end)
emu.register_frame_done(function()
  frame = frame + 1
  if booted ~= nil and started == nil and frame >= booted + 120 then
    for i = 0, #code / 2 - 1 do p:write_u8({STUB} + i, tonumber(code:sub(i * 2 + 1, i * 2 + 2), 16)) end
    for i = 0, 15 do p:write_u8({MARK} + i, 0) end
    p:write_u8({RESULT + 1}, 0)
    p:write_u8(0xDFF6, {STUB & 0xFF}); p:write_u8(0xDFF7, {STUB >> 8}); p:write_u8(0x0100, 0x40)
    started = frame
  elseif started ~= nil and p:read_u8({RESULT + 1}) == 0x5A then
    local s = ''
    for i = 0, 13 do s = s .. string.char(p:read_u8({MARK} + i)) end
    print(string.format('RESULT a=%02X mark=%s', p:read_u8({RESULT}), s))
    manager.machine:exit()
  elseif started ~= nil and frame >= started + 600 then
    print(string.format('TIMEOUT pc=%04X', cpu.state['PC'].value)); manager.machine:exit()
  end
end)
"""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("disk", type=Path)
    parser.add_argument("--mame", type=Path, default=os.environ.get("MAME"))
    parser.add_argument("--asm6f", default=os.environ.get("ASM6F", "asm6f"))
    arguments = parser.parse_args()
    if arguments.mame is None or not arguments.mame.is_file():
        parser.error("give MAME with --mame or the MAME environment variable")
    bios = assemble(arguments.asm6f)
    mame = arguments.mame.resolve()
    with tempfile.TemporaryDirectory(prefix="opendisksys-") as temp:
        work = Path(temp)
        (work / "roms" / "fds").mkdir(parents=True)
        shutil.copyfile(bios, work / "roms" / "fds" / "rp2c33a-01a.bin")
        (work / "test.lua").write_text(lua(), encoding="ascii")
        result = subprocess.run(
            [str(mame), "fds", "-flop", str(arguments.disk.resolve()), "-rompath", str(work / "roms"),
             "-cfg_directory", str(work / "cfg"), "-nvram_directory", str(work / "nvram"),
             "-video", "none", "-sound", "none", "-nothrottle", "-skip_gameinfo",
             "-autoboot_delay", "0", "-autoboot_script", str(work / "test.lua")],
            cwd=mame.parent, capture_output=True, text=True, timeout=600, stdin=subprocess.DEVNULL)
    lines = [l for l in result.stdout.splitlines() if l.startswith(("RESULT", "TIMEOUT"))]
    for line in lines:
        print(f"  {line}")
    passed = lines == ["RESULT a=00 mark=*NINTENDO-HVC*"]
    print(f"{'PASS' if passed else 'FAIL'} {arguments.disk.name}: block calls with interrupts enabled")
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
