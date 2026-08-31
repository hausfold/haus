# Apps — the picks the rice makes for you.
#
# Every other room installs an app because it needs one: windows brings AeroSpace
# because it IS the tiler, bar brings SketchyBar because it IS the bar. This
# room is the other kind — the editorial ones, the apps a machine the rice calls
# finished has rather than the ones a room needs to do its job. They live here
# rather than wherever they happened to get installed: a pick that drifts into
# the room whose code was next door is how the shell room ended up owning a
# media player for months.
#
# The shape each pick takes: one `haus.apps.<thing>.enable` knob and a roster
# entry (never a bare package — the roster is the one list of what this machine
# HAS, and it's what makes a second copy from a cask a build warning instead of
# a silent duplicate).
#
# What does NOT belong here: an app some other room needs to do its job, and
# anything personal. A host's own apps go in its own roster entries.
{
  config,
  lib,
  ...
}:

let
  cfg = config.haus.apps;

  # ---- packs ----------------------------------------------------------------
  # A collection file is data — `{ haus.roster = { … }; }` and nothing else — so
  # this room can import one and lower it. The priority is applied PER LEAF, and
  # that detail is the whole trick: `mkDefault` on the whole `roster` attrset
  # attaches to the entire definition, so one normal-priority field in a host
  # would outrank the collection's WHOLE roster — measured at three of four apps
  # silently not installed. Below the option leaf you set a priority; at or above
  # it you replace a value. `app-collections` in `nix flake check` is what keeps
  # that true.
  #
  # This is the ONLY route now. `haus.lib.pack` used to import the same shape
  # from a stranger, and it was retired on 2026-08-17: a stranger's app
  # collection is a ROOM, so haus ships exactly two shareable formats — a
  # desktop (data) and a room (code). These files are this repo's own.
  # The one map from a switch name to the file it installs, shared with the
  # `app-collections` check so the two cannot drift (packs/default.nix).
  collectionFiles = import ./packs;

  packEntries =
    name:
    let
      path = collectionFiles.${name};
      body = (import path).haus or { };
      stray = builtins.filter (k: k != "roster") (builtins.attrNames body);
    in
    # A collection file is narrowed to `haus.roster`, and this is the only thing
    # left enforcing that. `checkPack` used to, from the flake, back when a
    # stranger could publish one; the format retired and took the check with it.
    # The rule did not retire: only `roster` is carried through below, so
    # anything else the file sets would be SILENTLY DROPPED — no error, no
    # warning, just a setting that never happened. `writing.nix`'s own footnote
    # still names `haus.workspaces` as the obvious next thing to reach for.
    assert
      stray == [ ]
      || throw (
        "modules/apps/packs/${name}.nix sets haus.${builtins.concatStringsSep ", haus." stray}"
        + " — a saved collection may only set `haus.roster`, because that is all the Apps room"
        + " carries through. Say the rest in a room, or in the host that turns this on."
      );
    lib.mapAttrs (_: entry: lib.mapAttrs (_: value: lib.mkDefault value) entry) (
      (import path).haus.roster
    );
in
{
  # A roster entry, not `home.packages`: it shows up in `this-machine.md`, a host
  # can retune it by app id, and naming the same app from two sources trips the
  # roster's one-source assertion instead of quietly installing it twice (which
  # is exactly what happened for months — see modules/roster).
  haus.roster = lib.mkMerge [
    (lib.mkIf cfg.vscode.enable {
      vscode = {
        name = lib.mkDefault "Visual Studio Code";
        cask = lib.mkDefault "visual-studio-code";
      };
    })
    (lib.mkIf cfg.cursor.enable {
      cursor = {
        name = lib.mkDefault "Cursor";
        cask = lib.mkDefault "cursor";
      };
    })
    (lib.mkIf cfg.zed.enable {
      zed = {
        name = lib.mkDefault "Zed";
        cask = lib.mkDefault "zed";
      };
    })
    (lib.mkIf cfg.packs.writing.enable (packEntries "writing"))
  ];
}
