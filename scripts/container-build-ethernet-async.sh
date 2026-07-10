#!/usr/bin/env bash
set -euo pipefail

cd /work/src

target_name="pluto"
package_label="${PACKAGE_LABEL:-ethernet-async}"
default_out="/host/build-ethernet-async-fw-plutoplus-clg400"
asset_dir="${ASSET_DIR:-/host/build-assets/pluto-plus-clg400}"
out="${OUT_DIR:-$default_out}"
release_dir="build/pluto-plus-release"
source_frm="$release_dir/pluto.frm"
source_itb="$release_dir/pluto.itb"
host_dir="${HOST_DIR:-/host}"

copy_from_host() {
	local rel="$1"
	local src="$host_dir/$rel"
	local dst="$rel"

	if [ "$(readlink -f "$src" 2>/dev/null || echo "$src")" = "$(readlink -f "$dst" 2>/dev/null || echo "$dst")" ]; then
		return
	fi

	cp "$src" "$dst"
}

copy_tree_from_host() {
	local rel="$1"
	local src="$host_dir/$rel"
	local dst="$rel"

	rm -rf "$dst"
	mkdir -p "$(dirname "$dst")"
	cp -a "$src" "$dst"
}

git config --global --add safe.directory /work/src
git config --global --add safe.directory /work/src/buildroot
git config --global --add safe.directory /work/src/linux
git config --global --add safe.directory /work/src/hdl
git config --global --add safe.directory /work/src/u-boot-xlnx

patched_files=(
	buildroot/board/pluto/S21misc \
	buildroot/board/pluto/S40network \
	buildroot/board/pluto/S41network \
	buildroot/board/pluto/S50dropbear \
	buildroot/board/pluto/S70pluto-radio-api \
	buildroot/board/pluto/S98autostart \
	buildroot/board/pluto/device_persistent_keys \
	buildroot/board/pluto/ifupdown.sh \
	buildroot/board/pluto/post-build.sh \
	buildroot/board/pluto/pluto-sdcard-prepare \
	buildroot/board/pluto/pluto-web-apply-settings \
	buildroot/board/pluto/pluto-radio-api \
	buildroot/board/pluto/pluto-audio-backend \
	buildroot/board/pluto/pluto-audio-dsp/pluto-audio-backend.c \
	buildroot/board/pluto/pluto-audio-dsp/pluto-loopback-backend.c \
	buildroot/board/pluto/pluto-audio-sim-backend \
	buildroot/board/pluto/pluto-doppler-worker \
	buildroot/board/pluto/pluto-radio/profiles/FM_BROADCAST_WFM.json \
	buildroot/board/pluto/pluto-radio/profiles/IQ_CAPTURE.json \
	buildroot/board/pluto/pluto-radio/profiles/LOOPBACK_TEST.json \
	buildroot/board/pluto/pluto-radio/profiles/NOAA_NFM.json \
	buildroot/board/pluto/pluto-radio/profiles/SAT_AUDIO_NFM.json \
	buildroot/board/pluto/pluto-radio/profiles/SAT_CW.json \
	buildroot/board/pluto/pluto-radio/profiles/TX_AUDIO_AM.json \
	buildroot/board/pluto/pluto-radio/profiles/TX_AUDIO_FM.json \
	buildroot/board/pluto/pluto-radio/profiles/TX_CW.json \
	buildroot/board/pluto/pluto-radio/profiles/TX_TEST_TONE.json \
	buildroot/board/pluto/update.sh \
	buildroot/board/pluto/update_frm.sh \
	buildroot/board/pluto/msd/config.frm \
	buildroot/board/pluto/mdev.conf \
	buildroot/board/pluto/automounter.sh \
	buildroot/board/pluto/pluto-eth-fallback \
	buildroot/package/Config.in \
	buildroot/package/liquid-dsp/liquid-dsp.mk \
	buildroot/package/pluto-audio-dsp/Config.in \
	buildroot/package/pluto-audio-dsp/pluto-audio-dsp.mk \
	buildroot/package/python-sgp4/Config.in \
	buildroot/package/python-sgp4/python-sgp4.hash \
	buildroot/package/python-sgp4/python-sgp4.mk \
	buildroot/configs/zynq_pluto_defconfig \
	linux/arch/arm/boot/dts/zynq-pluto-sdr.dtsi \
	linux/arch/arm/configs/zynq_pluto_defconfig \
	u-boot-xlnx/include/configs/zynq-common.h
)

