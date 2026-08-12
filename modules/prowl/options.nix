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
    # den + hearth are the floor and have no switch (system, shell). Of the
    # rooms you can SEE, all six have one — prowl, sill, pounce, perch, hush,
    # collar — and turning one off drops its packages, agents and config
    # entirely. (The cross-cutting modules — apps, displays, roster, secrets,
    # theme, wallpaper, workspaces — have no room switch either; they aren't
    # rooms. And `full`/bootstrap deliberately expose only sill+prowl+pounce+
    # tour as the install-time choice, which is a narrower surface than this,
    # not a different list.)
    #
    # collar is NOT always on: haus.collar.enable is real and documented
    # (modules/collar/options.nix). This comment used to say it was, and that is
    # where "Touch ID for sudo can't be removed" got into the docs — caught by
    # hausfold.co#22's fact-check pass. Don't put it back.
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
