#!/usr/bin/env python3
"""Assemble a bakStaaJ Pluto release package from known-good local artifacts."""

from __future__ import annotations

import argparse
import binascii
import gzip
import hashlib
import shutil
import struct
import time
import zipfile
import zlib
from pathlib import Path

import make_oem_sdcard_package as oem
from make_plutoplus_sdcard_image import make_fat32_image


FDT_MAGIC = 0xD00DFEED
FDT_BEGIN_NODE = 1
FDT_END_NODE = 2
FDT_PROP = 3
FDT_NOP = 4
FDT_END = 9

DEVICE_VID = 0x0456
DEVICE_PID = 0xB673
DFU_SUFFIX_LEN = 16


class FdtNode:
    def __init__(self, name: str) -> None:
        self.name = name
        self.props: list[tuple[str, bytes]] = []
        self.children: list[FdtNode] = []


def align4(value: int) -> int:
    return (value + 3) & ~3


def read_file(path: Path) -> bytes:
    with path.open("rb") as f:
        return f.read()


def write_file(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as f:
        f.write(data)


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def parse_strings(strings: bytes) -> dict[int, str]:
    offsets: dict[int, str] = {}
    pos = 0
    while pos < len(strings):
        end = strings.find(b"\x00", pos)
        if end < 0:
            break
        if end > pos:
            offsets[pos] = strings[pos:end].decode("ascii", errors="replace")
        pos = end + 1
    return offsets


def parse_fit(data: bytes) -> tuple[FdtNode, bytes, bytes, dict[str, int], dict[str, int]]:
    header_values = struct.unpack_from(">10I", data, 0)
    (
        magic,
        totalsize,
        off_dt_struct,
        off_dt_strings,
        off_mem_rsvmap,
        version,
        last_comp_version,
        boot_cpuid_phys,
        size_dt_strings,
        size_dt_struct,
    ) = header_values
    if magic != FDT_MAGIC:
        raise ValueError("FIT image is not an FDT blob")

    strings = data[off_dt_strings : off_dt_strings + size_dt_strings]
    strings_by_offset = parse_strings(strings)
    mem_rsvmap = data[off_mem_rsvmap:off_dt_struct]
    struct_block = data[off_dt_struct : off_dt_struct + size_dt_struct]
    pos = 0
    stack: list[FdtNode] = []
    root: FdtNode | None = None

    while pos < len(struct_block):
        token = struct.unpack_from(">I", struct_block, pos)[0]
        pos += 4
        if token == FDT_BEGIN_NODE:
            end = struct_block.index(b"\x00", pos)
            name = struct_block[pos:end].decode("ascii", errors="replace")
            pos = align4(end + 1)
            node = FdtNode(name)
            if stack:
                stack[-1].children.append(node)
            else:
                root = node
            stack.append(node)
        elif token == FDT_END_NODE:
            stack.pop()
        elif token == FDT_PROP:
            prop_len, nameoff = struct.unpack_from(">II", struct_block, pos)
            pos += 8
            prop_name = strings_by_offset[nameoff]
            value = struct_block[pos : pos + prop_len]
            pos = align4(pos + prop_len)
            stack[-1].props.append((prop_name, value))
        elif token == FDT_NOP:
            continue
        elif token == FDT_END:
            break
        else:
            raise ValueError(f"Unexpected FDT token {token}")

    if root is None:
        raise ValueError("FIT root node not found")
    header = {
        "version": version,
        "last_comp_version": last_comp_version,
        "boot_cpuid_phys": boot_cpuid_phys,
        "totalsize": totalsize,
    }
    sizes = {
        "size_dt_strings": size_dt_strings,
        "size_dt_struct": size_dt_struct,
    }
    return root, mem_rsvmap, strings, header, sizes


def build_string_offsets(strings: bytes) -> dict[str, int]:
    offsets: dict[str, int] = {}
    pos = 0
    while pos < len(strings):
        end = strings.find(b"\x00", pos)
        if end < 0:
            break
        if end > pos:
            offsets[strings[pos:end].decode("ascii", errors="replace")] = pos
        pos = end + 1
    return offsets


def pack_node(node: FdtNode, strings: bytes, string_offsets: dict[str, int]) -> bytes:
    out = bytearray()
    out += struct.pack(">I", FDT_BEGIN_NODE)
    out += node.name.encode("ascii") + b"\x00"
    out += b"\x00" * (align4(len(out)) - len(out))
    for name, value in node.props:
        if name not in string_offsets:
            string_offsets[name] = len(strings)
            strings += name.encode("ascii") + b"\x00"
        out += struct.pack(">III", FDT_PROP, len(value), string_offsets[name])
        out += value
        out += b"\x00" * (align4(len(out)) - len(out))
    for child in node.children:
        out += pack_node(child, strings, string_offsets)
    out += struct.pack(">I", FDT_END_NODE)
    return bytes(out)


def find_child(node: FdtNode, name: str) -> FdtNode:
    for child in node.children:
        if child.name == name:
            return child
    raise KeyError(name)


def replace_ramdisk_data(root: FdtNode, rootfs_gz: bytes) -> None:
    images = find_child(root, "images")
    ramdisk = find_child(images, "ramdisk@1")
    replaced = False
    new_props: list[tuple[str, bytes]] = []
    for name, value in ramdisk.props:
        if name == "data":
            new_props.append((name, rootfs_gz))
            replaced = True
        else:
            new_props.append((name, value))
    if not replaced:
        raise ValueError("ramdisk@1 data property not found")
    ramdisk.props = new_props


def pack_fit(root: FdtNode, mem_rsvmap: bytes, strings: bytes, header: dict[str, int]) -> bytes:
    string_offsets = build_string_offsets(strings)
    struct_block = pack_node(root, strings, string_offsets) + struct.pack(">I", FDT_END)
    struct_block += b"\x00" * (align4(len(struct_block)) - len(struct_block))
    off_mem_rsvmap = 40
    off_dt_struct = off_mem_rsvmap + len(mem_rsvmap)
    off_dt_strings = off_dt_struct + len(struct_block)
    totalsize = off_dt_strings + len(strings)
    fdt_header = struct.pack(
        ">10I",
        FDT_MAGIC,
        totalsize,
        off_dt_struct,
        off_dt_strings,
        off_mem_rsvmap,
        header["version"],
        header["last_comp_version"],
        header["boot_cpuid_phys"],
        len(strings),
        len(struct_block),
    )
    return fdt_header + mem_rsvmap + struct_block + strings


def patch_fit_ramdisk(fit_data: bytes, rootfs_gz: bytes) -> bytes:
    root, mem_rsvmap, strings, header, _sizes = parse_fit(fit_data)
    replace_ramdisk_data(root, rootfs_gz)
    return pack_fit(root, mem_rsvmap, strings, header)


def make_frm(itb: bytes) -> bytes:
    md5 = hashlib.md5(itb).hexdigest().encode("ascii") + b"\n"
    return itb + md5


def dfu_crc(data: bytes) -> int:
    return 0xFFFFFFFF & -zlib.crc32(data) - 1


def make_dfu(payload: bytes, *, vid: int = DEVICE_VID, pid: int = DEVICE_PID) -> bytes:
    suffix_without_crc = struct.pack(
        "<4H3sB",
        0xFFFF,
        pid,
        vid,
        0x0100,
        b"UFD",
        DFU_SUFFIX_LEN,
    )
    data = payload + suffix_without_crc
    return data + struct.pack("<I", dfu_crc(data))


def normalize_oem_uenv_for_fat32(content: bytes) -> bytes:
    replacements = {
        "bootenv=": "bootenv=UENV.TXT",
        "devicetree_image=": "devicetree_image=DEVTREE.DTB",
        "kernel_image=": "kernel_image=UIMAGE",
        "ramdisk_image=": "ramdisk_image=URAMDISK.GZ",
    }
    out: list[str] = []
    for line in content.decode("utf-8", errors="replace").splitlines():
        for prefix, replacement in replacements.items():
            if line.startswith(prefix):
                out.append(replacement)
                break
        else:
            out.append(line)
    return ("\n".join(out) + "\n").encode("utf-8")


def make_sd_files(repo: Path, oem_dir: Path, source_dir: Path, rootfs_gz: bytes) -> dict[str, bytes]:
    dtb = oem.patch_dtb_jffs2_layout(read_file(oem_dir / "devicetree.dtb"), 5)
    return {
        "BOOT.bin": read_file(oem_dir / "BOOT.bin"),
        "uEnv.txt": read_file(oem_dir / "uEnv.txt"),
        "uImage": oem.make_uimage(
            read_file(source_dir / "zImage"),
            name="PlutoSDR zImage",
            image_type=2,
            compression=0,
            load=0x8000,
            entry=0x8000,
        ),
        "devicetree.dtb": dtb,
        "uramdisk.image.gz": oem.make_uimage(
            rootfs_gz,
            name="PlutoSDR rootfs",
            image_type=3,
            compression=1,
            load=0,
            entry=0,
        ),
    }


def make_fat32_sd_files(sd_files: dict[str, bytes]) -> dict[str, bytes]:
    return {
        "BOOT.BIN": sd_files["BOOT.bin"],
        "UENV.TXT": normalize_oem_uenv_for_fat32(sd_files["uEnv.txt"]),
        "UIMAGE": sd_files["uImage"],
        "DEVTREE.DTB": sd_files["devicetree.dtb"],
        "URAMDISK.GZ": sd_files["uramdisk.image.gz"],
    }


def zip_dir(src_dir: Path, zip_path: Path) -> None:
    if zip_path.exists():
        zip_path.unlink()
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for path in sorted(src_dir.rglob("*")):
            if path.is_file():
                zf.write(path, path.relative_to(src_dir))


def copy_if_exists(src: Path, dst: Path) -> None:
    if src.exists():
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)


