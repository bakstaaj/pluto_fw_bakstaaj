# Live Pluto APRS TX Test From ROC

This guide moves the validated APRS live-TX test into the ROC development workflow.
It tests the complete path:

`Pluto TX1 -> attenuator -> RTL-SDR -> rtl_fm -> Dire Wolf -> ROC`

The test is not considered successful from Pluto telemetry alone. Dire Wolf must
decode the packet from the live RF capture.

## 1. Equipment And Network

| Role | Address / setting |
|---|---|
| Pluto | `192.168.68.104`, SSH user `root`, password supplied out-of-band |
| ROC Linux host | `192.168.68.114`, SSH user `n0jcg`, password supplied out-of-band |
| RTL-SDR | Serial `00014439` |
| APRS RF frequency | `144.390 MHz` |
| Pluto TX sample rate | `2.4 MS/s` |
| Dire Wolf audio rate | `48 kHz` |

Connect Pluto `TX1` to the RTL-SDR input through the attenuator. Do not connect
the Pluto transmitter directly to the RTL-SDR. Confirm that no antenna or other
radio is sharing the test connection.

## 2. MSYS2 Shell Setup

Run these commands from the MSYS2 UCRT64 shell on the development laptop. Do not
use PowerShell or WSL for this workflow.

```bash
export PATH=/ucrt64/bin:/usr/bin:/bin
export PLUTO_HOST=192.168.68.104
export ROC_HOST=192.168.68.114
export PLUTO_PASS='use-the-Pluto-password-from-your-local-secret'
export ROC_PASS='use-the-ROC-password-from-your-local-secret'
```

`sshpass` is used below because the ROC and Pluto test hosts are development
devices. Do not commit these variables or passwords to Git.

## 3. Verify The RTL Device

On the ROC host, verify both dongles and identify the intended serial:

```bash
sshpass -p "$ROC_PASS" ssh -o StrictHostKeyChecking=no \
  n0jcg@$ROC_HOST rtl_test -t
```

The validated receiver is serial `00014439`. Always select it explicitly:

```bash
RTL_SERIAL=00014439
```

This avoids unstable device-index ordering when two RTL-SDRs are connected.

## 4. Correct The RTL Tuning Offset

With this RTL/`rtl_fm` combination, requesting `144.390 MHz` results in an
actual tuner frequency of approximately `144.642 MHz`. Request `144.138 MHz`
instead; `rtl_fm` then reports an actual tuned frequency of `144.390 MHz`.

```bash
RTL_REQUEST_HZ=144138000

sshpass -p "$ROC_PASS" ssh -o StrictHostKeyChecking=no \
  n0jcg@$ROC_HOST \
  "timeout 3 rtl_fm -d $RTL_SERIAL -f $RTL_REQUEST_HZ -s 48000 -g 0 -l 0 - >/dev/null 2>/tmp/rtl-check.log; cat /tmp/rtl-check.log"
```

The log must contain:

```text
Tuned to 144390000 Hz.
Output at 48000 Hz.
```

If the log does not show that frequency, stop and correct the receiver setup
before investigating firmware.

## 5. Verify Dire Wolf Independently

The ROC Dire Wolf configuration should contain:

```text
MYCALL N0JCG-5
CHANNEL 0
MODEM 1200
AGWPORT 18000
KISSPORT 18001
```

Verify the configuration independently with a known-good generated packet. The
following test must decode without using the Pluto:

```bash
sshpass -p "$ROC_PASS" ssh -o StrictHostKeyChecking=no \
  n0jcg@$ROC_HOST \
  'printf "N0JCG>APRS:HELLO PLUTO\\n" >/tmp/aprs-check.txt; \
   gen_packets -r 48000 -o /tmp/aprs-check.wav /tmp/aprs-check.txt; \
   sox /tmp/aprs-check.wav -t raw -r 48000 -e signed -b 16 -c 1 - | \
   direwolf -q h -r 48000 -c /home/n0jcg/sdrdev/N0JCG-ROC/config/direwolf.aprs-rx.example.conf - 2>&1'
```

Expected output includes:

```text
N0JCG>APRS:HELLO PLUTO
```

If this fails, fix ROC/Dire Wolf before testing Pluto RF.

## 6. Create The APRS PCM Packet

Generate the packet on ROC so the test artifact is owned by the ROC workstream:

```bash
sshpass -p "$ROC_PASS" ssh -o StrictHostKeyChecking=no \
  n0jcg@$ROC_HOST \
  'printf "N0JCG>APRS:HELLO PLUTO\\n" >/tmp/aprs-short.txt; \
   gen_packets -r 48000 -o /tmp/aprs-short.wav /tmp/aprs-short.txt; \
   sox /tmp/aprs-short.wav -t raw -r 48000 -e signed -b 16 -c 1 /tmp/aprs-short.pcm'
```

