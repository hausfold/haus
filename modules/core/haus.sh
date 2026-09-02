#!/usr/bin/env bash
# haus — the everyday CLI for a haus machine, so you never memorise the Nix
# incantations. This is the END-USER CLI haus ships (core puts it on
# PATH). It drives your OWN machine only — it knows nothing about the workshop
# family repos or agent worktrees (that's the workshop's developer CLI, `bench`).
#
#   haus rebuild        build + switch this machine from your config  (-v for raw output) (the usual day)
#   haus fix            hand the rebuild that just failed to a coding agent (needs the AI room)
#   haus update [name]  pull the latest haus (or a pinned desktop) + apps, then rebuild
#   haus rollback [N]    go back a generation (or to generation N)
#   haus generations     list the generations you can roll back to
#   haus status          current generation + how old your pinned haus is
#   haus edit            open your host config (identity, apps) in $EDITOR
#   haus options         refresh hosts/<host>/options.nix — every haus.* option, annotated
#   haus set             write + apply haus.* options in the machine overlay (pairs; bare = pick one)
#   haus get             read one option, or list the machine overlay (--json)
#   haus unset           force nullable options to null (variadic)
#   haus reset           remove machine overrides and inherit config again (variadic)
#   haus plan            preview what 'haus rebuild' would change — packages, settings, files, launchd jobs, casks — read-only
#   haus diff            declared config vs what macOS actually has right now — read-only
#   haus capture         turn this Mac's current settings into config lines + a snapshot
#   haus revert-settings put back a 'haus capture' snapshot (Nix rollback can't touch macOS defaults)
#   haus doctor          check the machine's health (Nix, CLT, the GUI agents)
#   haus report          file a bug on GitHub with 'haus doctor' already filled in (--print)
#   haus skill           print haus's own agent skill, or one of its reference pages;
#                        'haus skill install' writes it into an agent client
#   haus permissions     every grant and click this Mac still needs a person for
#   haus btm             check BTM daemon-gating (macOS 26 Tahoe+; no-op before)
#   haus tour            take the guided haus tour (it lives in the bar)
#   haus show            inspect a desktop or room — a local file or a source you have
#                        not got yet — class, checker verdict, what it sets (--json) — read-only
#   haus add <source>    pin a desktop and select it (--as/--file/--vendor/--print), or a
#                        room with --room --namespace <ns> — no rebuild
#   haus desktop [name]  list what this machine has, or switch to one — no rebuild
#   haus remove <name>   unpin a desktop and reselect explicitly — no rebuild
set -euo pipefail

# A bare/sudo/login-item shell may have almost nothing on PATH; make sure the
# tools we call (nix, darwin-rebuild, jq, git) resolve wherever we're invoked.
PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/etc/profiles/per-user/$(id -un)/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
export PATH

# Your config flake — the thin consumer with your host file, scaffolded by the
# bootstrap. Override with HAUS_CONSUMER if it lives elsewhere.
CONSUMER="${HAUS_CONSUMER:-$HOME/.config/nix}"
# `add`/`desktop`/`remove` all edit this one file; named once so every
# landmark check below reads the same thing settings_write's TX helpers do.
FLAKE="$CONSUMER/flake.nix"

# ---- snug's bash painter ----------------------------------------------------
# `share/ui.sh` is snug's bash half — the same spec as the `snug` binary, at
# lower fidelity, for a shell that cannot see the binary. `HAUS_UI_SH` is an
# absolute store path set by the wrapper in modules/core/default.nix, because
# this script is `builtins.readFile`'d into a store binary: it has no checkout
# to look beside, and a haus user has no clone of anything to look in.
#
# GUARDED, never assumed — the same contract this script keeps toward trill.
# `${VAR:-}` and `-r` rather than a bare `source`: under `set -euo pipefail` an
# unset variable is fatal and a `source` of a missing path exits 1, which would
# kill `haus` at load time, before any verb ran, with nothing on either stream.
# That is the worst possible failure mode for a courtesy, and it is exactly the
# shape of the `tput` bug ui.sh itself was written not to inherit.
if [ -r "${HAUS_UI_SH:-}" ]; then
  # shellcheck source=/dev/null
  source "$HAUS_UI_SH"
fi

# Did it load? A generation older than the wrapper that sets HAUS_UI_SH, or a
# hand-run `bash haus.sh`, has no painter at all and still has to work — so
# every line below degrades to plain text rather than assuming a function.
# (ui.sh sets its own gates — UI_TTY, UI_PROFILE — at load; never assume those
# either. UI_TTY is measured from fd 2, which is the point of the next block.)
# Probed by the functions this script actually CALLS, not by one of them: a
# partial painter is a `command not found` in the middle of a rebuild, and the
# gate below would have licensed it.
UI_READY=""
type ui_say ui_warn ui_hint ui_fail ui_glyph_bare \
     ui_row ui_clear ui_paint ui_live_close \
     ui_col ui_trow ui_table_data ui_table_clear >/dev/null 2>&1 && UI_READY=1

# ---- palette ----------------------------------------------------------------
# Role names, not colours. C_* alias snug's GENERATED roles — one source of
# hexes (snug's script/gen-palette.sh, resolved against nebelung) instead of the
# hand-picked 256-colour indices that used to sit here and had drifted from the
# tokens they were meant to be wearing. Colour is still a courtesy, never
# load-bearing: when it is off every C_* is empty and the same printf falls back
# to clean text.
#
# TWO gates, one palette. These C_* are the REPORT painter's, and a report is
# entirely on fd 1 (see the note by the verbs), so this gate keys on fd 1. The
# other gate is ui.sh's own, measured from fd 2, and it covers everything a
# narrating command draws — the message verbs and the rebuild's live region.
# Neither gate ever answers about the other's stream, which is the property that
# makes `haus doctor | less` escape-free while `haus rebuild` still paints.
#
# Alignment survives because colour only ever wraps AROUND a pre-padded field,
# never inside a %-Ns width — an escape counted as width shears the column.
C_OFF=; C_FOG=; C_OK=; C_WARN=; C_ERR=; C_MUT=
if [ -n "$UI_READY" ] && type ui__detect_profile ui__resolve_palette >/dev/null 2>&1; then
  # ui.sh measured fd 2 at load, because that is where its own lines go. A
  # report is on fd 1, so ask ITS detector about fd 1 and read the palette back
  # off that answer — rather than re-deriving the rule here, which is how the
  # two ended up disagreeing about `NO_COLOR` with `CLICOLOR_FORCE` set, and
  # about `TERM=dumb`, inside one binary. One precedence, asked twice.
  ui__haus_tty2="$UI_TTY"
  UI_TTY=""; [ -t 1 ] && UI_TTY=1
  ui__detect_profile; ui__resolve_palette
  C_OFF="${UI_OFF:-}"
  C_FOG="${UI_ACCENT:-}"   # primary accent — the fog itself
  C_OK="${UI_OK:-}"        # current / healthy
  C_WARN="${UI_WARN:-}"    # stale / wants attention
  C_ERR="${UI_ERR:-}"      # failure
  C_MUT="${UI_MUTED:-}"    # secondary detail
  # Put fd 2's answer back: everything after this line is ui.sh's own, and it
  # must not inherit a profile measured from the wrong stream.
  UI_TTY="$ui__haus_tty2"
  ui__detect_profile; ui__resolve_palette
  unset ui__haus_tty2
fi

# The glyphs the report verbs wear. ui.sh answers the ASCII set on a terminal
# that cannot draw the UTF-8 one (LANG=C, a serial console, a CI log with a
# non-UTF-8 locale), which a literal '✓' never could; without ui.sh they are the
# literals, exactly as before.
G_SAY=$'\u224B'; G_OK='✓'; G_BAD='✗'; G_WARN='⚠'; G_INFO='ⓘ'; G_HINT='↳'
if [ -n "$UI_READY" ]; then
  ui_glyph_bare G_SAY say
  ui_glyph_bare G_OK ok
  ui_glyph_bare G_BAD err
  ui_glyph_bare G_WARN warn
  ui_glyph_bare G_INFO info
  ui_glyph_bare G_HINT hint
fi

# ---- the snug coprocess -----------------------------------------------------
# ONE `snug run` for the whole command, not one fork per line: a fork costs
# ~4.4 ms and a rebuild draws sixty lines, so per-line would be a third of a
# second of pure overhead. bash pipes a coproc's stdin and stdout and leaves its
# stderr on the terminal, which is exactly the split snug wants — records go
# down the pipe, painted lines come out on fd 2.
#
# Opened by the phase PAINTER and closed with the work it narrates, so a command
# with no phases — `update`, `rollback`, `set`, every report — forks nothing at
# all. Records are tab-separated, one per line — `snug run` splits on tabs, and
# a space after the verb does not parse. The write end closes when `haus` exits;
# snug sees EOF and restores the cursor, so there is no EXIT trap to add here
# (and cmd_rebuild already owns EXIT for the card).
#
# The dispatch belongs to this script, not to ui.sh: one fork per COMMAND is the
# whole economy, and a library sourced per script cannot see the command
# boundary that decision needs. Never a message verb: that would put this
# script's own printfs and snug's lines on two schedules. The standard is snug's
# own AGENTS.md, **Rules a bash caller has to meet**.
SNUG_FD=""
SNUG_TRIED=""
# SNUG_PID is not declared here on purpose: `coproc SNUG` makes bash set it
# itself, to the coprocess's pid. Assigning it would shadow that, and the `wait`
# in snug_close would then be waiting on a number that is not a process.

snug_open() {
  [ -n "$SNUG_FD" ] && return 0
  [ -z "$SNUG_TRIED" ] || return 1
  SNUG_TRIED=1
  local bin
  bin="$(command -v snug 2>/dev/null || true)"
  [ -n "$bin" ] || return 1
  # No terminal on fd 2 — a pipe, a log, CI, an agent pane — means plain lines.
  # One detection, one answer: this is ui.sh's measurement, not a second one.
  [ -n "${UI_TTY:-}" ] || return 1
  coproc SNUG { "$bin" run; } || return 1
  # ⚠️ A coprocess's OWN descriptors are NOT available in a subshell — bash
  # closes them in every child it forks, to stop a subshell holding the pipe
  # open forever. The spinner below IS a subshell, so writing to `${SNUG[1]}`
  # from it silently does nothing: measured, the frame loop produced not one
  # record and the row sat on its first spinner glyph for the whole phase.
  # Duplicating the write end onto an ORDINARY fd fixes it — that one is
  # inherited like any other.
  exec {SNUG_FD}>&"${SNUG[1]}" || return 1
  # And close bash's copy, or nothing ever reaches EOF and `snug run` outlives
  # the command: the duplicate is now the only write end.
  eval "exec ${SNUG[1]}>&-" 2>/dev/null || true
  return 0
}

snug_emit() { # snug_emit <verb> <text> — one record; 1 = no coproc, caller falls back
  local line
  # 🚨 This NEVER opens the coprocess — the phase painter does, and only it.
  # A record crosses a pipe and is drawn by another process on ITS stderr,
  # while the lines this script prints itself (the blank that separates the
  # header, a failed phase's log tail) go straight to the terminal. Two
  # writers on two schedules put them in the wrong order. Inside a phase
  # region there is no race, because nothing here writes directly while one is
  # up. See snug's AGENTS.md, **Rules a bash caller has to meet**.
  [ -n "$SNUG_FD" ] || return 1
  # Multi-line text would break record framing, so it is one record per line.
  # (The Go side re-joins tab fields, so a tab inside prose is safe.)
  while IFS= read -r line; do
    { printf '%s\t%s\n' "$1" "$line" >&"$SNUG_FD"; } 2>/dev/null \
      || { snug_close; return 1; }
  done <<<"$2"
  return 0
}

snug_end() { # end the live region, keep the coprocess for the lines after it
  [ -n "$SNUG_FD" ] || return 0
  { printf 'end\n' >&"$SNUG_FD"; } 2>/dev/null || true
  return 0
}

# Every `&` inherits the write end, and everything that is not DRAWING has to
# drop it. The duplicate snug_open makes is an ordinary fd on purpose — that is
# what lets the spinner subshell write frames — so a background job that merely
# INHERITED it holds `snug run`'s stdin open too. `snug_close` closes the
# parent's copy and then waits for snug to see EOF; with a copy still open, EOF
# never comes. Measured: snug_close blocked for exactly the lifetime of the
# background subshell. And when that job's own exit condition is "the parent is
# gone" — card_hold's ticker loops on `kill -0 $CARD_PARENT` — the two wait for
# each other with no clock on it, which is a rebuild frozen on the phase whose
# failure the user most needs to read.
snug_detach() { # snug_detach — drop this process's copy of the write end
  [ -n "$SNUG_FD" ] || return 0
  eval "exec $SNUG_FD>&-" 2>/dev/null || true
  SNUG_FD=""
  return 0
}

snug_close() { # everything down: end the region and drop the coprocess
  [ -n "$SNUG_FD" ] || return 0
  snug_end
  eval "exec $SNUG_FD>&-" 2>/dev/null || true
  wait "${SNUG_PID:-}" 2>/dev/null || true
  SNUG_FD=""
  # SNUG_TRIED deliberately stays set: a snug that died once stays dead for this
  # command. Re-opening per frame would be a fork a frame — the exact regression
  # the coprocess exists to prevent. The verbs degrade to ui.sh instead.
  return 0
}

# ---- the verbs --------------------------------------------------------------
# Which stream a line goes to is a property of the COMMAND, not of the verb, and
# that is the whole design here. Half these verbs are called from helpers —
# `settings_diff` runs inside `haus plan` and inside `haus set`,
# `consumer_worktree_warning` inside `haus plan` and inside `haus rebuild` — so
# a per-verb rule cannot be right in both callers, and the first attempt at one
# split `haus doctor` across two streams: its section headers went to fd 2 while
# its findings stayed on fd 1, which makes `haus doctor | pbcopy` an unlabelled
# list of ticks. That flow is not optional — `.github/ISSUE_TEMPLATE/bug.yml`
# asks a stranger to paste exactly it, and it is the only feedback channel
# anything we ship has.
#
# So: a REPORT command draws entirely on fd 1, and everything else draws
# entirely on fd 2. `REPORT` is set once, in the dispatch at the bottom, where
# you can read the whole list at a glance.
#
#   report      status doctor plan diff permissions btm generations get capture
#               report
#   narration   rebuild update rollback set unset reset options add desktop
#               remove edit tour revert-settings skill
#
# `skill` is in the narration column and that is not an oversight: its payload
# is `cat`, which is on fd 1 whatever REPORT says, so `haus skill | pbcopy` is
# already whole — and `haus skill install` changes the machine, which is what
# the narration column means. Listing it as a report would move `install`'s
# every "wrote …" line into the document `haus skill` is supposed to be.
#
# A report never touches the coprocess. That costs it snug's folding — the same
# price `bench`'s tables pay, and the same one these verbs have always paid —
# and buys the thing that matters: one stream, in order, that a pipe can catch.
# The one exception is `die`: an error is not part of a report, so it stays on
# fd 2 wherever it fires, and `haus doctor >out` still says so on the terminal.
REPORT=""

say()  {
  if [ -n "$REPORT" ]; then printf '%s%s  %s%s\n' "$C_FOG" "$G_SAY" "$*" "$C_OFF"
  else snug_emit say "$*" || ui_draw say "$*"; fi
}
warn() {
  if [ -n "$REPORT" ]; then printf '%s%s  %s%s\n' "$C_WARN" "$G_WARN" "$*" "$C_OFF"
  else snug_emit warn "$*" || ui_draw warn "$*"; fi
}
# Secondary detail: what a line above it means, or what to run about it.
hint() {
  if [ -n "$REPORT" ]; then printf '  %s%s%s %s\n' "$C_MUT" "$G_HINT" "$C_OFF" "$*"
  else snug_emit hint "$*" || ui_draw hint "$*"; fi
}
die()  { snug_emit fail "$*" || ui_draw fail "$*"; exit 1; }

ui_draw() { # ui_draw <verb> <text> — ui.sh's line, or plain text if it is absent
  if [ -n "$UI_READY" ]; then "ui_$1" "$2"
  else printf '%s\n' "$2" >&2; fi
}

# The indented body of a report. Always fd 1 — nothing calls these outside one.
ok()   { printf '  %s%s%s %s\n' "$C_OK" "$G_OK" "$C_OFF" "$*"; }
bad()  { printf '  %s%s%s %s\n' "$C_ERR" "$G_BAD" "$C_OFF" "$*"; }
info() { printf '  %s%s%s %s\n' "$C_FOG" "$G_INFO" "$C_OFF" "$*"; }

# Every verb here drives THIS machine's config, so the config has to exist —
# with two exceptions. `haus show` reads a desktop someone is about to publish or
# about to trust — a local file, or a source it fetches into the store; it
# touches no machine at all, and a publisher checking a desktop in CI has no
# consumer flake to point it at. Guarding it here would
# make the one command with an audience outside this Mac the one command that
# cannot run outside it.
#
# `haus skill` is exempt because it reads ONE store path (HAUS_SKILL_DIR) and
# nothing on this machine at all: the answer is the same in a container, in CI
# and half way through a bootstrap, and an agent dropped into a fresh checkout
# asking what haus is should not be refused because the machine has no config
# yet — that is the moment the skill is most worth reading.
#
# `haus report` is exempt for the opposite reason: a missing or moved config
# flake is not a state to refuse in, it is a state to REPORT. That is a
# bootstrap that stopped half way, and the person meeting it is the reporter
# haus most needs to hear from — refusing them the door because the thing they
# are reporting is missing is the whole failure in one line. Everything the
# block reads from the consumer degrades on its own (an unpinned revision, an
# unknown desktop), so there is nothing here to protect.
#
# The verb is the first argument that isn't `-v`, for the same reason the
# dispatch strips it below: `haus -v show …` is a legal spelling, and keying
# this on `$1` alone would make the flag re-arm the guard.
haus_verb=""
for a in "$@"; do
  case "$a" in
    -v | --verbose) ;;
    *)
      haus_verb="$a"
      break
      ;;
  esac
done
case "$haus_verb" in
  show | report | skill) ;;
  *) [ -e "$CONSUMER/flake.nix" ] || die "no config flake at $CONSUMER — set HAUS_CONSUMER, or run the bootstrap first." ;;
esac
unset haus_verb a

SYSPROFILES=/nix/var/nix/profiles

# ---- the rebuild front end --------------------------------------------------
# A rebuild's own tools narrate ~100 lines, and ~95 of them are identical every
# single time: nix-darwin's activate script alone echoes 62 (18 of which are one
# `reloading service <x>` per launchd job), and home-manager adds ~39 more. None
# of it is ours to delete — it comes out of upstream's scripts — but it IS ours
# to fold. So the phases whose output we hide are the phases we log, and the
# summary is rendered from that log.
#
# The rule, so nothing important can go missing: we only hide what we WRITE
# DOWN, we hide nothing on failure, and anything that isn't a human watching a
# terminal (an agent pane, CI, a pipe) gets the raw stream instead.
HAUS_LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/haus"
HAUS_LOG="$HAUS_LOG_DIR/rebuild.log"

# Verbose = raw, unsummarised, exactly what the old haus printed. Deliberately
# NOT "quiet output plus filtering": a filter that drops a line you didn't
# expect is how a warning disappears, so verbose is a passthrough, full stop.
VERBOSE="${HAUS_VERBOSE:-}"
# BOTH streams, and that is the conservative reading of "is a human watching".
# The summary lives on fd 2 now and the log it is rendered from is a file, so
# fd 2 alone would be the tidy gate — but `haus rebuild >build.log` has always
# meant "give me the transcript", and gating on fd 2 would hand that person a
# nearly empty file and a pretty summary they cannot paste. Either stream
# redirected still means transcript; an agent pane and CI have neither, so they
# are unaffected.
{ [ -t 1 ] && [ -t 2 ]; } || VERBOSE=1

# ---- the phase painter ------------------------------------------------------
# The phase lines are a LIVE REGION, and snug owns it now: `phase_start` puts a
# SPINNING row on screen, the phase runs, `phase_ok`/`phase_bad` repaint it as
# the finished row and close the region. Closing leaves the final frame in
# scrollback, so the four rows of a rebuild stack up exactly as they always did
# — resolve, build, activate, generation — one region each.
#
# Everything this file used to carry in order to draw that itself is gone:
# PHASE_COLS, the five width tiers, the truncation, `\r\033[2K`, and the width
# probe
#
#   sz="$(stty size 2>/dev/null </dev/tty)" && COLS="${sz#* }" || COLS="$(tput cols)"
#
# which could kill its own caller — `tput` exits 2 with TERM unset, and `set -e`
# exempts every command in a `&&`/`||` list EXCEPT the last, so `ssh mac haus
# rebuild` died with status 2 and nothing on either stream, after a successful
# evaluation and before anything activated. Measured. One runtime, in snug,
# instead of a fourth copy of that here. See snug's README for what a live
# region owes you, and its AGENTS.md for the rules a bash caller has to meet.
#
# Three fidelities, and the row degrades rather than disappearing:
#
#   snug on PATH, terminal on fd 2  the coprocess — spinner, folding, resize
#   ui.sh only                      its live region: same spec, no spinner
#   neither                         one plain line per state change, on fd 2
PHASE_LABEL=""      # the row on screen; empty means there is none to repaint
PHASE_T0=0          # deciseconds at phase_start, for the running clock
PHASE_SPIN_PID=""   # the frame loop, alive only while the coprocess is
# Set non-empty to run the next phase as a STILL row: the region opens, the mark
# is a bullet, and nothing repaints. It exists for one case and it is not
# hypothetical — `sudo` writes its password prompt to /dev/tty, which is the same
# terminal the region is repainting, and the region's line count knows nothing
# about a line sudo printed. Ten frames a second would then rewind over the
# prompt and over what you are typing into it. A machine with passwordless
# activation (haus's security room installs the rule) never takes this path; a
# fresh one, before its first switch, does.
PHASE_STILL=""

# One frame: one row, painted. <state> is snug's — `run` spins, `ok`/`fail` are
# finished marks.
phase_frame() { # phase_frame <state> <label> <detail>
  if [ -n "$SNUG_FD" ]; then
    { printf 'row\t%s\t%s\t%s\npaint\n' "$1" "$2" "$3" >&"$SNUG_FD"; } 2>/dev/null \
      || { snug_close; return 1; }
  elif [ -n "$UI_READY" ]; then
    # ui_paint degrades on its own when fd 2 is not a terminal: one plain line
    # per state change, and no cursor escape ever reaches a file.
    ui_clear; ui_row "$1" "$2" "$3"; ui_paint
  else
    # No painter at all. The glyph carries the meaning; a `run` row has nothing
    # to repaint it, so it would only be noise.
    case "$1" in
      ok)   printf '   ✓  %s (%s)\n' "$2" "$3" >&2 ;;
      fail) printf '   ✗  %s (%s)\n' "$2" "$3" >&2 ;;
    esac
  fi
  return 0
}

# The spinner. `snug run` advances the frame on every `paint` and keeps no clock
# of its own, so somebody has to send frames — and the phase itself is a
# FOREGROUND command (`sudo haus-activate` has to keep the terminal for a
# password prompt, and backgrounding it to poll around it would risk that), so
# the sender is a background loop rather than a poll around a backgrounded phase.
#
# It writes ONLY to the coprocess, and only while nothing else is writing there:
# in quiet mode the phase's own output goes to the log, so the fd is idle for the
# whole phase. That is also why there is no ui.sh spinner — ui.sh's region lives
# in shell variables, and a subshell repainting it would leave the parent with a
# wrong idea of how many screen lines the region used.
#
# `kill -0 $$` is the leash. `haus` exiting closes the PARENT's write end, but
# this child holds a copy of it, so without the check the coprocess would never
# see EOF and would keep spinning as an orphan on somebody's terminal.
phase_spin_start() {
  [ -n "$SNUG_FD" ] || return 0
  local parent=$$
  {
    while kill -0 "$parent" 2>/dev/null; do
      sleep 0.1
      { printf 'row\trun\t%s\t%s\npaint\n' \
          "$PHASE_LABEL" "$(secs $(( $(now_ds) - PHASE_T0 )) )" >&"$SNUG_FD"; } 2>/dev/null || break
    done
  } &
  PHASE_SPIN_PID=$!
  return 0
}

phase_spin_stop() {
  [ -n "$PHASE_SPIN_PID" ] || return 0
  kill "$PHASE_SPIN_PID" 2>/dev/null || true
  wait "$PHASE_SPIN_PID" 2>/dev/null || true
  PHASE_SPIN_PID=""
  return 0
}

# Open the region for one phase.
#
# Two conditions, and the second is not redundant: VERBOSE is forced on wherever
# there is no terminal (see its assignment above), so today it implies this.
# Saying it here too keeps the function true on its own — PHASE_LABEL is what
# licenses every frame below, and it must never be set by a painter that had no
# terminal to paint on, whatever a distant assignment happens to do.
phase_start() {
  PHASE_LABEL=""
  if [ -n "$VERBOSE" ] || [ -z "${UI_TTY:-}" ]; then return 0; fi
  PHASE_LABEL="$1"
  PHASE_T0="$(now_ds)"
  snug_open || true
  if [ -n "$PHASE_STILL" ]; then
    # `wait`, not `run`: a spinner glyph that never turns reads as a hung
    # terminal, where a bullet reads as "queued", which is the truth.
    phase_frame wait "$PHASE_LABEL" "$(secs 0)" || true
  else
    phase_frame run "$PHASE_LABEL" "$(secs 0)" || true
    phase_spin_start
  fi
}

