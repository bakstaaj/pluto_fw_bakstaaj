#!/usr/bin/env bash
set -euo pipefail

cd /home/jim/sdrdev/pluto_fw_bakstaaj

out="/mnt/c/Users/jim/OneDrive/Documents/Pluto Firmware/build-sdcard-fw-plutoplus-clg400"
mkdir -p "$out"

u-boot-xlnx/tools/dumpimage -i build/pluto.itb -T flat_dt -p 0 -o build/verify-zynq-pluto-sdr.dtb build/verify-zynq-pluto-sdr.dtb >/dev/null
linux/scripts/dtc/dtc -I dtb -O dts build/verify-zynq-pluto-sdr.dtb > build/verify-zynq-pluto-sdr.dts

cp build/boot.frm \
   build/boot.dfu \
   build/pluto.frm \
   build/pluto.dfu \
   build/uboot-env.dfu \
   build/config.frm \
   build/plutosdr-fw-v0.39-pluto-plus.1-dirty.zip \
   "$out/"

(
  cd "$out"
  python3 - <<'PY'
import zipfile

names = ["boot.frm", "boot.dfu", "pluto.frm", "pluto.dfu", "uboot-env.dfu", "config.frm"]
with zipfile.ZipFile("plutosdr-fw-plutoplus-sdcard-clg400-complete.zip", "w", zipfile.ZIP_DEFLATED) as zf:
    for name in names:
        zf.write(name, name)
PY
  sha256sum boot.frm boot.dfu pluto.frm pluto.dfu uboot-env.dfu config.frm \
    plutosdr-fw-v0.39-pluto-plus.1-dirty.zip \
    plutosdr-fw-plutoplus-sdcard-clg400-complete.zip > SHA256SUMS.txt
)

echo "Artifacts:"
ls -lh "$out"
echo
echo "SDHCI verification:"
grep -n -A35 'mmc@e0100000' build/verify-zynq-pluto-sdr.dts || grep -n -A35 'sdhci' build/verify-zynq-pluto-sdr.dts
