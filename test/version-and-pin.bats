#!/usr/bin/env bats
# The two answers to "which haus is this?" — `haus version` (what is RUNNING)
# and the line `haus status` draws about the pin (what the next rebuild would
# build, and whether upstream has moved past it).
#
# Both were found by driving a fresh `tahoe-base` VM through a cold install, and
# both leave a working-looking command behind:
#
#   * there was no `version` verb at all, and no `--version`. The first thing
#     anybody types at a CLI they have just met answered `✗ unknown command
#     '--version'` and then dumped thirty verbs, which is the least useful
#     possible response to someone trying to find out what they have.
#   * `git ls-remote <url> <tag>` answers an ANNOTATED tag with the tag OBJECT's
#     hash, and a flake lock pins the COMMIT that tag peels to. Two hashes for
#     one release, compared with `!=`, so on a tag-pinned config — which is what
#     `script/build-golden-vm.sh` writes, and what any consumer wanting a stable
#     pin writes — `haus status` said "a newer haus is available upstream" on
#     every single run while `haus update` said "already at the latest". Neither
#     command errored. They just contradicted each other forever.
#
# ⚠️ Every stub here is a FUNCTION, not a script on PATH, for the reason
# test/report-door.bats spells out: haus.sh prepends the system profile to PATH
# at load, so on a machine that has shipped this a real `git` is ahead of any
# directory a test could add. `command -v` finds a function first.

bats_require_minimum_version 1.5.0

setup() {
  SUBJECT="$BATS_TEST_DIRNAME/../modules/core/haus.sh"

  # haus.sh refuses to load without a config flake (everything but the four
  # exempt verbs). This one carries a lock pinning haus to the commit an
  # annotated tag peels to — the golden VM's shape, and the one the bug needed.
  export HAUS_CONSUMER="$BATS_TEST_TMPDIR/consumer"
  mkdir -p "$HAUS_CONSUMER"
  : >"$HAUS_CONSUMER/flake.nix"
  lockfile hausfold haus v2026.09.03 "$PEELED"
}

# A consumer lock for one haus node. `$4` is the revision it pins — always the
# COMMIT, because that is what Nix writes whatever the ref names.
PEELED=56bbe8d99310b267038490b057d14c32a5ad9b90
TAGOBJ=2d493149fe597e872c2db68b8576d223f2a4ff1e

lockfile() { # lockfile <owner> <repo> <ref> <rev>
  local ref_json=""
  [ -z "$3" ] || ref_json="\"ref\": \"$3\", "
  cat >"$HAUS_CONSUMER/flake.lock" <<JSON
{
  "nodes": {
    "haus": {
      "locked": { "rev": "$4", "lastModified": 1789084800 },
      "original": { ${ref_json}"owner": "$1", "repo": "$2" }
    }
  }
}
JSON
}

