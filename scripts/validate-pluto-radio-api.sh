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
PLUTO_RADIO_DRY_RUN=1 "$python_bin" - "$api" "$profiles" <<'PY'
import importlib.util
import json
import sys
from importlib.machinery import SourceFileLoader
from pathlib import Path

api_path = Path(sys.argv[1])
profile_dir = Path(sys.argv[2])
loader = SourceFileLoader("pluto_radio_api_sample_rate_validation", str(api_path))
spec = importlib.util.spec_from_loader("pluto_radio_api_sample_rate_validation", loader)
api = importlib.util.module_from_spec(spec)
loader.exec_module(api)

floor = api.MIN_AD9361_SAMPLE_RATE_HZ
assert floor == 520833
assert api.parse_iio_available_range("[2083333 1 61440000]")["min"] == 2083333
for path in sorted(profile_dir.glob("*.json")):
    payload = json.loads(path.read_text(encoding="utf-8"))
    if int(payload["sample_rate_hz"]) < floor:
        raise SystemExit(f"{path.name} sample_rate_hz is below AD9361 floor")
try:
    api.clean_profile(
        {
            "name": "BAD_SAMPLE_RATE",
            "default_frequency_hz": 145800000,
            "sample_rate_hz": 100000,
            "rf_bandwidth_hz": 200000,
        },
        profile_dir / "BAD_SAMPLE_RATE.json",
    )
except api.ApiError:
    pass
else:
    raise SystemExit("1 MSPS profile unexpectedly passed validation")
PY
"$python_bin" "$api" profiles >/dev/null
"$python_bin" "$api" status >/dev/null
"$python_bin" "$api" health >/dev/null
PLUTO_RADIO_API_MODE=lighttpd-python-http "$python_bin" - "$api" <<'PY'
import importlib.util
import json
import os
import sys
from pathlib import Path

source = Path("buildroot/board/pluto/pluto-audio-dsp/pluto-audio-backend.c").read_text(encoding="utf-8")
assert "errno == EINTR" in source
assert "PLUTO_AUDIO_BACKEND_STATUS_FILE" in source
assert "audio_sink_open_failed" in source
assert "sink = open_audio_sink(fifo, regular_sink);" in source
assert "iio_context_set_timeout" in source
assert "pcm_bytes" in source
assert "iio_buffer_first(buf, q_chan)" in source
assert "phase" in source
assert "dsp_push_iq" in source
assert "dsp->iq_decim" in source
assert "processing_sample_rate_hz" in source
assert "pcm_rate_hz" in source
assert "PLUTO_AUDIO_FM_CHANNEL_FILTER" in source
assert "PLUTO_AUDIO_FM_LIMITER" in source
assert "fm_channel_filter" in source
assert "fm_limiter" in source

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
    with urllib.request.urlopen(base + "/radio/profile/list", timeout=5) as response:
        profiles_payload = json.loads(response.read().decode("utf-8"))
    assert profiles_payload["ok"] is True
    with urllib.request.urlopen(base + "/system/metrics", timeout=5) as response:
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
"$python_bin" "$api" demod-self-test --simulate >/dev/null
"$python_bin" "$api" audio-stop >/dev/null
tmp_stream_dir="$(mktemp -d "${TMPDIR:-/tmp}/pluto-audio-stream-test.XXXXXX")"
tmp_stream_out="${TMPDIR:-/tmp}/pluto-audio-stream-test.$$.out"
cleanup_stream_test() {
	rm -rf "$tmp_stream_dir"
	rm -f "$tmp_stream_out"
}
trap cleanup_stream_test EXIT
PLUTO_RADIO_API_MODE=lighttpd-python-http "$python_bin" - "$api" "$tmp_stream_dir" "$tmp_stream_out" <<'PY'
import importlib.util
import json
import os
import subprocess
import sys
import threading
import time
import urllib.request
from importlib.machinery import SourceFileLoader
from pathlib import Path

api_path = Path(sys.argv[1])
state_dir = Path(sys.argv[2])
out_path = Path(sys.argv[3])
loader = SourceFileLoader("pluto_radio_api", str(api_path))
spec = importlib.util.spec_from_loader("pluto_radio_api", loader)
api = importlib.util.module_from_spec(spec)
loader.exec_module(api)

api.STATE_DIR = state_dir
api.STATE_FILE = state_dir / "state.json"
api.AUDIO_BACKEND_STATUS_FILE = state_dir / "audio-backend-status.json"
api.AUDIO_STATE_FILE = state_dir / "audio.json"
api.AUDIO_FIFO = state_dir / "audio.pcm"
os.environ["PLUTO_RADIO_DRY_RUN"] = "0"
state_dir.mkdir(parents=True, exist_ok=True)
if hasattr(os, "mkfifo"):
    os.mkfifo(api.AUDIO_FIFO)