# Repaint the row as finished and close the region.
#
# It runs even when this phase left NO row, which is `build`'s case: nix keeps
# the terminal for its own progress bar, so nothing was painted to repaint —
# but the finished row still has to land, and opening a one-frame region for it
# is how it lands folded rather than as a raw printf.
#
# The elapsed and the detail share snug's one right-hand column: "12.3s" alone,
# or "12.3s · 12 services · homebrew changed" when a phase has something to add.
# A row never carries an empty field between two non-empty ones — `read`
# collapses consecutive delimiters — so the join is done here, not by sending an
# empty elapsed.
phase_repaint() { # phase_repaint <state> <label> <elapsed> [detail]
  local state="$1" label="$2" el="$3" detail="${4:-}"
  phase_spin_stop
  if [ -n "$el" ] && [ -n "$detail" ]; then detail="$el · $detail"
  elif [ -z "$detail" ]; then detail="$el"; fi
  snug_open || true
  phase_frame "$state" "$label" "$detail" || true
  if [ -n "$SNUG_FD" ]; then snug_end
  elif [ -n "$UI_READY" ]; then ui_live_close; fi
  PHASE_LABEL=""
  return 0
}
phase_ok()  { phase_repaint ok   "$1" "$2" "${3:-}"; }
phase_bad() { phase_repaint fail "$1" "$2"; }
secs()        { printf '%d.%01ds' $(( $1 / 10 )) $(( $1 % 10 )); }
# Deciseconds, from bash's own clock. NOT `date +%s%N`: that's a GNU extension,
# and BSD date prints a literal "N" — which only shows up as broken arithmetic
# on the one platform this script is FOR. The character class covers locales
# where $EPOCHREALTIME's separator is a comma.
now_ds() {
  local t="${EPOCHREALTIME:-}"
  [ -n "$t" ] || { echo $(( SECONDS * 10 )); return; }
  t="${t//[.,]/}"
  echo $(( 10#${t:0:11} ))
}

# Run one phase. Quiet mode appends everything to the log and shows a single
# line; verbose mode streams. On failure BOTH modes show the tail of what the
# phase actually said, plus where the whole thing was written.
# One log per rebuild, previous one kept. Fresh each time so "the log" always
# means this rebuild, and so the byte offsets run_phase slices by stay cheap.
log_open() {
  mkdir -p "$HAUS_LOG_DIR"
  [ -f "$HAUS_LOG" ] && mv -f "$HAUS_LOG" "$HAUS_LOG.prev" 2>/dev/null
  printf '=== %s · %s ===\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >"$HAUS_LOG"
}

HAUS_PHASE_SLICE=""   # this phase's own log slice, for the summary line
# Where that slice STARTS, in bytes. The slice itself is a string this shell is
# about to exit with; the offset is what survives into
# ~/.local/state/haus/last-failure, so `haus fix` can take the same slice out of
# the same log in a process that was not here when it was written.
HAUS_PHASE_OFF=0
run_phase() {
  local label="$1"; shift
  local t0 rc=0 off=0
  mkdir -p "$HAUS_LOG_DIR"
  : >>"$HAUS_LOG"
  off="$(wc -c <"$HAUS_LOG" | tr -d ' ')"
  HAUS_PHASE_OFF="$off"
  t0="$(now_ds)"
  phase_start "$label"
  if [ -n "$VERBOSE" ]; then
    "$@" 2>&1 | tee -a "$HAUS_LOG"
    rc="${PIPESTATUS[0]}"
  else
    "$@" >>"$HAUS_LOG" 2>&1 || rc=$?
  fi
  HAUS_PHASE_ELAPSED="$(secs $(( $(now_ds) - t0 )) )"
  HAUS_PHASE_SLICE="$(tail -c "+$((off + 1))" "$HAUS_LOG")"
  if [ "$rc" -ne 0 ]; then
    phase_bad "$label" "$HAUS_PHASE_ELAPSED"
    # The rebuild is over — every caller of run_phase follows a non-zero rc
    # with `die`. Drop the coprocess before the slice below, because that is a
    # printf straight to the terminal and a coprocess still holding records
    # would interleave its lines with a build log. The `warn` after it draws
    # through ui.sh, in this script's own order.
    snug_close
    # fd 2 with the rest of the rebuild: it is the failure it belongs to, not
    # output. (`>&2` on the pipeline's tail, which is what reaches a terminal.)
    [ -n "$VERBOSE" ] || printf '%s\n' "$HAUS_PHASE_SLICE" | tail -n 25 | sed 's/^/      /' >&2
    warn "full log: $HAUS_LOG"
  fi
  return "$rc"
}

# What actually happened during activation, from the lines we just hid.
activation_summary() {
  local services brewline=""
  services="$(printf '%s\n' "$HAUS_PHASE_SLICE" | grep -cE '^(reloading|creating) (user )?service ' || true)"
  if printf '%s\n' "$HAUS_PHASE_SLICE" | grep -qE '^(Installing|Upgrading|Uninstalling) '; then
    brewline=" · homebrew changed"
  elif printf '%s\n' "$HAUS_PHASE_SLICE" | grep -q 'Homebrew bundle'; then
    brewline=" · homebrew ok"
  fi
  printf '%s service%s%s' "$services" "$([ "$services" = 1 ] || echo s)" "$brewline"
}

# ---- doing two things at once -----------------------------------------------
# A rebuild is two independent pipelines that we ran back to back for no reason:
# nix (evaluate, substitute, build) and Homebrew (update taps, download casks).
# They share no state — different caches, different stores — so the brew half
# belongs alongside the build, not after it.
#
# The one ordering that IS load-bearing: activation runs `brew bundle` itself,
# and two brew processes fight over the same lock, so every brew job must be
# joined BEFORE we activate. Hence one registry and one `bg_wait` at the gate.
BG_PIDS=()
# snug_detach: this body draws nothing, so it must not hold the coprocess's
# write end open behind snug_close's wait — see snug_detach.
bg() { ( snug_detach; "$@" ) >>"$HAUS_LOG" 2>&1 & BG_PIDS+=("$!"); }
bg_wait() {
  local pid rc=0
  for pid in ${BG_PIDS[@]+"${BG_PIDS[@]}"}; do wait "$pid" || rc=1; done
  BG_PIDS=()
  return "$rc"
}

# Download (don't install) whatever activation is about to upgrade, while the
# nix build runs. `brew fetch` only fills brew's download cache — it touches no
# installed app — so this keeps haus's promise that a FAILED BUILD CHANGES
# NOTHING, while moving the part that actually takes minutes (a 200 MB Chrome
# or Zen update) off the critical path. Worst case on a failed build: a cached
# download nobody asked for yet.
#
# Gated on the running system's activate script, because a host with
# `haus.homebrew.upgrade = false` will never install what we'd fetch:
# nix-darwin passes `--no-upgrade` to `brew bundle` exactly then.
brew_prefetch() {
  command -v brew >/dev/null 2>&1 || return 0
  grep -q 'brew bundle .*--no-upgrade' /run/current-system/activate 2>/dev/null && return 0
  local outdated
  outdated="$(brew outdated --cask --quiet 2>/dev/null || true)"
  [ -n "$outdated" ] || return 0
  # shellcheck disable=SC2086
  brew fetch --cask $outdated || true
}

usage() {
  cat <<'EOF'
haus — the everyday CLI for a haus machine.

  haus rebuild        build + switch this machine from your config  (-v for raw output)
  haus fix            hand the rebuild that just failed to a coding agent: it reads
                      the error and what changed in your config, fixes it, verifies
                      the config evaluates and commits. It never activates — that
                      stays your 'haus rebuild'. Undo everything it did with
                      'git -C ~/.config/nix revert HEAD'. Needs the AI room
  haus update [name]  pull the latest haus (or a pinned desktop's input) + apps,
                      then rebuild
  haus rollback [N]   go back a generation (or to generation N)
  haus generations    list the generations you can roll back to
  haus status         current generation + how old your pinned haus is
  haus edit           open your host config in $EDITOR
  haus options        refresh the annotated catalogue of every haus.* option
                      (--force replaces your copy instead of writing options.nix.new)
  haus set <path> <value> [<path> <value>…]
                      write hosts/<host>/settings/<path>.nix, type-check it, and
                      rebuild (theme.accent and haus.theme.accent both work).
                      Several pairs land in ONE rebuild, all-or-nothing — which is
                      what an intent spanning two options needs (light mode is
                      theme.flavor + theme.systemAppearance)
  haus set            with no arguments: search every option this machine has, then
                      pick or type the value — the list of values comes from the
                      option's own type
  haus get [path]     print a declared value, or list values in the writable overlay.
                      --json for an agent: one {path, defined, value} object for a
                      path, an array of them for the listing
  haus unset <path> [<path>…]
                      force nullable options to null
  haus reset <path> [<path>…]
                      remove writable overrides and inherit the host/desktop/room value.
                      unset and reset take a LIST the way set takes pairs: several
                      paths land in ONE rebuild, all-or-nothing, so an intent that
                      took two options to make takes one command to undo
  haus plan           preview what 'haus rebuild' would change — packages, macOS
                      settings, the files home-manager writes into your home,
                      launchd jobs, casks — without building anything into place
  haus diff           the config currently active on this machine vs what macOS
                      actually has right now (effective state, not just the plist)
  haus capture [cat…] turn this Mac's current settings into config lines, and
                      snapshot them (default: dock keyboard finder; or a literal
                      plist domain, e.g. com.apple.Terminal)
  haus revert-settings [snapshot|list]
                      put back a 'haus capture' snapshot — Nix rollback rewinds
                      packages and agents, never macOS's own preferences
  haus doctor         check the machine's health (Nix, CLT, the GUI agents)
  haus report         file a bug: opens haus's issue form with this Mac's
                      details and its 'haus doctor' report already in the
                      diagnostics field, so the only thing left to write is
                      what happened. Nothing is sent until you press Submit,
                      and the block is printed here first so you can read
                      every line of it. --print stops there, without opening
                      a browser
  haus skill [name]   print haus's own agent skill — the file that teaches a
                      coding agent to change this Mac. With a name, one of its
                      reference pages instead: options, rooms or recipes. Always
                      the copy rendered from the revision this machine pinned,
                      so the option names in it are the ones you have
  haus skill install  write that skill into every agent client on this Mac that
                      hasn't got it. --client picks one — a wrong name lists the
                      clients this build knows, and the flag tab-completes —
                      --dir PATH writes somewhere else. On a normal haus machine
                      there is nothing to do: haus.ai.skill already installed it,
                      as read-only Nix symlinks, and it says so rather than
                      failing on a permission error
  haus permissions    walk everything on this Mac that needs a person: each grant
                      or click, why this machine wants it, and a button. Confirms
                      what macOS lets it confirm and says so about the rest.
                      --list reports without touching anything (so does doctor);
                      --reset forgets the cards you marked done by hand
  haus btm            check BTM daemon-gating (macOS 26 Tahoe+; no-op before)
  haus tour           take the guided haus tour (haus tour reset re-arms it)
  haus show <src>     inspect a desktop or room before you publish or trust it:
                      the class, whether it is a valid desktop and every rule it
                      breaks, what it sets and what it leaves alone. <src> is a
                      local .nix, or a source you have not got yet
                      (github:ada/desktop, git+https://…, file+https://…).
                      --file picks one inside a fetched repo; --room says it is
                      code; --json for CI and agents. A remote source is fetched
                      into the store and read there — nothing on this machine is
                      written, and nothing is activated
  haus add <src>      pin a desktop and select it — runs 'haus show' first as
                      the confirmation prompt, then writes flake.nix +
                      flake.lock. --as names the input, --file picks the file,
                      --vendor copies it in instead of pinning it, --print
                      shows the edit without writing it. Never rebuilds.
                      --room --namespace <ns> pins a ROOM instead: code, wired
                      into extraModules rather than selected as a desktop.
                      Confirming means typing back part of the revision — a
                      lock evaluates the room's flake.nix, which is the first
                      execution of its code, not the rebuild.
  haus desktop [name] list the built-in desktops and every one this machine has
                      pinned, marking the selected one; with a name, switch to
                      it. Never rebuilds.
  haus remove <name>  unpin a desktop this machine added, and reselect
                      explicitly (default: blank) so removing your selected
                      desktop can't silently fall back to the opinionated one.
                      Never rebuilds.

colour and width
  Colour is written only when stdout is a terminal and NO_COLOR is unset.
  CLICOLOR_FORCE=1 forces it back on through a pipe. The rebuild's phase lines
  fold to the window and repaint in place on a terminal, and degrade to one
  plain line each — no cursor escapes, no truncation — anywhere else.
EOF
}

# The running system's generation number — read from the profile symlink so it
# needs no sudo (darwin-rebuild --list-generations write-locks the profile).
current_gen() {
  local link
  link="$(readlink "$SYSPROFILES/system" 2>/dev/null)" || return 1
  link="${link#system-}"
  echo "${link%-link}"
}
gen_date() { date -r "$(stat -f %m "$SYSPROFILES/system-$1-link" 2>/dev/null || echo 0)" "${2:-+%Y-%m-%d}" 2>/dev/null || echo '?'; }

host_name() { # the darwinConfiguration to build — the one host in your flake
  if [ -n "${HAUS_HOST:-}" ]; then echo "$HAUS_HOST"; return; fi
  nix eval --json "$CONSUMER#darwinConfigurations" --apply builtins.attrNames 2>/dev/null \
    | jq -r '.[0]' 2>/dev/null \
    | grep . \
    || { scutil --get LocalHostName 2>/dev/null || hostname -s; }
}

# Nix's lazy-tree fetcher occasionally leaves a *partial* tree in its cache: the
# commit→tree mapping gets recorded, but a blob never finishes landing (an
# interrupted fetch, a laptop that slept mid-build, two nix runs racing the same
# cache). Every later eval that needs that blob then dies with the cryptic libgit2
# message "object not found - no match for id …", and nothing but clearing the
# cache fixes it. The tarball-/fetcher-caches are pure and regenerable, so on that
# exact signature we wipe them and retry once — a one-time re-fetch, not a rebuild.
NIX_CACHE_CORRUPT_SIG='no match for id'

nix_cache_wipe() { # drop the regenerable fetch caches for both the user and root nix stores
  warn "corrupt nix fetch cache — clearing it and retrying once (a one-time re-fetch) …"
  rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}"/nix/tarball-cache* \
         "${XDG_CACHE_HOME:-$HOME/.cache}"/nix/fetcher-cache*.sqlite 2>/dev/null || true
  # `darwin-rebuild switch` evaluates as root, so its cache is a separate store
  # under /var/root — needs sudo to clear (creds are usually still warm from the
  # switch we just ran; worst case it's one password prompt on the recovery path).
  sudo rm -rf /var/root/.cache/nix/tarball-cache* \
              /var/root/.cache/nix/fetcher-cache*.sqlite 2>/dev/null || true
}

heal() { # run "$@"; on the cache-corruption signature, wipe the caches and retry once
  local log rc
  log="$(mktemp)"
  if "$@" 2>&1 | tee "$log"; then rc=0; else rc=${PIPESTATUS[0]}; fi
  if [ "$rc" -ne 0 ] && grep -qF "$NIX_CACHE_CORRUPT_SIG" "$log"; then
    rm -f "$log"
    nix_cache_wipe
    "$@"; return $?
  fi
  rm -f "$log"
  return "$rc"
}

# ---- the Full Disk Access guard ---------------------------------------------
# The sharpest edge in the whole option surface:
# `system.defaults.universalaccess.*` is TCC-protected, and
# the write succeeds only if the app RESPONSIBLE for the rebuild holds Full Disk
# Access. nix-darwin emits it unguarded into an activation script running under
# `set -e`, two thirds of the way in — so without the grant activation aborts
# there and skips everything after it, including every launchd daemon and agent
# haus installs. The machine comes back with no bar, no tiling, no palette,
# and a symptom nowhere near its cause.
#
# THIS GUARD USED TO ASK THE WRONG QUESTION. It began with `under_agent ||
# return 0` — refuse an agent, wave a human through — and that is wrong in both
# directions, which is precisely what "must be impossible to hit by accident"
# rules out:
#
#   - It let two of the three clients through. `under_agent` tested CLAUDECODE,
#     and the lane chord spawns whichever client haus.ai.default names: Codex and OpenCode
#     set no such variable, so the one config shape that breaks a machine sailed
#     past the check written to catch it.
#   - It waved through the human it was protecting. A person in a terminal
#     nobody has granted FDA to hits the identical abort, and got no warning at
#     all — while a Claude pane INSIDE an FDA-holding terminal, which was always
#     going to work, was the case it stopped.
#
# The predicate that actually matters names no client and no persona: does this
# configuration write an unguarded TCC-protected domain, and can this process
# write it? Agent or human, terminal or .app, the answer is the same one, and
# it is the same answer the machine is about to give. `has_fda` tests the
# capability rather than guessing from who's driving — a Claude Code pane inside
# a terminal that holds the grant inherits it and rebuilds perfectly well, while
# the same agent under Claude.app, a cloud session, or a fresh terminal cannot.
#
# What makes strictness affordable is the other half of §5.12: every key in that
# domain measured to work now has a guarded `haus.accessibility.*` option, so
# refusing the raw form never refuses a setting that had no safer way to be
# said. Before that it would have.
#
# `under_agent()` lived here and is gone with the condition it served. Nothing
# else in this script needs to know who is driving, and leaving a
# who-is-driving predicate lying about is how the next guard gets written the
# same wrong way.
#
# Full Disk Access, for whichever app is responsible for THIS process. It must
# be a strict read of a protected file: the containing directory lists fine
# without the grant, so an `ls`-shaped test reports success on a machine that
# has no access at all.
has_fda() {
  head -c1 "$HOME/Library/Application Support/com.apple.TCC/TCC.db" >/dev/null 2>&1
}

# The TCC-protected keys this config actually sets, comma-separated (empty when
# there are none). It costs an evaluation of the darwin system, so it runs only
# on the guard's slow path — which, since the guard stopped short-circuiting on
# "is this an agent", is every `haus rebuild` from an app WITHOUT the grant. On
# a machine whose terminal holds FDA (the common case, and the one haus's own
# installer steers you to) it never runs at all. It can't be read out of the
# built script the way `haus plan`'s verdicts are: the guard has to answer
# before anything is built.
#
# The raw typed opt-ins ONLY — not haus.accessibility's, which reach the same
# domain through core's guarded writer and cost nothing worse than a skipped
# setting. This is the list of writes that would take the machine down with them.
universalaccess_keys() {
  ( cd "$CONSUMER" && nix eval --raw \
      ".#darwinConfigurations.$1.config.system.defaults.universalaccess" \
      --apply 'a: builtins.concatStringsSep ", " (builtins.filter (n: a.${n} != null) (builtins.attrNames a))' \
      2>/dev/null ) || true
}

guard_unguarded_fda() {
  local keys
  # Escape hatch: you said go. HAUS_AGENT_REBUILD is the name this had while the
  # guard was about agents — still honoured, since anything scripted against it
  # meant exactly this, and a silently-ignored override is the one failure an
  # escape hatch cannot have.
  [ -n "${HAUS_FDA_ANYWAY:-}${HAUS_AGENT_REBUILD:-}" ] && return 0
  has_fda && return 0                            # this app can write the domain
  keys="$(universalaccess_keys "$1")"
  [ -n "$keys" ] || return 0

  warn "refusing to rebuild — this config needs Full Disk Access and this app hasn't got it."
  cat >&2 <<EOF

  This config sets system.defaults.universalaccess:

      $keys

  macOS only lets an app holding Full Disk Access write that domain. The failure
  would not be contained: nix-darwin runs the write unguarded partway through
  activation, so it would abort there and skip every background service haus
  installs — the bar, the tiling, the palette.

  The grant follows the APP, not you and not root, so this is not about who is
  typing: an agent pane inside a terminal that has it rebuilds fine, and a human
  in a terminal that hasn't hits this same wall.

  Nothing has been changed. Any edit already made is still on disk. Two ways on:

    1. Move those keys to haus.accessibility.* — it reaches every key in that
       domain MEASURED to take effect, through a guarded write that degrades to
       "setting skipped" instead of a half-activated Mac, and it rebuilds from
       anywhere. This is the fix; the option exists for exactly this. Since
       2026-08-14 it covers ALL FIVE keys nix-darwin types here, cursor size and
       the closeView pair included, so there is nothing left that only route 2
       can say.

    2. Rebuild from an app that holds the grant (System Settings ▸ Privacy &
       Security ▸ Full Disk Access — on macOS 26 a stale entry often needs
       removing and re-adding with (+), then restarting the terminal):

           haus rebuild

  'haus doctor' reports whether this app has it. (Really meant it, and want the
  abort? HAUS_FDA_ANYWAY=1 haus rebuild.)
EOF
  exit 1
}

# Evaluate only — the .drv, not the build. Split from the build so the build's
# stderr can stay a terminal (see cmd_rebuild), and so evaluation's warnings are
# said once, into the log, instead of on your screen: nixpkgs' nixosOptionsDoc
# trips a `builtins.derivation … without a proper context` warning on every eval
# of any config that installs the agent skill, and it is not ours to fix.
resolve_drv() { ( cd "$CONSUMER" && nix eval --raw ".#darwinConfigurations.$1.system.drvPath" >"$2" ); }

closure_diff() { nix store diff-closures "$1" "$2" >"$3" 2>/dev/null || true; }

# The pre-haus-activate route, kept whole for the one rebuild that needs it.
legacy_switch() { ( cd "$CONSUMER" && sudo /run/current-system/sw/bin/darwin-rebuild switch --flake ".#$1" ); }

# ---- reversibility: plan / diff / capture / revert-settings ----------------
# A shared engine, because
# `haus plan` (what WOULD change) and `haus diff` (what's declared vs what
# macOS actually has right now) are the same comparison run against two
# different activation scripts — a fresh build for plan, the running system
# for diff.
#
# Ground truth is the BUILT activation script, not a hand-maintained map of
# nix-darwin's ~193 typed keys to plist domains: nix-darwin's own generator
# emits a uniform `defaults write DOMAIN KEY '<xml…>'` per key (verified
# against a real activate script, every one of the 47 this machine currently
# writes matches), so parsing that is ground truth that can't drift out from
# under an upstream change the way a hand-copied table would.

# TSV domain\tkey\tvalue for every `defaults write DOMAIN KEY '<?xml…'` block a
# built activation script contains. `-g` is normalised to `NSGlobalDomain` so
# callers never special-case it. `value` is plutil's rendering of the plist
# block, with any embedded newline (a dict/array value, e.g. Finder's
# FXInfoPanesExpanded) escaped to a literal `\n` — so this always emits exactly
# one TSV row per declared key, never a multi-line one a `read` loop would
# silently misparse into extra, bogus rows.
# `|| true` throughout: a key that isn't set, a domain with zero declared
# writes, a value plutil can't render — every one of these is a normal
# outcome, not a script error, and this runs (like the rest of haus.sh) under
# `set -euo pipefail`, which would otherwise abort the whole comparison on the
# first machine that doesn't happen to set every key this parses.
declared_defaults() {
  local f="$1" lineno rest domain key endline val
  # TWO shapes, not one, and the difference is the LEVEL the domain lives at.
  #
  #   USER defaults come through nix-darwin's `launchctl asuser … sudo --user=X --`
  #   wrapper, so the line has a literal ` -- ` before `defaults write`.
  #   SYSTEM defaults (`system.defaults.loginwindow.*`) are written bare, as root,
  #   to an absolute `/Library/Preferences/<domain>` path — activation is already
  #   root, so there is nothing to wrap.
  #
  # Matching only the first shape is how `haus.lock.login.*` and
  # `haus.security.guestAccount` were invisible to `haus diff` and `haus plan`
  # the day they shipped: six options that wrote correctly and that the checker
  # silently had no opinion about. Nothing looked wrong — a key nobody reports on
  # is indistinguishable from a key that agrees. So the pattern is anchored on
  # `defaults write` itself and the wrapper is optional.
  grep -nE -- "(^|[[:space:]]|--[[:space:]])defaults write .* '<\?xml" "$f" 2>/dev/null | while IFS=: read -r lineno rest; do
    domain="$(printf '%s' "$rest" | sed -E "s/.*defaults write (-g|[^ ]+) ([^ ]+) .*/\\1/")"
    key="$(printf '%s' "$rest" | sed -E "s/.*defaults write (-g|[^ ]+) ([^ ]+) .*/\\2/")"
    [ "$domain" = "-g" ] && domain="NSGlobalDomain"
    # Normalise the any-user level back to a bare domain name, so one domain is
    # never two rows: `live_value` knows how to read it, and `classify_key`
    # and modules/lib/*.nix are all keyed by the plain `com.apple.foo` spelling.
    domain="${domain##*/}"
    endline="$(awk -v s="$lineno" 'NR>=s && /<\/plist>/ {print NR; exit}' "$f")"
    [ -n "$endline" ] || continue
    val="$(
      sed -n "${lineno},${endline}p" "$f" \
        | sed -E "1s/^.*'(<\\?xml)/\\1/" \
        | sed -E "\$s/<\\/plist>'\$/<\\/plist>/" \
        | plutil -p - 2>/dev/null
    )" || true
    val="${val//$'\n'/\\n}"
    printf '%s\t%s\t%s\n' "$domain" "$key" "$val"
  done || true
}

# TSV domain\tkey\tvalue for core's own guarded accessibility writer (see
# modules/core/default.nix's `hausAccessibility` postActivation block) — a
# raw `defaults write` shell call carrying its own type flag, not the typed
# XML-plist shape declared_defaults parses, so it needs its own extraction.
declared_a11y_calls() {
  grep -E '^[[:space:]]*hausAccessibility [A-Za-z]+ -(bool|float) [^[:space:]]+[[:space:]]*$' "$1" 2>/dev/null \
    | while read -r _ key flag value; do
        # The writer carries `defaults write`'s own type flag since this domain
        # stopped being all-booleans (mouseDriverCursorSize, 2026-08-14). Only
        # -float needs anything doing to it: Nix stringifies 3.0 as "3.000000"
        # and `defaults read` prints "3", so canonicalise here rather than
        # letting a diff report a key as changed on every run forever. %g drops
        # the trailing zeros the same way macOS does — under LC_ALL=C, because
        # %g reads the decimal separator from the locale and a comma-separator
        # LC_NUMERIC would stop at the dot and turn 1.500000 into 1, causing
        # exactly the forever-changed diff this line exists to prevent.
        if [ "$flag" = -float ]; then
          value="$(LC_ALL=C printf '%g' "$value")"
        fi
        printf 'com.apple.universalaccess\t%s\t%s\n' "$key" "$value"
      done || true
}

# TSV for core's other guarded writer: haus.sound.alertSound. Same reason as
# the block above — it is a raw `defaults write … -string` call rather than the
# typed XML shape, because the write has to be skipped when the sound file is
# missing (an unresolvable path SILENCES the alert instead of falling back, and
# a pure-eval `builtins.pathExists` can't tell). Without this line `haus diff`
# would report a declared key as undeclared.
declared_alert_sound() {
  grep -E '^[[:space:]]*defaults write -g com\.apple\.sound\.beep\.sound -string ' "$1" 2>/dev/null \
    | sed -E 's/.*-string ([^ \\]+).*/NSGlobalDomain\tcom.apple.sound.beep.sound\t\1/' || true
}

# plutil's rendering → the same textual shape `defaults read` prints, so the
# two sides of a comparison need no further massaging. A value with an escaped
# `\n` (a dict/array — declared_defaults's escape marker, see above) is flagged
# rather than compared, since neither side of that comparison is a scalar.
normalize_declared() {
  case "$1" in
    *'\n'*) printf '%s' "__COMPLEX__" ;;
    true) echo 1 ;;
    false) echo 0 ;;
    \"*) local v="${1#\"}"; printf '%s\n' "${v%\"}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

live_value() { # <domain> <key> -> `defaults read`'s raw output, empty if unset
  # `|| true`: an unset key is the common case, not a script error — `defaults
  # read` exits non-zero for it, and this runs under `set -e`.
  local v
  if [ "$1" = "NSGlobalDomain" ]; then defaults read -g "$2" 2>/dev/null || true; return; fi
  v="$(defaults read "$1" "$2" 2>/dev/null || true)"
  # Fall through to the ANY-USER level when the user domain has nothing. A
  # SYSTEM default (`system.defaults.loginwindow.*`) is written by activation to
  # /Library/Preferences/<domain> as root, and `defaults read <domain>` — which
  # reads the invoking user's domain — does NOT see it. Reading only the first
  # level reports every one of those keys as unset, which is worse than not
  # reading them: `haus diff` would call a correctly applied setting missing, on
  # every machine, forever.
  #
  # This order, and not the reverse, because it is CFPreferences' own search
  # list: the user domain shadows the any-user level, so if somebody has set the
  # key for themselves in System Settings, THAT is the value macOS will act on
  # and therefore the one a diff should compare against.
  [ -n "$v" ] || v="$(defaults read "/Library/Preferences/$1" "$2" 2>/dev/null || true)"
  printf '%s' "$v"
}

# How to verify a declared key, per §4/§8's finding: some domains write and
# silently no-op, so a plist-only diff would call them "applied" when they
# aren't.
#   effective    — compare against hausax's NSWorkspace read, not the plist
#                  (the four universalaccess keys measured to write AND work)
#   noop         — com.apple.Accessibility: writes, changes nothing, ever
#   appearance   — NSGlobalDomain AppleInterfaceStyle: inert in BOTH directions
#                  (measured 2026-08-08 on 26.6), and worse than `noop` to diff,
#                  because the key IS where macOS mirrors the appearance it's
#                  showing — so a plist comparison would read back the write
#                  that did nothing and call it applied. There is a working
#                  lever; it just isn't this one. See modules/theme.
#   by-eye       — measured effective by a HUMAN on real hardware, with no API
#                  that can re-check it here (NSWorkspace reports no pointer size
#                  and no zoom state). Diffed against the plist like `plain`, and
#                  SAYS SO — the one thing it must never do is print the same
#                  confident line `effective` prints, because that line means
#                  "macOS itself agrees" and here nothing asked macOS.
#   unconfirmed  — other universalaccess keys: persist, effect never measured
#   plain        — everything else: the matrix's control group, plist is fine
classify_key() {
  case "$1" in
    com.apple.Accessibility) echo noop ;;
    NSGlobalDomain)
      case "$2" in
        AppleInterfaceStyle) echo appearance ;;
        *) echo plain ;;
      esac
      ;;
    com.apple.universalaccess)
      case "$2" in
        reduceMotion | reduceTransparency | increaseContrast | differentiateWithoutColor) echo effective ;;
        mouseDriverCursorSize | closeViewScrollWheelToggle | closeViewZoomFollowsFocus) echo by-eye ;;
        *) echo unconfirmed ;;
      esac
      ;;
    *) echo plain ;;
  esac
}

# The comparison itself: every declared key against what macOS actually has.
# Read-only, always — callers decide which activation script (a running system
# for `diff`, a freshly built one for `plan`) but this never writes anything.
settings_diff() {
  local script="$1" domain key declared_raw declared kind live
  local changed=0 matched=0 flagged=0 byeye=0
  local ax_json; ax_json="$(hausax 2>/dev/null || true)"
  # The differing keys are collected and drawn as ONE table after the loop
  # rather than printed as they are found. Two reasons, and the second is the
  # one that matters: four columns budgeted against the window instead of
  # `%-28s %-26s %-14s`, which reserves 68 cells plus gutters whatever is in
  # them and wraps every row in anything narrower; and the `info`/`warn` lines
  # this loop also emits are the tool talking about the check, so they belong
  # above the report rather than shuffled through it.
  if [ -n "$UI_READY" ]; then ui_table_clear; fi

  while IFS=$'\t' read -r domain key declared_raw; do
    [ -n "$domain" ] || continue
    declared="$(normalize_declared "$declared_raw")"
    kind="$(classify_key "$domain" "$key")"

    case "$kind" in
      effective)
        if [ -z "$ax_json" ]; then
          warn "$domain $key: declared $declared — can't verify (hausax unavailable)"
          flagged=$((flagged + 1))
          continue
        fi
        live="$(printf '%s' "$ax_json" | jq -r --arg k "$key" '.[$k]')" || true
        case "$live" in true) live=1 ;; false) live=0 ;; esac
        if [ "$declared" = "$live" ]; then
          matched=$((matched + 1))
        else
          bad "$domain $key: declared $declared, macOS effectively reports $live (NSWorkspace, not the plist)"
          changed=$((changed + 1))
        fi
        ;;
      noop)
        warn "$domain $key: declared $declared — this domain is a KNOWN SILENT NO-OP on macOS 26 (writes, no effect; see haus docs/macos-settings.md)"
        flagged=$((flagged + 1))
        ;;
      appearance)
        # Deliberately not diffed against the plist: this key is where macOS
        # MIRRORS the appearance it is showing, so reading it back reports the
        # inert write rather than the effect. hausax has the real answer.
        live=unknown
        if [ -n "$ax_json" ]; then
          live="$(printf '%s' "$ax_json" | jq -r '.appearance // "unknown"')" || live=unknown
        fi
        warn "$domain $key: declared $declared — writing this key is a KNOWN NO-OP in BOTH directions on macOS 26 (measured; the appearance system only mirrors it). macOS is effectively showing $live. Use haus.theme.systemAppearance instead."
        flagged=$((flagged + 1))
        ;;
      by-eye | unconfirmed | plain)
        if [ "$declared" = "__COMPLEX__" ]; then
          info "$domain $key: dict/array value — not diffed automatically"
          flagged=$((flagged + 1))
          continue
        fi
        live="$(live_value "$domain" "$key")"
        if [ "$declared" = "${live:-}" ]; then
          matched=$((matched + 1))
          [ "$kind" = unconfirmed ] && flagged=$((flagged + 1)) # matches, but a match here isn't proof it works
          if [ "$kind" = by-eye ]; then
            # Not flagged — this key backs a supported option and the plist
            # agreeing is the most any tool can establish for it. Said out loud
            # anyway: the `effective` arm above means "macOS itself agrees", and
            # a reader skimming a column of ticks would otherwise read this one
            # as the same claim.
            info "$domain $key: plist matches — nothing on this Mac can confirm the effect, so that is all this checked (measured by eye, macOS 26.6.1)"
          fi
        else
          if [ "$kind" = unconfirmed ]; then
            warn "$domain $key: declared $declared, plist shows ${live:-unset} (persists only — effect unconfirmed on this macOS)"
            flagged=$((flagged + 1))
          elif [ -n "$UI_READY" ]; then
            if [ "$kind" = by-eye ]; then byeye=1; ui_trow "$domain" "$key" "${live:-unset}" "$declared" "plist-only check"
            else ui_trow "$domain" "$key" "${live:-unset}" "$declared" ""; fi
          elif [ "$kind" = by-eye ]; then
            printf '  %-28s %-26s %-14s -> %s  (plist-only check)\n' "$domain" "$key" "${live:-unset}" "$declared"
          else
            printf '  %-28s %-26s %-14s -> %s\n' "$domain" "$key" "${live:-unset}" "$declared"
          fi
          changed=$((changed + 1))
        fi
        ;;
    esac
  done < <(declared_defaults "$script"; declared_a11y_calls "$script"; declared_alert_sound "$script")

  # Declared after the rows, which `ui_col` allows and which is what lets the
  # `plist-only check` column exist only on a run that has one: a column's
  # minimum is taken out of the window whether or not anything is ever drawn in
  # it. A row carries five cells either way; a table of four ignores the fifth.
  if [ -n "$UI_READY" ] && [ "$changed" -gt 0 ]; then
    ui_col domain   16 3 path    left
    ui_col key      12 3 subject right
    ui_col live      6 2 muted   right
    ui_col declared  6 2 accent  right
    if [ "$byeye" = 1 ]; then ui_col note 10 2 muted right; fi
    ui_table_data 2 1
  fi

  echo
  if [ "$changed" = 0 ]; then
    info "settings: live matches declared ($matched key(s))"
  else
    info "settings: $changed key(s) differ from live, $matched already match"
  fi
  [ "$flagged" -gt 0 ] && info "$flagged key(s) flagged above — unconfirmed effect, known no-op, or a value diff can't compare automatically"
}

# What a rebuild's Brewfile would newly install — the forward-looking half of
# cmd_doctor's declared-vs-installed check. Never removes anything to report:
# cleanup defaults to "none", so an uninstall is never silent either way.
plan_homebrew() {
  command -v brew >/dev/null 2>&1 || {
    info "no Homebrew on this machine yet — haus installs it on first activation"
    return 0
  }
  local sys="$1" brewfile declared installed toinstall
  # `|| true`: matches cmd_doctor's identical extraction below — a build with
  # no Brewfile line at all is a zero-match grep, not a script error.
  brewfile="$(grep -oE "brew bundle --file='[^']+'" "$sys/activate" 2>/dev/null | sed "s/.*--file='//;s/'\$//" || true)"
  if [ -z "$brewfile" ] || [ ! -f "$brewfile" ]; then
    info "no Brewfile in the new build"
    return 0
  fi
  declared="$(sed -nE 's/^cask "([^"]+)".*/\1/p' "$brewfile" | sed -E 's#.*/##')"
  installed="$(brew list --cask 2>/dev/null || true)"
  toinstall="$(comm -23 <(printf '%s\n' "$declared" | sort -u) <(printf '%s\n' "$installed" | sort -u) | grep . || true)"
  if [ -n "$toinstall" ]; then
    printf '  will install: %s\n' "$(printf '%s' "$toinstall" | paste -sd', ' -)"
  else
    info "no new casks to install"
  fi
  info "cleanup=none means nothing is ever removed automatically — 'haus doctor' flags undeclared casks"
}

# ---- which config did we just read? -----------------------------------------
# `haus` always evaluates $CONSUMER, never the directory you happen to be
# standing in. That is right for the everyday case (any pane, any cwd, one
# machine config) and silently wrong in exactly one: a LINKED GIT WORKTREE of
# the config itself, which is how an agent lane edits a host file. From in
# there, `haus plan` builds MAIN's config and then truthfully reports "nothing
# was changed" about a branch it never read — and `haus rebuild` would activate
# main while you believed you were feeling your branch. Nothing in the worktree
# is reachable from $CONSUMER, so the honest fix is to say which tree was read
# and name the way to point at this one.
consumer_worktree_warning() {
  local top common consumer ours
  command -v git >/dev/null 2>&1 || return 0
  # Every path here is resolved with cd+pwd -P before being compared. git reports
  # physical paths, $CONSUMER is whatever the environment said, and one symlinked
  # component anywhere in $HOME (or a /var → /private/var temp dir) is enough to
  # make two spellings of the same directory look like two directories — which
  # would silently switch this warning off in exactly the case it exists for.
  consumer="$(cd "${CONSUMER%/}" 2>/dev/null && pwd -P || true)"
  [ -n "$consumer" ] || return 0
  top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$top" ] || return 0
  top="$(cd "$top" 2>/dev/null && pwd -P || true)"
  [ -n "$top" ] || return 0
  [ "$top" != "$consumer" ] || return 0
  # The SHARED .git dir is what makes this another checkout of the config, rather
  # than an unrelated repo you happen to be sitting in. Asked of BOTH sides
  # rather than built as "$consumer/.git": a config that is a subdirectory of a
  # bigger dotfiles repo has its common dir at that repo's root, and comparing
  # against a constructed path would switch this warning off for exactly the
  # setup it exists for. It also covers $CONSUMER itself being a worktree.
  common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  [ -n "$common" ] || return 0
  common="$(cd "${common%/}" 2>/dev/null && pwd -P || true)"
  [ -n "$common" ] || return 0
  ours="$(git -C "$consumer" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  [ -n "$ours" ] || return 0
  ours="$(cd "${ours%/}" 2>/dev/null && pwd -P || true)"
  [ "$common" = "$ours" ] || return 0
  warn "this is a worktree of your config ($top), but haus reads \$CONSUMER — so it is reading $consumer, not the branch checked out here."
  # `hint`, not `info`: this is about the invocation, not part of any report, and
  # it has to sit under its own `warn` in both callers — `haus rebuild`, whose
  # output is all message stream, and `haus plan`, whose report is all fd 1.
  hint "to read THIS tree instead: HAUS_CONSUMER=$top haus <command>"
}

# ---- what a rebuild would write into $HOME ----------------------------------
# The other half of a haus rebuild, and the half `plan` was blind to until
# workshop#307: every file home-manager manages — the bar's items and plugins,
# the shell, the tiling config, the agent skills. None of it is a
# `system.defaults` key, so settings_diff cannot see it, and `nix store
# diff-closures` does not report it either: the whole tree lands under ONE
# store path whose name carries no version, and diff-closures only prints a
# same-name entry once its size has moved enough to notice. Switching on seven
# bar pills moved it 272 bytes, so `haus plan` said "nothing was changed"
# about a bar that was about to grow seven pills.
#
# Ground truth is the built tree, the same discipline declared_defaults uses on
# the activation script: walk home-files with the same `-type f -or -type l`
# find home-manager's own linkGeneration walks, so the set compared here is
# exactly the set that gets installed.

# <activate script> -> TSV user \t home-manager-generation store path.
# The chain nix-darwin emits per user, followed one hop at a time:
#   activate → …-activation-<user> → …-home-manager-generation/activate
# Read out of the script rather than picked out of the closure, because the
# closure knows nothing about WHICH user a generation belongs to — a Mac with
# two managed users would otherwise be compared against itself.
# Both paths are matched by SHAPE — a 32-character store hash plus the suffix
# nix-darwin/home-manager give it — rather than by a literal /nix/store prefix.
# The store dir is configurable, and matching the shape is also what lets
# test/haus-plan.sh check this against fixture scripts in a temp dir instead of
# needing a real built system, which no CI runner has.
hm_generations() {
  local wrapper user gen
  grep -oE '/[^ ]*/[a-z0-9]{32}-activation-[A-Za-z0-9_.-]+' "$1" 2>/dev/null | LC_ALL=C sort -u \
    | while read -r wrapper; do
        [ -f "$wrapper" ] || continue
        user="${wrapper##*-activation-}"
        gen="$(grep -oE '/[^ ]*/[a-z0-9]{32}-home-manager-generation' "$wrapper" 2>/dev/null | head -1 || true)"
        [ -n "$gen" ] || continue
        [ -d "$gen/home-files" ] || continue
        printf '%s\t%s\n' "$user" "$gen"
      done || true
}

# A content hash for the few entries in a home-files tree that are real files
# rather than symlinks into the store. Three spellings because this script is
# linted and tested on Linux and runs on macOS; `cksum` is the last resort and
# is only ever a weaker hash, never a wrong answer.
hash_file() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 -- "$1" | cut -d' ' -f1
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum -- "$1" | cut -d' ' -f1
  else cksum -- "$1" | cut -d' ' -f1
  fi
}

