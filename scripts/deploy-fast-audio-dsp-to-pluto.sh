#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -f "$ROOT_DIR/.pluto.env" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.pluto.env"
fi

PLUTO_HOST="${PLUTO_HOST:-192.168.2.1}"
PLUTO_USER="${PLUTO_USER:-root}"
PLUTO_PASS="${PLUTO_PASS:-analog}"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build-audio-dsp-fast-iq-file-regular-sink}"
TARGET="${PLUTO_USER}@${PLUTO_HOST}"

SSH_OPTS=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o ConnectTimeout=10
)
SSHPASS=(sshpass -p "$PLUTO_PASS")

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: missing required command: $1" >&2
    echo "Install in MSYS2 with: pacman -S --needed $1" >&2
    exit 2
  fi
}

need_file() {
  if [[ ! -f "$1" ]]; then
    echo "ERROR: missing required file: $1" >&2
    exit 2
  fi
}

need_cmd sshpass
need_cmd ssh
need_cmd scp

need_file "$BUILD_DIR/pluto-audio-backend"
need_file "$BUILD_DIR/pluto-loopback-backend"
need_file "$BUILD_DIR/pluto-spectrum-backend"

echo "Deploying fast audio-DSP binaries from:"
echo "  $BUILD_DIR"
echo "To:"
echo "  $TARGET"

"${SSHPASS[@]}" scp -O "${SSH_OPTS[@]}" \
  "$BUILD_DIR/pluto-audio-backend" \
  "$BUILD_DIR/pluto-loopback-backend" \
  "$BUILD_DIR/pluto-spectrum-backend" \
  "$TARGET:/tmp/"

"${SSHPASS[@]}" ssh "${SSH_OPTS[@]}" "$TARGET" '
set -eu

echo "Stopping any active audio session"
wget -qO- --post-data="{}" --header="Content-Type: application/json" \
  http://127.0.0.1:8081/radio/audio/stop >/tmp/pluto-audio-stop.json 2>/dev/null || true

echo "Stopping Pluto radio API"
/etc/init.d/S70pluto-radio-api stop 2>/dev/null || true

echo "Installing audio-DSP binaries"
chmod 755 /tmp/pluto-audio-backend /tmp/pluto-loopback-backend /tmp/pluto-spectrum-backend
cp /tmp/pluto-audio-backend /usr/sbin/pluto-audio-backend
cp /tmp/pluto-loopback-backend /usr/sbin/pluto-loopback-backend
cp /tmp/pluto-spectrum-backend /usr/sbin/pluto-spectrum-backend
ln -sf pluto-loopback-backend /usr/sbin/pluto-tx-backend

echo "Starting Pluto radio API"
/etc/init.d/S70pluto-radio-api start

echo "Installed binaries:"
ls -l /usr/sbin/pluto-audio-backend /usr/sbin/pluto-loopback-backend /usr/sbin/pluto-spectrum-backend
'

echo "Fast audio-DSP deploy complete."