else:
    api.AUDIO_FIFO.write_bytes(b"\x00" * 32768)
fake_backend = state_dir / "fake-sim-backend"
fake_backend.write_text("#!/bin/sh\nsleep 1\n", encoding="utf-8")
fake_backend.chmod(0o755)
old_backend = subprocess.Popen(["sh", "-c", "sleep 30"])
api.AUDIO_STATE_FILE.write_text(
    json.dumps(
        {
            "state": "running",
            "profile": "NOAA_NFM",
            "demod_mode": "nfm",
            "audio_rate_hz": 8000,
            "stream_format": "pcm_s16le",
            "fifo_path": str(api.AUDIO_FIFO),
            "pid": old_backend.pid,
            "backend": "validation",
        }
    ),
    encoding="utf-8",
)
api.SIM_AUDIO_BACKEND = fake_backend
api.start_audio({"profile": "NOAA_NFM", "simulate": "true"})
switched = json.loads(api.AUDIO_STATE_FILE.read_text(encoding="utf-8"))
if switched.get("backend") != "simulated_pcm":
    raise SystemExit("simulate=true did not switch a running external audio backend")
if switched.get("backend_path") != str(fake_backend):
    raise SystemExit("simulate=true did not select the simulated audio backend path")
api.stop_audio()
old_backend.wait(timeout=2)
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
            "backend": "external",
        }
    ),
    encoding="utf-8",
)
api.AUDIO_BACKEND_STATUS_FILE.write_text(
    json.dumps(
        {
            "state": "error",
            "pid": os.getpid(),
            "last_error": {"code": "audio_sink_open_failed", "message": "interrupted"},
        }
    ),
    encoding="utf-8",
)
failed_status = api.audio_status()["audio"]
if failed_status["state"] != "error" or failed_status["last_error"]["code"] != "audio_sink_open_failed":
    raise SystemExit("audio backend sidecar failure did not propagate to audio status")
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
            "backend": "external",
        }
    ),
    encoding="utf-8",
)
api.AUDIO_BACKEND_STATUS_FILE.write_text(
    json.dumps(
        {
            "state": "running",
            "pid": os.getpid(),
            "iio_refills": 2,
            "pcm_bytes": 4096,
            "rms_level": 0.25,
            "squelch_state": "open",
            "phase": "iio_streaming",
        }
    ),
    encoding="utf-8",
)
running_status = api.audio_status()["audio"]
if running_status["pcm_bytes"] != 4096 or running_status["iio_refills"] != 2 or running_status["squelch_state"] != "open" or running_status["phase"] != "iio_streaming":
    raise SystemExit("audio backend running metrics did not propagate to audio status")
os.environ["PLUTO_RADIO_DRY_RUN"] = "1"
try:
    retune = api.audio_retune({"profile": "NOAA_NFM", "frequency_hz": 162550000, "gain_db": 42})
    if retune["state"]["stream_state"] != "audio":
        raise SystemExit("audio retune did not preserve stream_state=audio")
    if not any(item.get("attr") == "ensm_mode" and item.get("value") == "fdd" for item in retune["writes"]):
        raise SystemExit("audio retune did not force ENSM fdd")
finally:
    os.environ.pop("PLUTO_RADIO_DRY_RUN", None)
old_read_attr = api.read_attr
try:
    api.read_attr = lambda device, attr: "alert" if attr == "ensm_mode" else old_read_attr(device, attr)
    wedged_status = api.audio_status()["audio"]
    if wedged_status["state"] != "error" or wedged_status["last_error"]["code"] != "rx_chain_not_streaming":
        raise SystemExit("audio status did not report ENSM alert while backend claimed streaming")
finally:
    api.read_attr = old_read_attr
api.clear_audio_backend_status()
if api.audio_stream_length({}, 8000) is not None:
    raise SystemExit("omitted seconds did not default to continuous audio")
if api.audio_stream_length({"continuous": "true"}, 8000) is not None:
    raise SystemExit("continuous audio stream did not report unbounded length")
if api.audio_stream_length({"seconds": "0"}, 8000) is not None:
    raise SystemExit("seconds=0 audio stream did not report unbounded length")
if api.audio_stream_length({"seconds": "2"}, 8000) != 32000:
    raise SystemExit("bounded seconds=2 audio stream length was not 2 seconds of PCM")
if api.audio_stream_wav_data_bytes(None) <= 8000 * 2:
    raise SystemExit("continuous wav header size was not expanded for browser streaming")
