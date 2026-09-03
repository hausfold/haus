#!/bin/bash
# raise-session.sh — "go to the window running this zmx session."
#
# The mirror of scripts/focused-session.sh: that one asks the window layer
# which session is in front, this one asks it to put a named session in front.
# Three callers, and they had a copy each until 2026-08-19 — the bar's agents
# popup (bar/sketchybar/plugins/agents.sh, clicking an agent row), ⌘F's ⏎
# (scripts/find.sh, jumping to the window a hit came from) and the palette's
# Lanes command (launcher/commands/lanes.sh, both its rows and its transcript
# search). All three had the same joins, all three spelled AeroSpace, and none
# of them worked on a machine without a tiler.
#
#   raise-session.sh [--or-open] [--fullscreen] <session>
#
# Exit 0 = a window was raised. Exit 1 = no window has this session; it is
# detached and still running (the whole point of zmx), and what to do about
# that is the caller's call — find.sh deliberately does nothing, and the bar
# passes --or-open, which opens a fresh window onto the session instead. That
# lives here rather than in the caller because "open a window onto a session"
# is the same backend question as "raise one", and the bar has no business
# knowing the answer.
#
# Backends are lanes/lane-open.sh's, read the same way, for the same reason:
#
#   aerospace  a LANE is the `lwindow=` label lane-open.sh's self-tile block
#              stamps with the AeroSpace window id it already had to look up —
#              exact, and asked first. Failing that (a lane reopened by
#              `open_window` below, which has no id to stamp, or one whose
#              self-tile bailed) it is an exact window-title match, MINUS the
#              impostors — see below. Anything else is found through the
#              `window=` label scripts/launch.sh stamps.
#   ghostty    both kinds are found through the `gwindow=` label — Ghostty's
#              own stable window id — and raised with `activate window`, which
#              needs no tiler and no Accessibility grant.
set -u

export PATH="/etc/profiles/per-user/${USER:-$(id -un)}/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/usr/bin:/bin${PATH:+:$PATH}"

# Two flags, taken in any order, and neither is a session name: the first
# session argument ends the loop.
or_open=0
fullscreen=0
while [ $# -gt 0 ]; do
  case "${1:-}" in
    --or-open) or_open=1 ;;
    --fullscreen) fullscreen=1 ;;
    *) break ;;
  esac
  shift
done

sess="${1:-}"
[ -n "$sess" ] || exit 1
# Both backends put this name inside a quoted string (an AppleScript literal,
# or Ghostty's shell-split initial-command). zmx session names haus writes
# are `term.<n>` and `scruff.<repo>.<lane>`; anything else is a bug rather than
# an input, so refuse it instead of escaping it.
case "$sess" in
  *[!A-Za-z0-9._-]*) exit 1 ;;
esac
command -v zmx >/dev/null 2>&1 || exit 1

backend="${HAUS_WINDOW_BACKEND:-}"
if [ -z "$backend" ]; then
  if command -v aerospace >/dev/null 2>&1; then backend=aerospace; else backend=ghostty; fi
fi

# One session's label, by key, through zmx-rows.sh --get. NOT the plain sed
# it used to be: `zmx get` went from tab- to space-separated at 0.7.0, and
# the tab-splitting sed answered EMPTY for every key on that era — so the
# exact `lwindow=`/`window=` joins below silently fell through to the title
# scan for as long as nobody noticed. The reader knows both eras.
label() {
  "$HOME/.config/haus/term/zmx-rows.sh" --get "$sess" "$1"
}

