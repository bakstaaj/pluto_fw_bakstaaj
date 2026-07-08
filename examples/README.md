# Pluto Radio App-Builder Examples

These examples show the firmware API patterns apps should use first:

- discover health and profiles
- check TX guardrails before transmitting
- run safe simulation tests while hardware is unavailable
- start AM, FM, CW, and tone TX in simulation
- run the firmware self-test bundle

The default target is the Pluto USB-network address:

```sh
http://192.168.2.1
```

## Python CLI

The Python client uses only the standard library:

```sh
python examples/python/pluto_radio_client.py health
python examples/python/pluto_radio_client.py profiles
python examples/python/pluto_radio_client.py self-test
python examples/python/pluto_radio_client.py guardrails --profile TX_AUDIO_FM
python examples/python/pluto_radio_client.py tx-sim --profile TX_AUDIO_AM
python examples/python/pluto_radio_client.py tx-sim --profile TX_AUDIO_FM --tx-audio-tone-hz 1200
python examples/python/pluto_radio_client.py tx-sim --profile TX_CW --cw-text "CQ TEST"
python examples/python/pluto_radio_client.py loopback-sim
python examples/python/pluto_radio_client.py audio-sim
```

Use `--base-url` when the Pluto is on another address:

```sh
python examples/python/pluto_radio_client.py --base-url http://pluto.local health
```

## Browser Client

Open `examples/browser/pluto-radio-client.html` in a browser. If it is not served
from the Pluto itself, set the base URL field to the Pluto address before running
tests.

## Live TX Guard

The samples default to `simulate=true`. Live TX is intentionally not a one-click
path in these examples. Apps should call `/radio/tx/guardrails` first, show the
returned limits/readiness to the operator, and only call `/radio/tx/start`
without `simulate=true` after a deliberate `confirm_live_tx=true` action.

AM/FM file audio uses signed 16-bit little-endian mono PCM. The firmware accepts
`tx_audio_path` only under `/mnt/jffs2`, `/media`, `/tmp`, or `/var/run`.
