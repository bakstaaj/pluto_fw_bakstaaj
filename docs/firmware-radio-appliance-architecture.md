# Pluto Firmware Radio Appliance Architecture

## Goal

The firmware image owns repeatable radio behavior. Applications own user intent,
pass selection, UI, filtering policy, and workflow.

This first milestone adds a firmware-side radio control surface that can be
reused by satellite audio, CW monitor, NOAA diagnostics, FM broadcast tests, IQ
capture tools, and future scanner-style applications.

## First Implemented Milestone

The firmware now carries:

- JSON radio profiles in `/etc/pluto-radio/profiles`.
- A small radio API helper at `/usr/sbin/pluto-radio-api`.
- A resident Python HTTP API on `127.0.0.1:8081`.
- lighttpd on port 80 for static dashboard/API-test pages and reverse proxying
  logical API routes to the resident API.
- A boot-time profile check in `/etc/init.d/S70pluto-radio-api`.
- Audio lifecycle endpoints for start/stop/status/live stream routing.
- A simulated PCM backend for validation and UI integration.
- A staged production audio DSP package using libiio and liquid-dsp.
- Health, logs, and bounded watchdog endpoints.
- Bounded capture metadata/list/delete/download API scaffold.
- Bounded spectrum snapshot, top-peak, and NDJSON stream API scaffold.
- Bounded Doppler plan executor and tiny retune worker.
- Firmware artifact size budget checks for rootfs, ITB/FRM, and release ZIPs.
- A host-side dry-run validation script at `scripts/validate-pluto-radio-api.sh`.

The implementation is deliberately userland-only. It does not require HDL, FPGA,
kernel, or libiio daemon changes.

## Profile Scope

Initial reusable profiles:

- `FM_BROADCAST_WFM`
- `NOAA_NFM`
- `SAT_AUDIO_NFM`
- `SAT_CW`
- `IQ_CAPTURE`
- `LOOPBACK_TEST`

Each profile defines the reusable radio/audio intent:

- Default frequency
- RX sample rate
- RX RF bandwidth
- RX gain mode
- RX gain value
- Demod/audio metadata for later audio service work
- Stream format metadata
- TX safety flag

Only RX-side radio configuration is applied in this milestone. TX remains
disabled by policy; no TX enable API exists yet.

## Audio Service Scope

The second milestone adds the firmware API and supervision surface for audio:

- `POST /radio/audio/start`
- `POST /radio/audio/stop`
- `GET /radio/audio/status`
- `GET /radio/audio/live.pcm`
- `GET /radio/audio/live.wav`

The API validates audio-capable profiles, records stream state, reports backend
errors as JSON, and exposes audio status through system health. A simulated PCM
backend is included so app and browser integration can be tested without RF.
Audio start requests are idempotent only when the requested profile, controls,
and backend mode match the current running session; changing from live RF to
`simulate=true` restarts the backend and switches to simulated PCM.

The production demodulator is intentionally isolated behind
`/usr/sbin/pluto-audio-backend`. That executable is launched with profile,
demod, input sample rate, audio-rate, filter, CW/BFO, and FIFO environment
variables. This keeps the app-facing API stable while the RF/audio DSP
implementation is tuned.

For production decoded audio, the firmware now stages a `pluto-audio-dsp`
Buildroot package. It compiles a small C backend around libiio and liquid-dsp.
That is the preferred path for clean NFM/WFM/AM/CW audio because the hard DSP
parts stay in a maintained SDR library instead of growing into custom firmware
code. The Python `/usr/sbin/pluto-audio-ref-backend` remains as a small
reference/fallback path and host validation aid, not as the final quality target.

Audio status is part of the API contract, not an app-local convention. The
production backend writes `/var/run/pluto-radio/audio-backend-status.json`; the
API merges that report into `/radio/audio/status` and `/system/health`.
`audio.rms_level` is a nullable linear full-scale PCM RMS ratio, not dBFS.
`audio.squelch_state` is the enum `unknown`, `disabled`, `open`, or `closed`.
Apps should use those fields for level and gate indicators instead of inventing
profile-specific meanings.

## Size Budget Discipline

The Pluto image has tight flash constraints, especially when larger
`/mnt/jffs2` layouts reserve more QSPI space for persistent storage. New
firmware features should be judged in this order:

1. Reuse already-enabled runtime pieces.
2. Add small Python/shell/userland contracts where possible.
3. Measure `rootfs.cpio.gz`, ITB/FRM, and release package size before enabling
   new Buildroot packages.
4. Prefer small mature DSP libraries over large SDR frameworks when signal
   quality requires more than lightweight glue code.
5. Avoid large packages until there is a proven need and a matching size budget.

Use:

```sh
python3 scripts/check-firmware-size-budget.py
```

The budget thresholds can be overridden with `PLUTO_MAX_*_BYTES` environment
variables after the exact target image limit is confirmed.

## Capture Scope

The capture harness is intentionally quota-first:

- Default storage is `/mnt/jffs2/pluto-captures`.
- Larger captures should use SD-card paths under `/media`.
- Capture duration and byte count are bounded by environment-configurable
  limits.
- The production capture worker is isolated behind
  `/usr/sbin/pluto-capture-backend`.
- `simulate=true` creates a small deterministic capture for UI and API testing.

## Spectrum Scope

The spectrum service follows the same size-conscious pattern:

- The API contract is built into the existing lightweight Python helper.
- Production RF work is isolated behind `/usr/sbin/pluto-spectrum-backend`.
- `simulate=true` returns deterministic points and peaks for app integration.
- Requests are bounded by `PLUTO_SPECTRUM_MAX_BINS` and
  `PLUTO_SPECTRUM_MAX_TOP_N`.
- `GET /radio/spectrum/stream` returns bounded NDJSON rows from one long-running
  backend process, avoiding a backend startup cycle for every waterfall row.
- Apps should prefer the top-peak endpoint when they do not need the full
  spectrum point list.

## Doppler Scope

The firmware Doppler executor accepts a time/frequency table from the app and
owns the repeatable retune mechanics:

- Validate profile, start/stop UTC, interval, and table size.
- Apply the base profile/frequency before execution.
- Track current index, next scheduled retune, current/actual frequency, worker
  PID, and last error.
- Run `/usr/sbin/pluto-doppler-worker` as a tiny loop that calls
  `pluto-radio-api doppler-tick`.

The app remains responsible for TLE management, pass selection, Doppler table
generation, and operator workflow.

## Runtime Behavior

Profile apply and tune operations write the AD936x IIO attributes exposed by
`ad9361-phy`:

- `out_altvoltage0_RX_LO_frequency`
- `in_voltage_rf_bandwidth`
- `in_voltage_sampling_frequency`
- `in_voltage0_gain_control_mode`
- `in_voltage1_gain_control_mode` when present
- `in_voltage0_hardwaregain` when gain mode is manual
- `in_voltage1_hardwaregain` when present and gain mode is manual

The API records active profile, requested frequency, actual RX LO when readable,
gain, stream state, radio state, and last error in `/var/run/pluto-radio/state.json`.

## Next Milestones

Recommended next implementation order:

1. Build and measure the `pluto-audio-dsp` package in the target image.
2. Replace the current direct-bin spectrum math with the smallest viable FFT
   path if higher waterfall frame rates are required.
3. Production capture backend with storage quotas.
4. Persisted device-level configuration schema.
5. Explicit TX/loopback safety API.

The full satellite tracker, TLE management, pass filtering, operator UI, and
decoder policy should stay in the application layer.
