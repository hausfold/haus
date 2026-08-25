# Part of the haus option surface. Split per room so each room's public API
# lives next to the code that implements it; modules/default.nix imports them all.
# Cross-cutting options (the app roster) stay in modules/options.nix.
#
# The trill room's options — the notification compositor.
{ lib, ... }:

{
  options.haus = {
    trill.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        The trill notification compositor, installed from its own flake and
        copied to a fixed `/Applications/Trill.app`.

        haus has drawn its banners through trill since `haus-notify` landed, but
        by *finding* it at runtime — PATH, then `~/Applications`, then
        `/Applications` — and falling back to Apple's banner when nothing
        answered. That still works and is still the fallback. What this switch
        adds is the other half: the bundle actually being there, at a path that
        does not move, pinned by this machine's flake lock like every other room.

        Why the path is fixed rather than a store path: trill's whole
        `trill doctor` and System Mirror surface is a **Full Disk Access** grant,
        and macOS keys a TCC grant per app *path* and signing identity. A store
        path changes on every version bump, so the grant would drop on the
        rebuild that installed the fix you wanted. `/Applications/Trill.app` is
        where a drag-install or a cask would have put it, so an existing grant
        carries over rather than being asked for again.

        Off by default, and not only out of taste: there is no `trill` cask and
        the `trill` command already resolves without this room, so turning it on
        is a decision to have haus own the bundle.

        It does **not** put `trill` on PATH — `modules/core/trill.sh` already
        does, for every install source including this one, and a second
        `bin/trill` would be a build-time collision rather than a redundancy.
      '';
    };
  };
}
