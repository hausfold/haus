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
#   haus-fix --dry-run print the prompt that would be sent, run no agent
#
# Exit 0 when the config evaluates afterwards, 1 when it does not, 2 when there
# was nothing to fix or nothing to fix it with. Every path ends on a banner.
# Installed by modules/ai (its systemPackages, under the room's own switch), so
# `command -v haus-fix` is the ONLY thing core has to test — core never reads
# `config.haus.ai.*`.
#
# @client@ and @oneshot@ are substituted at build time from `haus.ai.default`
# and modules/lib/agent-oneshot.nix.
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
[ "${1:-}" = "--dry-run" ] && DRY=1

# A banner, never a terminal line — this is usually spawned from a trill pill
# with no terminal at all. `haus-notify` picks trill or Apple's banner at
# runtime; the --source is what makes "stop telling me about this" a rules.json
# line rather than a rebuild.
banner() { # banner <kind> <title> [body]
  haus-notify --title "$2" --body "${3:-}" --kind "$1" \
    --source haus.rebuild.fix --symbol wrench.and.screwdriver >/dev/null 2>&1 || true
}

# Said on the terminal when there is one, and always written to the log.
note() { printf '%s\n' "$*" >&2; }

die2() { note "haus fix: $*"; banner fault "haus fix" "$*"; exit 2; }

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

# One at a time. Two agents editing one flake is how you get a merge conflict
# with yourself; `mkdir` is the atomic test-and-set every shell has.
if [ -z "$DRY" ]; then
  mkdir "$LOCK" 2>/dev/null || die2 "a fix is already running (remove $LOCK if it is not)."
  trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT
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
if [ -t 1 ]; then
  "${AGENT[@]}" "$prompt" </dev/null 2>&1 | tee -a "$FIXLOG"
  rc="${PIPESTATUS[0]}"
else
  "${AGENT[@]}" "$prompt" </dev/null >>"$FIXLOG" 2>&1
  rc=$?
fi

# ---- did it take? -----------------------------------------------------------
# Checked, never taken on the agent's word: `nix eval` is the same question the
# resolve phase asks, it activates nothing, and an agent that reports success
# onto a config that no longer evaluates is the one failure mode that would
# make this feature worse than no feature.
note "checking the config evaluates…"
if nix eval --raw "$consumer#darwinConfigurations.$host.system.drvPath" >>"$FIXLOG" 2>&1; then
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
  # Evaluates, but nothing was committed: either it was already fine or the
  # agent decided against a change. Either way there is nothing to apply and
  # saying "fixed" would be a lie.
  banner note "haus fix · nothing changed" "the config evaluates and $CLIENT committed nothing — see $FIXLOG"
  note "nothing changed — see $FIXLOG"
  exit 0
fi

banner fault "haus fix · still broken" "$CLIENT ran (exit $rc) and the config still does not evaluate — see $FIXLOG"
note "still broken — see $FIXLOG"
exit 1
