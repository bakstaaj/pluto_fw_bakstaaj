# Pluto Firmware Radio API Contract

This document is the app-builder contract for the Pluto firmware radio service.
It describes the HTTP API exposed on the Pluto itself and the matching
`pluto-radio-api` CLI used for on-device operation and host-side validation.

## Transport

The current firmware uses a resident Python API process behind lighttpd:

- `pluto-radio-api serve host=127.0.0.1 port=8081` owns the firmware API.
- lighttpd serves static files from `/www` on port 80.
- lighttpd reverse-proxies API routes from port 80 to the resident API.
- lighttpd streams long-lived proxy responses to clients as they arrive; it
  does not wait for an audio or spectrum stream to finish before sending it.
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
POST /radio/audio/retune
POST /radio/audio/demod-self-test
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
GET  /radio/loopback/demod/status
GET  /radio/loopback/cw/status
POST /radio/loopback/start
POST /radio/loopback/demod
POST /radio/loopback/cw
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
  "sample_rate_hz": 520999,
  "rf_bandwidth_hz": 521000,
  "fir_enabled": true,
  "gain_control_mode": "manual",
  "gain_db": 55,
  "demod_mode": "nfm",
  "audio_rate_hz": 48000,
  "filter_width_hz": 16100,
  "frequency_shift_hz": 400,
  "stream_format": "pcm_s16le",
  "tx_allowed": false
}
```

Profiles for externally translated RF may include:

```json
{
  "name": "CB_AM_HAMITUP",
  "source_frequency_hz": 27185000,
  "frequency_translation_hz": 125000000,
  "translated_frequency_hz": 152185000,
  "default_frequency_hz": 152185000
}
```

`default_frequency_hz` is always the Pluto LO frequency and must remain within
the Pluto tuning range. For upconverter profiles,
`translated_frequency_hz` must equal `source_frequency_hz +
frequency_translation_hz`. Apps may display `source_frequency_hz` to the user
while sending the translated/default Pluto frequency to firmware.

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
sample_rate_hz: 520.833 kSPS to 61.44 MSPS, validated against the active
AD9361 clock/filter path
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

The AD9361 driver computes the valid sample-rate range from the active clock and
FIR filter path. Profiles may request `fir_enabled=true`; firmware applies
`in_out_voltage_filter_fir_en=1` before validating and writing
`in_voltage_sampling_frequency`, so low-rate profiles use the same FIR-decimated
path reported by `in_voltage_sampling_frequency_available`.

Bundled `NOAA_NFM` defaults are aligned with the validated SDRSharp receive
path for NOAA weather testing: `fir_enabled=true`,
`sample_rate_hz=520999`, `rf_bandwidth_hz=521000`, `gain_db=55`,
`filter_width_hz=16100`, `frequency_shift_hz=400`, `deemphasis=75us`, and
`output_gain=2.0`. The `frequency_shift_hz` value is a DSP demodulation offset;
it does not change `requested_frequency_hz`. The production NFM backend also
uses FM channel filtering and limiting before quadrature demodulation; apps do
not need to implement these receiver-DSP details.

Bundled audio receive profiles use the same validated low-rate FIR path unless
the modulation requires a wider bandwidth. `SAT_AUDIO_NFM`,
`VHF_AUDIO_NFM_LOOPBACK`, and `UHF_AUDIO_NFM_LOOPBACK` are narrowband FM audio
profiles. `SAT_CW` and `UHF_CW_LOOPBACK` are CW monitor profiles with a
browser-friendly BFO tone. `CB_AM_HAMITUP` is an AM audio profile for CB channel
19 through a Ham It Up +125 MHz upconverter.

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

Returns persisted calibration metadata and the same guardrails. RX calibration is
firmware-managed: clients request the desired channel center in `frequency_hz`,
and firmware applies `rx_frequency_offset_hz` when programming the AD9361 RX LO.
Apps should not scan or shop around nearby frequency shifts for ordinary NOAA or
satellite use.

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

Behavior:

- `rx_frequency_offset_hz` is persisted and automatically applied to all RX tune
  paths: `/radio/profile/apply`, `/radio/tune`, `/radio/audio/retune`, audio
  start requests that include tuning fields, and Doppler retune ticks.
- If a channel is already tuned when calibration is changed, firmware retunes
  the current `requested_frequency_hz` immediately using the new offset.
- `radio.requested_frequency_hz` remains the user/app requested channel center.
  `radio.hardware_frequency_hz` and `radio.actual_frequency_hz` report the LO
  value written/read from the AD9361 after calibration is applied.
- `frequency_shift_hz` remains a DSP/off-center-demod control. It is not the
  normal way to compensate for device LO calibration.

`POST /radio/calibration/measure`

Measures RX frequency calibration from a known external reference carrier and
returns a recommended persistent `rx_frequency_offset_hz`. This is the preferred
calibration workflow; clients should not guess offsets by shopping around
channels.

Request:

```json
{
  "profile": "NOAA_NFM",
  "reference_frequency_hz": 162500000,
  "gain_db": 45,
  "gain_control_mode": "manual",
  "span_hz": 50000,
  "search_hz": 25000,
  "bins": 1024,
  "measurements": 3,
  "min_snr_db": 8,
  "apply": false
}
```

Behavior:

- Stops any running audio session before measuring, because RX streaming and
  spectrum capture cannot safely share the AD9361 receive path.
- Tunes the selected profile to `reference_frequency_hz`, using the currently
  persisted `rx_frequency_offset_hz`.
- Captures one or more spectrum snapshots, finds the strongest in-window peak,
  and computes:
  - `measured_peak_offset_hz = peak_frequency_hz - reference_frequency_hz`
  - `recommended_rx_frequency_offset_hz =
    current_rx_frequency_offset_hz + measured_peak_offset_hz`
- If `apply=true`, persists the recommended offset by calling the same behavior
  as `/radio/calibration/apply` and retunes the current requested frequency.
- Requires an external known-good RF reference. A Pluto TX-to-RX loopback is
  useful for demod/audio testing, but it is not an absolute frequency
  calibration reference because TX and RX share the same clock.

Response:

```json
{
  "ok": true,
  "calibration_measurement": {
    "profile": "NOAA_NFM",
    "reference_frequency_hz": 162500000,
    "span_hz": 50000,
    "search_hz": 25000,
    "bins": 1024,
    "bin_width_hz": 48.88,
    "measurements_requested": 3,
    "measurements_used": 3,
    "current_rx_frequency_offset_hz": 0,
    "measured_peak_offset_hz": -850,
    "recommended_rx_frequency_offset_hz": -850,
    "confidence": "high",
    "samples": [
      {
        "measurement": 1,
        "frequency_hz": 162499150,
        "measured_peak_offset_hz": -850,
        "power_dbfs": -42.1,
        "snr_db": 31.5
      }
    ],
    "rejected": [],
    "applied": null
  }
}
```

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
  "deemphasis": "75us",
  "agc": "fast_attack",
  "frequency_shift_hz": 400,
  "iq_mode": "normal",
  "output_gain": 2.0,
  "noise_gate_db": -85,
  "dc_block": false
}
```

