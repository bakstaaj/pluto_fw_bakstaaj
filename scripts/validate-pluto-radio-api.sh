#!/usr/bin/env bash
set -euo pipefail

api="buildroot/board/pluto/pluto-radio-api"
profiles="buildroot/board/pluto/pluto-radio/profiles"

bash_bin="${BASH:-bash}"
tool_dir="${bash_bin%/*}"
export PATH="$tool_dir:$PATH"
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

export PLUTO_RADIO_PROFILE_DIR="$profiles"
export PLUTO_RADIO_DRY_RUN=1

python_syntax "$api"
python_syntax buildroot/board/pluto/pluto-audio-backend
python_syntax buildroot/board/pluto/pluto-audio-sim-backend
"$python_bin" "$api" profiles >/dev/null
"$python_bin" "$api" status >/dev/null
"$python_bin" "$api" health >/dev/null
PLUTO_RADIO_API_MODE=lighttpd-python-http "$python_bin" - "$api" <<'PY'
import importlib.util
import json
import os
import sys
import threading
import urllib.request
from importlib.machinery import SourceFileLoader
from pathlib import Path

api_path = Path(sys.argv[1])
loader = SourceFileLoader("pluto_radio_api_http_validation", str(api_path))
spec = importlib.util.spec_from_loader("pluto_radio_api_http_validation", loader)
api = importlib.util.module_from_spec(spec)
loader.exec_module(api)

server = api.RadioApiHttpServer(("127.0.0.1", 0), api.RadioApiHttpHandler)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
base = f"http://127.0.0.1:{server.server_address[1]}"
try:
    with urllib.request.urlopen(base + "/system/health", timeout=5) as response:
        health = json.loads(response.read().decode("utf-8"))
    assert health["system"]["api_mode"] == "lighttpd-python-http"
    with urllib.request.urlopen(base + "/cgi-bin/pluto-radio-api?path=/radio/profile/list", timeout=5) as response:
        profiles_payload = json.loads(response.read().decode("utf-8"))
    assert profiles_payload["ok"] is True
    with urllib.request.urlopen(base + "/cgi-bin/pluto-metrics.cgi", timeout=5) as response:
        metrics_payload = json.loads(response.read().decode("utf-8"))
    assert "system" in metrics_payload and "radio" in metrics_payload
finally:
    server.shutdown()
    server.server_close()
PY
"$python_bin" "$api" logs audio >/dev/null
"$python_bin" "$api" audio-status >/dev/null
"$python_bin" "$api" watchdog-status >/dev/null
"$python_bin" "$api" watchdog-check >/dev/null
"$python_bin" "$api" capture-list >/dev/null
"$python_bin" "$api" spectrum-status >/dev/null
"$python_bin" "$api" loopback-status >/dev/null
"$python_bin" "$api" tx-status >/dev/null
"$python_bin" "$api" tx-guardrails TX_TEST_TONE --simulate >/dev/null
"$python_bin" "$api" calibration-status >/dev/null
"$python_bin" "$api" calibration-apply rx_frequency_offset_hz=12.5 tx_gain_offset_db=-1.0 notes=host-validation >/dev/null
"$python_bin" "$api" self-test >/dev/null
"$python_bin" "$api" self-test-status >/dev/null
"$python_bin" "$api" doppler-status >/dev/null

for profile in FM_BROADCAST_WFM NOAA_NFM SAT_AUDIO_NFM SAT_CW IQ_CAPTURE LOOPBACK_TEST TX_AUDIO_AM TX_AUDIO_FM TX_CW TX_TEST_TONE; do
	"$python_bin" "$api" apply "$profile" >/dev/null
done

"$python_bin" "$api" audio-start NOAA_NFM --simulate >/dev/null
"$python_bin" "$api" audio-status >/dev/null
"$python_bin" "$api" audio-stop >/dev/null
tmp_stream_dir="$(mktemp -d "${TMPDIR:-/tmp}/pluto-audio-stream-test.XXXXXX")"
tmp_stream_out="${TMPDIR:-/tmp}/pluto-audio-stream-test.$$.out"
cleanup_stream_test() {
	rm -rf "$tmp_stream_dir"
	rm -f "$tmp_stream_out"
}
trap cleanup_stream_test EXIT
REQUEST_METHOD=GET "$python_bin" - "$api" "$tmp_stream_dir" >"$tmp_stream_out" <<'PY'
import importlib.util
import json
import os
import sys
import threading
import time
from importlib.machinery import SourceFileLoader
from pathlib import Path

api_path = Path(sys.argv[1])
state_dir = Path(sys.argv[2])
loader = SourceFileLoader("pluto_radio_api", str(api_path))
spec = importlib.util.spec_from_loader("pluto_radio_api", loader)
api = importlib.util.module_from_spec(spec)
loader.exec_module(api)

