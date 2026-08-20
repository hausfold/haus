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
# A LANE (`holt.<repo>.<lane>`) is found by its window TITLE on the AeroSpace
# backend, so its window has to be spawned by `open -na --title` — the only
# spawn that forces a title the client inside cannot clobber. That is exactly
# what scripts/raise-session.sh already does for the bar's go-to, so lanes are
# handed to it rather than reimplemented here, and it picks the backend.
#
# A PLAIN window (`term.<n>`) must NOT get a forced title: its title is whatever
# the program in it emits, which is what a window switcher reads, and its join
# is the `window=` label launch.sh stamps on every attach. So it is spawned the
# way every other plain window is — Ghostty's own AppleScript API, running
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
      /^holt\./ { lanes[++l] = $0 }
      END {
        for (i = 1; i <= max; i++) if (i in terms) print terms[i]
        for (i = 1; i <= l; i++) print lanes[i]
      }'
)

[ -n "$parked" ] || exit 0

opened=0
while IFS= read -r sess; do
  [ -n "$sess" ] || continue
  [ "$sess" = "$except" ] && continue

  case "$sess" in
    holt.*)
      # --or-open: the session has no window by definition here, so this is
      # always the open path. raise-session.sh owns the forced title and the
      # backend split.
      "$HOME/.config/haus/term/raise-session.sh" --or-open "$sess" >/dev/null 2>&1
      ;;
    term.*)
      # launch.sh reads HAUS_ZMX_ATTACH and skips claiming a new name. The
      # working directory is the session's own — zmx restores it on attach —
      # so nothing is passed for it here; `initial working directory` would
      # only decide where the attach itself ran from.
      osascript - "$HOME/.config/haus/term/launch.sh" "HAUS_ZMX_ATTACH=$sess" <<'OSA' >/dev/null 2>&1
on run argv
    tell application "Ghostty"
        new window with configuration {command:item 1 of argv, environment variables:{item 2 of argv}}
    end tell
end run
OSA
      ;;
    *)
      # A session you made yourself with `zmx attach`. Not ours to reopen: it
      # was never a window of this rice's, and guessing would put a window on
      # someone's long-running build.
      continue
      ;;
  esac

  opened=$((opened + 1))
  # Ghostty serialises `new window` badly when they arrive faster than it can
  # map them — two windows in the same tick can both come back with the same
  # focused id, which is what launch.sh's tile poll and its label stamp both
  # key on. A beat between spawns is cheaper than either of those resolving to
  # the wrong window.
  sleep 0.35
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
  sleep 0.5
  "$HOME/.config/aerospace/resort-windows.sh" >/dev/null 2>&1
fi

exit 0
