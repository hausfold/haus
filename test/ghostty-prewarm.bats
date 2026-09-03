#!/usr/bin/env bats
# The Ghostty cold-start pre-warm, pinned across the three scripts that carry it.
#
# ── the one statement of the spelling, for all of them ───────────────────────
# The executable inside the bundle is LOWER-CASE — `Ghostty.app/Contents/MacOS/
# ghostty` — so `pgrep -x Ghostty` matches nothing, ever. It is `pgrep -ix
# ghostty`. That one word was wrong in scripts/new-window.sh and in
# lanes/lane-open.sh simultaneously until #415 (2026-08-19), where it cost every
# ⌘N and every lane spawn a full two seconds of polling for a process that was
# already up, silently: the branch is a fast path that ran as a slow one, and
# nothing anywhere reported it. This file is where that fact is stated now;
# the three carriers point here instead of re-deriving it a fourth time.
#
# ── why this is a test and not a shared helper ───────────────────────────────
# The overlap is four lines. Grilled 2026-09-03 and deliberately NOT promoted to
# a sourced helper or a modules/lib/ui-load.nix-style pinned string: those earn
# their indirection at ten carriers of forty lines whose every failure mode is
# silent, and this is three carriers of four lines whose one failure was caught
# and fixed in both files in the same pass. A sourced helper would also have to
# be resolvable from lanes/lane-open.sh, which scruff may exec from launchd.
#
# What this suite pins is therefore the INVARIANT, not the text — and that
# distinction is the whole point. A byte-diff between the copies would not have
# caught the bug above: both copies were wrong, identically, and a diff of them
# was green the entire time. So:
#
#   * no `pgrep` anywhere in the room's shell asks for a capital-G Ghostty;
#   * every carrier's poll keeps the same 40 × 0.05s ceiling (~2s), which is
#     the number that makes the branch a bounded wait rather than a hang;
#   * the guard is the pgrep itself, so a warm Ghostty pays one process and
#     nothing else.
#
# The two scripts that deliberately have NO pre-warm are pinned as absences,
# because both are one "helpful" commit away from growing one:
#
#   * scripts/float-term.sh always `open -na`s a FRESH instance, so there is no
#     running app for a cold start to race — a pre-warm there would launch a
#     whole second Ghostty for nothing.
#   * scripts/focused-session.sh's pgrep is a REFUSAL, not a warm-up: without
#     it, `tell application "Ghostty"` would LAUNCH Ghostty, so a chord pressed
#     over Finder would open a terminal nobody asked for and then answer "no
#     session" anyway. Turning that guard into a pre-warm inverts the script.
#
# scripts/raise-session.sh is the third carrier as of this suite, and it is a
# fix rather than a refactor: its ghostty branch asked a possibly-cold Ghostty
# for a window with no wait at all, and empty is a `return 1` the bar's agent
# row reports as nothing happening.

bats_require_minimum_version 1.5.0

ROOM() { printf '%s' "$BATS_TEST_DIRNAME/../modules/terminal"; }

# The line every carrier's poll turns on. Anchoring the extraction here rather
# than on the `for` keeps lanes/lane-open.sh's OTHER `seq 1 40` — the one it
# `printf`s into the lane's own launcher, which polls aerospace and not pgrep —
# out of the match.
POLL_LINE='pgrep -ix ghostty >/dev/null 2>&1 && break'

# The canonical body, dedented. Carriers sit at different nesting depths (the
# raise-session one is inside a `case` arm), so indentation is normalized away:
# what is pinned is the ceiling and the spelling, not the layout.
canonical() {
  cat <<'BODY'
for _ in $(seq 1 40); do
pgrep -ix ghostty >/dev/null 2>&1 && break
sleep 0.05
done
BODY
}

# The four lines around the poll, dedented.
poll_body() { # FILE
  local n
  n=$(grep -n -F "$POLL_LINE" "$1" | cut -d: -f1)
  [ -n "$n" ] || return 1
  sed -n "$((n - 1)),$((n + 2))p" "$1" | sed 's/^[[:space:]]*//'
}

poll_count() { # FILE
  grep -c -F "$POLL_LINE" "$1" || true
}

# Every carrier, one per line.
carriers() {
  cat <<CARRIERS
$(ROOM)/scripts/new-window.sh
$(ROOM)/lanes/lane-open.sh
$(ROOM)/scripts/raise-session.sh
CARRIERS
}

@test "every carrier polls on the same 40 x 0.05s ceiling" {
  local f
  while read -r f; do
    [ -n "$f" ] || continue
    run -0 poll_body "$f"
    [ "$output" = "$(canonical)" ] || {
      printf 'carrier %s no longer holds the canonical poll:\n%s\n' "$f" "$output" >&2
      false
    }
  done < <(carriers)
}

@test "no carrier grew a second pre-warm" {
  local f
  while read -r f; do
    [ -n "$f" ] || continue
    [ "$(poll_count "$f")" = 1 ]
  done < <(carriers)
}

@test "the pre-warm is guarded by the pgrep, so a warm Ghostty pays one process" {
  local f
  while read -r f; do
    [ -n "$f" ] || continue
    grep -q -F '! pgrep -ix ghostty >/dev/null 2>&1' "$f"
  done < <(carriers)
}

# The bug itself: a capital-G process name matches nothing and fails SILENTLY,
# which is why it survived in two files at once. Comments are stripped first —
# every carrier legitimately names the wrong spelling while explaining it.
#
# Scope, stated so nobody reads more into a green run than is there: `*.sh`
# only. Shell embedded in a .nix string is NOT scanned, and one such mention
# exists on purpose — modules/terminal/options.nix names the wrong spelling in
# an option description, which ships to the docs site through
# docs/site-data/options.json. Widening the scan would have to except it.
# The pattern is also deliberately loose enough to flag a legitimate `pgrep -f
# Ghostty.app`; that direction of wrongness is a red build someone reads, not
# a silent pass.
@test "nothing in the room's shell pgreps a capital-G Ghostty" {
  local hits
  hits=$(
    find "$(ROOM)" -name '*.sh' -type f -print0 |
      xargs -0 grep -n 'pgrep[^|;]*Ghostty' |
      awk -F: '{ line = $0; sub(/^[^:]*:[0-9]*:/, "", line)
                 if (line !~ /^[[:space:]]*#/) print }'
  )
  [ -z "$hits" ] || {
    printf 'pgrep against a capital-G Ghostty matches nothing:\n%s\n' "$hits" >&2
    false
  }
}

@test "float-term.sh stays pre-warm-free — it always spawns a fresh instance" {
  [ "$(poll_count "$(ROOM)/scripts/float-term.sh")" = 0 ]
  grep -q -F 'open -na Ghostty.app --args "${open_args[@]}"' "$(ROOM)/scripts/float-term.sh"
}

@test "focused-session.sh's pgrep stays a refusal, never a pre-warm" {
  [ "$(poll_count "$(ROOM)/scripts/focused-session.sh")" = 0 ]
  grep -q -F 'pgrep -ix ghostty >/dev/null 2>&1 || exit 0' "$(ROOM)/scripts/focused-session.sh"
}