def write_hashes(release_dir: Path) -> None:
    lines = []
    for path in sorted(release_dir.rglob("*")):
        if path.is_file() and path.name != "SHA256SUMS.txt":
            lines.append(f"{sha256_file(path)}  {path.relative_to(release_dir).as_posix()}")
    write_file(release_dir / "SHA256SUMS.txt", ("\n".join(lines) + "\n").encode("utf-8"))


def write_readme(release_dir: Path, version: str) -> None:
    text = f"""bakStaaJ Pluto Firmware Release

Version: {version}

This package is assembled from the known-good Pluto firmware payload in
build-large-jffs3-sdcard-ethernet-pluto-plus, with the dashboard files and
version string injected into the initramfs.

Firmware update files:
- firmware/pluto.frm
- firmware/pluto.dfu
- firmware/pluto.itb
- firmware/config.frm
- firmware/boot.frm
- firmware/boot.dfu
- firmware/uboot-env.dfu

SD boot files:
- sdcard/sdimg/
- sdcard/bakstaaj-{version}-sdcard-files.zip
- sdcard/bakstaaj-{version}-sdcard.img

For the new SD-boot board, use the SD-card files or image. The SD boot package
keeps the OEM BOOT.bin and uEnv.txt boot chain, uses the OEM DTB with qspi-nvmfs
patched to 5 MiB, and injects the dashboard-enabled rootfs.

Dashboard:
- http://192.168.2.1/dashboard.html

Version source:
- /opt/VERSIONS contains: device-fw {version}

Notes:
- This release was assembled locally without rerunning the full Vivado/Buildroot
  Docker build, because WSL has no installed Linux distribution on this machine.
- The .frm/.dfu files are generated from a patched FIT image so they share the
  same dashboard-enabled rootfs and version string.
"""
    write_file(release_dir / "README.txt", text.encode("utf-8"))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path.cwd())
    parser.add_argument("--version", default="v0.39-bakstaaj.1")
    parser.add_argument("--source-dir", type=Path, default=Path("build-large-jffs3-sdcard-ethernet-pluto-plus"))
    parser.add_argument("--oem-dir", type=Path, default=Path(r"C:\tmp\oem-pluto-sd"))
    parser.add_argument("--out-dir", type=Path, default=None)
    parser.add_argument("--sd-image-mib", type=int, default=64)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    repo = args.repo.resolve()
    source_dir = args.source_dir if args.source_dir.is_absolute() else repo / args.source_dir
    source_dir = source_dir.resolve()
    oem_dir = args.oem_dir.resolve()
    release_dir = args.out_dir if args.out_dir else repo / "release-packages" / f"bakstaaj-{args.version}"
    release_dir = release_dir.resolve()

    firmware_dir = release_dir / "firmware"
    sdcard_dir = release_dir / "sdcard"
    sdimg_dir = sdcard_dir / "sdimg"
    for path in (firmware_dir, sdimg_dir):
        path.mkdir(parents=True, exist_ok=True)

    base_rootfs = read_file(source_dir / "rootfs.cpio.gz")
    patched_rootfs = oem.patch_rootfs_cpio_gz(
        base_rootfs,
        repo=repo,
        brand_name=None,
        fw_version=args.version,
        force_usb_ethernet_mode=None,
        disable_usb_acm=False,
        disable_usb_msd=False,
        install_usb_debug=False,
        include_web_dashboard=True,
    )
    write_file(firmware_dir / "rootfs.cpio.gz", patched_rootfs)

    base_itb = read_file(source_dir / "pluto.itb")
    release_itb = patch_fit_ramdisk(base_itb, patched_rootfs)
    write_file(firmware_dir / "pluto.itb", release_itb)
    write_file(firmware_dir / "pluto.frm", make_frm(release_itb))
    write_file(firmware_dir / "pluto.dfu", make_dfu(release_itb))

    for name in ("boot.frm", "boot.dfu", "uboot-env.dfu", "config.frm", "FULL_DFU_UPDATE.bat"):
        copy_if_exists(source_dir / name, firmware_dir / name)
        copy_if_exists(repo / "scripts" / name, firmware_dir / name)

    sd_files = make_sd_files(repo, oem_dir, source_dir, patched_rootfs)
    for name, data in sd_files.items():
        write_file(sdimg_dir / name, data)
    sd_files_zip = sdcard_dir / f"bakstaaj-{args.version}-sdcard-files.zip"
    zip_dir(sdimg_dir, sd_files_zip)
    fat32_files = make_fat32_sd_files(sd_files)
    make_fat32_image(fat32_files, sdcard_dir / f"bakstaaj-{args.version}-sdcard.img", args.sd_image_mib)

    write_readme(release_dir, args.version)
    write_hashes(release_dir)
    release_zip = release_dir.parent / f"bakstaaj-{args.version}-release.zip"
    zip_dir(release_dir, release_zip)
    write_hashes(release_dir)

    print(f"Wrote {release_dir}")
    print(f"Wrote {release_zip}")


if __name__ == "__main__":
    main()