api.STATE_DIR = state_dir
api.AUDIO_STATE_FILE = state_dir / "audio.json"
api.AUDIO_FIFO = state_dir / "audio.pcm"
os.environ["PLUTO_RADIO_DRY_RUN"] = "0"
state_dir.mkdir(parents=True, exist_ok=True)
os.mkfifo(api.AUDIO_FIFO)
api.AUDIO_STATE_FILE.write_text(
    json.dumps(
        {
            "state": "running",
            "profile": "NOAA_NFM",
            "demod_mode": "nfm",
            "audio_rate_hz": 8000,
            "stream_format": "pcm_s16le",
            "fifo_path": str(api.AUDIO_FIFO),
            "pid": os.getpid(),
            "backend": "validation",
        }
    ),
    encoding="utf-8",
)

def writer():
    with api.AUDIO_FIFO.open("wb", buffering=0) as handle:
        deadline = time.time() + 3
        while time.time() < deadline:
            try:
                handle.write(b"\x00" * 512)
            except BrokenPipeError:
                break
            time.sleep(0.01)

thread = threading.Thread(target=writer, daemon=True)
thread.start()
api.stream_audio("wav", {"seconds": "1"})
thread.join(timeout=1)
PY
"$python_bin" - "$tmp_stream_out" <<'PY'
from pathlib import Path
import sys

data = Path(sys.argv[1]).read_bytes()
headers_end = data.find(b"\n\n")
riff = data.find(b"RIFF")
if not data.startswith(b"Content-Type: audio/wav\nCache-Control: no-store\n\n"):
    raise SystemExit("live.wav CGI headers were not emitted before the WAV body")
if riff <= headers_end:
    raise SystemExit("live.wav RIFF body appeared before the header terminator")
PY
cleanup_stream_test
trap - EXIT
controls_json="$("$python_bin" "$api" audio-start NOAA_NFM --simulate squelch_db=-58 deemphasis=50us agc=fast_attack output_gain=1.5 noise_gate_db=-85 dc_block=0)"
printf '%s\n' "$controls_json" | "$python_bin" -c 'import json, sys
payload = json.load(sys.stdin)
controls = payload["audio"]["controls"]
assert controls["squelch_db"] == -58.0
assert controls["deemphasis"] == "50us"
assert controls["agc"] == "fast_attack"
assert controls["output_gain"] == 1.5
assert controls["noise_gate_db"] == -85.0
assert controls["dc_block"] is False'
"$python_bin" "$api" capture-start IQ_CAPTURE --simulate >/dev/null
"$python_bin" "$api" spectrum-snapshot IQ_CAPTURE --simulate >/dev/null
"$python_bin" "$api" spectrum-top IQ_CAPTURE --simulate >/dev/null
"$python_bin" "$api" spectrum-stream IQ_CAPTURE --simulate frames=2 interval_ms=50 bins=32 | "$python_bin" -c 'import json, sys
rows = [json.loads(line) for line in sys.stdin if line.strip()]
assert len(rows) == 2
assert all(row.get("type") == "spectrum_row" for row in rows)
assert all(len(row.get("points", [])) == 32 for row in rows)'
REQUEST_METHOD=GET QUERY_STRING='path=/radio/spectrum/snapshot&profile=IQ_CAPTURE&frequency_hz=162550000&bins=64&simulate=true' \
	"$python_bin" "$api" >/dev/null
REQUEST_METHOD=GET QUERY_STRING='path=/radio/spectrum/top&profile=IQ_CAPTURE&frequency_hz=162550000&top_n=3&simulate=true' \
	"$python_bin" "$api" >/dev/null
REQUEST_METHOD=GET QUERY_STRING='path=/radio/spectrum/stream&profile=IQ_CAPTURE&frequency_hz=162550000&bins=32&frames=2&interval_ms=50&simulate=true' \
	"$python_bin" "$api" | "$python_bin" -c 'import json, sys
data = sys.stdin.read()
header, body = data.split("\n\n", 1)
assert "Content-Type: application/x-ndjson" in header
rows = [json.loads(line) for line in body.splitlines() if line.strip()]
assert len(rows) == 2
assert rows[0]["type"] == "spectrum_row"'
"$python_bin" "$api" loopback-start LOOPBACK_TEST --simulate >/dev/null
"$python_bin" "$api" tx-start TX_TEST_TONE --simulate >/dev/null
"$python_bin" "$api" tx-start TX_TEST_TONE --simulate tx_mode=carrier >/dev/null
"$python_bin" "$api" tx-start TX_AUDIO_AM --simulate >/dev/null
"$python_bin" "$api" tx-start TX_AUDIO_FM --simulate tx_audio_tone_hz=1200 tx_fm_deviation_hz=3500 >/dev/null
"$python_bin" "$api" tx-start TX_CW --simulate tx_cw_text='CQ TEST' tx_cw_wpm=18 >/dev/null
"$python_bin" "$api" tx-stop >/dev/null
"$python_bin" "$api" doppler-plan SAT_AUDIO_NFM >/dev/null
"$python_bin" "$api" doppler-start >/dev/null
"$python_bin" "$api" doppler-tick >/dev/null
"$python_bin" "$api" doppler-stop >/dev/null
"$python_bin" scripts/check-firmware-size-budget.py >/dev/null

