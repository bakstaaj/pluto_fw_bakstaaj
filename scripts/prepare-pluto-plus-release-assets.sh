#!/usr/bin/env bash
set -euo pipefail

cd /home/jim/sdrdev/pluto_fw_bakstaaj

release_dir=build/pluto-plus-release
mkdir -p "$release_dir" build

python3 - <<'PY'
import pathlib
import urllib.request

base = "https://github.com/bakstaaj/pluto_fw_bakstaaj/releases/download/v0.39-pluto-plus.1"
release_dir = pathlib.Path("build/pluto-plus-release")
for name in ("plutosdr-fw-v0.39-pluto-plus.1.zip", "boot.frm", "boot.dfu"):
    target = release_dir / name
    if not target.exists():
        urllib.request.urlretrieve(f"{base}/{name}", target)
    print(target)
PY

unzip -o "$release_dir/plutosdr-fw-v0.39-pluto-plus.1.zip" pluto.frm -d "$release_dir" >/dev/null
size=$(stat -c%s "$release_dir/pluto.frm")
head -c "$((size - 33))" "$release_dir/pluto.frm" > "$release_dir/pluto.itb"

u-boot-xlnx/tools/dumpimage -i "$release_dir/pluto.itb" -T flat_dt -p 3 -o build/system_top.bit build/system_top.bit
cp "$release_dir/boot.frm" build/boot.frm
cp "$release_dir/boot.dfu" build/boot.dfu

ls -l build/system_top.bit build/boot.frm build/boot.dfu
