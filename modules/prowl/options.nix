# Part of the nebelhaus option surface. Split per room so each room's public API
# lives next to the code that implements it; modules/default.nix imports them all.
# Cross-cutting options (the app roster) stay in modules/options.nix.
#
# prowl's options — tiling + the leader launcher. WHICH keys drive them is
# haus.keys.* in modules/options.nix: cross-cutting, because `leader` and
# `windowNav` are prowl's while `palette` is pounce's, and one table has to resolve
# all three so a chord and the caption documenting it can't drift.
{ lib, ... }:

{
  options.haus = {
    # ---- optional rooms ----
    # den + hearth + collar are always on (system, shell, Touch ID). These three
    # are the choosable rooms — turning one off drops its packages, agents, and
    # config entirely (the "minimal vs developer" difference is just these flags).
    prowl.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        AeroSpace tiling window management + the leader-key launcher.

        This is the room switch: off drops AeroSpace, its launch agent, the
        wake-time window re-sort and the key remap entirely. To keep the tiler but
        leave the keyboard alone, use haus.keys.leader = "none" and
        haus.keys.windowNav = "none" instead of turning the room off.
      '';
    };
  };
}
