#!/bin/bash
# restore-windows.sh — "put my terminal back the way I left it."
#
# One window per PARKED session: every zmx session with `clients=0`, which is
# exactly the set a ⌘W, a ⌘Q or a Ghostty crash leaves behind. The sessions
# never stopped running — that is the whole point of zmx — so this opens
# windows onto them rather than starting anything.
#
# Two callers, and they are the same act at two moments:
#
#   scripts/launch.sh   automatically, for the FIRST window of a Ghostty (see
#                       its `restoring the desk` block for how first is known).
#                       That window adopts one session itself and passes it as
#                       --except, so the desk comes back with no spare window
#                       on top of it.
#   the palette         `Restore Terminal Windows`, for when you want the rest
#                       back later — after closing a few by hand, or on a
#                       machine where the automatic half is switched off
#                       (haus.terminal.restoreWindows).
#
# Running it twice is safe and does nothing the second time: a session that has
# a window is attached, and attached sessions are not in the list.
#
# ── the two kinds of session open differently ────────────────────────────────
# A LANE (`scruff.<repo>.<lane>`) is found by its window TITLE on the AeroSpace
# backend, so its window has to be spawned by `open -na --title` — the only
# spawn that forces a title the client inside cannot clobber. That is exactly
# what scripts/raise-session.sh already does for the bar's go-to, so lanes are
# handed to it rather than reimplemented here, and it picks the backend.
#
# A PLAIN window (`term.<n>`) must NOT get a forced title: its title is whatever
# the program in it emits, which is what a window switcher reads, and its join
# is the `window=` label launch.sh stamps on every attach. So it is spawned the
# way every other plain window is — scripts/new-window.sh, running
# scripts/launch.sh, with the session named in the environment.
#
# ── placement ────────────────────────────────────────────────────────────────
# Nothing here moves a window. A lane's window tiles itself onto `T/<repo>` from
# its own title, a plain window tiles itself onto `T`, and the resort at the end
# is what heals the lanes that raise-session.sh opened before AeroSpace had seen
# their titles. This does mean a plain window you had moved onto some other
# workspace by hand comes back on `T`: a `term.<n>` carries no record of where
# it was, and inventing one would mean a writer on every workspace change.
set -u

export PATH="/etc/profiles/per-user/${USER:-$(id -un)}/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/usr/bin:/bin${PATH:+:$PATH}"

except=""
if [ "${1:-}" = "--except" ]; then
  except="${2:-}"
  shift 2
fi

command -v zmx >/dev/null 2>&1 || exit 0

# ── one restore at a time ────────────────────────────────────────────────────
# Two of these running at once would open every parked session twice and land
# two clients on each. It happens two ways: a double Dock click gives Ghostty
# two windows that both look like the first (launch.sh cannot know it is about
# to stop being the only client until `zmx attach` lands, which is after it has
# to decide), and the palette row can be pressed while an automatic restore is
# still fanning out.
#
# So a mkdir marker, held for the whole fan-out rather than for the moment of
# deciding. launch.sh takes it BEFORE it adopts a session — that decision is
# half of the same act — and hands the path down; the trap here is what releases
# it either way, so a fan-out that dies still frees the next one.
lock="${HAUS_RESTORE_LOCK:-}"
if [ -z "$lock" ]; then
  lock="${TMPDIR:-/tmp}/haus-term-restoring"
  if ! /bin/mkdir "$lock" 2>/dev/null; then
    # Held, or left behind by something killed mid-fan-out. Two minutes is far
    # past the slowest real restore (a settle is capped at 3 s per window), so a
    # marker older than that is debris rather than a peer.
    if [ -n "$(find "$lock" -maxdepth 0 -mmin +2 2>/dev/null)" ]; then
      /bin/rmdir "$lock" 2>/dev/null
      /bin/mkdir "$lock" 2>/dev/null || exit 0
    else
      exit 0
    fi
  fi
fi
trap '/bin/rmdir "$lock" 2>/dev/null' EXIT

# Parked sessions, in a stable order: `term.<n>` first and numerically, so the
# desk comes back in the order it was built, then the lanes by name. `sort -n`
# on the number alone, because `sort` would otherwise put term.10 before term.2.
parked=$(
  zmx ls 2>/dev/null | awk -F'\t' '
    {
      name = ""; clients = ""
      for (i = 1; i <= NF; i++) {
        p = index($i, "=")
        if (p == 0) continue
        k = substr($i, 1, p - 1); gsub(/^[ \t]+|[ \t]+$/, "", k)
        # zmx glues its "you are here" marker onto the first key of the row you
        # are attached to; strip anything before the key proper.
        sub(/^[^A-Za-z_]*/, "", k)
        if (k == "name")    name    = substr($i, p + 1)
        if (k == "clients") clients = substr($i, p + 1)
      }
      # An absent clients field is not "attached" — treat it as parked, since
      # the failure we care about is leaving a window unopened.
      if (name != "" && (clients == "" || clients == "0")) print name
    }' | awk '
      /^term\./ { n = substr($0, 6) + 0; terms[n] = $0; if (n > max) max = n; next }
      /^scruff\./ { lanes[++l] = $0 }
      END {
        for (i = 1; i <= max; i++) if (i in terms) print terms[i]
        for (i = 1; i <= l; i++) print lanes[i]
      }'
)

[ -n "$parked" ] || exit 0

