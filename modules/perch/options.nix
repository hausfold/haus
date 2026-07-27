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
      default = true;
      description = "The perch notch file shelf, installed via the perch flake (copied to /Applications).";
    };
  };
}
