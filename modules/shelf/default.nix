# Shelf — Perch, the haus notch file shelf, installed through Nix (the `perch` flake
# input's overlay puts `pkgs.perch` in scope) instead of a Homebrew cask, so it
# rides the same flake-lock chain as the rest of the family. The flake wraps
# perch's CI-built, Developer-ID-signed, notarized release .app (macOS 26 blocks a
# from-source Nix build — see the perch repo), so `pkgs.perch` is that exact
# bundle in the store.
#
# perch is a normal windowed app, not a daemon like pounce, so there's no launch
# agent — it just needs to exist somewhere Spotlight/Launchpad can find it. But a
# Nix store path is not that place: any permissions the shelf is granted are keyed
# per app *path*, and a store path changes on every version bump, which would drop
# the grant. So copy the bundle to a FIXED /Applications/Perch.app on activation
# (the same path a cask would use, so an existing grant carries over), re-copying
# only when the store path actually changes. No re-sign dance: the release .app is
# already Developer-ID signed, and a grant keyed to that stable identity + path
# survives rebuilds. `ditto` preserves the signature + notarization staple.
#
# Having no launch agent has one consequence the copy has to pay for: the app
# comes up at login (it registers itself as a login item) and NOTHING else ever
# starts it, so a rebuild that swaps the bundle under a running Perch leaves the
# machine shelf-less for the rest of the session. The activation below therefore
# stops the shelf on purpose before the swap and puts it back after — but only
# if it was up, so a deliberately-quit Perch is not resurrected by a rebuild.
#
# On by default: nix/release.nix in the perch repo pins a real notarized
# release, so `pkgs.perch` is a shipping app rather than a placeholder.
#
# Theming rides perch's RUNTIME palettes (perch's UI/Theme/RicePalette.swift):
# every rendered nebelung variant is dropped in ~/.config/perch/themes/, and
# ~/.config/perch/config.json names the dark/light pair theme.{flavor,contrast}
# selects, plus the theme.accent perch emphasises with. perch has no theme or
# accent picker of its own, so this file is the whole story for its colors.
{
  config,
  lib,
  pkgs,
  username,
  ...
}:

