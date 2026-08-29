#!/bin/bash
# lane-open.sh — scruff's `open`/`resume` seam, backed by zmx + a Ghostty window.
#
# scruff's built-in behaviour execs the client in the pane you ran it from, and
# the pane IS the lane. Here there is no pane, and three things carry a lane
# instead, all named the same:
#
#   zmx session   scruff.<repo>.<lane> the PTY the client actually runs in
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
# Only the FIRST of the three is a lane, though, and that is deliberate: a
# BACKGROUND lane (HAUS_LANE_BACKGROUND=1, the palette's plain-Return spawn) is
# the session alone, with no window and no tile until you go and look at it. The
# window is the view, not the lane — the note further down says why it has to be
# that way round.
#
# ── why the window is not the session ────────────────────────────────────────
# A zellij pane dies with its tab, so closing one had to mean parking the work.
# A zmx session outlives every client attached to it, so ⌘W closes the WINDOW
# and the agent keeps thinking. That falls out of the design rather than being
# implemented here: this script only ever runs `zmx attach`, which creates the
# session on first call and re-attaches on every call after. `scruff <name>` on a
# lane whose session is still up therefore reopens a window onto a live
# conversation instead of resuming a transcript — no client-side --continue, no
# session picker, nothing to resolve.
#
# ── the seam contract ────────────────────────────────────────────────────────
# scruff hands action seams their situation as SCRUFF_* in the environment ONLY —
# stdin is inherited from the caller, not JSON (internal/config/config.go's
# `run`, `action == true`). The two that matter:
#
#   SCRUFF_COMMAND  the exact client invocation scruff was about to exec, already
#                 resolved to continue-the-newest or open-the-picker. Run it;
#                 don't rebuild it, or a `scruff <name> --pick` lands on the
#                 picker scruff just resolved away.
#   SCRUFF_CHAT     the cwd the CONVERSATION lives in, which is NOT always the
#                 lane's checkout: on the RESUME of a lane with no chat of its
#                 own — a `scruff child`, or a nested spawn — it is the PARENT's
#                 checkout, because that is where the transcript this lane
#                 belongs to lives (scruff's resume.go, `chatHome`). Getting it
#                 wrong is how a resumed child opens an empty session. On
#                 `open` it is the lane's own checkout every time, `scruff spawn
#                 --prompt` included, because a first turn continues nothing.
#                 Verified against scruff 0.4.0 by dumping the hook's
#                 environment, 2026-08-23; the same narrowing is still stated
#                 flat in bar/sketchybar/plugins/agents-hook.sh. An empty
#                 SPAWNED lane is not this variable — see the scrub below.
#
# Exit 0 = handled. Exit 3 = no opinion, use the built-in — which is what a
# machine without zmx wants, so it stays exactly as good as it was before.
set -u

# A hook is exec'd by scruff, which may itself have been started by launchd (the
# palette's Spawn Agent) with a bare PATH. Resolve our tools the way every
# other rice script run from outside a shell does.
export PATH="/etc/profiles/per-user/${USER:-$(id -un)}/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/usr/bin:/bin${PATH:+:$PATH}"

