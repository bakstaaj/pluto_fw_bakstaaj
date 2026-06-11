Pluto Plus CLG400 retained build assets

These files are retained so future firmware builds do not depend on an
ephemeral WSL/Docker build directory for the known-good Pluto Plus FPGA image.

Files:
- pluto-plus-source.frm: source firmware image used for FPGA extraction.
- pluto-plus-source.itb: FIT image from pluto-plus-source.frm with the FRM footer removed.
- system_top.bit: FPGA bitstream extracted from fpga@1 in pluto-plus-source.itb.
- boot.frm / boot.dfu: matching known-good Pluto Plus boot artifacts.
- SHA256SUMS.txt: hashes for the retained assets.

Set REFRESH_BIT=1 when running the container build to force re-extraction from
pluto-plus-source.frm.
