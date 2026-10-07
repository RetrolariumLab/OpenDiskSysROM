"""Calls LoadFiles on a running game and checks what it did.

    python tests/loadfiles_test.py --mame path/to/mame.exe disk.fds

The disk boots as in boot_test.py. Once the game has been running for a
while, a Lua script fills the memory the requested files go to with
zeros, writes a small program to $0400 and has the next NMI run it: it
points the game's first NMI vector ($DFF6) at the program and selects
that vector in $0100, so the BIOS's own NMI dispatch jumps there. The
program turns NMIs off, calls LoadFiles with a disk ID and a file list
of the scenario, and stores A and Y. The script then checks the error
number, the number of files loaded and, after a successful load, that
every byte of the files is in place again.

The scenarios load one program file, a character file and a program
file together, and ask for disk IDs that do not match in the game name
or in the last byte, which must fail with the error of the differing
field ($05, $10) and load nothing. In the last scenario a read tap
spoils the first byte the BIOS reads from the disk, once: the first
attempt fails on the block type, and the second, which LoadFiles makes
by itself, must load the file.
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
from boot_test import assemble, disk_files, side_a  # noqa: E402

STUB = 0x0400       # the test program
DISK_ID = 0x0480    # its 10-byte disk ID
FILE_LIST = 0x0490  # its file list
RESULT = 0x04A0     # A, Y, then $5A when it has returned


def stub() -> bytes:
    code = bytearray()
    code += bytes([0xA9, 0x00, 0x8D, 0x00, 0x20])          # LDA #0 / STA $2000: no NMIs
    code += bytes([0x20, 0xF8, 0xE1])                      # JSR LoadFiles
    code += DISK_ID.to_bytes(2, "little") + FILE_LIST.to_bytes(2, "little")
    code += bytes([0x8D]) + RESULT.to_bytes(2, "little")         # STA result
    code += bytes([0x8C]) + (RESULT + 1).to_bytes(2, "little")   # STY result+1
    code += bytes([0xA9, 0x5A, 0x8D]) + (RESULT + 2).to_bytes(2, "little")
    loop = STUB + len(code)
    code += bytes([0x4C]) + loop.to_bytes(2, "little")           # JMP to itself
    return bytes(code)


def lua(disk_id: bytes, file_list: bytes, fills: list[tuple[str, int, int]],
        checks: list[tuple[str, int, bytes]], want_a: int, want_y: int,
        glitch: bool = False) -> str:
    def table(rows, fmt):
        return "{" + ", ".join(fmt(row) for row in rows) + "}"
    return f"""
local cpu = manager.machine.devices[':maincpu']
local program = cpu.spaces['program']
local video = manager.machine.devices[':ppu'].spaces['videoram']
local function space(name) return name == 'cpu' and program or video end
local fills = {table(fills, lambda r: f"{{'{r[0]}', {r[1]}, {r[2]}}}")}
local checks = {table(checks, lambda r: f"{{'{r[0]}', {r[1]}, '{r[2].hex()}'}}")}
local code = '{stub().hex()}'
local disk_id = '{disk_id.hex()}'
local file_list = '{file_list.hex()}'
local booted, started, frame = nil, nil, 0
local glitch = {'true' if glitch else 'false'}
local function poke(address, hex)
  for i = 0, #hex / 2 - 1 do program:write_u8(address + i, tonumber(hex:sub(i * 2 + 1, i * 2 + 2), 16)) end
