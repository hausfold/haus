# Part of the haus option surface. Split per room so each room's public API
# lives next to the code that implements it; modules/default.nix imports them all.
# Cross-cutting options (the app roster) stay in modules/options.nix.
#
# perch's options — the notch file shelf.
{ lib, ... }:

{
  options.haus = {
    perch.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "The perch notch file shelf, installed via the perch flake (copied to /Applications).";
    };

    perch.followSystemAppearance = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Let the shelf's palette follow macOS Light/Dark Mode instead of pinning
        one polarity: perch gets the nebelung variant AND its latte counterpart
        at your haus.theme.contrast, and picks between them itself — no
        rebuild, no relaunch.

        Same honest scope as the pounce option of the same name: with
        this on, perch does NOT follow haus.theme.flavor, because asking to
        follow the system says the polarity is macOS's call. The contrast axis
        still applies to both halves. Set it false to pin the shelf to
        theme.flavor like every other themed tool.

        Perch has no theme picker of its own — the shelf is a five-second
        surface with nowhere to put one — so this is the only word on its
        colors.
      '';
    };
  };
}