# ── identities a lane must not inherit ───────────────────────────────────────
# macOS `open` forwards the caller's environment to the app it launches — the
# fact scripts/peek-run.sh already scrubs for and says so. It bites whenever
# the spawner is itself inside a zmx session, which is an agent's lane most of
# the time (`scruff spawn`, `scruff child`, `scruff new --open` from a client's
# shell) but is EVERY ordinary Ghostty window too — scripts/launch.sh makes
# each one a `term.<n>` session, so a person typing `scruff <name>` in one after
# a reboot, when no lane session is left alive and the resume is therefore
# a creation, forwards it just the same. That is why both unsets below are
# unconditional: do NOT gate them behind "is an agent spawning this". Three
# things in that environment are wrong for the lane being born:
#
#   ZMX_SESSION       the fatal one. zmx injects it into every session it
#                     hosts, and with it set `zmx attach <new> bash -lc …` does
#                     not create the session HERE: the request goes to the
#                     session it names, whose server makes the new one in ITS
#                     OWN directory, with a default login shell, and DROPS the
#                     command. Measured 2026-08-23 from a lane in haus, cwd
#                     ~/code/workshop/haus: `zmx attach probe bash -lc 'sleep
#                     45'` gave start_dir=<the LANE's checkout>, no `cmd=`, and
#                     no sleep. That is the whole of the empty-lane bug — a row
#                     with nothing in it, no client, and no window, because the
#                     attach that was supposed to BECOME the window returned
#                     instead. Only CREATION is affected; attaching to a
#                     session that already exists is fine nested (measured the
#                     same day), which is why scripts/raise-session.sh needs no
#                     such line and scripts/launch.sh guards rather than scrubs.
#   CLAUDE_CODE_*     the spawning CLIENT's conversation. agents-hook.sh
#                     addresses the bar by $ZMX_SESSION and statusline.sh keys
#                     its transcript map by it, so an heir to both would report
#                     against the pane that made it; and a fresh agent holding
#                     the spawner's session id and messaging socket is being
#                     told it IS that conversation. Only the session-identity
#                     names go: config-shaped ones (CLAUDE_CONFIG_DIR,
#                     ANTHROPIC_*, and codex/opencode's CODEX_HOME and
#                     OPENCODE_BIN_PATH) are a machine's settings and stay.
#   HAUS_DESKTOP_OK   the one whose failure mode is someone's pointer moving:
#                     a pane where the desktop guard was turned off for one
#                     unattended run would hand every lane it spawns the same
#                     exemption, on a Mac whose user is sitting at it.
#
# Named individually rather than swept by prefix: an unset that guesses is one
# that silently takes a variable the next client needs.
#
# The scrub is HERE, in the hook process, and not only in the launcher, because
# `open -a Ghostty` below leaks the same environment into the APPLICATION on a
# cold start — and every window that instance opens afterwards (⌘N's
# scripts/new-window.sh, restore-windows.sh, this file's own ghostty backend)
# would inherit ZMX_SESSION and trip scripts/launch.sh's nested guard, so it
# would get a bare `zsh -l` with no session at all: ⌘F, ⌘L, peek, restore and
# the bar's rows quietly dead for the life of that Ghostty. Nothing in this
# script reads any of these, so unsetting them up front costs nothing.
leaked="ZMX_SESSION
CLAUDECODE CLAUDE_CODE_SESSION_ID CLAUDE_CODE_HOST_SESSION_ID
CLAUDE_CODE_CHILD_SESSION CLAUDE_CODE_MESSAGING_SOCKET
CLAUDE_CODE_BRIDGE_SESSION_ID CLAUDE_CODE_ENTRYPOINT CLAUDE_PID
HAUS_DESKTOP_OK"
# shellcheck disable=SC2086 # deliberate word split: one name per unset argument
unset $leaked

command -v zmx >/dev/null 2>&1 || exit 3
[ -n "${SCRUFF_COMMAND:-}" ] || exit 3
[ -n "${SCRUFF_NAME:-}" ] || exit 3

chat="${SCRUFF_CHAT:-${SCRUFF_PATH:-}}"
[ -d "$chat" ] || exit 3

# ── the name ─────────────────────────────────────────────────────────────────
# NOT bare $SCRUFF_NAME. `scruff child` names a child lane after the parent pane's
# own lane, so one agent that spawned an out-of-repo worktree owns two lanes
# with the SAME name in different repos — the exact ambiguity that forced
# agents.sh to keep a `.cwd` sibling file per pane just to tell them apart.
# Qualifying by the main checkout's basename makes the session name unique by
# construction, so nothing downstream needs a tiebreaker.
#
# SCRUFF_MAIN, not SCRUFF_REPO: the latter is a remote slug and is empty for a repo
# that has never been pushed, which is a perfectly ordinary lane.
repo="$(basename "${SCRUFF_MAIN:-$chat}")"
# ⚠️ WRITE ONE SPELLING, READ TWO. This prefix was `holt.` through the 1.1.x
# era and moved with scruff 1.2.0's fin key (its docs/rename.md §8.6). Every
# READER in this room matches `scruff.*|holt.*`, because a Ghostty window
# carries the title it was born with until it is closed and a fin on trill's
# ledge can only be resolved by the key that put it up — so the lanes open at
# the rebuild that shipped this keep working instead of going quiet. The read
# arm is dated: it comes out with scruff's, at 1.3.0.
sess="scruff.${repo}.${SCRUFF_NAME}"

