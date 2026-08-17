# Apps — the picks the rice makes for you, and which of them owns a file type.
#
# Every other room installs an app because it needs one: windows brings AeroSpace
# because it IS the tiler, bar brings SketchyBar because it IS the bar. This
# room is the other kind — the editorial ones. A machine the rice calls finished
# should play a video you double-click, and macOS out of the box does not (
# QuickTime declines mkv, webm, and most of what isn't Apple's codec list). So
# the pick lives here rather than wherever it happened to get installed: IINA
# spent months in terminal, the SHELL room, purely because terminal's file-
# association code was next door.
#
# The shape each pick takes: one `haus.apps.<thing>.enable` knob, a roster
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
  cfg = config.haus.apps;
  videoCfg = cfg.videoPlayer;

  # The extensions IINA declares as VIDEO, read off its own Info.plist
  # (CFBundleDocumentTypes, IINA 1.4.4) rather than guessed: duti can only bind
  # an extension whose UTI some installed app declares, so a type IINA doesn't
  # claim would be a silent no-op here rather than an error.
  #
  # Kept deliberately SHORT — what a normal machine double-clicks, not
  # everything IINA can decode. Every entry here is a standing claim re-asserted
  # on EVERY activation, so an entry that argues with another app's claim isn't
  # a one-time paper cut: it's a modal dialog every single rebuild (that is
  # exactly what mts/m2ts did — see below). An obscure format left off still
  # plays in IINA via Open With; it just doesn't get to own the double-click.
  #
  # Trimmed from IINA's own list on purpose:
  #   - audio (mp3, flac, m4a, wav, aac, opus, …), `gif`, playlists (m3u/pls)
  #     and IINA's own plugin types — "open videos in IINA" shouldn't quietly
  #     take the music library, or the gif the zellij previewer shows inline.
  #   - `ts`, `mts`, `m2ts`: transport streams by name, TypeScript by practice.
  #     terminal's hijackFileAssociations claims all three for the editor (`.mts`
  #     is an ESM TypeScript module). `mts` used to sit in BOTH lists, and since
  #     `.mts` and `.m2ts` resolve to ONE shared AVCHD UTI, every activation
  #     re-ran both claims against that single type and macOS stopped to ask
  #     which app won — every rebuild, forever. One owner per type; the editor
  #     keeps this one.
  #   - dead, pro or DRM'd containers (qt, divx, asf, f4v, f4p, 3g2, ogm, rm,
  #     rmvb, mxf, dv) and the purely-dynamic UTIs nothing else on the machine
  #     declares (mk3d, xvid, amv) — nobody double-clicks these, and the dynamic
  #     three only ever bound because IINA was their sole declarer.
  #   - `dat`, `swf`, `yuv`, `wv`, `mcf`, `mks`: junk drawer, WavPack audio, or
  #     Matroska subtitles — nothing you double-click expecting a player.
  #
  # Grouped by family and left hand-wrapped, like terminal's editorExts: nixfmt
  # would put each on its own line and bury the shape.
  #
  # Adding one back? Check it against terminal's `editorExts` FIRST — and against
  # the UTI, not just the spelling, since one UTI can carry several extensions.
  iinaVideoExts = [
    "mp4" "m4v" "mov" "mpg" "mpeg"
    "mkv" "webm" "avi" "wmv" "flv"
    "3gp" "ogv" "vob"
  ];

  lsregister = "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister";

  iinaPins = lib.concatStringsSep "\n" (
    map (
      ext:
      ''$DRY_RUN_CMD "${pkgs.duti}/bin/duti" -s com.colliderli.iina "${ext}" all 2>/dev/null || true''
    ) iinaVideoExts
  );

  # ---- packs ----------------------------------------------------------------
  # A pack file is data — `{ haus.roster = { … }; }` and nothing else — so this
  # room can import one and lower it, which is nearly what `haus.lib.pack` does
  # for a third party's file. The priority is applied PER LEAF, and that detail
  # is the whole trick: `mkDefault` on the whole `roster` attrset attaches to the
  # entire definition, so one normal-priority field in a host would outrank the
  # pack's WHOLE roster — measured at three of four apps silently not installed.
  # Below the option leaf you set a priority; at or above it you replace a value.
  #
  # "Nearly", and the difference is deliberate: `lib.pack` uses `packPriority`
  # (500) while this stays at `mkDefault` (1000), so a DESKTOP beats the
  # collections this room ships and loses to a pack the consumer imported by
  # hand. The switch above is desktop-safe, so a desktop may be what turned this
  # on — and its own explicit `roster` line should then win. Don't unify the two
  # without reading `packPriority` in flake.nix.
  packEntries =
    path:
    lib.mapAttrs (_: entry: lib.mapAttrs (_: value: lib.mkDefault value) entry) (
      (import path).haus.roster
    );
in
{
  # A roster entry, not `home.packages`: it shows up in `this-machine.md`, a host
  # can retune it by app id, and naming the same app from two sources trips the
  # roster's one-source assertion instead of quietly installing IINA twice (which
  # is exactly what happened for months — see modules/roster).
  haus.roster = lib.mkMerge [
    (lib.mkIf videoCfg.enable {
      iina = {
        name = lib.mkDefault "IINA";
        package = lib.mkDefault pkgs.iina;
      };
    })
    (lib.mkIf cfg.packs.writing.enable (packEntries ./packs/writing.nix))
  ];

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
      # registration is exactly as perishable as the binding — terminal
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
