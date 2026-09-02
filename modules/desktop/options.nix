# Part of the haus option surface. Split per room so each room's public API
# lives next to the code that implements it; modules/default.nix imports them all.
#
# The desktop seam's own record: which desktop this machine selected. Internal,
# and under the `haus._*` prefix haus reserves for wiring rather than
# settings (modules/lib/contrib.nix has the same shape) — a desktop is chosen by
# the builder, not by writing an option, so there is nothing here for a host to
# set. What it exists for is the one thing the module system cannot say on its
# own: WHICH file the values came from, so "you selected two desktops" can name
# both instead of reporting a conflict between two anonymous definitions.
{ lib, ... }:

{
  options.haus._desktop.sources = lib.mkOption {
    internal = true;
    visible = false;
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = ''
      The desktop files selected on this machine, one entry per `lib.desktop`
      import. A full builder passes exactly one; a standalone `darwinModules`
      import passes none and stays a room on the bare foundation.
    '';
  };
}