tmp_pcm="${TMPDIR:-/tmp}/pluto-audio-backend-test.$$.pcm"
trap 'rm -f "$tmp_pcm"' EXIT
PLUTO_AUDIO_SOURCE=synthetic \
PLUTO_AUDIO_FIFO="$tmp_pcm" \
PLUTO_AUDIO_DEMOD=nfm \
PLUTO_AUDIO_RATE_HZ=8000 \
PLUTO_DSP_INPUT_RATE_HZ=48000 \
PLUTO_AUDIO_FILTER_WIDTH_HZ=3000 \
PLUTO_AUDIO_SQUELCH_DB=-80 \
PLUTO_AUDIO_DEEMPHASIS=50us \
PLUTO_AUDIO_AGC=fast_attack \
PLUTO_AUDIO_OUTPUT_GAIN=1.25 \
PLUTO_AUDIO_NOISE_GATE_DB=-100 \
PLUTO_AUDIO_DC_BLOCK=1 \
PLUTO_AUDIO_TEST_SECONDS=1 \
	"$python_bin" buildroot/board/pluto/pluto-audio-backend
if [ ! -s "$tmp_pcm" ]; then
	echo "DSP audio backend did not produce PCM output" >&2
	exit 1
fi
rm -f "$tmp_pcm"

if "$python_bin" "$api" audio-start IQ_CAPTURE --simulate >/dev/null 2>&1; then
	echo "IQ capture profile was accepted as an audio stream" >&2
	exit 1
fi

if "$python_bin" "$api" audio-start NOAA_NFM --simulate deemphasis=bad >/dev/null 2>&1; then
	echo "invalid deemphasis control was accepted" >&2
	exit 1
fi

if "$python_bin" "$api" audio-start NOAA_NFM --simulate output_gain=99 >/dev/null 2>&1; then
	echo "out-of-range audio output gain was accepted" >&2
	exit 1
fi

if "$python_bin" "$api" loopback-start NOAA_NFM --simulate >/dev/null 2>&1; then
	echo "non-TX profile was accepted for loopback" >&2
	exit 1
fi

if "$python_bin" "$api" tx-start NOAA_NFM --simulate >/dev/null 2>&1; then
	echo "non-TX profile was accepted for TX" >&2
	exit 1
fi

if PLUTO_RADIO_DRY_RUN=0 "$python_bin" "$api" loopback-start LOOPBACK_TEST >/dev/null 2>&1; then
	echo "live loopback started without confirmation" >&2
	exit 1
fi

if PLUTO_RADIO_DRY_RUN=0 "$python_bin" "$api" tx-start TX_TEST_TONE >/dev/null 2>&1; then
	echo "live TX started without confirmation" >&2
	exit 1
fi

if "$python_bin" "$api" loopback-start LOOPBACK_TEST --simulate tx_amplitude=1.0 >/dev/null 2>&1; then
	echo "out-of-range loopback amplitude was accepted" >&2
	exit 1
fi

if "$python_bin" "$api" tx-start TX_TEST_TONE --simulate tx_amplitude=1.0 >/dev/null 2>&1; then
	echo "out-of-range TX amplitude was accepted" >&2
	exit 1
fi

if "$python_bin" "$api" tx-start TX_TEST_TONE --simulate tx_tone_hz=0 >/dev/null 2>&1; then
	echo "invalid tone-mode TX tone was accepted" >&2
	exit 1
fi

if "$python_bin" "$api" tx-start TX_AUDIO_AM --simulate tx_audio_source=file >/dev/null 2>&1; then
	echo "file audio TX was accepted without an audio path" >&2
	exit 1
fi

if "$python_bin" "$api" tx-start TX_AUDIO_FM --simulate tx_fm_deviation_hz=999999 >/dev/null 2>&1; then
	echo "out-of-range FM deviation was accepted" >&2
	exit 1
fi

if "$python_bin" "$api" tx-start TX_CW --simulate tx_cw_text='BAD!' >/dev/null 2>&1; then
	echo "unsupported CW text was accepted" >&2
	exit 1
fi

if "$python_bin" "$api" apply NOT_A_PROFILE >/dev/null 2>&1; then
	echo "invalid profile was accepted" >&2
	exit 1
fi

if "$python_bin" "$api" tune 1 >/dev/null 2>&1; then
	echo "out-of-range tune was accepted" >&2
	exit 1
fi

echo "pluto-radio-api-checks-ok"
