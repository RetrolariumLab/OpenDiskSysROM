"""Writes to a disk in MAME through the BIOS and reads it back.

    python tests/writefile_test.py --mame path/to/mame.exe disk.fds

As in loadfiles_test.py, a program written to RAM runs from the game's
first NMI vector once the disk has booted. It calls, in order:

  1. WriteFile, rewriting the last file of the disk at its place with new
     data (its header otherwise as it was);
  2. LoadFiles of that file, which must bring the new data;
  3. AppendFile of a new 32-byte file after the last one;
  4. LoadFiles of the new file;
  5. GetDiskInfo, called with A=$FF, which must list the disk ID, every
     file and the new one, and the disk size (data plus 261 per file);
  6. SetFileCount to the old count, hiding the new file;
  7. LoadFiles of the new file, which must find nothing;
  8. AdjustFileCount by one, hiding the last original file too;
  9. GetDiskInfo, which must show one file fewer than the disk had;
 10. CheckFileCount above the count, which must fail with $31;
 11. AppendFile of a 36 KiB file, more than the disk has left, which must
     run off the end of the disk and fail rather than hang: with $29, or
     with $28 when the second attempt reads into what the first left.

MAME keeps what is written in memory only, so the disk image file is
never changed; the test works on a copy anyway.
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

STUB = 0x0400
DISK_ID = 0x0500
LIST_LAST = 0x050A
LIST_NEW = 0x050C
HEADER_LAST = 0x0510
HEADER_NEW = 0x0530
SOURCE_LAST = 0x0550
SOURCE_NEW = 0x0560
RESULTS = 0x0590
DONE = 0x05AF
HEADER_BIG = 0x05B0
INFO_1 = 0x0600
INFO_2 = 0x0680
NEW_ADDRESS = 0x0700
NEW_ID = 0x50
NEW_NAME = b"OPENDISK"
NEW_DATA = bytes((i * 7 + 3) & 0xFF for i in range(32))
BIG_SIZE = 0x9000  # more than any side has free after a game's files

LOAD_FILES, APPEND_FILE, WRITE_FILE = 0xE1F8, 0xE237, 0xE239
CHECK_FILE_COUNT, ADJUST_FILE_COUNT, SET_FILE_COUNT, GET_DISK_INFO = 0xE2B7, 0xE2BB, 0xE305, 0xE32A


def word(value: int) -> bytes:
    return value.to_bytes(2, "little")


def program(calls: list[tuple[int, int, list[int]]], zero: list[tuple[int, int]]) -> bytes:
    code = bytearray(b"\xA9\x00\x8D\x00\x20")                 # no NMIs
    for address, length in zero:                              # clear where loads go
        code += bytes([0xA2, length - 1])                     # LDX #length-1
        code += bytes([0x9D]) + word(address)                 # STA address,X (A = 0)
        code += bytes([0xCA, 0x10, 0xFA])                     # DEX / BPL back
    for index, (routine, a, pointers) in enumerate(calls):
        code += bytes([0xA9, a, 0x20]) + word(routine)        # LDA #a / JSR routine
        for pointer in pointers:
            code += word(pointer)
        code += bytes([0x8D]) + word(RESULTS + index * 2)     # STA result
        code += bytes([0x8C]) + word(RESULTS + index * 2 + 1)  # STY result+1
    code += bytes([0xA9, 0x5A, 0x8D]) + word(DONE)
    code += bytes([0x4C]) + word(STUB + len(code))
    return bytes(code)


def header(file_id: int, name: bytes, address: int, data_size: int, source: int) -> bytes:
    return bytes([file_id]) + name + word(address) + word(data_size) + b"\x00" + word(source) + b"\x00"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("disk", type=Path)
    parser.add_argument("--mame", type=Path, default=os.environ.get("MAME"))
    parser.add_argument("--asm6f", default=os.environ.get("ASM6F", "asm6f"))
    arguments = parser.parse_args()
    if arguments.mame is None or not arguments.mame.is_file():
        parser.error("give MAME with --mame or the MAME environment variable")
    bios = assemble(arguments.asm6f)
    side = side_a(arguments.disk.read_bytes())
    _boot, files = disk_files(side)
    disk_id = side[15:25]
    last = files[-1]
    if last.kind != 0 or last.address < 0x0200:
        sys.exit("the last file of the disk must be a program file loaded above $0200")
    new_last = bytes((b ^ 0xA5) for b in last.data)
    count = len(files)

    calls = [
        (WRITE_FILE, count - 1, [DISK_ID, HEADER_LAST]),
        (LOAD_FILES, 0, [DISK_ID, LIST_LAST]),
        (APPEND_FILE, 0, [DISK_ID, HEADER_NEW]),
        (LOAD_FILES, 0, [DISK_ID, LIST_NEW]),
        (GET_DISK_INFO, 0xFF, [INFO_1]),  # A is not a parameter: $FF must not matter
        (SET_FILE_COUNT, count, [DISK_ID]),
        (LOAD_FILES, 0, [DISK_ID, LIST_NEW]),
        (ADJUST_FILE_COUNT, 1, [DISK_ID]),
        (GET_DISK_INFO, 0, [INFO_2]),
        (CHECK_FILE_COUNT, count, [DISK_ID]),
        (APPEND_FILE, 0, [DISK_ID, HEADER_BIG]),
    ]
    want = [(0, None), (0, 1), (0, None), (0, 1), (0, None), (0, None), (0, 0), (0, None), (0, None), (0x31, None), ({0x28, 0x29}, None)]
    if len(last.data) > 128 or SOURCE_LAST + len(last.data) > SOURCE_NEW:
        sys.exit("the last file is too large for this test")
    code = program(calls, [(last.address, len(last.data)), (NEW_ADDRESS, len(NEW_DATA))])
    pokes = {
        STUB: code,
        DISK_ID: disk_id,
        LIST_LAST: bytes([last.file_id, 0xFF]),
        LIST_NEW: bytes([NEW_ID, 0xFF]),
        HEADER_LAST: header(last.file_id, last.name, last.address, len(new_last), SOURCE_LAST),
        HEADER_NEW: header(NEW_ID, NEW_NAME, NEW_ADDRESS, len(NEW_DATA), SOURCE_NEW),
        HEADER_BIG: header(NEW_ID + 1, b"TOOLARGE", 0x6000, BIG_SIZE, 0x8000),
        SOURCE_LAST: new_last,
        SOURCE_NEW: NEW_DATA,
    }
    # The disk size counts 261 bytes for each file on top of its data.
    total = sum(len(f.data) for f in files) + len(NEW_DATA) + 261 * (count + 1)
    info_1 = disk_id + bytes([count + 1])
    for item in files:
        info_1 += bytes([item.file_id]) + item.name
    info_1 += bytes([NEW_ID]) + NEW_NAME + total.to_bytes(2, "big")
    total_2 = sum(len(f.data) for f in files[:-1]) + 261 * (count - 1)
    info_2 = disk_id + bytes([count - 1])
    for item in files[:-1]:
        info_2 += bytes([item.file_id]) + item.name
    info_2 += total_2.to_bytes(2, "big")
    checks = [(last.address, new_last), (NEW_ADDRESS, NEW_DATA), (INFO_1, info_1), (INFO_2, info_2)]

    lua = ["local cpu = manager.machine.devices[':maincpu']",
           "local p = cpu.spaces['program']",
           "local booted, started, frame = nil, nil, 0",
           "local function poke(a, hex) for i = 0, #hex / 2 - 1 do p:write_u8(a + i, tonumber(hex:sub(i * 2 + 1, i * 2 + 2), 16)) end end",
           "local function same(a, hex) local bad = 0 for i = 0, #hex / 2 - 1 do if p:read_u8(a + i) ~= tonumber(hex:sub(i * 2 + 1, i * 2 + 2), 16) then bad = bad + 1 end end return bad end",
           "tap = p:install_write_tap(0x0102, 0x0102, 'boot', function(o, d, m) if d == 0x35 and booted == nil then booted = frame end return d end)",
           "emu.register_frame_done(function()",
           "  frame = frame + 1",
           "  if booted ~= nil and started == nil and frame >= booted + 120 then"]
    for address, data in pokes.items():
        lua.append(f"    poke({address}, '{data.hex()}')")
    lua += [f"    p:write_u8({DONE}, 0)",
            f"    p:write_u8(0xDFF6, {STUB & 0xFF}); p:write_u8(0xDFF7, {STUB >> 8}); p:write_u8(0x0100, 0x40)",
            "    started = frame",
            f"  elseif started ~= nil and p:read_u8({DONE}) == 0x5A then"]
    for index in range(len(calls)):
        lua.append(f"    print(string.format('CALL {index + 1} a=%02X y=%d', p:read_u8({RESULTS + index * 2}), p:read_u8({RESULTS + index * 2 + 1})))")
    for address, data in checks:
        lua.append(f"    print(string.format('MEMORY ${address:04X} mismatched=%d of {len(data)}', same({address}, '{data.hex()}')))")
    lua += ["    print(string.format('FRAMES %d', frame - started))",
            "    manager.machine:exit()",
            "  elseif frame >= 60 * 300 then",
            "    print(string.format('TIMEOUT pc=%04X', cpu.state['PC'].value)); manager.machine:exit()",
            "  end",
            "end)"]

    with tempfile.TemporaryDirectory(prefix="opendisksys-") as temp:
        work = Path(temp)
        (work / "roms" / "fds").mkdir(parents=True)
        shutil.copyfile(bios, work / "roms" / "fds" / "rp2c33a-01a.bin")
        disk = work / "disk.fds"
        shutil.copyfile(arguments.disk, disk)
        (work / "test.lua").write_text("\n".join(lua) + "\n", encoding="ascii")
        mame = arguments.mame.resolve()
        result = subprocess.run(
            [str(mame), "fds", "-flop", str(disk), "-rompath", str(work / "roms"),
             "-cfg_directory", str(work / "cfg"), "-nvram_directory", str(work / "nvram"),
             "-video", "none", "-sound", "none", "-nothrottle", "-skip_gameinfo",
             "-autoboot_delay", "0", "-autoboot_script", str(work / "test.lua")],
            cwd=mame.parent, capture_output=True, text=True, timeout=900, stdin=subprocess.DEVNULL)
    lines = [l for l in result.stdout.splitlines() if l.startswith(("CALL", "MEMORY", "FRAMES", "TIMEOUT"))]
    passed = bool(lines) and not any(l.startswith("TIMEOUT") for l in lines)
    names = ["WriteFile", "LoadFiles (rewritten file)", "AppendFile", "LoadFiles (new file)", "GetDiskInfo",
             "SetFileCount", "LoadFiles (hidden file)", "AdjustFileCount", "GetDiskInfo", "CheckFileCount",
             "AppendFile (past the end of the disk)"]
    for line in lines:
        ok = True
        if line.startswith("CALL"):
            index = int(line.split()[1]) - 1
            a = int(line.split("a=")[1].split()[0], 16)
            y = int(line.split("y=")[1])
            want_a, want_y = want[index]
            ok = (a in want_a if isinstance(want_a, set) else a == want_a) and (want_y is None or y == want_y)
            line = f"{line}  {names[index]}"
        elif line.startswith("MEMORY"):
            ok = "mismatched=0 " in line
        passed = passed and ok
        print(f"  {'ok ' if ok else 'BAD'} {line}")
    print(f"{'PASS' if passed else 'FAIL'} {arguments.disk.name}: writes, counts and disk info")
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
