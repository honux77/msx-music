#!/usr/bin/env python3
"""
MSX-DOS disk image builder (pure Python, replaces make_msx_disk.sh).
Copies files into a FAT12 floppy disk image without requiring mtools.

Usage:
    python make_msx_disk.py <base.dsk> <output.dsk> <file1> [file2 ...]
"""

import struct
import sys
from pathlib import Path


class Fat12Disk:
    """Minimal FAT12 disk image editor."""

    def __init__(self, image: bytearray):
        self.image = image
        bpb = image[0:62]
        self.bytes_per_sector   = struct.unpack_from("<H", bpb, 11)[0]
        self.sectors_per_cluster = bpb[13]
        self.reserved_sectors   = struct.unpack_from("<H", bpb, 14)[0]
        self.fat_count          = bpb[16]
        self.root_entry_count   = struct.unpack_from("<H", bpb, 17)[0]
        self.sectors_per_fat    = struct.unpack_from("<H", bpb, 22)[0]

        self.bps = self.bytes_per_sector
        self.spc = self.sectors_per_cluster

        self.fat_start   = self.reserved_sectors * self.bps
        self.root_start  = self.fat_start + self.fat_count * self.sectors_per_fat * self.bps
        self.data_start  = self.root_start + self.root_entry_count * 32
        # FAT12 cluster 2 = first data cluster
        self.total_clusters = (len(image) - self.data_start) // (self.spc * self.bps)

    # --- FAT12 access ---

    def _fat_offset(self, cluster: int):
        return self.fat_start + cluster * 3 // 2

    def get_fat(self, cluster: int) -> int:
        off = self._fat_offset(cluster)
        lo, hi = self.image[off], self.image[off + 1]
        word = lo | (hi << 8)
        return (word >> 4) if (cluster & 1) else (word & 0xFFF)

    def set_fat(self, cluster: int, value: int):
        for fat_n in range(self.fat_count):
            base = self.fat_start + fat_n * self.sectors_per_fat * self.bps
            off = base + cluster * 3 // 2
            lo, hi = self.image[off], self.image[off + 1]
            word = lo | (hi << 8)
            if cluster & 1:
                word = (word & 0x000F) | ((value & 0xFFF) << 4)
            else:
                word = (word & 0xF000) | (value & 0xFFF)
            self.image[off]     = word & 0xFF
            self.image[off + 1] = (word >> 8) & 0xFF

    def alloc_cluster(self) -> int:
        for c in range(2, self.total_clusters + 2):
            if self.get_fat(c) == 0:
                self.set_fat(c, 0xFFF)
                return c
        raise RuntimeError("Disk full: no free clusters")

    def cluster_offset(self, cluster: int) -> int:
        return self.data_start + (cluster - 2) * self.spc * self.bps

    # --- Root directory ---

    def find_root_slot(self) -> int:
        for i in range(self.root_entry_count):
            off = self.root_start + i * 32
            first = self.image[off]
            if first == 0x00 or first == 0xE5:
                return off
        raise RuntimeError("Root directory full")

    def find_existing(self, name83: bytes) -> int:
        """Return offset of existing entry, or -1."""
        for i in range(self.root_entry_count):
            off = self.root_start + i * 32
            if self.image[off] in (0x00, 0xE5):
                continue
            if self.image[off:off + 11] == name83:
                return off
        return -1

    def delete_entry(self, off: int):
        """Free clusters and mark directory entry deleted."""
        cluster = struct.unpack_from("<H", self.image, off + 26)[0]
        while 2 <= cluster <= 0xFEF:
            next_c = self.get_fat(cluster)
            self.set_fat(cluster, 0)
            cluster = next_c
        self.image[off] = 0xE5

    # --- Public interface ---

    def add_file(self, filename: str, data: bytes):
        name83 = _to_8dot3(filename)

        # Remove existing entry if present
        existing = self.find_existing(name83)
        if existing >= 0:
            self.delete_entry(existing)

        # Allocate clusters
        size = len(data)
        first_cluster = 0
        prev_cluster = 0
        offset = 0
        cluster_size = self.spc * self.bps

        while offset < size:
            c = self.alloc_cluster()
            if first_cluster == 0:
                first_cluster = c
            if prev_cluster:
                self.set_fat(prev_cluster, c)
            chunk = data[offset:offset + cluster_size]
            dst = self.cluster_offset(c)
            self.image[dst:dst + len(chunk)] = chunk
            # Zero-pad rest of cluster
            if len(chunk) < cluster_size:
                self.image[dst + len(chunk):dst + cluster_size] = b'\x00' * (cluster_size - len(chunk))
            prev_cluster = c
            offset += cluster_size

        # Write directory entry (32 bytes)
        slot = self.find_root_slot()
        entry = bytearray(32)
        entry[0:11] = name83
        entry[11] = 0x20          # attribute: archive
        struct.pack_into("<H", entry, 26, first_cluster)
        struct.pack_into("<I", entry, 28, size)
        self.image[slot:slot + 32] = entry
        print(f"  Added: {filename} ({size} bytes, cluster {first_cluster})")

    def list_files(self):
        print("Disk contents:")
        for i in range(self.root_entry_count):
            off = self.root_start + i * 32
            first = self.image[off]
            if first == 0x00:
                break
            if first == 0xE5:
                continue
            name = self.image[off:off + 8].rstrip(b' ').decode('ascii', errors='replace')
            ext  = self.image[off + 8:off + 11].rstrip(b' ').decode('ascii', errors='replace')
            size = struct.unpack_from("<I", self.image, off + 28)[0]
            print(f"  {name}.{ext:<3}  {size:6} bytes" if ext else f"  {name:<8}  {size:6} bytes")


def _to_8dot3(filename: str) -> bytes:
    """Convert filename to 11-byte 8.3 format (uppercase, space-padded)."""
    p = Path(filename.upper())
    stem = p.stem[:8].ljust(8)
    suffix = p.suffix.lstrip('.')[:3].ljust(3)
    return (stem + suffix).encode('ascii')


def main():
    if len(sys.argv) < 4:
        print(f"Usage: {sys.argv[0]} <base.dsk> <output.dsk> <file1> [file2 ...]")
        sys.exit(1)

    base_path   = sys.argv[1]
    output_path = sys.argv[2]
    files       = sys.argv[3:]

    image = bytearray(Path(base_path).read_bytes())
    disk  = Fat12Disk(image)

    for f in files:
        p = Path(f)
        if not p.exists():
            print(f"Warning: {f} not found, skipping")
            continue
        disk.add_file(p.name, p.read_bytes())

    with open(output_path, 'wb') as f:
        f.write(image)
    print()
    disk.list_files()
    print(f"\nDisk image: {output_path}")


if __name__ == "__main__":
    main()