Copy the raw PCM to the Pluto. Pluto's dropbear image may not provide an SFTP
server, so use an SSH stream rather than relying on SCP's SFTP subsystem:

```bash
sshpass -p "$ROC_PASS" ssh -o StrictHostKeyChecking=no \
  n0jcg@$ROC_HOST cat /tmp/aprs-short.pcm |
  sshpass -p "$PLUTO_PASS" ssh -o StrictHostKeyChecking=no \
  root@$PLUTO_HOST 'cat >/tmp/aprs-short.pcm'
```

Verify the file:

```bash
sshpass -p "$PLUTO_PASS" ssh -o StrictHostKeyChecking=no \
  root@$PLUTO_HOST ls -l /tmp/aprs-short.pcm
```

The expected file is approximately `44,922` bytes for this short packet.

## 7. Start A Controlled RF Capture

Start the receiver before starting Pluto TX. Use a bounded capture so the exact
audio sent to Dire Wolf is retained:

```bash
sshpass -p "$ROC_PASS" ssh -o StrictHostKeyChecking=no \
  n0jcg@$ROC_HOST \
  "rm -f /tmp/aprs-live-rf.pcm /tmp/aprs-live-rtl.log; \
   nohup timeout 12 rtl_fm -d $RTL_SERIAL -f $RTL_REQUEST_HZ \
     -M fm -E dc -s 48000 -r 48000 -g 20 -l 0 - \
     >/tmp/aprs-live-rf.pcm 2>/tmp/aprs-live-rtl.log &"
```

## 8. Start Pluto Live TX

Create a temporary JSON request locally:

```bash
cat >/tmp/aprs-tx.json <<'JSON'
{"profile":"TX_AUDIO_FM","frequency_hz":144390000,"duration_seconds":5,"tx_audio_source":"file","tx_audio_path":"/tmp/aprs-short.pcm","tx_audio_rate_hz":48000,"tx_fm_deviation_hz":20000,"tx_amplitude":0.25,"tx_gain_db":0,"confirm_live_tx":true}
JSON
```

Submit it to the Pluto:

```bash
curl -sS -X POST http://$PLUTO_HOST/radio/tx/start \
  -H 'Content-Type: application/json' \
  --data-binary @/tmp/aprs-tx.json | tee /tmp/aprs-tx-result.json
```

The response should include:

```text
"ok": true
"state": "complete"
"sample_rate_hz": 2400000
"tx_runtime_sample_rate_hz": approximately 2400000
```

The cached-IQ path preloads and pre-renders the PCM packet. The 64-bit cache
length calculation is required on the Pluto's 32-bit ARM CPU; without it, a
normal 1.12-million-sample packet cache is truncated and RF decoding fails.

## 9. Mandatory Dire Wolf RF Decode

After the TX request completes, feed the captured RF audio to Dire Wolf:

```bash
sshpass -p "$ROC_PASS" ssh -o StrictHostKeyChecking=no \
  n0jcg@$ROC_HOST cat /tmp/aprs-live-rf.pcm |
  sshpass -p "$ROC_PASS" ssh -o StrictHostKeyChecking=no \
  n0jcg@$ROC_HOST direwolf -q h -r 48000 \
    -c /home/n0jcg/sdrdev/N0JCG-ROC/config/direwolf.aprs-rx.example.conf - 2>&1
```

The test passes only when output contains the expected frame:

```text
N0JCG>APRS:HELLO PLUTO
```

Multiple decodes are acceptable and expected because the short PCM packet is
replayed during the five-second TX window.

## 10. Live Listener Mode

For normal ROC development, run the listener script instead of the bounded
capture. Confirm that its defaults remain:

```bash
RTL serial: 00014439
RTL requested frequency: 144138000
Dire Wolf input rate: 48000
```

The listener is:

```text
/home/n0jcg/sdrdev/N0JCG-ROC/tools/aprs_listener.sh
```

The listener's packet log is:

```text
/home/n0jcg/sdrdev/N0JCG-ROC/runtime/aprs/packets.log
```

Use bounded capture mode for firmware debugging because it preserves the exact
audio needed for repeatable offline analysis.

## 11. Troubleshooting Order

1. Confirm TX1, attenuator, and RTL input wiring.
2. Confirm RTL serial `00014439`.
3. Confirm `rtl_fm` reports actual tuning at `144390000 Hz`.
4. Run the independent Dire Wolf configuration test.
5. Confirm `/tmp/aprs-short.pcm` exists on the Pluto.
6. Confirm the Pluto API response is `ok=true` and runtime rate is near 2.4 MS/s.
7. Feed the bounded RF capture to Dire Wolf.
8. Only after those checks investigate firmware changes.

Do not accept internal audio metrics, carrier presence, AFSK-looking spectrum, or
API completion as proof of APRS success. The final proof is the Dire Wolf decode
from live Pluto RF.
