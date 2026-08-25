# Trill — the notification compositor, installed through Nix (the `trill` flake
# input's overlay puts `pkgs.trill` in scope). The flake wraps trill's CI-built,
# Developer-ID-signed, notarized release .app (macOS 26 blocks a from-source Nix
# build — see the trill repo), so `pkgs.trill` is that exact bundle in the store.
#
# THE PATH IS THE POINT. trill is a normal background app, not a launchd daemon:
# it is LSUIElement, it registers itself as a login item through SMAppService,
# and it needs to exist somewhere Spotlight and LaunchServices can find it. A
# Nix store path is not that place, and for trill the reason is sharper than it
# was for the shelf: `trill doctor`, the System Mirror provider and the
# "Silence Native Banners" helper all rest on a **Full Disk Access** grant, and
# macOS keys a TCC grant per app *path* plus signing identity. A store path
# changes on every version bump, so the grant would drop on exactly the rebuild
# that installed the fix. So the bundle is copied to a FIXED
# /Applications/Trill.app on activation — the path a cask or a drag-install
# would have used, so an existing grant carries over — and re-copied only when
# the store path actually changes. No re-sign dance: the release .app is already
# Developer-ID signed, `ditto` preserves the signature and the stapled
# notarization ticket, and a grant keyed to that stable identity plus this path
# survives every rebuild.
#
# THIS ROOM PUTS NOTHING ON PATH, and that is deliberate rather than an
# omission. ../core/trill.sh already answers `trill` on every haus machine, and
# it is a WRAPPER, not a symlink: whether Trill.app exists is a runtime fact, and
# a symlink into a bundle that isn't there is a `trill` that `command -v` finds
# and every call fails on. The shelf's `perch-cli-link` is the right shape for
# perch precisely because nothing else in haus ships a `perch`; here a second
# `bin/trill` in systemPackages would be a build-time file collision with the
# wrapper, not a redundancy. The wrapper's second candidate is
# /Applications/Trill.app — which is what this room puts there.
#
# Like the shelf, having no launch agent has a consequence the copy must pay
# for: NOTHING but a login (or a person) ever starts trill, so a rebuild that
# swaps the bundle under a running compositor leaves the machine with no banners
# for the rest of the session — and on this desktop that is louder than a
# missing shelf, because `haus-notify` is how every room speaks. So the
# activation stops trill on purpose before the swap and puts it back after, but
# only if it was up: a deliberately-quit trill is not resurrected by a rebuild.
#
# NOT THEMED FROM HERE, and not yet configured from here either. trill's own
# rule is that ~/.config/trill/config.json is the source of truth for every
# app-level switch and that it REFUSES to move a toggle when the file is a
# symlink into the Nix store (it says so in Settings rather than moving a switch
# a rebuild would revert). Writing that file is therefore a real design decision
# about which keys haus owns and which stay the user's, not a copy of the
# shelf's theme drop — so it is deliberately not in this room's first version.
# `~/.config/trill/rules.json` stays entirely the user's: it is the dial for
# every `haus-notify --source`, and a second dial in front of it would be worse
# (../../AGENTS.md's rule).
{
  config,
  lib,
  pkgs,
  username,
  ...
}:

