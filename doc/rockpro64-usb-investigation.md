ROCKPro64 USB Probe Investigation
=================================

This note documents the current Tow-Boot build wiring for
`pine64-rockpro64`, the revised diagnosis for the `usb@fe900000` failure,
and the smallest reproducible control-build matrix for the next round of
testing.


Current target mapping
----------------------

The only ROCKPro64 board target in this repository is:

- `pine64-rockpro64`

The board definition lives in
[`boards/pine64-rockpro64/default.nix`](../boards/pine64-rockpro64/default.nix)
and selects:

- device identifier: `pine64-rockpro64`
- SoC family: `rockchip-rk3399`
- firmware defconfig: `rockpro64-rk3399_defconfig`
- dedicated firmware storage: SPI flash only

For repeated image builds:

- fastest SPI blob compare target: `nix-build -A pine64-rockpro64.build.firmwareSPI`
- full SD installer product: `nix-build -A pine64-rockpro64`

This board does **not** define `hardware.mmcBootIndex`, so `mmcboot` is not a
relevant comparison target here.


Current source selection
------------------------

Tow-Boot source selection is wired through
[`modules/tow-boot/src.nix`](../modules/tow-boot/src.nix):

- Tow-Boot builds default to U-Boot base version `2023.07`
- Tow-Boot builds fetch `Tow-Boot/U-Boot` tag `tb-2023.07-007`
- stock U-Boot builds use upstream release tarballs when
  `Tow-Boot.buildUBoot = true`

The current checkout identity is defined separately in
[`modules/tow-boot/identity.nix`](../modules/tow-boot/identity.nix):

- `releaseNumber = "008"`
- `releaseIdentifier = "-pre"`

That means local builds identify themselves as `2023.07-008-pre`, even when
they are built from stock upstream `v2023.07`. Do **not** use the `version`
banner alone to decide which image is running.

To swap in a stock upstream tree for testing, it is not enough to pass only
`--arg src /path/to/tree`. The Tow-Boot modules still gate some patch and
configuration logic on `Tow-Boot.uBootVersion`, so stock-upstream tests should
set both:

- `Tow-Boot.buildUBoot = true`
- `Tow-Boot.uBootVersion = "<release>"`


Current diagnosis
-----------------

The failure is currently best classified as a **state/timing-sensitive RK3399
USB3/xHCI problem**, not a Tow-Boot-only regression.

What changed:

- the stock-upstream `v2023.07` control image can still hit a synchronous abort
  while touching `usb@fe900000`
- the same stock-upstream image can also later survive autoboot and enumerate
  the Kingston USB 3.0 device on the same controller

That means the matrix no longer supports the simple conclusion "Tow-Boot fails,
stock `2023.07` passes". The next round must distinguish:

- autoboot preboot path
- manual `usb tree` traversal path
- manual `usb reset` repro path

The likely controller path is still the RK3399 USB3 host side enabled through:

- `&usbdrd3_1`
- `&usbdrd_dwc3_1`

in
[`arch/arm/dts/rk3399-rockpro64.dtsi`](../arch/arm/dts/rk3399-rockpro64.dtsi),
which maps to `usb@fe900000`.


Available helper builds
-----------------------

Helper modules live under `support/rockpro64-usb/` so the comparison builds can
be reproduced without editing `default.nix`.

### Already-built local artifacts

These investigation artifacts already exist locally and do not need to be
rebuilt before the next matrix pass:

- `/tmp/result-rockpro64-stock-2023.07/spi.installer.img`
- `/tmp/result-rockpro64-towboot-usb2phy-revert/spi.installer.img`

The baseline Tow-Boot-source image remains useful as a known-failing reference:

- `/tmp/result-rockpro64-towboot/spi.installer.img`

### Same-vintage stock upstream control (`v2023.07`)

```shell-session
$ nix-build -A pine64-rockpro64 \
    --arg configuration ./support/rockpro64-usb/stock-2023.07.nix \
    -o /tmp/result-rockpro64-stock-2023.07
```

### Tow-Boot-source control with Rockchip USB2 PHY refcounting reverted

```shell-session
$ nix-build -A pine64-rockpro64 \
    --arg configuration ./support/rockpro64-usb/towboot-revert-usb2phy-refcount.nix \
    -o /tmp/result-rockpro64-towboot-usb2phy-revert
```

This build keeps the Tow-Boot-flavoured source tree but removes the extra
init/power reference counting carried in
`drivers/phy/rockchip/phy-rockchip-inno-usb2.c`.

### Latest stable stock upstream control (`v2026.04`)

Use a clean local checkout of upstream U-Boot at tag `v2026.04`.

```shell-session
$ nix-build -A pine64-rockpro64 \
    --arg configuration ./support/rockpro64-usb/stock-2026.04.nix \
    --arg src /path/to/u-boot-v2026.04 \
    -o /tmp/result-rockpro64-stock-2026.04
```

### DT-only control with the `fe900000` host path disabled

This is a test-only control build. It does **not** change the default
`pine64-rockpro64` product wiring.

```shell-session
$ nix-build -A pine64-rockpro64 \
    --arg configuration ./support/rockpro64-usb/dt-disable-fe900000.nix \
    -o /tmp/result-rockpro64-dt-disable-fe900000
```

The helper applies a tiny board-local patch that marks both:

- `&usbdrd3_1`
- `&usbdrd_dwc3_1`

disabled in `rk3399-rockpro64.dtsi`.


Operator protocol
-----------------

Use the same physical setup for every trial:

- ROCKPro64 with SPI bypassed
- the same Kingston USB 3.0 device
- the same USB adapter
- the same USB 3.0 port
- the same serial setup

Before writing the SD card, record the exact artifact path you are about to
flash. These images all print a `2023.07-008-pre` banner, so the artifact path
is the ground truth for build identity.

For each flashed image, run **3 cold-boot trials**. Each trial uses this exact
sequence:

1. Power on with the USB device already attached.
2. Capture the full autoboot USB log without typing anything.
3. If the prompt is reached, run:

   ```text
   => usb tree
   ```

4. If the board is still alive, run:

   ```text
   => usb reset
   ```

5. If the board is still alive, run:

   ```text
   => usb tree
   ```

Treat these as distinct repro paths:

- autoboot preboot
- manual `usb tree`
- manual `usb reset`

Record one result row per trial with:

- flashed artifact path
- cold-boot trial number
- autoboot result: `abort`, `warn+enumerate`, `no device`, or `other`
- `usb tree` result: `ok` or `reset`
- `usb reset` result: `ok` or `reset`
- final detected device tree summary


Decision rules
--------------

A build is "clean" only if all 3 trials reach the prompt and complete the full
command sequence without reset.

A build is "failing" if any trial resets during autoboot, `usb tree`, or
`usb reset`.

The next-pass decision rules are:

1. If stock `2023.07` and stock `2026.04` are both clean, revisit
   Tow-Boot-specific source deltas only.
2. If stock `2023.07` fails but stock `2026.04` is clean, treat the issue as
   fixed upstream and prefer a source bump or backport over a board-local
   workaround.
3. If stock `2023.07` and stock `2026.04` both fail, treat the issue as
   upstream-or-hardware sensitive and continue to the DT-disable control.
4. If the DT-disable control is clean while enabled-controller builds fail,
   carry a temporary board-specific workaround by disabling the `fe900000`
   host path only.
5. If the DT-disable control also fails, stop before adding a workaround and
   continue with deeper xHCI/DWC3 instrumentation.
