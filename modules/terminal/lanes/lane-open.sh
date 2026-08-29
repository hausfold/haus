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
# All three exist for a BACKGROUND lane too (HAUS_LANE_BACKGROUND=1, the
# palette's plain-Return spawn) — what background changes is that none of it
# reaches you: the window is born unseen and tiled onto T/<repo> without focus
# ever leaving where you are standing. The note further down has the two
# measured facts that make that possible, and the shape it was for one release.
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
# ⚠️ This prefix is half of a JOIN and is not haus's to choose: it has to match
# scruff's fin key (`askKeyPrefix`, internal/commands/notify.go) byte for byte,
# because the marker file scruff writes IS this session name with the slashes
# flattened. Rename it here alone and lane-seen.sh stops joining silently.
# The 1.2.0 move of both halves shipped a release apart with a read arm on
# each side, for exactly that reason; both came out at 1.3.0.
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
# HAUS_LANE_BACKGROUND=1 opens the lane WITHOUT you seeing or feeling it — and
# it still opens a real WINDOW: named scruff.<repo>.<lane>, tiled onto T/<repo>,
# with the client on its prompt. You stay exactly where you were and go and read
# it when you are ready (⌃⇥, the Lanes palette, the agents pill). "Background"
# here is the opposite of "follow it there", NOT the opposite of "exists".
#
# This block has been the other thing once, and the round trip is worth knowing
# before touching it again:
#
#   #529  a silent birth: direct exec, so nothing activates, plus an
#         off-screen --window-position that was believed to clamp the pre-tile
#         frame to a hairline. It killed the focus loss for good. It did not
#         kill the flash, and the reason is that the position pair does
#         NOTHING — measured 2026-08-29, see the spawn below.
#   #544  no window at all until something went looking for the lane. That
#         killed the flash by construction and cost the thing this file exists
#         for: a background lane was absent from ⌃⇥ and from its own T/<repo>
#         page until it had been opened once, which is not quiet, it is
#         invisible.
#
# So the window is back, born the #529 way plus the flag pair that was actually
# measured to shrink the birth (--window-width/--window-height). What is left
# of the flash is a speck, not a terminal. If even that is too much, the honest
# next move is NOT a third position trick: it is to keep the windowless birth
# and materialise the window when you arrive on T/<repo>, where it belongs and
# where nothing has to be hidden.
#
# On the aerospace backend the silence is in how the window is BORN, two facts
# working together (both MEASURED 2026-08-27 on Ghostty 1.3.1):
#
#   no activation   the lane's Ghostty is exec'd from the app bundle directly
#                   rather than through `open -na`. LaunchServices never hears
#                   about the launch, so nothing is activated: the window
#                   opens, the initial-command runs, and focus stays exactly
#                   where it was — there is nothing to hand back.
#   a birth the size of a speck  the window is asked for at --window-width=10
#                   --window-height=4, Ghostty's smallest legal grid, so the
#                   ~200 ms before the self-tile block walks it to T/<repo>
#                   shows a box about a hundred pixels across rather than a
#                   terminal over your page. The position pair rides along and
#                   is measured NOT to work — the detail, and how both were
#                   measured, is at the spawn itself.
#
# Two more silences ride along, because each would take the screen on its own:
#
#   no --focus-follows-window  AeroSpace follows the window to T/<repo>, which
#                              is precisely what that flag is FOR normally —
#                              see the note on it below.
#   no `activate`              the ghostty backend's AppleScript spawn asks for
#                              the app front by hand.
#
# ── why not `open -g`, which is the obvious answer ───────────────────────────
# Because Ghostty launched into the background never opens a window at all.
# MEASURED 2026-08-23, from a plain shell and away from any of this:
#
#   open -g -na Ghostty.app --args --title=probe --initial-command=<script>
#
# leaves a live Ghostty process with NO window, ever, and the initial-command
# NEVER RUNS — so no zmx session, no client, no lane: a Dock icon and nothing
# else. Nothing downstream could catch it either, because `open -na` returns
# the moment LaunchServices accepts (spawn-agent.sh's own note says so), so
# `scruff spawn` exited 0 and the palette posted "… is working" over a lane that
# had never started. That was every ⌃↵ spawn until this note.
#
# The direct exec is the answer `open -g` was reaching for, and it degrades
# rather than breaks: a machine whose Ghostty.app is somewhere the lookup
# below doesn't find still spawns through a plain `open -na`, pays the old
# blink, and has the focus handed back once the lane has been moved off to
# T/<repo>. The giveback inside the launcher serves both paths — the fallback
# needs it every time, and the direct exec keeps it as a regression net that
# only fires if the lane's own instance somehow ended up holding focus.
#
# The palette's Spawn Agent sets it on ⌃↵, and it reaches here through `scruff
# spawn` because scruff hands a seam os.Environ(). That same inheritance is why
# it is DROPPED the instant it has been read, before either `open` below: the
# variable would otherwise be part of the environment of the Ghostty PROCESS
# this script starts, and every surface that instance goes on to make — the
# cold-started instance's own first window, anything new-window.sh's
# AppleScript lands there — would inherit it. A shell in one of those windows
# would then have ⌘↵ and `scruff <name>` silently open in the background with
# nothing on screen to say why. Same early-drop launch.sh does for
# HAUS_TERM_WORKSPACE and HAUS_ZMX_ATTACH, for the same reason.
bg=""
case "${HAUS_LANE_BACKGROUND:-}" in 1 | true | yes) bg=1 ;; esac
unset HAUS_LANE_BACKGROUND

