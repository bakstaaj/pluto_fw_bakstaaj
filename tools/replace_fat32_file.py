#!/usr/bin/env python3
"""Replace one root-directory FAT32 file in an image without mounting it."""

from __future__ import annotations

import argparse
import struct
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("image", type=Path)
    parser.add_argument("replacement", type=Path)
    parser.add_argument("filename")
    args = parser.parse_args()

    image = bytearray(args.image.read_bytes())
    replacement = args.replacement.read_bytes()
    partition = 2048 * 512
    bps = struct.unpack_from("<H", image, partition + 11)[0]
    spc = image[partition + 13]
    reserved = struct.unpack_from("<H", image, partition + 14)[0]
    fats = image[partition + 16]
    fat_sectors = struct.unpack_from("<I", image, partition + 36)[0]
    root_cluster = struct.unpack_from("<I", image, partition + 44)[0]
    fat = partition + reserved * bps
    data = partition + (reserved + fats * fat_sectors) * bps
    cluster_bytes = bps * spc

    def cluster_offset(cluster: int) -> int:
        return data + (cluster - 2) * cluster_bytes

    def next_cluster(cluster: int) -> int:
        return struct.unpack_from("<I", image, fat + cluster * 4)[0] & 0x0FFFFFFF

    target = args.filename.upper().replace(".", "")
    cluster = root_cluster
    entry_offset = None
    first_cluster = None
    size = None
    seen = set()
    while cluster >= 2 and cluster < 0x0FFFFFF8 and cluster not in seen:
        seen.add(cluster)
        base = cluster_offset(cluster)
        for offset in range(0, cluster_bytes, 32):
            entry = image[base + offset : base + offset + 32]
            if entry[0] in (0x00, 0xE5) or entry[11] == 0x0F:
                continue
            name = entry[0:8].decode("ascii", "ignore").rstrip()
            ext = entry[8:11].decode("ascii", "ignore").rstrip()
            candidate = (name + ext).upper()
            if candidate == target:
                entry_offset = base + offset
                first_cluster = (struct.unpack_from("<H", entry, 20)[0] << 16) | struct.unpack_from("<H", entry, 26)[0]
                size = struct.unpack_from("<I", entry, 28)[0]
                break
        if entry_offset is not None:
            break
        cluster = next_cluster(cluster)

    if entry_offset is None or first_cluster is None or size is None:
        raise SystemExit(f"root-directory file not found: {args.filename}")
    if len(replacement) > size:
        raise SystemExit(f"replacement is larger than allocated file size: {len(replacement)} > {size}")

    cluster = first_cluster
    remaining = replacement
    seen.clear()
    while remaining and cluster >= 2 and cluster < 0x0FFFFFF8 and cluster not in seen:
        seen.add(cluster)
        chunk = remaining[:cluster_bytes]
        start = cluster_offset(cluster)
        image[start : start + len(chunk)] = chunk
        if len(chunk) < cluster_bytes:
            image[start + len(chunk) : start + cluster_bytes] = b"\0" * (cluster_bytes - len(chunk))
        remaining = remaining[cluster_bytes:]
        cluster = next_cluster(cluster)
    if remaining:
        raise SystemExit("FAT chain ended before replacement was written")

    struct.pack_into("<I", image, entry_offset + 28, len(replacement))
    args.image.write_bytes(image)
    print(f"replaced {args.filename} with {len(replacement)} bytes")


if __name__ == "__main__":
    main()