mkdir -p "$release_dir" build "$asset_dir" "$out"

copy_from_host buildroot/board/pluto/S21misc
copy_from_host buildroot/board/pluto/S40network
copy_from_host buildroot/board/pluto/S41network
copy_from_host buildroot/board/pluto/S50dropbear
copy_from_host buildroot/board/pluto/S70pluto-radio-api
copy_from_host buildroot/board/pluto/S98autostart
copy_from_host buildroot/board/pluto/device_persistent_keys
copy_from_host buildroot/board/pluto/ifupdown.sh
copy_from_host buildroot/board/pluto/post-build.sh
copy_from_host buildroot/board/pluto/pluto-sdcard-prepare
copy_from_host buildroot/board/pluto/pluto-web-apply-settings
copy_from_host buildroot/board/pluto/pluto-radio-api
copy_from_host buildroot/board/pluto/pluto-audio-backend
mkdir -p buildroot/board/pluto/pluto-audio-dsp
copy_from_host buildroot/board/pluto/pluto-audio-dsp/pluto-audio-backend.c
copy_from_host buildroot/board/pluto/pluto-audio-dsp/pluto-loopback-backend.c
copy_from_host buildroot/board/pluto/pluto-audio-sim-backend
copy_from_host buildroot/board/pluto/pluto-doppler-worker
mkdir -p buildroot/board/pluto/pluto-radio/profiles
copy_from_host buildroot/board/pluto/pluto-radio/profiles/FM_BROADCAST_WFM.json
copy_from_host buildroot/board/pluto/pluto-radio/profiles/IQ_CAPTURE.json
copy_from_host buildroot/board/pluto/pluto-radio/profiles/LOOPBACK_TEST.json
copy_from_host buildroot/board/pluto/pluto-radio/profiles/NOAA_NFM.json
copy_from_host buildroot/board/pluto/pluto-radio/profiles/SAT_AUDIO_NFM.json
copy_from_host buildroot/board/pluto/pluto-radio/profiles/SAT_CW.json
copy_from_host buildroot/board/pluto/pluto-radio/profiles/TX_AUDIO_AM.json
copy_from_host buildroot/board/pluto/pluto-radio/profiles/TX_AUDIO_FM.json
copy_from_host buildroot/board/pluto/pluto-radio/profiles/TX_CW.json
copy_from_host buildroot/board/pluto/pluto-radio/profiles/TX_TEST_TONE.json
copy_from_host buildroot/board/pluto/update.sh
copy_from_host buildroot/board/pluto/update_frm.sh
copy_from_host buildroot/board/pluto/msd/config.frm
copy_from_host buildroot/board/pluto/mdev.conf
copy_from_host buildroot/board/pluto/automounter.sh
copy_from_host buildroot/board/pluto/pluto-eth-fallback
copy_tree_from_host buildroot/board/pluto/web
mkdir -p buildroot/package/pluto-audio-dsp
mkdir -p buildroot/package/python-sgp4
copy_from_host buildroot/package/Config.in
copy_from_host buildroot/package/liquid-dsp/liquid-dsp.mk
copy_from_host buildroot/package/pluto-audio-dsp/Config.in
copy_from_host buildroot/package/pluto-audio-dsp/pluto-audio-dsp.mk
copy_from_host buildroot/package/python-sgp4/Config.in
copy_from_host buildroot/package/python-sgp4/python-sgp4.hash
copy_from_host buildroot/package/python-sgp4/python-sgp4.mk
copy_from_host buildroot/configs/zynq_pluto_defconfig
copy_from_host linux/arch/arm/boot/dts/zynq-pluto-sdr.dtsi
copy_from_host linux/arch/arm/configs/zynq_pluto_defconfig
copy_from_host u-boot-xlnx/include/configs/zynq-common.h

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
	buildroot/board/pluto/S21misc \
	buildroot/board/pluto/S40network \
	buildroot/board/pluto/S41network \
	buildroot/board/pluto/S50dropbear \
	buildroot/board/pluto/S70pluto-radio-api \
	buildroot/board/pluto/S98autostart \
	buildroot/board/pluto/device_persistent_keys \
	buildroot/board/pluto/ifupdown.sh \
	buildroot/board/pluto/pluto-sdcard-prepare \
	buildroot/board/pluto/pluto-web-apply-settings \
	buildroot/board/pluto/pluto-radio-api \
	buildroot/board/pluto/pluto-audio-backend \
	buildroot/board/pluto/pluto-audio-sim-backend \
	buildroot/board/pluto/pluto-doppler-worker \
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
	cp "$host_dir/build-sdcard-fw-plutoplus-clg400/pluto.frm" "$source_frm"