Behavior:

- Validates the selected profile has an audio demod mode.
- For live production audio, applies the selected profile/frequency and forces the RX chain into `ensm_mode=fdd` before streaming.
- `frequency_shift_hz` is optional and defaults to `0`. It asks the firmware
  DSP to mix the received complex I/Q before demodulation, which lets an app
  tune the RX LO off-center while keeping demodulation centered in firmware.
  Valid range is plus/minus half of the selected profile sample rate.
  Apps should normally use the profile default; for `NOAA_NFM` that default is
  `400` Hz based on the validated local receive path.
- `iq_mode` is optional and defaults to `normal`. It is a firmware diagnostic
  control for live I/Q interpretation. Valid values are `normal`, `swap`,
  `invert_i`, `invert_q`, `conjugate`, `invert_both`, `swap_invert_i`,
  `swap_invert_q`, and `swap_invert_both`. Applications should leave this at
  `normal` unless firmware diagnostics identify an I/Q ordering or sign issue.
- Starts `/usr/sbin/pluto-audio-backend` for production audio.
- Uses `/usr/sbin/pluto-audio-sim-backend` when `simulate=true`.
- If audio is already running, an identical start request is idempotent and
  returns the current state.
- If audio is already running with the same profile, demod, controls, and
  backend mode, `frequency_hz`, `gain_db`, and `gain_control_mode` are applied
  as an in-place retune without restarting the DSP backend.
