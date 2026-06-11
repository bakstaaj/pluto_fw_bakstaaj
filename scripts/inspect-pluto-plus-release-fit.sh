#!/usr/bin/env bash
set -euo pipefail

cd /home/jim/sdrdev/pluto_fw_bakstaaj

unzip -o build/pluto-plus-release/plutosdr-fw-v0.39-pluto-plus.1.zip pluto.frm -d build/pluto-plus-release >/dev/null
size=$(stat -c%s build/pluto-plus-release/pluto.frm)
head -c "$((size - 33))" build/pluto-plus-release/pluto.frm > build/pluto-plus-release/pluto.itb
file build/pluto-plus-release/pluto.itb

if [[ -x u-boot-xlnx/tools/dumpimage ]]; then
  u-boot-xlnx/tools/dumpimage -l build/pluto-plus-release/pluto.itb
else
  echo no-dumpimage
fi