fi
if [ ! -f build/boot.frm ]; then
	if [ -f "$asset_dir/boot.frm" ]; then
		cp "$asset_dir/boot.frm" build/boot.frm
	else
		cp "$host_dir/build-sdcard-fw-plutoplus-clg400/boot.frm" build/boot.frm
	fi
fi
if [ ! -f build/boot.dfu ]; then
	if [ -f "$asset_dir/boot.dfu" ]; then
		cp "$asset_dir/boot.dfu" build/boot.dfu
	else
		cp "$host_dir/build-sdcard-fw-plutoplus-clg400/boot.dfu" build/boot.dfu
	fi
fi

cp "$source_frm" "$asset_dir/pluto-plus-source.frm"
cp build/boot.frm "$asset_dir/boot.frm"
cp build/boot.dfu "$asset_dir/boot.dfu"

make -C buildroot ARCH=arm "zynq_${target_name}_defconfig"
if grep -q '^BR2_PACKAGE_E2FSPROGS_RESIZE2FS=y$' buildroot/.config && \
	[ -d buildroot/output/build/e2fsprogs-1.46.5 ] && \
	[ ! -x buildroot/output/target/sbin/resize2fs ]; then
	echo "resize2fs is enabled but missing from cached target; rebuilding e2fsprogs"
	make -C buildroot e2fsprogs-dirclean
fi
if ! grep -q '^BR2_PACKAGE_FFTW_SINGLE=y$' buildroot/.config; then
	echo "BR2_PACKAGE_FFTW_SINGLE is disabled; rebuilding liquid-dsp/pluto-audio-dsp without stale FFTW-single artifacts"
	rm -rf \
		buildroot/output/build/liquid-dsp-1.4.0 \
		buildroot/output/build/pluto-audio-dsp \
		buildroot/output/build/fftw-single-* \
		buildroot/output/target/usr/lib/libfftw3f* \
		buildroot/output/host/arm-buildroot-linux-gnueabihf/sysroot/usr/lib/libfftw3f* \
		buildroot/output/host/arm-buildroot-linux-gnueabihf/sysroot/usr/lib/pkgconfig/fftw3f.pc
fi

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
cp "$host_dir/scripts/FULL_DFU_UPDATE.bat" "$out/FULL_DFU_UPDATE.bat"
cp "$host_dir/README.md" "$out/README.md"

for extra_artifact in \
	build/zImage \
	build/rootfs.cpio.gz \
	build/verify-zynq-pluto-sdr.dtb \
	build/verify-zynq-pluto-sdr.dts; do
	if [ -f "$extra_artifact" ]; then
		cp "$extra_artifact" "$out/"
	fi
done

cat > "$out/BUILD_MANIFEST.txt" <<EOF
Pluto Plus $package_label firmware package

Install files:
- pluto.frm
- config.frm

Recommended full deployment:
- Set the Pluto Plus USB reset jumper to USRT-MIO52.
- Press and hold the DFU button while plugging in or resetting the board. Hold
  it for about 5-10 seconds, until Windows enumerates the DFU device.
- Move the USB reset jumper to USRT-MIO46 before flashing or booting this
  firmware.
