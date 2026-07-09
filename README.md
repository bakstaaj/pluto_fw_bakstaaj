# PlutoSDR Firmware - Bakstaaj Build

Custom PlutoSDR firmware based on Analog Devices `plutosdr-fw` release `v0.39`.

This build adds an install-time option for the size of the persistent JFFS2 partition mounted at `/mnt/jffs2`. The selected size is controlled by `config.frm` when installing firmware. It also includes access to the SD Card for persistent file storage. The ethernet interface is enabled with a short DHCP address check with local DHCP server fallback using `192.168.3.1/24` scope.

The firmware also enables Pluto's extended AD936x tuning configuration for the 70 MHz to 6000 MHz range. U-Boot sets `attr_name=compatible` and selects `attr_val`/`compatible` plus `mode` from the detected Pluto hardware model: Rev.C hardware uses `ad9361` with `2r2t`, while other Pluto-style models use `ad9364` with `1r1t`. These values are exposed in `config.txt` under `[AD936X]` for later adjustment if needed. Pluto Plus boards with populated TX2/RX2 hardware can be tested in Rev.C-style 2R2T mode by setting `force_2r2t = 1`; this selects the Rev.C FIT device tree and forces `ad9361`/`2r2t` at boot. Dropbear host keys are persisted to `/mnt/jffs2` automatically through `device_persistent_keys`, and zeroconf is available with hostname `pluto` so hosts with mDNS support can reach `pluto.local`.

SD cards formatted as ext4 are recommended for persistent application storage because ext4 journaling is more resilient to unexpected power loss than FAT. The firmware includes `e2fsck` for ext2/3/4 and retains `fsck.vfat` for FAT compatibility. Supported cards are checked before mounting and again before `/mnt/jffs2/autorun.sh` is executed; a read-only filesystem is unmounted, repaired, and remounted before `autorun.sh` continues. SD preparation and `autorun.sh` run in a background startup worker so a lengthy filesystem repair cannot block normal Pluto boot. Python 3 is included in the root filesystem as `python3` for local application scripts, along with the `sgp4` Python package for TLE/orbit propagation.

The physical Ethernet interface uses the stable default MAC address `00:0a:35:00:01:22`, allowing a LAN DHCP reservation to remain valid across reboots. The address can be changed with `macaddr_eth` in `config.txt`; eject the USB mass-storage drive to persist the new value.

The generated `config.txt` also includes `device_persistent_keys = 0` under `[ACTIONS]`. Set it to `1`, save, and eject the USB mass-storage drive to manually refresh persisted Dropbear keys; the updater writes `PERSISTENT_KEYS_STATUS` with the command output and resets the action to `0`.

## Read This First

## SD Card Boot Image For SD-Boot Pluto Boards

Use this procedure for the newer Pluto-style boards that boot from a removable SD card and have boot DIP switches labeled `JTAG`, `SD`, and `OSPI`. This path does not require DFU mode, a DFU pushbutton, or MISO jumpers. Keep the original vendor SD card unchanged and write this image to a separate card.

The GitHub release package includes a ready-to-burn SD-card image:

```text
release-packages/bakstaaj-v0.39-bakstaaj.2b-release.zip
  sdcard/bakstaaj-v0.39-bakstaaj.2b-sdcard.img
  sdcard/bakstaaj-v0.39-bakstaaj.2b-sdcard-files.zip
  sdcard/sdimg/
```

The raw `.img` is the preferred install method. It creates a 100 MiB FAT32 boot partition containing the known-good OEM SD boot chain plus the Bakstaaj firmware payload, followed by a 100 MiB ext4 data partition labeled `PLUTO_DATA`:

- `BOOT.bin`
- `uEnv.txt`
- `uImage`
- `devicetree.dtb`
- `uramdisk.image.gz`

The SD package uses the OEM `BOOT.bin` and `uEnv.txt`, keeps the OEM-compatible device tree with the persistent JFFS2 partition patched to 5 MiB, and injects the dashboard-enabled root filesystem. The Pluto-hosted dashboard is available after boot at:

