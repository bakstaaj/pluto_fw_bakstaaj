# N0JCG Pluto Firmware

## User Guide

**Open Radio Platform**
**Release:** `v0.39-N0JCG.5f`
**Audience:** station operators, app builders, and maintainers
**Status:** release guide

![N0JCG Pluto Firmware dashboard](assets/n0jcg-pluto-dashboard.svg)

*Figure 1. Operator dashboard screen reference. The live state label, receiver controls, and guarded transmit panel are intentionally visible together.*

> **Brand and safety note**
> N0JCG uses the numeral zero in `N0JCG`. Receive and transmit are separate operating states. Never connect a Pluto transmitter directly to a receiver input; use the required attenuation or an appropriate RF load.

## 1. What this firmware provides

N0JCG Pluto Firmware is the reusable radio appliance layer for PlutoSDR and Pluto Plus applications. It keeps RF/IIO control, DSP, audio streaming, diagnostics, and transmit safety in firmware so multiple applications can share the same contract.

Core capabilities include:

- Receive audio and IQ workflows through documented HTTP endpoints.
- Native DSP services for FM, AM, CW, loopback, and signal diagnostics.
- Guarded live transmission for AM audio, FM audio, and CW.
- File-backed FM audio TX, including APRS-compatible 1200-baud audio.
- Loopback and self-test paths for development without an antenna.
- App-builder status, diagnostics, and API contract endpoints.

## 2. Hardware and network setup

### Minimum equipment

- PlutoSDR or compatible Pluto Plus board.
- USB OTG connection for initial setup and recovery.
- Ethernet connection when using a fixed station address.
- Suitable antenna, dummy load, or attenuated test connection.
- For RF loopback: TX1 to RX1 through at least a 30 dB attenuator.

### First connection

1. Power the Pluto off.
2. Connect the OTG USB port to the host computer.
3. Insert the release SD card or install the SD boot files from the release package.
4. Set the board for SD boot and power it on.
5. Open `http://192.168.2.1/dashboard.html` for a USB-networked board, or use the board's assigned Ethernet address.
6. Open `http://192.168.2.1/api-test.html` to verify the API before using an application.

The release package is named `n0jcg-v0.39-N0JCG.5f-release.zip`. The raw SD image is preferred for a new card; the copy-files ZIP is the fallback for a card that is already formatted as FAT32.

## 3. Operator workflow

### Start receiving

1. Open the dashboard and confirm the green **Operational** state.
2. Select a receive profile appropriate to the signal.
3. Set the frequency and verify the units shown by the dashboard.
4. Select **START RX**.
5. Confirm audio or IQ activity before making application-level changes.

The dashboard should make the system state clear: connected, ready, receiving, stopped, advisory, or fault. A cyan signal indicator means live activity; it does not by itself mean that a system is safe or complete.

### Stop receiving

Select **STOP RX** before changing a profile, changing the sample rate, or handing the device to another application. The owning application should release its stream before a new application starts one.

### Transmit safely

1. Connect the correct antenna, dummy load, or attenuated test path.
2. Select the intended TX mode: AM audio, FM audio, or CW.
3. Confirm frequency, gain, deviation or keying parameters, and duration.
4. Review the live-TX confirmation requirement.
5. Start only when the transmit path is physically safe.
6. Stop TX and verify that the state returns to ready.

The firmware applies bounded duration and explicit confirmation to live TX. Applications must still enforce station identification, legal operating limits, frequency coordination, and their own operator controls.

## 4. App-builder API

![N0JCG Pluto Firmware API test page](assets/n0jcg-pluto-api-test.svg)

*Figure 2. API test page screen reference. Use it to confirm connectivity and inspect a response before integrating an application.*

The complete contract is maintained in [`firmware-api-contract.md`](firmware-api-contract.md). The practical starting points are:

| Purpose | Method and path |
|---|---|
| System and firmware state | `GET /radio/status` |
| Start receive audio | `POST /radio/audio/start` |
| Read live audio | `GET /radio/audio/live.wav` |
| Start loopback | `POST /radio/loopback/start` |
| Run demodulation diagnostic | `POST /radio/loopback/demod` |
| Start live TX | `POST /radio/tx/start` |
| Stop active operation | `POST /radio/stop` |
| Read diagnostics | `GET /radio/diagnostics` |

Example status request:

```sh
curl http://192.168.2.1/radio/status
```

Example guarded FM TX request:

```sh
curl -X POST http://192.168.2.1/radio/tx/start \
  -H 'Content-Type: application/json' \
  -d '{"profile":"TX_AUDIO_FM","frequency_hz":144390000,
       "tx_audio_source":"file","tx_audio_path":"/tmp/aprs-short.pcm",
       "tx_audio_rate_hz":48000,"tx_fm_deviation_hz":20000,
       "tx_amplitude":0.25,"duration_seconds":5,
       "confirm_live_tx":true}'
```

Do not treat an HTTP success response as proof of RF output. For a live RF test, capture the signal with an independent receiver and require the expected demodulated result.

## 5. Loopback and self-test

Use the loopback path for development and regression testing:

1. Connect TX1 to RX1 through the required attenuator.
2. Confirm that no antenna or unprotected receiver input is in the path.
3. Run the built-in loopback diagnostic from the API test page.
4. Check the returned waveform, demodulated audio, and diagnostic status.
5. Stop the test and remove the loopback connection when finished.

For APRS or other packet tests, the acceptance gate is stronger: the Pluto must transmit live RF, an independent receiver must capture it, and Dire Wolf must decode the expected packet. See [`APRS-ROC-LIVE-TX-TEST-HOWTO.md`](APRS-ROC-LIVE-TX-TEST-HOWTO.md) and [`APRS-TX-DEBUG-GUARDRAIL.md`](APRS-TX-DEBUG-GUARDRAIL.md).

## 6. Calibration and guard rails

Before a station relies on TX:

- Confirm the RF path with a dummy load or attenuated receiver.
- Verify frequency and sample-rate settings.
- Start with conservative TX amplitude and gain.
- Set a short duration during commissioning.
- Keep the stop control available from the owning application.
- Record the firmware version from `/opt/VERSIONS` or `/radio/status`.

The firmware is a control and DSP layer, not a substitute for station commissioning. Follow applicable Amateur Radio rules and use the correct load, antenna, and power limits for the installation.

## 7. Troubleshooting

**Dashboard does not load**

Check the board address, USB networking, Ethernet link, and whether the radio API service is running. Try `GET /radio/status` directly.

**API returns an unknown path**

Confirm the installed firmware version and compare the route with the current API contract. Do not silently substitute a loopback diagnostic for a live TX route.

**Audio is correct before TX but wrong over RF**

Validate the cached-IQ and RF/IIO path with an independent receiver. For APRS, continue until Dire Wolf decodes the expected frame; internal audio measurements alone are not sufficient.

**TX starts but no RF is received**

Check the physical port, attenuator, receiver frequency correction, gain, and independent receiver ownership. Confirm that the selected profile is a real TX profile and that `confirm_live_tx` was supplied.

## 8. Release identification

The release identity is deliberately consistent across the repository, package, firmware, and device status:

```text
N0JCG Pluto Firmware
v0.39-N0JCG.5f
n0jcg-v0.39-N0JCG.5f-release.zip
```

Use the exact `N0JCG` spelling in application titles, documentation, repository references, and support reports.
