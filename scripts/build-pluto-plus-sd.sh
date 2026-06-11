#!/usr/bin/env bash
set -u

cd /home/jim/sdrdev/pluto_fw_bakstaaj

docker run --rm --user 1000:1000 \
  -v /opt/Xilinx:/opt/Xilinx:ro \
  -v /home/jim/sdrdev/pluto_fw_bakstaaj:/work \
  -v pluto-fw-dl:/dl \
  -v pluto-fw-ccache:/ccache \
  -w /work \
  -e HOME=/tmp \
  -e BR2_DL_DIR=/dl \
  -e CCACHE_DIR=/ccache \
  -e VIVADO_SETTINGS=/xilinx-2023.2-settings.sh \
  pluto-fw-v039 \
  bash -lc '
    source /xilinx-2023.2-settings.sh &&
    git config --global --add safe.directory /work &&
    make clean-build &&
    make -C hdl/projects/pluto clean &&
    make -C hdl/projects/pluto &&
    mkdir -p build &&
    cp hdl/projects/pluto/pluto.sdk/system_top.xsa build/system_top.xsa &&
    unzip -l build/system_top.xsa | grep -q ps7_init || cp hdl/projects/pluto/pluto.srcs/sources_1/bd/system/ip/system_sys_ps7_0/ps7_init* build/ &&
    make TARGET=pluto SKIP_LEGAL=1 VIVADO_SETTINGS=/xilinx-2023.2-settings.sh build/boot.frm build/boot.dfu build/pluto.frm build/pluto.dfu build/uboot-env.dfu build/config.frm zip-all
  '
