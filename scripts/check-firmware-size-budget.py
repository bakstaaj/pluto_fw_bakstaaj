#!/usr/bin/env python3
"""Check Pluto firmware artifact sizes against conservative budgets."""

import os
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


CHECKS = (
    (
        "rootfs",
        (
            "buildroot/output/images/rootfs.cpio.gz",
            "build/rootfs.cpio.gz",
            "build-*-fw*/rootfs.cpio.gz",
        ),
        "PLUTO_MAX_ROOTFS_GZ_BYTES",
        20 * 1024 * 1024,
    ),
    ("itb", ("build/pluto.itb", "build-*-fw*/pluto.itb"), "PLUTO_MAX_ITB_BYTES", 24 * 1024 * 1024),
    ("frm", ("build/pluto.frm", "build-*-fw*/pluto.frm"), "PLUTO_MAX_FRM_BYTES", 24 * 1024 * 1024),
    ("dfu", ("build/pluto.dfu", "build-*-fw*/pluto.dfu"), "PLUTO_MAX_DFU_BYTES", 24 * 1024 * 1024),
    ("sdcard-package", ("build-oem-pluto-sdcard-package*.zip",), "PLUTO_MAX_SDCARD_PACKAGE_BYTES", 24 * 1024 * 1024),
)


CUSTOM_PAYLOADS = (
    "buildroot/board/pluto/pluto-radio-api",
    "buildroot/board/pluto/pluto-audio-backend",
    "buildroot/board/pluto/pluto-audio-dsp/pluto-audio-backend.c",
    "buildroot/board/pluto/pluto-audio-dsp/pluto-loopback-backend.c",
    "buildroot/board/pluto/pluto-audio-dsp/pluto-spectrum-backend.c",
    "buildroot/board/pluto/pluto-audio-sim-backend",
    "buildroot/board/pluto/pluto-doppler-worker",
    "buildroot/board/pluto/web/*.html",
    "buildroot/board/pluto/web/img/pluto-*.css",
    "buildroot/board/pluto/web/img/pluto-*.js",
    "buildroot/package/pluto-audio-dsp/*",
    "buildroot/board/pluto/S70pluto-radio-api",
    "buildroot/board/pluto/pluto-radio/profiles/*.json",
)


def budget(name, default):
    value = os.environ.get(name)
    if not value:
        return default
    try:
        return int(value)
    except ValueError:
        raise SystemExit(f"{name} must be an integer byte count")


def fmt_size(size):
    return f"{size} bytes ({size / (1024 * 1024):.2f} MiB)"


def expand(patterns):
    paths = []
    for pattern in patterns:
        matches = sorted(ROOT.glob(pattern))
        if matches:
            paths.extend(matches)
    return paths


def custom_payload_size():
    total = 0
    files = []
    for path in expand(CUSTOM_PAYLOADS):
        if path.is_file():
            total += path.stat().st_size
            files.append(path)
    return total, files


def main():
    failures = []
    print("Firmware size budget check")
    print("==========================")

    payload_total, payload_files = custom_payload_size()
    print(f"custom-radio-api-payload: {fmt_size(payload_total)} across {len(payload_files)} files")

    for label, patterns, env_name, default_limit in CHECKS:
        limit = budget(env_name, default_limit)
        paths = expand(patterns)
        if not paths:
            print(f"{label}: missing, limit {fmt_size(limit)}")
            continue
        for path in paths:
            size = path.stat().st_size
            rel = path.relative_to(ROOT)
            status = "OK" if size <= limit else "FAIL"
            print(f"{label}: {rel} {fmt_size(size)} / limit {fmt_size(limit)} [{status}]")
            if size > limit:
                failures.append((label, rel, size, limit))

    if failures:
        print()
        print("Size budget failures:")
        for label, rel, size, limit in failures:
            print(f"- {label}: {rel} is {fmt_size(size)}, over {fmt_size(limit)}")
        return 1

    print("size-budget-ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
