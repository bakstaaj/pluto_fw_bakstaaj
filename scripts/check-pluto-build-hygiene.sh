#!/usr/bin/env bash
set -euo pipefail

files=(
	scripts/container-build-ethernet-async.sh
	buildroot/board/pluto/S40network
	buildroot/board/pluto/S41network
	buildroot/board/pluto/ifupdown.sh
	buildroot/board/pluto/post-build.sh
	buildroot/board/pluto/update.sh
	buildroot/board/pluto/update_frm.sh
	buildroot/board/pluto/msd/config.frm
	buildroot/board/pluto/mdev.conf
	buildroot/board/pluto/automounter.sh
	buildroot/board/pluto/pluto-eth-fallback
	linux/arch/arm/boot/dts/zynq-pluto-sdr.dtsi
	linux/arch/arm/configs/zynq_pluto_defconfig
)

bash -n scripts/container-build-ethernet-async.sh
sh -n buildroot/board/pluto/S41network
sh -n buildroot/board/pluto/ifupdown.sh
sh -n buildroot/board/pluto/pluto-eth-fallback

crlf_report="$(mktemp)"
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

if [ -d build-assets/pluto-plus-clg400 ]; then
	for asset in pluto-plus-source.frm pluto-plus-source.itb system_top.bit boot.frm boot.dfu SHA256SUMS.txt; do
		if [ ! -f "build-assets/pluto-plus-clg400/$asset" ]; then
			echo "Missing cached asset: build-assets/pluto-plus-clg400/$asset" >&2
			exit 1
		fi
	done
fi

echo "checks-ok"
