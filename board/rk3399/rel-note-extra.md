  - "the default" U-Boot build for `rk3399` with following changes:
    - `CONFIG_BOOTDELAY=0` to make it boot faster
    - `CONFIG_PREBOOT=""` to NOT start usb on boot to make it boot faster
      (enumerating USB is _slow_)