"""Checks the boot loader's error screen and its retry in MAME.

    python tests/boot_error_test.py --mame path/to/mame.exe disk.fds

MAME starts with a copy of the disk whose *NINTENDO-HVC* signature is
broken, so the boot load fails with error $21. A Lua script waits for the
boot screen to show DISK ERROR 21 in the nametable, then puts the intact
disk in the drive. The loader must try again by itself after its pause and
start the game (its write of $35 to $0102).
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

SIGNATURE = b"*NINTENDO-HVC*"
MESSAGE = 0x2000 + 14 * 32 + 10   # where BootScreenMessage puts DISK ERROR
# "DISK ERROR 21" in font tiles: 0-9 are digits, 10-35 letters, 36 space.
TILES = bytes([13, 18, 28, 20, 36, 14, 27, 27, 24, 27, 36, 2, 1])


def lua(good: Path) -> str:
    return f"""
local cpu = manager.machine.devices[':maincpu']
local program = cpu.spaces['program']
local video = manager.machine.devices[':ppu'].spaces['videoram']
local tiles = '{TILES.hex()}'
local frame, shown, booted = 0, nil, nil
local function message()
  for i = 0, #tiles / 2 - 1 do
    if video:read_u8({MESSAGE} + i) ~= tonumber(tiles:sub(i * 2 + 1, i * 2 + 2), 16) then return false end
  end
  return true
end
tap = program:install_write_tap(0x0102, 0x0102, 'boot', function(offset, data, mask)
  if data == 0x35 and booted == nil then booted = frame end
  return data
end)
emu.register_frame_done(function()
  frame = frame + 1
  if shown == nil and message() then
    shown = frame
    print(string.format('ERROR SHOWN frame=%d', frame))
    for _, image in pairs(manager.machine.images) do
      if image.exists then image:load([==[{good}]==]) end
    end
  end
  if booted ~= nil then
    print(string.format('BOOT frame=%d after=%d', booted, booted - shown))
    manager.machine:exit()
  elseif frame >= 60 * 90 then
    print(string.format('TIMEOUT pc=%04X shown=%s', cpu.state['PC'].value, tostring(shown)))
    manager.machine:exit()
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
    image = arguments.disk.read_bytes()
    at = image.find(SIGNATURE)
    if at < 0:
        sys.exit("the disk has no *NINTENDO-HVC* signature")
    broken = bytearray(image)
    broken[at] = ord("#")
    mame = arguments.mame.resolve()
    with tempfile.TemporaryDirectory(prefix="opendisksys-") as temp:
        work = Path(temp)
        (work / "roms" / "fds").mkdir(parents=True)
        shutil.copyfile(bios, work / "roms" / "fds" / "rp2c33a-01a.bin")
        bad = work / "bad.fds"
        bad.write_bytes(broken)
        good = work / "good.fds"
        shutil.copyfile(arguments.disk, good)
        (work / "test.lua").write_text(lua(good), encoding="ascii")
        result = subprocess.run(
            [str(mame), "fds", "-flop", str(bad), "-rompath", str(work / "roms"),
             "-cfg_directory", str(work / "cfg"), "-nvram_directory", str(work / "nvram"),
             "-video", "none", "-sound", "none", "-nothrottle", "-skip_gameinfo",
             "-autoboot_delay", "0", "-autoboot_script", str(work / "test.lua")],
            cwd=mame.parent, capture_output=True, text=True, timeout=600, stdin=subprocess.DEVNULL)
    lines = [l for l in result.stdout.splitlines() if l.startswith(("ERROR SHOWN", "BOOT", "TIMEOUT"))]
    for line in lines:
        print(f"  {line}")
    passed = any(l.startswith("ERROR SHOWN") for l in lines) and any(l.startswith("BOOT") for l in lines)
    print(f"{'PASS' if passed else 'FAIL'} {arguments.disk.name}: DISK ERROR 21, then a retry boots the intact disk")
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
