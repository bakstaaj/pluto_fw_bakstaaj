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

export PLUTO_RADIO_PROFILE_DIR="$profiles"
export PLUTO_RADIO_DRY_RUN=1

"$python_bin" -m py_compile "$api"
"$python_bin" -m py_compile buildroot/board/pluto/pluto-audio-backend
"$python_bin" -m py_compile buildroot/board/pluto/pluto-audio-sim-backend
"$python_bin" "$api" profiles >/dev/null
"$python_bin" "$api" status >/dev/null
"$python_bin" "$api" health >/dev/null
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