lib.mkIf config.haus.trill.enable {
  # The bundle is copied to a fixed /Applications path by this module's
  # activation step (see the header on why the path must be fixed), so
  # `installedBy` is the only honest source field.
  haus.roster.trill = {
    name = lib.mkDefault "Trill";
    installedBy = lib.mkDefault "haus.trill";
  };

  system.activationScripts.postActivation.text = ''
    # --- trill: install the notarized app at a fixed /Applications path -------
    trillStore="${pkgs.trill}/Applications/Trill.app"
    trillDest="/Applications/Trill.app"
    trillMarker="/Library/Application Support/haus/trill.installed-from"
    trillExec="$trillDest/Contents/MacOS/Trill"
    trillUid="$(/usr/bin/id -u -- ${username})"
    if [ "$(/bin/cat "$trillMarker" 2>/dev/null)" != "${pkgs.trill}" ]; then
      echo "trill: installing ${pkgs.trill} → $trillDest" >&2

      # Same two reasons the shelf has, decided BEFORE the swap:
      #
      #   * trill is up right now — the swap below deletes the bundle out from
      #     under it and it exits, and NOTHING starts it again (no launch agent;
      #     it registers itself as a login item), so the machine draws no
      #     banners for the rest of the session. Every room on this desktop
      #     speaks through `haus-notify`, which would silently fall back to
      #     Apple's banner — so the symptom is not "trill is gone", it is
      #     "my rules.json stopped working";
      #   * there is no marker at all — this room's first install, and an app
      #     that has never been launched has never registered itself as a login
      #     item either, so without this it would not come up at the next login
      #     and trill would simply never start.
      #
      # A trill the user quit on purpose, on a machine that already has it,
      # matches neither and stays quit.
      trillRelaunch=""
      [ -e "$trillMarker" ] || trillRelaunch=1
      if /usr/bin/pgrep -qU "$trillUid" -f "^$trillExec$"; then
        trillRelaunch=1
        # Stop it on purpose instead of letting the rm pull the rug: a process
        # whose bundle has been deleted can still be alive when we relaunch, and
        # `open` would then just re-activate that stale instance — running the
        # OLD binary out of a bundle that no longer exists — instead of starting
        # the new build. SIGTERM rather than an AppleScript `quit` because
        # sending an Apple event from activation would want an Automation
        # consent dialog, and activation is the one place that must never block
        # on one.
        #
        # ⚠️ The pattern is anchored on the APP executable, and it has to stay
        # that way. `Contents/MacOS/Trill` is also the `trill` CLI — every
        # `haus-notify`, every `holt notify` from an agent pane, every
        # `trill ask` blocking on a pill is that same binary — so an unanchored
        # `pkill -f trill` would kill the caller's own short-lived CLI processes
        # mid-call, and `trill ask` answers exit 75 when its socket dies.
        # `^…$` matches only the argv[0]-alone daemon launch. `-U` so this is
        # one login session's trill, not every trill on a fast-user-switched
        # machine — the relaunch below can only put ONE user's back.
        /usr/bin/pkill -U "$trillUid" -f "^$trillExec$" || true
        trillStopped=""
        for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
          /usr/bin/pgrep -qU "$trillUid" -f "^$trillExec$" || { trillStopped=1; break; }
          /bin/sleep 0.2
        done
        # Three seconds is a long time for a UIElement app to acknowledge a
        # TERM. If it hasn't, the relaunch would find a survivor and do nothing,
        # so make sure there is nothing to find.
        if [ -z "$trillStopped" ]; then
          /usr/bin/pkill -9 -U "$trillUid" -f "^$trillExec$" || true
          /bin/sleep 0.5
        fi
      fi

      if /usr/bin/ditto "$trillStore" "$trillDest.new"; then
        /bin/rm -rf "$trillDest"
        /bin/mv "$trillDest.new" "$trillDest"
        /bin/mkdir -p "$(/usr/bin/dirname "$trillMarker")"
        /usr/bin/printf '%s' "${pkgs.trill}" > "$trillMarker"
      else
        echo "trill: ditto failed; leaving any existing $trillDest in place" >&2
        /bin/rm -rf "$trillDest.new"
      fi

      # Start it again in the user's GUI session — activation runs as root, and
      # root's session is not the one with a menu bar in it (the same reason
      # ../core's activateSettings call goes through asuser). `-g` so a rebuild
      # never steals focus, `timeout` because `open` waits on LaunchServices and
      # this is the one unbounded call in the block, and `open` rather than
      # exec'ing the binary because the TCC identity has to be the app's — which
      # is the entire point of this room.
      #
      # The success line is printed from what actually happened rather than from
      # having tried. Unlike the shelf, the probe here is honest about more than
      # a process: trill's socket is what `haus-notify` needs, so `trill ping`
      # answers the question a rebuild actually cares about — "can this machine
      # draw a banner again" — and `open -g` not promising a window costs
      # nothing, because trill has none.
      if [ -n "$trillRelaunch" ] && [ -x "$trillExec" ]; then
        ${pkgs.coreutils}/bin/timeout 20 launchctl asuser "$trillUid" \
          sudo --user=${username} -- /usr/bin/open -g "$trillDest" || true
        trillUp=""
        for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
          if launchctl asuser "$trillUid" sudo --user=${username} -- \
               "$trillExec" ping >/dev/null 2>&1; then trillUp=1; break; fi
          /bin/sleep 0.2
        done
        if [ -n "$trillUp" ]; then
          echo "trill: compositor back up (its socket answers)" >&2
        else
          echo "warning: trill: the compositor did not answer on its socket. It will return at your next login; until then haus-notify falls back to Apple's banner and nothing else is affected." >&2
        fi
      fi
    fi
  '';
}
