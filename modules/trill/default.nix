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

let
  # Same path ../apps holds for its duti pins, and held for the same reason:
  # LaunchServices keeps its record of an app BY PATH, so a bundle replaced at
  # a fixed path has to be re-registered or `open` answers from the record of
  # the one that was deleted.
  lsregister = "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister";
in
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
    trillLock="/var/run/haus-trill-install.lock"
    if [ "$(/bin/cat "$trillMarker" 2>/dev/null)" != "${pkgs.trill}" ]; then

      # ⚠️ ONE INSTALL AT A TIME. Nothing serialises `darwin-rebuild switch`,
      # so parallel agent lanes routinely activate at the same moment — and
      # this block's shape is lethal under that. A stops trill, swaps the
      # bundle, relaunches it; B's `pkill` then lands on the instance A just
      # started, and B relaunches into a LaunchServices record for a path
      # whose bundle was replaced twice in fifteen seconds. `open` accepts,
      # starts nothing, and the rebuild ends with NO compositor. The symptom
      # is not "trill is gone" — it is "my banners stopped clearing
      # themselves", because every `trill resolve` an agent hook fires after
      # that exits 2 into the void and the fins nobody answered sit there
      # until a human clicks them. Measured on mbp 2026-08-26: killed
      # 01:17:17, relaunched, killed again 01:17:30 by the second activation,
      # then dead for three minutes until someone went looking.
      #
      # `ln -s` is the atomic create-or-fail, and the holder's pid IS the link
      # target — one syscall, so unlike ../ai's `mkdir` locks there is never a
      # moment when the lock exists but nobody owns it yet. ⚠️ That moment is
      # not theoretical: the first cut of this used `mkdir` and then wrote the
      # pid, and two waiters both read the empty lock, both deleted it and both
      # walked straight into the install — no lock at all, measured. The pid is
      # what lets a waiter tell a live holder from a dead one; /var/run only
      # clears at boot, and `set -e` means any abort in here leaves the lock.
      #
      # ⚠️ No EXIT trap to clean it up, deliberately. This snippet is
      # concatenated into one activation script with every other room's, so a
      # trap here would replace theirs — and it would fire at the END of the
      # whole rebuild, by which time the lock it deletes may belong to the NEXT
      # activation. The dead-pid reclaim below is the cleanup.
      trillLocked=""
      trillWaited=0
      while [ "$trillWaited" -lt 240 ]; do
        if /bin/ln -s "$$" "$trillLock" 2>/dev/null; then
          trillLocked=1
          break
        fi
        # Failing with nothing there is not contention, it is a path this
        # script cannot use. Say so in one line rather than spending four
        # minutes proving it and then blaming a lock nobody was holding.
        if [ ! -L "$trillLock" ] && [ ! -e "$trillLock" ]; then
          echo "warning: trill: cannot create $trillLock; installing without a lock." >&2
          break
        fi
        # The holder may finish by installing exactly what this generation
        # wants, and then there is nothing left to wait for — the re-read below
        # will see it. Without this a second lane sits through the holder's
        # whole relaunch only to learn it had no work to do.
        if [ "$(/bin/cat "$trillMarker" 2>/dev/null)" = "${pkgs.trill}" ]; then
          break
        fi
        trillHolder="$(/usr/bin/readlink "$trillLock" 2>/dev/null || true)"
        trillAlive=1
        # ⚠️ A `-z` test, not an empty `case` arm. Shell spells an empty
        # pattern as a pair of single quotes, and Nix escapes that pair inside
        # an indented string by adding a third — which reaches bash as a parse
        # error the moment activation runs. (Writing the pair in THIS comment
        # is the same trap: it ends the Nix string. Hence the words.)
        if [ -z "$trillHolder" ]; then
          trillAlive=""
        else
          case "$trillHolder" in
            *[!0-9]*) trillAlive="" ;;
            *) /bin/kill -0 "$trillHolder" 2>/dev/null || trillAlive="" ;;
          esac
        fi
        if [ -z "$trillAlive" ]; then
          # Reclaim through a rename, so there is a single winner: of two
          # waiters that both saw a dead holder only one `mv` finds a link to
          # move, and the loser loops and re-acquires normally. Deleting in
          # place would let the loser delete the winner's fresh lock.
          /bin/mv "$trillLock" "$trillLock.stale.$$" 2>/dev/null || true
          /bin/rm -f "$trillLock.stale.$$" || true
        fi
        /bin/sleep 1
        trillWaited=$(( trillWaited + 1 ))
      done
      # Four minutes is past this block's own worst case — a couple of seconds
      # for `pkill` to settle, then three relaunch attempts at 35 s each — so
      # exhausting it means something is genuinely stuck. Go ahead unlocked
      # rather than skip: activation must never leave /Applications disagreeing
      # with the generation it has just made current. Only the exhausted loop
      # says so; both breaks above explain themselves.
      if [ -z "$trillLocked" ] && [ "$trillWaited" -ge 240 ]; then
        echo "warning: trill: another activation has held $trillLock for four minutes; installing anyway." >&2
      fi

      # Read the marker again, now that nobody else is mid-swap. Two lanes
      # rebuilding the SAME trill both saw a stale marker on the way in, and
      # without this the second one takes the compositor down again to install
      # bytes that are already in place.
      if [ "$(/bin/cat "$trillMarker" 2>/dev/null)" = "${pkgs.trill}" ]; then
        echo "trill: ${pkgs.trill} was installed by another activation while this one waited" >&2
      else
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
        # never steals focus, `timeout` on everything that talks to LaunchServices
        # or to trill's socket because neither has a clock of its own, and
        # `open` rather than
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
          # ⚠️ Re-register BEFORE opening. LaunchServices keys its record of an
          # app by PATH, and the bundle at this one just changed inode, version
          # and code signature under it — so `open` can answer from the record of
          # the bundle we deleted, accept the launch, return 0 and start nothing.
          # Same ordering ../apps uses before its duti pins, and the same reason.
          ${lsregister} -f "$trillDest" 2>/dev/null || true

          # Three tries, not one. `open` returning 0 means LaunchServices took
          # the request, never that a process exists — so the socket probe is the
          # only real answer, and a probe that comes back empty deserves another
          # ask rather than a warning. 15 s per attempt because the FIRST launch
          # of a freshly-ditto'd notarized bundle re-runs Gatekeeper's check, and
          # that alone can outlast the 3 s this used to allow: the old warning
          # fired on a trill that was seconds from answering.
          trillUp=""
          for _ in 1 2 3; do
            # `open` returning 0 never proves a process exists — but non-zero
            # proves one doesn't, so don't spend a probe on it. That is the whole
            # cost of a rebuild with no Aqua session to open into (ssh, CI, a
            # lane's own VM), where `launchctl asuser` fails at once: three quick
            # failures instead of 45 s of probing a socket nobody is behind.
            if ! ${pkgs.coreutils}/bin/timeout 20 launchctl asuser "$trillUid" \
                   sudo --user=${username} -- /usr/bin/open -g "$trillDest"; then
              /bin/sleep 1
              continue
            fi
            trillProbed=0
            while [ "$trillProbed" -lt 75 ]; do
              # ⚠️ A clock on the ping too. trill's CLI reads its reply with none
              # of its own (`roundTrip`, Trill/CLI/TrillCLI.swift), so a daemon
              # that accepts the connection and then wedges — the first-launch
              # state this retry loop exists for — would block activation for
              # ever, as root, holding $trillLock.
              if ${pkgs.coreutils}/bin/timeout 5 launchctl asuser "$trillUid" \
                   sudo --user=${username} -- \
                   "$trillExec" ping >/dev/null 2>&1; then trillUp=1; break; fi
              /bin/sleep 0.2
              trillProbed=$(( trillProbed + 1 ))
            done
            if [ -n "$trillUp" ]; then break; fi
          done
          if [ -n "$trillUp" ]; then
            echo "trill: compositor back up (its socket answers)" >&2
          else
            echo "warning: trill: the compositor did not answer on its socket after three tries. Start it with \`open -g /Applications/Trill.app\`, or leave it — it returns at your next login. Until then haus-notify falls back to Apple's banner and, on a machine running agent lanes, parked \`trill ask\` fins stay on screen until you click them." >&2
          fi
        fi
      fi

      if [ -n "$trillLocked" ]; then /bin/rm -f "$trillLock" || true; fi
    fi
  '';
}