- A start request that changes profile, demod controls, `frequency_shift_hz`, or backend mode stops
  the current backend and launches the requested backend. Applications should
  not manually sequence stop/apply/start for ordinary retunes.
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
  `audio.iio_refills`, `audio.pcm_bytes`, `audio.pcm_rate_hz`,
  `audio.pcm_measured_rate_hz`,
  `audio.input_sample_rate_hz`, `audio.frequency_shift_hz`,
  `audio.fm_channel_filter`, `audio.fm_limiter`,
  `audio.processing_sample_rate_hz`,
  `audio.iq_decimation`, `audio.phase`, `audio.rms_level`, and
  `audio.squelch_state`; a live session that cannot refill an IIO buffer is
  converted to `audio.state=error` instead of remaining silently idle.
- The production backend reads Pluto AD9361 RX buffers using the kernel-reported
  `le:S12/16>>0` scan element format. Firmware sign-extends those 12-bit I/Q
  samples before demodulation; applications receive decoded PCM and do not need
  to handle raw AD9361 sample packing.
- If the external backend reports active IIO streaming while AD9361 `ensm_mode`
  is not `fdd` or `rx`, the API reports `audio.state=error` with
  `audio.last_error.code=rx_chain_not_streaming`. This prevents dashboards from
  treating a wedged RF chain as healthy only because the backend process is
  alive.

`POST /radio/audio/retune`

Request:

```json
{
  "profile": "NOAA_NFM",
  "frequency_hz": 162550000,
  "gain_db": 42,
  "gain_control_mode": "manual"
}
```

Behavior:

- Intended for live frequency/gain changes while audio is running.
- Only updates RX LO and optional gain controls; it does not change sample rate,
  RF bandwidth, demod mode, filter width, squelch, backend, or audio format.
- Forces `ensm_mode=fdd` after the retune and preserves `stream_state=audio`
  when a session is active.
- Returns `409 audio_retune_profile_mismatch` if asked to retune a different
  profile than the running audio session. Use `/radio/audio/start` for profile
  or demod changes.

`POST /radio/audio/demod-self-test`

Runs a bounded firmware DSP self-test without transmitting RF. The API starts
`/usr/sbin/pluto-audio-backend` with `PLUTO_AUDIO_SOURCE=synthetic_fm`, feeds
it synthetic FM-modulated I/Q, reads decoded PCM from a temporary FIFO, and
reports the recovered audio tone metrics. Use this to separate demodulator
faults from antenna, cable, TX leakage, and AD9361 direct-conversion behavior.

Request:

```json
{
  "profile": "NOAA_NFM",
  "duration_seconds": 3,
  "capture_seconds": 3,
  "tone_hz": 1000,
  "fm_deviation_hz": 5000,
  "carrier_hz": 0,
  "frequency_shift_hz": 0,
  "simulate": true
}
```

Response:

```json
{
  "ok": true,
  "bounded": true,
  "demod_self_test": {
    "profile": "NOAA_NFM",
    "source": "synthetic_fm",
    "tone_hz": 1000,
    "fm_deviation_hz": 5000,
    "carrier_hz": 0,
    "frequency_shift_hz": 0,
    "metrics": {
      "sample_count": 144000,
      "duration_seconds": 3.0,
      "pcm_bytes": 288000,
      "rms_dbfs": -18.0,
      "peak_dbfs": -6.0,
      "tone_hz": 1000,
      "detected_tone_hz": 1000,
      "tone_error_hz": 0,
      "tone_dbfs": -14.0,
      "reference_dbfs": -58.0,
      "tone_snr_db": 44.0,
      "passed": true
    }
  }
}
```

