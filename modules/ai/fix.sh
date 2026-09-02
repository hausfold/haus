#!/usr/bin/env bash
# `haus-fix` — hand the rebuild that just failed to a coding agent, once.
#
# ── what this is ────────────────────────────────────────────────────────────
# A failed `haus rebuild` leaves a breadcrumb (~/.local/state/haus/last-failure:
# which phase, which host, where in the log, which derivation) and puts a CTA
# in front of the person — `gum` rows in the pane they are looking at, or a
# `trill ask` fin if they are not. One pill: **Fix it**. The pill runs
# `haus fix`, which is a one-line dispatch onto this binary.
#
# So this script is the whole of "Fix it with AI": read the breadcrumb, gather
# the evidence a human would gather, run ONE non-interactive turn of this
# machine's `haus.ai.default` client in the config flake, check the answer, and
# say on a banner whether it took.
#
# It deliberately does NOT rebuild. Activation is machine-wide and serial and
# belongs to the person, so this ends at "the config evaluates again, here is
# the commit" and hands `haus rebuild` back. The prompt below forbids the agent
# from running it too.
#
# ── the boundary, and why the agent runs with permissions off ───────────────
# The one-shot argv (modules/lib/agent-oneshot.nix) opens each client's
# permission gate, and HAUS_DESKTOP_OK=1 turns off the desktop guard that would
# otherwise raise a trill question from a run nobody is watching. That is a
# deliberate trade, not an oversight: an agent that stops to ask about its
# first `Edit` is a one-shot that never finishes, and this one starts from a
# BANNER — the person who pressed the pill has already walked away.
#
# What bounds it instead is the cwd and the commit. It runs in $CONSUMER and
# nowhere else, the whole of its work lands as one git commit there, and the
# undo is one command a person can run without reading any of it:
#
#     git -C ~/.config/nix revert HEAD
#
# That is why $CONSUMER being a git repo is a hard requirement here and a gate
# on the CTA in haus.sh: without it there is no undo, so there is no offer.
#
# ── which evidence, per failure class ───────────────────────────────────────
#   resolve   evaluation failed. run_phase already captured it — the slice of
#             $HAUS_LOG from the offset the breadcrumb recorded.
#   activate  same shape: activation runs through run_phase too.
#   build     NOTHING is in the log. haus.sh gives the build phase the terminal
#             on purpose (nix draws its progress bar only onto a terminal), so
#             there is no slice to take. The evidence is re-derived instead:
#             `nix build -L` on the same derivation, which now stops at the
#             same failing builder with everything before it already in the
#             store — usually seconds — and prints the builder's own log.
#
# ── contract ────────────────────────────────────────────────────────────────
#   haus-fix           fix the failure the breadcrumb names
#   haus-fix --dry-run print the prompt that would be sent, run no agent — and
#                      nothing else either: for a build-class failure the real
#                      run re-derives the error with `nix build`, and a dry run
#                      names that command rather than running it
#
# Exit 0 when the config evaluates afterwards, 1 when it does not, 2 when there
# was nothing to fix or nothing to fix it with. Every path ends on a banner.
# Installed by modules/ai (its systemPackages, under the room's own switch), so
# `command -v haus-fix` is the ONLY thing core has to test — core never reads
# `config.haus.ai.*`.
#
# @client@, @oneshot@ and @uiSh@ are substituted at build time from
# `haus.ai.default`, modules/lib/agent-oneshot.nix and snug's bash painter.
# All three are assignment right-hand sides, which is why an unsubstituted copy
# still parses — CI lints this file as a template.
PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/etc/profiles/per-user/$(id -un 2>/dev/null)/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
export PATH

set -u

CLIENT="@client@"
AGENT=(@oneshot@)

STATE="${XDG_STATE_HOME:-$HOME/.local/state}/haus"
CRUMB="$STATE/last-failure"
FIXLOG="$STATE/fix.log"
LOCK="$STATE/fix.lock"

DRY=""
case "${1:-}" in
  "") ;;
  --dry-run) DRY=1 ;;
  # Refused rather than ignored: this is the one command on the machine that
  # spawns an agent with its permission gate open, and a flag it silently drops
  # is a person who thinks they asked for something safer than what runs.
  *)
    printf 'usage: haus fix [--dry-run]
' >&2
    exit 64
    ;;
