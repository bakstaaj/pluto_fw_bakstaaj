#!/usr/bin/env bash
set -u

cat /etc/os-release
echo ---
ldd --version | head -n 1
echo ---
ldconfig -p | grep libudev || true
echo ---
dpkg -l | grep -E 'libudev|systemd' | head -n 20 || true
