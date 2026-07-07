#!/usr/bin/env bash
set -euo pipefail

files=(
	scripts/container-build-ethernet-async.sh
	buildroot/board/pluto/S21misc
	buildroot/board/pluto/S40network
	buildroot/board/pluto/S41network
	buildroot/board/pluto/S50dropbear
	buildroot/board/pluto/S98autostart
	buildroot/board/pluto/device_persistent_keys
	buildroot/board/pluto/ifupdown.sh
	buildroot/board/pluto/post-build.sh
	buildroot/board/pluto/pluto-sdcard-prepare
	buildroot/board/pluto/update.sh
	buildroot/board/pluto/update_frm.sh
	buildroot/board/pluto/msd/config.frm
	buildroot/board/pluto/mdev.conf
	buildroot/board/pluto/automounter.sh
	buildroot/board/pluto/pluto-eth-fallback
	buildroot/package/Config.in
	buildroot/package/python-sgp4/Config.in
	buildroot/package/python-sgp4/python-sgp4.hash
	buildroot/package/python-sgp4/python-sgp4.mk
	buildroot/configs/zynq_pluto_defconfig
	linux/arch/arm/boot/dts/zynq-pluto-sdr.dtsi
	linux/arch/arm/configs/zynq_pluto_defconfig
	u-boot-xlnx/include/configs/zynq-common.h
)

bash_bin="${BASH:-bash}"
tool_dir="${bash_bin%/*}"
export PATH="$tool_dir:$PATH"
sh_bin="$tool_dir/sh"

"$bash_bin" -n scripts/container-build-ethernet-async.sh
"$sh_bin" -n buildroot/board/pluto/S21misc
"$sh_bin" -n buildroot/board/pluto/S40network
"$sh_bin" -n buildroot/board/pluto/S41network
"$sh_bin" -n buildroot/board/pluto/S50dropbear
"$sh_bin" -n buildroot/board/pluto/S98autostart
"$sh_bin" -n buildroot/board/pluto/device_persistent_keys
"$sh_bin" -n buildroot/board/pluto/ifupdown.sh
"$sh_bin" -n buildroot/board/pluto/pluto-sdcard-prepare
"$sh_bin" -n buildroot/board/pluto/update.sh
"$sh_bin" -n buildroot/board/pluto/pluto-eth-fallback

crlf_report=".check-pluto-build-hygiene.crlf.$$"
: > "$crlf_report"
for file in "${files[@]}"; do
	if perl -ne 'exit 1 if /\r/' "$file"; then
		:
	else
		echo "$file" >> "$crlf_report"
	fi
done

if [ -s "$crlf_report" ]; then
	echo "CRLF line endings found:" >&2
	cat "$crlf_report" >&2
	exit 1
fi
rm -f "$crlf_report"

if [ ! -f buildroot/board/pluto/msd/LICENSE ] && [ ! -f buildroot/board/pluto/msd/LICENSE.html ]; then
	echo "Missing board/pluto MSD license source" >&2
	exit 1
fi

if [ ! -f scripts/FULL_DFU_UPDATE.bat ]; then
	echo "Missing Windows full DFU loader template" >&2
	exit 1
fi

if [ -d build-assets/pluto-plus-clg400 ]; then
	for asset in pluto-plus-source.frm pluto-plus-source.itb system_top.bit boot.frm boot.dfu SHA256SUMS.txt; do
		if [ ! -f "build-assets/pluto-plus-clg400/$asset" ]; then
			echo "Missing cached asset: build-assets/pluto-plus-clg400/$asset" >&2
			exit 1
		fi
	done
fi

echo "checks-ok"