esac
[ "$#" -le 1 ] || { printf 'usage: haus fix [--dry-run]
' >&2; exit 64; }

# A banner, never a terminal line — this is usually spawned from a trill pill
# with no terminal at all. `haus-notify` picks trill or Apple's banner at
# runtime; the --source is what makes "stop telling me about this" a rules.json
# line rather than a rebuild.
banner() { # banner <kind> <title> [body]
  haus-notify --title "$2" --body "${3:-}" --kind "$1" \
    --source haus.rebuild.fix --symbol wrench.and.screwdriver >/dev/null 2>&1 || true
}

# Said on the terminal when there is one — and only then. On the banner path
# both streams are /dev/null, which is the point: the transcript is $FIXLOG and
# the verdict is the banner. Nothing here is load-bearing.
note() { printf '%s\n' "$*" >&2; }

die2() { note "haus fix: $*"; banner fault "haus fix" "$*"; exit 2; }

# ---- the wait, said in the pane ---------------------------------------------
# Pressing "Fix it with AI" in a pane used to print NOTHING for the length of a
# headless turn. That is not a slow client: `claude -p` holds its whole answer
# to the end (measured), which is what print mode is for, so `tee`ing it live
# showed an empty screen for a minute and then everything at once.
# Indistinguishable from a hang, and the one thing feel-testing #592/#626 on a
# live machine turned up once the rows themselves drew: you press the row, your
# terminal goes quiet, and the only sign anything is happening is a trill card
# on the other side of the screen.
#
# ⚠️ Measured for `claude` only — it is the one on the machine this was written
# on, the same limit modules/lib/agent-oneshot.nix states for `codex`. A client
# that DOES narrate as it works (`codex exec` and `opencode run` both look like
# they do) trades a live log for a spinner and one dump at the end. Nothing is
# lost — the transcript is $FIXLOG either way, and it is still the right side
# of the silence this replaced — but if a client turns out to stream something
# worth watching, the branch to add is a streaming one, not a redirect.
#
# So the two long silences get a spinner row each — the agent turn, and the
# `nix eval` that checks its work. The banner path pays for none of it: both
# streams are /dev/null there, `ui_load` is never called, and the verdict was
# always the banner.
#
# Substituted rather than inherited, the way `focus` and `haus-secret` take it:
# `haus-fix` is its own binary and inherits nobody's environment — the trill
# pill execs it from a detached holder with no terminal at all. `HAUS_UI_SH`
# still wins when a caller sets one, so a working copy is one variable away.
HAUS_UI_SH="${HAUS_UI_SH:-@uiSh@}"

# ── ui_load — source the painter once, and answer whether it can draw ────────
# The ONE copy of this block is modules/lib/ui-load.nix; `nix flake check`
# (ui-load-sync) diffs this file against it, so edit it THERE and re-copy.
# UI_READY=1 only when every verb named in UI_WANT arrived: the carrier sets
# UI_WANT to every ui_* verb it CALLS, not a sample, because a pin whose ui.sh
# predates one of them is a `command not found` halfway down a report — under
# `set -e` an abort AFTER the machine changed and before anything said so —
# and UI_READY would have licensed it. Idempotent, so calling it lazily from
# each draw path and calling it once at load are the same verb; a path that
# never draws never calls it and pays nothing. Three traps, each silent, each
# paid for before this block existed:
#
#   * ui.sh is bash 4+ (`declare -gA`, `${v^^}`). macOS's /bin/bash 3.2 does
#     not fail it quietly: three `bad substitution` errors and a half-loaded
#     painter that answers `type` and then draws nothing — so the version is
#     checked, never assumed, and 3.2 keeps the plain output.
#   * `|| true` is load-bearing under `set -euo pipefail`: a sourced file's
#     non-zero exit is the caller's to survive, and a ui.sh that failed at
#     load would otherwise abort the verb mid-flight — for `awake 3h`, AFTER
#     the assertion started.
#   * The path stays in `HAUS_UI_SH`, never `UI_SH` — that exact name is
#     ui.sh's own source-twice sentinel, and holding the path in it makes the
#     file return before defining anything, with no error and no colour.
UI_READY=""
ui_load() {
    [ -n "${UI_LOADED:-}" ] && return 0
    UI_LOADED=1
    [ "${BASH_VERSINFO[0]:-0}" -ge 4 ] || return 0
    if [ -r "${HAUS_UI_SH:-}" ]; then
        # shellcheck source=/dev/null
        source "$HAUS_UI_SH" || true
    fi
    [ -n "${UI_WANT:-}" ] || return 0
    # shellcheck disable=SC2086
    type $UI_WANT >/dev/null 2>&1 && UI_READY=1
    return 0
}

# Probed by what `spin_wait` draws with, for the same reason `focus` probes: a
# pin whose ui.sh predates the live region is a `command not found` in the
# middle of a wait, and the plain `note` line is still right for that machine.
UI_WANT="ui_row ui_paint ui_live_close"

# The job `spin_wait` is watching, so the signal handler below can stop it.
#
# Backgrounding the turn is what makes this necessary, and the reason is not
# obvious: bash's `wait` builtin RETURNS on a trapped signal, where a
# FOREGROUND command defers the trap until it finishes. So the ^C that used to
# reach the client first now reaches the handler first — and a handler that
# only dropped the lock and exited would leave an agent that caught the signal
# itself still editing $CONSUMER, gate open, with the one-at-a-time lock
# released so the next `haus fix` may start beside it. That is the exact thing
# the lock exists to prevent, arrived at from the other side. Measured on bash
# 5.3 against a child that ignores TERM.
FIX_JOB=""

# spin_wait <pid> <name> <detail> — spin one row until that job ends, leave the
# row on screen wearing its own verdict, and return the job's exit status.
#
# The job is BACKGROUNDED rather than piped, and that is the whole shape of it:
# a spinner and a live `tee` of the same terminal fight over the cursor, and
# there is nothing to tee until the client is done anyway. What the caller gets
# back instead is the byte offset trick haus.sh already uses on its own log —
# read $FIXLOG from where the run started and print that, once, underneath.
#
# Degrades to the `note` line it replaces wherever the painter is absent: no
# terminal (the banner path, where fd 2 is /dev/null), bash 3.2, or a snug too
# old to have the live region.
spin_wait() { # spin_wait <pid> <name> <detail>
  local pid="$1" name="$2" detail="$3" rc=0
  FIX_JOB="$pid"
  if [ -z "$UI_READY" ] || [ ! -t 2 ]; then
    # Braced, and it has to be: bash takes the ellipsis as part of the
    # IDENTIFIER, so a bare `$detail…` dies `detail…: unbound variable` under
    # `set -u`. Only this fallback line concatenates one, so only it was bitten.
    note "$name — ${detail}…"
    wait "$pid" || rc=$?
    FIX_JOB=""
    return "$rc"
  fi
  # `kill -0` and not `wait -n`: bash reaps a background child into its own job
  # table as it notices SIGCHLD, so the probe goes false on a finished job and
  # the `wait` below still hands back its recorded status (measured, bash 5.3).
  while kill -0 "$pid" 2>/dev/null; do
    ui_row run "$name" "$detail"
    ui_paint
    sleep 0.1
  done
  wait "$pid" || rc=$?
  if [ "$rc" = 0 ]; then
    ui_row ok "$name" "$detail"
  else
    ui_row fail "$name" "$detail — exit $rc"
  fi
  ui_paint
  ui_live_close
  FIX_JOB=""
  return "$rc"
}

# ---- the breadcrumb ---------------------------------------------------------
# Plain KEY=value lines, read into variables by name rather than `eval`'d: this
# file is written by haus.sh and read here, and a state file that can execute
# is a state file that can be made to execute something else.
class=""; host=""; consumer=""; faultlog=""; offset=""; drv=""; gen=""; when=""
[ -r "$CRUMB" ] || die2 "nothing to fix — no failed rebuild recorded. Run \`haus rebuild\` first."
while IFS='=' read -r k v; do
  case "$k" in
    class) class="$v" ;;
    host) host="$v" ;;
    consumer) consumer="$v" ;;
    log) faultlog="$v" ;;
    offset) offset="$v" ;;
    drv) drv="$v" ;;
    gen) gen="$v" ;;
    when) when="$v" ;;
  esac
