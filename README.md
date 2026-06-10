# PlutoSDR Firmware - Bakstaaj Build

Custom PlutoSDR firmware based on Analog Devices `plutosdr-fw` release `v0.39`.

This build adds an install-time option for the size of the persistent JFFS2 partition mounted at `/mnt/jffs2`. The selected size is controlled by `config.frm` when installing firmware.

## Read This First

If you want any `/mnt/jffs2` size other than the stock layout, install the matching `boot.frm` first. The boot image contains the U-Boot logic that applies the selected flash layout before Linux starts.

Safe install order when upgrading from stock or any firmware that does not already support `config.frm`:

1. Install `boot.frm`
2. Safely eject the USB drive and wait for it to reappear
3. Install `pluto.frm` once with the default layout
4. Wait for the device to reboot and the USB drive to reappear
5. Edit `config.frm`
6. Install `pluto.frm` again to apply the selected `/mnt/jffs2` size

The second `pluto.frm` install is required because the currently running firmware performs the USB mass-storage update. Stock PlutoSDR firmware does not know how to read `config.frm`, so the first custom firmware install can only install the new updater.

Do not install a larger `config.frm` layout with an old bootloader. The firmware image will be written to a shifted flash offset that old U-Boot does not understand.

## Release Files

Typical release artifacts:

| File | Purpose |
| --- | --- |
| `boot.frm` | Bootloader update for the Pluto USB mass-storage update method. Required for configurable JFFS2 sizes. |
| `boot.dfu` | Bootloader update for DFU mode. |
| `pluto.frm` | Main firmware update for the Pluto USB mass-storage update method. |
| `pluto.dfu` | Main firmware update for DFU mode. |
| `uboot-env.dfu` | U-Boot environment image for DFU mode. |
| `config.frm` | Editable install-time configuration file. Selects the `/mnt/jffs2` size. |
| `plutosdr-fw-*.zip` | Firmware ZIP containing `pluto.frm`, `pluto.dfu`, `uboot-env.dfu`, and `config.frm`. |

## JFFS2 Size Options

`config.frm` contains one active setting and the rest commented out:

```text
JFFS2_SIZE_MIB=1
#JFFS2_SIZE_MIB=2
#JFFS2_SIZE_MIB=3
#JFFS2_SIZE_MIB=4
#JFFS2_SIZE_MIB=5
```

Uncomment exactly one option before installing `pluto.frm`.

The default `1` option preserves the stock PlutoSDR layout. The stock persistent partition is actually 896 KiB, but it is kept under the `1` option for compatibility with existing Pluto firmware layouts.

Valid choices:

| `JFFS2_SIZE_MIB` | Persistent partition |
| --- | --- |
| `1` | Stock layout, 896 KiB |
| `2` | 2 MiB |
| `3` | 3 MiB |
| `4` | 4 MiB |
| `5` | 5 MiB |

Larger `/mnt/jffs2` sizes reduce the maximum space available for the main firmware image in QSPI flash.

## Install Using USB Mass Storage

### 1. Install The Boot Image

Connect the PlutoSDR to your computer. It should appear as a USB drive.

Copy `boot.frm` to the root of the PlutoSDR USB drive.

Safely eject the PlutoSDR USB drive, but leave the USB cable connected. The device will process the update and the USB drive will reappear when the boot update is finished.

Do not use the Pluto shell to check `/mnt/msd` before ejecting from the host computer. While the host owns the USB mass-storage volume, `/mnt/msd` may appear empty on the Pluto. The updater mounts and reads the volume after the host ejects it.

### 2. Install The Firmware Once

If the PlutoSDR is still running stock firmware, copy `pluto.frm` to the root of the PlutoSDR USB drive and eject the drive cleanly. This installs the custom firmware and updater using the stock flash layout.

Wait for the device to reboot and the USB drive to reappear.

### 3. Prepare `config.frm`

Copy `config.frm` to the root of the PlutoSDR USB drive if it is not already there.

Edit `config.frm` and leave exactly one `JFFS2_SIZE_MIB` line uncommented.

Example for a 4 MiB persistent partition:

```text
#JFFS2_SIZE_MIB=1
#JFFS2_SIZE_MIB=2
#JFFS2_SIZE_MIB=3
JFFS2_SIZE_MIB=4
#JFFS2_SIZE_MIB=5
```

### 4. Install The Firmware With The Selected Layout

Copy `pluto.frm` to the root of the PlutoSDR USB drive.

Alternatively, copy `plutosdr-fw-*.zip` to the PlutoSDR USB drive. The updater will extract the firmware and `config.frm`. If an edited `config.frm` already exists on the drive, the updater keeps it instead of replacing it with the default.

Eject the PlutoSDR USB drive cleanly. The device will validate `config.frm`, update firmware, apply the selected layout, and reboot.

