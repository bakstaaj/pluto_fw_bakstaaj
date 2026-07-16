#!/usr/bin/env bash
set -euo pipefail

export HOME="${HOME:-/tmp}"
export PATH="/usr/bin:/ucrt64/bin:/bin:$PATH"

host="${PLUTO_HOST:-192.168.2.1}"
user="${PLUTO_USER:-root}"
pass="${PLUTO_PASS:-analog}"
zip_path="${SD_BOOT_FILES_ZIP:-/c/Users/jim/OneDrive/Documents/Pluto Firmware/build-ethernet-async-fw-fm-channel-filter/pluto-sdcard-files.zip}"
remote_zip="${REMOTE_SD_BOOT_FILES_ZIP:-/tmp/pluto-sdcard-files.zip}"
remote_script="/tmp/pluto-sdboot-update.sh"
reboot_after="${REBOOT_AFTER_UPDATE:-1}"

ssh_opts=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o PreferredAuthentications=password
  -o PubkeyAuthentication=no
)

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: missing command: $1" >&2
    exit 2
  }
}

need_cmd sshpass
need_cmd ssh
need_cmd scp
need_cmd unzip
need_cmd sha256sum

if [ ! -f "$zip_path" ]; then
  echo "ERROR: missing SD boot files ZIP: $zip_path" >&2
  exit 2
fi

case "$zip_path" in
  *.img)
    echo "ERROR: refusing to deploy a raw .img to a running Pluto" >&2
    exit 2
    ;;
esac

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

echo "Validating local boot-file ZIP layout"
unzip -l "$zip_path" > "$tmp_dir/zip-list.txt"
for file in BOOT.bin devicetree.dtb uEnv.txt uImage uramdisk.image.gz; do
  if ! grep -Eq "[[:space:]]$file$" "$tmp_dir/zip-list.txt"; then
    echo "ERROR: ZIP is missing required boot file: $file" >&2
    exit 2
  fi
done

zip_sha="$(sha256sum "$zip_path" | awk '{print $1}')"
zip_size="$(wc -c < "$zip_path" | tr -d ' ')"

echo "Deploying SD boot files to Pluto"
echo "  target: $user@$host"
echo "  local zip: $zip_path"
echo "  sha256: $zip_sha"
echo "  bytes: $zip_size"
echo "  reboot after update: $reboot_after"

sshpass -p "$pass" scp -O "${ssh_opts[@]}" "$zip_path" "$user@$host:$remote_zip"

sshpass -p "$pass" ssh "${ssh_opts[@]}" "$user@$host" "cat > '$remote_script' && chmod +x '$remote_script'" <<'REMOTE'
#!/bin/sh
set -eu

remote_zip="${1:-/tmp/pluto-sdcard-files.zip}"
expected_sha="${2:-}"
reboot_after="${3:-1}"
boot_dev="${SD_BOOT_DEV:-/dev/mmcblk0p1}"
mount_dir="/tmp/sdboot-update-mnt"
extract_dir="/tmp/sdboot-update-files"
backup_root="/media/fw-backups"
required_files="BOOT.bin devicetree.dtb uEnv.txt uImage uramdisk.image.gz"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

[ "$(id -u)" = "0" ] || fail "must run as root"
[ -b "$boot_dev" ] || fail "missing boot partition block device: $boot_dev"
[ -f "$remote_zip" ] || fail "missing uploaded ZIP: $remote_zip"
[ -d /media ] || fail "/media is missing; refusing to run without persistent backup target"

if ! command -v unzip >/dev/null 2>&1; then
  fail "unzip is not available on the Pluto"
fi

actual_sha="$(sha256sum "$remote_zip" | awk '{print $1}')"
if [ -n "$expected_sha" ] && [ "$actual_sha" != "$expected_sha" ]; then
  fail "uploaded ZIP checksum mismatch: expected $expected_sha got $actual_sha"
fi

rm -rf "$mount_dir" "$extract_dir"
mkdir -p "$mount_dir" "$extract_dir" "$backup_root"
unzip -q "$remote_zip" -d "$extract_dir"

for file in $required_files; do
  [ -f "$extract_dir/$file" ] || fail "uploaded ZIP missing $file after extraction"
done

if mount | grep -q " on $mount_dir "; then
  umount "$mount_dir" || true
fi

mount -t vfat -o rw "$boot_dev" "$mount_dir"

backup_dir="$backup_root/sdboot-$(date +%Y%m%d-%H%M%S 2>/dev/null || echo unknown)"
mkdir -p "$backup_dir"
for file in $required_files; do
  if [ -f "$mount_dir/$file" ]; then
    cp "$mount_dir/$file" "$backup_dir/$file"
  fi
done

echo "$actual_sha  $(basename "$remote_zip")" > "$backup_dir/upload.sha256"
cat /etc/version > "$backup_dir/version-before.txt" 2>/dev/null || true

for file in $required_files; do
  cp "$extract_dir/$file" "$mount_dir/$file"
done

sync
umount "$mount_dir"

echo "SD boot partition update complete"
echo "  boot device: $boot_dev"
echo "  backup: $backup_dir"
echo "  sha256: $actual_sha"

if [ "$reboot_after" = "1" ]; then
  echo "Rebooting Pluto"
  reboot
else
  echo "Reboot skipped because reboot_after=$reboot_after"
fi
REMOTE

sshpass -p "$pass" ssh "${ssh_opts[@]}" "$user@$host" "$remote_script '$remote_zip' '$zip_sha' '$reboot_after'"