# The three silences, resolved once so the branches below read as one word each.
follow="--focus-follows-window "
[ -n "$bg" ] && follow=""
activate_line="  activate"
[ -n "$bg" ] && activate_line="  -- background lane: deliberately not activating"

# `-g` survives on the COLD START alone, and only on the `open -na` fallback —
# the pre-warm's own guard, and the reasoning for both, are down at that call.
#
# Worth knowing rather than fixing here: the instance it leaves behind is
# windowless AND a live Apple Events target, so a later `tell application
# "Ghostty"` (scripts/new-window.sh, the ghostty backend below) may be answered
# by it. That routing lottery predates this line — the flag it replaced did the
# same — and what it costs is written up in scripts/focused-session.sh.
warm_bg=""
[ -n "$bg" ] && warm_bg="-g"

# ── how a background lane's window is born ───────────────────────────────────
# The direct exec from the background note above. $took is the generated
# launcher's word for which path spawned it: 1 means `open -na`, which
# activates by construction, so the giveback below must always run; empty
# means the direct exec, where focus was never taken and the giveback is only
# a regression net. The bundle is looked up rather than assumed — a machine
# that keeps Ghostty.app somewhere else simply takes the `open -na` path and
# the old blink, which is a degradation and not a failure.
ghostty_bin=""
took=1
if [ -n "$bg" ] && [ "$backend" = aerospace ]; then
  for app in /Applications/Ghostty.app "$HOME/Applications/Ghostty.app"; do
    if [ -x "$app/Contents/MacOS/ghostty" ]; then
      ghostty_bin="$app/Contents/MacOS/ghostty"
      took=""
      break
    fi
  done
fi

# Who holds the screen right now, so a background lane can give it back once it
# has moved out of the way. Asked BEFORE anything is opened, because a moment
# later the honest answer is the lane itself.
#
# Empty for a foreground lane, which is what makes the give-back inside the
# launcher a no-op needing no branch of its own — and empty on the ghostty
# backend too, which has no AeroSpace to ask and whose AppleScript spawn simply
# never activates.
#
# The APP is captured beside the window, and it is not belt-and-braces: some
# window is not always AeroSpace's to name. A native-fullscreen app, an
# unmanaged window, or an AeroSpace that simply answers late all give an empty
# window id — and an empty one means `giveback` does nothing, which is ⌃↵
# silently keeping the screen and looking exactly like plain ↵. `lsappinfo` is
# LaunchServices' own view of who is frontmost, needs no grant and no Apple
# Event, and re-activating that app is a coarser give-back than the window but
# an enormously better one than none.
prev_wid=""
prev_app=""
if [ -n "$bg" ] && [ "$backend" = aerospace ]; then
  prev_wid="$(aerospace list-windows --focused --format '%{window-id}' 2>/dev/null)"
  prev_app="$(/usr/bin/lsappinfo info -only bundleid "$(/usr/bin/lsappinfo front 2>/dev/null)" 2>/dev/null |
    sed -n 's/.*"CFBundleIdentifier"="\([^"]*\)".*/\1/p')"
