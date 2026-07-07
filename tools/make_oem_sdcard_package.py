#!/usr/bin/env python3
"""Build an OEM-boot-chain SD-card package for the SD-boot Pluto clone.

This uses the known-good OEM SD card boot chain:
- BOOT.bin from the OEM card
- uEnv.txt from the OEM card

Only the Linux payload is replaced:
- uImage from the selected local zImage
- devicetree.dtb from the selected local DTB
- uramdisk.image.gz from the selected local rootfs.cpio.gz
"""

from __future__ import annotations

import argparse
import binascii
import gzip
import hashlib
import shutil
import struct
import time
import zipfile
from pathlib import Path

FDT_MAGIC = 0xD00DFEED
FDT_BEGIN_NODE = 1
FDT_END_NODE = 2
FDT_PROP = 3
FDT_NOP = 4
FDT_END = 9
CPIO_NEWC_MAGIC = b"070701"
CPIO_NEWC_FIELDS = 13


def branded_motd(brand_name: str) -> bytes:
    text = f"""Welcome to:
 _           _     _____ _             _ _____ ____  ____
| |         | |   / ____| |           | / ____|  _ \\|  _ \\
| |__   __ _| | _| (___ | |_ __ _  __| | (___ | | | | |_) |
| '_ \\ / _` | |/ /\\___ \\| __/ _` |/ _` |\\___ \\| | | |  _ <
| |_) | (_| |   < ____) | || (_| | (_| |____) | |_| | |_) |
|_.__/ \\__,_|_|\\_\\_____/ \\__\\__,_|\\__,_|_____/|____/|____/
                         {brand_name}

#BUILD#
https://wiki.analog.com/university/tools/pluto
"""
    return text.encode("utf-8")


def usb_debug_script() -> bytes:
    text = """#!/bin/sh
echo "=== versions ==="
cat /opt/VERSIONS 2>/dev/null
echo
echo "=== fw env usb/network ==="
fw_printenv usb_ethernet_mode ipaddr ipaddr_host netmask 2>/dev/null || true
echo
echo "=== interfaces ==="
cat /etc/network/interfaces 2>/dev/null
echo
echo "=== ifconfig ==="
/sbin/ifconfig -a 2>/dev/null
echo
echo "=== udhcpd ==="
cat /etc/udhcpd.conf 2>/dev/null
ps | grep '[u]dhcpd' || true
echo
echo "=== gadget UDC ==="
G=/sys/kernel/config/usb_gadget/composite_gadget
cat $G/UDC 2>/dev/null || true
echo
echo "=== gadget functions ==="
ls -l $G/configs/c.1 2>/dev/null || true
for f in $G/functions/*; do
	[ -d "$f" ] || continue
	echo "--- $f ---"
	find "$f" -maxdepth 2 -type f 2>/dev/null | while read p; do
		echo "$p=$(cat "$p" 2>/dev/null)"
	done
done
echo
echo "=== recent usb/kernel log ==="
dmesg | grep -Ei 'usb|udc|rndis|ncm|ecm|gadget|dwc|ci_hdrc' | tail -80
"""
    return text.encode("utf-8")


def read_file(path: Path) -> bytes:
    with path.open("rb") as f:
        return f.read()


