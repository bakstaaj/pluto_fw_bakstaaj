# Pluto Firmware Radio API Contract

This document is the app-builder contract for the Pluto firmware radio service.
It describes the HTTP API exposed on the Pluto itself and the matching
`pluto-radio-api` CLI used for on-device operation and host-side validation.

## Transport

The current firmware uses a resident Python API process behind lighttpd:

- `pluto-radio-api serve host=127.0.0.1 port=8081` owns the firmware API.
- lighttpd serves static files from `/www` on port 80.
- lighttpd reverse-proxies API routes from port 80 to the resident API.
- Browser clients and host-side tools normally use the port 80 lighttpd
  surface.
- On-device applications should use the resident API directly with
  `base_url=http://127.0.0.1:8081`.

Base URLs:

```text
External/browser base URL: http://192.168.2.1
On-device direct base URL: http://127.0.0.1:8081
```

Use logical API routes directly:

```text
GET  http://192.168.2.1/system/health
POST http://192.168.2.1/radio/profile/apply
GET  http://127.0.0.1:8081/system/health
POST http://127.0.0.1:8081/radio/profile/apply
```

POST bodies should be JSON:

```http
Content-Type: application/json
```

All control and status endpoints return JSON. Successful responses include
`"ok": true`. Errors use the same JSON shape:

```json
{
  "ok": false,
  "error": {
    "code": "out_of_range",
    "message": "frequency_hz must be between 70000000 and 6000000000",
    "details": {
      "frequency_hz": 1
    }
  }
}
```

## App Builder Quick Start

Read health:

```sh
curl "http://192.168.2.1/system/health"
```

List profiles:

```sh
curl "http://192.168.2.1/radio/profile/list"
```

Apply a profile:

```sh
curl -X POST "http://192.168.2.1/radio/profile/apply" \
  -H "Content-Type: application/json" \
  -d "{\"profile\":\"SAT_AUDIO_NFM\",\"frequency_hz\":145800000}"
```

Start decoded audio in simulation:

```sh
curl -X POST "http://192.168.2.1/radio/audio/start" \
  -H "Content-Type: application/json" \
  -d "{\"profile\":\"NOAA_NFM\",\"simulate\":true}"
```

Run a bounded TX test in simulation:

```sh
curl -X POST "http://192.168.2.1/radio/tx/start" \
  -H "Content-Type: application/json" \
  -d "{\"profile\":\"TX_TEST_TONE\",\"simulate\":true}"
```

Check guardrails before TX:

```sh
curl -X POST "http://192.168.2.1/radio/tx/guardrails" \
  -H "Content-Type: application/json" \
  -d "{\"profile\":\"TX_AUDIO_FM\",\"simulate\":true}"
```

Run the safe self-test bundle:

```sh
curl -X POST "http://192.168.2.1/system/self-test" \
  -H "Content-Type: application/json" \
  -d "{}"
```

Run a bounded live TX test only in a controlled RF setup:

```sh
curl -X POST "http://192.168.2.1/radio/tx/start" \
  -H "Content-Type: application/json" \
  -d "{\"profile\":\"TX_TEST_TONE\",\"confirm_live_tx\":true}"
```

Live TX emits RF. Use a dummy load, shielded setup, or a legal test frequency.

Sample app clients are available in `examples/python/pluto_radio_client.py` and
`examples/browser/pluto-radio-client.html`.

## Endpoint Summary

System:

```text
GET  /system/health
GET  /system/logs
GET  /system/watchdog
POST /system/watchdog/check
POST /system/self-test
GET  /system/self-test/status
```

Radio and profiles:

```text
GET  /radio/status
GET  /radio/profile/list
POST /radio/profile/apply
POST /radio/tune
POST /radio/stop
```

Decoded audio:

```text
GET  /radio/audio/status
POST /radio/audio/start
POST /radio/audio/stop
GET  /radio/audio/live.pcm
GET  /radio/audio/live.wav
```

