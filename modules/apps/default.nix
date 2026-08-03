# Apps — the picks the rice makes for you, and which of them owns a file type.
#
# Every other room installs an app because it needs one: prowl brings AeroSpace
# because it IS the tiler, sill brings SketchyBar because it IS the bar. This
# room is the other kind — the editorial ones. A machine the rice calls finished
# should play a video you double-click, and macOS out of the box does not (
# QuickTime declines mkv, webm, and most of what isn't Apple's codec list). So
# the pick lives here rather than wherever it happened to get installed: IINA
# spent months in hearth, the SHELL room, purely because hearth's file-
# association code was next door.
#
# The shape each pick takes: one `nebelhaus.apps.<thing>.enable` knob, a roster
# entry (never a bare package — the roster is the one list of what this machine
# HAS, and it's what makes a second copy from a cask a build warning instead of
# a silent duplicate), and optionally the file types that pick should own.
#
# What does NOT belong here: an app some other room needs to do its job, and
# anything personal. A host's own apps go in its own roster entries.
{
  config,
  lib,
  pkgs,
  username,
  ...
}:

let
  cfg = config.nebelhaus.apps;
  videoCfg = cfg.videoPlayer;

  # The extensions IINA declares as VIDEO, read off its own Info.plist
  # (CFBundleDocumentTypes, IINA 1.4.4) rather than guessed: duti can only bind
  # an extension whose UTI some installed app declares, so a type IINA doesn't
  # claim would be a silent no-op here rather than an error.
  #
  # Trimmed from that list on purpose:
  #   - audio (mp3, flac, m4a, wav, aac, opus, …), `gif`, playlists (m3u/pls)
  #     and IINA's own plugin types — "open videos in IINA" shouldn't quietly
  #     take the music library, or the gif the zellij previewer shows inline.
  #   - `ts`: TypeScript far more often than an MPEG transport stream, and
  #     hearth's hijackFileAssociations claims it for the editor. mts/m2ts do
  #     still bind.
  #   - `dat`, `swf`, `yuv`, `wv`, `mcf`, `mks`: junk drawer, WavPack audio, or
  #     Matroska subtitles — nothing you double-click expecting a player.
  #
  # Three of them (mk3d, xvid, amv) answer with a benign -50 — their extension
  # resolves to a purely dynamic UTI nothing binds — and land on IINA anyway,
  # because IINA is the only app declaring them. The activation swallows it, the
  # same way hearth's editor hijack does.
  # Grouped by family and left hand-wrapped, like hearth's editorExts: nixfmt
  # would put each of the 29 on its own line and bury the shape.
  iinaVideoExts = [
    "mp4" "m4v" "mov" "qt" "mpg" "mpeg"
    "mkv" "mk3d" "webm" "avi" "divx" "xvid"
    "wmv" "asf" "flv" "f4v" "f4p"
    "3gp" "3g2" "ogv" "ogm" "mts" "m2ts"
    "rm" "rmvb" "vob" "amv" "mxf" "dv"
  ];

  lsregister = "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister";

  iinaPins = lib.concatStringsSep "\n" (
    map (
      ext:
      ''$DRY_RUN_CMD "${pkgs.duti}/bin/duti" -s com.colliderli.iina "${ext}" all 2>/dev/null || true''
    ) iinaVideoExts
  );
in
{
  # A roster entry, not `home.packages`: it shows up in `this-machine.md`, a host
  # can retune it by app id, and naming the same app from two sources trips the
  # roster's one-source assertion instead of quietly installing IINA twice (which
  # is exactly what happened for months — see modules/roster).
  nebelhaus.roster = lib.mkIf videoCfg.enable {
    iina = {
      name = lib.mkDefault "IINA";
      package = lib.mkDefault pkgs.iina;
    };
  };

  home-manager.users.${username} =
    # A module function so the inner `lib` is home-manager's (carries `lib.hm`);
    # the outer `lib` above is plain nixpkgs lib and has no `.hm`.
    { lib, ... }:
    {
      # Video files → IINA.
      #
      # lsregister first, every activation, and that ordering is the whole
      # trick: binding a handler LaunchServices hasn't seen yet fails with a
      # silent -50. IINA's store path moves on every version bump, so the
      # registration is exactly as perishable as the binding — hearth
      # re-registers the whole Home Manager Apps directory for the same reason,
      # and this names both plausible bundles so the room works whether the
      # player came from nixpkgs or a cask.
      #
      # duti is idempotent and only ever writes the USER default (the record
      # Finder's Get Info ▸ Change All writes), so re-running costs nothing and
      # undoing it never needs Nix.
      home.activation.iinaFileTypes = lib.mkIf (videoCfg.enable && videoCfg.claimFileTypes) (
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          for app in "$HOME/Applications/Home Manager Apps/IINA.app" "/Applications/IINA.app"; do
            [ -e "$app" ] && $DRY_RUN_CMD ${lsregister} -f "$app" 2>/dev/null || true
          done

          if [ -x "${pkgs.duti}/bin/duti" ]; then
          ${iinaPins}
          fi
        ''
      );
    };
}
