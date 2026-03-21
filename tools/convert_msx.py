#!/usr/bin/env python3
"""
Batch-convert all VGZ files in a directory to 8.3 MSX-DOS filenames (*.MPS).

Output name: first 6 alphanumeric chars of the title (uppercased) + 2-digit index
Example: "01 Usas [Mohenjo daro].vgz" -> USASMO01.MPS

Also writes <out_dir>/songs.json mapping MPS filename -> display name,
used by build_msx_rom.py to generate the ROM menu.

Usage:
    python convert_msx.py <vgz_dir> <out_dir> [50|60]
"""

import json
import re
import sys
from pathlib import Path

import vgz2mpsg


def make_mps_name(stem: str, index: int) -> str:
    title = re.sub(r"^\d+\s*", "", stem)
    suffix = re.sub(r"[^A-Za-z0-9]", "", title)[:6].upper()
    return f"{index:02d}{suffix}.MPS"


def display_name(stem: str) -> str:
    """Human-readable title from VGZ filename stem.

    "01 Usas [Mohenjo daro]" -> "Mohenjo daro"
    "03 Some Song"           -> "Some Song"
    """
    m = re.search(r'\[([^\]]+)\]', stem)
    if m:
        return m.group(1)
    return re.sub(r'^\d+\s*', '', stem).strip()


def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <vgz_dir> <out_dir> [50|60]")
        sys.exit(1)

    vgz_dir = Path(sys.argv[1])
    out_dir = Path(sys.argv[2])
    fps = int(sys.argv[3]) if len(sys.argv) >= 4 else 60

    out_dir.mkdir(parents=True, exist_ok=True)

    vgz_files = sorted(vgz_dir.glob("*.vgz"))
    if not vgz_files:
        print(f"No .vgz files found in {vgz_dir}")
        sys.exit(1)

    metadata = {}
    for i, vgz_path in enumerate(vgz_files, start=1):
        out_name = make_mps_name(vgz_path.stem, i)
        out_path = out_dir / out_name

        vgm = vgz2mpsg.read_input(str(vgz_path))
        mpsg, loop = vgz2mpsg.convert(vgm, fps)

        out_path.write_bytes(mpsg)
        dname = display_name(vgz_path.stem)
        metadata[out_name] = dname
        print(f"Converted: {vgz_path.name} -> {out_name}  ({len(mpsg)} bytes, loop={loop})")

    songs_json = out_dir / "songs.json"
    songs_json.write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Metadata:  {songs_json}")


if __name__ == "__main__":
    main()