Capture:

```text
POST /capture/start
GET  /capture/list
GET  /capture/metadata
GET  /capture/download
POST /capture/delete
```

Spectrum:

```text
GET  /radio/spectrum/status
GET  /radio/spectrum/snapshot
GET  /radio/spectrum/top
GET  /radio/spectrum/stream
POST /radio/spectrum/snapshot
POST /radio/spectrum/top
```

Loopback diagnostics:

```text
GET  /radio/loopback/status
POST /radio/loopback/start
```

Transmit:

```text
GET  /radio/tx/status
GET  /radio/tx/guardrails
POST /radio/tx/guardrails
POST /radio/tx/start
POST /radio/tx/stop
```

Calibration:

```text
GET  /radio/calibration/status
POST /radio/calibration/apply
```

Doppler:

```text
GET  /radio/doppler/status
POST /radio/doppler/plan
POST /radio/doppler/start
POST /radio/doppler/stop
POST /radio/doppler/tick
```

## Profiles

Profiles are JSON files loaded from:

```text
/mnt/jffs2/pluto-radio/profiles
/etc/pluto-radio/profiles
```

The persistent `/mnt/jffs2` directory wins, so applications can install or
override profiles without replacing the firmware image.

Common fields:

```json
{
  "name": "SAT_AUDIO_NFM",
  "label": "Satellite audio narrowband FM",
  "default_frequency_hz": 145800000,
  "sample_rate_hz": 2400000,
  "rf_bandwidth_hz": 200000,
  "gain_control_mode": "manual",
  "gain_db": 40,
  "demod_mode": "nfm",
  "audio_rate_hz": 48000,
  "filter_width_hz": 15000,
  "stream_format": "pcm_s16le",
  "tx_allowed": false
}
```

TX-capable profiles add explicit transmit fields:

```json
{
  "name": "TX_TEST_TONE",
  "tx_allowed": true,
  "tx_mode": "tone",
  "tx_duration_limit_seconds": 10,
  "tx_gain_db": -30.0,
  "tx_tone_hz": 10000,
  "tx_amplitude": 0.05
}
```

Audio and CW TX profiles add mode-specific fields:

```json
{
  "name": "TX_AUDIO_FM",
  "tx_mode": "fm",
  "tx_audio_source": "tone",
  "tx_audio_rate_hz": 8000,
  "tx_audio_tone_hz": 1000,
  "tx_fm_deviation_hz": 5000
}
```

Applications can provide audio by writing signed 16-bit little-endian mono PCM
to a file or FIFO under `/mnt/jffs2`, `/media`, `/tmp`, or `/var/run`, then
starting TX with `tx_audio_source=file` and `tx_audio_path=/path/to/audio.pcm`.

Validation bounds:

```text
frequency_hz: 70 MHz to 6 GHz
sample_rate_hz: 2.083334 MSPS to 61.44 MSPS for the default no-FIR AD9361
clock path used by this firmware
rf_bandwidth_hz: 200 kHz to 56 MHz
tx_gain_db: -89.75 dB to 0 dB
tx_amplitude: 0.0 to PLUTO_TX_MAX_AMPLITUDE, default 0.25
tx_audio_rate_hz: 8 kHz to 48 kHz
tx_audio_tone_hz: 20 Hz to 3 kHz
tx_am_modulation_index: 0.0 to 1.0
tx_fm_deviation_hz: 100 Hz to 25 kHz and below sample_rate_hz / 8
tx_cw_wpm: 5 to 40
tx_duration_limit_seconds: 0 to PLUTO_TX_MAX_SECONDS, default 30
loopback_duration_limit_seconds: 0 to PLUTO_LOOPBACK_MAX_SECONDS, default 10
```

