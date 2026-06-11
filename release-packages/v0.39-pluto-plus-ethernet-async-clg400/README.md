# Pluto Plus Ethernet Async Firmware Package

Release package for Pluto Plus CLG400 firmware based on ADI PlutoSDR firmware v0.39.

## Install Files

Copy these files to the Pluto USB mass-storage drive:

- `pluto.frm`
- `config.frm`

Do not copy `boot.frm` when upgrading from the previously tested Pluto Plus firmware.

## Hardware Jumper

Set the Pluto Plus USB reset jumper to `USRT-MIO46` before booting this firmware.

This firmware enables physical Ethernet, which uses `MIO52..MIO53` for Ethernet MDIO. Standard Pluto-style firmware uses `MIO52` for USB PHY reset, so this firmware moves USB PHY reset to `MIO46`.

If the jumper remains on `USRT-MIO52`, the board may appear to boot but USB may not enumerate.

## Ethernet Behavior

Physical Ethernet starts asynchronously at boot. If the Pluto cannot obtain a network DHCP lease, it falls back to:

- Pluto address: `192.168.3.1`
- DHCP range served to the connected host: `192.168.3.10` through `192.168.3.99`

## Files

- `plutosdr-fw-plutoplus-ethernet-async-clg400-complete.zip`: complete firmware package.
- `pluto.frm`: USB mass-storage firmware update file.
- `config.frm`: install-time configuration file.
- `pluto.dfu`: DFU firmware image used by `RECOVER.bat`.
- `BUILD_MANIFEST.txt`: build contents and jumper notes.
- `SHA256SUMS.txt`: hashes for the generated artifacts.
- `RECOVER.bat`: Windows DFU recovery helper for restoring the known-good firmware.
