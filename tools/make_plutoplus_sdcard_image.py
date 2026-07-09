#!/usr/bin/env python3
"""Build PlutoPlus SD-card boot images from Tezuka and local firmware artifacts.

The output is intentionally conservative:
- a Tezuka baseline image, using the upstream PlutoPlus SD boot payload
- a Bakstaaj hybrid image, using Tezuka's SD BOOT.bin/uEnv boot chain plus
  this repository's kernel, initramfs, and default DTB

The image writer emits a simple MBR + FAT32 image with 8.3 filenames only.
That keeps the generated image independent of platform-specific mount tools.
"""

from __future__ import annotations

import argparse
import binascii
import hashlib
import lzma
import math
import os
import struct
import subprocess
import tempfile
import time
import urllib.request
import zipfile
import zlib
from pathlib import Path


TEZUKA_PLUTOPLUS_URL = (
    "https://github.com/F5OEO/tezuka_fw/releases/download/v0.3.12/"
    "tezuka-plutoplus-v0.3.12-730087d.zip"
)
TEZUKA_ZIP_NAME = "tezuka-plutoplus-v0.3.12-730087d.zip"
SECTOR_SIZE = 512


def round_up(value: int, quantum: int) -> int:
    return ((value + quantum - 1) // quantum) * quantum


def read_file(path: Path) -> bytes:
    with path.open("rb") as f:
        return f.read()


def write_file(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as f:
        f.write(data)


def download_if_needed(path: Path, url: str) -> None:
    if path.exists():
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    print(f"Downloading {url}")
    urllib.request.urlretrieve(url, path)


def find_zip_entry(zf: zipfile.ZipFile, suffix: str) -> zipfile.ZipInfo:
    matches = [entry for entry in zf.infolist() if entry.filename.endswith(suffix)]
    if not matches:
        raise FileNotFoundError(f"Tezuka zip does not contain {suffix}")
    return matches[0]


def load_tezuka_sdimg(zip_path: Path) -> dict[str, bytes]:
    required = {
        "BOOT.BIN": "sdimg/BOOT.bin",
        "UIMAGE": "sdimg/uImage",
        "DEVTREE.DTB": "sdimg/devicetree.dtb",
        "URAMDISK.XZ": "sdimg/uramdisk.image.xz",
        "SYSTEM.BIN": "sdimg/system_top.bin",
        "UENV.TXT": "sdimg/uEnv.txt",
    }
    files: dict[str, bytes] = {}
    with zipfile.ZipFile(zip_path) as zf:
        for out_name, suffix in required.items():
            entry = find_zip_entry(zf, suffix)
            files[out_name] = zf.read(entry)
    files["UENV.TXT"] = normalize_uenv(files["UENV.TXT"], ramdisk_name="URAMDISK.XZ")
    return files


def load_tezuka_sdimg_exact(zip_path: Path) -> dict[str, bytes]:
    files: dict[str, bytes] = {}
    with zipfile.ZipFile(zip_path) as zf:
        for entry in zf.infolist():
            marker = "/sdimg/"
            if marker not in entry.filename or entry.is_dir():
                continue
            rel = entry.filename.split(marker, 1)[1]
            if "/" in rel:
                continue
            files[rel] = zf.read(entry)
    required = {"BOOT.bin", "devicetree.dtb", "system_top.bin", "uEnv.txt", "uImage", "uramdisk.image.xz"}
    missing = required - set(files)
    if missing:
        raise FileNotFoundError(f"Tezuka zip is missing SD files: {', '.join(sorted(missing))}")
    return files


def normalize_uenv(content: bytes, ramdisk_name: str) -> bytes:
    text = content.decode("utf-8", errors="replace")
    replacements = {
        "kernel_image=": "kernel_image=UIMAGE",
        "devicetree_image=": "devicetree_image=DEVTREE.DTB",
        "ramdisk_image=": f"ramdisk_image={ramdisk_name}",
        "bootenv=": "bootenv=UENV.TXT",
    }
    out_lines: list[str] = []
    for line in text.splitlines():
        replaced = False
        for prefix, new_line in replacements.items():
            if line.startswith(prefix):
                out_lines.append(new_line)
                replaced = True
                break
        if not replaced:
            out_lines.append(line)
    return ("\n".join(out_lines) + "\n").encode("utf-8")


def make_uimage(
    payload: bytes,
    *,
    name: str,
    image_type: int,
    compression: int,
    load: int,
    entry: int,
) -> bytes:
    timestamp = int(time.time())
    data_crc = binascii.crc32(payload) & 0xFFFFFFFF
    name_bytes = name.encode("ascii", errors="ignore")[:32]
    name_bytes = name_bytes + (b"\x00" * (32 - len(name_bytes)))
    header = struct.pack(
        ">7I4B32s",
        0x27051956,
        0,
        timestamp,
        len(payload),
        load,
        entry,
        data_crc,
        5,  # IH_OS_LINUX
        2,  # IH_ARCH_ARM
        image_type,
        compression,
        name_bytes,
    )
    header_crc = binascii.crc32(header) & 0xFFFFFFFF
    header = struct.pack(
        ">7I4B32s",
        0x27051956,
        header_crc,
        timestamp,
        len(payload),
        load,
        entry,
        data_crc,
        5,
        2,
        image_type,
        compression,
        name_bytes,
    )
    return header + payload


def extract_kernel_payload(zimage: bytes) -> bytes:
    offset = zimage.find(b"\x1f\x8b\x08")
    if offset < 0:
        raise ValueError("Could not find gzip payload inside zImage")
    decompressor = zlib.decompressobj(16 + zlib.MAX_WBITS)
    return decompressor.decompress(zimage[offset:])


def build_hybrid_files(tezuka_files: dict[str, bytes], source_dir: Path) -> dict[str, bytes]:
    zimage_path = source_dir / "zImage"
    rootfs_path = source_dir / "rootfs.cpio.gz"
    dtb_path = source_dir / "verify-zynq-pluto-sdr.dtb"
    for path in (zimage_path, rootfs_path, dtb_path):
        if not path.exists():
            raise FileNotFoundError(path)

    kernel = extract_kernel_payload(read_file(zimage_path))
    kernel_lzma = lzma.compress(kernel, format=lzma.FORMAT_ALONE)
    files = dict(tezuka_files)
    files["UIMAGE"] = make_uimage(
        kernel_lzma,
        name="Linux kernel",
        image_type=2,  # IH_TYPE_KERNEL
        compression=3,  # IH_COMP_LZMA
        load=0x8000,
        entry=0x8000,
    )
    files["URAMDISK.GZ"] = make_uimage(
        read_file(rootfs_path),
        name="Bakstaaj rootfs",
        image_type=3,  # IH_TYPE_RAMDISK
        compression=1,  # IH_COMP_GZIP
        load=0,
        entry=0,
    )
    files.pop("URAMDISK.XZ", None)
    files["DEVTREE.DTB"] = read_file(dtb_path)
    files["UENV.TXT"] = normalize_uenv(tezuka_files["UENV.TXT"], ramdisk_name="URAMDISK.GZ")
    return files


def build_hybrid_files_exact(tezuka_files: dict[str, bytes], source_dir: Path) -> dict[str, bytes]:
    zimage_path = source_dir / "zImage"
    rootfs_path = source_dir / "rootfs.cpio.gz"
    dtb_path = source_dir / "verify-zynq-pluto-sdr.dtb"
    for path in (zimage_path, rootfs_path, dtb_path):
        if not path.exists():
            raise FileNotFoundError(path)

    kernel = extract_kernel_payload(read_file(zimage_path))
    kernel_lzma = lzma.compress(kernel, format=lzma.FORMAT_ALONE)
    files = dict(tezuka_files)
    files["uImage"] = make_uimage(
        kernel_lzma,
        name="Linux kernel",
        image_type=2,
        compression=3,
        load=0x8000,
        entry=0x8000,
    )
    files["uramdisk.image.gz"] = make_uimage(
        read_file(rootfs_path),
        name="Bakstaaj rootfs",
        image_type=3,
        compression=1,
        load=0,
        entry=0,
    )
    files.pop("uramdisk.image.xz", None)
    files["devicetree.dtb"] = read_file(dtb_path)
    files["uEnv.txt"] = normalize_uenv_exact(tezuka_files["uEnv.txt"], ramdisk_name="uramdisk.image.gz")
    return files


def normalize_uenv_exact(content: bytes, ramdisk_name: str) -> bytes:
    text = content.decode("utf-8", errors="replace")
    replacements = {
        "ramdisk_image=": f"ramdisk_image={ramdisk_name}",
    }
    out_lines: list[str] = []
    for line in text.splitlines():
        replaced = False
        for prefix, new_line in replacements.items():
            if line.startswith(prefix):
                out_lines.append(new_line)
                replaced = True
                break
        if not replaced:
            out_lines.append(line)
    return ("\n".join(out_lines) + "\n").encode("utf-8")


def fat_date_time() -> tuple[int, int]:
    now = time.localtime()
    fat_time = (now.tm_hour << 11) | (now.tm_min << 5) | (now.tm_sec // 2)
    fat_date = ((now.tm_year - 1980) << 9) | (now.tm_mon << 5) | now.tm_mday
    return fat_date, fat_time


def short_name_entry(name: str) -> bytes:
    if "." in name:
        base, ext = name.rsplit(".", 1)
    else:
        base, ext = name, ""
    base = base.upper()
    ext = ext.upper()
    if not base or len(base) > 8 or len(ext) > 3:
        raise ValueError(f"Only 8.3 filenames are supported: {name}")
    raw = base.encode("ascii").ljust(8, b" ") + ext.encode("ascii").ljust(3, b" ")
    return raw


def make_dir_entry(name: str, start_cluster: int, size: int) -> bytes:
    fat_date, fat_time = fat_date_time()
    return struct.pack(
        "<11sBBBHHHHHHHI",
        short_name_entry(name),
        0x20,
        0,
        0,
        fat_time,
        fat_date,
        fat_date,
        (start_cluster >> 16) & 0xFFFF,
        fat_time,
        fat_date,
        start_cluster & 0xFFFF,
        size,
    )


def write_mbr_partition(
    image: bytearray,
    index: int,
    *,
    bootable: bool,
    partition_type: int,
    start_sector: int,
    sector_count: int,
) -> None:
    if not 1 <= index <= 4:
        raise ValueError("MBR partition index must be 1..4")
    mbr_entry = struct.pack(
        "<B3sB3sII",
        0x80 if bootable else 0x00,
        b"\x00\x02\x00",
        partition_type,
        b"\xff\xff\xff",
        start_sector,
        sector_count,
    )
    offset = 446 + ((index - 1) * 16)
    image[offset : offset + 16] = mbr_entry
    image[510:512] = b"\x55\xaa"


def write_fat32_partition(
    image: bytearray,
    files: dict[str, bytes],
    *,
    partition_start: int,
    partition_sectors: int,
) -> None:
    reserved_sectors = 32
    sectors_per_cluster = 1
    num_fats = 2
    root_cluster = 2

    data_bytes = sum(round_up(len(data), SECTOR_SIZE * sectors_per_cluster) for data in files.values())
    needed_data_clusters = data_bytes // (SECTOR_SIZE * sectors_per_cluster)
    needed_clusters = needed_data_clusters + 1  # root directory cluster

    fat_sectors = 1
    while True:
        data_sectors = partition_sectors - reserved_sectors - (num_fats * fat_sectors)
        cluster_count = data_sectors // sectors_per_cluster
        new_fat_sectors = math.ceil((cluster_count + 2) * 4 / SECTOR_SIZE)
        if new_fat_sectors == fat_sectors:
            break
        fat_sectors = new_fat_sectors

    if cluster_count < 65525:
        raise ValueError("Image is too small for FAT32")
    if needed_clusters + 2 > cluster_count:
        raise ValueError("Image is too small for requested files")

    volume_id = int(time.time()) & 0xFFFFFFFF
    boot = bytearray(SECTOR_SIZE)
    boot[0:3] = b"\xeb\x58\x90"
    boot[3:11] = b"MSDOS5.0"
    struct.pack_into("<H", boot, 11, SECTOR_SIZE)
    boot[13] = sectors_per_cluster
    struct.pack_into("<H", boot, 14, reserved_sectors)
    boot[16] = num_fats
    struct.pack_into("<H", boot, 17, 0)
    struct.pack_into("<H", boot, 19, 0)
    boot[21] = 0xF8
    struct.pack_into("<H", boot, 22, 0)
    struct.pack_into("<H", boot, 24, 63)
    struct.pack_into("<H", boot, 26, 255)
    struct.pack_into("<I", boot, 28, partition_start)
    struct.pack_into("<I", boot, 32, partition_sectors)
    struct.pack_into("<I", boot, 36, fat_sectors)
    struct.pack_into("<H", boot, 40, 0)
    struct.pack_into("<H", boot, 42, 0)
    struct.pack_into("<I", boot, 44, root_cluster)
    struct.pack_into("<H", boot, 48, 1)
    struct.pack_into("<H", boot, 50, 6)
    boot[64] = 0x80
    boot[66] = 0x29
    struct.pack_into("<I", boot, 67, volume_id)
    boot[71:82] = b"PLUTOSD    "
    boot[82:90] = b"FAT32   "
    boot[510:512] = b"\x55\xaa"

    fsinfo = bytearray(SECTOR_SIZE)
    struct.pack_into("<I", fsinfo, 0, 0x41615252)
    struct.pack_into("<I", fsinfo, 484, 0x61417272)
    struct.pack_into("<I", fsinfo, 488, 0xFFFFFFFF)
    struct.pack_into("<I", fsinfo, 492, 0xFFFFFFFF)
    fsinfo[510:512] = b"\x55\xaa"

    part_offset = partition_start * SECTOR_SIZE
    image[part_offset : part_offset + SECTOR_SIZE] = boot
    image[part_offset + SECTOR_SIZE : part_offset + 2 * SECTOR_SIZE] = fsinfo
    backup_offset = part_offset + 6 * SECTOR_SIZE
    image[backup_offset : backup_offset + SECTOR_SIZE] = boot
    image[backup_offset + SECTOR_SIZE : backup_offset + 2 * SECTOR_SIZE] = fsinfo

    fat_offset = part_offset + reserved_sectors * SECTOR_SIZE
    data_offset = fat_offset + num_fats * fat_sectors * SECTOR_SIZE

    fat_entries = [0] * (cluster_count + 2)
    fat_entries[0] = 0x0FFFFFF8
    fat_entries[1] = 0x0FFFFFFF
    fat_entries[root_cluster] = 0x0FFFFFFF

    next_cluster = root_cluster + 1
    root_entries = bytearray(SECTOR_SIZE * sectors_per_cluster)
    root_entry_index = 0

    for name in sorted(files):
        data = files[name]
        clusters = max(1, round_up(len(data), SECTOR_SIZE * sectors_per_cluster) // (SECTOR_SIZE * sectors_per_cluster))
        start_cluster = next_cluster
        for i in range(clusters):
            cluster = next_cluster + i
            fat_entries[cluster] = 0x0FFFFFFF if i == clusters - 1 else cluster + 1
            cluster_offset = data_offset + (cluster - 2) * sectors_per_cluster * SECTOR_SIZE
            chunk = data[i * sectors_per_cluster * SECTOR_SIZE : (i + 1) * sectors_per_cluster * SECTOR_SIZE]
            image[cluster_offset : cluster_offset + len(chunk)] = chunk
        next_cluster += clusters
        entry_offset = root_entry_index * 32
        root_entries[entry_offset : entry_offset + 32] = make_dir_entry(name, start_cluster, len(data))
        root_entry_index += 1

    root_offset = data_offset + (root_cluster - 2) * sectors_per_cluster * SECTOR_SIZE
    image[root_offset : root_offset + len(root_entries)] = root_entries

    fat = bytearray(fat_sectors * SECTOR_SIZE)
    for idx, value in enumerate(fat_entries[:next_cluster]):
        struct.pack_into("<I", fat, idx * 4, value)
    for fat_idx in range(num_fats):
        start = fat_offset + fat_idx * fat_sectors * SECTOR_SIZE
        image[start : start + len(fat)] = fat


def make_ext4_image(size_bytes: int, label: str) -> bytes:
    with tempfile.TemporaryDirectory(prefix="pluto-ext4-") as tmp:
        image_path = Path(tmp) / "data.ext4"
        subprocess.run(
            [
                "mke2fs",
                "-q",
                "-t",
                "ext4",
                "-L",
                label,
                "-m",
                "0",
                "-O",
                "^64bit",
                "-F",
                str(image_path),
                str(size_bytes // 1024),
            ],
            check=True,
        )
        return read_file(image_path)


def make_fat32_image(files: dict[str, bytes], image_path: Path, image_mib: int) -> None:
    partition_start = 2048
    total_sectors = image_mib * 1024 * 1024 // SECTOR_SIZE
    partition_sectors = total_sectors - partition_start
    image = bytearray(total_sectors * SECTOR_SIZE)
    write_mbr_partition(
        image,
        1,
        bootable=True,
        partition_type=0x0C,
        start_sector=partition_start,
        sector_count=partition_sectors,
    )
    write_fat32_partition(image, files, partition_start=partition_start, partition_sectors=partition_sectors)
    write_file(image_path, bytes(image))


def make_fat32_ext4_image(
    files: dict[str, bytes],
    image_path: Path,
    *,
    image_mib: int,
    boot_mib: int,
    data_label: str = "PLUTO_DATA",
) -> None:
    total_sectors = image_mib * 1024 * 1024 // SECTOR_SIZE
    boot_start = 2048
    boot_sectors = boot_mib * 1024 * 1024 // SECTOR_SIZE
    data_start = round_up(boot_start + boot_sectors, 2048)
    data_sectors = total_sectors - data_start
    if data_sectors < 32768:
        raise ValueError("SD image is too small for a useful ext4 data partition")

    image = bytearray(total_sectors * SECTOR_SIZE)
    write_mbr_partition(
        image,
        1,
        bootable=True,
        partition_type=0x0C,
        start_sector=boot_start,
        sector_count=boot_sectors,
    )
    write_mbr_partition(
        image,
        2,
        bootable=False,
        partition_type=0x83,
        start_sector=data_start,
        sector_count=data_sectors,
    )
    write_fat32_partition(image, files, partition_start=boot_start, partition_sectors=boot_sectors)
    ext4 = make_ext4_image(data_sectors * SECTOR_SIZE, data_label)
    data_offset = data_start * SECTOR_SIZE
    image[data_offset : data_offset + len(ext4)] = ext4
    write_file(image_path, bytes(image))



def write_sdimg_dir(path: Path, files: dict[str, bytes]) -> None:
    path.mkdir(parents=True, exist_ok=True)
    for child in path.iterdir():
        if child.is_file():
            child.unlink()
    for name, data in sorted(files.items()):
        write_file(path / name, data)


def write_manifest(path: Path, source_dir: Path, tezuka_zip: Path, hybrid: bool) -> None:
    text = [
        "PlutoPlus SD-card image package",
        "",
        f"Generated: {time.strftime('%Y-%m-%d %H:%M:%S %z')}",
        f"Tezuka source zip: {tezuka_zip}",
        f"Local firmware source: {source_dir}",
        "",
    ]
    if hybrid:
        text.extend(
            [
                "Mode: experimental Bakstaaj hybrid",
                "",
                "BOOT.BIN and base U-Boot environment come from Tezuka PlutoPlus v0.3.12.",
                "UIMAGE, URAMDISK.GZ, and DEVTREE.DTB come from the selected local firmware output.",
                "This is the candidate image to test after the Tezuka baseline boots.",
            ]
        )
    else:
        text.extend(
            [
                "Mode: Tezuka PlutoPlus baseline",
                "",
                "All SD boot payload files come from Tezuka PlutoPlus v0.3.12.",
                "Filenames are shortened to 8.3 names and uEnv.txt is adjusted accordingly.",
                "This is the first image to test to prove the board boots the Tezuka SD layout.",
            ]
        )
    write_file(path, ("\n".join(text) + "\n").encode("utf-8"))


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def write_top_level_readme(out_dir: Path, baseline_img: Path, hybrid_img: Path) -> None:
    text = f"""PlutoPlus SD-card Images

Artifacts:

- copy-files-tezuka-plutoplus-baseline/sdimg/
  Exact Tezuka PlutoPlus SD boot files with upstream filenames preserved.
  Format an SD card as FAT32 and copy these files to the card root. This is
  the preferred next test if the raw .img files did not boot.

- copy-files-bakstaaj-hybrid/sdimg/
  Exact Tezuka SD filename layout with local Bakstaaj kernel, initramfs, and
  DTB swapped in. Test only after the Tezuka copy-files baseline boots.

- tezuka-plutoplus-baseline/tezuka-plutoplus-baseline.img
  Known-good Tezuka PlutoPlus SD boot payload. Burn this first to prove the
  board boots the Tezuka SD layout.

- bakstaaj-hybrid/bakstaaj-hybrid.img
  Experimental image using Tezuka's PlutoPlus SD BOOT.BIN/uEnv boot chain with
  the selected local Bakstaaj kernel, initramfs, and DTB. Burn this only after
  the baseline image boots.

Burning or copying:

Use Raspberry Pi Imager, balenaEtcher, Win32 Disk Imager, or another raw-image
writer. Select the .img file and write it to a spare SD card. Do not write over
the vendor SD card.

If the raw .img files do not boot, use the copy-files packages instead:
format the spare SD card as FAT32, then copy the contents of the selected
sdimg folder to the root of the card.

Hardware:

Set the board BOOT DIP switches to SD and use the OTG USB port for normal USB
gadget/network operation. The JTAG USB port is for debug/programming.

Expected first test order:

1. Burn tezuka-plutoplus-baseline.img and confirm the board boots.
2. Burn bakstaaj-hybrid.img and check whether the local firmware payload boots.

Hashes:

{sha256_file(baseline_img)}  {baseline_img.relative_to(out_dir)}
{sha256_file(hybrid_img)}  {hybrid_img.relative_to(out_dir)}
"""
    write_file(out_dir / "README.txt", text.encode("utf-8"))
    write_file(
        out_dir / "SHA256SUMS.txt",
        (
            f"{sha256_file(baseline_img)}  {baseline_img.relative_to(out_dir)}\n"
            f"{sha256_file(hybrid_img)}  {hybrid_img.relative_to(out_dir)}\n"
        ).encode("utf-8"),
    )


def zip_tree(src_dir: Path, zip_path: Path) -> None:
    if zip_path.exists():
        zip_path.unlink()
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for path in sorted(src_dir.rglob("*")):
            if path.is_file():
                zf.write(path, path.relative_to(src_dir.parent))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path.cwd())
    parser.add_argument(
        "--source-dir",
        type=Path,
        default=Path("build-large-jffs3-sdcard-ethernet-pluto-plus"),
        help="Local firmware output directory with zImage/rootfs.cpio.gz/verify-zynq-pluto-sdr.dtb",
    )
    parser.add_argument("--out-dir", type=Path, default=Path("build-plutoplus-sdcard-image"))
    parser.add_argument("--tezuka-zip", type=Path, default=None)
    parser.add_argument("--download-tezuka", action="store_true")
    parser.add_argument("--image-mib", type=int, default=128)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    repo = args.repo.resolve()
    source_dir = (repo / args.source_dir).resolve() if not args.source_dir.is_absolute() else args.source_dir.resolve()
    out_dir = (repo / args.out_dir).resolve() if not args.out_dir.is_absolute() else args.out_dir.resolve()
    tezuka_zip = args.tezuka_zip
    if tezuka_zip is None:
        tezuka_zip = out_dir / "downloads" / TEZUKA_ZIP_NAME
    tezuka_zip = tezuka_zip.resolve()

    if args.download_tezuka:
        download_if_needed(tezuka_zip, TEZUKA_PLUTOPLUS_URL)
    if not tezuka_zip.exists():
        raise FileNotFoundError(
            f"Missing Tezuka zip: {tezuka_zip}\n"
            f"Pass --download-tezuka or download {TEZUKA_PLUTOPLUS_URL}"
        )

    out_dir.mkdir(parents=True, exist_ok=True)
    tezuka_files = load_tezuka_sdimg(tezuka_zip)
    tezuka_exact_files = load_tezuka_sdimg_exact(tezuka_zip)
    hybrid_files = build_hybrid_files(tezuka_files, source_dir)
    hybrid_exact_files = build_hybrid_files_exact(tezuka_exact_files, source_dir)

    baseline_dir = out_dir / "tezuka-plutoplus-baseline"
    hybrid_dir = out_dir / "bakstaaj-hybrid"
    exact_baseline_dir = out_dir / "copy-files-tezuka-plutoplus-baseline"
    exact_hybrid_dir = out_dir / "copy-files-bakstaaj-hybrid"

    write_sdimg_dir(baseline_dir / "sdimg", tezuka_files)
    write_manifest(baseline_dir / "README.txt", source_dir, tezuka_zip, hybrid=False)
    baseline_img = baseline_dir / "tezuka-plutoplus-baseline.img"
    make_fat32_image(tezuka_files, baseline_img, args.image_mib)

    write_sdimg_dir(hybrid_dir / "sdimg", hybrid_files)
    write_manifest(hybrid_dir / "README.txt", source_dir, tezuka_zip, hybrid=True)
    hybrid_img = hybrid_dir / "bakstaaj-hybrid.img"
    make_fat32_image(hybrid_files, hybrid_img, args.image_mib)

    write_sdimg_dir(exact_baseline_dir / "sdimg", tezuka_exact_files)
    write_manifest(exact_baseline_dir / "README.txt", source_dir, tezuka_zip, hybrid=False)
    zip_tree(exact_baseline_dir, out_dir / "copy-files-tezuka-plutoplus-baseline.zip")

    write_sdimg_dir(exact_hybrid_dir / "sdimg", hybrid_exact_files)
    write_manifest(exact_hybrid_dir / "README.txt", source_dir, tezuka_zip, hybrid=True)
    zip_tree(exact_hybrid_dir, out_dir / "copy-files-bakstaaj-hybrid.zip")

    write_top_level_readme(out_dir, baseline_img, hybrid_img)

    print(f"Wrote {baseline_dir}")
    print(f"Wrote {hybrid_dir}")


if __name__ == "__main__":
    main()
