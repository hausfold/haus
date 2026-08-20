# Part of the haus option surface. Split per room so each room's public API
# lives next to the code that implements it; modules/default.nix imports them all.
# Cross-cutting options (the app roster) stay in modules/options.nix.
#
# The shelf room's options — the file shelf under the notch.
{ lib, ... }:

{
  options.haus = {
    shelf.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        The perch notch file shelf, installed from its own flake (copied to
        /Applications, with its `perch` command line tool linked onto PATH).
      '';
    };

    shelf.followSystemAppearance = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Let the shelf's palette follow macOS Light/Dark Mode instead of pinning
        one polarity: the shelf gets the nebelung variant AND its latte counterpart
        at your haus.theme.contrast, and picks between them itself — no
        rebuild, no relaunch.

        Same honest scope as the launcher option of the same name: with
        this on, the shelf does NOT follow haus.theme.flavor, because asking to
        follow the system says the polarity is macOS's call. The contrast axis
        still applies to both halves. Set it false to pin the shelf to
        theme.flavor like every other themed tool.

        The shelf has no theme picker of its own — it is a five-second
        surface with nowhere to put one — so this is the only word on its
        colors.
      '';
    };
  };
}