# TSV relpath \t l|f \t identity, for every file home-manager installs from one
# home-files tree. `find` is deliberately NOT given -L: a symlink to a store
# DIRECTORY (the sketchybar plugins dir, a Claude skill) is ONE managed entry,
# and descending into it would compare files home-manager never links
# individually — the same choice home-manager's own find makes. Identity is the
# symlink target, which is content-addressed, so a differing target is a
# differing file with no hashing needed for the 90% case.
hm_file_list() {
  local root p rel
  # Resolved with cd+pwd -P, because `home-files` is ITSELF a symlink into the
  # store: `find` without -L would stop at that one link and report a tree of
  # exactly one entry. Not `readlink -f`, which is a GNU extension this script
  # avoids everywhere else for the same reason (see now_ds).
  root="$(cd "${1%/}" 2>/dev/null && pwd -P || true)"
  [ -n "$root" ] || return 0
  find "$root" \( -type f -o -type l \) -print 2>/dev/null | while IFS= read -r p; do
    rel="${p#"$root"/}"
    if [ -L "$p" ]; then printf '%s\tl\t%s\n' "$rel" "$(readlink "$p" || true)"
    else printf '%s\tf\t%s\n' "$rel" "$(hash_file "$p" || true)"
    fi
  done || true
}

# The relative paths that carry an onChange hook, out of the BUILT home-manager
# activation script, which emits one `echo "Running onChange hook for" <path>`
# per hook. So this needs no table of which file reloads which daemon: bar
# hashes its whole bar config into one stamp file precisely so ONE hook fires
# when any of ~20 files move, and this reports that hook because the stamp is
# in the changed set — not because anything here knows what bar is.
hm_onchange_paths() {
  grep -oE 'Running onChange hook for" .+' "$1/activate" 2>/dev/null \
    | sed 's/^Running onChange hook for" //' || true
}

# The commands one hook runs, tidied for reading. home-manager wraps them in an
# `if [[ ! -v DRY_RUN ]]` inside the hook's own `if (( ${changedFiles[<path>]}
# == 1 ))` block, so the block is bounded by the path itself. The `== 1` is
# part of the match on purpose: the same subscript also appears earlier in the
# script, on the `_cmp` line that COMPUTES changedFiles, and matching that
# would print the comparison instead of the hook. Store paths are shortened to
# the binary's name and redirections dropped — this is a preview, not a script.
hm_onchange_cmds() {
  awk -v key="$2" '
    /== 1 \)\)/ && index($0, "changedFiles[" key "]") { inblock = 1; next }
    inblock && /^fi$/ { exit }
    inblock && /^[[:space:]]*(if|fi|echo)/ { next }
    inblock && NF {
      # A trailing backslash continues the command, so join before tidying —
      # home-managers font hook is a four-line rsync, and printing its lines
      # separately renders half an invocation as if it were the whole hook.
      line = line $0
      if (sub(/\\[[:space:]]*$/, "", line)) next
      print line; line = ""
    }
    END { if (line != "") print line }
  ' "$1/activate" 2>/dev/null \
    | sed -E 's#^[[:space:]]*##; s#^(run|\$DRY_RUN_CMD)[[:space:]]+##; s#^[^ ]*/##; s#[[:space:]]*(2>|>|\|\|).*$##' \
    | awk 'NR <= 2 { print (length > 72 ? substr($0, 1, 71) "…" : $0) } NR == 3 { print "…" }' || true
}

# How many changed files to name before summarising. A nixpkgs bump can move
# hundreds of managed files at once, and a preview that scrolls off the screen
# is the same as no preview.
FILE_CAP=25

plan_files_user() { # <user> <new home-manager-generation> <old generation or empty>
  local user="$1" newgen="$2" oldgen="$3"
  local newlist oldlist touched hooks mark rel cmds
  local added=0 removed=0 changed=0 shown=0 hooked=0

  if [ -z "$oldgen" ]; then
    info "$user: no home-manager generation in the running system — every managed file would be new"
    return 0
  fi

  newlist="$(mktemp)"; oldlist="$(mktemp)"; touched="$(mktemp)"; hooks="$(mktemp)"
  hm_file_list "$newgen/home-files" >"$newlist"
  hm_file_list "$oldgen/home-files" >"$oldlist"

  # FILENAME rather than the usual NR==FNR: an empty old list would make the
  # whole new list look like the first file and report every change as nothing.
  while IFS=$'\t' read -r mark rel; do
    [ -n "$rel" ] || continue
    case "$mark" in
      +) added=$((added + 1)) ;;
      -) removed=$((removed + 1)) ;;
      '~') changed=$((changed + 1)) ;;
    esac
    [ "$mark" = "-" ] || printf '%s\n' "$rel" >>"$touched"
    if [ "$shown" -lt "$FILE_CAP" ]; then
      printf '  %s %s\n' "$mark" "$rel"
      shown=$((shown + 1))
    fi
  done < <(
    awk -F'\t' -v OFS='\t' -v oldfile="$oldlist" '
      FILENAME == oldfile { kind[$1] = $2; id[$1] = $3; old[$1] = 1; next }
      {
        if (!($1 in old)) { print "+", $1; next }
        delete old[$1]
        if ($2 != kind[$1] || $3 != id[$1]) print "~", $1
      }
      END { for (p in old) print "-", p }
    ' "$oldlist" "$newlist" | LC_ALL=C sort -t"$(printf '\t')" -k2,2
  )

  if [ "$((added + changed + removed))" -gt "$shown" ]; then
    info "… and $((added + changed + removed - shown)) more"
  fi

  # Which onChange hooks that set would fire — the answer to "it landed on disk,
  # but will anything notice?" A KeepAlive daemon that read its config once at
  # boot (sketchybar, AeroSpace) keeps the old one in memory until its hook runs.
  hm_onchange_paths "$newgen" | LC_ALL=C sort -u >"$hooks"
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    cmds="$(hm_onchange_cmds "$newgen" "$rel" | awk '{ printf "%s%s", sep, $0; sep = " · " } END { print "" }' || true)"
    info "onChange: $rel → ${cmds:-a hook with no visible command}"
    hooked=$((hooked + 1))
  done < <(LC_ALL=C comm -12 "$hooks" <(LC_ALL=C sort -u "$touched"))

  if [ "$((added + changed + removed))" = 0 ]; then
    info "$user: no managed file would change ($(wc -l <"$newlist" | tr -d ' ') file(s) checked)"
  else
    info "$user: $changed changed, $added new, $removed removed — $hooked onChange hook(s) would fire"
  fi
  rm -f "$newlist" "$oldlist" "$touched" "$hooks"
}

plan_files() { # <new activate script> <the running system's activate script>
  local newgens oldgens user newgen oldgen
  newgens="$(hm_generations "$1")"
  if [ -z "$newgens" ]; then
    # Deliberately hedged rather than stated: a configuration genuinely without
    # home-manager and a chain this failed to follow (an upstream rename of the
    # `activation-<user>` wrapper, say) are indistinguishable from here, and
    # "there are none" would be a verdict where only one of the two is true.
    info "no home-manager generation found in this build — nothing to compare, or the activation chain has changed shape"
    return 0
  fi
  oldgens="$(hm_generations "$2")"
  while IFS=$'\t' read -r user newgen; do
    [ -n "$user" ] || continue
    oldgen="$(printf '%s\n' "$oldgens" | awk -F'\t' -v u="$user" '$1 == u { print $2; exit }')"
    plan_files_user "$user" "$newgen" "$oldgen"
  done < <(printf '%s\n' "$newgens")
}

# ---- which launchd jobs a rebuild would bounce ------------------------------
# Not a table of services: nix-darwin emits, per job,
#   if ! diff <the new plist in the store> <the installed plist>; then … reload
# so this runs that exact comparison read-only, one step early. A job whose
# plist is byte-identical is left alone by activation and reported unchanged
# here — which is precisely why a bar config change alone never restarts the
# bar (the plist didn't move), and why the onChange hook above is what makes it
# live. `~user/…` is expanded from the user database rather than by the shell:
# these paths come out of a generated script, and `eval`ing them to get a tilde
# expanded would be a needless hole.
expand_tilde() {
  local rest user tail home
  case "$1" in
    "~"*)
      rest="${1#\~}"; user="${rest%%/*}"; tail="${rest#*/}"
      home=""
      if command -v dscl >/dev/null 2>&1; then
        # Not `awk '{print $2}'`: a home directory containing a space would be
        # truncated at the first one, and every one of that user's agents would
        # then report "will create" against a path that isn't theirs.
        home="$(dscl . -read "/Users/$user" NFSHomeDirectory 2>/dev/null | sed -n 's/^NFSHomeDirectory: //p' | head -1 || true)"
      fi
      [ -n "$home" ] || home="$HOME"
      printf '%s/%s\n' "${home%/}" "$tail"
      ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# TSV job name \t new plist \t installed plist, for every launchd job an
# activation script guards with its own diff.
launchd_pairs() {
  sed -nE "s@^if ! diff '?([^' ]+)'? '?([^' ]+)'? &> /dev/null; then\$@\1\t\2@p" "$1" 2>/dev/null || true
}

plan_services() { # <new activate script> <the running system's activate script>
  local new inst name installed
  local reload="" create="" remove="" unchanged=0
  local newnames oldnames

  # A parse miss must never look like an answer. nix-darwin always ships at
  # least one daemon (org.nixos.activate-system), so zero guards means the shape
  # this reads has drifted — a bumped nix-darwin quoting that `if ! diff` line
  # differently. Without this the removal set below would be `comm -13 <empty>
  # <every running job>`, and plan would calmly announce that a rebuild is about
  # to unload the bar, the tiling and the palette. Saying "I could not read it"
  # is the only honest output there; silence that reads as a verdict is the
  # exact failure this whole section was added to end.
  if [ -z "$(launchd_pairs "$1")" ]; then
    warn "could not read any launchd guard out of this build — skipping the services preview (the activation script's shape has changed; this is a haus bug, not a machine problem)."
    return 0
  fi

  newnames="$(mktemp)"; oldnames="$(mktemp)"

  while IFS=$'\t' read -r new inst; do
    [ -n "$new" ] || continue
    name="$(basename "$new" .plist)"
    printf '%s\n' "$name" >>"$newnames"
    installed="$(expand_tilde "$inst")"
    if [ ! -e "$installed" ]; then
      create="$create${create:+, }$name"
    elif ! diff -q "$new" "$installed" >/dev/null 2>&1; then
      reload="$reload${reload:+, }$name"
    else
      unchanged=$((unchanged + 1))
    fi
  done < <(launchd_pairs "$1")

  # A job the new build no longer declares: activation unloads it. Read from the
  # OLD script's job list, since the new one has no line left to parse. Skipped
  # when the OLD script parses to nothing, for the mirror of the reason above: a
  # running system whose guards this cannot read would otherwise contribute no
  # names and quietly under-report a real removal.
  if [ -n "${2:-}" ] && [ -r "$2" ] && [ -n "$(launchd_pairs "$2")" ]; then
    launchd_pairs "$2" | cut -f1 | while IFS= read -r new; do basename "$new" .plist; done >"$oldnames"
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      remove="$remove${remove:+, }$name"
    done < <(LC_ALL=C comm -13 <(LC_ALL=C sort -u "$newnames") <(LC_ALL=C sort -u "$oldnames"))
  fi

  [ -z "$reload" ] || printf '  will reload: %s\n' "$reload"
  [ -z "$create" ] || printf '  will create: %s\n' "$create"
  [ -z "$remove" ] || printf '  will remove: %s\n' "$remove"
  if [ -z "$reload$create$remove" ]; then
    info "no launchd job would change ($unchanged checked)"
  else
    info "$unchanged other job(s) unchanged"
  fi
  rm -f "$newnames" "$oldnames"
}

# How activation makes the settings above live — read out of the built script
# rather than re-derived from modules/lib/restart-map.nix, so it cannot drift
# from what a rebuild actually runs (core renders that table into these exact
# calls). Unconditional by design, which is why this says "every rebuild"
# rather than "because a key changed": it is also the answer to why your Finder
# windows close.
plan_restarts() {
  local procs posts waits bits=""
  procs="$(grep -oE '^killall -qu [^ ]+ [A-Za-z]+' "$1" 2>/dev/null | awk '{ print $4 }' | LC_ALL=C sort -u | paste -sd, - || true)"
  posts="$(grep -oE "post-notification '?[A-Za-z0-9._-]+'?" "$1" 2>/dev/null | sed -E "s/post-notification '?//; s/'\$//" | LC_ALL=C sort -u | paste -sd, - || true)"
  [ -z "$procs" ] || bits="restarts ${procs//,/, }"
  if grep -q '"\$activateSettings" -u' "$1" 2>/dev/null; then
    bits="$bits${bits:+ · }broadcasts activateSettings"
  fi
  [ -z "$posts" ] || bits="$bits${bits:+ · }posts ${posts//,/, }"
  [ -z "$bits" ] || info "every rebuild also $bits"

  # And the half a restart CANNOT cover. core emits this line for any domain the
  # built configuration writes that macOS re-reads only at login, so the reader
  # stays "grep the built script" rather than a second copy of restart-map.nix.
  # Its own warning, not appended to the line above, because it is the opposite
  # kind of news: that one says what will happen, this one says what won't.
  waits="$(grep -oE 'haus: waits-for-logout [^"]+' "$1" 2>/dev/null | sed -E 's/^haus: waits-for-logout //' | tr ' ' '\n' | grep . | LC_ALL=C sort -u | paste -sd, - || true)"
  [ -z "$waits" ] || warn "waits for a logout — no live-reload path on macOS 26: ${waits//,/, }"
}

# The announcement core renders from modules/lib/reachability.nix — read the same
# way plan_restarts reads the restart map's, out of the BUILT script rather than
# from a second copy of the table.
#
# This is the front door §5.12 asked for. Full Disk Access is the one property
# that makes byte-identical config behave differently on two machines, and the
# only honest moment to say so is BEFORE the rebuild: `haus plan` never runs the
# script it greps, so it can report a grant this app hasn't got without paying
# for finding out the hard way. Each verdict is a different kind of news, so each
# gets its own line and its own severity.
plan_permissions() {
  local guarded unguarded noop
  guarded="$(_haus_verdict needs-full-disk-access "$1")"
  unguarded="$(_haus_verdict aborts-without-full-disk-access "$1")"
  noop="$(_haus_verdict writes-but-does-nothing "$1")"

  if [ -n "$unguarded" ]; then
    # The only one that can break the machine rather than the setting, so it
    # says which way it goes on THIS app rather than describing the hazard in
    # the abstract. `haus rebuild` refuses this combination outright.
    if has_fda; then
      info "needs Full Disk Access, unguarded — this app has it, so it will apply: ${unguarded//,/, }"
    else
      bad "would ABORT activation — ${unguarded//,/, } is written unguarded and this app has no Full Disk Access; every service after it would be skipped. Move those keys to haus.accessibility.*, or rebuild from an app that holds the grant."
    fi
  fi

  if [ -n "$guarded" ]; then
    if has_fda; then
      info "needs Full Disk Access — this app has it: ${guarded//,/, }"
    else
      warn "needs Full Disk Access, which this app hasn't got — these settings will be skipped and nothing else is affected: ${guarded//,/, }"
    fi
  fi

  [ -z "$noop" ] || warn "writes and changes nothing on macOS 26 — the plist will read back correct anyway: ${noop//,/, }"
}

# One `haus: <verdict> <domain>…` line out of a built activation script, as a
# comma-separated list. Shared by plan_permissions and doctor so the grep shape
# is written once; `|| true` throughout because a configuration with no such
# line is the common case, not an error, under this script's `set -e`.
_haus_verdict() {
  grep -oE "haus: $1 [^\"]+" "$2" 2>/dev/null \
    | sed -E "s/^haus: $1 //" | tr ' ' '\n' | grep . | LC_ALL=C sort -u | paste -sd, - || true
}

cmd_plan() {
  local host drvfile drvpath sysfile sys difffile
  host="$(host_name)"
  say "$host · plan — a preview of 'haus rebuild' (read-only; nothing is built into place)"
  info "from $CONSUMER"
  consumer_worktree_warning
  [ -n "$VERBOSE" ] || echo
  log_open "plan $host from $CONSUMER"

  drvfile="$(mktemp)"
  run_phase resolve heal resolve_drv "$host" "$drvfile" || die "evaluation failed — nothing was changed."
  drvpath="$(cat "$drvfile")"
  rm -f "$drvfile"
  phase_ok resolve "$HAUS_PHASE_ELAPSED"
  # resolve is this command's only phase, and everything below is the report:
  # `nix build`'s progress on fd 2, then echo / sed / say on fd 1. Drop the
  # coprocess here rather than leaving it open across all of it — outside a
  # region a line it drew (a `die`, the one verb a report still sends through
  # it) would land among lines this script printed itself.
  snug_close

  sysfile="$(mktemp)"
  if ! (cd "$CONSUMER" && nix build --no-link --print-out-paths "$drvpath^*") >"$sysfile"; then
    rm -f "$sysfile"
    die "build failed — plan needs a successful build to know what would change."
  fi
  sys="$(cat "$sysfile")"
  rm -f "$sysfile"

  echo
  say "packages"
  difffile="$(mktemp)"
  closure_diff /run/current-system "$sys" "$difffile"
  if [ -s "$difffile" ]; then sed 's/^/  /' "$difffile"; else info "no package changes"; fi
  rm -f "$difffile"

  echo
  say "settings"
  settings_diff "$sys/activate"
  plan_restarts "$sys/activate"
  plan_permissions "$sys/activate"

  # Everything home-manager writes into $HOME, which is most of haus and
  # none of the two sections above. See plan_files's header for why neither the
  # closure diff nor the settings diff can see a bar pill being switched on.
  echo
  say "files"
  plan_files "$sys/activate" /run/current-system/activate

  echo
  say "services"
  plan_services "$sys/activate" /run/current-system/activate

  echo
  say "homebrew"
  plan_homebrew "$sys"

  echo
  # NOT "nothing was changed", which is what this said until workshop#307: read
  # directly under a files section listing ten changed files, that sentence
  # reads as "your edit does nothing" rather than "this command changed
  # nothing", and it was the line that made a real change look like a no-op.
  info "this was a preview — nothing on this machine was touched. Apply it with: haus rebuild"
}

cmd_diff() {
  say "declared vs live — the config currently ACTIVE on this machine against what macOS actually has"
  [ -x /run/current-system/activate ] || die "no running system to compare against — haus rebuild first."
  echo
  settings_diff /run/current-system/activate
}

# ---- haus capture ------------------------------------------------------------
# Turn THIS Mac's current settings into pasteable haus host-config lines —
# the general form of bootstrap.sh's HAUS_KEEP (which only ever runs once,
# at install). bootstrap.sh keeps its own copy of this logic rather than
# depending on `haus`: it runs before the first switch, when `haus` isn't on
# PATH yet.
#
# Every domain this reads is ALSO snapshotted raw (`defaults export`), so a
# later `haus revert-settings` can put the exact bytes back — this is the
# "pre-activation preference snapshot" §5.11 asks for: run `haus capture`
# before a rebuild that's about to change settings you might want to keep.
SNAP_BASE="${XDG_STATE_HOME:-$HOME/.local/state}/haus/settings-snapshots"

cap_bool() { case "$(defaults read "$1" "$2" 2>/dev/null || true)" in 1) echo true ;; 0) echo false ;; esac; }
cap_int() {
  local v
  v="$(defaults read "$1" "$2" 2>/dev/null || true)"
  case "$v" in '' | *[!0-9-]*) : ;; *) echo "$v" ;; esac
}
cap_str() {
  local v
  v="$(defaults read "$1" "$2" 2>/dev/null || true)"
  [ -n "$v" ] && printf '"%s"' "$v"
}
cap_emit() { [ -n "${2:-}" ] && printf '  system.defaults.%s = %s;\n' "$1" "$2"; }

capture_dock() {
  cap_emit dock.autohide "$(cap_bool com.apple.dock autohide)"
  cap_emit dock.orientation "$(cap_str com.apple.dock orientation)"
  cap_emit dock.show-recents "$(cap_bool com.apple.dock show-recents)"
  cap_emit dock.mru-spaces "$(cap_bool com.apple.dock mru-spaces)"
}

capture_keyboard() {
  cap_emit NSGlobalDomain.KeyRepeat "$(cap_int NSGlobalDomain KeyRepeat)"
  cap_emit NSGlobalDomain.InitialKeyRepeat "$(cap_int NSGlobalDomain InitialKeyRepeat)"
  cap_emit NSGlobalDomain.ApplePressAndHoldEnabled "$(cap_bool NSGlobalDomain ApplePressAndHoldEnabled)"
  local kbdui; kbdui="$(cap_int NSGlobalDomain AppleKeyboardUIMode)"
  case "$kbdui" in 0 | 2 | 3) cap_emit NSGlobalDomain.AppleKeyboardUIMode "$kbdui" ;; esac
}

capture_finder() {
  local ext; ext="$(cap_bool NSGlobalDomain AppleShowAllExtensions)"
  cap_emit finder.AppleShowAllExtensions "$ext"
  cap_emit NSGlobalDomain.AppleShowAllExtensions "$ext"
  cap_emit finder.AppleShowAllFiles "$(cap_bool com.apple.finder AppleShowAllFiles)"
  cap_emit finder.FXPreferredViewStyle "$(cap_str com.apple.finder FXPreferredViewStyle)"
  cap_emit finder.ShowPathbar "$(cap_bool com.apple.finder ShowPathbar)"
  cap_emit finder.ShowStatusBar "$(cap_bool com.apple.finder ShowStatusBar)"
  cap_emit finder._FXSortFoldersFirst "$(cap_bool com.apple.finder _FXSortFoldersFirst)"
  cap_emit finder._FXSortFoldersFirstOnDesktop "$(cap_bool com.apple.finder _FXSortFoldersFirstOnDesktop)"
  cap_emit finder._FXShowPosixPathInTitle "$(cap_bool com.apple.finder _FXShowPosixPathInTitle)"
  cap_emit finder._FXEnableColumnAutoSizing "$(cap_bool com.apple.finder _FXEnableColumnAutoSizing)"
  cap_emit finder.FXDefaultSearchScope "$(cap_str com.apple.finder FXDefaultSearchScope)"
  cap_emit finder.FXEnableExtensionChangeWarning "$(cap_bool com.apple.finder FXEnableExtensionChangeWarning)"
  cap_emit finder.QuitMenuItem "$(cap_bool com.apple.finder QuitMenuItem)"
  cap_emit finder.ShowHardDrivesOnDesktop "$(cap_bool com.apple.finder ShowHardDrivesOnDesktop)"
  cap_emit finder.ShowExternalHardDrivesOnDesktop "$(cap_bool com.apple.finder ShowExternalHardDrivesOnDesktop)"
  cap_emit finder.ShowMountedServersOnDesktop "$(cap_bool com.apple.finder ShowMountedServersOnDesktop)"
  cap_emit finder.ShowRemovableMediaOnDesktop "$(cap_bool com.apple.finder ShowRemovableMediaOnDesktop)"
  local nwt=""
  case "$(defaults read com.apple.finder NewWindowTarget 2>/dev/null || true)" in
    PfCm) nwt='"Computer"' ;; PfVo) nwt='"OS volume"' ;;
    PfHm) nwt='"Home"' ;; PfDe) nwt='"Desktop"' ;;
    PfDo) nwt='"Documents"' ;; PfID) nwt='"iCloud Drive"' ;;
    PfLo) : ;; # "Other" needs NewWindowTargetPath too — leave both to haus
    Recents | "") : ;;
    *) nwt='"Recents"' ;;
  esac
  cap_emit finder.NewWindowTarget "$nwt"
  cap_emit NSGlobalDomain.NSTableViewDefaultSizeMode "$(cap_int NSGlobalDomain NSTableViewDefaultSizeMode)"
  cap_emit NSGlobalDomain.NSNavPanelExpandedStateForSaveMode "$(cap_bool NSGlobalDomain NSNavPanelExpandedStateForSaveMode)"
  cap_emit NSGlobalDomain.NSNavPanelExpandedStateForSaveMode2 "$(cap_bool NSGlobalDomain NSNavPanelExpandedStateForSaveMode2)"
  cap_emit NSGlobalDomain.NSDocumentSaveNewDocumentsToCloud "$(cap_bool NSGlobalDomain NSDocumentSaveNewDocumentsToCloud)"
}

# Any other domain: not a friendly category, so there's no known nix-darwin
# attribute path for it — but system.defaults.CustomUserPreferences takes a
# raw plist domain directly, which is exactly what this is. Nested (array or
# dict) values are called out rather than emitted, since JSON's `[a, b]` isn't
# valid nix list syntax (`[ a b ]`) and silently emitting it would be a nix
# file that doesn't evaluate.
capture_domain_block() {
  local domain="$1" json body
  json="$(defaults export "$domain" - 2>/dev/null | plutil -convert json -o - - 2>/dev/null)" || return 0
  [ -n "$json" ] && [ "$json" != "null" ] && [ "$json" != "{}" ] || return 0
  # Rendered into a variable first, not streamed straight to stdout: a jq
  # failure must skip the WHOLE domain, not print an opening `= {` with no
  # closing `};` (a truncated block would be worse than the domain missing).
  body="$(
    printf '%s\n' "$json" | jq -r '
      to_entries[] |
      if (.value | type) == "array" or (.value | type) == "object"
      then "    # " + .key + " — nested value, add it by hand if you need it"
      else "    " + (.key | @json) + " = " + (.value | tojson) + ";"
      end
    '
  )" || return 0
  printf '  system.defaults.CustomUserPreferences."%s" = {\n%s\n  };\n' "$domain" "$body"
}

cmd_capture() {
  local cats=("$@") cat lines="" domains=() cats_used=()
  [ "${#cats[@]}" -gt 0 ] || cats=(dock keyboard finder)

  for cat in "${cats[@]}"; do
    case "$cat" in
      dock) lines+="$(capture_dock)"$'\n'; domains+=(com.apple.dock); cats_used+=("$cat") ;;
      keyboard) lines+="$(capture_keyboard)"$'\n'; domains+=(NSGlobalDomain); cats_used+=("$cat") ;;
      finder) lines+="$(capture_finder)"$'\n'; domains+=(com.apple.finder NSGlobalDomain); cats_used+=("$cat") ;;
      *.*) lines+="$(capture_domain_block "$cat")"$'\n'; domains+=("$cat"); cats_used+=("$cat") ;;
      *) die "unknown capture category '$cat' — try: dock keyboard finder, or a literal domain like com.apple.Terminal" ;;
    esac
  done

  # De-dupe (finder and keyboard both touch NSGlobalDomain).
  local uniq_domains=() d s seen
  for d in "${domains[@]}"; do
    seen=""
    for s in ${uniq_domains[@]+"${uniq_domains[@]}"}; do [ "$s" = "$d" ] && seen=1; done
    [ -n "$seen" ] || uniq_domains+=("$d")
  done

  local ts snapdir
  ts="$(date -u '+%Y%m%dT%H%M%SZ')"
  snapdir="$SNAP_BASE/$ts"
  mkdir -p "$snapdir"
  : >"$snapdir/manifest.tsv"
  for d in "${uniq_domains[@]}"; do
    if defaults export "$d" "$snapdir/$(printf '%s' "$d" | tr '/' '_').plist" 2>/dev/null; then
      printf '%s\t%s\n' "$d" "$snapdir/$(printf '%s' "$d" | tr '/' '_').plist" >>"$snapdir/manifest.tsv"
    else
      warn "couldn't export $d (empty or unreadable domain) — not in the snapshot"
    fi
  done
  ln -sfn "$ts" "$SNAP_BASE/latest"

  say "captured $(IFS=,; echo "${cats_used[*]}") — snapshot: $snapdir"
  echo
  printf '%s' "$lines"
  echo
  info "paste what you want into your host file — a line you don't paste means 'use haus's default'."
  info "the snapshot above is what 'haus revert-settings' puts back if you don't like where a rebuild takes this."
}

