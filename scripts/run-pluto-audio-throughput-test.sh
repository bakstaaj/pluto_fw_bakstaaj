#!/usr/bin/env bash
set -euo pipefail

export PATH="/usr/bin:/bin:/mingw64/bin:$PATH"

PLUTO_HOST="${PLUTO_HOST:-192.168.2.1}"
PLUTO_USER="${PLUTO_USER:-root}"
PLUTO_PASS="${PLUTO_PASS:-analog}"
PROFILE="${PROFILE:-NOAA_NFM}"
FREQUENCY_HZ="${FREQUENCY_HZ:-162500000}"
GAIN_DB="${GAIN_DB:-55}"
TEST_SECONDS="${TEST_SECONDS:-40}"
LOCAL_OUT_DIR="${LOCAL_OUT_DIR:-./pluto-audio-throughput-output}"

SSH_OPTS=(
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o PreferredAuthentications=password
    -o PubkeyAuthentication=no
)
SSHPASS=(sshpass -p "$PLUTO_PASS")

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "ERROR: missing required command: $1" >&2
        exit 2
    }
}

need_cmd sshpass
need_cmd ssh
need_cmd scp
need_cmd python3

mkdir -p "$LOCAL_OUT_DIR"

echo "Running Pluto firmware-side audio throughput test"
echo "  target: ${PLUTO_USER}@${PLUTO_HOST}"
echo "  profile: ${PROFILE}"
echo "  frequency_hz: ${FREQUENCY_HZ}"
echo "  duration: ${TEST_SECONDS}s"
echo "  local output: ${LOCAL_OUT_DIR}"

remote_script="/tmp/pluto-audio-throughput-test.sh"
remote_prefix="/tmp/pluto-audio-throughput"

"${SSHPASS[@]}" ssh "${SSH_OPTS[@]}" "${PLUTO_USER}@${PLUTO_HOST}" "cat > '$remote_script' && chmod +x '$remote_script'" <<'REMOTE'
#!/bin/sh
set -eu

profile="$1"
frequency_hz="$2"
gain_db="$3"
seconds="$4"
prefix="/tmp/pluto-audio-throughput"

rm -f "$prefix".*

api="http://127.0.0.1:8081"

wget -qO- --post-data='{}' \
    --header='Content-Type: application/json' \
    "$api/radio/audio/stop" > "$prefix.stop.json" 2>"$prefix.stop.err" || true

start_payload="{\"profile\":\"$profile\",\"frequency_hz\":$frequency_hz,\"gain_db\":$gain_db,\"squelch_db\":-120,\"noise_gate_db\":-120}"
wget -qO- --post-data="$start_payload" \
    --header='Content-Type: application/json' \
    "$api/radio/audio/start" > "$prefix.start.json" 2>"$prefix.start.err"

sleep 2

url="$api/radio/audio/live.wav?continuous=true"
wget -qO "$prefix.live.wav" "$url" > "$prefix.wget.out" 2>"$prefix.wget.err" &
wget_pid="$!"

i=0
while [ "$i" -le "$seconds" ]; do
    ts="$(date +%s 2>/dev/null || echo "$i")"
    printf '=== t=%s epoch=%s ===\n' "$i" "$ts" >> "$prefix.status.log"
    wget -qO- "$api/radio/audio/status" >> "$prefix.status.log" 2>>"$prefix.status.err" || true
    printf '\n' >> "$prefix.status.log"
    sleep 2
    i=$((i + 2))
done

kill "$wget_pid" 2>/dev/null || true
wait "$wget_pid" 2>/dev/null || true

ls -l "$prefix.live.wav" "$prefix.status.log" "$prefix.start.json" > "$prefix.files.txt" 2>&1 || true
wget -qO- "$api/radio/audio/status" > "$prefix.final-status.json" 2>"$prefix.final-status.err" || true

cat "$prefix.files.txt"
REMOTE

"${SSHPASS[@]}" ssh "${SSH_OPTS[@]}" "${PLUTO_USER}@${PLUTO_HOST}" \
    "$remote_script '$PROFILE' '$FREQUENCY_HZ' '$GAIN_DB' '$TEST_SECONDS'"

echo "Copying firmware-side test outputs with scp -O"
"${SSHPASS[@]}" scp -O "${SSH_OPTS[@]}" \
    "${PLUTO_USER}@${PLUTO_HOST}:${remote_prefix}.*" \
    "$LOCAL_OUT_DIR/"

python3 - "$LOCAL_OUT_DIR" <<'PY'
import json
import re
import sys
from pathlib import Path

out_dir = Path(sys.argv[1])
status_path = out_dir / "pluto-audio-throughput.status.log"
wav_path = out_dir / "pluto-audio-throughput.live.wav"

entries = []
current_t = None
for line in status_path.read_text(encoding="utf-8", errors="replace").splitlines():
    header = re.match(r"=== t=(\d+) epoch=([^ ]+) ===", line)
    if header:
        current_t = int(header.group(1))
        continue
    if line.startswith("{"):
        try:
            payload = json.loads(line)
        except json.JSONDecodeError:
            continue
        audio = payload.get("audio", {})
        entries.append(
            {
                "t": current_t,
                "pcm_bytes": audio.get("pcm_bytes"),
                "pcm_rate_hz": audio.get("pcm_rate_hz"),
                "pcm_measured_rate_hz": audio.get("pcm_measured_rate_hz"),
                "state": audio.get("state"),
                "phase": audio.get("phase"),
                "rms_level": audio.get("rms_level"),
            }
        )

numeric = [e for e in entries if isinstance(e.get("pcm_bytes"), int) and isinstance(e.get("t"), int)]
print("=== firmware audio throughput summary ===")
print(f"status samples: {len(entries)}")
if wav_path.exists():
    wav_size = wav_path.stat().st_size
    print(f"live.wav bytes: {wav_size}")
    if wav_size >= 44:
        print(f"live.wav payload bytes: {wav_size - 44}")
        print(f"live.wav payload bytes/sec over requested window: {(wav_size - 44) / max(1, numeric[-1]['t'] if numeric else 1):.1f}")
if len(numeric) >= 2:
    first = numeric[0]
    last = numeric[-1]
    dt = last["t"] - first["t"]
    db = last["pcm_bytes"] - first["pcm_bytes"]
    bps = db / dt if dt > 0 else 0.0
    sample_rate = bps / 2.0
    print(f"pcm_bytes delta: {db} over {dt}s")
    print(f"firmware produced bytes/sec: {bps:.1f}")
    print(f"firmware produced sample_rate_hz: {sample_rate:.1f}")
    print(f"percent of 48k s16le nominal: {(bps / 96000.0) * 100.0:.1f}%")
    print(f"last status: state={last['state']} phase={last['phase']} pcm_rate_hz={last['pcm_rate_hz']} measured={last['pcm_measured_rate_hz']}")
else:
    print("not enough numeric status samples to calculate pcm_bytes rate")
PY