The AD9361 driver computes the minimum sample rate from the active clock path.
In the default no-FIR path, the driver requires the ADC clock to remain at or
above 25 MHz, making the practical sample-rate floor `ceil(25 MHz / 12)` =
2,083,334 samples/second. Lower rates such as 1 MSPS can be valid only when an
appropriate FIR decimation path is active; this firmware does not assume that
path for bundled profiles.

## Guardrails and Calibration

`GET /radio/tx/guardrails`

Returns the current TX limits, supported modes, safe audio roots, and the live
TX confirmation rule. Apps should use this endpoint to populate UI bounds.

`POST /radio/tx/guardrails`

Request:

```json
{
  "profile": "TX_AUDIO_FM",
  "simulate": true,
  "duration_seconds": 1
}
```

Returns a validated plan plus readiness fields:

```json
{
  "ok": true,
  "plan": {},
  "readiness": {
    "simulation_ready": true,
    "live_ready": false,
    "radio_present": true,
    "confirmation_required": false,
    "blockers": [],
    "warnings": []
  }
}
```

`GET /radio/calibration/status`

Returns persisted calibration metadata and the same guardrails. Calibration
values are exposed to apps but are not silently applied to RF tuning yet.

`POST /radio/calibration/apply`

Request:

```json
{
  "rx_frequency_offset_hz": 12.5,
  "tx_frequency_offset_hz": 0,
  "rx_gain_offset_db": 0,
  "tx_gain_offset_db": -1,
  "notes": "bench note"
}
```

Bounds:

```text
rx_frequency_offset_hz, tx_frequency_offset_hz: -250 kHz to +250 kHz
rx_gain_offset_db, tx_gain_offset_db: -20 dB to +20 dB
notes: 200 characters
```

The response includes `applied_to_hardware=false` until hardware-validated
offset application is added.

## Self Test

`POST /system/self-test`

Runs a safe diagnostic bundle. It checks profiles, health surfaces, guardrails,
calibration status, simulated audio, simulated spectrum, simulated loopback, and
simulated tone/AM/FM/CW TX. It does not run live RF.

Optional request:

```json
{
  "require_radio": false,
  "tx_duration_seconds": 1
}
```

The response includes `self_test.state` as `pass`, `warn`, or `fail` and a
per-step result list for app diagnostics.

## System

`GET /system/health`

Returns a single JSON view for dashboards and app readiness checks:

```json
{
  "ok": true,
  "system": {
    "hostname": "pluto",
    "uptime_seconds": 1234,
    "api_mode": "lighttpd-python-http",
    "api_version": "0.1"
  },
  "radio": {},
  "audio": {},
  "watchdog": {},
  "loopback": {},
  "tx": {},
  "tx_guardrails": {},
  "tx_readiness": {},
  "calibration": {},
  "self_test": {},
  "doppler": {},
  "iio": {}
}
```

`GET /system/logs`

Query parameters:

```text
source=messages|syslog|audio|profile_check|dmesg
lines=1..500
```

The response is bounded JSON and should be safe for app log panels.

## Radio

`GET /radio/status`

Returns the active profile, requested/actual frequency, RX/TX IIO attributes,
stream state, and last error.

`POST /radio/profile/apply`

Request:

```json
{
  "profile": "SAT_AUDIO_NFM",
  "frequency_hz": 145800000,
  "gain_db": 40,
  "gain_control_mode": "manual"
}
```

Behavior:

- Applies RX LO, RX bandwidth, RX sample rate, gain mode, and manual gain.
- Stores state in `/var/run/pluto-radio/state.json`.
- Rejects invalid profiles and out-of-range values.

`POST /radio/tune`

Request:

```json
{
  "frequency_hz": 145800000
}
```

Updates only the RX LO and preserves the current profile.

`POST /radio/stop`

Stops audio, forces TX idle when possible, and moves radio state to idle.

## Decoded Audio

`POST /radio/audio/start`

Request:

```json
{
  "profile": "NOAA_NFM",
  "frequency_hz": 162550000,
  "simulate": true,
  "squelch_db": -58,
  "deemphasis": "50us",
  "agc": "fast_attack",
  "output_gain": 1.5,
  "noise_gate_db": -85,
  "dc_block": false
}
```

Behavior:

- Validates the selected profile has an audio demod mode.
- Optionally applies profile/frequency before streaming.
- Starts `/usr/sbin/pluto-audio-backend` for production audio.
- Uses `/usr/sbin/pluto-audio-sim-backend` when `simulate=true`.
- If audio is already running, an identical start request is idempotent and
  returns the current state. A start request that changes profile, controls, or
  backend mode stops the current backend and launches the requested backend.
- `audio.backend` is a status enum:
  - `external`: production or environment-overridden backend.
  - `simulated_pcm`: `/usr/sbin/pluto-audio-sim-backend` selected by
    `simulate=true`.
  - `dry_run`: host validation mode.
- Tracks state in `/var/run/pluto-radio/audio.json`.
- Production audio backend startup failures are reported through
  `audio.last_error` and force `audio.state` to `error`. The backend retries an
  interrupted FIFO sink open (`EINTR`) instead of silently becoming a live but
  non-producing process. Fatal backend startup details are also mirrored through
  `/var/run/pluto-radio/audio-backend-status.json` for diagnostics. While
  running, the same sidecar reports backend progress fields such as
  `audio.iio_refills`, `audio.pcm_bytes`, `audio.rms_level`, and
  `audio.squelch_state`; a live session that cannot refill an IIO buffer is
  converted to `audio.state=error` instead of remaining silently idle.

Audio streams:

```text
GET /radio/audio/live.pcm
GET /radio/audio/live.wav
```

Applications should prefer `live.wav` for browser playback and `live.pcm` for
native clients that already know the sample format.

`live.wav` returns a normal HTTP response with `Content-Type: audio/wav`,
`Cache-Control: no-store`, a blank line, and then the WAV `RIFF` body. Clients
should not need to special-case a status-line-only WAV response.

`POST /radio/audio/stop`

Stops the backend and removes the live FIFO.

## Capture

`POST /capture/start`

Request:

```json
{
  "profile": "IQ_CAPTURE",
  "type": "iq",
  "duration_seconds": 10,
  "max_bytes": 1048576,
  "simulate": true
}
```

Behavior:

- Stores capture metadata next to capture data.
- Allows storage only under `/mnt/jffs2` or `/media`.
- Enforces `PLUTO_CAPTURE_MAX_SECONDS` and `PLUTO_CAPTURE_MAX_BYTES`.
- Uses `/usr/sbin/pluto-capture-backend` when installed.

Use SD-card storage under `/media` for larger captures.

## Spectrum

`GET /radio/spectrum/snapshot`
`POST /radio/spectrum/snapshot`

Request:

```json
{
  "profile": "IQ_CAPTURE",
  "center_frequency_hz": 162550000,
  "span_hz": 200000,
  "bins": 256,
  "top_n": 5,
  "simulate": true
}
```

Returns bounded spectrum points and peak information.

Spectrum power field contract:

- Spectrum bin power is always reported as `points[].power_dbfs`.
- Peak power is always reported as `peaks[].power_dbfs`.
- Peak signal-to-noise ratio is reported as `peaks[].snr_db`.
- The estimated floor for a snapshot or stream row is reported as
  `noise_floor_dbfs`.
- These values are numeric dBFS values. More-positive values are stronger
  signals; for example, `-42.5` dBFS is stronger than `-90.25` dBFS.
- Apps should treat `power_dbfs` as the canonical signal-power field for
  spectrum data. Aliases such as `power`, `db`, `level`, `rssi`, or
  `signal_power` are not part of the firmware spectrum contract.
- Hardware receiver RSSI is a different measurement and appears in radio/IIO
  status as `rx_rssi_ch0` and `rx_rssi_ch1`, not in spectrum point arrays.