`carrier_hz` may be paired with `frequency_shift_hz` to verify the DSP
frequency-shift path used by cabled loopback demod diagnostics.

The self-test is bounded. If the backend does not produce the requested PCM
before the deadline, firmware returns `503 demod_self_test_timeout` with
diagnostic details including bytes produced, target bytes, backend status, and a
backend log tail. It must not leave a background backend running.

Audio streams:

```text
GET /radio/audio/live.pcm
GET /radio/audio/live.wav
```

Applications should prefer `live.wav` for browser playback and `live.pcm` for
native clients that already know the sample format.

Decoded audio is mono signed 16-bit little-endian PCM. `audio_rate_hz` from
`/radio/audio/status` is the exact PCM sample rate; the `live.wav` header uses
the same value. Firmware must deliver that rate continuously while a live
reader is attached.

`pcm_rate_hz` is the configured decoded PCM sample rate and should match
`audio_rate_hz`, for example `48000` for NOAA_NFM. `pcm_measured_rate_hz` is
diagnostic reader-throughput telemetry from the latest backend report interval;
it can drop when no client is draining the FIFO and must not be used as the WAV
format rate. `input_sample_rate_hz`, `processing_sample_rate_hz`, and
`iq_decimation` expose the raw AD9361 rate and the firmware's CPU-saving I/Q
pre-decimation; applications should treat them as diagnostics and continue using
`audio_rate_hz`/`pcm_rate_hz` as the PCM/WAV format rate.

`live.wav` returns a normal HTTP response with `Content-Type: audio/wav`,
`Cache-Control: no-store`, a blank line, and then the WAV `RIFF` body. Clients
should not need to special-case a status-line-only WAV response.

When `seconds` is omitted, current firmware returns a bounded default clip. In
the tested build this default is approximately 2 seconds. Browser audio elements
that need long-lived playback must explicitly request continuous streaming with
`/radio/audio/live.wav?continuous=true` or `/radio/audio/live.wav?seconds=0`.

Clients may request `seconds=1..3600` for bounded snapshot captures. Bounded
responses end after the requested capture window. They may omit
`Content-Length` on the port-80 lighttpd surface, so clients must not treat a
missing `Content-Length` as proof that the stream is continuous.

Continuous responses intentionally omit a fixed `Content-Length`; on the
external port-80 surface they may use HTTP/1.1 chunked transfer encoding.
Headers and the WAV RIFF header are sent immediately. For continuous WAV, the
firmware uses a large WAV data length in the RIFF header and keeps writing PCM
until the client disconnects or the backend exits. A client timeout is therefore
an expected way to end a probe of a live stream, not an API error.

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

`POST /radio/loopback/demod`

Runs a bounded closed-loop FM demod diagnostic. This is different from
`/radio/loopback/start`: it uses the single-process `pluto-loopback-backend`
full-duplex path so one process owns both TX and RX IIO buffers. This avoids the
fragile two-process pattern where a TX backend and RX audio backend compete for
AD9361/IIO streaming state. The backend transmits a bounded FM audio tone,
captures RX IQ through the same process, applies the requested RX IF offset, and
reports whether the expected audio tone was recovered.

Recommended live cabled RF pairings:

```json
{
  "rx_profile": "VHF_AUDIO_NFM_LOOPBACK",
  "tx_profile": "TX_AUDIO_FM",
  "frequency_hz": 145950000,
  "rx_gain_db": 35,
  "tx_gain_db": -25,
  "tx_amplitude": 0.20,
  "confirm_live_tx": true
}
```

```json
{
  "rx_profile": "UHF_AUDIO_NFM_LOOPBACK",
  "tx_profile": "TX_AUDIO_FM",
  "frequency_hz": 915000000,
  "rx_if_offset_hz": 5000,
  "rx_gain_db": 45,
  "tx_gain_db": -30,
  "tx_amplitude": 0.15,
  "confirm_live_tx": true
}
```