# ── no window has it: open one, if the caller asked ──────────────────────────
# The session already exists (it is detached, not gone), so `zmx attach` walks
# straight back into the live conversation — this is never a restart.
open_window() {
  [ "$or_open" = 1 ] || return 1
  case "$backend" in
    aerospace)
      open -na Ghostty.app --args --title="$sess" --initial-command="zmx attach $sess"
      # This spawn never learns the AeroSpace id of the window it just made —
      # `open -na` returns as soon as LaunchServices accepts — so the
      # `lwindow=` label lanes/lane-open.sh stamps is now WRONG rather than
      # merely absent: it names the window that used to hold this session.
      # Clear it, and the title join below carries this lane exactly as well
      # as it did before that label existed. Leaving a dead id there would
      # hand this session to whatever window AeroSpace next gives that number
      # to, which is the impostor bug over again with the sides swapped.
      zmx set "$sess" "lwindow=" >/dev/null 2>&1
      ;;
    ghostty)
      # Cold start, and it is REACHABLE here rather than theoretical: ⌘W closes
      # a window and leaves the zmx session running, so quitting Ghostty with an
      # agent mid-thought is exactly the state the bar's agent row lands in. It
      # arrives through the cold-Ghostty guard on the main `ghostty)` arm below
      # rather than by itself — that guard is what makes this the ONE place the
      # cold start is paid for, and reading it is how this block came to exist.
      # Asking a not-yet-running Ghostty for a window over Apple Events fails
      # (scripts/new-window.sh's note): the `tell` does launch the app, but the
      # `new window` sent before it is ready comes back empty, and empty here is
      # a `return 1` the caller reports as nothing happening at all.
      #
      # `-g`, unlike the pre-warm in scripts/new-window.sh, because this branch
      # asks for its own window a line later and a foreground warm-up would
      # leave a stray plain one beside it. What backs that: lanes/lane-open.sh's
      # pre-warm already ships this exact call for every background lane
      # (`open $warm_bg -a Ghostty`), and its `why not open -g` note measures a
      # backgrounded Ghostty coming up windowless — though that measurement is
      # of `open -na -g … --args`, not of this shape, so it is inherited rather
      # than proven here. If a stray window ever does appear beside a raised
      # agent, this flag is the first thing to suspect.
      #
      # The poll body is pinned by test/ghostty-prewarm.bats, which is also
      # where the `-ix ghostty` spelling is stated once for all three sites.
      if ! pgrep -ix ghostty >/dev/null 2>&1; then
        open -g -a Ghostty
        for _ in $(seq 1 40); do
          pgrep -ix ghostty >/dev/null 2>&1 && break
          sleep 0.05
        done
      fi
      # Same spawn lanes/lane-open.sh uses on this backend, and the same
      # `gwindow=` stamp, so the window it opens is one this script can raise
      # next time. No retry loop around the `zmx set`: unlike a fresh lane,
      # the session is already there.
      gwid=$(
        /usr/bin/osascript 2>/dev/null <<APPLESCRIPT
tell application "Ghostty"
  set w to (new window with configuration {command:"zmx attach $sess"})
  activate
  return id of w
end tell
APPLESCRIPT
      )
      [ -n "$gwid" ] || return 1
      zmx set "$sess" "gwindow=$gwid" >/dev/null 2>&1
      ;;
    *)
      return 1
      ;;
  esac
  return 0
}

# ── --fullscreen: land ON the window, not on the page it sits in ─────────────
# The flag is for a caller answering a lane that BLOCKED — clicking its trill
# fin, which arrives here through lanes/lane-focus.sh. A plain raise onto a page
# holding five tiled windows says which PAGE wanted you and leaves the window
# itself to be found by its solid cursor.
#
# The take is not spelled here. Fullscreen is a MODE with three rules attached
# (a solo-window guard, `on` rather than the bare toggle, a bar poke only when
# the state changed) and those rules are the WINDOWS room's — one copy, in the
# room that owns <mod>f, so this one is a call rather than a second spelling to
# drift. It is handed the window ID we just raised, which is what lets it count
# that window's own page instead of whatever is in front.
#
# AeroSpace only, by construction: the ghostty backend has no tiler, so its
# raise already puts the window in front of everything with nothing to hunt
# through, and the script below is not on a machine without the windows room.
#
# The other three callers of this script deliberately DON'T pass it. The bar's
# agent rows, ⌘F's ⏎ and the Lanes palette are you going to a window you named;
# the fin is a window asking for you, and only that one earns the screen.
fullscreen_take="$HOME/.config/aerospace/fullscreen-toggle.sh"