reader_fd, writer_fd = os.pipe()
try:
    def fifo_writer():
        time.sleep(0.01)
        os.write(writer_fd, b"ready")

    writer_thread = threading.Thread(target=fifo_writer, daemon=True)
    started = time.monotonic()
    writer_thread.start()
    if api.read_audio_fifo_chunk(reader_fd, 16, timeout_seconds=0.2) != b"ready":
        raise SystemExit("audio FIFO readiness read did not return queued PCM")
    if time.monotonic() - started >= 0.1:
        raise SystemExit("audio FIFO readiness read added avoidable stream latency")
    writer_thread.join(timeout=1)
finally:
    os.close(reader_fd)
    os.close(writer_fd)
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
    if not hasattr(os, "mkfifo"):
        return
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
server = api.RadioApiHttpServer(("127.0.0.1", 0), api.RadioApiHttpHandler)
server_thread = threading.Thread(target=server.serve_forever, daemon=True)
server_thread.start()
try:
    base = f"http://127.0.0.1:{server.server_address[1]}"
    with urllib.request.urlopen(base + "/radio/audio/live.wav?seconds=1", timeout=5) as response:
        if response.status != 200:
            raise SystemExit(f"unexpected live.wav HTTP status {response.status}")
        if response.headers.get("Content-Type") != "audio/wav":
            raise SystemExit("live.wav did not return audio/wav")
        if response.headers.get("Content-Length") != str(8000 * 2 + 44):
            raise SystemExit("bounded live.wav did not include the expected Content-Length")
        out_path.write_bytes(response.read(4096))
finally:
    server.shutdown()
    server.server_close()
thread.join(timeout=1)
PY
"$python_bin" - "$tmp_stream_out" <<'PY'
from pathlib import Path
import sys

data = Path(sys.argv[1]).read_bytes()
if not data.startswith(b"RIFF"):
    raise SystemExit("live.wav HTTP body did not start with RIFF")
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
PLUTO_RADIO_API_MODE=lighttpd-python-http "$python_bin" - "$api" <<'PY'
import importlib.util
import json
import sys
from pathlib import Path

source = Path("buildroot/board/pluto/pluto-audio-dsp/pluto-audio-backend.c").read_text(encoding="utf-8")
assert "errno == EINTR" in source
assert "PLUTO_AUDIO_BACKEND_STATUS_FILE" in source
assert "audio_sink_open_failed" in source
assert "sink = open_audio_sink(fifo, regular_sink);" in source
assert "iio_context_set_timeout" in source
assert "pcm_bytes" in source
assert "iio_buffer_first(buf, q_chan)" in source
assert "phase" in source
assert "PLUTO_AUDIO_FM_CHANNEL_FILTER" in source
assert "PLUTO_AUDIO_FM_LIMITER" in source
assert "fm_channel_filter" in source
assert "fm_limiter" in source

import threading
import urllib.request
from importlib.machinery import SourceFileLoader
from pathlib import Path

api_path = Path(sys.argv[1])
loader = SourceFileLoader("pluto_radio_api_spectrum_http_validation", str(api_path))
spec = importlib.util.spec_from_loader("pluto_radio_api_spectrum_http_validation", loader)
api = importlib.util.module_from_spec(spec)
loader.exec_module(api)

server = api.RadioApiHttpServer(("127.0.0.1", 0), api.RadioApiHttpHandler)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
base = f"http://127.0.0.1:{server.server_address[1]}"
try:
    with urllib.request.urlopen(base + "/radio/spectrum/snapshot?profile=IQ_CAPTURE&frequency_hz=162550000&bins=64&simulate=true", timeout=5) as response:
        snapshot = json.loads(response.read().decode("utf-8"))
    assert snapshot["ok"] is True

    with urllib.request.urlopen(base + "/radio/spectrum/top?profile=IQ_CAPTURE&frequency_hz=162550000&top_n=3&simulate=true", timeout=5) as response:
        top = json.loads(response.read().decode("utf-8"))
    assert top["ok"] is True

    with urllib.request.urlopen(base + "/radio/spectrum/stream?profile=IQ_CAPTURE&frequency_hz=162550000&bins=32&frames=2&interval_ms=50&simulate=true", timeout=5) as response:
        if response.headers.get("Content-Type") != "application/x-ndjson":
            raise SystemExit("spectrum stream did not return NDJSON")
        rows = [json.loads(line) for line in response.read().decode("utf-8").splitlines() if line.strip()]
    assert len(rows) == 2
    assert rows[0]["type"] == "spectrum_row"
finally:
    server.shutdown()
    server.server_close()
PY
"$python_bin" "$api" loopback-start LOOPBACK_TEST --simulate >/dev/null
"$python_bin" "$api" loopback-demod --simulate --confirm-live-tx >/dev/null
"$python_bin" "$api" loopback-demod-status >/dev/null
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

if PLUTO_RADIO_DRY_RUN=0 "$python_bin" "$api" loopback-demod simulate=0 >/dev/null 2>&1; then
	echo "live loopback demod started without confirmation" >&2
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