`GET /radio/spectrum/top`
`POST /radio/spectrum/top`

Uses the same input but returns only the peak list. Apps should use this when
they do not need the full point array.

`GET /radio/spectrum/stream`

Query parameters:

```text
profile=IQ_CAPTURE
center_frequency_hz=162550000
span_hz=200000
bins=192
top_n=5
frames=120
interval_ms=250
simulate=true
```

Returns `application/x-ndjson`, one JSON spectrum row per line. Each row is
bounded to the requested bin count and has this shape:

```json
{
  "ok": true,
  "type": "spectrum_row",
  "sequence": 0,
  "time_epoch": 1783713600,
  "sample_count": 4096,
  "sample_rate_hz": 2400000,
  "center_frequency_hz": 162550000,
  "span_hz": 200000,
  "bins": 192,
  "backend": "external_stream",
  "bounded": false,
  "points": [
    {"frequency_hz": 162450000, "power_dbfs": -90.25}
  ],
  "peaks": [
    {"frequency_hz": 162550000, "power_dbfs": -42.5, "snr_db": 47.0}
  ],
  "noise_floor_dbfs": -89.5
}
```

The stream is intentionally bounded by `frames` and
`PLUTO_SPECTRUM_MAX_STREAM_FRAMES`; browser clients should reconnect if they
want a continuous display beyond the current stream window.

## Loopback Diagnostics

`POST /radio/loopback/start`

Request:

```json
{
  "profile": "LOOPBACK_TEST",
  "duration_seconds": 5,
  "frequency_hz": 915000000,
  "tx_gain_db": -30,
  "tx_tone_hz": 10000,
  "tx_amplitude": 0.05,
  "simulate": true
}
```

Live loopback requires:

```json
{
  "confirm_live_tx": true
}
```

Behavior:

- Requires `tx_allowed=true` on the profile.
- Applies RX and TX configuration.
- Runs a bounded TX tone and RX measurement.
- Reports metrics such as sample count, RX RMS, RX peak, tone, duration, and
  sample rate.

Use loopback for firmware and application diagnostics. Use `/radio/tx/start`
for a transmit-only test.

## Transmit

`POST /radio/tx/start`

Request:

```json
{
  "profile": "TX_TEST_TONE",
  "duration_seconds": 10,
  "frequency_hz": 915000000,
  "tx_mode": "tone",
  "tx_gain_db": -30,
  "tx_tone_hz": 10000,
  "tx_amplitude": 0.05,
  "simulate": true
}
```

For live RF, omit `simulate` and add:

```json
{
  "confirm_live_tx": true
}
```

Supported `tx_mode` values:

```text
tone
carrier
am
fm
cw
```

Stock TX profiles:

```text
TX_TEST_TONE
TX_AUDIO_AM
TX_AUDIO_FM
TX_CW
```

Behavior:

- Requires a TX-enabled profile.
- Requires explicit confirmation for live RF.
- Bounds duration, amplitude, tone frequency, sample rate, TX gain, audio rate,
  modulation index/deviation, CW text, and CW speed.
- Applies TX LO, TX bandwidth, TX sample rate, TX gain, and ENSM mode.
- Runs `/usr/sbin/pluto-tx-backend`, currently a symlink to the small libiio
  backend also used by loopback.
- Returns bounded metrics and stores state in `/var/run/pluto-radio/tx.json`.

AM test-tone request:

```json
{
  "profile": "TX_AUDIO_AM",
  "duration_seconds": 5,
  "tx_audio_source": "tone",
  "tx_audio_tone_hz": 1000,
  "tx_am_modulation_index": 0.8,
  "simulate": true
}
```

FM PCM-file request:

```json
{
  "profile": "TX_AUDIO_FM",
  "duration_seconds": 5,
  "tx_audio_source": "file",
  "tx_audio_path": "/mnt/jffs2/tx-audio/test.pcm",
  "tx_audio_rate_hz": 8000,
  "tx_fm_deviation_hz": 5000,
  "simulate": true
}
```