- Run FULL_DFU_UPDATE.bat from the extracted package directory. It flashes
  pluto.dfu, boot.dfu, and uboot-env.dfu.
- When the Pluto USB mass-storage drive appears, edit config.frm to select the
  desired JFFS2_SIZE_MIB value.
- Copy pluto.frm and the edited config.frm to the root of the Pluto USB drive.
- Safely eject the Pluto USB drive, but do not disconnect the USB cable.
- After the device reboots and the USB drive comes back, adjust config.txt
  runtime settings as needed and safely eject again.
- After the final reboot, physically disconnect and reconnect the USB cable.
  Leave the jumper on USRT-MIO46 for normal use with this firmware.

Pluto Plus hardware jumper:
- Standard Pluto-style firmware uses MIO52 for USB PHY reset. This firmware
  uses MIO52..MIO53 for Ethernet MDIO, so USB PHY reset is moved to MIO46.
- If the jumper is left on USRT-MIO52 after this firmware is installed, USB may
  not enumerate even though the board appears to boot.

Physical Ethernet:
- eth0 starts asynchronously at boot.
- If network DHCP fails, eth0 falls back to 192.168.3.1 and serves
  192.168.3.10-192.168.3.99.

RF / hostname / keys:
- U-Boot defaults AD936x extended range settings at boot. Rev.C hardware uses
  attr_val/compatible=ad9361 with mode=2r2t; other Pluto-style hardware uses
  attr_val/compatible=ad9364 with mode=1r1t.
- config.txt includes an editable [AD936X] section for attr_name, attr_val,
  compatible, mode, and force_2r2t.
- On Pluto Plus boards with populated TX2/RX2 hardware, set force_2r2t=1 to
  select the Rev.C FIT device tree and force ad9361/2r2t at boot for testing.
- Hostname defaults to pluto and Avahi/zeroconf is enabled for pluto.local.
- Dropbear host keys are persisted to /mnt/jffs2 with device_persistent_keys.
- config.txt includes device_persistent_keys = 0 under [ACTIONS]. Setting it
  to 1 manually refreshes persisted Dropbear keys and writes
  PERSISTENT_KEYS_STATUS.
- ext4 is recommended for SD card application storage. e2fsck supports
  ext2/3/4 repair, while fsck.vfat remains available for FAT compatibility.
  Cards are checked before mount and before /mnt/jffs2/autorun.sh. Startup
  repair and autorun run in the background so checks cannot block normal boot.
- python3 is included in the root filesystem for local application scripts.
- python-sgp4 2.24 is included for local TLE/orbit propagation workflows.
- Physical Ethernet uses a stable default MAC address of 00:0a:35:00:01:22.
  It can be changed with macaddr_eth in config.txt before ejecting the drive.

DFU loader:
- FULL_DFU_UPDATE.bat flashes pluto.dfu, boot.dfu, and uboot-env.dfu from a
  forced DFU session. It is intended for complete package deployment and
  rewrites the U-Boot environment.

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

(
	cd "$out"
	rm -f plutosdr-fw-plutoplus-*-clg400-complete.zip
	python3 - <<'PY'
import zipfile
import os

names = [
    "README.md",
    "BUILD_MANIFEST.txt",
    "boot.frm",
    "boot.dfu",
    "pluto.frm",
    "pluto.dfu",
    "uboot-env.dfu",
    "config.frm",
    "FULL_DFU_UPDATE.bat",
]
zip_name = os.environ["COMPLETE_ZIP"]
with zipfile.ZipFile(zip_name, "w", zipfile.ZIP_DEFLATED) as zf:
    for name in names:
        zf.write(name, name)
PY
	sha256sum \
		README.md \
		BUILD_MANIFEST.txt \
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
		FULL_DFU_UPDATE.bat \
		"$zip_name" \
		"$complete_zip" \
		> SHA256SUMS.txt
)

echo "Artifacts:"
ls -lh "$out"
echo
echo "GEM0 verification:"
grep -n -A35 'ethernet@e000b000' build/verify-zynq-pluto-sdr.dts
echo
echo "SDHCI verification:"
grep -n -A15 'mmc@e0100000' build/verify-zynq-pluto-sdr.dts
