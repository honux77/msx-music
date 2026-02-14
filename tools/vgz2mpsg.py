#!/usr/bin/env python3
"""
VGZ/VGM to MPSG converter for MSX-DOS PSG player.

MPSG format:
  Header (16 bytes)
    0-3   : magic 'MPSG'
    4-5   : data length (little-endian)
    6-7   : loop offset in data stream (little-endian, 0 = no loop)
    8-15  : reserved

  Stream
    00-0D vv : AY register write
    80-FD    : wait 1-126 frames
    FF ll hh : extended wait (16-bit frame count)
    FD       : loop marker
    FE       : end
"""

import gzip
import struct
import sys
from pathlib import Path

CMD_AY8910 = 0xA0
CMD_WAIT_N = 0x61
CMD_WAIT_60HZ = 0x62
CMD_WAIT_50HZ = 0x63
CMD_END = 0x66

MPSG_END = 0xFE
MPSG_LOOP = 0xFD
MPSG_WAIT_EXT = 0xFF


def read_input(path: str) -> bytes:
    if path.lower().endswith((".vgz", ".gz")):
        with gzip.open(path, "rb") as f:
            return f.read()
    with open(path, "rb") as f:
        return f.read()


def parse_header(vgm: bytes):
    if vgm[0:4] != b"Vgm ":
        raise ValueError("Not a valid VGM file")

    version = struct.unpack_from("<I", vgm, 0x08)[0]
    loop_raw = struct.unpack_from("<I", vgm, 0x1C)[0]
    loop_offset = (0x1C + loop_raw) if loop_raw else 0

    if version >= 0x150:
        data_raw = struct.unpack_from("<I", vgm, 0x34)[0]
        data_offset = 0x34 + data_raw if data_raw else 0x40
    else:
        data_offset = 0x40

    return data_offset, loop_offset


def convert(vgm: bytes, fps: int):
    if fps not in (50, 60):
        raise ValueError("fps must be 50 or 60")

    samples_per_frame = 882 if fps == 50 else 735
    data_offset, loop_offset = parse_header(vgm)

    out = bytearray()
    pending_samples = 0
    pos = data_offset
    stream_loop_offset = 0

    def flush_wait():
        nonlocal pending_samples
        if pending_samples == 0:
            return

        frames = pending_samples // samples_per_frame
        pending_samples %= samples_per_frame

        while frames > 0:
            chunk = min(frames, 65535)
            if chunk <= 126:
                out.append(0x7F + chunk)
            else:
                out.append(MPSG_WAIT_EXT)
                out.append(chunk & 0xFF)
                out.append((chunk >> 8) & 0xFF)
            frames -= chunk

    while pos < len(vgm):
        if loop_offset and pos == loop_offset and stream_loop_offset == 0:
            flush_wait()
            stream_loop_offset = len(out)
            out.append(MPSG_LOOP)

        cmd = vgm[pos]

        if cmd == CMD_AY8910:
            if pos + 2 >= len(vgm):
                break
            reg = vgm[pos + 1]
            val = vgm[pos + 2]
            if reg <= 0x0D:
                flush_wait()
                out.append(reg)
                out.append(val)
            pos += 3
        elif cmd == CMD_WAIT_N:
            if pos + 2 >= len(vgm):
                break
            pending_samples += struct.unpack_from("<H", vgm, pos + 1)[0]
            pos += 3
        elif cmd == CMD_WAIT_60HZ:
            pending_samples += 735
            pos += 1
        elif cmd == CMD_WAIT_50HZ:
            pending_samples += 882
            pos += 1
        elif cmd == CMD_END:
            flush_wait()
            out.append(MPSG_END)
            break
        elif 0x70 <= cmd <= 0x7F:
            pending_samples += (cmd & 0x0F) + 1
            pos += 1
        elif 0x80 <= cmd <= 0x8F:
            pending_samples += cmd & 0x0F
            pos += 1
        elif cmd in (0x30, 0x3F, 0x4F, 0x50, 0xB0, 0xB1, 0xB2):
            pos += 2
        elif cmd in (
            0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59,
            0x5A, 0x5B, 0x5C, 0x5D, 0x5E, 0x5F, 0xA1, 0xA2, 0xA3,
            0xB3, 0xB4, 0xB5, 0xB6, 0xB7, 0xB8, 0xB9, 0xBA, 0xBB,
            0xBC, 0xBD, 0xBE, 0xBF,
        ):
            pos += 3
        elif cmd in (0xC0, 0xC1, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7, 0xC8):
            pos += 4
        elif cmd == 0x67:
            if pos + 6 < len(vgm):
                block_size = struct.unpack_from("<I", vgm, pos + 3)[0]
                pos += 7 + block_size
            else:
                pos += 1
        else:
            pos += 1

    if not out or out[-1] != MPSG_END:
        out.append(MPSG_END)

    header = bytearray(16)
    header[0:4] = b"MPSG"
    header[4] = len(out) & 0xFF
    header[5] = (len(out) >> 8) & 0xFF
    header[6] = stream_loop_offset & 0xFF
    header[7] = (stream_loop_offset >> 8) & 0xFF

    return bytes(header) + bytes(out), stream_loop_offset


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <input.vgz|input.vgm> [output.mpsg] [50|60]")
        sys.exit(1)

    input_path = sys.argv[1]
    output_path = sys.argv[2] if len(sys.argv) >= 3 else f"{Path(input_path).stem}.mpsg"
    fps = int(sys.argv[3]) if len(sys.argv) >= 4 else 60

    vgm = read_input(input_path)
    mpsg, loop = convert(vgm, fps)

    with open(output_path, "wb") as f:
        f.write(mpsg)

    print(f"Converted: {input_path} -> {output_path}")
    print(f"Output bytes: {len(mpsg)}")
    print(f"Loop offset: {loop}")


if __name__ == "__main__":
    main()
