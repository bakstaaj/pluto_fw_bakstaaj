#!/usr/bin/env bash
set -euo pipefail

cd /work/src

target_name="pluto"
package_label="ethernet-async"
default_out="/host/build-ethernet-async-fw-plutoplus-clg400"
asset_dir="${ASSET_DIR:-/host/build-assets/pluto-plus-clg400}"
out="${OUT_DIR:-$default_out}"
release_dir="build/pluto-plus-release"
source_frm="$release_dir/pluto.frm"
source_itb="$release_dir/pluto.itb"

git config --global --add safe.directory /work/src
git config --global --add safe.directory /work/src/buildroot
git config --global --add safe.directory /work/src/linux
git config --global --add safe.directory /work/src/hdl
git config --global --add safe.directory /work/src/u-boot-xlnx

patched_files=(
	buildroot/board/pluto/S40network \
	buildroot/board/pluto/S41network \
	buildroot/board/pluto/ifupdown.sh \
	buildroot/board/pluto/post-build.sh \
	buildroot/board/pluto/update.sh \
	buildroot/board/pluto/update_frm.sh \
	buildroot/board/pluto/msd/config.frm \
	buildroot/board/pluto/mdev.conf \
	buildroot/board/pluto/automounter.sh \
	buildroot/board/pluto/pluto-eth-fallback \
	linux/arch/arm/boot/dts/zynq-pluto-sdr.dtsi \
	linux/arch/arm/configs/zynq_pluto_defconfig
)

mkdir -p "$release_dir" build "$asset_dir" "$out"

cp /host/buildroot/board/pluto/S40network buildroot/board/pluto/S40network
cp /host/buildroot/board/pluto/S41network buildroot/board/pluto/S41network
cp /host/buildroot/board/pluto/ifupdown.sh buildroot/board/pluto/ifupdown.sh
cp /host/buildroot/board/pluto/post-build.sh buildroot/board/pluto/post-build.sh
cp /host/buildroot/board/pluto/update.sh buildroot/board/pluto/update.sh
cp /host/buildroot/board/pluto/update_frm.sh buildroot/board/pluto/update_frm.sh
cp /host/buildroot/board/pluto/msd/config.frm buildroot/board/pluto/msd/config.frm
cp /host/buildroot/board/pluto/mdev.conf buildroot/board/pluto/mdev.conf
cp /host/buildroot/board/pluto/automounter.sh buildroot/board/pluto/automounter.sh
cp /host/buildroot/board/pluto/pluto-eth-fallback buildroot/board/pluto/pluto-eth-fallback
cp /host/linux/arch/arm/boot/dts/zynq-pluto-sdr.dtsi linux/arch/arm/boot/dts/zynq-pluto-sdr.dtsi
cp /host/linux/arch/arm/configs/zynq_pluto_defconfig linux/arch/arm/configs/zynq_pluto_defconfig

perl -pi -e 's/\r$//' "${patched_files[@]}"

crlf_report="$(mktemp)"
if grep -Il $'\r' "${patched_files[@]}" > "$crlf_report"; then
	if [ -s "$crlf_report" ]; then
		echo "CRLF line endings remain after normalization:" >&2
		cat "$crlf_report" >&2
		exit 1
	fi
fi
rm -f "$crlf_report"

chmod +x \
	buildroot/board/pluto/S40network \
	buildroot/board/pluto/S41network \
	buildroot/board/pluto/ifupdown.sh \
	buildroot/board/pluto/update.sh \
	buildroot/board/pluto/update_frm.sh \
	buildroot/board/pluto/automounter.sh \
	buildroot/board/pluto/pluto-eth-fallback

if [ ! -f buildroot/board/pluto/msd/LICENSE.html ]; then
	echo "Creating board/pluto MSD LICENSE.html for SKIP_LEGAL=1 build"
	cp buildroot/board/pluto/msd/LICENSE buildroot/board/pluto/msd/LICENSE.html
fi

if [ -f "$asset_dir/pluto-plus-source.frm" ]; then
	cp "$asset_dir/pluto-plus-source.frm" "$source_frm"