On first boot, the firmware skips the FAT32 boot partition, mounts the second SD partition at `/media`, and expands the ext4 filesystem to the remaining physical SD-card capacity when the card is larger than the shipped image.

```text
http://192.168.2.1/dashboard.html
```

The Pluto-hosted radio API documentation and endpoint test page is available at:

```text
http://192.168.2.1/api-test.html
```

The full app-builder API contract is maintained in `docs/firmware-api-contract.md`.
Sample app clients for Python and browser-based applications are in `examples/`.

### Recommended Windows Burn Tools

Recommended image writers:

- Raspberry Pi Imager: simple, current, and works well for raw `.img` files.
- balenaEtcher: straightforward burn-and-verify workflow.
- Win32 Disk Imager: older but reliable for writing a raw image to a selected drive.

Use the image writer's "write image" or "flash from file" option. Do not copy the `.img` file onto the SD card as a normal file; the writer must write the image to the card device.

### Burn The SD Image

1. Download the latest release ZIP from GitHub and extract it on your Windows computer.
2. Insert a new SD card. Any normal 1 GB or larger card is enough; the boot image itself is small.
3. Open Raspberry Pi Imager, balenaEtcher, or Win32 Disk Imager.
4. Select `sdcard/bakstaaj-v0.39-bakstaaj.2b-sdcard.img` from the extracted release.
5. Select the SD card device. Double-check this carefully; the write operation overwrites the selected device.
6. Write or flash the image, then let the tool finish its verify step if it offers one.
7. Eject the SD card cleanly from Windows.
8. Reinsert the card if you want to inspect it. Windows should show a small FAT32 volume containing `BOOT.bin`, `uEnv.txt`, `uImage`, `devicetree.dtb`, and `uramdisk.image.gz`.

### Boot The Board

1. Power the board off.
2. Set the boot DIP switches to `SD`.
3. Insert the newly written SD card.
4. Connect the `JTAG` USB port to a serial terminal if you want boot logs. Use `115200 8N1`.
5. Connect the `OTG` USB port for the normal Pluto USB gadget drive/network connection.
6. Power the board on.

Expected boot signs:

- U-Boot reads `uEnv.txt`, `uImage`, `devicetree.dtb`, and `uramdisk.image.gz` from the SD card.
- Linux sees the SD card as `mmcblk0`.
- Windows sees the normal Pluto USB mass-storage drive on the OTG port.
- The serial login banner reports `device-fw v0.39-bakstaaj.2b`.
- The dashboard loads at `http://192.168.2.1/dashboard.html` when USB networking is up.

### Copy-Files Fallback

If an image writer is not available, use the copy-files package only on a card that is already formatted as FAT32:

1. Format a spare SD card as FAT32.
2. Extract `sdcard/bakstaaj-v0.39-bakstaaj.2b-sdcard-files.zip`.
3. Copy the extracted files to the root of the SD card, not into a subdirectory.
4. Verify that the card root contains `BOOT.bin`, `uEnv.txt`, `uImage`, `devicetree.dtb`, and `uramdisk.image.gz`.
5. Eject the card cleanly before booting the Pluto board.

The raw `.img` method is preferred because it also recreates the expected FAT boot volume layout. If the copy-files method does not boot, reburn the raw image.

## Recommended Full Deployment From DFU

Use this procedure when installing this Pluto Plus Ethernet/SD firmware package from DFU. Keep the USB cable connected until the final reconnect step.

1. Set the Pluto Plus USB reset jumper to `USRT-MIO52`.
2. Press and hold the DFU button while plugging in or resetting the Pluto Plus. Hold it for about 5-10 seconds, until Windows enumerates the device in DFU mode.
3. Move the USB reset jumper to `USRT-MIO46`. This is the required running position for this firmware.
4. From the extracted firmware package directory, run `FULL_DFU_UPDATE.bat`. The script flashes `pluto.dfu`, `boot.dfu`, and `uboot-env.dfu`.
5. Wait for the Pluto USB mass-storage drive to appear in Windows. It is often `D:`, but use whichever drive letter Windows assigns.
6. Edit `config.frm` on your computer and select the desired `JFFS2_SIZE_MIB` value.
7. Copy `pluto.frm` and the edited `config.frm` to the root of the Pluto USB drive.
8. Safely eject the Pluto USB drive. Do not disconnect the USB cable. The Pluto will process the firmware update and reboot.
9. When the USB drive appears again, edit `config.txt` for any runtime settings you want, such as `[AD936X] force_2r2t = 1` or `[ACTIONS] device_persistent_keys = 1`.
10. Safely eject the Pluto USB drive again and wait for it to reboot.
11. After the device comes back up, physically disconnect and reconnect the USB cable. Use the Pluto normally with the jumper left on `USRT-MIO46`.

