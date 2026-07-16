#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://192.168.2.1}"
PROFILE="${PROFILE:-NOAA_NFM}"
GAIN_DB="${GAIN_DB:-60}"
GAIN_CONTROL_MODE="${GAIN_CONTROL_MODE:-manual}"
SQUELCH_DB="${SQUELCH_DB:--90}"
SAMPLE_RATE_HZ="${SAMPLE_RATE_HZ:-2400000}"
CYCLES="${CYCLES:-42}"
RETUNE_EVERY="${RETUNE_EVERY:-6}"
READ_TIMEOUT_SECONDS="${READ_TIMEOUT_SECONDS:-12}"
SLEEP_SECONDS="${SLEEP_SECONDS:-2}"
OUTPUT_DIR="${OUTPUT_DIR:-${TMPDIR:-/tmp}/pluto-noaa-endurance}"
PYTHON_BIN="${PYTHON_BIN:-${PYTHON:-python3}}"

NOAA_FREQS=(
  162400000
  162425000
  162450000
  162475000
  162500000
  162525000
  162550000
)

mkdir -p "$OUTPUT_DIR"

post_json() {
  local path="$1"
  local payload="$2"
  curl -fsS -X POST \
    -H 'Content-Type: application/json' \
    --data "$payload" \
    "${BASE_URL}${path}"
}

post_empty() {
  local path="$1"
  curl -fsS -X POST \
    -H 'Content-Type: application/json' \
    --data '' \
    "${BASE_URL}${path}"
}

"$PYTHON_BIN" - "$OUTPUT_DIR" <<'PY'
import json
import sys
from pathlib import Path

outdir = Path(sys.argv[1])
(outdir / "summary.jsonl").write_text("", encoding="utf-8")
PY

echo "Output: $OUTPUT_DIR"
echo "Base URL: $BASE_URL"

post_empty "/radio/audio/stop" >/dev/null || true
post_empty "/radio/stop" >/dev/null || true

for ((cycle=1; cycle<=CYCLES; cycle++)); do
  freq_index=$(( ((cycle - 1) / RETUNE_EVERY) % ${#NOAA_FREQS[@]} ))
  freq_hz="${NOAA_FREQS[$freq_index]}"
  wav_path="$OUTPUT_DIR/live-${cycle}.wav"
  health_path="$OUTPUT_DIR/health-${cycle}.json"
  audio_path="$OUTPUT_DIR/audio-${cycle}.json"

  if (( cycle == 1 )); then
    echo "-- cycle $cycle start -> $freq_hz Hz"
    post_json "/radio/audio/start" "$(printf '{"profile":"%s","frequency_hz":%s,"simulate":false,"squelch_db":%s,"gain_db":%s,"gain_control_mode":"%s"}' \
      "$PROFILE" "$freq_hz" "$SQUELCH_DB" "$GAIN_DB" "$GAIN_CONTROL_MODE")" > "$OUTPUT_DIR/start-${cycle}.json"
  elif (( (cycle - 1) % RETUNE_EVERY == 0 )); then
    echo "-- cycle $cycle retune -> $freq_hz Hz"
    post_json "/radio/audio/retune" "$(printf '{"profile":"%s","frequency_hz":%s,"gain_db":%s,"gain_control_mode":"%s"}' \
      "$PROFILE" "$freq_hz" "$GAIN_DB" "$GAIN_CONTROL_MODE")" > "$OUTPUT_DIR/retune-${cycle}.json"
  fi

  curl -fsS "${BASE_URL}/system/health" > "$health_path"
  curl -fsS "${BASE_URL}/radio/audio/status" > "$audio_path"

  if curl -fsS --max-time "$READ_TIMEOUT_SECONDS" "${BASE_URL}/radio/audio/live.wav?seconds=${READ_TIMEOUT_SECONDS}" -o "$wav_path"; then
    :
  else
    echo "cycle=$cycle live.wav fetch failed"
  fi

  "$PYTHON_BIN" - "$cycle" "$freq_hz" "$wav_path" "$health_path" "$audio_path" "$OUTPUT_DIR/summary.jsonl" <<'PY'
import json
import struct
import sys
import wave
from pathlib import Path

cycle = int(sys.argv[1])
freq_hz = int(sys.argv[2])
wav_path = Path(sys.argv[3])
health_path = Path(sys.argv[4])
audio_path = Path(sys.argv[5])
summary_path = Path(sys.argv[6])

entry = {
    "cycle": cycle,
    "frequency_hz": freq_hz,
    "wav_exists": wav_path.exists(),
}

try:
    entry["health"] = json.loads(health_path.read_text(encoding="utf-8"))
except Exception as exc:
    entry["health_error"] = str(exc)

try:
    entry["audio"] = json.loads(audio_path.read_text(encoding="utf-8"))
except Exception as exc:
    entry["audio_error"] = str(exc)

if wav_path.exists():
    try:
        with wave.open(str(wav_path), "rb") as handle:
            frames = handle.readframes(min(handle.getnframes(), 48000))
        samples = struct.unpack("<" + "h" * (len(frames) // 2), frames) if frames else ()
        nonzero = sum(1 for sample in samples if sample != 0)
        peak = max((abs(sample) for sample in samples), default=0)
        entry["wav"] = {
            "samples": len(samples),
            "nonzero_samples": nonzero,
            "nonzero_ratio": (nonzero / len(samples)) if samples else 0.0,
            "peak": peak,
        }
    except Exception as exc:
        entry["wav_error"] = str(exc)

with summary_path.open("a", encoding="utf-8") as handle:
    handle.write(json.dumps(entry, sort_keys=True) + "\n")

line = f"cycle={cycle} freq={freq_hz}"
if "wav" in entry:
    line += f" samples={entry['wav']['samples']} nonzero_ratio={entry['wav']['nonzero_ratio']:.3f} peak={entry['wav']['peak']}"
if entry.get("health", {}).get("iio", {}).get("ensm_mode"):
    line += f" ensm={entry['health']['iio']['ensm_mode']}"
if entry.get("audio", {}).get("audio", {}).get("state"):
    line += f" audio_state={entry['audio']['audio']['state']}"
print(line)
PY

  sleep "$SLEEP_SECONDS"
done

echo "Summary written to $OUTPUT_DIR/summary.jsonl"