end
tap = program:install_write_tap(0x0102, 0x0102, 'boot', function(offset, data, mask)
  if data == 0x35 and booted == nil then booted = frame end
  return data
end)
emu.register_frame_done(function()
  frame = frame + 1
  if booted ~= nil and started == nil and frame >= booted + 120 then
    for _, fill in ipairs(fills) do
      for i = 0, fill[3] - 1 do space(fill[1]):write_u8(fill[2] + i, 0) end
    end
    poke({STUB}, code)
    poke({DISK_ID}, disk_id)
    poke({FILE_LIST}, file_list)
    program:write_u8({RESULT + 2}, 0)
    program:write_u8(0xDFF6, {STUB & 0xFF})
    program:write_u8(0xDFF7, {STUB >> 8})
    program:write_u8(0x0100, 0x40)
    started = frame
    if glitch then
      -- The first byte read from the disk comes out wrong, once.
      glitch_tap = program:install_read_tap(0x4031, 0x4031, 'glitch', function(offset, data, mask)
        glitch_tap:remove()
        print('GLITCH')
        return data ~ 0xFF
      end)
    end
  elseif started ~= nil and program:read_u8({RESULT + 2}) == 0x5A then
    local a, y = program:read_u8({RESULT}), program:read_u8({RESULT + 1})
    local bad, total = 0, 0
    if a == 0 then
      for _, check in ipairs(checks) do
        local hex = check[3]
        for i = 0, #hex / 2 - 1 do
          total = total + 1
          if space(check[1]):read_u8(check[2] + i) ~= tonumber(hex:sub(i * 2 + 1, i * 2 + 2), 16) then
            if bad < 4 then print(string.format('MISMATCH %s $%04X', check[1], check[2] + i)) end
            bad = bad + 1
          end
        end
      end
    end
    print(string.format('RESULT a=%02X y=%d frames=%d bytes=%d mismatched=%d', a, y, frame - started, total, bad))
    manager.machine:exit()
  elseif frame >= 60 * 120 then
    print(string.format('TIMEOUT pc=%04X booted=%s started=%s', cpu.state['PC'].value, tostring(booted), tostring(started)))
    manager.machine:exit()
  end
end)
"""


def run(mame: Path, bios: Path, disk: Path, name: str, disk_id: bytes, ids: list[int],
        want_a: int, glitch: bool = False) -> bool:
    side = side_a(disk.read_bytes())
    _boot, files = disk_files(side)
    wanted = [f for f in files if f.file_id in ids]
    fills = [("cpu" if f.kind == 0 else "ppu", f.address, len(f.data)) for f in wanted]
    checks = [("cpu" if f.kind == 0 else "ppu", f.address, f.data) for f in wanted]
    want_y = len(wanted) if want_a == 0 else 0
    script = lua(disk_id, bytes(ids) + b"\xff", fills, checks, want_a, want_y,
                 glitch)
    with tempfile.TemporaryDirectory(prefix="opendisksys-") as temp:
        work = Path(temp)
        (work / "roms" / "fds").mkdir(parents=True)
        shutil.copyfile(bios, work / "roms" / "fds" / "rp2c33a-01a.bin")
        (work / "test.lua").write_text(script, encoding="ascii")
        result = subprocess.run(
            [str(mame), "fds", "-flop", str(disk), "-rompath", str(work / "roms"),
             "-cfg_directory", str(work / "cfg"), "-nvram_directory", str(work / "nvram"),
             "-video", "none", "-sound", "none", "-nothrottle", "-skip_gameinfo",
             "-autoboot_delay", "0", "-autoboot_script", str(work / "test.lua")],
            cwd=mame.parent, capture_output=True, text=True, timeout=600, stdin=subprocess.DEVNULL)
    lines = [l for l in result.stdout.splitlines()
             if l.startswith(("RESULT", "MISMATCH", "TIMEOUT", "GLITCH"))]
    for line in lines:
        print(f"  {line}")
    expected = f"RESULT a={want_a:02X} y={want_y} "
    passed = any(l.startswith(expected) and l.endswith("mismatched=0") for l in lines)
    print(f"{'PASS' if passed else 'FAIL'} {name}: want A=${want_a:02X} Y={want_y}")
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
    disk = arguments.disk.resolve()
    side = side_a(disk.read_bytes())
    boot_id, files = disk_files(side)
    disk_id = side[15:25]
    # The largest program file the boot does not load: what games load later.
    later = [f for f in files if f.kind == 0 and f.address >= 0x0200 and f.file_id > boot_id]
    program = max(later or [f for f in files if f.kind == 0], key=lambda f: len(f.data)).file_id
    character = [f.file_id for f in files if f.kind == 1][-1]
    wrong = bytes([disk_id[0], disk_id[1] ^ 0xFF]) + disk_id[2:]
    last_wrong = disk_id[:9] + bytes([disk_id[9] ^ 0x01])
    mame = arguments.mame.resolve()
    results = [
        run(mame, bios, disk, f"one program file (ID ${program:02X})", disk_id, [program], 0),
        run(mame, bios, disk, f"character and program files (IDs ${character:02X}, ${program:02X})",
            b"\xff" * 10, [character, program], 0),
        run(mame, bios, disk, "a disk ID with another game name", wrong, [program], 0x05),
        run(mame, bios, disk, "a disk ID with another last byte", last_wrong, [program], 0x10),
        run(mame, bios, disk, "one byte read wrong in the first attempt",
            disk_id, [program], 0, glitch=True),
    ]
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
