# Part of the nebelhaus option surface. Split per room so each room's public API
# lives next to the code that implements it; modules/default.nix imports them all.
# Cross-cutting options (the app roster) stay in modules/options.nix.
#
# perch's options — the notch file shelf.
{ lib, ... }:

{
  options.nebelhaus = {
    perch.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        The perch notch file shelf, installed via the perch flake (copied to
        /Applications). Off by default until perch's first release exists — its
        flake pin is a bootstrap placeholder until `bench release perch` cuts a
        real tag, so enabling it before then can't build.
      '';
    };
  };
}
