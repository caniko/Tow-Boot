{ lib, ... }:

{
  Tow-Boot = {
    buildUBoot = true;
    uBootVersion = "2026.04";
    patches = lib.mkForce [];
    config = [
      (helpers: with helpers; {
        # Newer upstream Rockchip builds no longer inject the legacy
        # distro_bootcmd environment through rk3399_common.h, while
        # Tow-Boot's generic config layer still defaults bootcmd to
        # "run distro_bootcmd". Use bootstd for this stock-upstream
        # control build so autoboot exercises the modern path.
        #
        # Use the text bootflow menu for interactive serial-driven testing:
        # scan bootflows, show the upstream menu, and boot the selected
        # entry if one is chosen.
        BOOTSTD = lib.mkForce yes;
        BOOTSTD_FULL = lib.mkForce yes;
        BOOTSTD_DEFAULTS = lib.mkForce yes;
        BOOTCOMMAND = lib.mkForce (
          freeform ''"bootflow scan -l; if bootflow menu -t; then bootflow boot; fi"''
        );
      })
    ];

    # This repo does not pin a v2026.04 upstream tarball hash yet.
    # The intended test path is to pass a local upstream checkout with:
    #
    #   --arg src /path/to/u-boot-v2026.04
    #
    # default.nix injects that `src` override with a stronger definition, so
    # this mkDefault only trips when the caller forgets to pass one.
    src = lib.mkDefault (builtins.throw ''
      support/rockpro64-usb/stock-2026.04.nix requires a local upstream tree.

      Re-run with:

        --arg src /path/to/u-boot-v2026.04
    '');
  };
}