case "$backend" in
  aerospace)
    # A window WEARING a lane's title is not necessarily that lane's window.
    # Ghostty's `--title` is INSTANCE-WIDE configuration rather than a property
    # of the one window it was spawned for, so every window opened later inside
    # a lane's Ghostty process is BORN wearing that lane's name. Raising one of
    # those puts a plain shell in front of someone looking for their agent.
    #
    # scripts/new-window.sh stopped making them — it asks the responder's front
    # window title first and takes `open -na` rather than land in an instance
    # whose title this room forced. This subtraction still stands: Ghostty's own
    # New Window menu item lands wherever it likes, and every window opened
    # before that refusal keeps its name for life.
    #
    # The discriminator was already in the room: a plain window carries its own
    # `window=` label (launch.sh stamps it on every attach) and a real lane
    # never does, because a lane's session is created by `zmx attach` inside the
    # window rather than by launch.sh. So an id some session has CLAIMED is
    # exactly an impostor, and skipping those leaves the real lane.
    #
    # SPACE-separated, and never a newline: `awk -v` is not a variable
    # assignment, it is a piece of awk SOURCE, and macOS's one-true-awk
    # (`awk version 20200816`, /usr/bin/awk) refuses a literal newline inside a
    # string literal — `awk: newline in string`, exit 2, NOTHING on stdout.
    # This list is empty or one id most of the time, so the program parsed
    # fine and the join worked; the second plain window to earn a `window=`
    # label put a newline in it and killed the awk, silently, for every lane at
    # once. `win` came back empty, a lane has no `window=` label of its own to
    # fall back on, and the caller read that as "no window holds this session"
    # — so clicking a lane's trill banner opened a SECOND window beside the one
    # it was meant to raise, and ⌘F's ⏎ and the bar's agent rows did their own
    # version of the same. Ids are digits by construction, so a space is a safe
    # join, and `split(c, a, " ")` is awk's default-FS split: runs of
    # whitespace, leading and trailing ignored. (MEASURED 2026-08-26.)
    # ── the exact join ──────────────────────────────────────────────────
    # lanes/lane-open.sh's self-tile block stamps the AeroSpace window id it
    # looked up as `lwindow=`, which makes a lane answerable by id the way a
    # plain window always was — and answers the ceiling the title scan below
    # cannot reach on its own, an impostor with no session and so no label to
    # be subtracted by (test/raise-session-lane-join.bats says as much in its
    # "one labelled plain window" case). Checked against the live window list
    # rather than trusted: a session outlives its window (⌘W parks one), so
    # the label can name an id nobody holds — exactly as `window=` can, and
    # handled here exactly as it is below.
    #
    # It does not replace the scan. A lane reopened by `open_window` above
    # carries no id to stamp, a self-tile that bailed never wrote one, and a
    # lane from before this label existed has none, so the scan is still the
    # answer for all three.
    #
    # Resolved BEFORE the scan and applied AFTER it, which costs one listing
    # this could in principle skip. That is deliberate: the two statements
    # below are pinned BYTE FOR BYTE by that bats suite, which extracts them
    # with `sed -n '/^    claimed=/,/^        \$2 == "Ghostty"/p'` and evals
    # the result under `set -u`. Wrapping them in an `if` re-indents the awk
    # body, the extraction yields nothing, and every case in the suite fails
    # on an empty answer. A raise is a click or a ⏎, not a keystroke on the
    # typing path, so the spare `aerospace list-windows` is worth more as a
    # test that keeps working.
    lwin=""
    lw=$(label lwindow)
    [ -n "$lw" ] && lwin=$(aerospace list-windows --all --format '%{window-id}' 2>/dev/null | grep -Fx "$lw")

    claimed=$(zmx ls 2>/dev/null | tr '\t' '\n' | sed -n 's/^window=//p' | tr '\n' ' ')
    win=$(aerospace list-windows --all --format '%{window-id}|%{app-name}|%{window-title}' 2>/dev/null |
      awk -F'|' -v t="$sess" -v c="$claimed" '
        BEGIN { n = split(c, a, " "); for (i = 1; i <= n; i++) if (a[i] != "") skip[a[i]] = 1 }
        $2 == "Ghostty" && $3 == t && !($1 in skip) { print $1; exit }')
    # The id beats the title, whatever the scan turned up.
    [ -n "$lwin" ] && win="$lwin"
    if [ -z "$win" ]; then
      lw=$(label window)
      [ -n "$lw" ] && win=$(aerospace list-windows --all --format '%{window-id}' 2>/dev/null | grep -Fx "$lw")
    fi
    if [ -z "$win" ]; then
      open_window && exit 0
      exit 1
    fi
    aerospace focus --window-id "$win" >/dev/null 2>&1
    if [ "$fullscreen" = 1 ] && [ -x "$fullscreen_take" ]; then
      "$fullscreen_take" on "$win" >/dev/null 2>&1
    fi
    ;;

  ghostty)
    gw=$(label gwindow)
    # A Ghostty that is not running holds no window, so the query below has
    # nothing to find — and asking anyway is far from free: `tell application
    # "Ghostty"` LAUNCHES the app (scripts/focused-session.sh's note), and a
    # cold launch opens its own default window, since the config sets
    # `quit-after-last-window-closed` but leaves `initial-window` alone. That
    # is exactly the ⌘Q-with-a-lane-running case, and `gwindow=` is still set
    # there — nothing clears it when a window closes, unlike the aerospace
    # arm's `lwindow=` — so the stale-id path is the one that gets reached,
    # not the empty one. Without this guard it cost a stray plain window
    # beside the one open_window then opened, and made open_window's own
    # pre-warm a no-op: the launching `tell` had already started Ghostty by
    # the time its pgrep looked. Fall straight through and pay the cold start
    # once, where it is guarded.
    if [ -z "$gw" ] || ! pgrep -ix ghostty >/dev/null 2>&1; then
      open_window && exit 0
      exit 1
    fi
    # The label goes into an AppleScript string literal below. Ghostty's ids
    # are `window-<hex>`, so rather than escape a value that should never need
    # it, refuse anything that isn't shaped like one — a label is written by
    # haus, and one that isn't is a bug, not an input.
    case "$gw" in
      *[!A-Za-z0-9._-]*) exit 1 ;;
    esac
    # Iterate rather than `first window whose id is …`: a whose-clause over a
    # scripting-bridge collection is the kind of thing that quietly returns the
    # wrong object when the property is a string, and there are never more than
    # a handful of windows to walk.
    #
    # `activate window` puts that window in front of Ghostty's own stack;
    # the bare `activate` is what puts Ghostty in front of everything else.
    # Both are needed — a window raised inside a background app is still
    # behind your browser.
    out=$(
      /usr/bin/osascript 2>/dev/null <<APPLESCRIPT
tell application "Ghostty"
  repeat with w in windows
    if (id of w as text) is "$gw" then
      activate window w
      activate
      return "ok"
    end if
  end repeat
  return ""
end tell
APPLESCRIPT
    )
    if [ "$out" != ok ]; then
      open_window && exit 0
      exit 1
    fi
    ;;

  *)
    exit 1
    ;;
esac

exit 0
