#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat >&2 <<'EOF'
Fast Pluto audio-DSP debug build.

Expected container layout:
  /host     = bind-mounted host firmware checkout
  /work/src = container-internal firmware source tree

Run from the host checkout:
  docker run --name pluto-fw-audio-dsp-fast --rm \
    -v "$PWD:/host" \
    -v pluto-fw-async-work-0611b:/work \
    -v pluto-fw-dl:/dl \
    -v pluto-fw-ccache:/ccache \
    -w /work/src \
    -e HOME=/tmp \
    -e BR2_DL_DIR=/dl \
    -e CCACHE_DIR=/ccache \
    -e OUT_DIR=/host/build-audio-dsp-fast \
    pluto-fw-v039:latest \
    bash -lc '/host/scripts/container-build-audio-dsp-fast.sh'

This rebuilds only the pluto-audio-dsp Buildroot package and copies the ARM
userspace binaries to OUT_DIR. It does not rebuild U-Boot, the kernel, the FIT,
or pluto-sdcard.img. Use scripts/container-build-ethernet-async.sh when a full
flashable SD image is required.
EOF
}

die() {
	echo "ERROR: $*" >&2
	usage
	exit 2
}

host_dir="${HOST_DIR:-/host}"
work_dir="${WORK_DIR:-/work/src}"
out="${OUT_DIR:-$host_dir/build-audio-dsp-fast}"

[ -d "$host_dir" ] || die "missing host checkout mount at $host_dir"
[ -d "$work_dir" ] || die "missing container source tree at $work_dir"
[ -f "$host_dir/scripts/container-build-audio-dsp-fast.sh" ] || die "missing wrapper at $host_dir/scripts/container-build-audio-dsp-fast.sh"
[ -f "$work_dir/Makefile" ] || die "missing firmware Makefile under $work_dir"

host_real="$(cd "$host_dir" && pwd -P)"
work_real="$(cd "$work_dir" && pwd -P)"
[ "$host_real" != "$work_real" ] || die "$host_dir and $work_dir resolve to the same directory; mount the repo at /host and use the Docker volume at /work"

cd "$work_dir"

copy_from_host() {
	local rel="$1"
	local src="$host_dir/$rel"
	local dst="$rel"

	[ -e "$src" ] || die "missing patched file from host: $src"
	mkdir -p "$(dirname "$dst")"
	cp "$src" "$dst"
}

git config --global --add safe.directory /work/src
git config --global --add safe.directory /work/src/buildroot

patched_files=(
	buildroot/board/pluto/pluto-audio-dsp/pluto-audio-backend.c
	buildroot/board/pluto/pluto-audio-dsp/pluto-loopback-backend.c
	buildroot/board/pluto/pluto-audio-dsp/pluto-spectrum-backend.c
	buildroot/package/Config.in
	buildroot/package/liquid-dsp/liquid-dsp.mk
	buildroot/package/pluto-audio-dsp/Config.in
	buildroot/package/pluto-audio-dsp/pluto-audio-dsp.mk
	buildroot/configs/zynq_pluto_defconfig
)

for rel in "${patched_files[@]}"; do
	copy_from_host "$rel"
done

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

make -C buildroot ARCH=arm zynq_pluto_defconfig

echo "Rebuilding pluto-audio-dsp only"
make -C buildroot pluto-audio-dsp-rebuild

mkdir -p "$out"
cp buildroot/output/build/pluto-audio-dsp/pluto-audio-backend "$out/"
cp buildroot/output/build/pluto-audio-dsp/pluto-loopback-backend "$out/"
cp buildroot/output/build/pluto-audio-dsp/pluto-spectrum-backend "$out/"

cat > "$out/README-fast-audio-dsp.txt" <<'EOF'
Fast audio-DSP debug artifacts

These are ARM userspace binaries only. They are intended for bench debugging on
an already-booted Pluto running a compatible firmware build.

Deploy from the host using sshpass and legacy scp mode:

BUILD_DIR=/path/to/this/output \
PLUTO_HOST=192.168.2.1 \
PLUTO_PASS=analog \
bash scripts/deploy-fast-audio-dsp-to-pluto.sh

For iq_file backend diagnostics:

PLUTO_HOST=192.168.2.1 \
PLUTO_PASS=analog \
REMOTE_IQ_FILE=/tmp/noaa-live-iq-s12.raw \
bash scripts/run-pluto-iq-file-debug.sh

For persistent release or reboot testing, build a full pluto-sdcard.img instead.
EOF

(
	cd "$out"
	sha256sum \
		pluto-audio-backend \
		pluto-loopback-backend \
		pluto-spectrum-backend \
		> SHA256SUMS.txt
)

echo "Fast audio-DSP artifacts:"
ls -lh "$out"