General request shape:

```json
{
  "rx_profile": "UHF_AUDIO_NFM_LOOPBACK",
  "tx_profile": "TX_AUDIO_FM",
  "frequency_hz": 915000000,
  "rx_if_offset_hz": 5000,
  "duration_seconds": 5,
  "capture_seconds": 4,
  "rx_gain_db": 45,
  "tx_gain_db": -30,
  "tx_amplitude": 0.15,
  "tx_audio_tone_hz": 1000,
  "tx_fm_deviation_hz": 5000,
  "squelch_db": -120,
  "noise_gate_db": -120,
  "simulate": true
}
```

For a live cabled RF test, omit `simulate` and include:

```json
{
  "confirm_live_tx": true
}
```

Response fields:

```json
{
  "ok": true,
  "bounded": true,
  "loopback_demod": {
    "state": "complete",
    "rx_profile": "NOAA_NFM",
    "tx_profile": "TX_AUDIO_FM",
    "rx_frequency_hz": 915000000,
    "tx_frequency_hz": 915000000,
    "metrics": {
      "sample_count": 192000,
      "sample_rate_hz": 520999,
      "duration_ms": 4000,
      "tx_mode": "fm",
      "carrier_offset_hz": 25000,
      "rx_rms_dbfs": -78.0,
      "rx_peak_dbfs": -63.0,
      "demod_sample_count": 192000,
      "demod_rms": 0.31,
      "tone_hz": 1000,
      "detected_tone_hz": 1000,
      "tone_dbfs": -58.0,
      "reference_dbfs": -66.0,
      "tone_snr_db": 8.0,
      "pass_snr_db_min": 6.0,
      "passed": true,
      "backend": "pluto-loopback-backend"
    }
  }
}
```

Use `GET /radio/loopback/demod/status` to retrieve the last diagnostic result.

`POST /radio/loopback/cw`

Runs a bounded closed-loop CW diagnostic. Firmware starts the CW RX audio
path and bounded `TX_CW` inside the single-process `pluto-loopback-backend`
full-duplex path. It verifies recovered RF energy/keying on the cabled loopback
path and leaves the normal browser audio path untouched. It does not currently
decode Morse text.

Default receive/transmit pairing:

```json
{
  "rx_profile": "UHF_CW_LOOPBACK",
  "tx_profile": "TX_CW",
  "frequency_hz": 915000000,
  "duration_seconds": 6,
  "capture_seconds": 5,
  "rx_gain_db": 35,
  "tx_gain_db": -35,
  "tx_amplitude": 0.08,
  "tx_cw_text": "CQ TEST",
  "tx_cw_wpm": 12,
  "squelch_db": -120,
  "noise_gate_db": -120,
  "confirm_live_tx": true
}
```

Response fields:

```json
{
  "ok": true,
  "bounded": true,
  "loopback_cw": {
    "state": "complete",
    "mode": "cw",
    "rx_profile": "UHF_CW_LOOPBACK",
    "tx_profile": "TX_CW",
    "rx_frequency_hz": 915000000,
    "tx_frequency_hz": 915000000,
    "tx_cw_text": "CQ TEST",
    "tx_cw_wpm": 12,
    "metrics": {
      "sample_rate_hz": 520999,
      "tx_mode": "cw",
      "rx_rms_dbfs": -78.0,
      "rx_peak_dbfs": -63.0,
      "pass_criteria": {
        "rx_peak_dbfs_min": -85.0
      },
      "passed": true,
      "keying": {
        "requested_wpm": 12,
        "decode_supported": false,
        "decode_note": "This endpoint verifies recovered CW RF energy/keying. Morse text decode is not enabled yet."
      }
    }
  }
}
```

The current CW endpoint is an RF-path/keying diagnostic, not a Morse decoder.
Applications must treat `decode_supported=false` as authoritative until a text
decoder is added and validated.

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
