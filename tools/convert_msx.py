#!/usr/bin/env python3
"""
Batch-convert all VGZ files in a directory to 8.3 MSX-DOS filenames (*.MPS).

Output name: first 6 alphanumeric chars of the title (uppercased) + 2-digit index
Example: "01 Usas [Mohenjo daro].vgz" -> USASMO01.MPS

Usage:
    python convert_msx.py <vgz_dir> <out_dir> [50|60]
"""

import re
import sys
from pathlib import Path

import vgz2mpsg


def make_mps_name(stem: str, index: int) -> str:
    # Strip leading digits and spaces: "01 Usas [...]" -> "Usas [...]"
    title = re.sub(r"^\d+\s*", "", stem)
    # Keep alphanumeric only, uppercase, max 6 chars
    prefix = re.sub(r"[^A-Za-z0-9]", "", title)[:6].upper()
    return f"{prefix}{index:02d}.MPS"


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

    for i, vgz_path in enumerate(vgz_files, start=1):
        out_name = make_mps_name(vgz_path.stem, i)
        out_path = out_dir / out_name

        vgm = vgz2mpsg.read_input(str(vgz_path))
        mpsg, loop = vgz2mpsg.convert(vgm, fps)

        out_path.write_bytes(mpsg)
        print(f"Converted: {vgz_path.name} -> {out_name}  ({len(mpsg)} bytes, loop={loop})")


if __name__ == "__main__":
    main()