# ---- haus revert-settings ----------------------------------------------------
# The installer already admits Nix rollback doesn't undo macOS defaults —
# `haus rollback` rewinds every package and launchd agent, atomically, but a
# Dock or Finder preference just sits there. This is the other half: restore
# the exact snapshot `haus capture` took, byte for byte (`defaults import`,
# not a replay of individual key writes), then make it live the same way core's
# own postActivation does — a Dock/Finder/universalaccessd restart plus
# activateSettings, so nothing waits for a logout.
cmd_revert_settings() {
  local which="${1:-latest}" snapdir domain file rc=0 touched_dock="" touched_finder="" touched_ua=""

  if [ "$which" = "list" ]; then
    if [ ! -d "$SNAP_BASE" ]; then
      info "no snapshots yet — run 'haus capture' first."
      return 0
    fi
    say "settings snapshots ($SNAP_BASE):"
    local latest d name
    latest="$(readlink "$SNAP_BASE/latest" 2>/dev/null || true)"
    for d in "$SNAP_BASE"/*/; do
      [ -d "$d" ] || continue
      name="$(basename "$d")"
      [ "$name" = latest ] && continue # the symlink alias, not a snapshot of its own
      printf '  %s%s\n' "$name" "$([ "$name" = "$latest" ] && echo '  (latest)' || echo '')"
    done
    return 0
  fi

  snapdir="$SNAP_BASE/$which"
  [ -d "$snapdir" ] || die "no snapshot '$which' — try 'haus revert-settings list'."
  [ -f "$snapdir/manifest.tsv" ] || die "$snapdir has no manifest.tsv — was it written by 'haus capture'?"

  say "restoring settings from $snapdir"
  while IFS=$'\t' read -r domain file; do
    [ -n "$domain" ] || continue
    if { [ "$domain" = com.apple.universalaccess ] || [ "$domain" = com.apple.Accessibility ]; } && ! has_fda; then
      warn "$domain needs Full Disk Access on this app to restore — skipped (run from a terminal that has it)"
      continue
    fi
    if defaults import "$domain" "$file" 2>/dev/null; then
      ok "$domain restored"
      [ "$domain" = com.apple.dock ] && touched_dock=1
      [ "$domain" = com.apple.finder ] && touched_finder=1
      [ "$domain" = com.apple.universalaccess ] && touched_ua=1
    else
      bad "$domain: restore failed"
      rc=1
    fi
  done <"$snapdir/manifest.tsv"

  # `|| true` on every one of these: a `defaults write`-triggered restart is
  # allowed to no-op (Dock/Finder not running, activateSettings missing on a
  # future macOS) without aborting the rest of this command under `set -e` —
  # same convention modules/core/default.nix uses for the identical calls.
  [ -n "$touched_dock" ] && { killall -qu "$(id -un)" Dock 2>/dev/null || true; }
  [ -n "$touched_finder" ] && { killall -qu "$(id -un)" Finder 2>/dev/null || true; }
  # universalaccessd for the same reason as the two above, added 2026-08-14:
  # cursor size and the closeView pair are invisible until this daemon rereads
  # the domain, so a restore without it puts the bytes back and shows the user
  # nothing until their next logout — the failure this whole command exists to
  # avoid. Unconditional on the domain rather than per-key: `defaults import`
  # replaces the whole plist, so which keys moved isn't knowable here.
  [ -n "$touched_ua" ] && { killall -qu "$(id -un)" universalaccessd 2>/dev/null || true; }

  # Same broadcast core's postActivation makes after writing preferences — run
  # as ourselves (not root, so no launchctl-asuser wrapping needed here).
  local activateSettings=/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings
  [ -x "$activateSettings" ] && { "$activateSettings" -u 2>/dev/null || true; }

  if [ "$rc" = 0 ]; then say "restored."; else warn "some domains failed to restore — see above."; fi
  return "$rc"
}

# ---- one card for the whole rebuild -----------------------------------------
# On a Mac running trill, `haus rebuild` draws a single banner that fills up as
# the build goes — the answer to "is it done yet" once you have looked away.
# All of it soft: no trill, no card, no error, no delay, and HAUS_NO_BANNER=1
# turns it off.
#
# It reads the STORE, never nix's output. The build phase keeps the terminal on
# purpose (see below), and taking its stderr to parse `--log-format
# internal-json` would quietly cost you nix's own progress bar — the one thing
# that phase exists to show. So `--dry-run` lists the paths this rebuild needs
# and a poller counts how many have appeared: same numbers, nothing of nix's
# borrowed.
#
# That dry run happens BEFORE the build and in this shell, never beside it.
# Measured 2026-08-25 in bench, which carries the same block: a `nix build
# --dry-run` racing the real `nix build` over the same dirty flake made the
# build exit non-zero with nothing printed, one run in three. Serial is free
# here because the derivation is already resolved — 0.05 s measured, a store
# query rather than an evaluation. (Cold, with nothing of this closure in the
# narinfo cache, it is a substituter query pass and can take longer; it is still
# work the build itself would do a second later.)
#
# The card is keyed, so every tick REPLACES it rather than stacking a second
# banner, and the poll doubles as the heartbeat that keeps it on screen —
# trill's dismiss clock is short by design, and a card nobody re-sends leaves.
# That is what `card_hold` is for: the two stretches with no paths to count
# (homebrew fetching, activation) still need a re-send every two seconds.
#
# The card must keep finding trill at RUNTIME (`trill_bin`), never through
# `pkgs.trill`: `haus.notifications.compositor` is off by default, so wiring a
# rebuild's own progress bar to that room would make it depend on a room nobody
# turned on.
# This finds whatever the machine already has, or draws nothing.
CARD_KEY=""
CARD_TITLE=""
CARD_PID=""
# The generation that was current when the rebuild started — what a cancelled
# run points the user back at.
CARD_GEN=""
# The pid the poller watches: it exits with us even when we die by a signal
# nothing can trap, so a kill -9'd build can't leave a banner ticking forever.
CARD_PARENT="$$"
# How many store paths this build needs, and which — measured once, up front.
# Zero means there was never anything to watch.
CARD_TOTAL=0
CARD_PATHS=()

# Same search scruff's `notify` does (internal/commands/notify.go, `trillBinary`),
# for the same reason: Trill.app is routinely installed while `trill` is on
# nobody's PATH, because the app binary IS the CLI. `HAUS_TRILL` is authoritative
# when set — including set to something that isn't there, which is how a machine
# says "no banners".
#
# The two bundle paths are /Applications first, and the argument for that is
# modules/core/trill.sh's, written out where the wrapper resolves: a dev build
# left in ~/Applications by trill's own dev-install would otherwise outrank the
# bundle haus.notifications.compositor pins, on every rebuild, silently. The two
# copies of that precedence live in this repo and MUST agree — test/trill-
# precedence.bats diffs this list against the wrapper's so they cannot drift.
#
# scruff's list (internal/commands/notify.go) is still home-first, and the honest
# reason it isn't fixed here is that it is a different repo, not that it can
# never fire. `exec.LookPath("trill")` and the `command -v trill` below both find
# this wrapper whenever the system profile is on PATH — every login shell, and so
# every agent hook that inherits one — and that is why this tail is a fallback
# rather than the answer. It is NOT unreachable: a launchd context that sets its
# own PATH has no `trill` to look up and falls through to the bundles, which is
# precisely why the two lines below had to be flipped too. The same gap is live
# in scruff, where it would drive a stale daemon while haus drove the pinned one;
# tracked, not fixed here.
trill_bin() {
  local candidate
  if [ -n "${HAUS_TRILL:-}" ]; then
    [ -x "$HAUS_TRILL" ] && { printf '%s' "$HAUS_TRILL"; return 0; }
    return 1
  fi
  for candidate in \
      "$(command -v trill 2>/dev/null || true)" \
      "/Applications/Trill.app/Contents/MacOS/Trill" \
      "$HOME/Applications/Trill.app/Contents/MacOS/Trill"; do
    [ -n "$candidate" ] && [ -x "$candidate" ] && { printf '%s' "$candidate"; return 0; }
  done
  return 1
}

# Was there ever anything to watch? A build with nothing to do is over before
# you could look away, and a lone "done" banner for it is noise — so no bar, no
# card. A failure is the exception: that one you want either way.
card_drawn() { [ "$CARD_TOTAL" -gt 0 ]; }

# card <percent|-> <kind|-> <body>. Never fails, never blocks: a banner is a
# courtesy, and a build that stopped because one didn't draw would be absurd.
card() {
  [ -n "${HAUS_NO_BANNER:-}" ] && return 0
  [ -n "$CARD_KEY" ] || return 0
  [ "$2" = fault ] || card_drawn || return 0
  local bin args=()
  bin="$(trill_bin)" || return 0
  args=(send --key "$CARD_KEY" --source haus --title "$CARD_TITLE" --body "$3")
  [ "$1" = - ] || args+=(--progress "$1%")
  [ "$2" = - ] || args+=(--kind "$2")
  "$bin" "${args[@]}" >/dev/null 2>&1 || true
  return 0
}

# The paths this build still needs: derivations it will build (whose outputs we
# ask the store for) plus paths it will fetch (already store paths). The two
# globs are the whole contract with nix's output — if a future nix changes the
# indentation or prints `…drv^out`, this quietly finds nothing and no card is
# drawn, which is the safe direction to fail in. Verified against Determinate
# Nix 3.15.1 / 2.33.0, 2026-08-25.
card_targets() {
  local line drvs=()
  while IFS= read -r line; do
    case "$line" in
      "  /nix/store/"*.drv) drvs+=("${line#"  "}") ;;
      "  /nix/store/"*)     printf '%s\n' "${line#"  "}" ;;
    esac
  done < <(cd "$CONSUMER" && nix build --dry-run "$@" 2>&1)
  [ "${#drvs[@]}" -gt 0 ] && nix-store -q --outputs "${drvs[@]}" 2>/dev/null
  return 0
}

# The background half, and the only part that runs beside the build: counting
# files. No nix, no evaluation, nothing that can contend with the real one.
card_ticker() {
  local path done_n pct
  while kill -0 "$CARD_PARENT" 2>/dev/null; do
    done_n=0
    for path in "${CARD_PATHS[@]}"; do [ -e "$path" ] && done_n=$((done_n + 1)); done
    # Capped at 99 while the build runs: the ending owns 100, and a card
    # reading done while nix is still going is the one number nobody forgives.
    pct=$(( done_n * 100 / CARD_TOTAL )); [ "$pct" -gt 99 ] && pct=99
    # Re-sent even when the count hasn't moved — that is the heartbeat.
    card "$pct" "pulse" "$done_n/$CARD_TOTAL paths"
    sleep 2
  done
}

# The same heartbeat for a phase that has no paths to count — homebrew fetching
# in the background, activation running as root. Without it the card would be
# gone before the longest silent stretch of the job ended: trill's dismiss clock
# is short by design, and only a re-send holds a card on screen.
card_hold() { # card_hold <percent> <body>
  card_stop
  card_drawn || return 0
  [ -n "$CARD_KEY" ] || return 0
  card "$1" "pulse" "$2"
  # snug_detach first: this loop outlives every phase and exits only when the
  # parent does, so a copy of the write end here is the deadlock snug_detach
  # exists for — and this is the ticker that is live across `activate`.
  ( snug_detach; while kill -0 "$CARD_PARENT" 2>/dev/null; do sleep 2; card "$1" "pulse" "$2"; done ) &
  CARD_PID="$!"
  return 0
}

card_watch() { # card_watch <installable> [nix args…] — measure now, poll after
  [ -n "${HAUS_NO_BANNER:-}" ] && return 0
  [ -n "$CARD_KEY" ] || return 0
  trill_bin >/dev/null || return 0
  local path
  CARD_PATHS=()
  while IFS= read -r path; do [ -n "$path" ] && CARD_PATHS+=("$path"); done < <(card_targets "$@")
  CARD_TOTAL="${#CARD_PATHS[@]}"
  [ "$CARD_TOTAL" -gt 0 ] || return 0
  { snug_detach; card_ticker; } & CARD_PID="$!"
  return 0
}

card_stop() {
  [ -n "$CARD_PID" ] || return 0
  # `|| true` because the poller may already be gone: a bare `kill` that returns
  # 1 aborts this function under `set -e`, and from the EXIT trap that becomes
  # the whole rebuild's exit status.
  kill "$CARD_PID" 2>/dev/null || true
  # Reaped, not just signalled: a `trill send` the poller had already forked
  # would otherwise land after the ending card and supersede it, leaving "99%"
  # on screen for a build that finished.
  wait "$CARD_PID" 2>/dev/null || true
  CARD_PID=""
  return 0
}

# ⌃C is not a failure and not a success; it is a question that stopped being
# asked. Say so and leave, rather than letting the bar sit there claiming a
# build is in flight.
card_cancelled() {
  card_stop
  # Take the live region down before anything else prints: the spin loop would
  # otherwise keep painting frames over the cancellation for the tenth of a
  # second it takes to notice this shell is gone.
  phase_spin_stop
  snug_end
  card - "fault" "cancelled"
  # A ⌃C during activation leaves the same half-applied state the activation
  # failure path warns about, so say the same thing rather than exiting mute.
  warn "cancelled — if activation had started, generation ${CARD_GEN:-?} is still on disk (haus rollback)."
  exit 130
}

# `haus fix` — hand the last failed rebuild to a coding agent. One line of
# dispatch and nothing else: everything about WHICH agent, what it is told and
# what it is allowed to do belongs to the AI room (modules/ai/fix.sh), which is
# also the only room that knows whether this machine has agents at all. This
# file's whole share of that question is the `command -v` below.
cmd_fix() {
  command -v haus-fix >/dev/null 2>&1 \
    || die "no fixer on this machine — \`haus fix\` comes with the AI room (haus.ai.enable = true, then haus rebuild)."
  exec haus-fix "$@"
}

# ---- the fix-it-with-AI CTA -------------------------------------------------
# A rebuild that fails leaves you holding a nix trace and a machine that did not
# change. The three ways out are all the same shape — read the error, find what
# in $CONSUMER caused it, change that — and it is work a coding agent does well
# from a standing start, because everything it needs (the failing phase, the log
# slice, what changed since the last good rebuild) is already written down by
# the time we get here.
#
# So: write that down where a cold process can find it, then put ONE offer in
# front of the person. The offer runs `haus fix`, which is a line of dispatch
# onto `haus-fix` — a binary the AI ROOM installs. That is the whole coupling,
# and it is deliberately a `command -v`: core may not read `config.haus.ai.*`
# (AGENTS.md), so this file cannot know whether agents are configured, only
# whether a fixer is on PATH. No fixer, no offer, and the error prints exactly
# as it always did.
#
# What the CTA needs, all four or it stays quiet:
#   a fixer          `haus-fix`, from the AI room
#   an undo          $CONSUMER is a git repo, so the agent's whole change is one
#                    `git -C $CONSUMER revert HEAD` — see modules/ai/fix.sh
#   a surface        a pane you are looking at, or a trill that answers
#   your consent     HAUS_NO_FIX=1 turns the whole thing off
FAULT_HOST=""   # the host this rebuild was for
FAULT_DRV=""    # the system derivation, once we have one — the build phase's
                # only evidence, since that phase writes nothing to the log

# What `haus fix` reads: plain KEY=value, no newlines in any value, and read
# back by name rather than sourced — a state file that can execute is a state
# file that can be made to execute something else.
fault_crumb() { # fault_crumb <class>
  mkdir -p "$HAUS_LOG_DIR" 2>/dev/null || return 0
  {
    printf 'class=%s\n'    "$1"
    printf 'host=%s\n'     "$FAULT_HOST"
    printf 'consumer=%s\n' "$CONSUMER"
    printf 'log=%s\n'      "$HAUS_LOG"
    printf 'offset=%s\n'   "$HAUS_PHASE_OFF"
    printf 'drv=%s\n'      "$FAULT_DRV"
    printf 'gen=%s\n'      "${CARD_GEN:-$(current_gen || echo '?')}"
    printf 'when=%s\n'     "$(date '+%Y-%m-%d %H:%M:%S')"
  } >"$HAUS_LOG_DIR/last-failure" 2>/dev/null || true
  return 0
}

# Which door. A pane you are SITTING AT gets rows in place — one keypress, no
# mouse, and the error is still on screen above them. Anywhere else gets a
# banner, because the whole point of the offer is that it survives you having
# walked away. The window-to-session join is terminal's (the same one every
# chord uses); with no join and no zmx session, a terminal is taken at face
# value.
fault_surface() { # -> pane | banner | none
  local join focused
  if [ -t 0 ] && [ -t 2 ] && command -v gum >/dev/null 2>&1; then
    join="$HOME/.config/haus/term/focused-session.sh"
    if [ -n "${ZMX_SESSION:-}" ] && [ -r "$join" ]; then
      focused="$(bash "$join" 2>/dev/null || true)"
      [ "$focused" = "$ZMX_SESSION" ] && { printf pane; return 0; }
    else
      printf pane; return 0
    fi
  fi
  # Same gate as `card`: a machine that said "no banners" means this one too.
  [ -n "${HAUS_NO_BANNER:-}" ] && { printf none; return 0; }
  trill_bin >/dev/null 2>&1 && { printf banner; return 0; }
  printf none
}

# The in-pane door. Timed out on purpose: a picker that waits forever holds a
# prompt you may have walked away from, and gum returns 124 with no selection
# rather than committing the row under the cursor (measured, gum 0.17).
#
# stderr is deliberately NOT redirected, and that is the whole reason there is
# anything to look at: gum draws the picker on STDERR precisely so that `$( )`
# can take the SELECTION off stdout. A `2>/dev/null` here — which is what the
# first cut of this shipped — silences the rows while gum still blocks for its
# full timeout, so pressing nothing looks identical to the feature being off:
# a rebuild that fails, then thirty seconds of nothing, then your prompt back.
# Measured under a pty, gum 0.17. If a future gum needs quieting, quiet its
# diagnostics by name; never the stream it renders on.
fault_rows() {
  local pick
  pick="$(gum choose --timeout=30s --header='Fix it with AI?' \
    'Fix it with AI' 'Not now')" || return 0
  [ "$pick" = 'Fix it with AI' ] || return 0
  haus-fix || true
  return 0
}

# The banner door's waiting half, and the reason any of this is detached: a
# `trill ask` parks as a fin until it is answered, which can be tomorrow, and
# trill retracts an ask whose caller died. Closing the Ghostty window this
# rebuild ran in HUPs the whole process group, so a holder that merely
# outlived `haus` would take the fin with it. `trap "" HUP` is nohup, spelled
# where we can also drop the coprocess and the rebuild's own traps.
fault_holder() { # fault_holder <class>
  local bin child rc
  bin="$(trill_bin)" || return 0
  "$bin" ask "$FAULT_HOST · rebuild failed" \
    --pill "Fix it" \
    --body "The $1 phase failed and nothing was changed. Hand it to an agent: it reads the error and what changed in $CONSUMER, fixes it, commits, and leaves \`haus rebuild\` to you." \
    --subtitle "$1 phase" \
    --source haus.rebuild.fault \
    --symbol wrench.and.screwdriver \
    --key haus-rebuild-fault >/dev/null 2>&1 &
  child=$!
  # SIGINT is what retracts an ask (trill's rule: a question with nobody behind
  # it comes down), and TERM is what the NEXT failure sends this process.
  trap 'kill -INT "$child" 2>/dev/null' TERM INT
  # `|| rc=$?`, NEVER `wait "$child"; rc=$?` — this file runs under `set -e`,
  # and a relayed TERM makes `wait` return 143, which under errexit exits this
  # subshell before the assignment. Measured: the line after it is not reached.
  # That silently skipped the reap below, which is the whole ordering
  # `fault_hold` waits on.
  rc=0; wait "$child" || rc=$?
  trap - TERM INT
  # Reaped, not just signalled: a relayed INT leaves `wait` returning 143 with
  # the child still winding down, and the retraction it is winding down INTO is
  # what must land before the next failure's ask goes up.
  wait "$child" 2>/dev/null || true
  # 0 is the first (and only) pill. Everything else — dismissed, daemon gone,
  # 75 nobody answered — means no.
  [ "$rc" = 0 ] || return 0
  haus-fix || true
  return 0
}

# Take down whatever holder the LAST failure left, and the fin it is holding up.
# TERM is what makes it retract its own ask on the way out (its trap relays the
# INT trill retracts on), and it is WAITED for, briefly: a retraction that
# landed after the next ask went up would take the NEW fin down with it, since
# both carry `haus-rebuild-fault`. Bounded, because every caller is on an exit
# path and a holder that will not go is not worth standing here for — trill's
# own same-key replacement is the backstop if the race is lost anyway.
# Named once, as a function rather than a global, because HAUS_LOG_DIR is read
# from the environment and both callers run long after load.
fault_pidfile() { printf '%s' "$HAUS_LOG_DIR/fault-holder.pid"; }

fault_holder_stop() {
  local pidfile old
  pidfile="$(fault_pidfile)"
  old="$(cat "$pidfile" 2>/dev/null || true)"
  rm -f "$pidfile" 2>/dev/null || true
  case "$old" in
    '' | *[!0-9]*) return 0 ;;
  esac
  kill -TERM "$old" 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    kill -0 "$old" 2>/dev/null || break
    sleep 0.05
  done
  return 0
}

# A rebuild that SUCCEEDS ends the last one's offer, and this is not tidiness.
# The breadcrumb names a log `log_open` rotates on every rebuild, so one more
# run makes its offset point into a different rebuild's output — and the ask
# carries no timeout by design, so a fin can sit on the ledge for days. Pressing
# a stale one would spawn an agent, unattended and with its permission gate
# open, at a config that is fine, holding a slice of a SUCCESSFUL rebuild's log
# as "what the failure said". So: the crumb goes, the holder goes, and the fin
# is resolved by key for the case where the holder was already gone (killed -9,
# a reboot) and only trill still remembers.
fault_clear() {
  local bin
  fault_holder_stop
  rm -f "$HAUS_LOG_DIR/last-failure" 2>/dev/null || true
  bin="$(trill_bin)" || return 0
  "$bin" resolve haus-rebuild-fault >/dev/null 2>&1 || true
  return 0
}

fault_hold() {
  local pidfile
  pidfile="$(fault_pidfile)"
  fault_holder_stop
  # The detach, in one line of subshell: no HUP when the window closes, none of
  # the rebuild's traps (the inherited EXIT one would fire card_stop in here),
  # no copy of snug's write end (snug_close waits for EOF on it), and no fd on
  # the terminal we are about to give back to the shell.
  (
    trap - EXIT INT TERM
    trap '' HUP
    snug_detach
    fault_holder "$1"
  ) </dev/null >/dev/null 2>&1 &
  printf '%s\n' "$!" >"$pidfile" 2>/dev/null || true
  return 0
}

fault_cta() { # fault_cta <class> — the offer, on whichever surface fits
  [ -n "${HAUS_NO_FIX:-}" ] && return 0
  # The only gate on the AI room there is or may be, from this file.
  command -v haus-fix >/dev/null 2>&1 || return 0
  # No git, no undo, no offer. modules/ai/fix.sh refuses on the same ground —
  # this copy is so the refusal is never something you find out by pressing it.
  git -C "$CONSUMER" rev-parse --git-dir >/dev/null 2>&1 || return 0
  case "$(fault_surface)" in
    pane)   fault_rows ;;
    banner) fault_hold "$1" ;;
    # No surface — a pipe, CI, a machine with banners off. There is still a
    # fixer and still an undo, so the offer is worth ONE line rather than
    # nothing: silence here would make the whole feature undiscoverable on
    # exactly the machines whose owner reads the transcript later.
    *)      hint "or hand it to an agent: haus fix" ;;
  esac
  return 0
}

# The one ending every failed rebuild takes. It is `die` with two things in
# front of the exit: the card gets its fault, and the breadcrumb + offer get
# written while the phase that failed is still known. The message is drawn
# here rather than by `die` because the offer belongs UNDER the error it is
# offering to fix, and `die` exits.
rebuild_failed() { # rebuild_failed <resolve|build|activate>
  local fault msg gen="${CARD_GEN:-?}"
  case "$1" in
    resolve)
      fault="evaluation failed"
      msg="evaluation failed — nothing was changed."
      ;;
    build)
      fault="build failed"
      msg="build failed — nothing was changed."
      ;;
    activate)
      fault="activation failed — $gen is still on disk"
      msg="activation failed partway — generation $gen is still on disk (haus rollback), and the log above says where it stopped."
      ;;
  esac
  card_stop
  card - "fault" "$fault"
  fault_crumb "$1"
  # Idempotent, and called on every class rather than just the build one:
  # run_phase already closes the coprocess when a phase it owns fails, and the
  # build phase has no run_phase to do it. nix keeps the terminal for that
  # phase and has just written its own error to fd 2, so closing first is what
  # puts the line below AFTER what nix said instead of on snug's own schedule.
  snug_close
  snug_emit fail "$msg" || ui_draw fail "$msg"
  fault_cta "$1"
  exit 1
}

cmd_rebuild() {
  local host drv sys old gen_before drvfile outfile difffile bt0
  host="$(host_name)"
  FAULT_HOST="$host"
  guard_unguarded_fda "$host"

  old="$(cd /run/current-system 2>/dev/null && pwd -P || true)"
  gen_before="$(current_gen || echo '?')"
  drvfile="$(mktemp)"; outfile="$(mktemp)"; difffile="$(mktemp)"
  log_open "rebuild $host from $CONSUMER"

  say "$host · rebuild"
  consumer_worktree_warning
  # fd 2, with the summary it separates — the whole rebuild narration is on the
  # message stream now.
  [ -n "$VERBOSE" ] || printf '\n' >&2

  run_phase resolve heal resolve_drv "$host" "$drvfile" \
    || rebuild_failed resolve
  drv="$(cat "$drvfile")"; rm -f "$drvfile"
  # What a build-phase failure has instead of a log slice: the derivation
  # itself, so `haus fix` can reproduce the error rather than read it.
  FAULT_DRV="$drv"
  phase_ok resolve "$HAUS_PHASE_ELAPSED"

  # Homebrew's half of the rebuild, alongside nix's rather than after it. Joined
  # at bg_wait below, before anything activates.
  bg "${BREW_JOB:-brew_prefetch}"

  # Build. Deliberately neither hidden nor logged: nix draws its progress bar
  # only when stderr is a terminal, and a rebuild with gigabytes to fetch should
  # be able to say so. We only hide what we write down — this is the one phase
  # that narrates itself, so it keeps the terminal.
  bt0="$(now_ds)"
  # The build phase has no run_phase, so nothing moves HAUS_PHASE_OFF past the
  # resolve phase's slice. Park it at the END of the log: this phase keeps the
  # terminal and writes nothing here, and an offset pointing at somebody else's
  # output is worse evidence than none. (modules/ai/fix.sh reproduces the build
  # for this class instead of slicing.)
  HAUS_PHASE_OFF="$(wc -c <"$HAUS_LOG" 2>/dev/null | tr -d ' ')"
  # Name the card, then start the poller beside the build. These two
  # assignments are what arms the whole feature: `card` returns early on an
  # empty CARD_KEY, so without them every call below is a no-op and nothing
  # ever draws.
  CARD_KEY="haus-rebuild"; CARD_TITLE="$host · rebuild"; CARD_GEN="$gen_before"
  trap card_stop EXIT
  trap card_cancelled INT TERM
  card_watch "$drv"
  ( cd "$CONSUMER" && nix build --print-out-paths --out-link "$CONSUMER/result" "$drv^*" ) >"$outfile" \
    || rebuild_failed build
  # Not `card_stop`: `bg_wait` below joins the homebrew half, which by its own
  # comment can run for minutes on a 200 MB cask. Hold the bar where the build
  # left it and keep beating, or the card would leave during the longest silent
  # stretch of the rebuild and come back as a different banner.
  card_hold 99 "homebrew"
  sys="$(cat "$outfile")"; rm -f "$outfile"
  phase_ok build "$(secs $(( $(now_ds) - bt0 )) )"

  # The one thing a rebuild never used to tell you: what actually changed.
  # Backgrounded so it costs nothing — it reads the OLD system, which is still
  # current until the activation below swaps it.
  [ -n "$old" ] && bg closure_diff "$old" "$sys" "$difffile"
  bg_wait || warn "a background job failed — see $HAUS_LOG (continuing)"

  # The bar's last stop before the ending. Nothing here counts paths, so it
  # holds at 99 and beats — 99 rather than 95 because a bar that goes backwards
  # reads as the build losing ground, and holds rather than fires once because
  # activation outlives trill's dismiss clock.
  card_hold 99 "activating"

  # Activate exactly what we just built. The old route here was
  # `darwin-rebuild switch --flake`, which BUILDS again as root — a second
  # evaluation against root's separate caches, costing ~3 s after a host edit
  # and ~15 s whenever a flake input moved (root re-unpacks nixpkgs into its
  # own lazy-trees cache). `haus-activate` does only the privileged half; see
  # modules/core/haus-activate.sh. No `heal`: nothing here evaluates or fetches,
  # so the corrupt-fetch-cache signature can't arise past the build above.
  #
  # Both paths go through a stable /run/current-system path, never ./result or
  # a store path: security's passwordless-sudo rule matches the literal path,
  # because sudo no longer follows the command symlink.
  #
  # Quiet mode redirects this phase's stdout+stderr, which is safe for the one
  # thing that must never be swallowed here: sudo writes its password prompt to
  # /dev/tty, not to either stream (and where there's no tty, VERBOSE is already
  # on). A Touch ID prompt is a GUI dialog, so it's unaffected either way.
  # Both branches below go through sudo, and sudo's prompt lands on /dev/tty —
  # the same terminal the phase row repaints, and one the region's line count
  # knows nothing about. Ten frames a second would rewind over the prompt and
  # over what you are typing into it.
  #
  # So: spin only where we can PROVE there will be no prompt. `sudo -n true`
  # succeeding means the timestamp is valid, which means the sudo below will not
  # ask. It is deliberately one-way and it under-detects — a machine whose
  # NOPASSWD rule names only `haus-activate` (which is every machine haus's
  # security room has configured) fails this and gets a still row even though it
  # would never have been asked. That is the safe direction to be wrong in, and
  # it is no worse than what this phase drew before there was a spinner at all.
  # Discriminating properly would mean parsing sudo's refusal text, which is
  # localised.
  sudo -n true 2>/dev/null || PHASE_STILL=1
  if [ -x /run/current-system/sw/bin/haus-activate ]; then
    run_phase activate sudo /run/current-system/sw/bin/haus-activate "$CONSUMER/result"
  else
    # The running system predates haus-activate — take the old, slower route
    # once; the switch it performs is what installs the fast one.
    run_phase activate heal legacy_switch "$host"
  fi || rebuild_failed activate
  PHASE_STILL=""
  phase_ok activate "$HAUS_PHASE_ELAPSED" "$(activation_summary)"

  # The ending replaces the bar on the same card, because it carries the same
  # key — a second banner saying "and now it's done" is one banner too many.
  card_stop
  local gen_now
  gen_now="$(current_gen || echo '?')"
  card 100 "done" "$([ "$gen_before" = "$gen_now" ] && echo "generation $gen_now" \
    || echo "generation $gen_before → $gen_now")"
  # This machine builds again, so the last failure's offer is over: the crumb it
  # left points into a log this run has already rotated, and the fin holding it
  # up would spawn an agent at a config that is fine. See fault_clear.
  fault_clear
  # Done with the card. Release the handlers, or a ⌃C through the tail of this
  # function replaces the ending with "cancelled" for a machine that already
  # switched.
  trap - INT TERM EXIT

  # Generation + closure diff: the two lines that are actually about YOUR
  # machine rather than about the tools that rebuilt it.
  if [ -n "$VERBOSE" ]; then
    say "the house stands."
  else
    local gen_after changed n
    gen_after="$(current_gen || echo '?')"
    phase_ok generation '' \
      "$([ "$gen_before" = "$gen_after" ] && echo "$gen_after (unchanged)" || echo "$gen_before → $gen_after")"
    n="$(wc -l <"$difffile" 2>/dev/null | tr -d ' ')"; n="${n:-0}"
    # `hint`, not `info`: this line belongs with the rows above it on fd 2, and
    # `info` is the reports' verb on fd 1. Mixing the two here would split one
    # summary across two streams, which is only invisible while both happen to
    # be the same terminal.
    if [ "$n" = "0" ]; then
      hint "nothing changed in the closure"
    else
      changed="$(sed 's/^ *//' "$difffile" | head -3 | paste -sd', ' -)"
      [ "$n" -gt 3 ] && changed="$changed, +$((n - 3)) more"
      hint "$changed"
    fi
    say "the house stands."
  fi
  rm -f "$difffile"

  # The one place a fresh machine is told its grants are missing. A rebuild is
  # when the deck can first be right — the generation that installed it is the
  # one now running — and it is also the moment somebody is looking. ONE line,
  # never the wizard itself: opening System Settings at the end of a rebuild
  # would take a screen nobody offered.
  local unmet
  unmet="$(_perm_unmet 2>/dev/null || echo 0)"
  [ "${unmet:-0}" -eq 0 ] \
    || warn "$unmet permission(s) macOS says you have not granted — walk them with: haus permissions"
}

