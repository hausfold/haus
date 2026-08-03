# Part of the nebelhaus option surface. Split per room so each room's public API
# lives next to the code that implements it; modules/default.nix imports them all.
# Cross-cutting options (the app roster) stay in modules/options.nix.
#
# apps' options — the picks the rice makes for you, and which of them owns a
# file type. One knob per pick: turn it off and the rice installs nothing and
# rebinds nothing, leaving that job to you (or to a roster entry of your own).
{ lib, ... }:

{
  options.nebelhaus.apps = {
    videoPlayer = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Install IINA — the rice's video player — as the roster entry `iina`.
          A nixpkgs build, so it lands in ~/Applications/Home Manager Apps
          rather than /Applications.

          On by default: macOS ships QuickTime Player, which refuses most of
          what you actually double-click (mkv, webm, and anything not in
          Apple's codec list), so "a video player that plays videos" is part
          of what the rice considers a finished machine.

          Set false and nothing is installed or rebound — bring your own
          player via the pounce "Install App" palette command or a roster
          entry. Once on it is a roster entry like any other: give it a leader
          letter with `nebelhaus.roster.iina.key`, or pin a different build
          with `nebelhaus.roster.iina.package`.
        '';
      };

      claimFileTypes = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Make IINA the default handler for every video extension it declares
          — mp4, m4v, mov, mkv, webm, avi, wmv, flv, mpg, 3gp, ogv, mts/m2ts,
          vob, rm, … — so double-clicking a video opens IINA instead of
          QuickTime Player, TV or a browser. Ignored unless the player is
          installed.

          Video only. Audio (mp3, flac, m4a, wav, …), `.gif` and playlists
          keep whatever owns them today, since "open videos in IINA" rarely
          means "and my music library too". `.ts` is deliberately excluded as
          well: it is TypeScript far more often than an MPEG transport stream,
          and `nebelhaus.hearth.hijackFileAssociations` claims it for the
          editor.

          This sets the USER default (via `duti`) — the same record Finder's
          Get Info ▸ Change All writes, so it is undoable by hand. Set false to
          install the app and leave every association alone.
        '';
      };
    };
  };
}
