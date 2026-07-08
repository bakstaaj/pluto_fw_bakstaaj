bakStaaJ Pluto Firmware Release

Version: v0.39-bakstaaj.2

This package is assembled from the locally built Pluto firmware payload in
build-tx-dsp-appbuilder-fw-plutoplus-clg400, with the release version string injected into the initramfs.

Firmware update files:
- firmware/pluto.frm
- firmware/pluto.dfu
- firmware/pluto.itb
- firmware/config.frm
- firmware/boot.frm
- firmware/boot.dfu
- firmware/uboot-env.dfu

SD boot files:
- sdcard/sdimg/
- sdcard/bakstaaj-v0.39-bakstaaj.2-sdcard-files.zip
- sdcard/bakstaaj-v0.39-bakstaaj.2-sdcard.img

For the new SD-boot board, use the SD-card files or image. The SD boot package
keeps the OEM BOOT.bin and uEnv.txt boot chain, uses the OEM DTB with qspi-nvmfs
patched to 5 MiB, and injects the dashboard-enabled rootfs.

Dashboard:
- http://192.168.2.1/dashboard.html

Version source:
- /opt/VERSIONS contains: device-fw v0.39-bakstaaj.2

Notes:
- This release was assembled from a completed Docker firmware build.
- The .frm/.dfu files are generated from a patched FIT image so they share the
  same dashboard-enabled rootfs and version string.