# Family apps (pounce, perch…) ship as CI-published casks/formulae in
# hausfold/tap, released on their OWN cadence — a haus flake bump never carries
# them. Worse, activation's `brew bundle` leans on Homebrew's auto-update, which
# is THROTTLED: a rebuild can run against a stale tap clone and never see a fresh
# release (the "released but not installed" trap). So do an explicit, unthrottled
# `brew update` + a targeted upgrade of just the hausfold/tap packages here —
# third-party casks keep whatever upgrade policy the host set (autoUpdate/upgrade).
refresh_family_apps() {
  command -v brew >/dev/null 2>&1 || return 0
  local root tap
  root="$(brew --repository 2>/dev/null)" || return 0
  tap="$root/Library/Taps/hausfold/homebrew-tap"
  [ -d "$tap" ] || return 0
  brew update --quiet >/dev/null 2>&1 || warn "brew update failed — family apps may be stale"
  local kind dir f name
  for kind in Casks Formula; do
    dir="$tap/$kind"; [ -d "$dir" ] || continue
    for f in "$dir"/*.rb; do
      [ -e "$f" ] || continue
      name="$(basename "$f" .rb)"
      if [ "$kind" = Casks ]; then
        brew list --cask "$name" >/dev/null 2>&1 || continue
        brew upgrade --cask "$name" || warn "  $name: upgrade failed"
      else
        brew list --formula "$name" >/dev/null 2>&1 || continue
        brew upgrade --formula "$name" || warn "  $name: upgrade failed"
      fi
    done
  done
}

# The changelog fetch and the family-app refresh, so cmd_update can start them
# and walk away. Both are network-bound and neither gates the build.
fetch_changelog() { # <owner> <repo> <old> <new> <outfile>
  curl -fsSL --max-time 5 \
    -H 'accept: application/vnd.github+json' \
    "https://api.github.com/repos/$1/$2/compare/$3...$4" 2>/dev/null \
    | jq -r '.commits[]?.commit.message | split("\n")[0]' 2>/dev/null | head -15 >"$5" || true
}

# The whole brew half of an update, as ONE job — family apps first, then a
# prefetch of whatever else activation will upgrade. One job and not two
# because brew takes a global lock: two of these in parallel would serialise
# anyway, badly, on a lock timeout rather than on the work.
update_brew_job() { refresh_family_apps; brew_prefetch; }

cmd_update() {
  # `cmd_update` used to be written for exactly one caller — every local
  # hardcoded to the node `haus` — because `bootstrap.sh` never scaffolded a
  # second input to pull. `haus add` does now, so this re-keys every one of
  # those reads on $input instead of adding a branch beside them.
  local input="${1:-haus}"
  # 🚨 The input NAME belongs to the consumer's flake, not to us — and
  # `nix flake update <name that isn't in the lock>` WARNS AND EXITS 0 without
  # touching anything. So an unchecked name here doesn't fail loudly, it turns
  # `haus update` into a permanent no-op that then reports "already at the
  # latest".
  jq -e --arg n "$input" '.nodes[$n] != null' "$CONSUMER/flake.lock" >/dev/null 2>&1 \
    || die "no input named '$input' in this config — 'haus desktop' lists what's pinned, or run 'haus update' with no name to pull haus itself."

  local old new otype oowner orepo logfile old_nar new_nar
  old="$(jq -r --arg n "$input" '.nodes[$n].locked.rev // ""' "$CONSUMER/flake.lock" 2>/dev/null || true)"
  old_nar="$(jq -r --arg n "$input" '.nodes[$n].locked.narHash // ""' "$CONSUMER/flake.lock" 2>/dev/null || true)"
  otype="$(jq -r --arg n "$input" '.nodes[$n].original.type // ""' "$CONSUMER/flake.lock" 2>/dev/null || true)"

  if [ "$input" = haus ]; then say "pulling the latest haus …"
  else say "pulling the latest '$input' …"
  fi
  ( cd "$CONSUMER" && heal nix flake update "$input" )

  new="$(jq -r --arg n "$input" '.nodes[$n].locked.rev // ""' "$CONSUMER/flake.lock" 2>/dev/null || true)"
  new_nar="$(jq -r --arg n "$input" '.nodes[$n].locked.narHash // ""' "$CONSUMER/flake.lock" 2>/dev/null || true)"

  if [ -n "$old" ] && [ "$old" = "$new" ]; then
    say "already at the latest ${input} (${new:0:12}) — rebuilding anyway."
  elif [ -n "$old" ] && [ -n "$new" ]; then
    # What's about to land. Best-effort via the GitHub compare API — offline,
    # rate-limited, or a non-GitHub upstream just skips the list. Fetched in
    # the background: it's a 5-second timeout on a network you may not have,
    # and nothing downstream waits on it. Gated on the node's ORIGINAL shape,
    # not just "has a rev": a non-GitHub git source has a rev too, and no
    # owner/repo to compare with GitHub's API.
    if [ "$otype" = github ]; then
      oowner="$(jq -r --arg n "$input" '.nodes[$n].original.owner // ""' "$CONSUMER/flake.lock")"
      orepo="$(jq -r --arg n "$input" '.nodes[$n].original.repo // ""' "$CONSUMER/flake.lock")"
      if [ -n "$oowner" ] && [ -n "$orepo" ]; then
        logfile="$(mktemp)"
        bg fetch_changelog "$oowner" "$orepo" "$old" "$new" "$logfile"
      fi
    fi
  elif [ "$old_nar" != "$new_nar" ]; then
    # A revisionless source (a `file+https` node): Nix's own update line
    # prints the SAME url on both sides even when the content underneath
    # moved, so this is the only place that ever shows it actually happened.
    say "'$input' has no revision to compare — nix's update line for it looks like a no-op. Its content hash moved:"
    printf '    %s\n    %s %s\n' "${old_nar:-(none)}" "$(printf '\xe2\x86\x92')" "$new_nar"
  else
    say "'$input' has no revision, and its content hash didn't move either — nothing changed."
  fi
  # The rebuild's own bg_wait joins this before anything activates.
  BREW_JOB=update_brew_job
  cmd_rebuild
  if [ -n "${logfile:-}" ]; then
    if [ -s "$logfile" ]; then
      echo
      say "new in ${input} (${old:0:7} → ${new:0:7}):"
      sed 's/^/  · /' "$logfile"
    fi
    rm -f "$logfile"
  fi
}

cmd_rollback() {
  if [ -n "${1:-}" ]; then
    say "switching to generation $1 …"
    sudo darwin-rebuild --switch-generation "$1"
  else
    say "rolling back to the previous generation …"
    sudo darwin-rebuild --rollback
  fi
  say "rolled back. (Nix reverts everything IT manages; macOS system settings and"
  warn "Homebrew apps are not rewound — see haus status / your notes.)"
}

cmd_generations() {
  local cur link num nums total show; cur="$(current_gen || echo '')"
  nums="$(for link in "$SYSPROFILES"/system-*-link; do
    [ -e "$link" ] || continue
    num="$(basename "$link")"; num="${num#system-}"; echo "${num%-link}"
  done | sort -rn)"
  total="$(echo "$nums" | grep -c .)"
  show=20
  # Newest first, capped — the recent ones are what you roll back to.
  echo "$nums" | head -n "$show" | while read -r num; do
    printf '%s %5s   %s\n' "$([ "$num" = "$cur" ] && echo '→' || echo ' ')" "$num" "$(gen_date "$num" '+%Y-%m-%d %H:%M')"
  done
  [ "$total" -gt "$show" ] && say "… and $((total - show)) older (roll back to any with: haus rollback <N>)"
  return 0
}

cmd_status() {
  local host lockrev lockdate url owner repo ref remoterev
  host="$(host_name)"
  say "this machine: $host"

  echo
  say "current generation"
  local cur; cur="$(current_gen || echo '')"
  if [ -n "$cur" ]; then printf '  %s  (%s)\n' "$cur" "$(gen_date "$cur")"
  else warn "  (none yet — haus rebuild)"; fi

  echo
  say "pinned haus"
  if [ -f "$CONSUMER/flake.lock" ]; then
    lockrev="$(jq -r '.nodes.haus.locked.rev // "?"' "$CONSUMER/flake.lock")"
    lockdate="$(jq -r '.nodes.haus.locked.lastModified // 0' "$CONSUMER/flake.lock")"
    if [ "$lockdate" != "0" ]; then
      printf '  %s  (%s)\n' "${lockrev:0:12}" "$(date -r "$lockdate" '+%Y-%m-%d' 2>/dev/null || echo '?')"
    else
      printf '  %s\n' "${lockrev:0:12}"
    fi
    # Is upstream haus ahead of what you've pinned? Best-effort, offline-safe.
    owner="$(jq -r '.nodes.haus.original.owner // "hausfold"' "$CONSUMER/flake.lock")"
    repo="$(jq -r '.nodes.haus.original.repo // "haus"' "$CONSUMER/flake.lock")"
    ref="$(jq -r '.nodes.haus.original.ref // "HEAD"' "$CONSUMER/flake.lock")"
    url="https://github.com/$owner/$repo.git"
    remoterev="$(git ls-remote "$url" "$ref" 2>/dev/null | awk 'NR==1{print $1}')"
    if [ -n "$remoterev" ] && [ "$remoterev" != "$lockrev" ]; then
      warn "  a newer haus is available upstream (${remoterev:0:12}) — haus update"
    elif [ -n "$remoterev" ]; then
      ok "up to date with upstream"
    fi
  else
    warn "  no flake.lock yet"
  fi
}

cmd_edit() {
  local host f
  host="$(host_name)"
  f="$CONSUMER/hosts/$host/default.nix"
  [ -f "$f" ] || die "no host file at $f"
  exec "${EDITOR:-hx}" "$f"
}

# ---- haus set / get / unset / reset ----------------------------------------
# The machine-writable overlay is deliberately ordinary Nix: one tiny module
# per option under hosts/<host>/settings/, auto-imported by mkHaus beside
# Pounce's packages/ modules. There is no second settings database to drift.
#
# These files use mkForce because this layer is the machine owner's explicit
# answer and must be able to override its desktop. `haus reset` removes that answer
# entirely, revealing the host/desktop/room value underneath. `haus unset` is a
# different operation: it explicitly writes null, and therefore only succeeds
# for nullable options.
settings_path() {
  local raw="$1" path
  [ -n "$raw" ] || die "an option path is required (for example: theme.accent)"
  # The `haus.` prefix is optional on the command line and always present in
  # what gets WRITTEN — an overlay file is regenerated on every `haus set`.
  case "$raw" in
    haus.*) path="$raw" ;;
    *) path="haus.$raw" ;;
  esac
  # A component may start with a digit: the keys of an `attrsOf` option are the
  # user's, not haus's, and `haus.displays.<uuid>.uiScale` is the worked
  # example — display UUIDs begin with a hex digit as often as not.
  [[ "$path" =~ ^haus(\.[A-Za-z0-9_][A-Za-z0-9_-]*)+$ ]] \
    || die "only haus.* option paths are writable (got '$raw')"
  printf '%s\n' "$path"
}

# `haus.displays."37D8832A-…".uiScale` — a component that isn't a bare Nix
# identifier gets quoted, and only then, so the common file still reads as the
# plain attrpath a human would have typed.
settings_attrpath() {
  local out="" c
  local IFS=.
  # Deliberate word splitting on '.' — that is what makes this a path walk.
  # shellcheck disable=SC2086
  for c in $1; do
    case "$c" in
      # A Nix keyword is all letters and still not an identifier, so it needs the
      # quotes as much as a UUID does — `haus.displays.if.uiScale` is a syntax
      # error otherwise, and an attrsOf key can be any word the user likes.
      assert | else | if | in | inherit | let | or | rec | then | with) c="\"$c\"" ;;
      [A-Za-z_]*) ;;
      *) c="\"$c\"" ;;
    esac
    out="${out:+$out.}$c"
  done
  printf '%s' "$out"
}

settings_host_dir() {
  printf '%s/hosts/%s/settings\n' "$CONSUMER" "$(host_name)"
}

settings_file() {
  local path="$1"
  printf '%s/%s.nix\n' "$(settings_host_dir)" "${path#haus.}"
}

# Does this path name something settable? `options.<path>` alone can't answer
# that, and that was the old guard's bug: the module system's options tree stops
# at an option, so `options.haus.bar.items` exists but `options.haus.bar.items.
# aiUsage` does not — a submodule's sub-options live behind `type.getSubOptions`,
# and an `attrsOf`'s keys aren't in the tree at all because they're the user's to
# invent. Both are perfectly ordinary definition sites, so both were being
# refused, leaving the whole-attrset form (`haus set bar.items '{"cpu":true}'`)
# as the only way in — which silently resets every key you didn't name.
#
# So walk it instead, one component at a time:
#   - a plain attrset of options: index into it (`bar` → `bar.bottom`)
#   - an option whose type is attrsOf/lazyAttrsOf: the next component is a KEY,
#     free-form by definition, so consume it without checking
#   - an option with sub-options (submodule, or nullOr/attrsOf of one): descend
#     into getSubOptions, which is where a submodule's declared options live
#   - anything left over with nowhere to go is a typo, and is still refused
# A leaf reached this way is settable exactly when the module system would accept
# a definition there, which is the property this guard is trying to have.
#
# Running OUT of components has to land on an option, not merely somewhere: the
# old guard refused `haus set theme '{…}'` because a namespace has no `.type`,
# and it was right to. A whole-room mkForce evaluates fine and then quietly
# scatters over every option in the room — and, now, collides with the overlap
# guard, so one of those would lock every leaf under it out of `haus set`.
settings_option_exists() {
  local host="$1" path="$2" parts result err
  # Every component is [A-Za-z0-9_-]+ by now (settings_path), so this is safe to
  # interpolate into Nix string literals.
  parts="$(printf '%s' "${path#haus.}" | tr '.' '\n' | sed 's/.*/"&"/' | tr '\n' ' ')"
  err="$(mktemp)"
  result="$(
    cd "$CONSUMER" && nix eval --json ".#darwinConfigurations.$host" --apply "cfg:
      let
        isOption = x: (x._type or null) == \"option\";
        descend = node: ps:
          if ps == [ ] then isOption node
          else if isOption node then
            (let
              rest = if node.type.name == \"attrsOf\" || node.type.name == \"lazyAttrsOf\"
                     then builtins.tail ps else ps;
              subs = node.type.getSubOptions [ ];
            in if rest == [ ] then true
               else if subs == { } then false
               else into subs rest)
          else into node ps;
        into = attrs: ps:
          let h = builtins.head ps; in
          if !builtins.isAttrs attrs then false
          else if !(attrs ? \${h}) then false
          else descend attrs.\${h} (builtins.tail ps);
      in descend cfg.options.haus [ $parts ]" 2>"$err"
  )" || {
    # A failure here is the host file or the pinned haus not evaluating at all,
    # never this walk — so show nix's own words rather than a shrug.
    warn "could not evaluate this machine's option surface:"
    tail -n 12 "$err" >&2
    rm -f "$err"
    die "'$path' could not be checked (try: haus doctor)"
  }
  rm -f "$err"
  [ "$result" = "true" ] \
    || die "'$path' is not a settable option on this machine's pinned haus"
}

# A courtesy check for `haus add --room --namespace`, sibling to
# settings_option_exists above but answering with a boolean instead of dying:
# is `haus.$ns` already a namespace on THIS machine, from haus itself or from
# any other already-imported module? A claim naming a namespace that's already
# in use is always wrong — the whole point of a claim is to name a namespace a
# room is ABOUT to introduce, never one that exists for a different reason
# already. This is NOT the load-bearing check: modules/namespaces.nix's
# assertion is what actually refuses a real collision, at eval time, on the
# CONSUMER's evaluated option tree, regardless of what this walk finds first.
# This one just turns an obvious mistake into an add-time refusal instead of a
# rebuild-time one, so a bad `--namespace` doesn't cost a fetch and a lock to
# discover.
#
# `--apply` throughout rather than a quoted attribute inside the `.#…`
# installable fragment: `$ns` only ever needs escaping into a NIX STRING
# LITERAL (inside the lambda body, ordinary Nix source), never into the CLI's
# own flake-fragment parser, which is one fewer syntax to get quoting right in.
#
# Fails CLOSED, not open: exit 0 (taken), 1 (not taken), 2 (couldn't check —
# a transient nix eval failure, NOT a proof the namespace is free). The
# earlier cut folded 2 into 1, which reads a network blip or a broken host as
# "go ahead" — silently the wrong direction for what is otherwise a courtesy
# check standing in FRONT of a fetch and a lock. Found by the pre-PR
# assurance pass, not by testing: nothing in test/haus-add.sh can make
# `nix eval` itself fail without breaking every other assertion in the same
# run, so this is reasoned about rather than fixture-proven.
namespace_taken() { # host ns
  local host="$1" ns="$2" result
  result="$(
    cd "$CONSUMER" && nix eval --json ".#darwinConfigurations.$host" --apply "cfg:
      cfg.options.haus ? \"$ns\"" 2>/dev/null
  )" || return 2
  [ "$result" = "true" ] && return 0
  return 1
}

# The value half of a namespace claim's collision check — sibling to
# settings_eval_json, reading what THIS machine currently believes
# haus._rooms.claimed.<ns> is, so a second `add --room` claiming a namespace
# already claimed by a DIFFERENT origin can refuse before locking anything,
# rather than discovering the E1 assertion's refusal only at the next
# rebuild. Prints the claimed origin (possibly empty, meaning unclaimed) and
# returns 0 when the read succeeded; returns 1 with nothing printed when it
# could not be answered at all — a DIFFERENT thing from "unclaimed", and the
# caller has to tell them apart (same fail-closed fix as namespace_taken).
namespace_claimed_by() { # host ns
  local host="$1" ns="$2"
  ( cd "$CONSUMER" && nix eval --raw ".#darwinConfigurations.$host" --apply "cfg:
      cfg.config.haus._rooms.claimed.\"$ns\" or \"\"" 2>/dev/null )
}

# Writes haus._rooms.claimed.<ns> = "<typed>" for one namespace, reusing the
# exact primitives `cmd_set` uses for every other leaf (settings_write et al.)
# rather than inventing a second writer — the option is an ordinary attrsOf
# str (modules/namespaces.nix:32-45), so nothing room-specific belongs in the
# write path at all. Stops one phase short of cmd_set's own: no
# settings_apply, because `add` never rebuilds, same as it never rebuilds a
# desktop selection. Returns non-zero (and writes nothing) on a genuine
# collision — a differently-typed origin already claims this namespace — and
# also on simply being unable to check, rather than reading "couldn't check"
# as "unclaimed" and overwriting whatever is actually there with mkForce.
rooms_claim_namespace() { # host name typed ns
  local host="$1" name="$2" typed="$3" ns="$4"
  local dir target existing
  dir="$(settings_host_dir)"
  target="$(settings_file "haus._rooms.claimed.$ns")"
  if ! existing="$(namespace_claimed_by "$host" "$ns")"; then
    warn "couldn't check whether '$ns' is already claimed — not writing, to avoid overwriting a claim this machine couldn't be asked about. Re-run, or set it by hand: haus set _rooms.claimed.$ns \"$typed\""
    return 1
  fi
  if [ -n "$existing" ]; then
    if [ "$existing" = "$typed" ]; then
      return 0 # same room, re-added — nothing to do
    fi
    warn "'$ns' is already claimed by $existing — remove that input first, or pick a different --namespace."
    return 1
  fi
  mkdir -p "$dir"
  settings_write "haus._rooms.claimed.$ns" "$typed" "$dir" "$target"
  local err; err="$(mktemp)"
  # A direct --apply, not settings_eval_json: that helper builds the path
  # into the `.#…` installable FRAGMENT, and `$ns` only needs to be a valid
  # NIX STRING there (namespace_claimed_by's own reasoning) — one syntax to
  # get right instead of two.
  if ! (
    cd "$CONSUMER" && nix eval --json ".#darwinConfigurations.$host" --apply "cfg:
      cfg.config.haus._rooms.claimed.\"$ns\"" >/dev/null 2>"$err"
  ); then
    rm -f "$target"
    warn "the namespace claim for '$ns' did not type-check:"
    tail -n 12 "$err" >&2
    rm -f "$err"
    return 1
  fi
  rm -f "$err"
  return 0
}

# One override per path is the model, and a path plus one of its ancestors is
# not one override — `bar.items` written whole and `bar.items.cpu` written on
# its own are two mkForce definitions of the same leaf the moment they name the
# same key, and the module system reports that from inside the submodule, as a
# conflict between two anonymous definitions the caller can't trace back to
# either file. So refuse the overlap here, where both file names are in hand.
# Prints the offending path and returns 0 when there is one.
settings_overlap() {
  local path="$1" p f
  shift
  p="$path"
  while [ "${p%.*}" != "$p" ] && [ "${p%.*}" != "haus" ]; do
    p="${p%.*}"
    [ -e "$(settings_file "$p")" ] && { printf '%s\n' "$p"; return 0; }
    for f in "$@"; do [ "$f" = "$p" ] && { printf '%s\n' "$p"; return 0; }; done
  done
  for f in "$(settings_host_dir)/${path#haus.}."*.nix; do
    [ -e "$f" ] || continue
    printf 'haus.%s\n' "$(basename "$f" .nix)"
    return 0
  done
  for f in "$@"; do
    case "$f" in "$path".*) printf '%s\n' "$f"; return 0 ;; esac
  done
  return 1
}

settings_stage() {
  local target="$1" rel
  rel="${target#"$CONSUMER"/}"
  if git -C "$CONSUMER" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$CONSUMER" add -A -- "$rel"
  fi
}

settings_eval_json() {
  local host="$1" path="$2"
  ( cd "$CONSUMER" && nix eval --json ".#darwinConfigurations.$host.config.$path" )
}

settings_print_json() {
  jq -r 'if type == "string" then . else tojson end'
}

# `haus get --json`'s one row, and its whole schema:
#
#   {"path": "haus.theme.accent", "defined": true, "value": "mauve"}
#
# `defined` is what earns the envelope rather than printing the bare value.
# A settable path need not be a DEFINED one — nothing has to have named an
# `attrsOf` key yet — and `"value": null` alone cannot tell that apart from an
# option whose type allows null and which is set to null, which is precisely the
# pair `haus unset` creates. The plain rendering says the difference in prose on
# stderr; JSON has to say it in a field.
#
# ⚠️ `defined: false` is "this evaluation produced no value", which is USUALLY
# the undefined key above and is not only that: a value nix cannot render as
# JSON lands here too. So the reason goes to stderr rather than being swallowed
# — the field says what happened, the stream says why.
settings_json_row() { # settings_json_row <path> [<value as json>]
  if [ "$#" -ge 2 ]; then
    jq -n --arg path "$1" --argjson value "$2" '{ $path, defined: true, $value }'
  else
    jq -n --arg path "$1" '{ $path, defined: false, value: null }'
  fi
}

# True when a path is GONE rather than broken. An `attrsOf` key exists only
# because something defined it, so withdrawing the last definition of
# `displays.<uuid>.uiScale` takes the key away instead of revealing a value
# underneath — the reset working, but failing to evaluate exactly like a real
# conflict does. The nearest ancestor that still evaluates tells them apart: a
# conflict takes the tree above it down too, a vanished key doesn't.
settings_path_vanished() {
  local host="$1" p="$2"
  while [ "${p%.*}" != "$p" ]; do
    p="${p%.*}"
    settings_eval_json "$host" "$p" >/dev/null 2>&1 && return 0
  done
  return 1
}

settings_literal() {
  local raw="$1" parsed lines
  # JSON covers booleans, numbers, null, lists and attrsets. A bare token is the
  # ergonomic string form (`haus set theme.accent teal`). Quoted strings also
  # work when a caller wants to distinguish "true" from the boolean true.
  if parsed="$(printf '%s' "$raw" | jq -c '.' 2>/dev/null)"; then
    lines="$(printf '%s\n' "$parsed" | wc -l | tr -d ' ')"
  else
    lines=0
  fi
  if [ "$lines" = 1 ]; then
    printf 'builtins.fromJSON %s' "$(jq -Rn --arg value "$parsed" '$value')"
  else
    jq -Rn --arg value "$raw" '$value'
  fi
}

settings_restore() {
  local target="$1" backup="$2"
  if [ -n "$backup" ]; then cp -p "$backup" "$target"; else rm -f "$target"; fi
  settings_stage "$target"
}

settings_apply() {
  if [ -n "${HAUS_NO_REBUILD:-}" ]; then
    info "not rebuilding (HAUS_NO_REBUILD is set)"
  else
    cmd_rebuild
  fi
}

# `rm -f ""` is not portably a no-op, and an override that had no previous file
# is recorded as an empty backup path, so drop them one at a time.
settings_drop_backups() {
  local b
  for b in "$@"; do [ -n "$b" ] && rm -f "$b"; done
  return 0
}

# Write ONE override file. No validation, no rebuild — cmd_set owns both,
# because with several pairs neither can be per-file (see its header).
settings_write() {
  local path="$1" value="$2" dir="$3" target="$4" tmp literal attrpath
  literal="$(settings_literal "$value")"
  attrpath="$(settings_attrpath "$path")"
  tmp="$(mktemp "$dir/.haus-set.XXXXXX")"
  {
    printf '%s\n' '# Managed by haus set. Ordinary Nix: safe to inspect or edit.'
    printf '# Remove this override with: haus reset %s\n' "${path#haus.}"
    # One arg per %s: `printf FMT a b` reuses FMT, so a shared '%s\n\n' here
    # would put a blank line after the opening brace as well as before it.
    printf '%s\n\n' '{ lib, ... }:'
    printf '%s\n' '{'
    printf '  %s = lib.mkForce (%s);\n' "$attrpath" "$literal"
    printf '%s\n' '}'
  } >"$tmp"
  mv "$tmp" "$target"
  settings_stage "$target"
}

# The rollback half of the set/reset transaction, kept out of the trap body so
# the trap is one line. Reads the TX_* globals the command fills in; deliberately
# NOT `local` there, because a trap reaching into another frame's locals is the
# kind of thing that works until someone refactors. Shared by cmd_set and
# cmd_reset — restoring a backup and un-removing a file are the same operation,
# and settings_restore already treats an empty backup as "there was no file".
settings_tx_rollback() {
  local k
  for k in ${TX_TARGETS[@]+"${!TX_TARGETS[@]}"}; do
    [ "${TX_BACKUPS[$k]+set}" = set ] || continue # never got as far as touching this one
    settings_restore "${TX_TARGETS[$k]}" "${TX_BACKUPS[$k]}" || true
  done
  settings_drop_backups ${TX_BACKUPS[@]+"${TX_BACKUPS[@]}"}
}

# The offline options catalogue — every settable `haus.*` path with its type,
# its default and one line of prose, rendered from THIS machine's pinned haus by
# the same derivation as the annotated host file (modules/options-catalogue.jq).
#
# It is READ, never evaluated, and that is the whole point. `settings_option_
# exists` answers "is this settable?" by evaluating the entire darwin config,
# which is seconds — right for accepting a value, hopeless for drawing a menu of
# 200 rows or answering a Tab. So the picker and the zsh completion read this
# file and leave cmd_set's eval as the one authority on what is actually legal.
HAUS_CATALOGUE="${HAUS_CATALOGUE:-/run/current-system/sw/share/haus/options.json}"

# The value prompt's shape, read off the module system's own type prose.
#
# A type names a CLOSED set exactly when, after peeling a leading `null or ` and
# a leading `boolean or `, what's left is `boolean` or an `one of "…"` list. That
# peeling is not pedantry — it is what keeps the three real shapes apart:
#
#   boolean                                    → true / false
#   null or one of "12h", "24h"                → null / 12h / 24h
#   boolean or one of "left", "center", …      → true / false / left / center / …
#   null or positive integer, …, or value "never"
#                                              → OPEN. Has quoted tokens and is
#                                                still mostly a number, so a list
#                                                would take away every value the
#                                                option is mainly for.
#
# Prints one candidate per line, nothing at all when the set is open.
settings_type_choices() {
  local type="$1" rest
  rest="${type#null or }"
  rest="${rest#boolean or }"
  case "$rest" in
    boolean | 'one of "'*) ;;
    *) return 0 ;;
  esac
  case "$type" in "null or"*) printf 'null\n' ;; esac
  case "$type" in *boolean*) printf 'true\nfalse\n' ;; esac
  # Quotes exist in these type strings only around enum members, and `haus set`
  # takes a bare token as the string form, so strip them. A plain `boolean` has
  # none, and grep finding nothing is not a failure here.
  case "$type" in
    *'one of "'*) printf '%s' "$type" | grep -o '"[^"]*"' | tr -d '"' ;;
  esac
}

# `haus set` with nothing to set: pick the option, then the value. Fills PICK
# with the pair; returns non-zero when the user backs out of either prompt.
#
# Two prompts, and the second one's shape comes from the type — a closed set is a
# list you arrow through, everything else a text box holding the current default.
# Nothing here validates. It hands a pair to cmd_set, which owns the write, the
# type-check, the backups and the rollback; a picker that pre-judged any of that
# would be a second, weaker authority that disagrees with the first one on
# exactly the machines where it matters.
settings_pick() {
  local usage="$1" sel path type default literal prefill value line
  local -a choices=()
  PICK=()

  [ -t 0 ] && [ -t 1 ] || die "$usage"
  command -v gum >/dev/null 2>&1 || die "picking an option needs gum — $usage"
  [ -r "$HAUS_CATALOGUE" ] \
    || die "no options catalogue at $HAUS_CATALOGUE (haus rebuild installs it) — $usage"

  # Path AND prose in the row, because the filter matches the whole line: you
  # can search for `flavor` or for `light mode` and land on the same option.
  #
  # The `%-38s` here is NOT one of the fixed widths snug's table replaced, and a
  # sweep that converts it breaks the picker. This is gum's INPUT, not a report:
  # `gum filter` owns the window, does its own truncation, and hands the chosen
  # LINE back — which is parsed three lines down by taking everything before the
  # first space. The padding is what guarantees that split, and a `…` from a
  # width budget would be parsed as part of the path.
  sel="$(
    jq -r 'to_entries[] | "\(.key[5:])\t\(.value.summary)"' "$HAUS_CATALOGUE" \
      | awk -F'\t' '{ printf "%-38s %s\n", $1, $2 }' \
      | gum filter --height 20 --placeholder 'which option?' --prompt 'haus set '
  )" || return 1
  # Padded columns, and no `haus.*` path contains a space — so the first field
  # is the path however long it ran.
  path="${sel%% *}"
  [ -n "$path" ] || return 1

  type="$(jq -r --arg p "haus.$path" '.[$p].type' "$HAUS_CATALOGUE")"
  default="$(jq -r --arg p "haus.$path" '.[$p].default // ""' "$HAUS_CATALOGUE")"
  literal="$(jq -r --arg p "haus.$path" '.[$p].literal' "$HAUS_CATALOGUE")"
  say "$path"
  info "type: $type"
  [ -n "$default" ] && info "default: $default"

  while IFS= read -r line; do choices+=("$line"); done < <(settings_type_choices "$type")

  if [ "${#choices[@]}" -gt 0 ]; then
    # --selected puts the cursor on the current default rather than the top of
    # the list, so the first thing you see is what the machine does today. Only
    # when the default is actually one of the choices, though: gum takes it as a
    # comma-separated list of items to pre-select, and rather than find out per
    # gum release what an unknown one does, don't hand it one. Every option's
    # default type-checks, so this holds for all of today's; it's the option with
    # no default at all that this is here for.
    local bare
    local -a selected=()
    bare="$(printf '%s' "$default" | tr -d '"')"
    for line in "${choices[@]}"; do
      if [ "$line" = "$bare" ]; then selected=(--selected "$line"); fi
    done
    value="$(printf '%s\n' "${choices[@]}" | gum choose ${selected[@]+"${selected[@]}"})" \
      || return 1
  else
    # Prefill only a default that would round-trip. `haus set` reads its value as
    # JSON (settings_literal), and a Nix-only default like `[ "self" "nebelung" ]`
    # is not JSON — handing it back as the starting text would quietly turn the
    # whole list into one string the moment someone pressed Enter. Those get an
    # empty box, with the default still on screen above it.
    prefill=""
    if [ "$literal" = true ] && printf '%s' "$default" | jq . >/dev/null 2>&1; then
      prefill="$default"
    fi
    value="$(gum input --value "$prefill" --placeholder "${default:-value}" \
                       --prompt "$path = ")" || return 1
  fi
  # Every way out of here says so. Backing out of a prompt is a perfectly normal
  # thing to do, and the alternative — cmd_set exiting 0 with nothing printed —
  # is indistinguishable from the command having quietly failed. An empty text
  # box counts as backing out: pressing Enter on nothing is how people leave a
  # prompt they opened by accident, and the empty STRING is still reachable as
  # `""`, which is also how you write it on the command line.
  if [ -z "$value" ]; then
    info "nothing entered — $path is unchanged"
    return 1
  fi
  if ! gum confirm "set $path = $value, then rebuild?"; then
    info "left $path alone"
    return 1
  fi
  PICK=("$path" "$value")
}