done <"$CRUMB"

[ -n "$consumer" ] || consumer="${HAUS_CONSUMER:-$HOME/.config/nix}"
[ -d "$consumer" ] || die2 "$consumer is not there — nothing to fix."
git -C "$consumer" rev-parse --git-dir >/dev/null 2>&1 \
  || die2 "$consumer is not a git repo. The undo for an agent's edits is \`git -C $consumer revert HEAD\`, so this refuses to edit a checkout that has none."
command -v "$CLIENT" >/dev/null 2>&1 \
  || die2 "$CLIENT is not on PATH — haus.ai.default names it, but nothing installed it."

# The cwd IS the remit, so it is set once, here, rather than per command. The
# prompt below tells the agent that $consumer is where it is working; a client
# spawned from whatever directory a trill pill happens to inherit would make
# that sentence a lie, and every relative path in its answer wrong.
cd "$consumer" || die2 "cannot enter $consumer."

# The signal handler, and the ORDER inside it is the whole point: stop the turn
# FIRST, drop the lock second. See FIX_JOB above for why a backgrounded turn
# needs one at all — cancelling has to mean the agent stopped, not merely that
# `haus fix` stopped waiting for it.
fix_cancelled() {
  if [ -n "$FIX_JOB" ]; then
    kill -TERM "$FIX_JOB" 2>/dev/null || true
    # Bounded, then forced. A client that will not go must not keep the lock
    # alive, and must not outlive the person's cancel either — it is editing
    # their config flake with its permission prompts off. `_` and not a named
    # counter: haus.sh's `fault_holder_stop` spells the same wait the same way,
    # and CI lints this file at --severity=warning where an unused one is red.
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      kill -0 "$FIX_JOB" 2>/dev/null || break
      sleep 0.1
    done
    kill -KILL "$FIX_JOB" 2>/dev/null || true
  fi
  rmdir "$LOCK" 2>/dev/null || true
  exit 130
}

