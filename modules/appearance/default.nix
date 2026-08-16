# Appearance — the room's own profile, and nothing else.
#
# The room itself is spread across the modules that own each surface (theme,
# wallpaper, fonts in core, the accessibility keys in core, `ui.scale` in
# modules/options.nix). What lives HERE is the one thing none of them owns: a
# named profile that answers a whole-machine question — "make this readable" —
# by setting four of their options at once.
#
# It was `presets/large-print.nix`, a top-level file a consumer stacked into
# `extraModules` beside a whole rice. Under the rooms model whole selections do
# not stack, so a cross-cutting CONCERN that is still useful becomes a
# room-owned profile instead (notes/rooms-desktops.md, step 5). Same four
# values, one address, and it is desktop-safe: a desktop may name it, and a host
# may override any single value it sets with a plain assignment.
#
# Every value is `mkDefault` (1000), which is what makes that ladder work:
#
#   100   the host       haus.ui.scale = 1.0;     ← wins
#   900   the desktop    haus.ui.scale = 1.2;     ← wins over the profile
#   1000  here           haus.ui.scale = 1.4;
#   1500  the option's own default
#
# Adding a value here is therefore additive for a machine that never asked for
# large print, and overridable for one that did.
{ config, lib, ... }:

let
  cfg = config.haus.appearance;
in
{
  config = lib.mkIf cfg.largePrint {
    haus = {
      ui.scale = lib.mkDefault 1.4;

      theme.contrast = lib.mkDefault "high";

      accessibility.increaseContrast = lib.mkDefault true;

      # `main`, not `internal` — see the option's description. This CREATES the
      # entry when none exists, so a host naming its own panel by UUID is
      # untouched and a host that also names `main` simply outranks this.
      displays.main.uiScale = lib.mkDefault "larger-text";
    };
  };
}
