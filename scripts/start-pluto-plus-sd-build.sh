#!/usr/bin/env bash
set -u

log=/tmp/pluto-plus-sd-build.log
status=/tmp/pluto-plus-sd-build.status

rm -f "$status"
: > "$log"

nohup bash -c '
  bash "/mnt/c/Users/jim/OneDrive/Documents/Pluto Firmware/scripts/build-pluto-plus-sd.sh"
  echo $? > /tmp/pluto-plus-sd-build.status
' >> "$log" 2>&1 < /dev/null &

echo $!