# One at a time. Two agents editing one flake is how you get a merge conflict
# with yourself; `mkdir` is the atomic test-and-set every shell has.
if [ -z "$DRY" ]; then
  mkdir "$LOCK" 2>/dev/null || die2 "a fix is already running (remove $LOCK if it is not)."
  # INT/TERM/HUP as well as EXIT: the holder that started this can be reaped by
  # the NEXT failed rebuild, and an EXIT-only trap would leave the directory
  # behind — after which every later `haus fix` answers "already running" and
  # the button is dead until someone reads this file to find out why.
  trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT
  trap fix_cancelled INT TERM HUP
fi

# ---- the evidence -----------------------------------------------------------
clip() { head -c "${1:-20000}"; }

phase_slice() { # what the failing phase said, from the log run_phase wrote
  [ -n "$faultlog" ] && [ -r "$faultlog" ] || return 0
  case "${offset:-}" in '' | *[!0-9]*) offset=0 ;; esac
  # The tail, not the head: a nix trace ends on the error, and the pages above
  # it are the same twenty frames every time.
  tail -c "+$((offset + 1))" "$faultlog" 2>/dev/null | tail -n 200 | clip
}

build_slice() { # the build phase kept the terminal, so re-derive its error
  [ -n "$drv" ] || return 0
  # `--dry-run` means run nothing, and re-deriving the error IS running
  # something — minutes of it, on the one class where the evidence is not
  # already on disk. Say what would happen instead.
  [ -n "$DRY" ] && {
    printf '(--dry-run: the real run re-derives this with `nix build -L %s^*`)\n' "$drv"
    return 0
  }
  note "re-running the build to capture its error (everything before the failure is already in the store)…"
  nix build -L --no-link "$drv^*" 2>&1 | tail -n 250 | clip
}

# What changed in the config since the generation that is still running. That
# generation's symlink mtime is when the last GOOD rebuild landed, so anything
# after it is a candidate for what broke this one.
since_good() {
  local link mtime
  link="/nix/var/nix/profiles/system"
  mtime="$(stat -f %m "$link" 2>/dev/null || echo 0)"
  printf '### uncommitted (git diff HEAD)\n'
  git -C "$consumer" --no-pager diff HEAD 2>/dev/null | head -n 400 | clip 12000
  # No generation on disk means no date to cut at, and `--before=@0` is not
  # that date: git IGNORES an out-of-range one silently and answers HEAD, which
  # would report "nothing committed since" about a config that changed all
  # week. Say what is actually known instead.
  if [ "$mtime" = 0 ]; then
    printf '\n### recent commits (no running generation to date from)\n'
    git -C "$consumer" --no-pager log --oneline -n 10 2>/dev/null
    return 0
  fi
  printf '\n### committed since the running generation (%s)\n' "$(date -r "$mtime" '+%Y-%m-%d %H:%M' 2>/dev/null || echo '?')"
  local first
  first="$(git -C "$consumer" log --format=%H --before="@$mtime" -n 1 2>/dev/null)"
  if [ -n "$first" ]; then
    git -C "$consumer" --no-pager log --oneline "$first..HEAD" 2>/dev/null | head -n 30
    git -C "$consumer" --no-pager diff "$first..HEAD" 2>/dev/null | head -n 400 | clip 12000
  else
    printf '(no commit predates it — this checkout is younger than the generation)\n'
  fi
}