# `haus set` takes PAIRS: `haus set theme.flavor latte theme.systemAppearance flavor`.
#
# Not ergonomics — arithmetic. settings_apply is a full rebuild, so N calls is N
# rebuilds, and the intents that genuinely need more than one option (pounce's
# "Switch to light mode", which is theme.flavor AND theme.systemAppearance) would
# otherwise rebuild twice AND leave the machine sitting in the half-done state in
# between. One call, one validation, one rebuild.
#
# Every file is written BEFORE anything is validated, and ANY failure between the
# first write and the last type-check restores ALL of them — via an EXIT trap, not
# just the explicit rejection path. That distinction is the whole safety property
# and it was found by the pre-PR assurance pass: `set -e` has plenty of other ways
# out of here (a stale `.git/index.lock` making `settings_stage` fail is the
# realistic one), and with a single pair those aborted before anything else was on
# disk. With pairs they'd leave file 1 written, staged, unvalidated and un-restored
# — precisely the half-done machine this command exists to prevent, with no error
# the user can act on. (`ERR` would not do: the script has `set -e` but not `set -E`,
# so an ERR trap isn't inherited into settings_write/settings_stage.)
#
# Validating each pair as it lands is the other tempting shape and it is worse: it
# leaves pairs 1..n-1 applied when pair n is refused, which is the same partial
# write, arrived at deliberately.
cmd_set() {
  # cmd_unset delegates here, and quoting `haus set`'s pair syntax at someone who
  # typed `haus unset` names a command they didn't run — so it may override this.
  local usage="${TX_USAGE:-usage: haus set <haus.path|relative.path> <value> [<path> <value>…]}"
  # No arguments is not a usage error any more — it's the picker. `haus unset`
  # can't land here with none (it dies on its own usage first), so TX_USAGE
  # being set is enough to keep this out of a delegated call's way.
  if [ "$#" -eq 0 ] && [ -z "${TX_USAGE:-}" ]; then
    settings_pick "$usage" || exit 0
    set -- "${PICK[@]}"
  fi
  [ "$#" -ge 2 ] && [ $(( $# % 2 )) -eq 0 ] || die "$usage"
  local host dir path target backup clash seen="" i err
  local -a paths=() values=() results=()
  TX_TARGETS=() TX_BACKUPS=()
  host="$(host_name)"
  dir="$(settings_host_dir)"

  # Phase 1 — resolve every pair and refuse anything we can't own, before a
  # single byte is written. A path named twice is an error rather than
  # last-one-wins: the second write's "backup" would be the first write's file,
  # so a restore would leave the first value in place and report failure.
  while [ "$#" -gt 0 ]; do
    path="$(settings_path "$1")"
    settings_option_exists "$host" "$path"
    case "$seen" in *"|$path|"*) die "$usage — ${path#haus.} named twice" ;; esac
    seen="$seen|$path|"
    target="$(settings_file "$path")"
    if [ -e "$target" ] && ! grep -q '^# Managed by haus set\.' "$target"; then
      die "$target already exists and is not managed by haus; edit it by hand"
    fi
    if clash="$(settings_overlap "$path" ${paths[@]+"${paths[@]}"})"; then
      die "${path#haus.} overlaps ${clash#haus.}, which is already set — \
reset one of them first (haus reset ${clash#haus.})"
    fi
    paths+=("$path"); values+=("$2"); TX_TARGETS+=("$target")
    shift 2
  done

  # Phase 2 — from here until phase 3 succeeds, ANY exit rolls everything back.
  mkdir -p "$dir"
  trap 'settings_tx_rollback' EXIT
  for i in "${!paths[@]}"; do
    # Register the backup only once the copy is IN it. Appending first and
    # filling it after would, on a failed `cp`, leave the rollback restoring an
    # empty file over the user's previous override — a worse outcome than the
    # failure itself. An unregistered temp file is the cheap side of that trade.
    if [ -e "${TX_TARGETS[$i]}" ]; then
      backup="$(mktemp)"; cp -p "${TX_TARGETS[$i]}" "$backup"; TX_BACKUPS+=("$backup")
    else
      TX_BACKUPS+=("")
    fi
    settings_write "${paths[$i]}" "${values[$i]}" "$dir" "${TX_TARGETS[$i]}"
  done

  # Phase 3 — one evaluation per path, keeping the value so phase 4 needn't
  # re-evaluate. The first rejection reports and lets the trap do the restoring.
  err="$(mktemp)"
  for i in "${!paths[@]}"; do
    if results+=("$(settings_eval_json "$host" "${paths[$i]}" 2>"$err")"); then continue; fi
    warn "the generated override did not type-check; restored the previous file(s)."
    tail -n 12 "$err" >&2
    rm -f "$err"
    die "'${paths[$i]}' rejected that value — no config change remains"
  done
  rm -f "$err"
  trap - EXIT
  settings_drop_backups ${TX_BACKUPS[@]+"${TX_BACKUPS[@]}"}

  # Phase 4 — report everything, then rebuild ONCE.
  for i in "${!paths[@]}"; do
    say "set ${paths[$i]#haus.} = $(printf '%s' "${results[$i]}" | settings_print_json)"
    info "${TX_TARGETS[$i]} (staged as ordinary Nix)"
  done
  settings_apply
}

# `--json` is A2 of the family agent-surface standard: a read verb owes an agent
# one documented schema. Two shapes, and they mirror the two the plain rendering
# already has — a path prints ONE object, no path prints an ARRAY of them
# (`[]` when the overlay is empty, never a message where JSON was promised).
#
# Under `--json` the prose lines move out of the way rather than being reworded:
# `info` is fd 1 (see the note by the verbs), so a single "no machine-writable
# settings" line would land in the middle of the document it was describing.
cmd_get() {
  local path host dir f json found="" as_json="" rows="" a err
  local -a args=()
  for a in "$@"; do
    case "$a" in
      --json) as_json=1 ;;
      -*) die "get takes a path and --json, not '$a'" ;;
      *) args+=("$a") ;;
    esac
  done
  [ "${#args[@]}" -le 1 ] || die "usage: haus get [<haus.path|relative.path>] [--json]"

  host="$(host_name)"
  if [ "${#args[@]}" -eq 1 ]; then
    path="$(settings_path "${args[0]}")"
    # 🚨 `get` is a REPORT command, so `warn` and `info` draw on fd 1 — and
    # `settings_option_exists` warns (with a dozen lines of nix) whenever this
    # machine's option surface will not evaluate at all. Under `--json` that
    # prose lands INSIDE the document it was describing and every caller's `jq`
    # dies on it, so the whole pre-flight is redirected: diagnostics on fd 2,
    # stdout for the object alone.
    if [ -n "$as_json" ]; then settings_option_exists "$host" "$path" >&2
    else settings_option_exists "$host" "$path"; fi
    # A settable path need not be a defined one: nothing has to have named this
    # `attrsOf` key yet. Saying so beats printing a blank line — on stderr, so
    # `$(haus get …)` stays the value alone and this doesn't become one.
    err="$(mktemp)"
    if json="$(settings_eval_json "$host" "$path" 2>"$err")"; then
      rm -f "$err"
      if [ -n "$as_json" ]; then settings_json_row "$path" "$json"
      else printf '%s' "$json" | settings_print_json; fi
    elif [ -n "$as_json" ]; then
      # The field cannot carry the reason and stdout may not, so nix's own words
      # go to stderr: `defined: false` is nearly always the undefined key, and
      # the one time it is not, the caller can see which.
      tail -n 4 "$err" >&2
      rm -f "$err"
      settings_json_row "$path"
    else
      rm -f "$err"
      info "${path#haus.} is settable, but nothing defines it yet" >&2
    fi
    return
  fi

  dir="$(settings_host_dir)"
  if [ ! -d "$dir" ]; then
    if [ -n "$as_json" ]; then printf '[]\n'
    else info "no machine-writable settings; use: haus set <path> <value>"; fi
    return
  fi
  # No header and no indent: this is a listing, and `haus get` with no path is
  # read by eye and by pipe alike. A redirected stdout has no window to fit, so
  # snug folds nothing there — the pipe keeps whole values, exactly as the
  # `%-38s` pad did, without charging a terminal 38 cells for a path of nine.
  if [ -n "$UI_READY" ] && [ -z "$as_json" ]; then
    ui_table_clear
    ui_col option 12 3 path   left
    ui_col value   6 2 accent right
  fi
  for f in "$dir"/*.nix; do
    [ -e "$f" ] || continue
    grep -q '^# Managed by haus set\.' "$f" || continue
    path="haus.$(basename "$f" .nix)"
    json="$(settings_eval_json "$host" "$path" 2>/dev/null)" || continue
    if [ -n "$as_json" ]; then
      rows="$rows$(settings_json_row "$path" "$json")"
    elif [ -n "$UI_READY" ]; then
      ui_trow "${path#haus.}" "$(printf '%s' "$json" | settings_print_json)"
    else
      printf '%-38s %s\n' "${path#haus.}" "$(printf '%s' "$json" | settings_print_json)"
    fi
    found=1
  done
  if [ -n "$as_json" ]; then
    # `jq -s` over an empty stream is `[]`, which is the answer an overlay with
    # nothing in it deserves — a caller's `.[]` then iterates nothing instead of
    # dying on the message the plain rendering prints in its place.
    printf '%s' "$rows" | jq -s '.'
    return
  fi
  if [ -n "$UI_READY" ]; then ui_table_data 0; fi
  [ -n "$found" ] || info "no machine-writable settings; use: haus set <path> <value>"
}

# Variadic for the same arithmetic as cmd_set, which does the actual work: every
# path becomes a `<path> null` pair, so N paths are one validation and one
# rebuild, all-or-nothing, and an option whose type has no null takes the whole
# call down rather than leaving the others applied.
cmd_unset() {
  # Bash's dynamic scope makes this local visible inside cmd_set, so a rejection
  # from down there quotes the invocation the user actually typed rather than
  # `haus set`'s pair syntax.
  local TX_USAGE="usage: haus unset <haus.path|relative.path> [<path>…]"
  [ "$#" -ge 1 ] || die "$TX_USAGE"
  local p
  local -a pairs=()
  for p in "$@"; do pairs+=("$p" null); done
  # Validation after writing is intentional: the module system is the one
  # authority on whether this option's type admits null.
  cmd_set "${pairs[@]}"
}

# The mirror image of cmd_set, phase for phase, and variadic for the same reason:
# an intent that took two options to express takes two files to withdraw, and
# doing that as two calls is two rebuilds with a half-undone machine in between
# (`haus set theme.flavor latte theme.systemAppearance flavor` is light mode; one
# `haus reset theme.flavor theme.systemAppearance` is the way back).
#
# Removing a file can fail validation exactly like writing one — not because
# some other option breaks (nix is lazy; phase 3 only forces the path being
# withdrawn, so it would never see that), but because the definition underneath
# is the one the override was masking: two host/desktop modules that conflict on
# this option evaluate fine while mkForce sits on top of them and stop doing so
# the moment it is removed. So the removals are a transaction too, under the same
# EXIT trap — settings_restore puts a backed-up file back, which is all
# "un-remove" means here.
cmd_reset() {
  local usage="usage: haus reset <haus.path|relative.path> [<path>…]"
  [ "$#" -ge 1 ] || die "$usage"
  local host path target backup seen="" i err
  local -a paths=() results=() inherited=()
  TX_TARGETS=() TX_BACKUPS=()
  host="$(host_name)"

  # Phase 1 — resolve every path and refuse anything we can't own, before a
  # single file is removed. A path that has no override is noted and dropped
  # rather than fatal: the caller asked for it to inherit, and it already does,
  # so `haus reset a b` still withdraws b. Noted, not said — a later path can
  # still take the whole call down, and a transcript that reported success for
  # one path before dying reads as if something happened.
  while [ "$#" -gt 0 ]; do
    path="$(settings_path "$1")"
    settings_option_exists "$host" "$path"
    case "$seen" in *"|$path|"*) die "$usage — ${path#haus.} named twice" ;; esac
    seen="$seen|$path|"
    target="$(settings_file "$path")"
    if [ ! -e "$target" ]; then
      inherited+=("${path#haus.} already inherits the host/desktop/room value ($(settings_eval_json "$host" "$path" 2>/dev/null | settings_print_json))")
      shift; continue
    fi
    grep -q '^# Managed by haus set\.' "$target" \
      || die "$target is not managed by haus; refusing to remove it"
    paths+=("$path"); TX_TARGETS+=("$target")
    shift
  done
  # Nothing was overridden, so nothing changed — say so, but don't spend a
  # rebuild on it.
  if [ "${#paths[@]}" -eq 0 ]; then
    for i in ${inherited[@]+"${!inherited[@]}"}; do say "${inherited[$i]}"; done
    return 0
  fi

  # Phase 2 — from here until phase 3 succeeds, ANY exit puts every file back.
  trap 'settings_tx_rollback' EXIT
  for i in "${!paths[@]}"; do
    # Register the backup only once the copy is IN it — see cmd_set's phase 2.
    backup="$(mktemp)"; cp -p "${TX_TARGETS[$i]}" "$backup"; TX_BACKUPS+=("$backup")
    rm -f "${TX_TARGETS[$i]}"
    settings_stage "${TX_TARGETS[$i]}"
  done

  # Phase 3 — one evaluation per path, keeping the inherited value for phase 4.
  err="$(mktemp)"
  for i in "${!paths[@]}"; do
    if results+=("$(settings_eval_json "$host" "${paths[$i]}" 2>"$err")"); then continue; fi
    # The failed substitution already appended "", which phase 4 reads as "gone".
    if settings_path_vanished "$host" "${paths[$i]}"; then continue; fi
    warn "removing the override did not type-check; restored the previous file(s)."
    tail -n 12 "$err" >&2
    rm -f "$err"
    die "'${paths[$i]}' cannot inherit its underlying value — no config change remains"
  done
  rm -f "$err"
  trap - EXIT
  settings_drop_backups ${TX_BACKUPS[@]+"${TX_BACKUPS[@]}"}
  rmdir "$(settings_host_dir)" 2>/dev/null || true

  # Phase 4 — report everything, then rebuild ONCE.
  for i in ${inherited[@]+"${!inherited[@]}"}; do say "${inherited[$i]}"; done
  for i in "${!paths[@]}"; do
    if [ -n "${results[$i]}" ]; then
      say "reset ${paths[$i]#haus.}; now inherits $(printf '%s' "${results[$i]}" | settings_print_json)"
    else
      say "reset ${paths[$i]#haus.}; nothing defines it now"
    fi
  done
  settings_apply
}

# ---- haus options -----------------------------------------------------------
# Refresh hosts/<host>/options.nix — the annotated catalogue of every
# haus.* option at its default, all commented out. The bootstrap writes it
# once at install; this is how it gets refreshed when `haus update` moves the
# pin and haus grows options that weren't in your copy.
#
# Read from the SYSTEM PROFILE, not built on demand: core ships it (see
# core/default.nix), so what you get is exactly the option surface this machine
# is pinned to. Nothing here evaluates or fetches anything.
#
# It never silently overwrites. Once you've uncommented lines in your copy that
# file is yours, so a re-run writes options.nix.new beside it and shows the
# diff — you merge what you want. --force is the "I never edited it" shortcut.
HOST_TEMPLATE="${HAUS_HOST_TEMPLATE:-/run/current-system/sw/share/haus/host-options.nix}"

cmd_options() {
  local force="" host dir dest
  [ "${1:-}" = "--force" ] && force=1

  [ -f "$HOST_TEMPLATE" ] \
    || die "no option template at $HOST_TEMPLATE — this machine's haus predates it; run 'haus update' first."

  host="$(host_name)"
  dir="$CONSUMER/hosts/$host"
  dest="$dir/options.nix"
  [ -d "$dir" ] || die "no host directory at $dir"

  if [ ! -e "$dest" ] || [ -n "$force" ]; then
    cp -f "$HOST_TEMPLATE" "$dest"
    chmod u+w "$dest"   # it comes out of the store read-only
    say "wrote $dest ($(grep -c '^  # haus\.' "$dest") options, all commented out)"
  elif cmp -s "$HOST_TEMPLATE" "$dest"; then
    say "$dest is already current."
    return 0
  else
    cp -f "$HOST_TEMPLATE" "$dest.new"
    chmod u+w "$dest.new"
    say "your options.nix differs from this pin's — wrote $dest.new instead."
    diff -u "$dest" "$dest.new" | sed -n '1,40p' | sed 's/^/  /' || true
    info "merge what you want, then: rm $dest.new   (or: haus options --force to replace)"
  fi

  # The catalogue only does anything if the host file imports it. Say so rather
  # than editing default.nix behind their back — that file is hand-written.
  if ! grep -q '\./options\.nix' "$dir/default.nix" 2>/dev/null; then
    printf '\n'
    warn "$dir/default.nix doesn't import it yet. Add this line inside the { … } block:"
    printf '\n      imports = [ ./options.nix ];\n\n'
  fi
}

cmd_doctor() {
  local uid; uid="$(id -u)"
  say "haus doctor"

  # On macOS 26 Tahoe+, a "stopped agent" is often BTM gating the /bin/sh-invoked
  # nix login item rather than a cold-boot wedge — point at `haus btm` when so.
  local osver osmajor btmhint=""
  osver="$(sw_vers -productVersion 2>/dev/null || echo 0)"; osmajor="${osver%%.*}"
  [ "${osmajor:-0}" -ge 26 ] && btmhint=" · on Tahoe+ this is often BTM: haus btm"

  # Determinate Nix (core assumes it owns the daemon: nix.enable = false).
  if [ -f /nix/receipt.json ]; then ok "Determinate Nix installed"
  elif [ -d /nix ]; then bad "/nix exists but not Determinate — haus expects the Determinate installer"
  else bad "Nix not installed"; fi
  pgrep -qx nix-daemon && ok "nix-daemon running" || bad "nix-daemon not running"

  # Xcode CLT (pounce compiles against system Swift; git comes from here too).
  /usr/bin/xcode-select -p >/dev/null 2>&1 && ok "Xcode Command Line Tools" || bad "Xcode CLT missing — xcode-select --install"

  command -v darwin-rebuild >/dev/null 2>&1 && ok "darwin-rebuild on PATH" || bad "darwin-rebuild missing — has this machine switched yet?"

  # GUI agents — only report on the ones whose launchd plist exists (i.e. the
  # rooms you enabled). Running is good; stopped may just mean the room is off.
  echo
  say "GUI agents"
  local label name
  for pair in $(_haus_gui_agents); do
    label="${pair%%:*}"; name="${pair##*:}"
    if launchctl print "gui/$uid/$label" >/dev/null 2>&1; then
      if pgrep -qx "$name"; then ok "$name running"
      else bad "$name enabled but not running — check /tmp/$name.err.log (a wedged cold-boot agent: launchctl kickstart -k gui/$uid/$label)$btmhint"; fi
    fi
  done

  # Every manual step this machine needs, in ONE place — rendered from the deck
  # `haus permissions` walks, never from a second copy of it here. It was three
  # grants reported in three different sections before, none of them linked and
  # none of them aware of the rooms that had since grown cards of their own.
  #
  # doctor stays the READ-ONLY half: it opens nothing and prompts for nothing,
  # because a health check that fires a permission dialog is a health check
  # people stop running. Every card still wanting a person names the command
  # that walks them.
  echo
  say "Permissions"
  _perm_report
  local pending
  pending="$(_perm_pending 2>/dev/null || echo 0)"
  [ "${pending:-0}" -eq 0 ] || info "$pending still want a person — walk them with: haus permissions"

  # Not a permission, and here anyway: the settings this RUNNING system declares
  # that macOS only reads at login. Same reader as everything above (`_haus_verdict`
  # over the built activation script — never a second copy of
  # modules/lib/restart-map.nix), and the same reason it belongs in a checklist:
  # it is a live property of this machine that nothing else will volunteer.
  #
  # `haus plan` says it BEFORE a rebuild, which is the more useful half. This is
  # the after: it answers "I set that days ago and my Mac never changed", which
  # is precisely when somebody runs doctor, and it is what 19 option descriptions
  # promise doctor will say. Silent unless the configuration writes such a
  # domain, so it costs nothing on a machine with no opinion about them.
  local waits
  waits="$(_haus_verdict waits-for-logout /run/current-system/activate)"
  if [ -n "$waits" ]; then
    echo
    say "Waiting for a login"
    warn "these settings are applied but macOS only reads them when a session starts, so they appear at your next login: ${waits//,/, }"
    info "  nothing is half-applied, and no rebuild can hurry it — the process that would reread these is the one that owns your session"
  fi

  # Homebrew casks are declared in nix (homebrew.casks) but live OUTSIDE Nix
  # generations: `haus rollback` swaps the system profile without re-running
  # `brew bundle`, so casks never rewind with the generation — that's a
  # permanent, by-design caveat, not a fault (hence a plain note). The real
  # fault worth a ⚠ is drift: a cask installed but NOT in the declared Brewfile
  # (only possible when cleanup ≠ "zap"), which no rebuild will manage. Detect
  # it by diffing `brew list --cask` against the current system's Brewfile —
  # the one nix-darwin's activate script feeds to `brew bundle --file=`.
  if command -v brew >/dev/null 2>&1; then
    echo
    say "Homebrew"
    local installed brewfile declared undeclared count
    installed="$(brew list --cask 2>/dev/null || true)"
    count="$(printf '%s\n' "$installed" | grep -c . || true)"
    brewfile="$(grep -oE "brew bundle --file='[^']+'" /run/current-system/activate 2>/dev/null | sed "s/.*--file='//;s/'\$//" || true)"
    if [ -n "$brewfile" ] && [ -f "$brewfile" ]; then
      # Declared cask tokens, minus any tap prefix (pear-devs/pear/foo → foo),
      # so they line up with the bare names `brew list --cask` prints.
      declared="$(sed -nE 's/^cask "([^"]+)".*/\1/p' "$brewfile" | sed -E 's#.*/##')"
      undeclared="$(comm -13 <(printf '%s\n' "$declared" | sort -u) <(printf '%s\n' "$installed" | sort -u) | grep . || true)"
      if [ -z "$undeclared" ]; then
        ok "brew on PATH ($count casks, all declared)"
      else
        ok "brew on PATH ($count casks installed)"
        warn "$(printf '%s' "$undeclared" | grep -c .) undeclared cask(s) no rebuild will manage: $(printf '%s' "$undeclared" | paste -sd, - ) — declare them or 'brew uninstall --zap <cask>'"
      fi
    else
      # No readable Brewfile (unswitched machine, or path moved) — can't diff, so
      # just report the count without claiming everything is or isn't declared.
      ok "brew on PATH ($count casks installed)"
    fi
    info "casks live outside Nix generations — 'haus rollback' won't rewind them (that's by design)"
  fi

  # Nebelung ports for roster apps. modules/theme/ports.nix drops each themeable
  # roster app's theme file where that app looks for it and writes what it could
  # NOT finish here — because a file on disk only makes a theme active for apps
  # that read a fixed path.
  #
  # The ones needing a click USED to be a section of their own here, listing
  # every port including the finished ones. They are now theme's card in the
  # Permissions deck above, which reads the same report through the card's
  # `detail` — one place, and in the section a person is already scanning for
  # things that want them. The `done` rows went with it: a health check saying
  # "this theme applied correctly" about nine apps in a row is the noise that
  # makes people skip the two lines underneath that matter.

  # Agents — whether an AI agent can usefully and safely drive this machine.
  # Three separate questions, all of which have bitten someone: does it have the
  # knowledge (the skill), does the config repo orient it (an AGENTS.md), and can
  # a rebuild from an agent pane actually complete — that third one is Full Disk
  # Access, and it moved to the Permissions section above with the other grants.
  #
  # AGENTS.md is the file that matters: Codex, OpenCode, pi, Cursor, Copilot and
  # anything else that speaks agents.md read it, while Claude Code reads only
  # CLAUDE.md. So a repo with just a CLAUDE.md orients exactly one client — worth
  # saying out loud, since the agent keybind can spawn any of them.
  echo
  say "Agents"
  # The skill lands once per installed client, each in the directory that
  # client scans — the same table `skill install` writes by
  # (HAUS_AGENT_SKILL_DIRS, rendered from modules/ai/agents/homes.nix). Report
  # the first one found rather than the Claude path alone: on a codex-only
  # machine that path is legitimately absent, and saying "no skill" there sent
  # people to set an option already true.
  local skilldir=""
  local c d
  for c in $(skill_clients); do
    d="$(skill_client_dir "$c")/haus" || continue
    if [ -f "$d/SKILL.md" ]; then
      skilldir="$d"
      break
    fi
  done
  if [ -n "$skilldir" ]; then
    ok "the haus skill is installed ($skilldir)"
  elif [ -z "$HAUS_AGENT_SKILL_DIRS" ]; then
    # Off the wrapper the loop above scanned NOTHING — say that, rather than
    # advising an option that may already be true on the one output people
    # paste into bug reports.
    info "no client table in this shell (HAUS_AGENT_SKILL_DIRS is empty) — run the 'haus' on PATH to check for the skill"
  else
    info "no haus skill — set haus.ai.skill = true to let an agent change this machine"
  fi
  if [ -f "$CONSUMER/AGENTS.md" ] && [ -f "$CONSUMER/CLAUDE.md" ]; then
    ok "$CONSUMER/AGENTS.md orients any agent opened there (+ CLAUDE.md imports it)"
  elif [ -f "$CONSUMER/AGENTS.md" ]; then
    info "$CONSUMER/AGENTS.md orients most agents, but Claude Code reads only CLAUDE.md — add one holding '@AGENTS.md'"
  elif [ -f "$CONSUMER/CLAUDE.md" ]; then
    info "$CONSUMER/CLAUDE.md orients Claude Code only — Codex and OpenCode read AGENTS.md; move the rules there and leave '@AGENTS.md' behind"
  elif [ -f "$skilldir/consumer-AGENTS.md" ]; then
    # `install -m 644`, never `cp`: the starter pair are symlinks into the Nix
    # store, whose files are r--r--r--. A plain `cp` preserves that mode, so the
    # user lands on an AGENTS.md their editor refuses to save — on the one file
    # the whole point of copying is to then edit.
    info "nothing orients an agent opened in your config — start from haus's pair: install -m 644 $skilldir/consumer-AGENTS.md $CONSUMER/AGENTS.md && install -m 644 $skilldir/consumer-CLAUDE.md $CONSUMER/CLAUDE.md"
  else
    info "nothing orients an agent opened in your config, and the starter pair isn't here to copy — set haus.ai.skill = true, rebuild, then re-run 'haus doctor'"
  fi
  # The third agent question — can a rebuild from an agent pane complete? — is
  # Full Disk Access, and it is reported once, under Permissions above, rather
  # than a second time here: a grant stated in two sections is two places to
  # correct when the wording is wrong.

  # Secrets — the declaration (secretspec.toml) rebuilds with Nix, but the
  # VALUES live in the provider and may need entering once per machine.
  echo
  say "Secrets"
  if command -v secretspec >/dev/null 2>&1; then
    local provider
    provider="$(sed -n 's/^provider *= *"\(.*\)"/\1/p' "$HOME/.config/secretspec/config.toml" 2>/dev/null | head -1)"
    if [ -n "$provider" ]; then ok "secretspec on PATH (default provider: $provider)"
    else warn "no default provider — set haus.secrets.provider, or run: secretspec config init"; fi
    # What the ROOMS on this machine declared (haus._contrib.secrets, rendered
    # by the secrets room). `--ok` prompts for nothing and prints nothing —
    # doctor may never be the thing that pops a dialog.
    if [ -f "$HOME/.config/haus/secretspec.toml" ] && command -v haus-secret >/dev/null 2>&1; then
      if haus-secret --ok; then
        ok "no room on this Mac is waiting on a secret value"
      else
        bad "a room here is waiting on a secret value — 'haus-secret --status' says which (and whether the provider is even reachable), 'haus-secret --check' fills them in"
      fi
    fi
    # If your config flake declares secrets, verify their values are present.
    # Missing values are for `set`; --no-prompt is what keeps the check from
    # trying to fill them in here, and the </dev/null stays for the stdin
    # hygiene every doctor probe wants (see `_perm_run` below).
    #
    # The --reason is not decoration: `require_reason` (secretspec's own
    # default, "agents") refuses a bare `check` run from an AGENT pane, and a
    # refusal is indistinguishable from a missing value here — so without it
    # doctor drew a red "missing secret values" on a machine whose secrets are
    # all present, but only when an agent ran it. What it resolves is presence
    # and what it prints is never a value, which is the reason `haus-secret`'s
    # report paths give too. It does NOT inherit their other guard: those gate
    # a live check on `PROVIDER_ITEM_ACL`, and this call has no such gate, so
    # on the login keychain a rebuild that moved secretspec's store path can
    # still make THIS line raise one dialog per secret in the consumer's own
    # manifest. Pre-existing, and the deck's rule says it should not stay.
    if [ -f "$CONSUMER/secretspec.toml" ]; then
      if (cd "$CONSUMER" && secretspec check --no-prompt \
        --reason "haus doctor: report whether this config flake's declared secrets have values (no value is read out)" \
        </dev/null >/dev/null 2>&1); then
        ok "all secrets in $CONSUMER/secretspec.toml have values"
      else
        bad "missing secret values — run: cd $CONSUMER && secretspec check"
      fi
    fi
  else
    bad "secretspec missing — 'haus rebuild' installs it (the secrets room)"
  fi
}

# ---- haus report -------------------------------------------------------------
# The in-product door to haus's bug form: it opens the form with the diagnostics
# field already answered. The palette's *Report haus Issue* row is one line that
# runs this, and a `curl | bash` user with no palette at all still has a door.
#
# There is no telemetry in anything haus ships and there never will be, so the
# issue form is not one feedback channel among several — it is the only one (the
# workshop's docs/bug-reports.md). Its third field asks the reporter to run
# `haus doctor` and paste the output: two steps for a report to get lost in, and
# a third for it to arrive truncated from because a terminal scrolled. haus can
# answer that field itself.
#
# Three things here are easy to get wrong and NONE of them fails loudly:
#
#   `?template=bug.yml`, never `?title=&body=`. A `body=` prefill opens GitHub's
#   BLANK editor and walks straight past the form — its four fields, its "wrong
#   repo? file it anyway" preamble, and the `bug`/`triage` labels it applies. An
#   issue is still filed, so nothing anywhere errors; the report just arrives
#   shapeless, every time. The palette row hand-built exactly that URL from
#   before the forms existed until this landed, and pounce's did the same for a
#   year (its own report-issue-pounce.sh carries the story).
#
#   Only `diagnostics` is prefilled. `what` is the report, `area` is the
#   reporter's guess, `anything` is optional by design — filling any of them in
#   is putting words in their mouth, and the old row pre-blocked `what` with a
#   markdown skeleton. `diagnostics` is the one field haus answers better than
#   the person can, which is the whole argument for the door.
#
#   Nothing in the block may want redacting: it lands in a PUBLIC issue, and a
#   field haus filled in is a weaker kind of consent than one the reporter
#   typed. See report_redact.
REPORT_REPO="hausfold/haus"
REPORT_FORM="https://github.com/$REPORT_REPO/issues/new?template=bug.yml"

# Above this many characters of URL, drop the prefill: the block goes to stdout
# (and, with no terminal to read it, the pasteboard) and the form opens empty.
#
# The number is NOT the ~8 KB GitHub refuses past, and that is the trap. A
# reporter who is signed OUT is bounced to `/login?return_to=<this whole URL
# again>`, and that redirect breaks first — with a 500, on GitHub's side, for
# exactly the person filing their first issue. Measured against the real form
# (2026-09-01): 6.6 KB of URL redirects fine, 6.9 KB comes back 500, and the raw
# 414 doesn't start until 8.3 KB. 6000 keeps ~800 characters of margin, and is
# the number every other door in the family carries.
#
# It is a LIVE path here rather than a guard rail: `haus doctor` grows a line per
# permission card and per room, and on a full hacker machine the block already
# encodes to ~6.9 KB. Most reports from a finished desktop take the overflow
# branch, which is why that branch has to be as good as the prefill.
REPORT_URL_MAX=6000

# The reporter's home directory, written back as `~`.
#
# `haus doctor` names real paths — $CONSUMER, the skill directory, a theme port
# under ~/Library — and every one of them starts with the reporter's own name.
# In a terminal that is fine: they typed the command and they are reading their
# own screen. In a field haus filled in for them, on its way to a public issue,
# it is a username we put there. `~` says the same thing to whoever reads it.
# (The row this replaces did worse: its footer was `scutil --get LocalHostName`,
# which on a stock Mac is the owner's full name.)
#
# The guard is not decoration: an empty or `/` HOME would rewrite every path in
# the report to nonsense. The pattern is quoted so a home directory containing a
# glob character stays a literal.
report_redact() {
  local home="${HOME:-}"
  # Trailing slashes come off FIRST and all of them: `HOME=//` survives a single
  # `%/` as `/`, and `/` as a needle rewrites every path in the report — and
  # every slash in its prose — to `~`.
  while [ "$home" != "${home%/}" ]; do home="${home%/}"; done
  case "$home" in "" | /) printf '%s' "$1"; return 0 ;; esac
  printf '%s' "${1//"$home"/\~}"
}

# What haus knows and the reporter would otherwise have to look up, above the
# doctor report the form asks for: which haus this is, which Mac, which desktop.
# Facts about the machine's haus, never about its owner — the host's name is
# deliberately absent, because it tells a maintainer nothing and on a stock Mac
# it is a person's name.
report_header() {
  local lock="$CONSUMER/flake.lock" rev="" when="" from="" ident
  if [ -f "$lock" ]; then
    rev="$(jq -r '.nodes.haus.locked.rev // "" | .[0:12]' "$lock" 2>/dev/null || true)"
    when="$(jq -r '.nodes.haus.locked.lastModified // empty' "$lock" 2>/dev/null || true)"
    # A machine can pin a FORK, and a bug in one is not a bug in the other —
    # said only when it isn't ours, so the usual report carries no noise.
    from="$(jq -r '.nodes.haus.original | select(.owner and .repo) | "\(.owner)/\(.repo)"' "$lock" 2>/dev/null || true)"
  fi
  ident="haus ${rev:-unpinned}"
  [ -n "$when" ] && ident="$ident ($(date -r "$when" '+%Y-%m-%d' 2>/dev/null || echo '?'))"
  case "$from" in "" | "$REPORT_REPO") ;; *) ident="$ident from $from" ;; esac
  printf '%s\n' "$ident"
  printf 'macOS %s (%s)\n' \
    "$(sw_vers -productVersion 2>/dev/null || echo '?')" \
    "$(sw_vers -buildVersion 2>/dev/null || echo '?')"
  printf '%s\n' "$(sysctl -n hw.model 2>/dev/null || echo 'unknown Mac')"
  # A missing flake is a legal state for this verb (see the guard above the
  # dispatch), and `hacker` — desktop_selected's answer for a flake with no
  # `desktop =` line, which is what mkHaus would really install — would be a
  # guess dressed as a fact in a bug report.
  if [ -r "$FLAKE" ]; then
    printf 'desktop: %s\n' "$(desktop_selected)"
  else
    printf 'desktop: unknown — no config flake at %s\n' "$CONSUMER"
  fi
}

cmd_report() {
  local quiet="" a
  for a in "$@"; do
    case "$a" in
      # One spelling, and no short alias: an alias nobody documents is surface
      # you cannot remove later, because you cannot know who found it.
      --print) quiet=1 ;;
      *) die "report takes no '$a' — 'haus report', or 'haus report --print' for the block and the link without opening a browser." ;;
    esac
  done

  local block encoded url overflow=""
  # REPORT and the palette are set INSIDE the capture rather than trusted from
  # the caller. Without REPORT, doctor's section headers go to fd 2 (see the note
  # by the verbs) and the block arrives as an unlabelled list of ticks; without
  # the empty C_*, every line of it carries a colour escape into a public issue,
  # because those are resolved once at load against the real fd 1 and a command
  # substitution never re-measures them.
  block="$(REPORT=1; C_OFF=; C_FOG=; C_OK=; C_WARN=; C_ERR=; C_MUT=; report_header; echo; cmd_doctor)" || true
  block="$(report_redact "$block")"

  # Strict percent-encoding, UTF-8 byte by byte. `jq @uri` rather than a
  # hand-rolled loop, and not because it is shorter — an encoder built from a
  # "characters allowed in a query" set (which is what `URLComponents` and most
  # one-liners use) CONTAINS `+`, so it leaves it literal and the receiving
  # server reads it back as a space. doctor prints `Tahoe+` on every Mac running
  # one, and a pounce-style report prints `cmd+space` on nearly every line.
  #
  # What jq keeps unencoded is RFC 2396's unreserved set (3986's, plus
  # `!~*'()`) — sub-delims, legal in a query and returned verbatim, so the
  # round trip is exact either way. `+`, `&`, `=`, `#`, `%` and space are all
  # encoded, which is the whole of what this has to get right. jq is already
  # load-bearing here (the permissions deck is jq), so it adds no dependency.
  encoded="$(printf '%s' "$block" | jq -sRr @uri)"
  url="$REPORT_FORM&diagnostics=$encoded"
  if [ "${#url}" -gt "$REPORT_URL_MAX" ]; then
    url="$REPORT_FORM"
    overflow=1
  fi

  printf '%s\n\n%s\n' "$block" "$url"

  if [ -n "$overflow" ]; then
    printf '\n'
    # The block is already on stdout, which is where a CLI puts it. A palette row
    # has no stdout anyone will ever read, so that is the one case worth writing
    # to the reporter's own pasteboard — the door's single write, to their
    # clipboard, and it is still the reporter who presses Submit.
    #
    # The gate is EITHER stream, the same conservative reading of "is a human
    # watching" the verbose gate up by the rebuild front end takes: with
    # `haus report >out.txt` from a terminal, fd 1 is a file and fd 2 is still
    # the person, so a clipboard they did not ask for is a clipboard we took.
    # `--print` is excluded whatever the streams say, because it means "hand me
    # the text" — `haus report --print | pbcopy` must not find the clipboard
    # already taken by a copy it never asked for.
    if [ -t 1 ] || [ -t 2 ] || [ -n "$quiet" ]; then
      # 7 KB of scrollback is the truncation problem this door exists to remove,
      # so name the command that hands it over whole rather than saying "select
      # the text above".
      info "too long to prefill — paste the block above into the form's diagnostics field, or: haus report --print | pbcopy"
    elif printf '%s\n' "$block" | pbcopy 2>/dev/null; then
      info "too long to prefill — copied to the clipboard instead."
      # Reached only from the palette row (no terminal on either stream, and a
      # browser about to open), where this banner is the only way the person
      # learns there is something to paste — an empty field they were not told
      # about is the silent failure this whole door exists to stop.
      #
      # `--kind fault` rather than `note`, and that is the difference between
      # arriving and not: under a Focus, trill's standard policy banners `fault`
      # and files everything else in the inbox (its `FocusPolicy.standard` —
      # `{fault: banner, ask: ledge}`, fallback `inbox`), so a `note` would be
      # silently filed on exactly the machine that is most likely to be in one.
      # Not `--urgency critical`, which would also outrank quiet hours: a bug
      # report at 3am can wait for the inbox.
      if command -v haus-notify >/dev/null 2>&1; then
        haus-notify --source haus.report --kind fault --symbol ladybug \
          --title "Paste your haus report" \
          --body "It was too long to fill in for you, so it's on your clipboard — paste it into the form's diagnostics field." \
          >/dev/null 2>&1 || true
      fi
    else
      info "too long to prefill — run 'haus report --print' in a terminal, then paste the block into the diagnostics field."
    fi
  fi

  [ -z "$quiet" ] || return 0
  # Nothing is SENT from here: this opens a page with one field filled in, and
  # the report exists only once the reporter presses Submit.
  open "$url" || die "couldn't open a browser — the link is above."
}

