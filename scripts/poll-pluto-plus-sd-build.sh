#!/usr/bin/env bash
set -u

status=/tmp/pluto-plus-sd-build.status
log=/tmp/pluto-plus-sd-build.log

if [[ -f "$status" ]]; then
  printf 'STATUS=%s\n' "$(cat "$status")"
else
  echo 'STATUS=running'
fi

tail -n 80 "$log"
