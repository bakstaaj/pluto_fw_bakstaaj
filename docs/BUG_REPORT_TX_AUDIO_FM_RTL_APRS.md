# Bug report: TX audio/tone is not reproduced correctly on the RF output

## Summary

On firmware `v0.39-bakstaaj.5d` (HDL `10124`, Buildroot `5353c3`), the documented
`POST /radio/tx/start` API accepts bounded `TX_AUDIO_FM` and `TX_TEST_TONE`
requests and reports successful external-backend/IIO writes. A receiver connected
to the Pluto TX path, however, does not reproduce the requested audio frequency
reliably. This prevents validating the APRS AFSK waveform over the air.

The failure is in the Pluto TX modulation path or its RF-output mapping, not in
Dire Wolf or APRS framing. The same APRS PCM file decodes correctly when tested
offline with Dire Wolf.

## Device and API context

- Firmware: `v0.39-bakstaaj.5d`
- HDL: `10124`
- Buildroot: `5353c3`
- API: documented `/radio/tx/start`
- RF: 144.390 MHz
- TX gain used: `-10 dB`
- External test receiver: RTL-SDR serial `00000144`
- Direct RF connection: Pluto TX -> 30 dB attenuator -> RTL-SDR

Example bounded tone request:

```json
{
  "profile": "TX_TEST_TONE",
  "frequency_hz": 144390000,
  "duration_seconds": 5,
  "tx_tone_hz": 1200,
  "tx_amplitude": 0.1,
  "tx_gain_db": -10,
  "confirm_live_tx": true
}
```

The API returns `ok: true`, `backend: external`, successful IIO writes, and TX
metrics such as `tx_sample_count`, `tx_push_count`, and `tx_transition_count`.

## Expected behavior

1. `TX_TEST_TONE` with `tx_tone_hz: 1200` produces a stable 1200 Hz FM audio
   tone on the RF output.
2. `TX_AUDIO_FM` with `tx_audio_source: file` and the known-good APRS PCM file
   reproduces that file's 1200-baud AFSK waveform on RF.
3. A receiver directly connected through the attenuator can demodulate the
   requested tone and Dire Wolf can decode the APRS frame.

## Observed behavior

- A handheld with an antenna can hear a carrier/tone from the Pluto, and the API
  reports successful transmission.
- The direct RTL IQ capture shows the RF carrier, but the requested modulation
  is not reproduced consistently. After correcting the RTL center-frequency
  offset, the carrier was within roughly 41 Hz of center, while the demodulated
  audio contained a repeatable ~390 Hz component instead of the requested
  800/1200 Hz tone.
- `TX_AUDIO_FM` requests report `tx_audio_source: file`, but response metrics
  continue to expose default tone/CW fields (for example `audio_tone_hz: 1000`
  and `tx_cw_text: CQ PLUTO`). This makes it unclear whether the file/tone
  source is actually selected by the backend.
- Dire Wolf decoded no frames from multiple fresh RF captures, including
  captures with DC-blocked and rate-corrected audio.
- The APRS PCM waveform itself is valid: offline resampling and Dire Wolf
  decoding produce a valid `N0JCG-9>APRS` frame.

## Reproduction procedure

1. Connect Pluto TX through a 30 dB attenuator to an RTL-SDR.
2. Tune the RTL using raw IQ or an equivalent calibrated receiver. Do not infer
   success from the API response alone.
3. Issue the bounded `TX_TEST_TONE` request above.
4. Capture raw IQ at 1.024 MS/s and digitally demodulate FM.
5. Compare the measured audio spectrum with `tx_tone_hz`.
6. Repeat with `TX_AUDIO_FM`, `tx_audio_source: file`, and the known-good APRS
   PCM file.

## Additional investigation notes

- The `rtl_fm` build on the ROC applies a frequency-dependent center offset, so
  raw-IQ capture was used to avoid confusing an RTL tuning artifact with a
  firmware failure.