# ---- the agent skill ---------------------------------------------------------
# A3 of the family agent-surface standard (docs/agent-surface.md in the
# workshop): every hausfold tool prints its own skill, and can write it into a
# client that has not got it. `perch skill`, `trill skill`, `factory skill` and
# this one are the same sixty lines, deliberately — an agent that has learned
# the verb on one of them has learned it on all four.
#
# 🚨 IT PRINTS THE RENDERED COPY, never `modules/ai/agents/SKILL.md` beside it.
# That file is a TEMPLATE: its version line is the literal `@hausVersion@`, and
# `agents/skill.nix` substitutes it on the way into the store, alongside the
# `references/` pages it renders from the module system and the room registry.
# Reading the source would put `@hausVersion@` in front of a user and hand an
# agent an option reference that does not exist.
#
# So the store path is handed IN, by the wrapper that builds this script
# (modules/core/default.nix) — exactly the way `HAUS_UI_SH` is, and for exactly
# the same reason: haus.sh is `builtins.readFile`'d into a store binary, so
# `dirname $0` is /nix/store and a haus user has no checkout of anything to look
# beside. Nothing else can supply it. modules/ai INSTALLS this skill into each
# client, but core may not read that room's config, and `haus skill` has to work
# on a machine with the AI room switched off — the skill is a property of the
# haus CLI, not of a room a desktop can turn off.
HAUS_SKILL_DIR="${HAUS_SKILL_DIR:-}"

# The client table — which agent clients exist and where each keeps its skills
# directory — handed in the same way and from the same room: the wrapper
# renders modules/ai/agents/homes.nix into `claude=.claude/skills:codex=…`
# (home-relative, colon-separated). PARSED here, never restated: this file
# used to carry the table as a bash case, and test/agent-surface.bats was the
# only thing holding the two spellings equal.
HAUS_AGENT_SKILL_DIRS="${HAUS_AGENT_SKILL_DIRS:-}"

# Sets SKILL_DIR rather than printing it, so its refusal happens in the
# CALLER's shell. A `dir="$(skill_dir)"` would run the check in a subshell,
# where `die`'s exit ends the subshell alone: the message reaches stderr, the
# caller gets an empty string, and what it does with that is `cat /SKILL.md`.
# `set -e` happens to catch it today, which is precisely the kind of accident
# that stops being true the first time this is called inside an `if`.
SKILL_DIR=""
skill_dir() {
  [ -n "$HAUS_SKILL_DIR" ] && [ -d "$HAUS_SKILL_DIR" ] || die \
    "no rendered skill on this machine — HAUS_SKILL_DIR names ${HAUS_SKILL_DIR:-nothing}. Run the 'haus' on PATH rather than the script."
  SKILL_DIR="$HAUS_SKILL_DIR"
}

# Every page `haus skill <name>` will print, one per line, in reading order.
# `haus` is first and is the skill itself — a list an agent is then REFUSED from
# is worse than no list, so `cmd_skill` resolves that name explicitly rather
# than leaving it to a `haus/SKILL.md` that does not exist.
skill_names() {
  local dir="$1" f
  printf 'haus\n'
  for f in "$dir"/*/SKILL.md; do [ -f "$f" ] && basename "$(dirname "$f")"; done
  for f in "$dir"/references/*.md; do [ -f "$f" ] && basename "$f" .md; done
  return 0
}

# Where the per-HOST page lives, if this machine has one. It is the one page the
# store copy cannot carry — modules/ai renders `references/this-machine.md` from
# this host's evaluated config, into each client's skills directory — so asking
# for it by name gets a path rather than "no such page".
skill_this_machine() {
  local c d
  for c in $(skill_clients); do
    d="$(skill_client_dir "$c")/haus/references/this-machine.md"
    [ -f "$d" ] && { printf '%s\n' "$d"; return 0; }
  done
  return 1
}

# The two halves of the table's parse. One directory per client, and the
# layout inside is the same for all of them — `<dir>/<skill name>/…`. The
# variable is home-relative; this function is where the `$HOME/` join lives,
# so no caller re-derives it.
#
# `skill_clients` degrades to an empty list off the wrapper (the loops over it
# simply find no clients), while asking for a NAMED client's directory with no
# table is the same broken invocation `skill_dir` refuses, in the same words.
# The die's subshell caveat from `skill_dir` does not bite here: every caller
# already handles this function returning nothing.
skill_clients() {
  local pair
  for pair in ${HAUS_AGENT_SKILL_DIRS//:/ }; do printf '%s\n' "${pair%%=*}"; done
  return 0
}
skill_client_dir() {
  [ -n "$HAUS_AGENT_SKILL_DIRS" ] || die \
    "no client table — HAUS_AGENT_SKILL_DIRS names nothing. Run the 'haus' on PATH rather than the script."
  local pair
  for pair in ${HAUS_AGENT_SKILL_DIRS//:/ }; do
    [ "${pair%%=*}" = "$1" ] && { printf '%s/%s\n' "$HOME" "${pair#*=}"; return 0; }
  done
  return 1
}

cmd_skill() {
  local sub="${1:-}"
  case "$sub" in
    "") ;;
    install) shift; cmd_skill_install "$@"; return ;;
    -*) die "skill takes a name or 'install', not '$sub'" ;;
  esac

  skill_dir
  local dir="$SKILL_DIR" path
  path="$dir/SKILL.md"
  if [ -n "${1:-}" ]; then
    [ "$#" -le 1 ] || die "one page at a time (got: $*)"
    # A name is ONE component. Not a security boundary — the caller could `cat`
    # anything they can read — but `haus skill ../../etc/passwd` answering with
    # a file is the kind of surprise a CLI should not hold.
    case "$1" in
      */* | .*) die "a skill name is one word, not a path (got '$1')" ;;
      # The skill's own name, and it has to resolve: `skill_names` offers it and
      # every refusal below prints that list, so an agent that takes the list at
      # its word would otherwise be refused twice with the same words.
      haus) ;;
      *)
        # A sibling skill is checked FIRST, so haus can grow one
        # (`<name>/SKILL.md`, factory's layout) without a reference page of the
        # same name shadowing it. The references are the second arm because
        # haus's skill is the one in the family that is a DIRECTORY: its prose
        # says "see references/options.md" and every option name lives there, so
        # a `haus skill` that could not print one would be a routing document
        # pointing at a file the reader cannot open.
        if [ -f "$dir/$1/SKILL.md" ]; then
          path="$dir/$1/SKILL.md"
        elif [ -f "$dir/references/$1.md" ]; then
          path="$dir/references/$1.md"
        elif [ "$1" = this-machine ]; then
          # Named rather than lumped in with a typo: it is a real page, it is
          # just not in the copy this prints from.
          path="$(skill_this_machine)" || die \
            "'this-machine' is rendered per host by the AI room, into each client's skills directory — this machine has no copy (haus.ai.skill is off, or nothing has rebuilt since)"
        else
          die "no skill or reference '$1' — this machine has: $(skill_names "$dir" | tr '\n' ' ')"
        fi
        ;;
    esac
  fi
  cat "$path"
}

cmd_skill_install() {
  # The refusals name what the table actually holds, so off the wrapper they
  # name an empty list — the honest answer, and the next line the user reads
  # (`skill_client_dir`'s die) says why.
  local clients; clients="$(skill_clients | xargs)"
  local dir="" client="" wrote=0 nixed=0 skipped=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      # The emptiness check comes BEFORE the shift, and it is not decoration: a
      # trailing `--dir` with nothing after it would otherwise reach `shift 2`
      # with one positional left, which returns 1 and — under `set -e` — ends
      # the command with no message on either stream.
      --dir)    dir="${2:-}";    [ -n "$dir" ]    || die "--dir needs a path"; shift 2 ;;
      --client) client="${2:-}"; [ -n "$client" ] || die "--client needs one of: $clients"; shift 2 ;;
      *) die "unknown flag '$1' — usage: haus skill install [--client ${clients// /|}] [--dir PATH]" ;;
    esac
  done

  skill_dir
  local src="$SKILL_DIR"
  local -a targets=()
  if [ -n "$dir" ]; then
    targets=("$dir")
  elif [ -n "$client" ]; then
    local d; d="$(skill_client_dir "$client")" || die "unknown client '$client' — one of: $clients"
    targets=("$d")
  else
    local c d
    for c in $(skill_clients); do
      d="$(skill_client_dir "$c")"
      [ -d "$(dirname "$d")" ] && targets+=("$d")
    done
  fi
  [ "${#targets[@]}" -gt 0 ] || die "no agent client found — name one with --client or --dir"

  # Everything modules/ai puts in a client's skills directory, minus the one
  # file core cannot render. The list matches that room's (default.nix's
  # `agentSkillFiles`) deliberately: a directory that DIFFERS from the one a
  # rebuild would write is a second layout for every later reader to handle, and
  # `haus doctor` already reads `consumer-AGENTS.md` from exactly this path to
  # decide whether to offer the starter pair — leave it out and doctor tells the
  # user to switch on the room whose work they have just done by hand.
  #
  # `references/this-machine.md` is the exception, and it is not one this can
  # close: modules/ai renders it per HOST out of the evaluated config, so it is
  # not in the store dir copied from here. `haus skill this-machine` says where
  # it does live.
  local rel dest t wrote_client=""
  local -a pages=(
    SKILL.md
    references/options.md references/rooms.md references/recipes.md
    consumer-AGENTS.md consumer-CLAUDE.md
  )
  for t in "${targets[@]}"; do
    for rel in "${pages[@]}"; do
      [ -f "$src/$rel" ] || continue
      dest="$t/haus/$rel"
      # THE HAUS MACHINE CASE, and the reason this is a refusal rather than an
      # EPERM: on any machine with `haus.ai.skill` on, every one of these is a
      # read-only symlink into the store that haus itself put there, one rebuild
      # ago. Writing is impossible and re-installing is pointless, so say which
      # of the two it is — an agent that met a bare "permission denied" here
      # would reach for sudo, and sudo would succeed at corrupting a generation.
      if [ -L "$dest" ] || [ -L "$t/haus" ]; then
        hint "skipped $dest — a symlink, so something else manages it (on a haus machine, haus.ai.skill already did)"
        nixed=$((nixed + 1)); continue
      fi
      if [ -f "$dest" ] && ! cmp -s "$src/$rel" "$dest"; then
        warn "skipped $dest — exists and differs; diff it against $src/$rel"
        skipped=$((skipped + 1)); continue
      fi
      mkdir -p "$(dirname "$dest")"
      cp "$src/$rel" "$dest"
      chmod u+w "$dest"
      say "wrote $dest"
      wrote=$((wrote + 1))
      [ -n "$dir" ] || wrote_client=1
    done
  done

  # Exit 0 either way. "Already installed, by us, and unwritable for that
  # reason" is the desired end state holding, not a failure — a non-zero here
  # would make every agent that ran this on a normal haus machine report a
  # broken command and try again with more force.
  if [ "$wrote" -eq 0 ] && [ "$skipped" -eq 0 ] && [ "$nixed" -gt 0 ]; then
    say "nothing to install: haus.ai.skill already installed this skill here, as read-only Nix symlinks."
    hint "to place a copy somewhere haus does not manage: haus skill install --dir <path>"
    return
  fi
  say "skills: $wrote written, $((nixed + skipped)) left alone"
  # The one thing a copy in a CLIENT directory costs, said at the moment it is
  # made rather than discovered at the next rebuild. `haus.ai.skill` declares
  # these exact paths as home-manager files, and home-manager will not link over
  # a real file: a consumer built by `mkHaus` renames each to `*.backup` and
  # leaves it in the user's home forever (and fails outright the second time,
  # the backup name being taken), while one composing `darwinModules.*` by hand
  # sets no `backupFileExtension` at all and simply refuses to activate.
  [ -n "$wrote_client" ] && hint \
    "these are real files, and haus.ai.skill wants to link the same paths — remove them before you switch that room on, or the next rebuild backs them up (or refuses)"
  return 0
}

# macOS 26 Tahoe and later gate LaunchDaemons/Agents whose executable isn't
# Apple-signed, via Background Task Management (BTM). Every nix login item runs
# through `/bin/sh -c "…"`, which BTM flags as "unidentified developer" and can
# silently refuse to launch at login — the agent registers but never starts, so
# your bar/tiling/palette come up dead after the upgrade. There is NO declarative
# fix: the remedy is a toggle in the BTM store, which is GUI-only (sfltool can
# dump it but not set it). So this DETECTS the condition and prints the one-time
# manual fix. A pure no-op before Tahoe — nothing to gate there.
# ---- the manual-click deck ---------------------------------------------------
# Everything a fresh haus machine needs a PERSON for: the TCC grants, the login
# items Tahoe gates, the theme ports an app only reads from its own preferences,
# the logout macOS is waiting for. One deck, because they all cost the same
# thing — somebody's attention, once — and splitting them across three commands
# is why they got missed.
#
# The deck is DATA, written per-generation by modules/core/default.nix out of
# whatever rooms contributed to `haus._contrib.permissions`. Nothing about any
# particular grant is known here: this file walks cards. That is what makes the
# deck correct on `blank`, where no room writes one, and correct after a
# rollback, where the card for a room you no longer have goes with it.
HAUS_PERMISSIONS="${HAUS_PERMISSIONS:-/run/current-system/sw/share/haus/permissions.json}"
# Cards taken on the user's word, one key per line. Only ever consulted for a
# card macOS gives no way to ask about — a real check always outranks it, in
# both directions (see _perm_status).
PERM_TAKEN="${XDG_STATE_HOME:-$HOME/.local/state}/haus/permissions-taken"

# Each card as one record, ordered — fields separated by US and a card's steps
# by RS, NOT by tabs.
#
# @tsv with `IFS=$'\t' read` looks right and silently loses every empty field:
# tab is an IFS *whitespace* character, so bash collapses runs of them and
# strips leading and trailing ones. A card with no `applies` therefore shifted
# every field after it left, and the wizard ran its pane URL as a shell check —
# no error, just cards quietly missing from the deck. US and RS are not
# whitespace, so empties survive; `flat` has already removed every newline and
# run of spaces from the prose, and no description contains a control character.
_perm_deck() {
  [ -r "$HAUS_PERMISSIONS" ] || return 0
  jq -j '
    def flat: (. // "") | gsub("\\s+"; " ") | sub("^ +"; "") | sub(" +$"; "");
    # A shell snippet may legitimately span lines, and a raw newline would end
    # the record halfway through the card. VT stands in for it here and
    # _perm_code puts it back before anything is evaluated: prose is flattened,
    # code is preserved exactly.
    def code: (. // "") | gsub("\n"; "\u000b");
    sort_by(.order, .key)[]
    | [ .key, (.title|flat), (.why|flat), (.cost|flat), (.applies|code),
        (.check|code), (.prompt|code), (.promptLabel|flat), (.pane // ""),
        ((.steps // []) | map(flat) | join("\u001e")), (.detail|code) ]
    | join("\u001f") + "\n"
  ' "$HAUS_PERMISSIONS" 2>/dev/null || true
}

# A snippet as it was written: the deck carries a multi-line one with VT in
# place of each newline (see _perm_deck), so nothing is evaluated before this
# has put them back.
_perm_code() { printf '%s' "$1" | tr '\013' '\n'; }

# A card's snippet, run so it cannot take the caller with it: a subshell, so an
# `exit` in a contributed check ends the check rather than `haus`, and silenced,
# because a probe's stderr is noise on a machine where the answer is simply no.
#
# `</dev/null` is load-bearing, not tidiness: every caller runs INSIDE
# `while read … < <(_perm_deck)`, so a snippet that reads stdin — a bare `grep`,
# a `cat`, anything with a forgotten argument — eats the rest of the deck and
# the loop ends early with status 0. Cards vanish and nothing says so, which is
# the same silent-truncation failure the record encoding above was designed to
# remove. `secretspec check` two hundred lines up closes its stdin for exactly
# this reason.
_perm_run() { ( eval "$(_perm_code "$1")" ) >/dev/null 2>&1 </dev/null; }

# ok | unmet | taken | unknown.
#
# The distinction between `ok` and `taken` is the whole honesty of this command,
# and it is trill's (Trill/UI/OnboardingAssistantPanel.swift, `confirmed` vs
# `advanced`): `ok` is macOS agreeing, `taken` is the user saying so and nothing
# more. Only the first earns a green tick. A card that HAS a check is never
# `taken` — the check outranks the note in both directions, so marking one done
# and then revoking it in System Settings reads as unmet again rather than
# staying green off a stale file.
_perm_status() {
  local key="$1" check="$2"
  if [ -n "$check" ]; then
    if _perm_run "$check"; then echo ok; else echo unmet; fi
  elif [ -f "$PERM_TAKEN" ] && grep -qxF "$key" "$PERM_TAKEN" 2>/dev/null; then
    echo taken
  else
    echo unknown
  fi
}

_perm_mark_taken() {
  mkdir -p "$(dirname "$PERM_TAKEN")"
  grep -qxF "$1" "$PERM_TAKEN" 2>/dev/null || printf '%s\n' "$1" >>"$PERM_TAKEN"
}

# Poll a check while the user is over in System Settings, so walking back to the
# terminal finds the card already green rather than a prompt asking whether they
# did it. `read -t 1` is both the one-second sleep and the escape hatch, which is
# why there is no `sleep` here: a key ends the wait immediately.
#   0 = macOS agreed   1 = timed out   2 = the user stopped waiting
_perm_wait() {
  local check="$1" i=0
  info "waiting for macOS to agree — press any key to stop"
  while [ "$i" -lt 90 ]; do
    _perm_run "$check" && return 0
    read -r -s -n 1 -t 1 _ 2>/dev/null && return 2
    i=$((i + 1))
  done
  return 1
}

# The GUI agents haus installs, `<launchd label>:<process name>`. One list, read
# by doctor's own section and by core's Login Items card — which is gated on a
# wedged agent rather than on the macOS version, so it appears when something is
# actually broken instead of on every Tahoe machine forever.
_haus_gui_agents() {
  printf '%s\n' org.nixos.aerospace:AeroSpace org.nixos.sketchybar:sketchybar com.hausfold.pounce:pounce
}

# Is anything bootstrapped into launchd but not running? That is the SYMPTOM
# Background Task Management produces, and it is readable without sudo — unlike
# the BTM store itself, which `haus btm` needs a password to open. A card gated
# on a real wedge beats a card gated on "you are on macOS 26", which every Tahoe
# machine would answer yes to whether or not anything was ever blocked.
_perm_agent_wedged() {
  local pair label name
  for pair in $(_haus_gui_agents); do
    label="${pair%%:*}"; name="${pair##*:}"
    launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1 || continue
    pgrep -qx "$name" || return 0
  done
  return 1
}

_perm_open_pane() {
  # `x-apple.systempreferences:` is not http, so `open` is the only thing that
  # follows it. Foreground and not `open -g` on purpose: this is the one place in
  # haus that MAY take the screen, because the user just pressed the button that
  # asks for it.
  open "$1" >/dev/null 2>&1 || warn "couldn't open that pane — do it by hand: $1"
}

# The report half: every card, no interaction, nothing opened. `haus doctor`
# renders its Permissions section from this, so the deck is described in exactly
# one voice and doctor can never fall behind a room that added a card.
_perm_report() {
  local key title why cost applies check prompt plabel pane steps detail status any=""
  while IFS=$'\037' read -r key title why cost applies check prompt plabel pane steps detail; do
    [ -n "$key" ] || continue
    [ -z "$applies" ] || _perm_run "$applies" || continue
    any=1
    status="$(_perm_status "$key" "$check")"
    case "$status" in
      ok) ok "$title" ;;
      taken) ok "$title — on your word (macOS gives nothing to ask)" ;;
      unmet) bad "$title — $why${cost:+ Without it: $cost}" ;;
      unknown) info "$title — $why${cost:+ Without it: $cost}" ;;
    esac
    # The card's own runtime list, under it — which apps, which entries. Only
    # for a card that still wants something: repeating the list under a green
    # tick is noise, and this is the read-only report.
    if [ -n "$detail" ] && [ "$status" != ok ] && [ "$status" != taken ]; then
      { ( eval "$(_perm_code "$detail")" ) 2>/dev/null </dev/null || true; } \
        | while IFS= read -r line || [ -n "$line" ]; do
          [ -z "$line" ] || printf '     %s\n' "$line"
        done
    fi
  done < <(_perm_deck)
  [ -n "$any" ] || info "nothing on this machine needs a click — no enabled room asks for one"
  return 0
}

# How many cards MEASURABLY are not done — macOS asked, macOS said no. This is
# the count a rebuild is allowed to end on, because it is the only one that can
# ever reach zero on its own: an unconfirmable card stays outstanding until
# somebody says otherwise, and warning about it after every single rebuild
# would train people to stop reading the last line.
_perm_unmet() { _perm_count unmet; }

# Everything still wanting a person, measurable or not. doctor's count, where a
# fuller answer is the point and nothing is competing for the last line.
_perm_pending() { _perm_count unmet unknown; }

_perm_count() {
  local key title why cost applies check prompt plabel pane steps detail want n=0
  while IFS=$'\037' read -r key title why cost applies check prompt plabel pane steps detail; do
    [ -n "$key" ] || continue
    [ -z "$applies" ] || _perm_run "$applies" || continue
    for want in "$@"; do
      [ "$(_perm_status "$key" "$check")" = "$want" ] || continue
      n=$((n + 1))
      break
    done
  done < <(_perm_deck)
  printf '%s' "$n"
}

# ---- haus permissions --------------------------------------------------------
# The wizard: one card at a time, what it is for, and a button. Everything it can
# measure it measures; everything it cannot it says so about and takes your word
# for. It opens a System Settings pane only when you press the button that says
# it will — the screen belongs to the person at it.
cmd_permissions() {
  case "${1:-}" in
    --list | -l)
      say "haus permissions"
      _perm_report
      return 0
      ;;
    --reset)
      rm -f "$PERM_TAKEN"
      say "forgot every card you'd marked done by hand — the measured ones are unaffected."
      return 0
      ;;
    "") ;;
    *) die "unknown flag '$1' — try: haus permissions [--list|--reset]" ;;
  esac

  [ -r "$HAUS_PERMISSIONS" ] \
    || die "no permissions deck at $HAUS_PERMISSIONS (haus rebuild installs it)"

  # gum draws the buttons and gum needs a terminal. Rather than half-work over a
  # pipe, fall back to the report — which is the useful thing a script wanted
  # anyway.
  if [ ! -t 0 ] || [ ! -t 1 ]; then
    _perm_report
    return 0
  fi
  # It is on the wrapper's PATH, so this should be unreachable — and unguarded
  # its absence is indistinguishable from pressing "Stop here", so the wizard
  # would quit after one card and never say why.
  command -v gum >/dev/null 2>&1 \
    || die "the wizard needs gum, which ships with haus — try 'haus permissions --list' for the report, and 'haus doctor' for why this install is missing it."


  local key title why cost applies check prompt plabel pane steps detail line
  local -a cards=()
  while IFS= read -r line; do cards+=("$line"); done < <(_perm_deck)

  say "haus permissions — everything on this Mac that needs a person"
  info "nothing here happens without you pressing for it; ⌃C leaves the rest alone"

  local total=0 confirmed=0 word=0 left=0 quit=""
  local card status choice step n waited
  for card in ${cards[@]+"${cards[@]}"}; do
    IFS=$'\037' read -r key title why cost applies check prompt plabel pane steps detail <<<"$card"
    [ -n "$key" ] || continue
    [ -z "$applies" ] || _perm_run "$applies" || continue
    total=$((total + 1))

    status="$(_perm_status "$key" "$check")"
    if [ "$status" = ok ]; then
      confirmed=$((confirmed + 1))
      ok "$title"
      continue
    fi
    if [ "$status" = taken ]; then
      word=$((word + 1))
      ok "$title — on your word"
      continue
    fi
    if [ -n "$quit" ]; then
      left=$((left + 1))
      continue
    fi

    echo
    say "$title"
    info "$why"
    # The specifics only this Mac knows — which apps, which entries. Run in the
    # same subshell every other snippet gets, and simply absent when it prints
    # nothing, so a card whose list has emptied does not draw a blank heading.
    if [ -n "$detail" ]; then
      # `|| [ -n "$line" ]` because a snippet whose output does not end in a
      # newline leaves `read` returning false on its LAST line — which it has
      # still read. Without it the final entry of every list silently vanishes.
      # `|| true` because a `detail` is a LIST, and the natural way to write
      # one is a grep or an awk that exits non-zero when the list is empty.
      # Under `set -o pipefail` that status is the pipeline's, and it would end
      # the wizard mid-walk with no message at all.
      { ( eval "$(_perm_code "$detail")" ) 2>/dev/null </dev/null || true; } \
        | while IFS= read -r line || [ -n "$line" ]; do
        [ -z "$line" ] || printf '     %s\n' "$line"
      done
    fi
    [ -z "$cost" ] || warn "without it: $cost"
    [ -n "$check" ] || info "macOS gives no way to ask about this one, so nothing here can confirm it"

    # The buttons, in the order they are worth pressing. A real system prompt
    # beats a trip to Settings whenever the service has one, which is why it is
    # first and why its label says what will happen.
    local -a buttons=()
    [ -z "$prompt" ] || buttons+=("$plabel")
    [ -z "$pane" ] || buttons+=("Open System Settings")
    if [ -n "$check" ]; then buttons+=("Check again"); else buttons+=("I've done it"); fi
    buttons+=("Skip this one" "Stop here")

    choice="$(printf '%s\n' "${buttons[@]}" | gum choose --header "$title")" || choice="Stop here"

    case "$choice" in
      "Stop here")
        quit=1
        left=$((left + 1))
        ;;
      "Skip this one")
        left=$((left + 1))
        ;;
      "I've done it")
        _perm_mark_taken "$key"
        word=$((word + 1))
        ok "noted — taken on your word, not measured"
        ;;
      "Check again")
        if _perm_run "$check"; then
          confirmed=$((confirmed + 1))
          ok "$title"
        else
          left=$((left + 1))
          bad "macOS still says no"
        fi
        ;;
      *)
        # A button that acts: fire the prompt, or open the pane and print the
        # clicks. Then wait, so the walk back to the terminal lands on a card
        # that has already turned green.
        if [ -n "$prompt" ] && [ "$choice" = "$plabel" ]; then
          _perm_run "$prompt" || true
          info "macOS should be asking now — the dialog belongs to whichever app it is about"
        else
          _perm_open_pane "$pane"
          n=0
          # Same trailing-line rule as the detail loop above: `printf '%s'`
          # emits no final newline, so the LAST step is read and then dropped
          # by a bare `while read` — three steps print as two, silently.
          while IFS= read -r step || [ -n "$step" ]; do
            [ -n "$step" ] || continue
            n=$((n + 1))
            printf '     %d. %s\n' "$n" "$step"
          done < <(printf '%s' "$steps" | tr '\036' '\n')
        fi

        if [ -n "$check" ]; then
          # 0 agreed · 1 timed out · 2 you stopped waiting. The last one is a
          # decision rather than a failure, and saying "not granted yet" to
          # somebody who just pressed a key to move on reads as an argument.
          _perm_wait "$check" && waited=0 || waited=$?
          case "$waited" in
            0)
              confirmed=$((confirmed + 1))
              ok "$title — macOS agrees"
              ;;
            2)
              left=$((left + 1))
              info "left for later — 'haus permissions' picks up where this stopped"
              ;;
            *)
              left=$((left + 1))
              warn "not granted yet — 'haus permissions' picks up where this left off"
              ;;
          esac
        elif gum confirm "Done?" --affirmative "Yes" --negative "Not yet"; then
          _perm_mark_taken "$key"
          word=$((word + 1))
          ok "noted — taken on your word"
        else
          left=$((left + 1))
        fi
        ;;
    esac
  done

  echo
  if [ "$total" -eq 0 ]; then
    say "nothing on this machine needs a click"
    info "no enabled room asks for one — that is the whole report, and it is a good one"
    return 0
  fi
  say "$confirmed of $total confirmed by macOS"
  [ "$word" -eq 0 ] || info "$word taken on your word — nothing here measured those"
  if [ "$left" -gt 0 ]; then
    warn "$left still waiting — run 'haus permissions' again whenever; it resumes, and never repeats what is done"
  else
    ok "nothing left waiting on you"
  fi
}

cmd_btm() {
  local ver major
  ver="$(sw_vers -productVersion 2>/dev/null || echo 0)"; major="${ver%%.*}"
  say "Background Task Management (BTM)"

  if [ "${major:-0}" -lt 26 ]; then
    ok "macOS $ver — pre-Tahoe; BTM doesn't gate nix daemons here. Nothing to do."
    return 0
  fi

  warn "macOS $ver: Tahoe+ can block nix login items (they run via /bin/sh) from starting."

  # The BTM store is root-only. Try passwordlessly first, then a plain sudo
  # (security's Touch ID prompts here); degrade gracefully if we can read neither.
  local dump="" blocked=""
  if dump="$(sudo -n sfltool dumpbtm 2>/dev/null)"; then :
  elif dump="$(sudo sfltool dumpbtm 2>/dev/null)"; then :
  else dump=""; fi

  if [ -n "$dump" ]; then
    # The needle has to cover every naming the family's login items use, not
    # just the org.nixos.* one nix-darwin gives an agent by default. pounce
    # carries AssociatedBundleIdentifiers = com.hausfold.pounce (modules/launcher),
    # and that key is precisely what BTM reads to attribute the item — so a
    # nixos-only grep reports "no nix items in the BTM store yet" on a machine
    # where the launcher is the one thing BTM disallowed.
    local stanzas
    stanzas="$(printf '%s\n' "$dump" | grep -A8 -iE 'nixos|hausfold|darwin-store' 2>/dev/null || true)"
    if [ -z "$stanzas" ]; then
      warn "no nix items in the BTM store yet — they appear after the first post-upgrade login."
    elif printf '%s\n' "$stanzas" | grep -qi 'disallowed'; then
      bad "nix background items are DISALLOWED by BTM — that's why daemons won't start."
      blocked=1
    else
      ok "nix background items are allowed by BTM — daemons aren't being gated."
    fi
  else
    warn "couldn't read the BTM store (needs sudo). Inspect it by hand:"
    printf '     sudo sfltool dumpbtm | grep -B2 -A8 -iE "nixos|hausfold|darwin-store"\n'
    blocked=1
  fi

  if [ -n "$blocked" ]; then
    echo
    say "one-time fix (GUI-only — BTM has no CLI to set it):"
    cat <<'EOF'
     1. System Settings → General → Login Items & Extensions
     2. Scroll to "Allow in the Background"
     3. Find the entries named "sh" — subtitle "Item from unidentified developer"
     4. Toggle them ON, then reboot
        (already ON but still blocked? flip OFF then ON to force a DB write)
EOF
  fi
}

# The tour itself is the bar's tour.sh (bar ships it; see modules/bar) —
# haus is just the terminal-shaped door to it, for the user who read the
# bootstrap's closing line instead of spotting the pill.
cmd_tour() {
  local plugin="$HOME/.config/sketchybar/plugins/tour.sh"
  [ -x "$plugin" ] || die "the tour lives in the bar — it needs the bar + windows rooms enabled."
  case "${1:-start}" in
    start) "$plugin" start && say "the tour is in the bar — follow the paw, top right." ;;
    reset) "$plugin" reset && say "tour re-armed — the dormant hint is back in the bar." ;;
    *)     die "unknown tour subcommand '$1' — try: haus tour [start|reset]" ;;
  esac
}

# ---- acquisition step D: add / desktop / remove -----------------------------
# `haus add`, `haus desktop` and `haus remove` all write ONE file — flake.nix —
# and never rebuild: acquisition never activates, and anything this cannot
# verify, it prints instead of writing.
#
# The subject's string goes into a Nix expression (the input URL), so it is
# escaped as a Nix string rather than pasted — the same rule and the same
# one-liner as haus-show.sh's `nix_string`, kept here rather than sourced
# because it is one line and the two scripts are not meant to share state.
nix_string() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\$/\\$/g'; }

# `github:ada/writer-desktop` -> writer ; `git+https://…/ada/desktop` -> desktop
# ; a `file+https` source names itself by its filename. No second registry to
# keep in step — `nix flake update <name>` already addresses this namespace,
# so the name only has to be legal and free.
derive_input_name() { # typed shape
  local typed="$1" shape="$2" n
  if [ "$shape" = file ]; then
    n="$(basename "$typed")"; n="${n%.nix}"
  else
    n="${typed%%\?*}"; n="${n%%\#*}"; n="${n%.git}"; n="${n%/}"
    n="${n##*/}"
  fi
  n="${n%-desktop}"; n="${n%-haus}"
  n="$(printf '%s' "$n" | LC_ALL=C tr -c 'A-Za-z0-9_-' '-')"
  case "$n" in [0-9]*) n="d$n" ;; esac
  [ -n "$n" ] || n="desktop"
  printf '%s' "$n"
}

# ---- flake.nix surgical edits ------------------------------------------------
# Three landmarks, at three different syntactic depths, and all three or none:
# the input (`inputs.haus.url`), the outputs BINDING PATTERN (`...` matches an
# unlisted name syntactically but does not bind it), and the `desktop = ` line
# inside `mkHaus { … }`. Line-based, not `sed -i … a\` — BSD and GNU sed
# disagree on that syntax's quoting, and a plain read/printf loop needs no
# escaping for a URL that can itself contain `&`, `\` or a sed delimiter.
#
# ⚠️ Handles exactly ONE additional pinned desktop at a time. A second `add`
# finds the outputs pattern already reads `{ haus, <name>, ... }:` rather than
# the bare scaffolded `{ haus, ... }:`, the landmark match fails, and it
# degrades to --print — the same "hand-reorganised flake" case the design's
# exit gate asks for, reached by this command's own first success rather than
# by a hand edit. Supporting N simultaneous third-party desktops is real added
# complexity this step does not need to spend on day one.
flake_backup=""
flake_stage()   { flake_backup="$(mktemp)"; cp -p "$FLAKE" "$flake_backup"; }
flake_restore() { [ -z "$flake_backup" ] || cp -p "$flake_backup" "$FLAKE"; }
flake_commit()  { [ -z "$flake_backup" ] || rm -f "$flake_backup"; flake_backup=""; }
# nixfmt purely as a parser (output discarded) — modules/host-template.nix's
# trick, aimed here at a mutation instead of a render.
flake_verify()  { nixfmt - <"$FLAKE" >/dev/null 2>&1; }