The update starts only after the host computer ejects the USB drive. Seeing files in Windows Explorer but an empty `/mnt/msd` directory on the Pluto before eject is normal.

## Verify The Layout

After the update finishes and the PlutoSDR reboots, verify the selected layout from the Pluto shell:

```sh
fw_printenv jffs2_size_mib
cat /proc/mtd
df -h /mnt/jffs2
sh -n /sbin/update.sh
```

For `JFFS2_SIZE_MIB=5`, the expected result is:

```text
jffs2_size_mib=5
mtd2: 00500000 00010000 "qspi-nvmfs"
mtd3: 019e0000 00010000 "qspi-linux"
```

`df -h /mnt/jffs2` should report a 5 MiB filesystem, and `sh -n /sbin/update.sh` should return with no output.

## Status Files

After an update attempt, the PlutoSDR USB drive may contain status files:

| File | Meaning |
| --- | --- |
| `SUCCESS` | Main firmware update succeeded. |
| `FAILED` | Main firmware update failed. |
| `FAILED_FIRMWARE_CHSUM_ERROR` | `pluto.frm` checksum did not match. |
| `FAILED_JFFS2_CONFIG_ERROR` | `config.frm` was missing, invalid, or unsafe. |
| `BOOT_SUCCESS` | `boot.frm` update succeeded. |
| `BOOT_FAILED` | `boot.frm` update failed. |
| `FAILED_BOOT_CHSUM_ERROR` | `boot.frm` checksum did not match. |
| `FAILED_MTD_PARTITION_ERROR` | Boot update partition check failed. |

If `FAILED_JFFS2_CONFIG_ERROR` appears, open it as a text file. It contains the validation error.

Common causes:

- `config.frm` is missing.
- More than one `JFFS2_SIZE_MIB` line is uncommented.
- No `JFFS2_SIZE_MIB` line is uncommented.
- The value is not `1`, `2`, `3`, `4`, or `5`.
- The selected layout would shrink the active persistent partition in an unsafe one-step update.

## Shrinking The Persistent Partition

Growing `/mnt/jffs2` from the stock layout to a larger layout is supported in one firmware install.

Shrinking from a larger layout back to a smaller layout may be refused by the updater because the new firmware offset could overlap the currently active JFFS2 partition. This is intentional. The updater stops rather than risk leaving the device without a bootable firmware image.

If you need to shrink a previously enlarged layout, use DFU recovery or a known-safe two-step procedure with a bootable firmware image at the target offset.

## DFU Notes

DFU artifacts are provided for advanced recovery and scripted installs:

```bash
dfu-util -D boot.dfu -a boot.dfu
dfu-util -D uboot-env.dfu -a uboot-env.dfu
dfu-util -D pluto.dfu -a firmware.dfu
dfu-util -e
```

Use DFU carefully. Updating the bootloader or U-Boot environment incorrectly can make normal USB mass-storage recovery unavailable.

## Building

This fork is intended to be built in a Linux Docker container from WSL2. The boot image build requires Linux AMD/Xilinx Vivado/Vitis `2023.2` tools mounted at `/opt/Xilinx`.

Build from a Linux/WSL checkout, or make sure Git preserves LF line endings for shell scripts. The firmware updater runs under BusyBox `/bin/sh` on the Pluto; CRLF line endings in scripts can prevent the updater from running after the USB drive is ejected.

Normal firmware build:

```bash
docker run --rm -it \
  --user "$(id -u):$(id -g)" \
  -v "$PWD":/work \
  -v pluto-fw-dl:/dl \
  -v pluto-fw-ccache:/ccache \
  -w /work \
  -e HOME=/tmp \
  -e BR2_DL_DIR=/dl \
  -e CCACHE_DIR=/ccache \
  pluto-fw-v039 \
  bash -lc 'git config --global --add safe.directory /work && make TARGET=pluto SKIP_LEGAL=1'
```

Boot image build:

```bash
docker run --rm -it \
  --user "$(id -u):$(id -g)" \
  -v "$PWD":/work \
  -v /opt/Xilinx:/opt/Xilinx:ro \
  -v pluto-fw-dl:/dl \
  -v pluto-fw-ccache:/ccache \
  -w /work \
  -e HOME=/tmp \
  -e BR2_DL_DIR=/dl \
  -e CCACHE_DIR=/ccache \
  -e VIVADO_SETTINGS=/xilinx-2023.2-settings.sh \
  pluto-fw-v039 \
  bash -lc 'git config --global --add safe.directory /work && make TARGET=pluto SKIP_LEGAL=1 build/boot.frm build/boot.dfu'
```

## Upstream

This firmware is derived from Analog Devices PlutoSDR firmware:

https://github.com/analogdevicesinc/plutosdr-fw
