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
TARGET="${PLUTO_USER}@${PLUTO_HOST}"

REMOTE_IQ_FILE="${REMOTE_IQ_FILE:-/tmp/noaa-live-iq-s12.raw}"
REMOTE_PCM_OUT="${REMOTE_PCM_OUT:-/tmp/backend-iq-file.pcm}"
REMOTE_WAV_OUT="${REMOTE_WAV_OUT:-/tmp/backend-iq-file.wav}"
REMOTE_STATUS_OUT="${REMOTE_STATUS_OUT:-/tmp/backend-iq-file-status.json}"
LOCAL_OUT_DIR="${LOCAL_OUT_DIR:-$ROOT_DIR/debug-output}"
LOCAL_PCM_NAME="${LOCAL_PCM_NAME:-backend-iq-file.pcm}"
LOCAL_WAV_NAME="${LOCAL_WAV_NAME:-backend-iq-file.wav}"
LOCAL_STATUS_NAME="${LOCAL_STATUS_NAME:-backend-iq-file-status.json}"
LOCAL_IQ_FILE="${LOCAL_IQ_FILE:-}"
LOCAL_IQ_FORMAT="${LOCAL_IQ_FORMAT:-s12}"

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

need_cmd sshpass
need_cmd ssh
need_cmd scp

mkdir -p "$LOCAL_OUT_DIR"

echo "Running Pluto iq_file backend diagnostic"
echo "  target: $TARGET"
echo "  remote IQ: $REMOTE_IQ_FILE"
echo "  IQ format: $LOCAL_IQ_FORMAT"
echo "  local output: $LOCAL_OUT_DIR"

if [[ -n "$LOCAL_IQ_FILE" ]]; then
  if [[ ! -f "$LOCAL_IQ_FILE" ]]; then
    echo "ERROR: missing local IQ file: $LOCAL_IQ_FILE" >&2
    exit 2
  fi

  echo "Uploading local IQ capture with scp -O"
  "${SSHPASS[@]}" scp -O "${SSH_OPTS[@]}" \
    "$LOCAL_IQ_FILE" \
    "$TARGET:$REMOTE_IQ_FILE"
fi

"${SSHPASS[@]}" ssh "${SSH_OPTS[@]}" "$TARGET" \
  "REMOTE_IQ_FILE='$REMOTE_IQ_FILE' REMOTE_PCM_OUT='$REMOTE_PCM_OUT' REMOTE_WAV_OUT='$REMOTE_WAV_OUT' REMOTE_STATUS_OUT='$REMOTE_STATUS_OUT' LOCAL_IQ_FORMAT='$LOCAL_IQ_FORMAT' sh -s" <<'REMOTE_SCRIPT'
set -eu

if [ ! -f "$REMOTE_IQ_FILE" ]; then
  echo "ERROR: missing remote IQ file: $REMOTE_IQ_FILE" >&2
  exit 2
fi

echo "Stopping any active audio session"
wget -qO- --post-data="{}" --header="Content-Type: application/json" \
  http://127.0.0.1:8081/radio/audio/stop >/tmp/pluto-audio-stop.json 2>/dev/null || true

rm -f "$REMOTE_PCM_OUT" "$REMOTE_WAV_OUT" "$REMOTE_STATUS_OUT"

PLUTO_AUDIO_FIFO="$REMOTE_PCM_OUT" \
PLUTO_AUDIO_SOURCE=iq_file \
PLUTO_AUDIO_IQ_FILE="$REMOTE_IQ_FILE" \
PLUTO_AUDIO_IQ_FILE_FORMAT="$LOCAL_IQ_FORMAT" \
PLUTO_AUDIO_BACKEND_STATUS_FILE="$REMOTE_STATUS_OUT" \
PLUTO_AUDIO_PROFILE=NOAA_NFM \
PLUTO_AUDIO_DEMOD=nfm \
PLUTO_AUDIO_RATE_HZ=48000 \
PLUTO_DSP_INPUT_RATE_HZ=520999 \
PLUTO_AUDIO_FILTER_WIDTH_HZ=8050 \
PLUTO_AUDIO_SQUELCH_DB=-120 \
PLUTO_AUDIO_NOISE_GATE_DB=-120 \
PLUTO_AUDIO_DEEMPHASIS=75us \
PLUTO_AUDIO_OUTPUT_GAIN=2.0 \
PLUTO_AUDIO_DC_BLOCK=1 \
/usr/sbin/pluto-audio-backend

rc=$?
echo "backend rc=$rc"
if command -v python3 >/dev/null 2>&1; then
  PCM_IN="$REMOTE_PCM_OUT" WAV_OUT="$REMOTE_WAV_OUT" python3 - <<'PY'
import os
import wave

pcm_path = os.environ["PCM_IN"]
wav_path = os.environ["WAV_OUT"]

with open(pcm_path, "rb") as src:
    pcm = src.read()

with wave.open(wav_path, "wb") as dst:
    dst.setnchannels(1)
    dst.setsampwidth(2)
    dst.setframerate(48000)
    dst.writeframes(pcm)
PY
else
  echo "WARNING: python3 not available on Pluto; skipping WAV wrapper" >&2
fi
ls -l "$REMOTE_PCM_OUT" "$REMOTE_WAV_OUT" "$REMOTE_STATUS_OUT" 2>/dev/null || true
cat "$REMOTE_STATUS_OUT"
exit "$rc"
REMOTE_SCRIPT

"${SSHPASS[@]}" scp -O "${SSH_OPTS[@]}" \
  "$TARGET:$REMOTE_PCM_OUT" \
  "$LOCAL_OUT_DIR/$LOCAL_PCM_NAME"

if "${SSHPASS[@]}" ssh "${SSH_OPTS[@]}" "$TARGET" "test -f '$REMOTE_WAV_OUT'"; then
  "${SSHPASS[@]}" scp -O "${SSH_OPTS[@]}" \
    "$TARGET:$REMOTE_WAV_OUT" \
    "$LOCAL_OUT_DIR/$LOCAL_WAV_NAME"
fi

"${SSHPASS[@]}" scp -O "${SSH_OPTS[@]}" \
  "$TARGET:$REMOTE_STATUS_OUT" \
  "$LOCAL_OUT_DIR/$LOCAL_STATUS_NAME"

echo "Copied diagnostic outputs:"
ls -l "$LOCAL_OUT_DIR/$LOCAL_PCM_NAME" "$LOCAL_OUT_DIR/$LOCAL_WAV_NAME" "$LOCAL_OUT_DIR/$LOCAL_STATUS_NAME" 2>/dev/null || true
