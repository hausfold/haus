# Part of the nebelhaus option surface. Split per room so each room's public API
# lives next to the code that implements it; modules/default.nix imports them all.
# Cross-cutting options (the app roster) stay in modules/options.nix.
#
# prowl's options — tiling + the Caps-Lock leader launcher.
{ lib, ... }:

{
  options.nebelhaus = {
    # ---- optional rooms ----
    # den + hearth + collar are always on (system, shell, Touch ID). These three
    # are the choosable rooms — turning one off drops its packages, agents, and
    # config entirely (the "minimal vs developer" difference is just these flags).
    prowl.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "AeroSpace tiling window management + the Caps-Lock leader launcher.";
    };
  };
}