def write_file(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as f:
        f.write(data)


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


def align4(value: int) -> int:
    return (value + 3) & ~3


def get_fdt_string(strings: bytes, offset: int) -> str:
    end = strings.index(b"\x00", offset)
    return strings[offset:end].decode("ascii", errors="replace")


def patch_dtb_jffs2_layout(dtb: bytes, jffs2_size_mib: int) -> bytes:
    """Patch OEM DTB SPI flash partitions for a larger qspi-nvmfs partition."""
    if jffs2_size_mib < 1:
        raise ValueError("JFFS2 size must be at least 1 MiB")

    data = bytearray(dtb)
    header = struct.unpack_from(">10I", data, 0)
    magic, totalsize, off_dt_struct, off_dt_strings, _off_mem_rsvmap, _version, _last_comp, _boot_cpuid, size_dt_strings, size_dt_struct = header
    if magic != FDT_MAGIC:
        raise ValueError("Not a flattened device tree blob")

    strings = bytes(data[off_dt_strings : off_dt_strings + size_dt_strings])
    struct_end = off_dt_struct + size_dt_struct
    pos = off_dt_struct
    stack: list[dict[str, object]] = []
    patches = 0
    nvmfs_size = jffs2_size_mib * 1024 * 1024
    nvmfs_start = 0x120000
    flash_size = 0x1000000
    linux_start = nvmfs_start + nvmfs_size
    linux_size = flash_size - linux_start
    if linux_start >= flash_size:
        raise ValueError("JFFS2 size leaves no room for qspi-linux")
    if linux_start % 0x10000 != 0 or linux_size % 0x10000 != 0:
        raise ValueError("Partition layout is not erase-block aligned")

    while pos < struct_end:
        token = struct.unpack_from(">I", data, pos)[0]
        pos += 4
        if token == FDT_BEGIN_NODE:
            name_end = data.index(0, pos)
            name = bytes(data[pos:name_end]).decode("ascii", errors="replace")
            pos = align4(name_end + 1)
            stack.append({"name": name, "label": None})
        elif token == FDT_END_NODE:
            if stack:
                stack.pop()
        elif token == FDT_PROP:
            prop_len, nameoff = struct.unpack_from(">II", data, pos)
            pos += 8
            prop_name = get_fdt_string(strings, nameoff)
            value_pos = pos
            value = bytes(data[value_pos : value_pos + prop_len])
            pos = align4(value_pos + prop_len)
            if not stack:
                continue
            current = stack[-1]
            if prop_name == "label":
                current["label"] = value.rstrip(b"\x00").decode("ascii", errors="replace")
            elif prop_name == "reg" and prop_len == 8:
                label = current.get("label")
                if label == "qspi-nvmfs":
                    struct.pack_into(">II", data, value_pos, nvmfs_start, nvmfs_size)
                    patches += 1
                elif label == "qspi-linux":
                    struct.pack_into(">II", data, value_pos, linux_start, linux_size)
                    patches += 1
        elif token == FDT_NOP:
            continue
        elif token == FDT_END:
            break
        else:
            raise ValueError(f"Unexpected FDT token {token} at offset {pos - 4}")

    if patches != 2:
        raise ValueError(f"Expected to patch 2 partition regs, patched {patches}")
    return bytes(data[:totalsize])


def parse_newc_cpio(blob: bytes) -> list[dict[str, object]]:
    entries: list[dict[str, object]] = []
    pos = 0
    while pos + 110 <= len(blob):
        header = blob[pos : pos + 110]
        magic = header[:6]
        if magic != CPIO_NEWC_MAGIC:
            raise ValueError(f"Unsupported cpio magic at offset {pos}: {magic!r}")
        values = [
            int(header[6 + index * 8 : 14 + index * 8], 16)
            for index in range(CPIO_NEWC_FIELDS)
        ]
        pos += 110
        filesize = values[6]
        namesize = values[11]
        name_bytes = blob[pos : pos + namesize]
        name = name_bytes.rstrip(b"\x00").decode("utf-8", errors="replace")
        pos = align4(pos + namesize)
        data = blob[pos : pos + filesize]
        pos = align4(pos + filesize)
        entries.append({"magic": magic, "values": values, "name": name, "data": data})
        if name == "TRAILER!!!":
            break
    if not entries or entries[-1]["name"] != "TRAILER!!!":
        raise ValueError("cpio archive is missing TRAILER!!!")
    return entries


def pack_newc_cpio(entries: list[dict[str, object]]) -> bytes:
    out = bytearray()
    for entry in entries:
        values = list(entry["values"])
        name = str(entry["name"])
        data = bytes(entry["data"])
        name_bytes = name.encode("utf-8") + b"\x00"
        values[6] = len(data)
        values[11] = len(name_bytes)
        header = CPIO_NEWC_MAGIC + b"".join(f"{value:08x}".encode("ascii") for value in values)
        out += header
        out += name_bytes
        out += b"\x00" * (align4(len(out)) - len(out))
        out += data
        out += b"\x00" * (align4(len(out)) - len(out))
    return bytes(out)


def add_or_replace_cpio_file(
    entries: list[dict[str, object]],
    name: str,
    data: bytes,
    *,
    mode: int = 0o100644,
) -> None:
    for entry in entries:
        if entry["name"] == name:
            values = list(entry["values"])
            values[1] = mode
            entry["values"] = values
            entry["data"] = data
            return

    trailer_index = next(
        (index for index, entry in enumerate(entries) if entry["name"] == "TRAILER!!!"),
        len(entries),
    )
    entries.insert(
        trailer_index,
        {
            "magic": CPIO_NEWC_MAGIC,
            "values": [
                0,
                mode,
                0,
                0,
                1,
                int(time.time()),
                len(data),
                0,
                0,
                0,
                0,
                len(name.encode("utf-8")) + 1,
                0,
            ],
            "name": name,
            "data": data,
        },
    )


def add_or_replace_cpio_dir(
    entries: list[dict[str, object]],
    name: str,
    *,
    mode: int = 0o40755,
) -> None:
    name = name.rstrip("/")
    for entry in entries:
        if entry["name"] == name:
            values = list(entry["values"])
            values[1] = mode
            values[6] = 0
            entry["values"] = values
            entry["data"] = b""
            return

    trailer_index = next(
        (index for index, entry in enumerate(entries) if entry["name"] == "TRAILER!!!"),
        len(entries),
    )
    entries.insert(
        trailer_index,
        {
            "magic": CPIO_NEWC_MAGIC,
            "values": [
                0,
                mode,
                0,
                0,
                2,
                int(time.time()),
                0,
                0,
                0,
                0,
                0,
                len(name.encode("utf-8")) + 1,
                0,
            ],
            "name": name,
            "data": b"",
        },
    )


def patch_versions_file(data: bytes, fw_version: str) -> bytes:
    lines = data.decode("utf-8", errors="replace").splitlines()
    patched = False
    for index, line in enumerate(lines):
        if line.startswith("device-fw "):
            lines[index] = f"device-fw {fw_version}"
            patched = True
            break
    if not patched:
        lines.append(f"device-fw {fw_version}")
    return ("\n".join(lines) + "\n").encode("utf-8")


def patch_s98_for_web_settings(data: bytes) -> bytes:
    text = data.decode("utf-8", errors="replace")
    marker = "\t\tif test -f /mnt/jffs2/autorun.sh; then\n"
    insert = (
        "\t\tif test -x /usr/sbin/pluto-web-apply-settings; then\n"
        "\t\t\t/usr/sbin/pluto-web-apply-settings\n"
        "\t\tfi\n\n"
    )
    if "pluto-web-apply-settings" in text:
        return data
    if marker not in text:
        raise ValueError("Could not find S98autostart autorun marker")
    return text.replace(marker, insert + marker).encode("utf-8")


def inject_web_dashboard(entries: list[dict[str, object]], repo: Path) -> None:
    web_dir = repo / "buildroot" / "board" / "pluto" / "web"
    apply_script = repo / "buildroot" / "board" / "pluto" / "pluto-web-apply-settings"
    if not web_dir.exists():
        raise FileNotFoundError(web_dir)
    if not apply_script.exists():
        raise FileNotFoundError(apply_script)

    add_or_replace_cpio_dir(entries, "www")
    add_or_replace_cpio_dir(entries, "www/img")
    add_or_replace_cpio_dir(entries, "www/cgi-bin")
    add_or_replace_cpio_dir(entries, "usr")
    add_or_replace_cpio_dir(entries, "usr/sbin")

    add_or_replace_cpio_file(
        entries,
        "www/dashboard.html",
        read_file(web_dir / "dashboard.html"),
        mode=0o100644,
    )
    for path in sorted((web_dir / "img").iterdir()):
        if path.is_file():
            add_or_replace_cpio_file(
                entries,
                f"www/img/{path.name}",
                read_file(path),
                mode=0o100644,
            )
    for path in sorted((web_dir / "cgi-bin").iterdir()):
        if path.is_file():
            add_or_replace_cpio_file(
                entries,
                f"www/cgi-bin/{path.name}",
                read_file(path),
                mode=0o100755,
            )
    add_or_replace_cpio_file(
        entries,
        "usr/sbin/pluto-web-apply-settings",
        read_file(apply_script),
        mode=0o100755,
    )

    for entry in entries:
        if entry["name"] == "etc/init.d/S98autostart":
            entry["data"] = patch_s98_for_web_settings(bytes(entry["data"]))
            return
    raise ValueError("rootfs archive is missing etc/init.d/S98autostart")


def force_usb_mode_in_script(data: bytes, mode: str) -> bytes:
    text = data.decode("utf-8", errors="replace")
    old = "USB_ETH_MODE=`fw_printenv -n usb_ethernet_mode 2> /dev/null || echo rndis`"
    new = f"USB_ETH_MODE={mode}"
    if old not in text:
        raise ValueError("Could not find USB_ETH_MODE assignment to patch")
    return text.replace(old, new).encode("utf-8")


def disable_gadget_acm_in_s23udc(data: bytes) -> bytes:
    text = data.decode("utf-8", errors="replace")
    replacements = {
        "\tmkdir -p $GADGET/functions/acm.usb0\n": "",
        "\tln -s $GADGET/functions/acm.usb0 $GADGET/configs/c.1\n": "",
        "\trm $GADGET/configs/c.1/acm.usb0\n": "",
        "\t#rmdir $GADGET/functions/acm.usb0\n": "",
    }
    for old, new in replacements.items():
        text = text.replace(old, new)
    text = text.replace(
        'echo "RNDIS/MSD/ACM/IIOUSBD" > $GADGET/configs/c.1/strings/0x409/configuration',
        'echo "RNDIS/MSD/IIOUSBD" > $GADGET/configs/c.1/strings/0x409/configuration',
    )
    return text.encode("utf-8")


def disable_gadget_msd_in_s23udc(data: bytes) -> bytes:
    text = data.decode("utf-8", errors="replace")
    replacements = {
        "\tmkdir -p $GADGET/functions/mass_storage.0\n": "",
        "#\techo /opt/vfat.img > $GADGET/functions/mass_storage.0/lun.0/file\n": "",
        "\techo Y > $GADGET/functions/mass_storage.0/lun.0/removable\n": "",
        "\tln -s $GADGET/functions/mass_storage.0 $GADGET/configs/c.1\n": "",
        "\trm $GADGET/configs/c.1/mass_storage.0\n": "",
        "\trmdir $GADGET/functions/mass_storage.0\n": "",
    }
    for old, new in replacements.items():
        text = text.replace(old, new)
    text = text.replace(
        'echo "RNDIS/MSD/IIOUSBD" > $GADGET/configs/c.1/strings/0x409/configuration',
        'echo "RNDIS/IIOUSBD" > $GADGET/configs/c.1/strings/0x409/configuration',
    )
    text = text.replace(
        'echo "RNDIS/MSD/ACM/IIOUSBD" > $GADGET/configs/c.1/strings/0x409/configuration',
        'echo "RNDIS/ACM/IIOUSBD" > $GADGET/configs/c.1/strings/0x409/configuration',
    )
    return text.encode("utf-8")


def disable_iio_ffs_in_s23udc(data: bytes) -> bytes:
    text = data.decode("utf-8", errors="replace")
    replacements = {
        "\tmkdir -p $GADGET/functions/ffs.iio_ffs\n": "",
        "\tln -s $GADGET/functions/ffs.iio_ffs $GADGET/configs/c.1/ffs.iio_ffs\n": "",
        "\tmkdir -p /dev/iio_ffs\n": "",
        "\tmount iio_ffs -t functionfs /dev/iio_ffs 2> /dev/null\n": "",
        "\tstart-stop-daemon -S -b -q -m -p /var/run/iiod.pid -x  /usr/sbin/iiod  -- $IIOD_OPTS\n": "",
        "\tstart-stop-daemon -K -q -p /var/run/iiod.pid 2>/dev/null\n": "",
        "\trm $GADGET/configs/c.1/ffs.iio_ffs\n": "",
        "\trmdir $GADGET/functions/ffs.iio_ffs\n": "",
    }
    for old, new in replacements.items():
        text = text.replace(old, new)
    text = text.replace("/IIOUSBD", "")
    text = text.replace("IIOUSBD/", "")
    text = text.replace("IIOUSBD", "")
    return text.encode("utf-8")


def patch_s23_usb_identity(data: bytes, *, product: str | None, serial_suffix: str | None) -> bytes:
    text = data.decode("utf-8", errors="replace")
    if product:
        text = text.replace(
            'echo $PRODUCT > $GADGET/strings/0x409/product',
            f'echo "{product}" > $GADGET/strings/0x409/product',
        )
    if serial_suffix:
        marker = "serial=${serial#*SPI-NOR-UniqueID }\n"
        replacement = marker + f'serial="${{serial}}-{serial_suffix}"\n'
        if marker not in text:
            raise ValueError("Could not find serial extraction line to patch")
        text = text.replace(marker, replacement)
    return text.encode("utf-8")


def disabled_msd_script() -> bytes:
    text = """#!/bin/sh
case "$1" in
	start)
		echo -n "Starting MSD Daemon: disabled "
		BUILD=`grep device-fw /opt/VERSIONS | cut -d ' ' -f 2`
		sed -i -e "s/#BUILD#/$BUILD/g" /etc/motd 2>/dev/null
		echo "OK"
		;;
	stop)
		echo "Stopping MSD Daemon: disabled"
		;;
	restart)
		$0 stop
		$0 start
		;;
	*)
		echo "Usage: $0 {start|stop|restart}"
		exit 1
esac
"""
    return text.encode("utf-8")


def remove_ttygs0_getty(data: bytes) -> bytes:
    lines = data.decode("utf-8", errors="replace").splitlines()
    lines = [line for line in lines if "ttyGS0" not in line]
    return ("\n".join(lines) + "\n").encode("utf-8")


def patch_rootfs_cpio_gz(
    rootfs_gz: bytes,
    *,
    repo: Path,
    brand_name: str | None,
    fw_version: str | None,
    force_usb_ethernet_mode: str | None,
    disable_usb_acm: bool,
    disable_usb_msd: bool,
    install_usb_debug: bool,
    include_web_dashboard: bool,
) -> bytes:
    if not brand_name and not fw_version and not force_usb_ethernet_mode and not disable_usb_acm and not disable_usb_msd and not install_usb_debug and not include_web_dashboard:
        return rootfs_gz

    entries = parse_newc_cpio(gzip.decompress(rootfs_gz))
    changed = set()
    for entry in entries:
        name = str(entry["name"])
        if brand_name and name == "etc/motd":
            entry["data"] = branded_motd(brand_name)
            changed.add("etc/motd")
        if fw_version and name == "opt/VERSIONS":
            entry["data"] = patch_versions_file(bytes(entry["data"]), fw_version)
            changed.add("opt/VERSIONS")
        if force_usb_ethernet_mode and name in (
            "etc/init.d/S23udc",
            "etc/init.d/S40network",
            "etc/init.d/S45msd",
        ):
            entry["data"] = force_usb_mode_in_script(bytes(entry["data"]), force_usb_ethernet_mode)
            changed.add(name)
        if disable_usb_acm and name == "etc/init.d/S23udc":
            entry["data"] = disable_gadget_acm_in_s23udc(bytes(entry["data"]))
            changed.add("etc/init.d/S23udc:disable-acm")
        if disable_usb_msd and name == "etc/init.d/S23udc":
            entry["data"] = disable_gadget_msd_in_s23udc(bytes(entry["data"]))
            changed.add("etc/init.d/S23udc:disable-msd")
        if disable_usb_msd and name == "etc/init.d/S45msd":
            entry["data"] = disabled_msd_script()
            changed.add("etc/init.d/S45msd:disable-msd")
        if disable_usb_acm and name == "etc/inittab":
            entry["data"] = remove_ttygs0_getty(bytes(entry["data"]))
            changed.add("etc/inittab")

    if install_usb_debug:
        add_or_replace_cpio_file(
            entries,
            "usr/sbin/pluto-usb-debug",
            usb_debug_script(),
            mode=0o100755,
        )
        changed.add("usr/sbin/pluto-usb-debug")
    if include_web_dashboard:
        inject_web_dashboard(entries, repo)
        changed.add("web-dashboard")

    missing = []
    if brand_name and "etc/motd" not in changed:
        missing.append("etc/motd")
    if fw_version and "opt/VERSIONS" not in changed:
        missing.append("opt/VERSIONS")
    if force_usb_ethernet_mode:
        for path in ("etc/init.d/S23udc", "etc/init.d/S40network", "etc/init.d/S45msd"):
            if path not in changed:
                missing.append(path)
    if disable_usb_acm:
        for path in ("etc/init.d/S23udc:disable-acm", "etc/inittab"):
            if path not in changed:
                missing.append(path)
    if disable_usb_msd:
        for path in ("etc/init.d/S23udc:disable-msd", "etc/init.d/S45msd:disable-msd"):
            if path not in changed:
                missing.append(path)
    if install_usb_debug and "usr/sbin/pluto-usb-debug" not in changed:
        missing.append("usr/sbin/pluto-usb-debug")
    if include_web_dashboard and "web-dashboard" not in changed:
        missing.append("web-dashboard")
    if missing:
        raise ValueError(f"rootfs archive is missing required path(s): {', '.join(missing)}")

    return gzip.compress(pack_newc_cpio(entries), compresslevel=9, mtime=0)


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def copy_payload(out_sdimg: Path, files: dict[str, bytes]) -> None:
    out_sdimg.mkdir(parents=True, exist_ok=True)
    for child in out_sdimg.iterdir():
        if child.is_file():
            child.unlink()
    for name, data in files.items():
        write_file(out_sdimg / name, data)


def zip_tree(src_dir: Path, zip_path: Path) -> None:
    if zip_path.exists():
        zip_path.unlink()
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for path in sorted(src_dir.rglob("*")):
            if path.is_file():
                zf.write(path, path.relative_to(src_dir.parent))


def write_readme(
    out_dir: Path,
    oem_dir: Path,
    source_dir: Path,
    jffs2_size_mib: int | None,
    brand_name: str | None,
    fw_version: str | None,
    force_usb_ethernet_mode: str | None,
    disable_usb_acm: bool,
    disable_usb_msd: bool,
    install_usb_debug: bool,
    include_web_dashboard: bool,
) -> None:
    if jffs2_size_mib:
        jffs2_size_hex = f"{jffs2_size_mib * 1024 * 1024:08x}"
        dtb_note = (
            f"devicetree.dtb: copied from OEM DTB and patched so qspi-nvmfs is {jffs2_size_mib} MiB"
        )
        verify_note = (
            f"Expected /proc/mtd after boot: mtd2 size {jffs2_size_hex} for qspi-nvmfs."
        )
    else:
        dtb_note = "devicetree.dtb: copied from local verify-zynq-pluto-sdr.dtb"
        verify_note = "Expected /proc/mtd depends on the local DTB partition layout."
    branding_note = []
    if brand_name:
        branding_note.append(f"- Login banner: {brand_name}")
    if fw_version:
        branding_note.append(f"- Firmware version: {fw_version}")
    branding_text = "\n".join(branding_note) if branding_note else "- None"
    usb_note = []
    if force_usb_ethernet_mode:
        usb_note.append(f"- USB ethernet mode forced to {force_usb_ethernet_mode}")
    if disable_usb_acm:
        usb_note.append("- USB gadget ACM serial disabled; use the JTAG USB serial console")
    if disable_usb_msd:
        usb_note.append("- USB mass-storage gadget disabled; no Pluto config drive will appear")
    if install_usb_debug:
        usb_note.append("- Serial diagnostic command installed: pluto-usb-debug")
    usb_text = "\n".join(usb_note) if usb_note else "- Stock Pluto USB gadget behavior"
    web_text = (
        "- Pluto dashboard installed at http://192.168.2.1/dashboard.html"
        if include_web_dashboard
        else "- None"
    )
    text = f"""OEM Pluto SD-card Package

This package keeps the known-good OEM boot chain and replaces only the Linux
payload files.

Source directories:

- OEM boot files: {oem_dir}
- Local firmware files: {source_dir}

SD card root files:

- BOOT.bin: copied unchanged from OEM SD card
- uEnv.txt: copied unchanged from OEM SD card
- uImage: generated from local zImage as an uncompressed legacy U-Boot image
- {dtb_note}
- uramdisk.image.gz: generated from local rootfs.cpio.gz as a gzip-compressed legacy U-Boot ramdisk image

Branding:

{branding_text}

USB behavior:

{usb_text}

Web additions:

{web_text}

Install:

1. Format a spare SD card as FAT32.
2. Copy the contents of sdimg to the root of the SD card.
3. Set the board BOOT switches to SD.
4. Boot using the OTG port for normal USB/network operation and JTAG USB for serial console.

If this fails, capture the serial console from power-on through the U-Boot or
kernel error. The OEM BOOT.bin and uEnv.txt are intentionally unchanged, so a
failure should be in the kernel, DTB, ramdisk size/load, or userspace payload.

Verification:

{verify_note}
"""
    write_file(out_dir / "README.txt", text.encode("utf-8"))


def write_hashes(out_dir: Path) -> None:
    lines = []
    for path in sorted((out_dir / "sdimg").iterdir()):
        if path.is_file():
            lines.append(f"{sha256_file(path)}  sdimg/{path.name}")
    zip_path = out_dir.parent / f"{out_dir.name}.zip"
    if zip_path.exists():
        lines.append(f"{sha256_file(zip_path)}  {zip_path.name}")
    write_file(out_dir / "SHA256SUMS.txt", ("\n".join(lines) + "\n").encode("utf-8"))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path.cwd())
    parser.add_argument("--oem-dir", type=Path, default=Path(r"C:\tmp\oem-pluto-sd"))
    parser.add_argument(
        "--source-dir",
        type=Path,
        default=Path("build-large-jffs3-sdcard-ethernet-pluto-plus"),
    )
    parser.add_argument("--out-dir", type=Path, default=Path("build-oem-pluto-sdcard-package"))
    parser.add_argument(
        "--oem-dtb",
        action="store_true",
        help="Use OEM devicetree.dtb instead of local verify-zynq-pluto-sdr.dtb",
    )
    parser.add_argument(
        "--jffs2-size-mib",
        type=int,
        default=None,
        help="Patch qspi-nvmfs in the selected DTB to this MiB size",
    )
    parser.add_argument(
        "--brand-name",
        default=None,
        help="Replace /etc/motd in the ramdisk with this login banner name",
    )
    parser.add_argument(
        "--fw-version",
        default=None,
        help="Replace the device-fw entry in /opt/VERSIONS inside the ramdisk",
    )
    parser.add_argument(
        "--force-usb-ethernet-mode",
        choices=("rndis", "ncm", "ecm"),
        default=None,
        help="Force the USB network gadget mode instead of reading fw_printenv",
    )
    parser.add_argument(
        "--disable-usb-acm",
        action="store_true",
        help="Disable the OTG USB serial gadget so only the JTAG USB console appears",
    )
    parser.add_argument(
        "--disable-usb-msd",
        action="store_true",
        help="Disable the USB mass-storage gadget so no Pluto config drive appears",
    )
    parser.add_argument(
        "--install-usb-debug",
        action="store_true",
        help="Install /usr/sbin/pluto-usb-debug into the ramdisk",
    )
    parser.add_argument(
        "--include-web-dashboard",
        action="store_true",
        help="Inject the Pluto dashboard web UI, CGI endpoints, and persistent settings applier",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    repo = args.repo.resolve()
    oem_dir = args.oem_dir.resolve()
    source_dir = args.source_dir if args.source_dir.is_absolute() else repo / args.source_dir
    source_dir = source_dir.resolve()
    out_dir = args.out_dir if args.out_dir.is_absolute() else repo / args.out_dir
    out_dir = out_dir.resolve()
    out_sdimg = out_dir / "sdimg"

    required_oem = ["BOOT.bin", "uEnv.txt"]
    for name in required_oem:
        path = oem_dir / name
        if not path.exists():
            raise FileNotFoundError(path)

    local_zimage = source_dir / "zImage"
    local_dtb = source_dir / "verify-zynq-pluto-sdr.dtb"
    local_rootfs = source_dir / "rootfs.cpio.gz"
    for path in (local_zimage, local_rootfs):
        if not path.exists():
            raise FileNotFoundError(path)
    if not args.oem_dtb and not local_dtb.exists():
        raise FileNotFoundError(local_dtb)

    dtb = read_file(oem_dir / "devicetree.dtb") if args.oem_dtb else read_file(local_dtb)
    if args.jffs2_size_mib:
        dtb = patch_dtb_jffs2_layout(dtb, args.jffs2_size_mib)

    rootfs = patch_rootfs_cpio_gz(
        read_file(local_rootfs),
        repo=repo,
        brand_name=args.brand_name,
        fw_version=args.fw_version,
        force_usb_ethernet_mode=args.force_usb_ethernet_mode,
        disable_usb_acm=args.disable_usb_acm,
        disable_usb_msd=args.disable_usb_msd,
        install_usb_debug=args.install_usb_debug,
        include_web_dashboard=args.include_web_dashboard,
    )

    files = {
        "BOOT.bin": read_file(oem_dir / "BOOT.bin"),
        "uEnv.txt": read_file(oem_dir / "uEnv.txt"),
        "uImage": make_uimage(
            read_file(local_zimage),
            name="PlutoSDR zImage",
            image_type=2,  # IH_TYPE_KERNEL
            compression=0,  # IH_COMP_NONE
            load=0x8000,
            entry=0x8000,
        ),
        "devicetree.dtb": dtb,
        "uramdisk.image.gz": make_uimage(
            rootfs,
            name="PlutoSDR rootfs",
            image_type=3,  # IH_TYPE_RAMDISK
            compression=1,  # IH_COMP_GZIP
            load=0,
            entry=0,
        ),
    }

    copy_payload(out_sdimg, files)
    write_readme(
        out_dir,
        oem_dir,
        source_dir,
        args.jffs2_size_mib,
        args.brand_name,
        args.fw_version,
        args.force_usb_ethernet_mode,
        args.disable_usb_acm,
        args.disable_usb_msd,
        args.install_usb_debug,
        args.include_web_dashboard,
    )
    zip_path = out_dir.parent / f"{out_dir.name}.zip"
    zip_tree(out_dir, zip_path)
    write_hashes(out_dir)

    print(f"Wrote {out_dir}")
    print(f"Wrote {zip_path}")


if __name__ == "__main__":
    main()