# ── the launcher ─────────────────────────────────────────────────────────────
# Ghostty's `initial-command` is split shell-style, so passing an already-quoted
# `zmx attach … bash -lc '…'` through `open --args` means three levels of
# quoting over a $SCRUFF_COMMAND we don't control. A throwaway script is one
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
held="$SCRUFF_COMMAND"'
rc=$?
[ "$rc" -eq 0 ] && exit 0
zmx set . state= client= label= since= >/dev/null 2>&1
printf "\n\033[1;31m▲ the lane exited %s\033[0m — held so you can read why.\n" "$rc"
printf "  enter → close · s + enter → shell in %s\n" "$PWD"
read -r _ans || _ans=
[ "$_ans" = s ] && exec bash -l
exit "$rc"'

# ── which backend places this lane ───────────────────────────────────────────
# windows is a ROOM, and a machine can run Ghostty, zmx, scruff and agents with
# no tiler at all. Everything that makes a lane a lane — the zmx session that
# outlives its window, the hold-on-error, the bar row, scruff's registry — is
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
# title, which is the client's own rather than `scruff.<repo>.<lane>`. With a
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

# ── a lane that does not take the screen ─────────────────────────────────────
# HAUS_LANE_BACKGROUND=1 opens the lane without you seeing or feeling it, and
# the way it does that is by opening NO WINDOW AT ALL. The lane is its zmx
# session: the client comes up in a detached PTY, on its prompt, in the same
# millisecond it would have otherwise — and a window is born the first time you
# go and look at it, placed properly on T/<repo> by this script's own foreground
# path. Three doors, all of them ending at `resume` → here: clicking the lane's
# trill fin runs `scruff focus` → lane-focus.sh, which finds no window and defers;
# the bar's agents pill and the Lanes palette each try a raise first and then ask
# `scruff <repo>/<lane>` outright (bar/sketchybar/plugins/agents.sh,
# launcher/commands/lanes.sh).
#
# That is a change of SHAPE rather than a tuning, and what forced it is that
# every way of making a real window's birth invisible failed on a fact nothing
# in this repo owns:
#
#   `open -g -na Ghostty.app`  opens no window, ever, and never runs its
#                   initial-command (MEASURED 2026-08-23): a Dock icon, no
#                   session, no client, and `scruff spawn` exiting 0 over a lane
#                   that never existed.
#   direct exec of the bundle's binary, asked for at
#   --window-position 25000,25000
#                   fixed the FOCUS half for good — LaunchServices never hears
#                   the launch, so nothing activates — but not the seeing half:
#                   a terminal still flashed over the page you were standing on
#                   (reported off a live machine 2026-08-27, feel-testing #529).
#                   The room already knew why, one file over:
#                   scripts/float-term.sh's own header says a fresh macOS
#                   instance's `--window-position/-width` flags "are silently
#                   ignored (it inherits a saved-state frame)", which is why
#                   THAT script gave up on the flags and drives the frame
#                   through AX after the window exists. A position you cannot
#                   set before the first paint cannot hide a birth, and AX
#                   arrives too late by construction.
#   an `on-window-detected` rule that moves it
#                   loses the race every window rule in this repo loses:
#                   windows/scripts/launch.sh's own note is that a window
#                   "appears on the current workspace and then
#                   on-window-detected yanks it to its assigned one".
#
# A window whose first paint you don't control cannot be made invisible from out
# here. A window that does not exist can. So the promise is kept by
# construction, and everything that was buying a quieter birth went with the
# window it was protecting: the direct exec, the clamped position, the `-g`
# pre-warm, the focus giveback and its captured previous window, and the
# notification for a lane stranded off-screen.
#
# What you give up: ⌃⇥ to T/<repo> shows a background lane only once you have
# opened it. What you get beyond the silence: the window that eventually appears
# is a LANE's window — tiled, titled, joined — rather than one born wrong in a
# corner and teleported.
#
# The palette's Spawn Agent sets it by DEFAULT — a plain Return — and clears it
# on ⌃↵, the "spawn and follow it" chord. It reaches here through `scruff spawn`
# because scruff hands a seam os.Environ(). That same inheritance is why it is
# DROPPED the instant it has been read: the variable would otherwise sit in the
# environment of everything this lane goes on to run, and a shell in there would
# have ⌘↵ and `scruff <name>` silently open in the background with nothing on
# screen to say why. Same early-drop launch.sh does for HAUS_TERM_WORKSPACE and
# HAUS_ZMX_ATTACH, for the same reason.
bg=""
case "${HAUS_LANE_BACKGROUND:-}" in 1 | true | yes) bg=1 ;; esac
unset HAUS_LANE_BACKGROUND