lib.mkIf config.haus.shelf.enable {
  # The bundle is copied to a fixed /Applications path by this module's
  # activation step (see the header on why the path must be fixed), so
  # `installedBy` is the only honest source field.
  haus.roster.perch = {
    name = lib.mkDefault "Perch";
    installedBy = lib.mkDefault "haus.shelf";
  };

  # ---- `perch` on PATH -------------------------------------------------------
  # The shelf's command line door (`perch add <path>...`) ships INSIDE the
  # bundle, as Contents/MacOS/perch-cli — it is signed and notarized as part of
  # the app, and it is named perch-cli rather than perch because a
  # Contents/MacOS/perch IS Contents/MacOS/Perch on a case-insensitive volume
  # and would replace the app's own executable. So something has to put it on
  # PATH under its real name, and that something is this room: pkgs.perch does
  # carry a bin/perch, but installing the package into a profile to reach it
  # would drag a SECOND copy of the whole .app along for one 419 KB tool, right
  # beside the /Applications copy the activation below already placed.
  #
  # The link points at that fixed path, not at the store, for the same reason
  # the activation copies there: permission grants are keyed per app path, and
  # the tool's fallback for finding the app it should launch is the bundle it
  # sits in. Pointing at /Applications also means the link survives a version
  # bump untouched — only the copy behind it changes.
  environment.systemPackages = [
    (pkgs.runCommand "perch-cli-link" { } ''
      mkdir -p $out/bin
      ln -s /Applications/Perch.app/Contents/MacOS/perch-cli $out/bin/perch
    '')
  ];

  # All home-manager wiring in ONE block — a dynamic attr key (${username}) can't
  # be merged across multiple statements. Passed as a module FUNCTION so it gets
  # the overlaid `pkgs`, the `nebelung` input, and home-manager's extended lib
  # (`lib.hm.dag` — the outer nix-darwin `lib` has no `hm`).
  home-manager.users.${username} =
    {
      lib,
      nebelung,
      pkgs,
      ...
    }:
    let
      # theme.{flavor,contrast} resolved to the selected nebelung variant, the
      # same way terminal/bar/theme/pounce do it.
      nb = import ../lib/nebelung.nix {
        inherit lib nebelung;
        theme = config.haus.theme;
      };
      followAppearance = config.haus.shelf.followSystemAppearance;

      # The palette per polarity. Perch picks between them by the macOS
      # appearance, so PINNING a flavor is expressed by writing the same variant
      # to both keys. An older perch that predates theming ignores this file.
      #
      # `accent` is a catppuccin ROLE NAME, not a hex: perch resolves it against
      # whichever half of the pair is in force, so one key is the right hue in
      # both polarities and follows a flavor change on its own. A perch that
      # predates the key ignores it and keeps accenting with its mark green.
      configJSON = pkgs.writeText "perch-config.json" (
        builtins.toJSON {
          themeDark = if followAppearance then nb.darkVariant else nb.variant;
          themeLight = if followAppearance then nb.lightVariant else nb.variant;
          accent = config.haus.theme.accent;
        }
      );

      # Every rendered variant, not just the selected one — a file SHADOWS
      # perch's compiled-in variant of the same name, so this is how a nebelung
      # palette bump reaches an installed Perch.app that hasn't been rebuilt.
      # Perch reads seven of the twenty-three roles and ignores the rest, so the
      # files go out verbatim. `or { }` on an older nebelung lock that predates
      # the output: no files, and perch falls back to its compiled-in nebelung.
      themeDrop = pkgs.runCommand "perch-theme" { } ''
        mkdir -p $out/themes
        cp ${configJSON} $out/config.json
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (
            variant: palette:
            "cp ${pkgs.writeText "perch-${variant}.json" (builtins.toJSON palette)} $out/themes/${variant}.json"
          ) (nebelung.palettes or { })
        )}
      '';
    in
    {
      # REAL FILES, not the xdg.configFile symlinks every other room here uses:
      # perch is app-sandboxed and reaches ~/.config/perch through a read-only
      # home-relative temporary exception. The sandbox resolves a symlink before
      # it checks the path, so a link into /nix/store reads as a store access and
      # is denied — the shelf would silently sit on compiled-in nebelung and the
      # rice's theme would never show. A few KB of copies keeps perch's sandbox
      # exception at exactly one directory, which is the point of the exception.
      home.activation.perchTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run /bin/mkdir -p "$HOME/.config/perch/themes"
        run /usr/bin/install -m 0644 ${themeDrop}/config.json "$HOME/.config/perch/config.json"
        # Replace the drop wholesale so a variant nebelung stopped rendering
        # doesn't linger as a stale palette a config.json could still name.
        run /bin/rm -f "$HOME"/.config/perch/themes/*.json
        for palette in ${themeDrop}/themes/*.json; do
          [ -e "$palette" ] || continue
          run /usr/bin/install -m 0644 "$palette" "$HOME/.config/perch/themes/"
        done
      '';
    };

  # ---- give the shelf the top edge back --------------------------------------
  # The Dock arms a top-screen-edge trigger for the whole duration of ANY drag
  # session — files included, not just windows despite the key's name — and
  # entering that band throws you into Mission Control. That band is precisely
  # where perch's notch catch zone lives, so overshooting the notch by a few
  # points hands the drag to the Dock and the shelf never sees a draggingEntered.
  # Perch cannot defend itself here: the Dock's edge monitor sits above every
  # window level, and intercepting it would need a CGEventTap (Accessibility
  # permission), which perch deliberately refuses to ask for.
  #
  # So the shelf only works if this is off. Not an opinion and therefore not
  # mkDefault — same footing as _HIHideMenuBar tracking bar.enable in core: it's
  # a function of running perch, and it comes back the moment perch is disabled.
  # This is the "Drag windows to top of screen to enter Mission Control" toggle
  # in System Settings ▸ Desktop & Dock; CustomUserPreferences because
  # nix-darwin's typed dock block has no option for it. The Dock restart at the
  # end of activation (core sets system.defaults.dock.*) picks it up.
  system.defaults.CustomUserPreferences."com.apple.dock".enterMissionControlByTopWindowDrag = false;

  # ---- let a capture reach the shelf while you still care about it -----------
  # Perch's watched folders are how screenshots get onto the shelf without being
  # dragged: point one at the screenshot folder and every new capture is copied
  # up on its own. macOS's floating thumbnail breaks exactly that, because it is
  # not a preview of a file that exists — the capture is HELD in the corner and
  # only written out when the thumbnail expires (~5 s) or is dismissed. So the
  # shelf catches it five seconds after the moment you took it, which is a
  # lifetime for a surface whose whole promise is "drag it somewhere now".
  #
  # `mkDefault`, unlike the Dock key above, and the difference is real: the
  # thumbnail only DELAYS the shelf, it does not defeat it (you can even drag
  # the thumbnail into the notch yourself), so this is the room stating a
  # preference rather than a requirement. The ladder from ../appearance applies
  # — a desktop (900) or a host (100) that wants the markup affordance back
  # writes `haus.screenshots.thumbnail = true;` and wins with no mkForce.
  #
  # Through core's option rather than the plist key direct, so `haus plan`, the
  # restart map and the option reference all keep describing what the machine
  # actually does.
  haus.screenshots.thumbnail = lib.mkDefault false;

  system.activationScripts.postActivation.text = ''
    # --- perch: install the notarized app at a fixed /Applications path -------
    perchStore="${pkgs.perch}/Applications/Perch.app"
    perchDest="/Applications/Perch.app"
    perchMarker="/Library/Application Support/haus/perch.installed-from"
    perchExec="$perchDest/Contents/MacOS/Perch"
    perchUid="$(/usr/bin/id -u -- ${username})"
    if [ "$(/bin/cat "$perchMarker" 2>/dev/null)" != "${pkgs.perch}" ]; then
      echo "perch: installing ${pkgs.perch} → $perchDest" >&2

      # Two reasons this block has to end with a running Perch, and they are
      # both decided BEFORE the swap:
      #
      #   * the shelf is up right now — the swap below deletes the bundle out
      #     from under it and it exits (measured), and NOTHING starts it again:
      #     perch has no launch agent, it registers itself as a login item, so
      #     the machine sits shelf-less for the rest of the session and the
      #     version bump reads as "I rebuilt and now perch won't open";
      #   * there is no marker at all — this is the room's first install, and
      #     an app that has never been launched has never registered itself as
      #     a login item either, so without this it would not come up at the
      #     next login and the shelf would simply never appear.
      #
      # A Perch the user quit on purpose, on a machine that already has it,
      # matches neither and stays quit.
      perchRelaunch=""
      [ -e "$perchMarker" ] || perchRelaunch=1
      if /usr/bin/pgrep -qU "$perchUid" -f "^$perchExec$"; then
        perchRelaunch=1
        # Stop it on purpose instead of letting the rm pull the rug: a process
        # whose bundle has been deleted can still be alive when we relaunch,
        # and `open` would then just re-activate that stale instance — running
        # the OLD binary, out of a bundle that no longer exists — instead of
        # starting the new build. SIGTERM rather than an AppleScript `quit`
        # because sending an Apple event from activation would want an
        # Automation consent dialog, and activation is the one place that must
        # never block on one. The shelf's contents survive either way: perch
        # writes its manifest to its container as items are added, not at
        # quit. `-U` so this is one login session's Perch, not every Perch on
        # a fast-user-switched machine — the relaunch below can only put ONE
        # user's back.
        /usr/bin/pkill -U "$perchUid" -f "^$perchExec$" || true
        perchStopped=""
        for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
          /usr/bin/pgrep -qU "$perchUid" -f "^$perchExec$" || { perchStopped=1; break; }
          /bin/sleep 0.2
        done
        # Three seconds is a long time for a UIElement app to acknowledge a
        # TERM. If it hasn't, the relaunch would find a survivor and do
        # nothing, so make sure there is nothing to find.
        if [ -z "$perchStopped" ]; then
          /usr/bin/pkill -9 -U "$perchUid" -f "^$perchExec$" || true
          /bin/sleep 0.5
        fi
      fi

      if /usr/bin/ditto "$perchStore" "$perchDest.new"; then
        /bin/rm -rf "$perchDest"
        /bin/mv "$perchDest.new" "$perchDest"
        /bin/mkdir -p "$(/usr/bin/dirname "$perchMarker")"
        /usr/bin/printf '%s' "${pkgs.perch}" > "$perchMarker"
      else
        echo "perch: ditto failed; leaving any existing $perchDest in place" >&2
        /bin/rm -rf "$perchDest.new"
      fi

      # Put the shelf back up, in the user's GUI session — activation runs as
      # root, and root's session is not the one with a menu bar in it (same
      # reason core's activateSettings call goes through asuser). `-g` so a
      # rebuild never steals focus from whatever is in front, `timeout` because
      # `open` waits on LaunchServices and this is the one unbounded call in
      # the block, and `open` rather than exec'ing the binary because the TCC
      # identity has to be the app's.
      #
      # The success line is printed from what actually happened rather than
      # from having tried: a rebuild that says it put the shelf back and
      # didn't is the bug this whole block exists to stop being invisible.
      if [ -n "$perchRelaunch" ] && [ -x "$perchExec" ]; then
        ${pkgs.coreutils}/bin/timeout 20 launchctl asuser "$perchUid" \
          sudo --user=${username} -- /usr/bin/open -g "$perchDest" || true
        perchUp=""
        for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
          if /usr/bin/pgrep -qU "$perchUid" -f "^$perchExec$"; then perchUp=1; break; fi
          /bin/sleep 0.2
        done
        if [ -n "$perchUp" ]; then
          echo "perch: shelf back up" >&2
        else
          echo "warning: perch: the shelf did not come back up. It will return at your next login; nothing else was affected." >&2
        fi
      fi
    fi
  '';
}
