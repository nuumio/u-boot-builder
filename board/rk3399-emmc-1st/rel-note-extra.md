  - "the eMMC 1st" U-Boot build for `rk3399` with following changes:
    - `CONFIG_BOOTDELAY=0` to make it boot faster
    - `CONFIG_PREBOOT=""` to NOT start usb on boot to make it boot faster
      (enumerating USB is _slow_)
    - boot order is changed to: 1) eMMC, 2) SD card
  - only building rockpro64 (at least for now),
    it's for my (nuumio's) special retrogaming rockpro64 setup