# Load haus.sh as a library in a fresh shell, stub the machine away, run a
# snippet. `LSREMOTE` is what the stubbed `git ls-remote` prints — each case
# below sets the remote it wants to reason about.
#
# `REPORT` is taken from the environment rather than pinned to 1, and that is
# load-bearing for half of this file: `status` is a report and draws its body on
# fd 1, while `version` is narration and must not. A harness that set REPORT for
# both would make every `hint` here land on fd 1 and quietly pass the one
# assertion that matters — that the version is the whole of stdout.
haus_sh() { # haus_sh <VAR=val…> <snippet>
  local snippet="${!#}"
  # ⚠️ No backticks anywhere in this string, in a comment least of all: it is
  # double-quoted, so a backtick pair is a command substitution run by THIS
  # shell (report-door.bats measured what that costs on a Mac).
  run env "${@:1:$#-1}" HAUS_CONSUMER="$HAUS_CONSUMER" HAUS_LIB=1 "$BASH" -c "
    set -uo pipefail
    source '$SUBJECT'
    REPORT=\"\${REPORT:-}\"
    current_gen() { echo 42; }
    gen_date() { echo 2026-09-11; }
    host_name() { echo mbp; }
    git() {
      [ \"\$1\" = ls-remote ] || return 1
      # An empty LSREMOTE must print NOTHING, not a blank line: a blank first
      # line would give awk a record whose \$1 is empty and make 'offline' look
      # like 'answered with an empty sha'.
      [ -n \"\${LSREMOTE:-}\" ] || return 0
      printf '%s\\n' \"\$LSREMOTE\"
    }
    $snippet"
}

fail() { printf '%s\n' "$*" >&2; return 1; }   # not a bats builtin

# ---- haus status and an annotated tag ---------------------------------------

@test "a tag-pinned config is up to date, not eternally behind" {
  # The regression itself. ls-remote is asked for both patterns and answers
  # with both lines; the lock holds the PEELED commit, so status must compare
  # against that one and agree with what 'haus update' would say.
  haus_sh REPORT=1 LSREMOTE="$TAGOBJ	refs/tags/v2026.09.03
$PEELED	refs/tags/v2026.09.03^{}" 'cmd_status'
  [ "$status" -eq 0 ] || fail "$output"
  [[ "$output" != *"newer haus is available"* ]] \
    || fail "compared the tag OBJECT to the locked commit again: $output"
  [[ "$output" == *"up to date with upstream"* ]] || fail "$output"
}

@test "the peeled ref is asked for by name, because a bare tag does not return it" {
  # The half of the fix that is invisible from the output above: `git ls-remote
  # <url> v2026.09.03` matches refs/tags/v2026.09.03 and NOT
  # refs/tags/v2026.09.03^{}, so preferring the peel is worth nothing unless the
  # pattern spells it out. Asserted on the call, since a remote that never sends
  # the line cannot be told from one whose line we ignored.
  local asked="$BATS_TEST_TMPDIR/asked"
  haus_sh REPORT=1 ASKED="$asked" '
    git() { printf "%s\n" "$*" >>"$ASKED"; return 1; }
    cmd_status'
  [ "$status" -eq 0 ] || fail "$output"
  grep -q 'refs/tags/v2026.09.03\^{}' "$asked" \
    || fail "the peeled ref was never requested: $(cat "$asked")"
}

@test "a tag that HAS moved is still reported as behind" {
  # The fix must not silence the real signal: same shape, different commit
  # under the tag, and status has to say so.
  haus_sh REPORT=1 LSREMOTE="$TAGOBJ	refs/tags/v2026.09.03
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa	refs/tags/v2026.09.03^{}" 'cmd_status'
  [[ "$output" == *"newer haus is available upstream (aaaaaaaaaaaa)"* ]] || fail "$output"
}

@test "a branch pin has no peeled line and still compares" {
  # `github:hausfold/haus` locks a branch head — one ls-remote line, no peel,
  # and the first-line fallback is the whole answer. Both directions.
  lockfile hausfold haus "" "$PEELED"
  haus_sh REPORT=1 LSREMOTE="$PEELED	refs/heads/main" 'cmd_status'
  [[ "$output" == *"up to date with upstream"* ]] || fail "behind on a branch it matches: $output"

  haus_sh REPORT=1 LSREMOTE="$TAGOBJ	refs/heads/main" 'cmd_status'
  [[ "$output" == *"newer haus is available upstream (2d493149fe59)"* ]] || fail "$output"
}

@test "an unreachable remote says nothing, and does not kill the command" {
  # Offline is the ordinary state of a laptop, and until this change it was the
  # one state this block died on: `git ls-remote` exits non-zero with no network,
  # `pipefail` carries that out of the pipeline, and an assignment whose command
  # substitution failed ends a `set -e` script. `haus status` exited 1 in the
  # middle of itself, silently, every time — which is why the assertion here is
  # on the EXIT CODE and on a line drawn after the probe, not just on the absence
  # of an upstream claim.
  haus_sh REPORT=1 'git() { return 1; }; cmd_status; echo REACHED-THE-END'
  [ "$status" -eq 0 ] || fail "offline status exits non-zero: $output"
  [[ "$output" == *"REACHED-THE-END"* ]] || fail "died mid-command: $output"
  [[ "$output" == *"56bbe8d99310"* ]] || fail "no pinned line: $output"
  [[ "$output" != *"newer haus"* ]] || fail "$output"
  [[ "$output" != *"up to date"* ]] || fail "$output"
}

@test "a remote that answers with nothing claims nothing" {
  haus_sh REPORT=1 LSREMOTE= 'cmd_status'
  [ "$status" -eq 0 ] || fail "$output"
  [[ "$output" != *"newer haus"* ]] || fail "$output"
  [[ "$output" != *"up to date"* ]] || fail "$output"
}

# ---- haus version ------------------------------------------------------------

@test "the version is the whole of stdout, with no glyph on it" {
  # The point of the verb: $(haus --version) is a value. A painted line would
  # put a glyph and a colour escape inside the string every caller compares,
  # which is why `version` is not in the REPORT list.
  haus_sh HAUS_VERSION=2026.09.12 'cmd_version 2>/dev/null'
  [ "$status" -eq 0 ] || fail "$output"
  [ "$output" = "2026.09.12" ] || fail "stdout is not the bare version: $(printf '%q' "$output")"
}

@test "the pinned revision is a note on fd 2, not part of the value" {
  # Drawn with `hint`, which is the narration painter — it measures the stream it
  # writes to. The report body's `info` would have measured fd 1, so the note
  # would carry colour into a redirected stderr and none at all to a terminal
  # whose stdout is the pipe this verb usually feeds.
  haus_sh HAUS_VERSION=2026.09.12 'cmd_version 2>&1'
  [[ "$output" == *"pinned 56bbe8d99310"* ]] || fail "no pin: $output"
  [[ "$output" == *"haus status"* ]] || fail "does not hand the upstream question on: $output"

  # And it is not on fd 1, whatever REPORT happens to say — a `haus version`
  # reached through a report's stream split must still hand back the value alone.
  haus_sh REPORT=1 HAUS_VERSION=2026.09.12 'cmd_version 2>/dev/null'
  [ "$output" = "2026.09.12" ] || fail "the note reached stdout: $(printf '%q' "$output")"
}

@test "no lock is a version, not a failure" {
  # `version` is exempt from the config-flake guard for the same reason `skill`
  # is: a bootstrap that stopped half way is exactly when someone asks.
  rm -f "$HAUS_CONSUMER/flake.lock"
  haus_sh HAUS_VERSION=2026.09.12 'cmd_version 2>/dev/null'
  [ "$status" -eq 0 ] || fail "$output"
  [ "$output" = "2026.09.12" ] || fail "$output"
}

@test "a haus that does not know its version refuses rather than invents one" {
  # `bash haus.sh` out of a checkout has no wrapper and therefore no version. A
  # made-up one would land in a bug report as a fact.
  haus_sh HAUS_VERSION= 'cmd_version 2>&1'
  [ "$status" -ne 0 ] || fail "invented a version: $output"
  [[ "$output" == *"HAUS_VERSION"* ]] || fail "$output"
}

@test "--version and version both reach it, and neither needs a config flake" {
  # The dispatch, not the function. Both spellings are arms, and both are in the
  # guard's exempt list — which is what makes the answer the same on a machine
  # that has not finished installing.
  grep -qE '^  version\|--version\) cmd_version ;;$' "$SUBJECT" \
    || fail "the version arm has moved or changed shape"
  # 🚨 The exempt list is a list of plain verb WORDS, and it has to stay one:
  # report-door.bats and agent-surface.bats each grep this same line with
  # `[a-z |]*` for their own verb, so a `--version` spelled into it turns both of
  # those suites red while the guard goes on working. `--version` is folded to
  # `version` in the loop above the list instead.
  grep -qE '^  show \| report \| skill \| version\) ;;$' "$SUBJECT" \
    || fail "version is no longer exempt from the config-flake guard"
  grep -qE '^    --version\) haus_verb="version"; break ;;$' "$SUBJECT" \
    || fail "--version is no longer folded to the verb before the guard"

  # And end to end, with no flake.nix at all.
  run env HAUS_CONSUMER="$BATS_TEST_TMPDIR/nothing" HAUS_VERSION=2026.09.12 \
    "$BASH" "$SUBJECT" --version
  [ "$status" -eq 0 ] || fail "$output"
  [ "$output" = "2026.09.12" ] || fail "$output"

  run env HAUS_CONSUMER="$BATS_TEST_TMPDIR/nothing" HAUS_VERSION=2026.09.12 \
    "$BASH" "$SUBJECT" version
  [ "$status" -eq 0 ] || fail "$output"
  [ "$output" = "2026.09.12" ] || fail "$output"
}

@test "the verb is in the help, the completion and the unknown-command list" {
  # Three places a verb has to be spelled or it is a command nobody discovers.
  grep -q 'haus version ' "$SUBJECT" || fail "usage() never mentions it"
  grep -qE "die \"unknown command .*\bversion\"" "$SUBJECT" \
    || fail "the unknown-command list does not offer it"
  grep -qE "^    'version:" "$BATS_TEST_DIRNAME/../modules/core/haus-completion.zsh" \
    || fail "zsh completion does not offer it"
}

@test "the version is handed in by the wrapper, from VERSION" {
  # haus.sh is a static readFile with no Nix values in it, so this is the only
  # way the number can reach it — and reading it from anywhere else (the lock,
  # the skill's frontmatter) would answer a different question.
  grep -q 'set-default HAUS_VERSION' "$BATS_TEST_DIRNAME/../modules/core/default.nix" \
    || fail "the wrapper no longer sets HAUS_VERSION"
  grep -q 'HAUS_VERSION ${lib.escapeShellArg (lib.fileContents ../../VERSION)}' \
    "$BATS_TEST_DIRNAME/../modules/core/default.nix" \
    || fail "HAUS_VERSION is no longer the VERSION file"
}