- With the RTL center corrected, the carrier is present and stable. The missing
  or incorrectly scaled audio modulation remains.
- The problem persists across both `TX_TEST_TONE` and `TX_AUDIO_FM`, which points
  to the common external TX backend/IIO sample-generation or RF-output path.

## Requested firmware investigation

1. Verify that `tx_tone_hz` is used as the generated baseband/FM audio frequency
   and is not being replaced by a default value.
2. Verify that `tx_audio_source: file` opens and streams the requested PCM file,
   rather than falling back to the default tone/CW generator.
3. Add a measured modulation-frequency field to the TX metrics (or a loopback
   self-test) so API success cannot be reported without confirming the generated
   samples.
4. Confirm that the selected TX IIO channel/port is the same path represented by
   the reported TX metrics.
5. Add an automated test that requests 800 Hz and 1200 Hz tones and verifies the
   generated sample spectrum and frequency ratio before declaring `ok: true`.

## Fix status

Implemented for the next firmware build after `v0.39-bakstaaj.5d`.

### Root cause confirmed in firmware source

`TX_TEST_TONE` was configured as `tx_mode: "tone"`, and the external TX backend
handled that mode as a complex IQ/baseband tone. Demodulating that as FM audio
does not provide a clean requested 800/1200 Hz audio tone. That made the API
contract misleading for app builders and for the APRS RF test workflow.

### Firmware changes

- Changed `TX_TEST_TONE` into a bounded FM audio tone profile:
  `tx_mode: "fm"`, `tx_audio_source: "tone"`, `tx_audio_rate_hz: 8000`,
  `tx_audio_tone_hz: 1000`, and `tx_fm_deviation_hz: 5000`.
- Kept backward compatibility for AM/FM tone requests: when `tx_audio_tone_hz`
  is omitted, `tx_tone_hz` is accepted as an alias for `tx_audio_tone_hz`.
- Added TX audio evidence to external backend metrics, including audio sample
  count, zero-crossing count, RMS/peak, measured audio tone, tone error, PCM
  file samples read, and file rewind count.
- Added API-side backend validation so tone-source AM/FM requests fail if the
  generated audio tone is not within tolerance, and file-source AM/FM requests
  fail if the backend did not read PCM samples.
- Updated API documentation and validation tests for 800 Hz and 1200 Hz FM
  audio tone behavior.

### Validation performed

- Confirmed the issue from the firmware source path: old `TX_TEST_TONE` was an
  IQ tone, not an FM audio tone.
- `TX_TEST_TONE --simulate tx_tone_hz=1200` now reports `tx_mode: "fm"`,
  `tx_audio_tone_hz: 1200`, `tx_measured_audio_tone_hz: 1200`, and zero tone
  error.
- `TX_AUDIO_FM --simulate tx_audio_tone_hz=800` now reports `tx_mode: "fm"`,
  `tx_audio_tone_hz: 800`, `tx_measured_audio_tone_hz: 800`, and zero tone
  error.
- Host C syntax compile passed for `pluto-loopback-backend.c`.
- Full Docker firmware build passed and cross-compiled `pluto-loopback-backend`
  for ARM; `pluto-tx-backend` is installed as the symlink to that backend.
- Build hygiene passed.
- Firmware size budget passed for the new output:
  `rootfs.cpio.gz` 17.37 MiB, `pluto.itb` 22.90 MiB, `pluto.frm` 22.90 MiB,
  and `pluto.dfu` 22.90 MiB.

### Remaining live-RF validation

The fix still needs a controlled live RF verification on hardware:

1. Deploy the new SD boot files or full image.
2. Run bounded `TX_TEST_TONE` tests at 800 Hz and 1200 Hz through the attenuated
   Pluto-to-RTL path.
3. Verify demodulated audio frequency against the new backend metrics.
4. Repeat `TX_AUDIO_FM` with the known-good APRS PCM file and verify Dire Wolf
   decode from the RF capture.
