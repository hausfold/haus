#!/bin/bash
# lane-open.sh — holt's `open`/`resume` seam, backed by zmx + a Ghostty window.
#
# holt's built-in behaviour execs the client in the pane you ran it from, and
# the pane IS the lane. Here there is no pane, and three things carry a lane
# instead, all named the same:
#
#   zmx session   holt.<repo>.<lane>   the PTY the client actually runs in
#   Ghostty       --title=<same>       a window looking at that PTY
#   AeroSpace     workspace T/<repo>   a tile on that repo's own page
#
# One name across all three is the whole point. Everything the rice does to a
# lane from outside — the bar's go-to, a peek, "which window is this branch" —
# used to be a join across a zellij session id, a pane id, a checkout path and
# an AeroSpace window title, with a /tmp file per pane to glue them (see
# modules/bar/sketchybar/plugins/agents.sh). With this backend it's a string
# equality.
#
# ── why the window is not the session ────────────────────────────────────────
# A zellij pane dies with its tab, so closing one had to mean parking the work.
# A zmx session outlives every client attached to it, so ⌘W closes the WINDOW
# and the agent keeps thinking. That falls out of the design rather than being
# implemented here: this script only ever runs `zmx attach`, which creates the
# session on first call and re-attaches on every call after. `holt <name>` on a
# lane whose session is still up therefore reopens a window onto a live
# conversation instead of resuming a transcript — no client-side --continue, no
# session picker, nothing to resolve.
#
# ── the seam contract ────────────────────────────────────────────────────────
# holt hands action seams their situation as HOLT_* in the environment ONLY —
# stdin is inherited from the caller, not JSON (internal/config/config.go's
# `run`, `action == true`). The two that matter:
#
#   HOLT_COMMAND  the exact client invocation holt was about to exec, already
#                 resolved to continue-the-newest or open-the-picker. Run it;
#                 don't rebuild it, or a `holt <name> --pick` lands on the
#                 picker holt just resolved away.
#   HOLT_CHAT     the cwd the CONVERSATION lives in, which for a `holt child`
#                 lane is the PARENT's checkout, not the lane's. Getting this
#                 wrong is how a resumed child opens an empty session.
#
# Exit 0 = handled. Exit 3 = no opinion, use the built-in — which is what a
# machine without zmx wants, so it stays exactly as good as it was before.
set -u

# A hook is exec'd by holt, which may itself have been started by launchd (the
# palette's Spawn Agent) with a bare PATH. Resolve our tools the way every
# other rice script run from outside a shell does.
export PATH="/etc/profiles/per-user/${USER:-$(id -un)}/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/usr/bin:/bin${PATH:+:$PATH}"

command -v zmx >/dev/null 2>&1 || exit 3
[ -n "${HOLT_COMMAND:-}" ] || exit 3
[ -n "${HOLT_NAME:-}" ] || exit 3

chat="${HOLT_CHAT:-${HOLT_PATH:-}}"
[ -d "$chat" ] || exit 3

# ── the name ─────────────────────────────────────────────────────────────────
# NOT bare $HOLT_NAME. `holt child` names a child lane after the parent pane's
# own lane, so one agent that spawned an out-of-repo worktree owns two lanes
# with the SAME name in different repos — the exact ambiguity that forced
# agents.sh to keep a `.cwd` sibling file per pane just to tell them apart.
# Qualifying by the main checkout's basename makes the session name unique by
# construction, so nothing downstream needs a tiebreaker.
#
# HOLT_MAIN, not HOLT_REPO: the latter is a remote slug and is empty for a repo
# that has never been pushed, which is a perfectly ordinary lane.
repo="$(basename "${HOLT_MAIN:-$chat}")"
sess="holt.${repo}.${HOLT_NAME}"

# ── the launcher ─────────────────────────────────────────────────────────────
# Ghostty's `initial-command` is split shell-style, so passing an already-quoted
# `zmx attach … bash -lc '…'` through `open --args` means three levels of
# quoting over a $HOLT_COMMAND we don't control. A throwaway script is one
# level, and deletes itself the moment it has run.
run_dir="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/haus-lanes"
mkdir -p "$run_dir" 2>/dev/null || exit 3
launcher="$(mktemp "$run_dir/open.XXXXXX")" || exit 3