fi

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
    # ── giving the screen back ────────────────────────────────────────────
    # On the `open -na` fallback ($took=1) the window arrives with focus, so
    # this hands focus back to whatever had it before the spawn, on EVERY exit
    # from this block, not only the happy one — the two bails below are the
    # cases where the lane stays put on the page you are standing on, which is
    # exactly when leaving it focused as well would be worst.
    #
    # On the direct-exec path ($took empty) focus never moved, and a giveback
    # that ran anyway would YANK it: the user had those seconds to focus a
    # third window, and re-asserting the pre-spawn one would steal from it. So
    # there it fires only if this lane's own instance somehow holds focus — a
    # future Ghostty that self-activates on launch — and stays silent
    # otherwise. The gpid guard is a real line, not left to "empty matches
    # nothing": `list-windows --focused` can answer EMPTY too (a
    # native-fullscreen app, an unmanaged window, a late AeroSpace — the same
    # cases the prev_wid capture above lists), and empty = empty would have
    # fired the net on the exact path where focus was never taken.
    #
    # `$back` is empty for a foreground lane, so this is a no-op there and the
    # block needs no branch of its own. Best effort throughout: a window that
    # has since closed is not worth a word, and there is nowhere here to say it.
    #
    # vanish() is the bails' other half, and only for the silent birth: a
    # $took=1 bail strands a VISIBLE floating window on the page you are
    # standing on — a nuisance you can see and fix — but a direct-exec bail
    # strands a 1-px sliver in a screen corner, a lane that exists and works
    # with nothing on any page to say so. ⌃⇥ will never find it (no tile ever
    # landed on T/<repo>), so say where it went: the agents pill and `scruff`
    # both raise it by session name, which is exactly what they are for.
    printf '  back=%q\n' "$prev_wid"
    printf '  backapp=%q\n' "$prev_app"
    printf '  took=%q\n' "$took"
    printf '  giveback() {\n'
    printf '    if [ -z "$took" ]; then\n'
    printf '      [ -n "$gpid" ] || return 0\n'
    printf '      [ "$(aerospace list-windows --focused --format "%%{app-pid}" 2>/dev/null)" = "$gpid" ] || return 0\n'
    printf '    fi\n'
    printf '    [ -n "$back" ] && aerospace focus --window-id "$back" >/dev/null 2>&1 && return 0\n'
    printf '    [ -n "$backapp" ] && /usr/bin/open -b "$backapp" >/dev/null 2>&1\n'
    printf '    return 0\n'
    printf '  }\n'
    printf '  vanish() {\n'
    printf '    [ -z "$took" ] || return 0\n'
    printf '    /run/current-system/sw/bin/haus-notify --source haus.lane --kind fault --symbol eye.slash \\\n'
    printf '      --thread %q --title "haus · agent lane" \\\n' "$sess"
    printf '      --body %q >/dev/null 2>&1\n' "$sess opened out of sight and could not be tiled — raise it from the agents pill, or scruff"
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
    printf '  [ -n "$gpid" ] || { stamp ""; vanish; giveback; exit 0; }\n'
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
    printf '  [ -n "${WID:-}" ] || { stamp ""; vanish; giveback; exit 0; }\n'
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
    printf '  aerospace move-node-to-workspace %s--window-id "$WID" %q\n' \
      "$follow" "T/$repo"
    printf '  aerospace layout --window-id "$WID" tiling\n'
    # Only once the lane has left the visible workspace: give it back any
    # earlier and AeroSpace would move a window that no longer has focus,
    # which is the same mis-aim `--focused` used to make.
    printf '  giveback\n'
    # LAST: the label is allowed to land late — a chord pressed in the first
    # quarter-second simply gets the title join — and neither the move nor the
    # giveback is.
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
# `-g` survives on the COLD START alone. That call is a pre-warm — its whole job
# is to have the process up before the `open -na` below, so the lane's own spawn
# doesn't race the app's launch and land a stray default window beside it — and
# an instance that comes up windowless is precisely what a pre-warm wants. The
# lane's OWN spawn must never carry it: see the measurement in the background
# note above.
#
# The direct-exec path skips the pre-warm outright: it involves no
# LaunchServices launch to race, and the windowless instance a `-g` pre-warm
# leaves behind is exactly the Apple Events lottery entrant the note above
# warns about — spawning one for a path that cannot need it would be all cost.
if [ -z "$ghostty_bin" ] && ! pgrep -ix ghostty >/dev/null 2>&1; then
  # shellcheck disable=SC2086  # $warm_bg is a whole flag or nothing
  open $warm_bg -a Ghostty
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
  # initial-command, so the whole lane silently fails to exist. The measurement,
  # and what a lane that must not be seen does instead — the direct exec below —
  # are in the background note above.
  if [ -n "$ghostty_bin" ]; then
    # A background lane's window, born silent: exec'ing the bundle's binary
    # skips LaunchServices, so nothing activates, and the clamped
    # --window-position keeps the birth frame to a 1-px corner sliver until the
    # launcher's self-tile block moves it to T/<repo>. Backgrounded and nohup'd
    # because this hook exits immediately and the app must outlive it.
    #
    # BOTH stdio redirects are load-bearing, not tidy: a direct exec inherits
    # this hook's fds, the hook inherits scruff's, and `scruff spawn`'s stdout is
    # a command substitution in spawn-agent.sh — a Ghostty holding that pipe
    # open would hang the palette for the life of the lane. (`open -na` never
    # had the problem; LaunchServices launches carry no fds.)
    #
    # `&` cannot fail, which `open -na` could (a refused launch exits non-zero
    # → exit 3 → scruff reports and the palette drops the lane). The kill -0
    # probe below buys that reporting back for the launch failures that show
    # inside 200ms — a bad dylib, translocation, an instant crash. A death
    # after that is the same blindness `open -na` already has: it, too,
    # returns before the window exists (the note in the launcher section
    # above), and the launcher's holds keep the evidence if the lane dies.
    #
    # ── the size flags are the ones that WORK ─────────────────────────────
    # MEASURED 2026-08-29 in a headless macOS guest, screenshotting a direct
    # exec at 150 ms intervals, because #529's claim about the position pair
    # did not survive contact with a live machine (#544 removed the whole
    # window over it):
    #
    #   --window-position-x/-y=25000  IGNORED. The window is born at the same
    #                   mid-screen frame as a launch with no position flags at
    #                   all — the two screenshots differ only in the dialogs
    #                   already on the guest's desktop. Not clamped to a 1-px
    #                   corner sliver, whatever #529 measured. This is the
    #                   flash that was reported and never isolated, and it is
    #                   the same fact scripts/float-term.sh's header records
    #                   ("inherits a saved-state frame"), which is why THAT
    #                   script drives the frame through AX instead.
    #   --window-width/--window-height  HONOURED, in CELLS, on the initial
    #                   window. 10x4 is Ghostty's floor ("Windows smaller than
    #                   10 wide by 4 high are not allowed", +show-config), and
    #                   it turns the birth from a full terminal blinking over
    #                   your page into a speck about a hundred pixels across,
    #                   for the ~200 ms before the self-tile block moves it to
    #                   T/<repo> and AeroSpace gives it the tile's own frame.
    #
    # So the position pair stays — it costs nothing and a machine whose
    # Ghostty honours it is strictly better off — and the size pair is what
    # actually buys the silence. What it costs: the client starts on a 10x4
    # PTY and takes a SIGWINCH when the tile lands, so a lane's first frame
    # can be drawn narrow and redrawn. That is a scrollback artifact; the
    # alternative was a full window on the page you were standing on.
    nohup "$ghostty_bin" \
      --title="$sess" \
      --initial-command="$launcher" \
      --window-width=10 \
      --window-height=4 \
      --window-position-x=25000 \
      --window-position-y=25000 >/dev/null 2>&1 &
    sleep 0.2
    kill -0 $! 2>/dev/null || exit 3
  else
    open -na Ghostty.app --args \
      --title="$sess" \
      --initial-command="$launcher" || exit 3
  fi
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

# `activate` is what a foreground lane wants and a background one must not ask
# for — $activate_line is the whole difference. It is not a guarantee on this
# backend the way the direct exec is on the other: this one asks a RUNNING
# Ghostty for a window, and AppKit may order that window front whatever the
# script says. A tiler-less machine has no T/<repo> to hide it on either, so
# "background" here means "we do not ask for the screen", not "you will not see
# it".
gwid="$(
  /usr/bin/osascript -e "tell application \"Ghostty\"
  set w to (new window with configuration {command:$(osa_str "$launcher")})
$activate_line
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
