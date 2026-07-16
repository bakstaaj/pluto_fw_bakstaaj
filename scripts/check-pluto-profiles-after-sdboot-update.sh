#!/usr/bin/env bash
set -euo pipefail

export HOME=/tmp
export PATH="/usr/bin:/ucrt64/bin:/bin:$PATH"

host="${PLUTO_HOST:-192.168.2.1}"
user="${PLUTO_USER:-root}"
pass="${PLUTO_PASS:-analog}"

ssh_opts=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o PreferredAuthentications=password
  -o PubkeyAuthentication=no
  -o ConnectTimeout=8
)

sshpass -p "$pass" ssh "${ssh_opts[@]}" "$user@$host" <<'REMOTE'
set -eu
api="http://127.0.0.1:8081"
wget -qO /tmp/profile-list.json "$api/radio/profile/list"
python3 - <<'PY'
import json
data=json.load(open("/tmp/profile-list.json"))
names=[p.get("name") for p in data.get("profiles", [])]
expected=[
  "NOAA_NFM",
  "SAT_AUDIO_NFM",
  "SAT_CW",
  "VHF_AUDIO_NFM_LOOPBACK",
  "UHF_AUDIO_NFM_LOOPBACK",
  "UHF_CW_LOOPBACK",
  "CB_AM_HAMITUP",
]
missing=[name for name in expected if name not in names]
print("profile_count=%s" % len(names))
print("missing=%s" % missing)
for profile in data.get("profiles", []):
    if profile.get("name") == "CB_AM_HAMITUP":
        print("cb_source=%s cb_translation=%s cb_default=%s" % (
            profile.get("source_frequency_hz"),
            profile.get("frequency_translation_hz"),
            profile.get("default_frequency_hz"),
        ))
if missing:
    raise SystemExit(1)
PY
REMOTE