## Pluto Plus USB Reset Jumper

For this Pluto Plus Ethernet/SD firmware, the board must run with the USB reset jumper on `USRT-MIO46`.

Standard Pluto-style firmware uses `MIO52` as the USB PHY reset signal. This Pluto Plus firmware enables the physical Ethernet controller, which uses `MIO52..MIO53` for Ethernet MDIO. Because `MIO52` is no longer available for USB reset, the firmware moves USB PHY reset to `MIO46`.

If the jumper is left on `USRT-MIO52`, the firmware can boot far enough to light LEDs but USB may never enumerate. Typical symptoms are no USB mass-storage drive, no normal USB gadget, and sometimes only forced DFU recovery appears. During the full DFU deployment procedure, start from `USRT-MIO52` only long enough to enter DFU with the existing boot path, then move the jumper to `USRT-MIO46` before running `FULL_DFU_UPDATE.bat`. Move it back to `USRT-MIO52` only when returning to standard Pluto-style firmware that expects USB reset on `MIO52`.

## Pluto Plus 2R2T Test Mode

Pluto Plus hardware with populated `TX1`, `RX1`, `TX2`, `RX2`, and clock connectors can be tested with the AD9361 2RX/2TX software path.

Edit `config.txt` on the Pluto USB drive:

```ini
[AD936X]
force_2r2t = 1
attr_name = compatible
attr_val = ad9361
compatible = ad9361
mode = 2r2t
```

After saving and ejecting the drive, reboot the Pluto Plus. `force_2r2t = 1` causes U-Boot to select the Rev.C FIT configuration (`config@8`) and to apply the AD9361/2R2T device-tree settings even if the hardware reference resistor reports a Rev.B-style model.

Verify after reboot:

```sh
fw_printenv force_2r2t attr_name attr_val compatible mode
cat /proc/device-tree/model
dmesg | grep -iE 'ad936|9361|9364|2rx|2tx|cf-ad936'
for d in /sys/bus/iio/devices/iio:device*; do
  echo "== $d: $(cat $d/name 2>/dev/null) =="
  ls $d 2>/dev/null | grep -E '^(in|out)_voltage[01]|out_altvoltage[01]' | sort
done
```

Expected signs of success include `force_2r2t=1`, `attr_val=ad9361`, a Rev.C device-tree model, AD9361 probe messages, and IIO attributes for both channel `0` and channel `1` RF paths.

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
| `bakstaaj-v*-release.zip` | Complete Bakstaaj release package containing DFU, USB mass-storage, and SD-card boot artifacts. |
| `sdcard/bakstaaj-v*-sdcard.img` | Preferred raw SD-card boot image for SD-boot Pluto boards. |
| `sdcard/bakstaaj-v*-sdcard-files.zip` | FAT32 copy-files fallback for SD boot. |
| `sdcard/sdimg/` | Expanded SD boot files used to build the image and copy-files ZIP. |

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

Altenatively, copy `plutosdr-fw-*.zip` to the PlutoSDR USB drive. The updater will extract the firmware and `config.frm`. If an edited `config.frm` already exists on the drive, the updater keeps it instead of replacing it with the default.

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

`df -h /mnt/jffs2` should report a 5 MiB filesystem, and `sh -n /sbin/update.sh` should retun with no output.

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

On Windows, use `FULL_DFU_UPDATE.bat` from the firmware package directory to deploy the complete DFU set. It flashes `pluto.dfu`, `boot.dfu`, and `uboot-env.dfu`, then detaches the device. This is different from `RECOVER.bat`, which only rewrites the main firmware image.

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
