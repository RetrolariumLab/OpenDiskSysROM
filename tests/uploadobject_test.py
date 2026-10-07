"""Puts objects into the OAM buffer in MAME through UploadObject.

    python tests/uploadobject_test.py --mame path/to/mame.exe disk.fds

The disk boots as in boot_test.py and, as in loadfiles_test.py, a program
written to RAM runs from the game's first NMI vector with NMIs off, so
the game no longer touches $0200-$02FF. A Lua script fills that page with
$AA, the program calls UploadObject for each object below, and the script
compares the page with what the documented object structure describes:

  - 2 x 3 tiles numbered from $40, frame 2, palette 1;
  - 3 x 2 tiles from a table, frame 1, flipped horizontally;
  - the same flipped both ways, frame 0;
  - 4 x 4 tiles from a table, frame 20, past its first 256 bytes;
  - a hidden object, whose sprites only move below the screen;
  - a skipped one, which leaves its OAM entries as they were.
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
OBJECTS = 0x0480    # 16 bytes each
TABLE_SMALL = 0x0500
TABLE_LARGE = 0x0600
DONE = 0x04FF
UPLOAD_OBJECT = 0xEC22
FILL = 0xAA


def word(value: int) -> bytes:
    return value.to_bytes(2, "little")


def structure(render: int, y: int, x: int, frame: int, tiles: int, flags: int, palette: int,
              width: int, height: int, entry: int) -> bytes:
    return bytes([render, y, 0x80, x, 0x40, frame, tiles >> 8, tiles & 0xFF, flags, palette,
                  height << 4 | width, entry])


SMALL = bytes(0x90 + i * 3 for i in range(12))
LARGE = bytes((i ^ (i >> 8) * 0x35) & 0xFF for i in range(0x200))
CASES = [
    structure(0x00, 0x50, 0x60, 2, 0x0040, 0x00, 1, 2, 3, 0),
    structure(0x00, 0x20, 0x30, 1, TABLE_SMALL, 0x10, 2, 3, 2, 8),
    structure(0x00, 0x90, 0xA0, 0, TABLE_SMALL, 0x11, 3, 3, 2, 16),
    structure(0x00, 0x10, 0x08, 20, TABLE_LARGE, 0x00, 0, 4, 4, 24),
    structure(0x80, 0x40, 0x40, 0, 0x0001, 0x00, 0, 2, 2, 44),
    structure(0x01, 0x40, 0x40, 0, 0x0001, 0x00, 0, 2, 2, 52),
]


def memory(address: int) -> int:
    for base, data in ((TABLE_SMALL, SMALL), (TABLE_LARGE, LARGE)):
        if base <= address < base + len(data):
            return data[address - base]
    raise ValueError(f"no test data at ${address:04X}")


def expected() -> bytes:
    oam = bytearray([FILL] * 256)
    for item in CASES:
        render, y, x, frame = item[0], item[1], item[3], item[5]
        tiles, flags, palette = item[6] << 8 | item[7], item[8], item[9]
        width, height, entry = item[10] & 0x0F, item[10] >> 4, item[11]
        if render & 0x80:
            for n in range(width * height):
                oam[(entry * 4 + n * 4) & 0xFF] = 0xF8
            continue
        if render:
            continue
        attributes = palette & 3 | (0x40 if flags & 0x10 else 0) | (0x80 if flags & 0x01 else 0)
        first = frame * width * height
        n = 0
        for column in range(width):
            for row in range(height):
                tile = (tiles + first + n) & 0xFF if tiles < 0x100 else memory(tiles + first + n)
                left = width - 1 - column if flags & 0x10 else column
                top = height - 1 - row if flags & 0x01 else row
                at = (entry * 4 + n * 4) & 0xFF
                oam[at:at + 4] = bytes([(y + top * 8) & 0xFF, tile, attributes, (x + left * 8) & 0xFF])
                n += 1
    return bytes(oam)


def stub() -> bytes:
    code = bytearray(b"\xA9\x00\x8D\x00\x20")                  # no NMIs
    for index in range(len(CASES)):
        address = OBJECTS + index * 16
        code += bytes([0xA9, address & 0xFF, 0x85, 0x00])      # LDA #< / STA $00
        code += bytes([0xA9, address >> 8, 0x85, 0x01])        # LDA #> / STA $01
        code += bytes([0x20]) + word(UPLOAD_OBJECT)            # JSR UploadObject
    code += bytes([0xA9, 0x5A, 0x8D]) + word(DONE)
    code += bytes([0x4C]) + word(STUB + len(code))
    return bytes(code)


def lua() -> str:
    pokes = {STUB: stub(), TABLE_SMALL: SMALL, TABLE_LARGE: LARGE}
    for index, item in enumerate(CASES):
        pokes[OBJECTS + index * 16] = item
    lines = [
        "local cpu = manager.machine.devices[':maincpu']",
        "local p = cpu.spaces['program']",
        "local booted, started, frame = nil, nil, 0",
        "local function poke(a, hex) for i = 0, #hex / 2 - 1 do p:write_u8(a + i, tonumber(hex:sub(i * 2 + 1, i * 2 + 2), 16)) end end",
        "tap = p:install_write_tap(0x0102, 0x0102, 'boot', function(o, d, m) if d == 0x35 and booted == nil then booted = frame end return d end)",
        "emu.register_frame_done(function()",
        "  frame = frame + 1",
        "  if booted ~= nil and started == nil and frame >= booted + 120 then",
    ]
    for address, data in pokes.items():
        lines.append(f"    poke({address}, '{data.hex()}')")
    lines += [
        f"    for i = 0, 255 do p:write_u8(0x0200 + i, {FILL}) end",
        f"    p:write_u8({DONE}, 0)",
        f"    p:write_u8(0xDFF6, {STUB & 0xFF}); p:write_u8(0xDFF7, {STUB >> 8}); p:write_u8(0x0100, 0x40)",
        "    started = frame",
        f"  elseif started ~= nil and p:read_u8({DONE}) == 0x5A then",
        "    local s = 'OAM '",
        "    for i = 0, 255 do s = s .. string.format('%02X', p:read_u8(0x0200 + i)) end",
        "    print(s)",
        "    manager.machine:exit()",
        "  elseif frame >= 60 * 120 then",
        "    print(string.format('TIMEOUT pc=%04X', cpu.state['PC'].value)); manager.machine:exit()",
        "  end",
        "end)",
    ]
    return "\n".join(lines) + "\n"


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
    lines = [l for l in result.stdout.splitlines() if l.startswith(("OAM", "TIMEOUT"))]
    if not lines or not lines[0].startswith("OAM"):
        print(f"FAIL {lines[0] if lines else 'no result'}")
        return 1
    oam = bytes.fromhex(lines[0][4:])
    want = expected()
    bad = [n for n in range(64) if oam[n * 4:n * 4 + 4] != want[n * 4:n * 4 + 4]]
    for n in bad[:8]:
        print(f"  BAD entry {n}: {oam[n * 4:n * 4 + 4].hex()} instead of {want[n * 4:n * 4 + 4].hex()}")
    print(f"{'PASS' if not bad else 'FAIL'} {len(CASES)} objects, {64 - len(bad)} of 64 OAM entries as expected")
    return 0 if not bad else 1


if __name__ == "__main__":
    sys.exit(main())