elif [ ! -f "$source_frm" ]; then
	cp /host/build-sdcard-fw-plutoplus-clg400/pluto.frm "$source_frm"
fi
if [ ! -f build/boot.frm ]; then
	if [ -f "$asset_dir/boot.frm" ]; then
		cp "$asset_dir/boot.frm" build/boot.frm
	else
		cp /host/build-sdcard-fw-plutoplus-clg400/boot.frm build/boot.frm
	fi
fi
if [ ! -f build/boot.dfu ]; then
	if [ -f "$asset_dir/boot.dfu" ]; then
		cp "$asset_dir/boot.dfu" build/boot.dfu
	else
		cp /host/build-sdcard-fw-plutoplus-clg400/boot.dfu build/boot.dfu
	fi
fi

cp "$source_frm" "$asset_dir/pluto-plus-source.frm"
cp build/boot.frm "$asset_dir/boot.frm"
cp build/boot.dfu "$asset_dir/boot.dfu"

if [ -f "$asset_dir/system_top.bit" ] && [ "${REFRESH_BIT:-0}" != "1" ]; then
	cp "$asset_dir/system_top.bit" build/system_top.bit
else
	make -C u-boot-xlnx sandbox_defconfig >/tmp/u-boot-defconfig.log
	make -C u-boot-xlnx tools >/tmp/u-boot-tools.log

	size=$(stat -c%s "$source_frm")
	head -c "$((size - 33))" "$source_frm" > "$source_itb"
	u-boot-xlnx/tools/dumpimage \
		-i "$source_itb" \
		-T flat_dt \
		-p 3 \
		-o build/system_top.bit \
		build/system_top.bit

	cp "$source_itb" "$asset_dir/pluto-plus-source.itb"
	cp build/system_top.bit "$asset_dir/system_top.bit"
fi

if [ ! -f "$source_itb" ]; then
	size=$(stat -c%s "$source_frm")
	head -c "$((size - 33))" "$source_frm" > "$source_itb"
fi
cp "$source_itb" "$asset_dir/pluto-plus-source.itb"
cp build/system_top.bit "$asset_dir/system_top.bit"
(
	cd "$asset_dir"
	sha256sum \
		pluto-plus-source.frm \
		pluto-plus-source.itb \
		system_top.bit \
		boot.frm \
		boot.dfu \
		> SHA256SUMS.txt
)
cat > "$asset_dir/README.txt" <<'EOF'
Pluto Plus CLG400 retained build assets

These files are retained so future firmware builds do not depend on an
ephemeral WSL/Docker build directory for the known-good Pluto Plus FPGA image.

Files:
- pluto-plus-source.frm: source firmware image used for FPGA extraction.
- pluto-plus-source.itb: FIT image from pluto-plus-source.frm with the FRM footer removed.
- system_top.bit: FPGA bitstream extracted from fpga@1 in pluto-plus-source.itb.
- boot.frm / boot.dfu: matching known-good Pluto Plus boot artifacts.
- SHA256SUMS.txt: hashes for the retained assets.

Set REFRESH_BIT=1 when running the container build to force re-extraction from
pluto-plus-source.frm.
EOF

rm -f \
	build/pluto.itb \
	build/pluto.frm \
	build/pluto.dfu \
	build/uboot-env.dfu \
	build/config.frm \
	build/zynq-pluto-sdr.dtb \
	build/zynq-pluto-sdr-revb.dtb \
	build/zynq-pluto-sdr-revc.dtb

make -o build/system_top.bit \
	TARGET="$target_name" \
	SKIP_LEGAL=1 \
	build/pluto.frm \
	build/pluto.dfu \
	build/uboot-env.dfu \
	build/config.frm \
	zip-all

zip_archive=$(ls -t build/plutosdr-fw-*.zip | head -n 1)
zip_name=$(basename "$zip_archive")
complete_zip="plutosdr-fw-plutoplus-${package_label}-clg400-complete.zip"
export COMPLETE_ZIP="$complete_zip"