# ── holding a failed lane open ───────────────────────────────────────────────
# A zellij lane that dies leaves its pane sitting there with the error in it. A
# zmx lane's window is the client's own process tree: the client exits, the
# session ends, `zmx attach` returns, and Ghostty closes the window it was the
# initial-command of — so a one-line failure ("No conversation found to
# continue") flashes for a frame and takes the evidence with it. That is the
# single worst thing about this backend to debug, so a NON-ZERO exit holds the
# window instead of closing it, and offers a shell in the checkout the lane was
# going to open in. A clean exit still closes, which is the point of ⌘W being
# detach rather than quit.
#
# The hold clears the session's labels first, and that is load-bearing rather
# than tidy. The bar's zmx rows have no reaper — agents.sh says so in as many
# words ("a lane that dies takes its labels with it"), because a dead session
# takes its own row with it. A held session is alive, so a client that died
# mid-thought would otherwise leave `state=working` on the bar forever, and the
# agents pill would show an agent that is in fact sitting at a prompt. Clearing
# them drops the row (agents.sh skips a session with no `state`), which is the
# truth: this window is now a held error, not an agent. `zmx set .` is the same
# "." = current session idiom agents-hook.sh uses, so the hold needs no name.
held="$HOLT_COMMAND"'
rc=$?
[ "$rc" -eq 0 ] && exit 0
zmx set . state= client= label= since= >/dev/null 2>&1
printf "\n\033[1;31m▲ the lane exited %s\033[0m — window held so you can read why.\n" "$rc"
printf "  enter → close · s + enter → shell in %s\n" "$PWD"
read -r _ans || _ans=
[ "$_ans" = s ] && exec bash -l
exit "$rc"'

# ── which backend places this lane ───────────────────────────────────────────
# windows is a ROOM, and a machine can run Ghostty, zmx, holt and agents with
# no tiler at all. Everything that makes a lane a lane — the zmx session that
# outlives its window, the hold-on-error, the bar row, holt's registry — is
# already tiler-free; only PLACEMENT and the window→session JOIN ever needed
# AeroSpace, and this is the file that decides both. So it has two backends:
#
#   aerospace  the window is spawned by `open -na --title`, which forces a
#              title nothing inside can clobber, and tiles itself onto the
#              repo's own T/<repo> page. The join is that title.
#   ghostty    the window is spawned through Ghostty's own AppleScript API,
#              which RETURNS the window and its stable id, and the join is
#              that id, stamped onto the session as a `gwindow=` label. macOS
#              places the window; there are no pages to place it on.
#
# The backends are not interchangeable, and the reason is instance routing:
# `open -na` starts a SEPARATE Ghostty process per lane, and
# `tell application "Ghostty"` reaches exactly one of them (measured
# 2026-08-19: with three instances up it kept answering for one, and raising
# another window did not move it). So a forced title and an AppleScript id can
# never be read from the same place. The tiler-less machine gets the
# single-instance half — one process, every window enumerable, ids stable,
# `activate window` able to raise any of them — and pays for it in the window
# title, which is the client's own rather than `holt.<repo>.<lane>`. With a
# tiler, AeroSpace already sees every process, so the forced title wins there
# for the reason the note below gives.
#
# HAUS_WINDOW_BACKEND=aerospace|ghostty forces one, so a machine that HAS a
# tiler can feel-test the path a machine without one takes. Read the same way
# by scripts/focused-session.sh and scripts/raise-session.sh.
backend="${HAUS_WINDOW_BACKEND:-}"
if [ -z "$backend" ]; then
  if command -v aerospace >/dev/null 2>&1; then backend=aerospace; else backend=ghostty; fi
fi

# printf %q, not bash 5's ${var@Q}: /bin/bash on macOS is still 3.2, and this
# script has no guarantee about which bash holt found first.
#
# The self-tile block is lifted from zellij/launch.sh, for the reason its own
# comment gives: windows floats every ghostty window spawned at runtime, because
# an `on-window-detected` TITLE rule races window detection (the AX title lands
# after the window is mapped) and a popup tiled for a beat reflows the whole
# workspace. From inside the window that race is gone — it certainly exists, and
# it has focus, because it was just opened. So a lane tiles ITSELF onto T rather
# than adding a title rule to aerospace.toml that would lose the same race.
{
  printf '#!/bin/bash\n'
  printf 'rm -f %q\n' "$launcher"
  printf 'export PATH="/opt/homebrew/bin:$PATH"\n'
  if [ "$backend" = aerospace ]; then
    printf '(\n'
    printf '  for _ in $(seq 1 20); do\n'
    printf '    WID=$(aerospace list-windows --focused --format "%%{window-id}" 2>/dev/null)\n'
    printf '    [ -n "$WID" ] && break\n'
    printf '    sleep 0.05\n'
    printf '  done\n'
    printf '  [ -n "${WID:-}" ] || exit 0\n'
    # T/<repo>, not a single shared T: every lane of one repo tiles on its own
    # workspace page, so five agents across three repos stop fighting over one
    # tree. Workspace names may contain "/" (checked by hand against AeroSpace);
    # the pages are deliberately NOT in persistent-workspaces, so an emptied page
    # evaporates instead of accreting. Plain terminal windows stay on T.
    #
    # --focus-follows-window, because a lane you can't see is a lane you have to
    # go looking for. Without it, spawning a lane for a repo other than the one
    # the current page belongs to sent the window to T/<other-repo> and left you
    # standing on T/<this-repo>, ⌃⇥-ing through pages to find the agent you just
    # asked for. It is unconditional rather than "only when the repo differs":
    # the page a lane belongs to is not the page you spawned it from, and
    # windows floats every runtime-spawned Ghostty window onto the CURRENTLY
    # focused workspace (aerospace.toml's on-window-detected rule), so even a
    # same-repo lane is somewhere else until this line runs. The one case that
    # really is a no-op — you were already standing on T/<repo> — costs nothing,
    # because the focus it follows to is the focus that window already has.
    printf '  aerospace move-node-to-workspace --focus-follows-window --window-id "$WID" %q\n' "T/$repo"
    printf '  aerospace layout --window-id "$WID" tiling\n'
    printf ') >/dev/null 2>&1 &\n'
  fi
  printf 'cd %q || exit 1\n' "$chat"
  # `zmx attach` creates the session if it is not there and ignores the trailing
  # command if it is — so open and resume are the same call, and a resume can
  # never restart a client that is already running.
  printf 'exec zmx attach %q bash -lc %q\n' "$sess" "$held"
} >"$launcher"
chmod +x "$launcher"

