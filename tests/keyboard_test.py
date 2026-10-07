"""Reads the Family BASIC keyboard in MAME through ReadKeyboard.

    python tests/keyboard_test.py --mame path/to/mame.exe disk.fds

The disk boots as in boot_test.py; any disk will do, it only gives the
console something to run. As in loadfiles_test.py, a program written to
RAM runs from the game's first NMI vector. It waits for a go byte, calls
ReadKeyboard and keeps A and $00-$08, twice: first with every key up,
then with F8, STOP, Q and SPACE held through MAME's input ports.

MAME runs twice, with its Family Computer keyboard on the expansion port
and with nothing there. With the keyboard, both calls must return $FF,
the first with no key down and the second with exactly the held keys in
their rows and columns. Without it, both must return $00 and clear the
data.
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
GO = 0x04F0
RESULT = 0x04A0     # A, then $00-$08
DONE = 0x04AA       # counts the calls made
READ_KEYBOARD = 0xEB13

# The held keys as MAME names them, with the byte and bit ReadKeyboard must
# set: $00 holds row 8, $08 row 0, column 0 in the low nibble.
HELD = [("FCKEY.0", "F8", 8, 0x01), ("FCKEY.0", "Stop", 8, 0x80),
        ("FCKEY.7", "Q", 1, 0x04), ("FCKEY.8", "Space", 0, 0x20)]


def word(value: int) -> bytes:
    return value.to_bytes(2, "little")


def stub() -> bytes:
    code = bytearray(b"\xA9\x00\x8D\x00\x20")                  # no NMIs
    wait = STUB + len(code)
    code += bytes([0xAD]) + word(GO) + b"\xF0\xFB"             # LDA go / BEQ wait
    code += bytes([0xA9, 0x00, 0x8D]) + word(GO)               # LDA #0 / STA go
    code += bytes([0x20]) + word(READ_KEYBOARD)                # JSR ReadKeyboard
    code += bytes([0x8D]) + word(RESULT)                       # STA result
    code += b"\xA2\x08"                                        # LDX #8
    code += b"\xB5\x00" + bytes([0x9D]) + word(RESULT + 1)     # LDA $00,X / STA result+1,X
    code += b"\xCA\x10\xF8"                                    # DEX / BPL copy
    code += bytes([0xEE]) + word(DONE)                         # INC done
    code += bytes([0x4C]) + word(wait)
    return bytes(code)


def lua(keyboard: bool) -> str:
    press = "\n".join(
        f"    ports[':exp:fc_keyboard:{port}'].fields['{name}']:set_value(1)" for port, name, _, _ in HELD)
    return f"""
local cpu = manager.machine.devices[':maincpu']
local p = cpu.spaces['program']
local ports = manager.machine.ioport.ports
local booted, started, frame, calls = nil, nil, 0, 0
local code = '{stub().hex()}'
tap = p:install_write_tap(0x0102, 0x0102, 'boot', function(o, d, m)
  if d == 0x35 and booted == nil then booted = frame end
  return d
end)
local function report()
  local s = string.format('CALL %d a=%02X data=', calls, p:read_u8({RESULT}))
  for i = 0, 8 do s = s .. string.format('%02X', p:read_u8({RESULT + 1} + i)) end
  print(s)
end
emu.register_frame_done(function()
  frame = frame + 1
  if booted ~= nil and started == nil and frame >= booted + 120 then
    for i = 0, #code / 2 - 1 do p:write_u8({STUB} + i, tonumber(code:sub(i * 2 + 1, i * 2 + 2), 16)) end
    p:write_u8({DONE}, 0)
    p:write_u8({GO}, 1)
    p:write_u8(0xDFF6, {STUB & 0xFF}); p:write_u8(0xDFF7, {STUB >> 8}); p:write_u8(0x0100, 0x40)
    started = frame
  elseif started ~= nil and p:read_u8({DONE}) > calls then
    calls = calls + 1
    report()
    if calls == 2 then manager.machine:exit() return end
{press if keyboard else ""}
    p:write_u8({GO}, 1)
  elseif frame >= 60 * 120 then
    print(string.format('TIMEOUT pc=%04X', cpu.state['PC'].value)); manager.machine:exit()
  end
end)
"""


def run(mame: Path, bios: Path, disk: Path, keyboard: bool) -> bool:
    with tempfile.TemporaryDirectory(prefix="opendisksys-") as temp:
        work = Path(temp)
        (work / "roms" / "fds").mkdir(parents=True)
        shutil.copyfile(bios, work / "roms" / "fds" / "rp2c33a-01a.bin")
        (work / "test.lua").write_text(lua(keyboard), encoding="ascii")
        result = subprocess.run(
            [str(mame), "fds", "-flop", str(disk), *(["-exp", "fc_keyboard"] if keyboard else []),
             "-rompath", str(work / "roms"),
             "-cfg_directory", str(work / "cfg"), "-nvram_directory", str(work / "nvram"),
             "-video", "none", "-sound", "none", "-nothrottle", "-skip_gameinfo",
             "-autoboot_delay", "0", "-autoboot_script", str(work / "test.lua")],
            cwd=mame.parent, capture_output=True, text=True, timeout=600, stdin=subprocess.DEVNULL)
    lines = [l for l in result.stdout.splitlines() if l.startswith(("CALL", "TIMEOUT"))]
    held = bytearray(9)
    for _, _, index, bit in HELD:
        held[index] |= bit
    if keyboard:
        want = [f"CALL 1 a=FF data={bytes(9).hex().upper()}", f"CALL 2 a=FF data={held.hex().upper()}"]
    else:
        want = [f"CALL {n} a=00 data={bytes(9).hex().upper()}" for n in (1, 2)]
    for line in lines:
        print(f"  {'ok ' if line in want else 'BAD'} {line}")
    passed = lines == want
    name = "keyboard on the expansion port" if keyboard else "nothing on the expansion port"
    print(f"{'PASS' if passed else 'FAIL'} {name}")
    return passed


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
    disk = arguments.disk.resolve()
    results = [run(mame, bios, disk, True), run(mame, bios, disk, False)]
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