u-boot-xlnx/tools/dumpimage \
	-i build/pluto.itb \
	-T flat_dt \
	-p 0 \
	-o build/verify-zynq-pluto-sdr.dtb \
	build/verify-zynq-pluto-sdr.dtb >/dev/null
linux/scripts/dtc/dtc -I dtb -O dts \
	build/verify-zynq-pluto-sdr.dtb \
	> build/verify-zynq-pluto-sdr.dts

cp \
	build/boot.frm \
	build/boot.dfu \
	build/pluto.frm \
	build/pluto.dfu \
	build/uboot-env.dfu \
	build/config.frm \
	"$zip_archive" \
	"$out/"

cp build/system_top.bit "$out/system_top.bit"
cp "$source_frm" "$out/pluto-plus-source.frm"
cp "$source_itb" "$out/pluto-plus-source.itb"
cp build/pluto.itb "$out/pluto.itb"

for extra_artifact in \
	build/zImage \
	build/rootfs.cpio.gz \
	build/verify-zynq-pluto-sdr.dtb \
	build/verify-zynq-pluto-sdr.dts; do
	if [ -f "$extra_artifact" ]; then
		cp "$extra_artifact" "$out/"
	fi
done

(
	cd "$out"
	rm -f plutosdr-fw-plutoplus-*-clg400-complete.zip
	python3 - <<'PY'
import zipfile
import os

names = ["boot.frm", "boot.dfu", "pluto.frm", "pluto.dfu", "uboot-env.dfu", "config.frm"]
zip_name = os.environ["COMPLETE_ZIP"]
with zipfile.ZipFile(zip_name, "w", zipfile.ZIP_DEFLATED) as zf:
    for name in names:
        zf.write(name, name)
PY
	sha256sum \
		boot.frm \
		boot.dfu \
		pluto.frm \
		pluto.dfu \
		uboot-env.dfu \
		config.frm \
		system_top.bit \
		pluto-plus-source.frm \
		pluto-plus-source.itb \
		pluto.itb \
		"$zip_name" \
		"$complete_zip" \
		> SHA256SUMS.txt
)
cat > "$out/BUILD_MANIFEST.txt" <<EOF
Pluto Plus $package_label firmware package

Install files:
- pluto.frm
- config.frm

Pluto Plus hardware jumper:
- Set the USB reset jumper to USRT-MIO46 before booting this firmware.
- Standard Pluto-style firmware uses MIO52 for USB PHY reset. This firmware
  uses MIO52..MIO53 for Ethernet MDIO, so USB PHY reset is moved to MIO46.
- If the jumper is left on USRT-MIO52, USB may not enumerate even though the
  board appears to boot.

Physical Ethernet:
- eth0 starts asynchronously at boot.
- If network DHCP fails, eth0 falls back to 192.168.3.1 and serves
  192.168.3.10-192.168.3.99.

Retained build/debug files:
- system_top.bit: cached FPGA bitstream used for this build.
- pluto-plus-source.frm: source firmware image used to extract system_top.bit.
- pluto-plus-source.itb: FIT image from pluto-plus-source.frm.
- pluto.itb: FIT image generated for this firmware package.
- zImage: Linux kernel image.
- rootfs.cpio.gz: generated root filesystem archive.
- verify-zynq-pluto-sdr.dtb / .dts: extracted default DTB used for Ethernet/SD verification.

Durable asset cache:
- build-assets/pluto-plus-clg400

Build hygiene:
- Patched shell/DTS/config inputs are copied from the host, normalized to LF,
  and checked for CRLF before the build continues.
- board/pluto/msd/LICENSE.html is created from board/pluto/msd/LICENSE when
  SKIP_LEGAL=1 is used.
EOF

echo "Artifacts:"
ls -lh "$out"
echo
echo "GEM0 verification:"
grep -n -A35 'ethernet@e000b000' build/verify-zynq-pluto-sdr.dts
echo
echo "SDHCI verification:"
grep -n -A15 'mmc@e0100000' build/verify-zynq-pluto-sdr.dts