haus_rev() {
  jq -r '.nodes[.nodes.root.inputs.haus // "haus"].locked.rev // "unknown"' \
    "$consumer/flake.lock" 2>/dev/null || printf 'unknown'
}

case "$class" in
  build) evidence="$(build_slice)" ;;
  *)     evidence="$(phase_slice)" ;;
esac
[ -n "$evidence" ] || evidence="(nothing captured — reproduce it yourself with the command in the rules below)"

# ---- the prompt -------------------------------------------------------------
# Deliberately silent on where it may commit: the instructions this machine
# already writes for every client (haus.ai.instructions) say what a one-off in
# a non-worktree checkout may do, and a second copy of that rule here would
# drift away from it.
# The heredoc lives in a function rather than inside the `$( )` that captures
# it: bash 3.2 mis-parses a heredoc opened inside a command substitution, and
# while this script always runs under nix's bash 5, being readable by the bash
# every Mac ships is what makes `bash -n` a usable check on it.
build_prompt() {
cat <<PROMPT
A \`haus rebuild\` on host **$host** just failed in the **$class** phase${when:+ ($when)}.
You are being run once, non-interactively, to fix it. Work in $consumer — that
is your cwd and the whole of your remit. The machine is still on generation
${gen:-?}; nothing new was activated.

## Rules
- Do NOT run \`haus rebuild\`, \`haus update\`, \`darwin-rebuild\` or anything else
  that activates this machine. Activation is the user's call and it is serial;
  they will run it themselves when you are done.
- Verify your fix by evaluating it, which changes nothing:
      nix eval "$consumer#darwinConfigurations.$host.system.drvPath"
  It must succeed before you stop. For a build- or activation-phase failure that
  is necessary, not sufficient — say so in your summary rather than overclaiming.
- Commit the fix in $consumer, with a message that says what broke and why the
  change fixes it. Leave the tree clean.
- If you cannot find a real fix, change nothing, commit nothing, and say what you
  ruled out. A plausible guess committed here costs the user a failed rebuild to
  discover. Do not disable, comment out or delete the feature that failed just to
  make evaluation pass.
- This machine pins haus at rev $(haus_rev) (github:hausfold/haus). haus.* options
  come from there; \`haus options\` and \`haus get <path>\` read what this machine
  actually has.

## What the failure said
\`\`\`
$evidence
\`\`\`

## What changed in $consumer since the last good rebuild
\`\`\`diff
$(since_good)
\`\`\`

## When you are done
End with two or three lines: what was wrong, what you changed, and whether
\`nix eval\` passes now. haus draws the banner; you do not need to notify anyone.
PROMPT
}
prompt="$(build_prompt)"

if [ -n "$DRY" ]; then
  printf '%s\n' "$prompt"
  exit 0
fi

# ---- is this failure still real? --------------------------------------------
# A breadcrumb outlives the failure that wrote it. `haus rebuild` clears it on
# success and takes the fin down with it (modules/core/haus.sh's `fault_clear`),
# but that only covers the machine that rebuilt: a fin answered days later, or a
# `haus fix` typed from memory, can still arrive at a config somebody already
# fixed by hand. Spawning an agent there is not a no-op — it is an unattended
# turn with its permission gate open, holding a slice of some other rebuild's
# log as "what the failure said".
#
# So for the one class where the question is cheap and exact, ask it: an
# evaluation failure that now evaluates is over. Deliberately NOT asked for the
# other two — a build or an activation failure evaluates perfectly well, and
# refusing on that would refuse every real one.
if [ "$class" = resolve ] \
  && nix eval --raw "$consumer#darwinConfigurations.$host.system.drvPath" >/dev/null 2>&1; then
  die2 "that failure is over — $consumer evaluates again. Nothing was run."
fi

# ---- run it -----------------------------------------------------------------
mkdir -p "$STATE"
[ -f "$FIXLOG" ] && mv -f "$FIXLOG" "$FIXLOG.prev" 2>/dev/null
{
  printf '=== %s · haus fix · %s · %s phase · %s ===\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" "$host" "$class" "$CLIENT"
  printf -- '--- prompt ---\n%s\n--- transcript ---\n' "$prompt"
} >"$FIXLOG"

banner pulse "haus fix · $host" "$CLIENT is reading the $class failure…"

head_before="$(git -C "$consumer" rev-parse HEAD 2>/dev/null || echo none)"

# HAUS_DESKTOP_OK: the desktop guard's whole job is to put a question on screen
# before an agent touches the pointer or focus. This run is headless and started
# from a banner, so that question would be asked of nobody — see the header.
# stdin from /dev/null so a client that would prompt gets EOF and exits rather
# than blocking forever on a terminal it does not have.
export HAUS_DESKTOP_OK=1
# Only where somebody is looking. The trill pill runs this from a detached
# holder with both streams on /dev/null, and sourcing a thousand lines of bash
# to decide not to draw is the cost `focus` made ui_load lazy to avoid — fd 2
# is the one the region paints, so it is the one asked. The gate is the
# CALL's, not the block's: `statusline.sh` loads the same block with no
# terminal at all.
if [ -t 2 ]; then ui_load; fi
# Where this run's own output starts, so the spinner path can print it after
# the row rather than during it — `phase_slice` reads haus.sh's log exactly
# this way, and for the same reason: everything before the offset belongs to
# somebody else.
turn_off="$(wc -c <"$FIXLOG" 2>/dev/null | tr -d ' ')"
case "$turn_off" in '' | *[!0-9]*) turn_off=0 ;; esac
# ONE path, where there used to be a `tee` for a terminal and a redirect for
# everything else. The redirect is now both: `spin_wait` degrades to the plain
# line wherever it cannot paint, and the `tee` had nothing to stream anyway —
# print mode holds its whole answer to the end, so it drew an empty screen for
# a minute and then the lot, while fighting the spinner for the cursor.
"${AGENT[@]}" "$prompt" </dev/null >>"$FIXLOG" 2>&1 &
rc=0; spin_wait "$!" "$CLIENT" "fixing the $class failure" || rc=$?
# The answer, once, under the row it was drawn beneath — and only where
# somebody is looking, which is what the old `tee` branch meant by `-t 1`. On
# the banner path this is /dev/null and the transcript is $FIXLOG, as it always
# was.
if [ -t 1 ]; then
  tail -c "+$((turn_off + 1))" "$FIXLOG" 2>/dev/null
fi

# ---- did it take? -----------------------------------------------------------
# Checked, never taken on the agent's word: `nix eval` is the same question the
# resolve phase asks, it activates nothing, and an agent that reports success
# onto a config that no longer evaluates is the one failure mode that would
# make this feature worse than no feature.
# The second silence, and on a cold eval it is not a short one. `spin_wait`
# prints the line this used to print wherever there is no painter.
nix eval --raw "$consumer#darwinConfigurations.$host.system.drvPath" >>"$FIXLOG" 2>&1 &
evalrc=0; spin_wait "$!" "nix eval" "checking the config evaluates" || evalrc=$?
if [ "$evalrc" = 0 ]; then
  evals=1
else
  evals=""
fi

head_after="$(git -C "$consumer" rev-parse HEAD 2>/dev/null || echo none)"
dirty=""
git -C "$consumer" diff --quiet HEAD 2>/dev/null || dirty=1
committed=""
[ "$head_before" != "$head_after" ] && committed=1

if [ -n "$evals" ] && [ -n "$committed" ]; then
  body="$(git -C "$consumer" log -1 --format=%s 2>/dev/null)"
  [ -n "$dirty" ] && body="$body · uncommitted changes left in the tree"
  banner "done" "fixed — \`haus rebuild\` to apply" "$body"
  note "fixed — run \`haus rebuild\` to apply. Undo: git -C $consumer revert HEAD"
  exit 0
fi

if [ -n "$evals" ]; then
  # Evaluates, but nothing was COMMITTED. Two very different situations, and
  # they must not read alike: an untouched tree means the config was already
  # fine or the agent decided against a change, while a dirty one means the fix
  # may well be sitting there unsaved — which `git revert` cannot undo and a
  # "nothing changed" banner would send you right past.
  if [ -n "$dirty" ]; then
    banner note "haus fix · uncommitted" \
      "$CLIENT left changes in $consumer without committing them — the config evaluates. Read them before \`haus rebuild\`; see $FIXLOG"
    note "uncommitted changes left in $consumer — see $FIXLOG"
  else
    banner note "haus fix · nothing changed" \
      "the config evaluates and $CLIENT committed nothing — see $FIXLOG"
    note "nothing changed — see $FIXLOG"
  fi
  exit 0
fi

banner fault "haus fix · still broken" "$CLIENT ran (exit $rc) and the config still does not evaluate — see $FIXLOG"
note "still broken — see $FIXLOG"
exit 1