# Only the `desktop = ` line — reused by `--vendor`'s add, by `haus desktop
# <name>` switching between what is already pinned, and by `remove`'s
# explicit replacement.
# `host = ` always comes before `desktop = ` in the scaffolded shape, so a
# loop that decides "insert after host, unless already written" by checking
# $written AT the host line fires every time — $written can only have been
# set by a LATER line it hasn't read yet. Two insertion points is two lines.
# The fix is to know, before the loop starts, whether a desktop line exists
# at all, and run exactly one of "replace it" or "insert after host" — never
# both. A refusal on more than one existing line is deliberate: that shape is
# already hand-edited or corrupted, and guessing which one wins is the thing
# `--print`'s degrade path exists for.
#
# ⚠️ The SAME refusal is needed on `host = `, and for a reason the desktop
# count alone cannot see: a consumer managing more than one Mac from one
# flake has one `host = ` line per `darwinConfigurations.<name> = haus.mkHaus
# { … }` block. With no desktop line yet, `$existing` is 0 for the WHOLE
# file regardless of how many host blocks it has, so "insert after host when
# $existing is 0" would insert a desktop line after EVERY block — syntactically
# valid Nix, so `nixfmt` cannot catch it, and it silently gives every OTHER
# host on the file the same desktop too. Caught by the pre-PR assurance pass,
# not by `test/haus-add.sh`, which only ever fixtures one host. The general
# form is the same as the two-insertion-point bug this function was already
# rewritten to fix: a landmark this function edits by regex is only a safe
# landmark when there is exactly one of it, and that has to be checked, not
# assumed, for EVERY landmark the function touches — not just the one the
# first bug happened to be in.
flake_set_desktop_line() { # rhs
  local rhs="$1" tmp; tmp="$(mktemp)"
  local existing hosts written=""
  existing="$(grep -cE '^        desktop = .*;$' "$FLAKE" || true)"
  hosts="$(grep -cE '^        host = .*;$' "$FLAKE" || true)"
  [ "$existing" -le 1 ] && [ "$hosts" -eq 1 ] || { rm -f "$tmp"; return 1; }
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      '        desktop = '*';')
        printf '        desktop = %s;\n' "$rhs" >>"$tmp"; written=1; continue ;;
      '        host = '*';')
        printf '%s\n' "$line" >>"$tmp"
        if [ "$existing" -eq 0 ]; then
          printf '        desktop = %s;\n' "$rhs" >>"$tmp"; written=1
        fi
        continue ;;
    esac
    printf '%s\n' "$line" >>"$tmp"
  done <"$FLAKE"
  if [ -z "$written" ]; then rm -f "$tmp"; return 1; fi
  mv "$tmp" "$FLAKE"
}

flake_add_input() { # name url rhs
  local name="$1" url="$2" rhs="$3" tmp; tmp="$(mktemp)"
  local existing hosts input_w="" pattern_w="" desktop_w=""
  existing="$(grep -cE '^        desktop = .*;$' "$FLAKE" || true)"
  hosts="$(grep -cE '^        host = .*;$' "$FLAKE" || true)"
  [ "$existing" -le 1 ] && [ "$hosts" -eq 1 ] || { rm -f "$tmp"; return 1; }
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      '  inputs.haus.url = '*)
        printf '%s\n' "$line" >>"$tmp"
        printf '  inputs.%s.url = "%s";\n' "$name" "$(nix_string "$url")" >>"$tmp"
        printf '  inputs.%s.flake = false;\n' "$name" >>"$tmp"
        input_w=1; continue ;;
      '    { haus, ... }:')
        printf '    { haus, %s, ... }:\n' "$name" >>"$tmp"
        pattern_w=1; continue ;;
      '        desktop = '*';')
        printf '        desktop = %s;\n' "$rhs" >>"$tmp"
        desktop_w=1; continue ;;
      '        host = '*';')
        printf '%s\n' "$line" >>"$tmp"
        if [ "$existing" -eq 0 ]; then
          printf '        desktop = %s;\n' "$rhs" >>"$tmp"; desktop_w=1
        fi
        continue ;;
    esac
    printf '%s\n' "$line" >>"$tmp"
  done <"$FLAKE"
  if [ -z "$input_w" ] || [ -z "$pattern_w" ] || [ -z "$desktop_w" ]; then
    rm -f "$tmp"; return 1
  fi
  mv "$tmp" "$FLAKE"
}

# The room sibling of flake_add_input above — same three-or-none discipline,
# a different third landmark. A room is an ORDINARY flake input (no
# `flake = false;`: dropping it is what makes `nix flake lock` evaluate the
# source's own flake.nix, see the acquisition note's step F), and it has no
# `desktop = ` line to replace — nothing in `mkHaus`'s signature selects a
# room the way it selects a desktop. What it has instead is `extraModules`,
# the same argument bootstrap.sh used to scaffold a preset selection into
# before presets were retired: `extraModules = [ <name>.darwinModules.<module> ];`,
# inserted once, never replaced. One room at a time, for the identical reason
# flake_add_input supports one desktop at a time: refuse (return 1, degrade
# to --print) on any PRE-EXISTING `extraModules = ` line rather than parse and
# rewrite a Nix list — real added scope this step does not spend on day one.
flake_add_room_input() { # name url module
  local name="$1" url="$2" module="$3" tmp; tmp="$(mktemp)"
  local existing hosts input_w="" pattern_w="" extra_w=""
  existing="$(grep -cE '^        extraModules = .*;$' "$FLAKE" || true)"
  hosts="$(grep -cE '^        host = .*;$' "$FLAKE" || true)"
  [ "$existing" -eq 0 ] && [ "$hosts" -eq 1 ] || { rm -f "$tmp"; return 1; }
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      '  inputs.haus.url = '*)
        printf '%s\n' "$line" >>"$tmp"
        printf '  inputs.%s.url = "%s";\n' "$name" "$(nix_string "$url")" >>"$tmp"
        input_w=1; continue ;;
      '    { haus, ... }:')
        printf '    { haus, %s, ... }:\n' "$name" >>"$tmp"
        pattern_w=1; continue ;;
      '        host = '*';')
        printf '%s\n' "$line" >>"$tmp"
        printf '        extraModules = [ %s.darwinModules.%s ];\n' "$name" "$module" >>"$tmp"
        extra_w=1
        continue ;;
    esac
    printf '%s\n' "$line" >>"$tmp"
  done <"$FLAKE"
  if [ -z "$input_w" ] || [ -z "$pattern_w" ] || [ -z "$extra_w" ]; then
    rm -f "$tmp"; return 1
  fi
  mv "$tmp" "$FLAKE"
}

flake_remove_input() { # name
  local name="$1" tmp; tmp="$(mktemp)"
  local removed=""
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "  inputs.$name.url = "*|"  inputs.$name.flake = "*)
        removed=1; continue ;;
      "    { haus, $name, ... }:")
        printf '    { haus, ... }:\n' >>"$tmp"; continue ;;
      # A room's third landmark, dropped whole rather than edited — the same
      # one-room-at-a-time scope flake_add_room_input keeps means this line
      # can only ever name the input being removed, never a second room's.
      '        extraModules = [ '"$name"'.darwinModules.'*'];')
        continue ;;
    esac
    printf '%s\n' "$line" >>"$tmp"
  done <"$FLAKE"
  if [ -z "$removed" ]; then rm -f "$tmp"; return 1; fi
  mv "$tmp" "$FLAKE"
}

# Which file inside an ALREADY-pinned input is the desktop — re-derived from
# the LOCK (offline, no re-resolution of the pin) rather than remembered,
# because nothing yet remembers it (that is E1's claim table). Fetches the
# exact locked tree via the same `builtins.fetchTree` the lock itself used,
# so a content-addressed cache hit costs nothing.
desktop_rhs_for_pinned() { # name
  local name="$1"
  [ -f "$CONSUMER/flake.lock" ] || return 1
  local locked; locked="$(jq -c --arg n "$name" '.nodes[$n].locked // empty' "$CONSUMER/flake.lock" 2>/dev/null)"
  [ -n "$locked" ] || return 1
  local lockfile; lockfile="$(mktemp)"
  printf '%s' "$locked" >"$lockfile"
  local tree
  tree="$(NIX_PATH='' nix eval --impure --raw \
    --expr "(builtins.fetchTree (builtins.fromJSON (builtins.readFile \"$(nix_string "$lockfile")\"))).outPath" \
    2>/dev/null)" || true
  rm -f "$lockfile"
  [ -n "$tree" ] || return 1
  if [ -f "$tree" ]; then printf '%s' "$name"; return 0; fi
  local cands=() f
  for f in "$tree"/*.nix "$tree"/desktops/*.nix; do
    [ -f "$f" ] || continue
    [ "$(basename "$f")" = flake.nix ] && continue
    cands+=("${f#"$tree"/}")
  done
  [ "${#cands[@]}" -eq 1 ] || return 1
  printf '%s + "/%s"' "$name" "${cands[0]}"
}

cmd_add() {
  local source="" as="" pickfile="" vendor="" doprint="" yes="" room="" module="default"
  local -a namespaces=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --print) doprint=1 ;;
      --as) shift; [ $# -gt 0 ] || die "--as needs a name"; as="$1" ;;
      --as=*) as="${1#--as=}" ;;
      --file) shift; [ $# -gt 0 ] || die "--file needs a path"; pickfile="$1" ;;
      --file=*) pickfile="${1#--file=}" ;;
      --vendor) vendor=1 ;;
      -y | --yes) yes=1 ;;
      --room) room=1 ;;
      --namespace) shift; [ $# -gt 0 ] || die "--namespace needs a name"; namespaces+=("$1") ;;
      --namespace=*) namespaces+=("${1#--namespace=}") ;;
      --module) shift; [ $# -gt 0 ] || die "--module needs a darwinModules attribute"; module="$1" ;;
      --module=*) module="${1#--module=}" ;;
      -h | --help)
        cat <<'EOF'
haus add <source> — pin a desktop and select it, or pin a ROOM. Writes
flake.nix + flake.lock; never rebuilds — 'haus rebuild' is the next step,
printed at the end.

  haus add github:ada/writer-desktop
  haus add --as writer --file writer.nix github:ada/desktops
  haus add --vendor file+https://example.org/writer.nix
  haus add --print git+https://git.example.org/ada/desktop
  haus add --room --namespace photography github:ada/photo-room

  --as <name>       the input name (default: the repo name, minus a
                    -desktop/-haus suffix)
  --file <path>     which .nix in a fetched repo is the desktop
  --vendor          copy the file into this config instead of pinning it
  --print           print the edit instead of writing it
  -y, --yes         skip the confirmation prompt (desktops only)
  --room            the source is CODE, not data — see below
  --namespace <ns>  which haus.<ns> this room claims (repeatable; required
                    with --room, refused without it)
  --module <attr>   the darwinModules.<attr> this room's flake exports
                    (default: default)

A room is a nix-darwin module: it may install packages, write files and run
activation scripts as root. Nothing here vouches for it — read it, or trust
whoever wrote it. Pinning one LOCKS it, and locking a flake input evaluates
its flake.nix — that already runs the room's code, before any rebuild, so
--room's confirmation is a typed one naming the revision, and neither -y nor
--yes can skip it. Non-interactively, a per-name
HAUS_ADD_ROOM_<NAME>=<full revision> is required instead — a piped installer
can never accept a room on a person's behalf with one blanket switch.
EOF
        return 0 ;;
      -*) die "unknown flag $1 — try 'haus add --help'" ;;
      *) [ -z "$source" ] || die "one source at a time (got '$source' and '$1')"; source="$1" ;;
    esac
    shift
  done
  [ -n "$source" ] || die "usage: haus add <source> — try 'haus add --help'"
  [ -z "$doprint" ] || yes=1   # nothing is written, so nothing needs confirming

  local host=""
  if [ -n "$room" ]; then
    [ "${#namespaces[@]}" -gt 0 ] \
      || die "haus add --room needs --namespace <name> (repeatable) — a room's own namespace can't be inferred without running its code, which is the one thing this command must not do before you've confirmed it."
    [ -z "$pickfile" ] || die "--file has nothing to name in a room — --room reads nothing at all."
    [ -z "$vendor" ] || die "--vendor doesn't apply to a room — it isn't a single file, it's a flake. Pin it as an input instead."

    # $module lands in flake.nix the same way $name and each $ns do
    # (extraModules = [ $name.darwinModules.$module ];) and gets the same
    # identifier check they get — nothing here is exempt just because it has
    # a default. An unvalidated --module would be the one token in this
    # command's whole write path that a publisher's own copy-paste
    # instructions could shape into more than an attribute name.
    [[ "$module" =~ ^[A-Za-z_][A-Za-z0-9_\'-]*$ ]] || die "'--module $module' isn't a legal Nix identifier."

    host="$(host_name)"
    local ns taken_status
    for ns in "${namespaces[@]}"; do
      [[ "$ns" =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]] || die "'--namespace $ns' isn't a legal namespace component."
      case "$ns" in
        haus) die "'--namespace haus' — haus is the layer itself, not a namespace a room could claim." ;;
        my) die "'--namespace my' — haus.my.* is reserved for YOUR OWN private modules; a published room claims a plain haus.<name>." ;;
      esac
      taken_status=0
      namespace_taken "$host" "$ns" || taken_status=$?
      case "$taken_status" in
        0) die "'haus.$ns' already exists on this machine — pick a namespace this room actually introduces, or re-read its docs." ;;
        1) ;;
        *) die "couldn't check whether 'haus.$ns' already exists on this machine (try: haus doctor) — refusing rather than guessing." ;;
      esac
    done
  else
    [ "${#namespaces[@]}" -eq 0 ] || die "--namespace only applies to --room."
  fi

  local showbin="${HAUS_SHOW:-/run/current-system/sw/share/haus/show.sh}"
  [ -r "$showbin" ] || die "no 'haus show' at $showbin — this machine's haus predates it; run 'haus update' first."

  local showargs=()
  [ -n "$pickfile" ] && showargs+=(--file "$pickfile")
  [ -n "$room" ] && showargs+=(--room)

  # The human report IS the confirmation prompt the design calls for — haus
  # already has cmd_plan/cmd_diff to build a diff, and this is that diff,
  # reused rather than re-rendered. Read again as JSON afterward for the
  # values the write needs: two evals of the same fetch, not one, because the
  # JSON envelope and the human render are two different consumers of one
  # report and forcing one to parse the other is the wrong coupling.
  local show_status=0
  HAUS_CONSUMER="$CONSUMER" bash "$showbin" "${showargs[@]}" "$source" || show_status=$?
  if [ -n "$room" ]; then
    [ "$show_status" -eq 0 ] || die "$source did not pass — see the report above."
  else
    case "$show_status" in
      0) ;;
      3) die "$source is a room, not a desktop — pass --room --namespace <name> to pin it as one. See 'haus show --room $source'." ;;
      *) die "$source did not pass — see the report above." ;;
    esac
  fi

  local report
  report="$(HAUS_CONSUMER="$CONSUMER" bash "$showbin" --json "${showargs[@]}" "$source")" \
    || die "$source stopped passing between the two reads above — try again."

  local class ok origin
  class="$(jq -r .class <<<"$report")"
  ok="$(jq -r .ok <<<"$report")"
  origin="$(jq -c .origin <<<"$report")"
  if [ -n "$room" ]; then
    [ "$class" = room ] || die "$source is a desktop, not a room — drop --room and --namespace."
  else
    [ "$class" = desktop ] || die "$source is a room — 'haus add' needs --room --namespace <name> to pin one."
    [ "$ok" = true ] || die "$source failed the desktop checker — see the report above."
  fi
  [ "$origin" != null ] || die "haus add takes a source to fetch, not a local path already on this machine."

  local typed shape pick rev
  typed="$(jq -r .typed <<<"$origin")"
  shape="$(jq -r .shape <<<"$origin")"
  pick="$(jq -r '.file // ""' <<<"$origin")"
  rev="$(jq -r '.rev // ""' <<<"$origin")"

  local name="$as"
  [ -n "$name" ] || name="$(derive_input_name "$typed" "$shape")"
  [ "$name" != haus ] || die "'haus' is reserved for the layer itself — pick another with --as."
  [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_\'-]*$ ]] || die "'--as $name' isn't a legal Nix identifier."
  grep -qE "^  inputs\.$name\.url = " "$FLAKE" \
    && die "'$name' is already pinned — 'haus desktop $name' selects it, or pass a different --as."

  if [ -n "$room" ]; then
    [ "$shape" = repo ] \
      || die "a room must be an ordinary flake — a repo with a revision, not a '$shape' source: haus cannot lock what it cannot pin as an input."

    if [ -z "$doprint" ]; then
      local rev_short="${rev:0:12}"
      if [ -t 0 ]; then
        printf '\n'
        say "Pinning '$name' from $typed means LOCKING it, and locking a flake input evaluates its flake.nix — that is the FIRST execution of this code, not the rebuild."
        local reply
        read -r -p "Type the first 12 characters of the revision ($rev_short) to confirm: " reply
        [ "$reply" = "$rev_short" ] || { say "not added."; return 1; }
      else
        local var; var="HAUS_ADD_ROOM_$(printf '%s' "$name" | tr 'a-z' 'A-Z' | tr -c 'A-Z0-9_' '_')"
        [ "${!var:-}" = "$rev" ] \
          || die "not a terminal — set $var=$rev (the full revision) to confirm non-interactively. -y/--yes does not confirm a room."
      fi
    fi

    if [ -n "$doprint" ]; then
      printf '  inputs.%s.url = "%s";\n' "$name" "$(nix_string "$typed")"
      printf '\n  outputs = { haus, %s, ... }: { … extraModules = [ %s.darwinModules.%s ]; … }\n' "$name" "$name" "$module"
      for ns in "${namespaces[@]}"; do
        printf '  haus._rooms.claimed.%s = "%s";\n' "$ns" "$(nix_string "$typed")"
      done
      return 0
    fi

    flake_stage
    if ! flake_add_room_input "$name" "$typed" "$module"; then
      flake_restore
      say "flake.nix has moved past the scaffolded shape — add these by hand:"
      printf '  inputs.%s.url = "%s";\n' "$name" "$typed"
      printf '  # bind %s in the outputs pattern, and: extraModules = [ %s.darwinModules.%s ];\n' "$name" "$name" "$module"
      return 0
    fi
    if ! flake_verify; then
      flake_restore
      die "the edit produced invalid Nix — restored. See above for the lines to add by hand."
    fi
    flake_commit
    say "locking … (this runs $name's flake.nix)"
    if ! ( cd "$CONSUMER" && heal nix flake lock ); then
      warn "flake.nix is edited but 'nix flake lock' failed — run it by hand, then 'haus rebuild'."
      return 0
    fi
    say "'$name' pinned and wired into extraModules."
    local claim_failed=""
    for ns in "${namespaces[@]}"; do
      rooms_claim_namespace "$host" "$name" "$typed" "$ns" || claim_failed=1
    done
    if [ -n "$claim_failed" ]; then
      warn "pinned and wired; at least one namespace claim didn't write — 'haus rebuild' will warn about it until you set it by hand ('haus set _rooms.claimed.<ns> \"$typed\"') or re-run with --namespace."
    else
      say "namespace claimed: ${namespaces[*]}. Run 'haus rebuild' to apply it."
    fi
    return 0
  fi

  if [ -z "$yes" ]; then
    [ -t 0 ] || die "not a terminal — pass -y/--yes to confirm non-interactively."
    printf '\n'
    read -r -p "Add '$name' from $typed and select it? [y/N] " reply
    case "$reply" in [Yy]*) ;; *) say "not added."; return 1 ;; esac
  fi

  if [ -n "$vendor" ]; then
    # Vendoring never touches inputs or the outputs pattern — the file
    # becomes an ordinary part of this config, addressed by a relative path,
    # the same as any hand-written .nix under hosts/. It must be `git add`ed:
    # Nix can't see an untracked file in a git-tracked flake.
    mkdir -p "$CONSUMER/desktops"
    local dest="$CONSUMER/desktops/$name.nix"
    [ -e "$dest" ] && die "$dest already exists — pick a different --as."
    local src_abs; src_abs="$(jq -r .file <<<"$report")"
    if [ -n "$doprint" ]; then
      say "would copy $src_abs -> desktops/$name.nix and set: desktop = ./desktops/$name.nix;"
      return 0
    fi
    cp "$src_abs" "$dest"
    ( cd "$CONSUMER" && git add "$dest" ) 2>/dev/null \
      || warn "couldn't 'git add $dest' — do it by hand, or the rebuild won't see it."
    flake_stage
    if ! flake_set_desktop_line "./desktops/$name.nix"; then
      flake_restore
      say "flake.nix has moved past the scaffolded shape — set this by hand:"
      printf '        desktop = ./desktops/%s.nix;\n' "$name"
      return 0
    fi
    if ! flake_verify; then
      flake_restore
      die "the edit produced invalid Nix — restored. Set it by hand: desktop = ./desktops/$name.nix;"
    fi
    flake_commit
    say "vendored to desktops/$name.nix and selected. Run 'haus rebuild' to apply it."
    return 0
  fi

  local rhs
  if [ "$shape" = file ]; then
    rhs="$name"
  else
    [ -n "$pick" ] || die "couldn't tell which file in $source is the desktop — pass --file."
    rhs="$name + \"/$pick\""
  fi

  if [ -n "$doprint" ]; then
    printf '  inputs.%s.url = "%s";\n' "$name" "$(nix_string "$typed")"
    printf '  inputs.%s.flake = false;\n' "$name"
    printf '\n  outputs = { haus, %s, ... }: { … desktop = %s; … }\n' "$name" "$rhs"
    return 0
  fi

  flake_stage
  if ! flake_add_input "$name" "$typed" "$rhs"; then
    flake_restore
    say "flake.nix has moved past the scaffolded shape — add these by hand:"
    printf '  inputs.%s.url = "%s";\n' "$name" "$typed"
    printf '  inputs.%s.flake = false;\n' "$name"
    printf '  # bind %s in the outputs pattern, and: desktop = %s;\n' "$name" "$rhs"
    return 0
  fi
  if ! flake_verify; then
    flake_restore
    die "the edit produced invalid Nix — restored. See above for the lines to add by hand."
  fi
  flake_commit
  say "locking …"
  if ( cd "$CONSUMER" && heal nix flake lock ); then
    say "'$name' pinned and selected. Run 'haus rebuild' to apply it."
  else
    warn "flake.nix is edited but 'nix flake lock' failed — run it by hand, then 'haus rebuild'."
  fi
}

# The current selection, read the same landmark way it is WRITTEN — a grep, not
# an eval: "what does this machine have" should cost nothing and need no
# network, the same rule --no-diff protects in `haus show`. Shared with
# `haus report`, whose diagnostics block names the desktop and must not answer
# that question a second way.
desktop_selected() {
  local line
  line="$(grep -E '^        desktop = ' "$FLAKE" 2>/dev/null || true)"
  case "$line" in
    *'haus.desktops.'*) line="${line#*haus.desktops.}"; printf '%s' "${line%;}" ;;
    '') printf 'hacker' ;;  # mkHaus's own default when no line is written
    # A pinned input's RHS is `name` (a file-shaped source) or
    # `name + "/file.nix"` (a tree) — either way the input's own name is the
    # leading token, up to the first space.
    *) line="${line#*desktop = }"; line="${line%;}"; printf '%s' "${line%% *}" ;;
  esac
}

cmd_desktop() {
  local want="${1:-}"
  local check="${HAUS_DESKTOP_CHECK:-/run/current-system/sw/share/haus/desktop-check}"
  [ -r "$check/desktops.json" ] \
    || die "no desktop list at $check — this machine's haus predates 'haus desktop'; run 'haus update' first."
  local builtin_list; builtin_list="$(jq -r '.[]' "$check/desktops.json")"

  local current; current="$(desktop_selected)"

  local pinned; pinned="$(grep -oE '^  inputs\.[A-Za-z0-9_'"'"'-]+\.url = ' "$FLAKE" \
    | sed -E 's/^  inputs\.//; s/\.url = $//' | grep -vx haus || true)"

  if [ -z "$want" ]; then
    say "desktops"
    # Built-in and pinned are ONE table, not two loops that happen to agree on a
    # width: budgeted together, the name column fits the longest name in either
    # half rather than each half guessing. The `→` is a column of its own so a
    # name is at the same column whether or not it is the current one.
    if [ -n "$UI_READY" ]; then
      ui_table_clear
      ui_col on      1 1 ok      never
      ui_col desktop 8 3 subject right
      ui_col from    7 1 muted   never
      while IFS= read -r n; do
        [ -n "$n" ] || continue
        if [ "$n" = "$current" ]; then ui_trow "→" "$n" "built in"; else ui_trow "" "$n" "built in"; fi
      done < <(printf '%s\n' "$builtin_list")
      while IFS= read -r n; do
        [ -n "$n" ] || continue
        if [ "$n" = "$current" ]; then ui_trow "→" "$n" "pinned"; else ui_trow "" "$n" "pinned"; fi
      done < <(printf '%s\n' "$pinned")
      ui_table_data 2
      return 0
    fi
    printf '%s\n' "$builtin_list" | while IFS= read -r n; do
      [ -n "$n" ] || continue
      if [ "$n" = "$current" ]; then printf '  %s→%s %-12s built in\n' "$C_OK" "$C_OFF" "$n"
      else printf '    %-12s built in\n' "$n"; fi
    done
    if [ -n "$pinned" ]; then
      printf '%s\n' "$pinned" | while IFS= read -r n; do
        if [ "$n" = "$current" ]; then printf '  %s→%s %-12s pinned\n' "$C_OK" "$C_OFF" "$n"
        else printf '    %-12s pinned\n' "$n"; fi
      done
    fi
    return 0
  fi

  if [ "$want" = "$current" ]; then say "already on $want."; return 0; fi

  if printf '%s\n' "$builtin_list" | grep -qx "$want"; then
    flake_stage
    if ! flake_set_desktop_line "haus.desktops.${want}"; then
      flake_restore
      die "flake.nix has moved past the scaffolded shape — set it by hand: desktop = haus.desktops.${want};"
    fi
    if ! flake_verify; then
      flake_restore
      die "the edit produced invalid Nix — restored. Set it by hand: desktop = haus.desktops.${want};"
    fi
    flake_commit
    say "desktop set to $want. Run 'haus rebuild' to apply it."
    return 0
  fi

  if printf '%s\n' "$pinned" | grep -qx "$want"; then
    local rhs
    rhs="$(desktop_rhs_for_pinned "$want")" \
      || die "couldn't tell which file inside '$want' is the desktop — re-run 'haus add --as $want --file <path> <source>' to reselect it."
    flake_stage
    if ! flake_set_desktop_line "$rhs"; then
      flake_restore
      die "flake.nix has moved past the scaffolded shape — set it by hand: desktop = $rhs;"
    fi
    if ! flake_verify; then
      flake_restore
      die "the edit produced invalid Nix — restored. Set it by hand: desktop = $rhs;"
    fi
    flake_commit
    say "desktop set to $want. Run 'haus rebuild' to apply it."
    return 0
  fi

  die "no desktop named '$want' — built in: $(printf '%s' "$builtin_list" | tr '\n' ' ')· pinned: $(printf '%s' "${pinned:-none}" | tr '\n' ' ')(or 'haus add' one)"
}

cmd_remove() {
  local name="${1:-}" replacement="${2:-}"
  [ -n "$name" ] || die "usage: haus remove <name> [replacement desktop, default blank]"
  [ "$name" != haus ] || die "haus is the layer itself, not something 'haus remove' can drop."
  grep -qE "^  inputs\.$name\.url = " "$FLAKE" \
    || die "no pinned input named '$name' — 'haus desktop' lists what's pinned."

  local current_line was_selected="" was_room=""
  current_line="$(grep -E '^        desktop = ' "$FLAKE" || true)"
  case "$current_line" in *"$name"*) was_selected=1 ;; esac
  grep -qE "^        extraModules = \[ $name\.darwinModules\." "$FLAKE" && was_room=1

  flake_stage
  if ! flake_remove_input "$name"; then
    flake_restore
    die "flake.nix has moved past the scaffolded shape — remove 'inputs.$name' and its binding by hand."
  fi
  if [ -n "$was_selected" ]; then
    # `mkHaus`'s `desktop` argument defaults to the opinionated hacker
    # desktop, so deleting the selection line silently installs it rather
    # than returning the machine to neutral. Write an explicit replacement —
    # blank unless told otherwise.
    local repl="${replacement:-blank}"
    if ! flake_set_desktop_line "haus.desktops.${repl}"; then
      flake_restore
      die "flake.nix has moved past the scaffolded shape — remove 'inputs.$name' and set 'desktop' by hand."
    fi
  fi
  if ! flake_verify; then
    flake_restore
    die "the edit produced invalid Nix — restored. Remove 'inputs.$name' by hand."
  fi
  flake_commit
  if ( cd "$CONSUMER" && heal nix flake lock ); then
    :
  else
    warn "flake.nix is edited but 'nix flake lock' failed — run it by hand."
  fi
  if [ -n "$was_selected" ]; then
    say "'$name' removed. It was your selected desktop — set to '${replacement:-blank}' instead. Run 'haus rebuild' to apply it."
  elif [ -n "$was_room" ]; then
    say "'$name' removed, and its extraModules entry with it. Run 'haus rebuild' to apply it."
    # This command doesn't know WHICH namespace(s) '$name' claimed — that
    # would mean re-reading haus._rooms.claimed for a value matching an
    # origin the lock no longer carries, over every claimed namespace on the
    # machine, to undo one write it isn't sure it made. A note is cheaper and
    # doesn't risk resetting a claim this room never actually owned.
    info "if '$name' had a namespace claim (haus._rooms.claimed.<ns>), reset it by hand: haus reset _rooms.claimed.<ns>"
  else
    say "'$name' removed. Run 'haus rebuild' to apply it."
  fi
}

# `haus show` is its own script, staged beside the evaluator it drives so that
# the machine's copy and `nix run github:hausfold/haus#show` are ONE file rather
# than two that agree today (modules/desktop-check.nix). `exec` rather than a
# call: its exit code is the whole point — a publisher's CI reads it — and
# handing the process over is the only way it reaches the caller unedited.
cmd_show() {
  local show="${HAUS_SHOW:-/run/current-system/sw/share/haus/show.sh}"
  [ -r "$show" ] \
    || die "no 'haus show' at $show — this machine's haus predates it; run 'haus update' first."
  exec bash "$show" "$@"
}

# Sourced, not run: test/haus-plan.sh exercises the parsers above directly (they
# are pure text-and-tree functions, so CI can run them on Linux even though a
# real `haus plan` needs a Mac with a built system). Everything above this line
# is definitions; everything below is the CLI, so stopping here is the whole
# library.
#
# Gated on ACTUALLY BEING SOURCED as well as on the variable, because `return`
# outside a sourced script is a fatal error, not a no-op: keyed on HAUS_LIB
# alone, one exported variable left in a shell would turn every later `haus` in
# it into `can only 'return' from a function or sourced script`, exit 2, with no
# other output. The subshell `return` is the standard probe — it succeeds only
# when this file is being sourced.
if [ -n "${HAUS_LIB:-}" ] && (return 0 2>/dev/null); then return 0; fi

# -v anywhere turns the summary back into the raw stream (same as HAUS_VERBOSE=1).
HAUS_ARGS=()
for a in "$@"; do
  case "$a" in
    -v|--verbose) VERBOSE=1 ;;
    *)            HAUS_ARGS+=("$a") ;;
  esac
done
set -- ${HAUS_ARGS[@]+"${HAUS_ARGS[@]}"}

# Which stream this command's prose goes to — see the note by the verbs. A
# REPORT is a thing somebody pipes: `haus doctor | pbcopy` into the issue form,
# `haus plan >plan.txt`, `$(haus get …)`. Everything else narrates while it
# changes the machine, and narration is stderr, because stdout carries data only.
#
# Set here rather than inside each cmd_ so the whole split is one list you can
# read at a glance — and so a helper both kinds call (`settings_diff`,
# `consumer_worktree_warning`) needs no opinion of its own.
case "${1:-status}" in
  status | doctor | plan | diff | permissions | btm | generations | get | capture | report)
    REPORT=1
    ;;
esac

case "${1:-status}" in
  rebuild)     cmd_rebuild ;;
  fix)         shift; cmd_fix "$@" ;;
  update)      cmd_update "${2:-}" ;;
  rollback)    cmd_rollback "${2:-}" ;;
  generations) cmd_generations ;;
  status)      cmd_status ;;
  edit)        cmd_edit ;;
  options)     cmd_options "${2:-}" ;;
  set)         shift; cmd_set "$@" ;;
  get)         shift; cmd_get "$@" ;;
  unset)       shift; cmd_unset "$@" ;;
  reset)       shift; cmd_reset "$@" ;;
  plan)        cmd_plan ;;
  diff)        cmd_diff ;;
  capture)     shift; cmd_capture "$@" ;;
  revert-settings) cmd_revert_settings "${2:-latest}" ;;
  doctor)      cmd_doctor ;;
  report)      shift; cmd_report "$@" ;;
  skill)       shift; cmd_skill "$@" ;;
  permissions) cmd_permissions "${2:-}" ;;
  btm)         cmd_btm ;;
  tour)        cmd_tour "${2:-}" ;;
  show)        shift; cmd_show "$@" ;;
  add)         shift; cmd_add "$@" ;;
  desktop)     cmd_desktop "${2:-}" ;;
  remove)      cmd_remove "${2:-}" "${3:-}" ;;
  -h|--help|help) usage ;;
  *)           die "unknown command '$1' — try: rebuild fix update rollback generations status edit options set get unset reset plan diff capture revert-settings doctor report skill permissions btm tour show add desktop remove" ;;
esac
