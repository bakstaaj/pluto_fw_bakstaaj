#!/usr/bin/env bash
set -euo pipefail

files=(
	scripts/container-build-ethernet-async.sh
	buildroot/board/pluto/S21misc
	buildroot/board/pluto/S40network
	buildroot/board/pluto/S41network
	buildroot/board/pluto/S50dropbear
	buildroot/board/pluto/S70pluto-radio-api
	buildroot/board/pluto/S98autostart
	buildroot/board/pluto/device_persistent_keys
	buildroot/board/pluto/ifupdown.sh
	buildroot/board/pluto/lighttpd.conf
	buildroot/board/pluto/post-build.sh
	buildroot/board/pluto/pluto-sdcard-prepare
	buildroot/board/pluto/update.sh
	buildroot/board/pluto/update_frm.sh
	buildroot/board/pluto/msd/config.frm
	buildroot/board/pluto/mdev.conf
	buildroot/board/pluto/automounter.sh
	buildroot/board/pluto/pluto-eth-fallback
	buildroot/board/pluto/pluto-radio-api
	buildroot/board/pluto/pluto-audio-backend
	buildroot/board/pluto/pluto-audio-dsp/pluto-audio-backend.c
	buildroot/board/pluto/pluto-audio-dsp/pluto-ft8-decoder.c
	buildroot/board/pluto/pluto-audio-dsp/pluto-ft8-decoder.h
	buildroot/board/pluto/pluto-audio-dsp/pluto-loopback-backend.c
	buildroot/board/pluto/pluto-audio-dsp/pluto-spectrum-backend.c
	buildroot/board/pluto/pluto-audio-sim-backend
	buildroot/board/pluto/pluto-doppler-worker
	buildroot/board/pluto/pluto-radio/profiles/*.json
	buildroot/board/pluto/web/api-test.html
	buildroot/board/pluto/web/dashboard.html
	buildroot/board/pluto/web/img/pluto-api-test.js
	buildroot/board/pluto/web/img/pluto-dashboard.css
	buildroot/package/pluto-audio-dsp/Config.in
	buildroot/package/pluto-audio-dsp/pluto-audio-dsp.mk
	buildroot/package/ft8-lib/Config.in
	buildroot/package/ft8-lib/ft8-lib.hash
	buildroot/package/ft8-lib/ft8-lib.mk
	buildroot/package/liquid-dsp/liquid-dsp.mk
	scripts/validate-pluto-radio-api.sh
	scripts/check-firmware-size-budget.py
	tools/make_plutoplus_sdcard_image.py
	tools/make_oem_sdcard_package.py
	examples/README.md
	examples/python/pluto_radio_client.py
	examples/browser/pluto-radio-client.html
	buildroot/package/Config.in
	buildroot/package/python-sgp4/Config.in
	buildroot/package/python-sgp4/python-sgp4.hash
	buildroot/package/python-sgp4/python-sgp4.mk
	buildroot/configs/zynq_pluto_defconfig
	docs/firmware-api-contract.md
	docs/firmware-radio-appliance-architecture.md
	linux/arch/arm/boot/dts/zynq-pluto-sdr.dtsi
	linux/arch/arm/configs/zynq_pluto_defconfig
	u-boot-xlnx/include/configs/zynq-common.h
)

no_legacy_web_files=(
	README.md
	docs/firmware-api-contract.md
	docs/firmware-radio-appliance-architecture.md
	buildroot/board/pluto/lighttpd.conf
	buildroot/board/pluto/pluto-radio-api
	buildroot/board/pluto/web/api-test.html
	buildroot/board/pluto/web/img/pluto-api-test.js
	buildroot/board/pluto/web/img/pluto-dashboard.js
	scripts/validate-pluto-radio-api.sh
	tools/make_oem_sdcard_package.py
)
legacy_web_token="c""gi"

bash_bin="${BASH:-bash}"
tool_dir="${bash_bin%/*}"
export PATH="$tool_dir:$PATH"
sh_bin="$tool_dir/sh"
python_bin="${PYTHON:-python3}"
if ! command -v "$python_bin" >/dev/null 2>&1; then
	python_bin=python
fi

python_syntax() {
	"$python_bin" - "$1" <<'PY'
import ast
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
PY
}

"$bash_bin" -n scripts/container-build-ethernet-async.sh
"$sh_bin" -n buildroot/board/pluto/S21misc
"$sh_bin" -n buildroot/board/pluto/S40network
"$sh_bin" -n buildroot/board/pluto/S41network
"$sh_bin" -n buildroot/board/pluto/S50dropbear
"$sh_bin" -n buildroot/board/pluto/S70pluto-radio-api
"$sh_bin" -n buildroot/board/pluto/S98autostart
"$sh_bin" -n buildroot/board/pluto/device_persistent_keys
"$sh_bin" -n buildroot/board/pluto/ifupdown.sh
"$sh_bin" -n buildroot/board/pluto/pluto-sdcard-prepare
"$sh_bin" -n buildroot/board/pluto/update.sh
"$sh_bin" -n buildroot/board/pluto/pluto-eth-fallback
"$bash_bin" -n scripts/validate-pluto-radio-api.sh
python_syntax buildroot/board/pluto/pluto-radio-api
python_syntax buildroot/board/pluto/pluto-audio-backend
python_syntax buildroot/board/pluto/pluto-audio-sim-backend
python_syntax scripts/check-firmware-size-budget.py
python_syntax tools/make_plutoplus_sdcard_image.py
python_syntax examples/python/pluto_radio_client.py
"$sh_bin" -n buildroot/board/pluto/pluto-doppler-worker
grep -q 'proxy.server' buildroot/board/pluto/lighttpd.conf
if grep -q '=~' buildroot/board/pluto/lighttpd.conf; then
	echo "lighttpd.conf must avoid PCRE-dependent regex conditions" >&2
	exit 1
fi
if [ -e "buildroot/board/pluto/web/${legacy_web_token}-bin" ]; then
	echo "Legacy web script path must not be packaged" >&2
	exit 1
fi
if grep -R -n -i "$legacy_web_token" "${no_legacy_web_files[@]}"; then
	echo "Legacy web script references found in current API contract files" >&2
	exit 1
fi

if ! grep -q 'LIQUID_DSP_CFLAGS += -mcpu=cortex-a9 -mfpu=neon -mfloat-abi=hard' \
	buildroot/package/liquid-dsp/liquid-dsp.mk; then
	echo "Missing Cortex-A9 liquid-dsp CPU/FPU guardrail" >&2
	exit 1
fi
if ! grep -q 'LIQUID_DSP_CONF_OPTS += --enable-simdoverride' \
	buildroot/package/liquid-dsp/liquid-dsp.mk; then
	echo "Missing liquid-dsp SIMD override guardrail" >&2
	exit 1
fi

crlf_report="${TMPDIR:-/tmp}/check-pluto-build-hygiene.crlf.$$"
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