if [ -n "$bg" ]; then
  # ── the windowless birth ───────────────────────────────────────────────────
  # `zmx run <name> -d` is the one call in zmx's surface that CREATES a session
  # with no client attached (measured 2026-08-27): the session comes up on a
  # login shell, the argv is typed into it, and `-d` returns instead of
  # attaching. `exec` in front of it is what makes the session's root process
  # the client itself rather than a shell holding one — so this lane ends on a
  # clean exit and holds on a bad one exactly as a windowed lane does, and
  # nothing downstream can tell which way it was born. Both backends take this
  # path: there is no window, so there is nothing for either of them to place.
  #
  # A session that is ALREADY up is left strictly alone. `zmx run` TYPES, and
  # typing into a live agent's PTY hands the client a line of shell as if you
  # had pressed the keys. This is the background half of "open and resume are
  # the same act": a background resume of a lane that is still running has
  # nothing to do, because there is no window to place either. `zmx list`
  # rather than `zmx get`, whose "not found or unresponsive" answers two
  # questions with one word — and of the two mistakes available here, treating
  # a live session as absent is the one that types into it.
  #
  # It fails CLOSED. `zmx list` answering nothing because the daemon is busy or
  # the socket is unhappy is not "no session", and reading it as one is exactly
  # the mistake above — so a listing that fails takes the lane back to scruff
  # rather than typing on a hunch.
  # Every bail below takes the temp launcher with it. `mktemp` already ran, and
  # only a launcher that RUNS deletes itself — measured as a real leak, one empty
  # `open.XXXXXX` per background resume of a live lane, which is the commonest
  # path through this block.
  live="$(zmx list --short 2>/dev/null)" || { rm -f "$launcher"; exit 3; }
  if printf '%s\n' "$live" | grep -Fxq "$sess"; then
    rm -f "$launcher"
    exit 0
  fi

  {
    printf '#!/bin/bash\n'
    # The arrival marker the hook below waits on — FIRST, before anything that
    # could fail, because its whole job is to say "the launcher ran".
    printf 'touch %q\n' "$launcher.ok"
    printf 'rm -f %q\n' "$launcher"
    # Same PATH line the windowed launcher below carries, for the same reason:
    # this script is typed into a login shell whose profile is the machine's, and
    # the two `zmx` calls under it must resolve whatever that profile did.
    printf 'export PATH="/opt/homebrew/bin:$PATH"\n'
    printf 'unset %s\n' "$(printf '%s' "$leaked" | tr '\n' ' ')"
    # …and then PUT ZMX_SESSION BACK, because on this path the one in the
    # environment is the RIGHT one. `$leaked` exists to strip the SPAWNER's
    # identity, and on the windowed path the `zmx attach` that follows re-injects
    # the lane's own — there is no attach here, so the scrub would leave the
    # client with none at all, and everything that addresses a lane BY session
    # goes quiet at once: agents-hook.sh returns before writing a `state` label
    # (so the agents pill has no row for this lane — one of the three doors this
    # note promises), the lidAwake hold is never taken, statusline.sh never files
    # the session→transcript row ⌘F and the Links picker read, and the hold's own
    # `zmx set .` errors out instead of clearing the row of a lane that died.
    # Measured 2026-08-27: `zmx set .` answers `requires ZMX_SESSION`, rc 1.
    printf 'export ZMX_SESSION=%q\n' "$sess"
    # A window's scrollback starts empty; this session's starts with the line
    # zmx typed to create it (`exec bash /…/open.XXXXXX; echo
    # ZMX_TASK_COMPLETED:$?`). Screen AND scrollback, so the first thing in the
    # lane's history is the client — that history is what the bar's peek and
    # ⌘F read.
    printf 'printf "\\033[H\\033[2J\\033[3J"\n'
    # TERM, because there is no terminal emulator on the other end to set one:
    # zmx gives an unattached session `dumb` (measured), and a client that
    # believes it is on a dumb terminal draws like it. Whatever is chosen here is
    # the client's for LIFE — attaching a window later does not change a running
    # process's environment — so it has to be a value the client can RESOLVE, not
    # the one its future window will use.
    #
    # And the resolution is the whole subtlety: `xterm-ghostty` lives in the app
    # bundle's own terminfo tree, which Ghostty exports as TERMINFO to the
    # processes IT starts (modules/terminal/default.nix says so). A background
    # lane descends from the pounce daemon instead, so a bare `infocmp
    # xterm-ghostty` fails there — measured 2026-08-27: rc 1 in a clean
    # environment, rc 0 with TERMINFO pointed at the bundle. So point it, and
    # claim xterm-ghostty only when that lookup actually answers; otherwise take
    # xterm-256color, which every machine can resolve. A TERM with no terminfo
    # entry is the shape that hangs `tset` and blanks a TUI.
    printf 'gterminfo=/Applications/Ghostty.app/Contents/Resources/terminfo\n'
    printf 'if [ -d "$gterminfo" ] && TERMINFO="$gterminfo" /usr/bin/infocmp xterm-ghostty >/dev/null 2>&1; then\n'
    printf '  export TERMINFO="$gterminfo" TERM=xterm-ghostty\n'
    printf 'else\n'
    printf '  export TERM=xterm-256color\n'
    printf 'fi\n'
    printf 'unset gterminfo\n'
    # COLORTERM is the other half of the same claim, and the one that actually
    # decides whether a client draws in 24-bit colour: xterm-256color's terminfo
    # says 256, Ghostty sets COLORTERM=truecolor in every window it opens, and a
    # lane whose window will be a Ghostty is entitled to say so from the start.
    printf 'export COLORTERM=truecolor\n'
    # No `lwindow=`/`gwindow=` clear here, deliberately: a label lives IN its
    # session and dies with it, and the guard above means this launcher only ever
    # runs for a session that did not exist a moment ago. There is nothing stale
    # to clear, and a line whose premise is false is worse than no line.
    printf 'cd %q || exit 1\n' "$chat"
    printf 'exec bash -lc %q\n' "$held"
  } >"$launcher"
  chmod +x "$launcher"

  # `cd` FIRST: zmx takes a new session's start_dir from its caller's cwd, and
  # start_dir is how a session is mapped back to a checkout by the bar's agent
  # rows (bar/sketchybar/plugins/agents.sh) and the Lanes palette
  # (launcher/commands/lanes.sh). A lane whose start_dir is the palette daemon's
  # cwd is a lane neither of them can place.
  cd "$chat" || { rm -f "$launcher"; exit 3; }
  zmx run "$sess" -d exec bash "$launcher" >/dev/null 2>&1 || { rm -f "$launcher"; exit 3; }

  # ── did the launcher actually run? ────────────────────────────────────────
  # `zmx run` is two acts — create the session, then type into it — and its exit
  # status covers the request rather than either act (measured 2026-08-27: it
  # answers 0 even for a socket dir it cannot use). So the launcher signs its own
  # arrival with a marker beside itself, and this waits for THAT.
  #
  # Not for the session, which is the version of this loop that could cost you a
  # checkout: exit 3 is a REFUSAL for a spawn — `scruff spawn` opens through this
  # hook and has no built-in to fall back to — so spawn-agent.sh treats it as a
  # lane that never started and runs `scruff drop`. A client that exits 0 inside
  # this window (a `--version`, a config error that ends cleanly) takes its
  # session with it, and polling for the session would call that a failure and
  # delete the worktree and branch out from under a lane that ran perfectly.
  # The marker is written before the client is exec'd, so it cannot lie in that
  # direction.
  for _ in $(seq 1 40); do
    if [ -e "$launcher.ok" ]; then
      rm -f "$launcher.ok"
      exit 0
    fi
    sleep 0.05
  done
  # Nothing ever ran: no session, no client, nothing typed. Refusing is right
  # here — it is what lets spawn-agent.sh clean up the checkout it made.
  rm -f "$launcher" "$launcher.ok"
  exit 3