CW request:

```json
{
  "profile": "TX_CW",
  "duration_seconds": 5,
  "tx_cw_text": "CQ PLUTO",
  "tx_cw_wpm": 12,
  "simulate": true
}
```

`POST /radio/tx/stop`

Forces ENSM to `alert` when possible and marks TX stopped.

## Doppler

`POST /radio/doppler/plan`

Request:

```json
{
  "profile": "SAT_AUDIO_NFM",
  "base_frequency_hz": 145800000,
  "start_utc": "2026-07-08T20:15:00Z",
  "stop_utc": "2026-07-08T20:27:00Z",
  "retune_interval_ms": 1000,
  "doppler_table": [
    { "offset_ms": 0, "frequency_hz": 145803200 },
    { "offset_ms": 1000, "frequency_hz": 145803050 }
  ]
}
```

Behavior:

- The application owns TLEs, pass prediction, satellite selection, and table
  generation.
- Firmware validates and stores the table.
- Firmware applies the base profile/frequency and reports current/next retune
  state.
- `PLUTO_DOPPLER_MAX_POINTS` and `PLUTO_DOPPLER_MIN_INTERVAL_MS` bound table
  size and retune cadence.

`POST /radio/doppler/start`

Starts `/usr/sbin/pluto-doppler-worker`.

`POST /radio/doppler/tick`

Runs one scheduler tick. This is useful for tests or an external supervisor.

`POST /radio/doppler/stop`

Stops the worker and leaves the last plan stored.

## CLI Equivalents

The HTTP API and CLI share the same validation code:

```text
pluto-radio-api status
pluto-radio-api health
pluto-radio-api profiles
pluto-radio-api apply PROFILE [FREQUENCY_HZ]
pluto-radio-api tune FREQUENCY_HZ
pluto-radio-api stop
pluto-radio-api audio-start PROFILE [--simulate] [key=value...]
pluto-radio-api audio-stop
pluto-radio-api audio-status
pluto-radio-api capture-start PROFILE [--simulate]
pluto-radio-api capture-list
pluto-radio-api spectrum-status
pluto-radio-api spectrum-snapshot PROFILE [--simulate]
pluto-radio-api spectrum-top PROFILE [--simulate]
pluto-radio-api loopback-status
pluto-radio-api loopback-start LOOPBACK_TEST [--simulate] [--confirm-live-tx] [key=value...]
pluto-radio-api tx-status
pluto-radio-api tx-start TX_TEST_TONE [--simulate] [--confirm-live-tx] [key=value...]
pluto-radio-api tx-stop
pluto-radio-api doppler-status
pluto-radio-api doppler-plan [PROFILE]
pluto-radio-api doppler-start
pluto-radio-api doppler-stop
pluto-radio-api doppler-tick
```

## Onboard Test Page

The firmware includes an app-builder test page:

```text
http://192.168.2.1/api-test.html
```

It exercises logical API routes from the browser and includes safe simulated
tests for health, profiles, audio, spectrum, loopback, and TX. The page sends
requests through the same-origin lighttpd proxy and shows the matching
on-device direct URL using `http://127.0.0.1:8081`. Live TX remains guarded by
an explicit checkbox and should only be used in a controlled RF setup.

## Validation

Host-side validation:

```sh
bash scripts/validate-pluto-radio-api.sh
bash scripts/check-pluto-build-hygiene.sh
python3 scripts/check-firmware-size-budget.py
```

The validation script:

- Compiles Python helpers.
- Loads all profile JSON files.
- Exercises status, health, apply, tune, simulated audio, spectrum, loopback,
  TX, Doppler, and invalid-input paths.
- Checks that the DSP reference backend can produce PCM from synthetic IQ.

The final acceptance check for release remains a full Buildroot image build and
target-rootfs inspection, because the production backends link against target
libraries.