# ── the window ───────────────────────────────────────────────────────────────
# Cold start, both backends. `open -a` returns as soon as LaunchServices
# accepts, so firing the spawn below in the same breath races the app's own
# launch and lands you a stray default window beside the lane. Wait for the
# process, briefly and with a ceiling — the chord always arrives from inside a
# Ghostty window and never pays this, but the palette's Spawn Agent can reach
# here on a fresh login or after ⌘Q.
#
# `pgrep -ix ghostty`, not `pgrep -x Ghostty`: the executable inside the bundle
# is lowercase (`Ghostty.app/Contents/MacOS/ghostty`), so the capitalised form
# NEVER matched — every lane took the cold-start branch, activated a running
# Ghostty and then polled for two seconds before opening its window. Fixed
# 2026-08-19; same one-word bug was in scripts/new-window.sh.
if ! pgrep -ix ghostty >/dev/null 2>&1; then
  open -a Ghostty
  for _ in $(seq 1 40); do
    pgrep -ix ghostty >/dev/null 2>&1 && break
    sleep 0.05
  done
fi

if [ "$backend" = aerospace ]; then
  # `--title` is a FORCED title in Ghostty, not a starting value: the client
  # inside can't clobber it with OSC 2. That is not a nicety, it is the whole
  # join: everything outside finds this lane by its window name
  # (`aerospace list-windows | grep '^holt\.'`), without the per-pane state files
  # the bar keeps today.
  #
  # The AppleScript spawn (`new window with configuration`, 252 ms vs 366 ms
  # here, and no second Ghostty process per lane) was tried and REJECTED for
  # THIS backend 2026-08-16: `set_surface_title` via `perform action` does set a
  # title AeroSpace reads, but it is a starting value — the next OSC 2 out of
  # the client overwrites it, and OSC 2 passes straight through zmx (measured,
  # both facts). Claude Code retitles constantly, so the machine-readable name
  # survived only until the client's first thought. The extra process is the
  # price of a title nothing inside the window can take away. (It is also what
  # makes that spawn the only option for the ghostty backend below, which has
  # no AeroSpace to read a title with and joins on an id instead.)
  #
  # `open -na` rather than `ghostty +new-window`, which refuses on macOS
  # ("not supported on this platform").
  open -na Ghostty.app --args \
    --title="$sess" \
    --initial-command="$launcher" || exit 3
  exit 0
fi

# ── the ghostty backend ──────────────────────────────────────────────────────
# One instance, so `new window with configuration` returns a window whose `id`
# is readable immediately — no polling, no race, and no second process. That id
# is the join, stamped onto the session as `gwindow=` for
# scripts/focused-session.sh (which window am I in?) and
# scripts/raise-session.sh (go to that agent).
#
# AppleScript string literals escape backslash and double-quote and nothing
# else. Same helper, same reasoning as scripts/new-window.sh.
osa_str() {
  v="$1"
  v="${v//\\/\\\\}"
  v="${v//\"/\\\"}"
  printf '"%s"' "$v"
}

gwid="$(
  /usr/bin/osascript -e "tell application \"Ghostty\"
  set w to (new window with configuration {command:$(osa_str "$launcher")})
  activate
  return id of w
end tell" 2>/dev/null
)"

if [ -z "$gwid" ]; then
  # The classic cause is the Automation (Apple Events) grant, and a chord that
  # fails silently is the one thing this script can't afford — the same
  # notification scripts/new-window.sh gives for the same failure.
  osascript -e 'display notification "couldn'"'"'t ask Ghostty for a window — check Privacy & Security → Automation." with title "haus · agent lane"' >/dev/null 2>&1
  exit 3
fi

# The session doesn't exist until `zmx attach` inside the window creates it, a
# few milliseconds from now. Retry in the background rather than ordering the
# two: the window is already open and usable, and a label that lands late costs
# nothing but a chord pressed in the first quarter-second.
(
  for _ in $(seq 1 60); do
    zmx set "$sess" "gwindow=$gwid" >/dev/null 2>&1 && break
    sleep 0.05
  done
) >/dev/null 2>&1 &

exit 0
