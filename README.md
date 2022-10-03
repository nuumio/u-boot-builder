# U-Boot Builder

Builds U-Boot binaries on GitHub.

# License

For stuff in this repo the license is MIT.

U-Boot and Arm Trusted Firmware have their own licences.

# Directory / file structure

- `boards` directory contains all the information for builds
- every directory under `boards`, including, itself may contain
  - `atf-patches` directory for ATF patches (`*.patch`)
  - `uboot-patches` directory for U-Boot patches (`*.patch`)
  - `config` file having any of following:
    - `ATF_VERSION` ATF version to build (use a tag)
    - `ATF_PLATFORM` ATF platform (used in make)
    - `ATF_CROSS_COMPILE` ATF CROSS_COMPILE option (used in make)
    - `UBOOT_VERSION` U-Boot version to build (use a tag)
    - `UBOOT_CONFIG` U-Boot defconfig (used in make)
    - `UBOOT_CROSS_COMPILE` U-Boot CROSS_COMPILE option (used in make)
- patch apply order: closest to root first in filename sort order.
- directory structure in `boards` is expected to have `platform`/`board`
  as leaf directories (which may contain `atf-patches` and `uboot-patches`)