fi

# Everything below opens a WINDOW, so everything below is a FOREGROUND lane —
# the two silences a background one used to ask for (no --focus-follows-window,
# so AeroSpace doesn't walk you to T/<repo>; no AppleScript `activate`) went with
# the block above, which is why both are plain literals again rather than the
# variables they were while one caller wanted them empty.

# printf %q, not bash 5's ${var@Q}: /bin/bash on macOS is still 3.2, and this
# script has no guarantee about which bash scruff found first.
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
  # The same scrub again, inside the window. The one above cleans what THIS
  # hook forwards; this one cleans what a Ghostty instance that was ALREADY
  # running carries — the ghostty backend's AppleScript window is born inside
  # whichever instance answers, which may have been cold-started from a lane's
  # shell long before this run. Two lines, one list, no way for the window to
  # come up holding another lane's session.
  printf 'unset %s\n' "$(printf '%s' "$leaked" | tr '\n' ' ')"
  if [ "$backend" = aerospace ]; then
    printf '(\n'
    # ── which window is MINE ──────────────────────────────────────────────
    # NOT `list-windows --focused`, which is what this block asked for until
    # 2026-08-20 and is a race with no guard on it. Some window is ALWAYS
    # focused, so the poll below can never wait for the right one — it takes
    # whatever had focus at the instant it ran, and if AeroSpace has not
    # handed focus to the window being born yet, that is the window you were
    # standing in. Both halves then go wrong at once: the lane stays FLOATING
    # on whatever page windows' on-window-detected rule dropped it (a browser
    # workspace, if that is where you pressed the chord), and
    # --focus-follows-window drags an innocent window to T/<repo> and follows
    # it there. "Spawn Agent opened a Ghostty window in workspace C" and "lanes
    # open at the last random size and never tile" are the same line.
    #
    # The right join was already in the room: `open -na` gives this lane its
    # OWN Ghostty process (see the backend note above), and that process is
    # this launcher's own ancestor. So walk up to it and ask AeroSpace for the
    # windows of that pid — `--monitor all --pid`, since `--all` refuses to be
    # combined with a filter. One process, one window at this moment, no focus
    # anywhere in the question.
    #
    # If the walk somehow comes back empty, the block moves NOTHING. A lane
    # that opened floating is a nuisance you can fix with the leader's ` ;
    # a confidently mis-aimed
    # `move-node-to-workspace` is a window you did not touch leaving the page
    # you were reading it on.
    # ── the exact window→session join ──────────────────────────────────
    # A lane had none on this backend until now: its session is created by
    # the `zmx attach` at the end of this launcher rather than by
    # scripts/launch.sh, so nothing ever wrote a `window=` label and
    # scripts/focused-session.sh had to fall through to matching the window
    # TITLE. That fallback is not safe here — Ghostty's `--title` is
    # INSTANCE-WIDE configuration rather than a property of the one window it
    # was spawned for, so any window opened LATER into this lane's own
    # Ghostty process is BORN wearing this lane's name. We already hold the
    # id AeroSpace gave us; writing it down is the whole fix.
    #
    # A KEY OF ITS OWN, and that is load-bearing rather than fussy. Two other
    # scripts read `window=` as the impostor discriminator on precisely the
    # invariant "a plain window always has it, a real lane never does" —
    # windows/scripts/resort-windows.sh subtracts those ids before healing a
    # lane onto T/<repo>, and scripts/raise-session.sh before raising one.
    # Stamping `window=` here would put every real lane in both skip lists:
    # a resort would stop healing lanes, and a click on an agent banner would
    # open a SECOND window beside the one it meant to raise. `lwindow=` adds
    # an exact join without touching the invariant either of them rests on.
    #
    # It is written on EVERY exit from this block, empty on the two bails,
    # and that is the point rather than tidiness: a lane that resumes into a
    # new window after its old one was closed would otherwise keep the dead
    # id, and an id AeroSpace later hands to some other window would resolve
    # that window to this session. An empty stamp costs nothing — the title
    # join below is exactly as good as it was before this label existed.
    #
    # Same retry as the ghostty backend's `gwindow=` stamp at the foot of
    # this file, for the same reason: the session does not exist until that
    # `zmx attach` creates it, a few milliseconds from now.
    # ── a RESUME starts out mislabelled, so unlabel it first ─────────────
    # scruff wires `resume` to this same script, and a resumed lane still
    # carries the `lwindow=` of the window it had LAST time — a dead id, or
    # worse, one AeroSpace has since handed to something else. The stamp at
    # the foot of this block only lands after the pid walk, the window poll
    # (up to 2 s) and the move, and for that whole gap
    # scripts/focused-session.sh sees a label that does not match this window
    # and, on its strength, refuses the title join — so every chord in the
    # lane you just walked back into answers NOTHING and falls back to $HOME.
    # An unlabelled window is the honest state while this settles, and the
    # title join covers it exactly as it did before the label existed.
    #
    # ONE attempt, not `stamp ""`: on a resume the session is already there
    # so it lands immediately, and on a FIRST open there is nothing to clear
    # and a retry loop would sit here for three seconds before the walk below
    # even starts.
    printf '  command -v zmx >/dev/null 2>&1 && zmx set %q "lwindow=" >/dev/null 2>&1\n' "$sess"
    printf '  stamp() {\n'
    printf '    command -v zmx >/dev/null 2>&1 || return 0\n'
    printf '    for _ in $(seq 1 60); do\n'
    printf '      zmx set %q "lwindow=$1" >/dev/null 2>&1 && break\n' "$sess"
    printf '      sleep 0.05\n'
    printf '    done\n'
    printf '    return 0\n'
    printf '  }\n'
    printf '  gpid=""; p=$$\n'
    printf '  while [ -n "$p" ] && [ "$p" != 1 ]; do\n'
    printf '    case "$(ps -o comm= -p "$p" 2>/dev/null)" in\n'
    # Both spellings. The room has paid for this exact word once already:
    # `pgrep -x Ghostty` never matched the lowercase executable inside the
    # bundle, so every lane took the cold-start branch for months (see the
    # note above the pgrep below). A `comm` that reads Ghostty rather than
    # ghostty would silently disable this whole block, and its failure path is
    # a bare `exit 0` with nowhere to say so.
    printf '      *ghostty|*Ghostty) gpid="$p"; break ;;\n'
    printf '    esac\n'
    printf '    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d " ")\n'
    printf '  done\n'
    printf '  [ -n "$gpid" ] || { stamp ""; exit 0; }\n'
    # The window does not exist for AeroSpace the instant the shell inside it
    # does, so this poll is a real wait rather than the no-op the old one was.
    # ONE window, or none. A fresh `open -na` process owns exactly one window,
    # which is the whole reason the pid is a good enough join here — but that
    # is a fact about this moment, not a structural guarantee: Ghostty's
    # AppleScript API opens a window in whichever instance it reaches, so a ⌘N
    # landing in this brand-new instance during the poll below would make a
    # `head -1` a coin flip, and the loser is teleported by the
    # --focus-follows-window on the next line. Refusing an ambiguous answer is
    # the same call the block already makes when it cannot find itself at all.
    printf '  for _ in $(seq 1 40); do\n'
    printf '    mine=$(aerospace list-windows --monitor all --pid "$gpid" --format "%%{window-id}" 2>/dev/null)\n'
    printf '    [ "$(printf "%%s\\n" "$mine" | grep -c .)" = 1 ] && { WID="$mine"; break; }\n'
    printf '    sleep 0.05\n'
    printf '  done\n'
    printf '  [ -n "${WID:-}" ] || { stamp ""; exit 0; }\n'
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
    printf '  aerospace move-node-to-workspace --focus-follows-window --window-id "$WID" %q\n' \
      "T/$repo"
    printf '  aerospace layout --window-id "$WID" tiling\n'
    # LAST: the label is allowed to land late — a chord pressed in the first
    # quarter-second simply gets the title join — and the move is not.
    printf '  stamp "$WID"\n'
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
#
# No `-g` on this pre-warm any more: it only ever carried one for a background
# lane, and a background lane no longer reaches this line at all (the windowless
# block above returns long before it).
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
  # join: everything outside finds this lane by its window name, without the
  # per-pane state files the bar keeps today. Not by that name ALONE, mind — the
  # title is instance-wide config, so a plain window opened later into this same
  # process wears it too, and the readers that care (scripts/raise-session.sh,
  # windows/scripts/resort-windows.sh) subtract the ids some zmx session has
  # claimed with a `window=` label. See scripts/focused-session.sh's note.
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
  #
  # And never `-g`, however much it looks like the answer for a quiet spawn:
  # Ghostty launched into the background opens no window and never runs its
  # initial-command, so the whole lane silently fails to exist. That
  # measurement, and what a lane that must not be seen does instead — no window
  # at all — are in the background note above.
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

# `activate` is unconditional now. It was a variable so a background lane could
# drop it, and it was never enough anyway — this backend asks a RUNNING Ghostty
# for a window, and AppKit may order that window front whatever the script says.
# A lane that must not be seen opens no window on either backend; see the
# background note above.
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
  /run/current-system/sw/bin/haus-notify --source haus.lane --kind fault --symbol exclamationmark.triangle \
    --title "haus · agent lane" \
    --body "couldn't ask Ghostty for a window — check Privacy & Security → Automation." >/dev/null 2>&1
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