# One field of one session, out of `zmx ls` — `zmx get` returns labels only, so
# `clients` (which zmx keeps itself) is not reachable through it.
field() {
  zmx ls 2>/dev/null | awk -F'\t' -v want="$1" -v key="$2" '
    {
      name = ""; val = ""
      for (i = 1; i <= NF; i++) {
        p = index($i, "=")
        if (p == 0) continue
        k = substr($i, 1, p - 1); gsub(/^[ \t]+|[ \t]+$/, "", k)
        sub(/^[^A-Za-z_]*/, "", k)
        if (k == "name") name = substr($i, p + 1)
        else if (k == key) val = substr($i, p + 1)
      }
      if (name == want) { print val; exit }
    }'
}

# Wait for a spawned window to have finished IDENTIFYING itself, before letting
# the next one open. This is the whole reason the fan-out is serial.
#
# A plain window works out which window it is by asking the window layer what
# has FOCUS (launch.sh does, in a backgrounded subshell) and stamps the answer
# onto its session as the `window=` / `gwindow=` label. Two windows mapping at
# once therefore both resolve to whichever one happened to be in front, and the
# loser's label points at its neighbour — after which ⌘F searches the wrong
# scrollback, ⌘L mines the wrong URLs and the bar peeks the wrong agent, all
# silently and all durably. A fixed sleep is not a fix for that: the margin is
# ~150 ms and the quick-terminal probe alone is an unbounded Apple Event.
#
# So: `term.*` is done when it is attached AND its label has moved off the value
# it carried before the spawn — that label is written by the very subshell we
# are waiting on, which makes it the exact signal rather than a proxy for it.
# A lane on the AeroSpace backend resolves nothing (raise-session.sh
# forces the window title and the join IS the title), so attachment alone is the
# whole condition there.
settle() {
  local sess="$1" before="$2" i=0 clients label
  while [ "$i" -lt 60 ]; do
    clients="$(field "$sess" clients)"
    if [ -n "$clients" ] && [ "$clients" != 0 ]; then
      case "$sess" in
        term.*)
          label="$(field "$sess" window)"
          [ -n "$label" ] || label="$(field "$sess" gwindow)"
          # No label before and none now means a machine with neither backend
          # answering; do not hold the whole restore for it.
          [ -n "$label" ] && [ "$label" != "$before" ] && return 0
          ;;
        *) return 0 ;;
      esac
    fi
    i=$((i + 1))
    sleep 0.05
  done
  # Three seconds is far past any real spawn. Carrying on is better than
  # stopping: the remaining windows are still wanted, and the cost of being
  # wrong here is one label, not one session.
  return 0
}

opened=0
while IFS= read -r sess; do
  [ -n "$sess" ] || continue
  [ "$sess" = "$except" ] && continue

  before="$(field "$sess" window)"
  [ -n "$before" ] || before="$(field "$sess" gwindow)"

  case "$sess" in
    # Both prefixes: a parked session from before scruff 1.2.0 renamed the join
    # is restored by name, and the name it was parked under is the old one.
    scruff.*|holt.*)
      # --or-open: the session has no window by definition here, so this is
      # always the open path. raise-session.sh owns the forced title and the
      # backend split. </dev/null because this loop is reading the parked list
      # on fd 0 — anything downstream that read stdin would eat the rest of the
      # restore and stop it dead, with nothing to say why.
      "$HOME/.config/haus/term/raise-session.sh" --or-open "$sess" \
        </dev/null >/dev/null 2>&1
      ;;
    term.*)
      # new-window.sh rather than an osascript of our own, for the three things
      # it already solves and this script must not solve twice: Ghostty may not
      # be RUNNING (`quit-after-last-window-closed` is on, so "I quit Ghostty"
      # is the likeliest state anyone reaches for a restore in, and asking a
      # dead Ghostty for a window over Apple Events simply fails), a caller with
      # no Automation grant needs the `open -na` fallback rather than an error,
      # and a runtime-spawned Ghostty window floats until something tiles it.
      #
      # launch.sh reads HAUS_ZMX_ATTACH and skips claiming a new name. No --cwd:
      # the directory is the session's own and zmx restores it on attach, so
      # anything passed here would only decide where the attach itself ran.
      "$HOME/.config/haus/term/new-window.sh" \
        --env "HAUS_ZMX_ATTACH=$sess" \
        -- "$HOME/.config/haus/term/launch.sh" \
        </dev/null >/dev/null 2>&1
      ;;
    *)
      # Defensive only — the ordering pass above emits nothing else. A session
      # you made yourself with `zmx attach` is not ours to reopen: it was never
      # a window of this rice's, and guessing would put a window on someone's
      # long-running build.
      continue
      ;;
  esac

  opened=$((opened + 1))
  settle "$sess" "$before"
done <<EOF
$parked
EOF

[ "$opened" -gt 0 ] || exit 0

# Lanes that raise-session.sh opened may have landed on bare `T`: the
# `on-window-detected` rule in aerospace.toml cannot derive a workspace from a
# title, and the title arrives after the window is mapped in any case. The
# resort reads each window's title and sends it to its page — the same script
# the leader's backtick runs, and the same one AeroSpace runs at startup.
if [ -x "$HOME/.config/aerospace/resort-windows.sh" ]; then
  "$HOME/.config/aerospace/resort-windows.sh" </dev/null >/dev/null 2>&1
fi

exit 0
