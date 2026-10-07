"""Boots Famicom Disk System images in MAME with the BIOS built from this
repository and checks that the boot files arrived where their headers say.

    python tests/boot_test.py --mame path/to/mame.exe disk1.fds [disk2.fds ...]

The BIOS is assembled with asm6f (--asm6f, the ASM6F environment variable,
or asm6f on PATH) into build/opendisksys.bin and handed to MAME's "fds"
system as rp2c33a-01a.bin from a private ROM path. MAME warns that the
checksum is not Nintendo's; headless runs do not stop for that warning.

For each disk the test reads side A's blocks, works out which files the
boot loader must load (every file whose ID is not above the disk's boot
file code), and gives a Lua script their expected contents. The script
compares CPU and PPU memory the moment the BIOS hands over to the game
(its write of $35 to $0102), so the game has not touched anything yet.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SIDE = 65500


@dataclass
class DiskFile:
    number: int
    file_id: int
    name: bytes
    address: int
    kind: int  # 0 program, 1 character, 2 nametable
    data: bytes


def side_a(image: bytes) -> bytes:
    """The first side of an .fds image, with or without its 16-byte header."""
    offset = 16 if image[:4] == b"FDS\x1a" else 0
    side = image[offset:offset + SIDE]
    if len(side) != SIDE or side[0] != 1 or side[1:15] != b"*NINTENDO-HVC*":
        raise ValueError("not a Famicom Disk System side")
    return side


def disk_files(side: bytes) -> tuple[int, list[DiskFile]]:
    """The boot file code and every file of a side, in disk order."""
    boot_id = side[25]
    if side[56] != 2:
        raise ValueError("no file amount block")
    count = side[57]
    position = 58
    files = []
    for _ in range(count):
        header = side[position:position + 16]
        if header[0] != 3:
            raise ValueError(f"no file header block at {position}")
        size = int.from_bytes(header[13:15], "little")
        if side[position + 16] != 4:
            raise ValueError(f"no file data block at {position + 16}")
        data = side[position + 17:position + 17 + size]
        files.append(DiskFile(header[1], header[2], header[3:11],
                              int.from_bytes(header[11:13], "little"), header[15], data))
        position += 17 + size
    return boot_id, files


def lua_script(checks: list[tuple[str, int, bytes]], frames: int) -> str:
    """A script that compares memory when $0102 becomes $35, then lets the
    game run for `frames` frames and reports."""
    lines = [
        "local cpu = manager.machine.devices[':maincpu']",
        "local program = cpu.spaces['program']",
        "local video = manager.machine.devices[':ppu'].spaces['videoram']",
        "local checks = {",
    ]
    for space, address, data in checks:
        lines.append(f"  {{'{space}', {address}, '{data.hex()}'}},")
    lines += [
        "}",
        "local booted = nil",
        "local frame = 0",
        "local function compare()",
        "  local bad, total = 0, 0",
        "  for _, check in ipairs(checks) do",
        "    local space = check[1] == 'cpu' and program or video",
        "    local hex = check[3]",
        "    for i = 0, #hex / 2 - 1 do",
        "      local want = tonumber(hex:sub(i * 2 + 1, i * 2 + 2), 16)",
        "      local got = space:read_u8(check[2] + i)",
        "      total = total + 1",
        "      if got ~= want then",
        "        if bad < 8 then",
        "          print(string.format('MISMATCH %s $%04X: want %02X got %02X', check[1], check[2] + i, want, got))",
        "        end",
        "        bad = bad + 1",
        "      end",
        "    end",
        "  end",
        "  return bad, total",
        "end",
        "tap = program:install_write_tap(0x0102, 0x0102, 'boot', function(offset, data, mask)",
        "  if data == 0x35 and booted == nil then",
        "    local bad, total = compare()",
        "    booted = frame",
        "    print(string.format('BOOT frame=%d bytes=%d mismatched=%d', frame, total, bad))",
        "  end",
        "  return data",
        "end)",
        "emu.register_frame_done(function()",
        "  frame = frame + 1",
        "  if (booted ~= nil and frame >= booted + 120) or frame >= " + str(frames) + " then",
        "    print(string.format('END frame=%d pc=%04X booted=%s $0102=%02X $0103=%02X', frame,",
        "      cpu.state['PC'].value, tostring(booted), program:read_u8(0x0102), program:read_u8(0x0103)))",
        "    manager.machine:exit()",
        "  end",
        "end)",
    ]
    return "\n".join(lines) + "\n"


def assemble(asm6f: str) -> Path:
    build = ROOT / "build"
    build.mkdir(exist_ok=True)
    output = build / "opendisksys.bin"
    result = subprocess.run([asm6f, "freedisksys.asm", str(output)], cwd=ROOT,
                            capture_output=True, text=True)
    if result.returncode != 0 or not output.is_file():
        sys.exit(f"asm6f failed:\n{result.stdout}{result.stderr}")
    if output.stat().st_size != 0x2000:
        sys.exit(f"the BIOS is {output.stat().st_size} bytes, not 8192")
    return output


def run_disk(mame: Path, bios: Path, disk: Path, frames: int) -> bool:
    side = side_a(disk.read_bytes())
    boot_id, files = disk_files(side)
    checks = []
    for item in files:
        if item.file_id > boot_id:
            continue
        if item.kind == 0:
            if item.address < 0x0200:
                continue  # the BIOS does not load into zero page or the stack
            checks.append(("cpu", item.address, item.data))
        else:
            checks.append(("ppu", item.address, item.data))
    with tempfile.TemporaryDirectory(prefix="opendisksys-") as temp:
        work = Path(temp)
        (work / "roms" / "fds").mkdir(parents=True)
        shutil.copyfile(bios, work / "roms" / "fds" / "rp2c33a-01a.bin")
        script = work / "check.lua"
        script.write_text(lua_script(checks, frames), encoding="ascii")
        command = [str(mame), "fds", "-flop", str(disk), "-rompath", str(work / "roms"),
                   "-cfg_directory", str(work / "cfg"), "-nvram_directory", str(work / "nvram"),
                   "-video", "none", "-sound", "none", "-nothrottle", "-skip_gameinfo",
                   "-autoboot_delay", "0", "-autoboot_script", str(script)]
        result = subprocess.run(command, cwd=mame.parent, capture_output=True, text=True,
                                timeout=600, stdin=subprocess.DEVNULL)
    report = [line for line in result.stdout.splitlines() if line.startswith(("BOOT", "MISMATCH", "END"))]
    for line in report:
        print(f"  {line}")
    booted = any(line.startswith("BOOT") and line.endswith("mismatched=0") for line in report)
    loaded = sum(len(data) for _, _, data in checks)
    print(f"{'PASS' if booted else 'FAIL'} {disk.name}: boot file code ${boot_id:02X}, "
          f"{len(checks)} boot files, {loaded} bytes")
    return booted


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("disks", nargs="+", type=Path)
    parser.add_argument("--mame", type=Path, default=os.environ.get("MAME"))
    parser.add_argument("--asm6f", default=os.environ.get("ASM6F", "asm6f"))
    parser.add_argument("--frames", type=int, default=60 * 60,
                        help="frames to wait for the boot before giving up")
    arguments = parser.parse_args()
    if arguments.mame is None or not arguments.mame.is_file():
        parser.error("give MAME with --mame or the MAME environment variable")
    bios = assemble(arguments.asm6f)
    results = [run_disk(arguments.mame.resolve(), bios, disk.resolve(), arguments.frames)
               for disk in arguments.disks]
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
