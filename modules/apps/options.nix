# Part of the nebelhaus option surface. Split per room so each room's public API
# lives next to the code that implements it; modules/default.nix imports them all.
# Cross-cutting options (the app roster) stay in modules/options.nix.
#
# apps' options — the picks the rice makes for you, and which of them owns a
# file type. One knob per pick: turn it off and the rice installs nothing and
# rebinds nothing, leaving that job to you (or to a roster entry of your own).
{ lib, ... }:

{
  options.haus.apps = {
    videoPlayer = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Install IINA — haus's video player — as the roster entry `iina`.
          A nixpkgs build, so it lands in ~/Applications/Home Manager Apps
          rather than /Applications.

          The nebelhaus desktop turns this on, because macOS ships QuickTime
          Player, which refuses most of what you actually double-click (mkv,
          webm, and anything not in Apple's codec list) — so "a video player
          that plays videos" is part of what that desktop considers a finished
          machine. The bare layer installs nothing you didn't ask for.

          Set false and nothing is installed or rebound — bring your own
          player via the pounce "Install App" palette command or a roster
          entry. Once on it is a roster entry like any other: give it a leader
          letter with `haus.roster.iina.key`, or pin a different build
          with `haus.roster.iina.package`.
        '';
      };

      claimFileTypes = lib.mkOption {
        type = lib.types.bool;
        # In-room taste: it is ignored unless the player is installed, so it
        # only ever acts on a machine that already asked for IINA. Installing a
        # video player that doesn't open videos is the useless-when-enabled
        # shape the room contract rules out.
        default = true;
        description = ''
          Make IINA the default handler for the everyday video extensions —
          mp4, m4v, mov, mpg, mpeg, mkv, webm, avi, wmv, flv, 3gp, ogv, vob —
          so double-clicking a video opens IINA instead of QuickTime Player, TV
          or a browser. Ignored unless the player is installed.

          A short list on purpose: it covers what you actually double-click,
          not everything IINA can decode. Dead, professional and DRM'd
          containers (qt, divx, asf, f4v, 3g2, ogm, rm, rmvb, mxf, dv, …) are
          left alone — they still play via Open With, they just don't get the
          default, and every extension haus claims is a binding it
          re-asserts on every rebuild.

          Video only. Audio (mp3, flac, m4a, wav, …), `.gif` and playlists
          keep whatever owns them today, since "open videos in IINA" rarely
          means "and my music library too". The transport-stream extensions
          `.ts`, `.mts` and `.m2ts` are excluded too: on a developer's machine
          they are TypeScript far more often than video, and
          `haus.hearth.hijackFileAssociations` claims them for the editor.
          Claiming them here as well made macOS stop and ask which app should
          win on every single rebuild, because `.mts` and `.m2ts` share one
          UTI.

          This sets the USER default (via `duti`) — the same record Finder's
          Get Info ▸ Change All writes, so it is undoable by hand. Set false to
          install the app and leave every association alone.
        '';
      };
    };

    # ---- packs ----------------------------------------------------------
    # A saved app collection, named. `pack` used to be a top-level concept a
    # consumer stacked beside a whole rice; it is something this room offers
    # now, because "what's on this machine" is the question the Apps room
    # already answers (the workshop's notes/rooms-desktops.md, step 5).
    #
    # One switch per shipped pack rather than a list of names: the switch is
    # then an ordinary desktop-safe boolean the registry can classify, the
    # options reference documents each collection where a person will look for
    # it, and a typo is an unknown-option error instead of a silently ignored
    # string. A stranger's pack file still arrives through `haus.lib.pack`,
    # which is the same seam at the same priority.
    packs.writing.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
      description = ''
        Install the **writing** collection: Obsidian, Zotero, Anki and calibre —
        a Mac that reads and writes rather than compiles.

        These arrive as ordinary roster entries at `mkDefault`, so anything you
        say about one of them in your own host file wins per FIELD and the rest
        of the entry survives:

          haus.roster.zotero.key = "y";      # a letter of your own
          haus.roster.obsidian.appId = "…";  # osascript -e 'id of app "Obsidian"'

        Two of them claim a leader letter (`o`, `l`, `k`) and none claims a
        workspace — a workspace names its own members, so give one to Obsidian
        in your host with `haus.workspaces`. The file is
        `modules/apps/packs/writing.nix`, and it is readable data: four casks
        and the keys to reach them.
      '';
    };
  };
}
