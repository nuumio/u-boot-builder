  - "the default" U-Boot build for `rk3288` with following change:
    - `CONFIG_PREBOOT=""` to NOT start usb on boot to make it boot faster (enumerating USB is _slow_)