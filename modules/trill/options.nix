# Part of the nebelhaus option surface. Split per room so each room's public API
# lives next to the code that implements it; modules/default.nix imports them all.
# Cross-cutting options (the app roster) stay in modules/options.nix.
#
# trill's options — the Messages client.
{ lib, ... }:

{
  options.nebelhaus = {
    trill.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "The trill Messages client, installed via the trill flake (copied to /Applications).";
    };
  };
}
