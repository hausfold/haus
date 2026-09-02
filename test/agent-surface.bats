#!/usr/bin/env bats
# The two halves of the family agent-surface standard haus owes an agent
# (`docs/agent-surface.md` in the workshop): **A3**, the `haus skill` verb, and
# **A2**, `--json` on a read verb — here, `haus get`.
#
# What this suite is FOR. Both are surfaces an agent reads and a person almost
# never does, so every way they break is silent:
#
#   * `haus skill` printing the SOURCE `modules/ai/agents/SKILL.md` instead of
#     the rendered store copy. That file is a TEMPLATE: its version line is the
#     literal `@hausVersion@` and its `references/` pages do not exist beside it
#     at all. Nothing errors — the user is just told their skill version is
#     `@hausVersion@`, and an agent is pointed at option documentation that was
#     never rendered.
#   * `skill install` meeting the read-only Nix symlinks haus itself installed
#     and dying on EPERM. An agent that reads "permission denied" reaches for
#     sudo, and sudo would succeed — at writing into a home-manager generation.
#     So it has to REFUSE, in words, naming `haus.ai.skill`.
#   * `haus get --json` printing a bare value. `null` then means both "nothing
#     defines this yet" and "defined as null", which is exactly the pair
#     `haus unset` creates, and an agent cannot tell a reset from a set.
#   * `haus get --json` on an empty overlay printing the prose line the plain
#     rendering prints. `info` is fd 1 (the note by the verbs in haus.sh), so
#     that lands INSIDE the document, and every caller's `jq` dies on it.
#
# ⚠️ Every stub here is a FUNCTION, not a script on PATH — the reason
# test/report-door.bats spells out: haus.sh prepends the system profile to PATH
# at load, so on a machine that has shipped this a real `haus` is ahead of any
# directory a test could add, and only `command -v`'s function lookup shadows it.

bats_require_minimum_version 1.5.0

setup() {
  SUBJECT="$BATS_TEST_DIRNAME/../modules/core/haus.sh"

  # haus.sh refuses to load without a config flake. Its CONTENT is irrelevant
  # here — nothing in this suite evaluates nix.
  export HAUS_CONSUMER="$BATS_TEST_TMPDIR/consumer"
  mkdir -p "$HAUS_CONSUMER"
  echo '{ outputs = _: { }; }' >"$HAUS_CONSUMER/flake.nix"

  # A stand-in for what agents/skill.nix builds: the rendered SKILL.md (the
  # version line already substituted) plus its three reference pages, and the
  # consumer starter pair that is NOT part of the skill.
  export SKILL="$BATS_TEST_TMPDIR/skill"
  mkdir -p "$SKILL/references"
  printf -- '---\nname: haus\n---\nSkill version: 1.2.3 (rendered).\n' >"$SKILL/SKILL.md"
  echo 'haus.theme.accent — the accent'   >"$SKILL/references/options.md"
  echo '## Focus'                          >"$SKILL/references/rooms.md"
  echo 'recipe: install an app'            >"$SKILL/references/recipes.md"
  echo 'starter AGENTS.md'                 >"$SKILL/consumer-AGENTS.md"
  echo 'starter CLAUDE.md'                 >"$SKILL/consumer-CLAUDE.md"

  export FAKEHOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$FAKEHOME"
}

fail() { printf '%s\n' "$*" >&2; return 1; }   # not a bats builtin

# Load haus.sh as a library in a fresh shell and run a snippet against it.
# HOME is redirected so `skill install`'s client table lands in the tmpdir.
haus_sh() { # haus_sh <VAR=val…> <snippet>
  local snippet="${!#}"
  # The caller's assignments come LAST so a case can override a default —
  # `env` takes the rightmost of a repeated name, and the one this suite most
  # needs to blank is HAUS_SKILL_DIR itself.
  run env \
    HAUS_CONSUMER="$HAUS_CONSUMER" HAUS_SKILL_DIR="$SKILL" HOME="$FAKEHOME" \
    "${@:1:$#-1}" HAUS_LIB=1 "$BASH" -c "
    set -uo pipefail
    source '$SUBJECT'
    $snippet"
}

# ---- A3: printing the skill --------------------------------------------------

@test "haus skill prints the RENDERED copy, never the template beside it" {
  haus_sh 'cmd_skill'
  [ "$status" -eq 0 ] || fail "$output"
  [[ "$output" == *"Skill version: 1.2.3"* ]] || fail "not the rendered file: $output"
  # The whole reason this verb reads a store path rather than a sibling file.
  [[ "$output" != *'@hausVersion@'* ]] || fail "the unsubstituted template rode through: $output"
}

@test "the source SKILL.md really is a template, so the check above means something" {
  # If someone stops substituting the version, the assertion above passes for
  # the wrong reason and this verb quietly becomes safe to point at the source.
  grep -q '@hausVersion@' "$BATS_TEST_DIRNAME/../modules/ai/agents/SKILL.md" \
    || fail "modules/ai/agents/SKILL.md no longer carries @hausVersion@ — re-read cmd_skill's header before trusting it"
}

@test "haus.sh never names a path inside the repo to read the skill from" {
  # The regression this suite exists to stop, pinned at the source: the store
  # path is handed in by the wrapper, and there is no checkout to fall back to.
  # Comments are stripped wherever they are indented to, not just at column 0 —
  # an indented one naming the path would otherwise fail this spuriously, and a
  # test that cries wolf is one somebody deletes.
  grep -n 'agents/SKILL\.md\|modules/ai/agents' "$SUBJECT" | grep -vE '^[0-9]+:[[:space:]]*#' \
    && fail "haus.sh reaches for the skill source directly"
  return 0
}

@test "a named reference page prints" {
  haus_sh 'cmd_skill options'
  [ "$status" -eq 0 ] || fail "$output"
  [[ "$output" == *"haus.theme.accent"* ]] || fail "$output"
}

@test "a sibling skill outranks a reference of the same name" {
  # A3's `skill <name>` means a SIBLING skill; haus ships none today, and the
  # reference arm is haus's addition. The order is what keeps the day haus grows
  # one from being shadowed by a page that happens to share its name.
  mkdir -p "$SKILL/options"
  echo 'a real sibling skill' >"$SKILL/options/SKILL.md"
  haus_sh 'cmd_skill options'
  [[ "$output" == *"a real sibling skill"* ]] || fail "the reference shadowed the skill: $output"
}

@test "an unknown name is refused on stderr, with nothing on stdout, and lists what there is" {
  haus_sh 'cmd_skill nope 2>/dev/null'
  [ "$status" -eq 1 ] || fail "accepted an unknown name"
  [ -z "$output" ] || fail "the refusal landed on stdout: $output"
  haus_sh 'cmd_skill nope 2>&1'
  [[ "$output" == *"options"* ]] && [[ "$output" == *"rooms"* ]] \
    || fail "the refusal named no pages: $output"
}

@test "every name the refusal offers actually prints" {
  # The loop this closes: `haus skill nope` lists what there is, an agent takes
  # the list at its word, and `haus skill haus` answers with the SAME refusal.
  # `haus` has no `haus/SKILL.md` and no `references/haus.md`, so it only
  # resolves because cmd_skill spells it out.
  haus_sh 'cmd_skill nope 2>&1'
  local listed; listed="${output##*this machine has: }"
  [ -n "$listed" ] || fail "the refusal listed nothing: $output"
  local n
  for n in $listed; do
    haus_sh "cmd_skill $n 2>&1"
    [ "$status" -eq 0 ] || fail "the refusal offered '$n', which then refused: $output"
    [ -n "$output" ] || fail "'$n' printed nothing"
  done
}

@test "this-machine is named as a real page elsewhere, not as a typo" {
  # It is the one page the store copy cannot carry — modules/ai renders it per
  # HOST — so the answer is where it lives, never "no such thing".
  haus_sh 'cmd_skill this-machine 2>&1'
  [ "$status" -eq 1 ] || fail "invented a per-host page"
  [[ "$output" == *"rendered per host"* ]] || fail "treated a real page as a typo: $output"

  # And when the machine HAS one, it prints it.
  mkdir -p "$FAKEHOME/.claude/skills/haus/references"
  echo 'host: testmac' >"$FAKEHOME/.claude/skills/haus/references/this-machine.md"
  haus_sh 'cmd_skill this-machine'
  [ "$status" -eq 0 ] || fail "$output"
  [[ "$output" == *"host: testmac"* ]] || fail "$output"
}

@test "two names at once are refused rather than silently half-ignored" {
  haus_sh 'cmd_skill options rooms 2>/dev/null'
  [ "$status" -eq 1 ] || fail "printed one and said nothing about the other"
}

@test "a name is one component, never a path" {
  # Not a security boundary — the caller can `cat` anything they can read — but
  # `haus skill ../../etc/passwd` answering with a file is a surprise a CLI
  # should not hold, and `references/<name>.md` would happily traverse.
  haus_sh 'cmd_skill ../consumer/flake 2>&1'
  [ "$status" -eq 1 ] || fail "walked out of the skill dir"
  [[ "$output" == *"one word, not a path"* ]] || fail "$output"
}

@test "a missing skill dir is named, not silently empty" {
  haus_sh HAUS_SKILL_DIR= 'cmd_skill 2>&1'
  [ "$status" -eq 1 ] || fail "printed nothing and called it success"
  [[ "$output" == *"HAUS_SKILL_DIR"* ]] || fail "$output"
}

@test "the payload is on stdout even though skill is not a REPORT command" {
  # `haus skill | pbcopy` has to be whole. It is `cat`, so it does not need the
  # REPORT arm — and must not have it, or `skill install`'s narration would land
  # in the middle of the document. Both halves, asserted together.
  haus_sh 'cmd_skill 2>/dev/null'
  [[ "$output" == *"Skill version"* ]] || fail "the skill went to stderr: $output"
  # Two assertions, because the negative one alone passes VACUOUSLY the day the
  # list is reordered or rewrapped: find the arm first, by a member that is not
  # the one under test, and only then check what it does not contain.
  local arm
  arm="$(grep -nE '^  [a-z| ]*\bdoctor\b[a-z| ]*\)$' "$SUBJECT" | head -1)" \
    || fail "could not find the REPORT arm at all"
  [ -n "$arm" ] || fail "could not find the REPORT arm at all"
  [[ "$arm" != *skill* ]] || fail "skill was added to the REPORT list: $arm"
}

# ---- A3: installing it -------------------------------------------------------

@test "an install lands exactly what a rebuild would, minus the per-host page" {
  # The list has to MATCH modules/ai's `agentSkillFiles`: a directory that
  # differs from the one `haus.ai.skill` writes is a second layout for every
  # later reader, and `haus doctor` reads consumer-AGENTS.md from this very path
  # to decide whether to offer the starter pair.
  haus_sh "cmd_skill_install --dir '$FAKEHOME/elsewhere'"
  [ "$status" -eq 0 ] || fail "$output"
  local d="$FAKEHOME/elsewhere/haus" f
  for f in SKILL.md consumer-AGENTS.md consumer-CLAUDE.md; do
    [ -f "$d/$f" ] || fail "no $f"
  done
  for f in options rooms recipes; do
    [ -f "$d/references/$f.md" ] || fail "no references/$f.md"
  done
  # The one exception, and it is not one this can close: modules/ai renders
  # `this-machine.md` per HOST, so it is not in the store dir copied from.
  [ ! -e "$d/references/this-machine.md" ] || fail "invented a per-host page"
}

@test "doctor's starter-pair probe finds what this installed" {
  # The regression that made leaving the pair out wrong: doctor tells the user
  # to switch on the room whose work they have just done by hand.
  haus_sh "cmd_skill_install --dir '$FAKEHOME/elsewhere'"
  grep -q 'consumer-AGENTS\.md' "$SUBJECT" \
    || fail "haus doctor no longer probes for the starter pair — re-read why install carries it"
  [ -f "$FAKEHOME/elsewhere/haus/consumer-AGENTS.md" ] || fail "install did not leave one"
}

@test "a copy it wrote is writable, not a read-only store file" {
  # `cp` of a store file hands the user r--r--r--, the same trap the skill's own
  # consumer-pair note names. A skill nobody can edit is one nobody can fix.
  haus_sh "cmd_skill_install --dir '$FAKEHOME/elsewhere'"
  [ -w "$FAKEHOME/elsewhere/haus/SKILL.md" ] || fail "installed read-only"
}

@test "the install narrates on stderr, so stdout stays free for the skill" {
  haus_sh "cmd_skill_install --dir '$FAKEHOME/elsewhere' 2>/dev/null"
  [ -z "$output" ] || fail "install wrote to stdout: $output"
}

@test "a Nix symlink is REFUSED in words, naming haus.ai.skill — never an EPERM" {
  # The haus machine. Every destination is a read-only symlink into the store
  # that a rebuild put there, so there is nothing to do and nothing to force.
  local d="$FAKEHOME/.claude/skills"
  mkdir -p "$d/haus/references"
  local f
  # ALL of them, the way a rebuild leaves them — a fixture that symlinks only
  # some would let this pass while the rest were quietly written over.
  for f in SKILL.md consumer-AGENTS.md consumer-CLAUDE.md; do ln -s "$SKILL/$f" "$d/haus/$f"; done
  for f in options rooms recipes; do ln -s "$SKILL/references/$f.md" "$d/haus/references/$f.md"; done

  haus_sh 'cmd_skill_install --client claude 2>&1'
  [ "$status" -eq 0 ] || fail "a machine in its NORMAL state was reported as a failure: $output"
  [[ "$output" == *"haus.ai.skill"* ]] || fail "did not name what installed them: $output"
  [[ "$output" == *"nothing to install"* ]] || fail "no refusal line: $output"
  # And the symlinks are untouched — no clobber, no dereferenced write.
  [ -L "$d/haus/SKILL.md" ] || fail "the store symlink was replaced"
}

@test "a copy in a CLIENT dir warns about the rebuild that will trip over it" {
  # `haus.ai.skill` declares these exact paths as home-manager files, and
  # home-manager will not link over a real one: a mkHaus consumer renames each
  # to *.backup and leaves it in $HOME forever (and fails outright the second
  # time), one composing darwinModules.* by hand refuses to activate at all.
  mkdir -p "$FAKEHOME/.claude"
  haus_sh 'cmd_skill_install --client claude 2>&1'
  [ "$status" -eq 0 ] || fail "$output"
  [[ "$output" == *"haus.ai.skill wants to link the same paths"* ]] || fail "no warning: $output"
}

@test "--dir does not carry that warning" {
  # A directory of the user's own is not a path haus will ever link, so the
  # warning would be noise — and a warning that fires on the safe path is one
  # people learn to scroll past on the unsafe one.
  haus_sh "cmd_skill_install --dir '$FAKEHOME/mine' 2>&1"
  [[ "$output" != *"wants to link the same paths"* ]] || fail "warned about a path haus never touches: $output"
}

@test "an existing file that DIFFERS is left alone, with the diff path named" {
  local d="$FAKEHOME/.codex/skills"
  mkdir -p "$d/haus"
  echo 'someone edited this' >"$d/haus/SKILL.md"
  haus_sh 'cmd_skill_install --client codex 2>&1'
  [ "$status" -eq 0 ] || fail "$output"
  [ "$(cat "$d/haus/SKILL.md")" = 'someone edited this' ] || fail "clobbered a hand-edited skill"
  [[ "$output" == *"exists and differs"* ]] || fail "$output"
  [[ "$output" == *"$SKILL/SKILL.md"* ]] || fail "did not say what to diff it against: $output"
}

@test "installing twice is quiet and idempotent" {
  haus_sh "cmd_skill_install --dir '$FAKEHOME/twice'"
  haus_sh "cmd_skill_install --dir '$FAKEHOME/twice' 2>&1"
  [ "$status" -eq 0 ] || fail "$output"
  [[ "$output" != *"differs"* ]] || fail "a byte-identical file was treated as a conflict: $output"
}

@test "with no client and no flag, it writes into every client that exists" {
  # The bare `haus skill install`. A client is "present" when its parent dir is
  # — `~/.claude` exists long before `~/.claude/skills` does.
  mkdir -p "$FAKEHOME/.claude" "$FAKEHOME/.pi/agent"
  haus_sh 'cmd_skill_install'
  [ "$status" -eq 0 ] || fail "$output"
  [ -f "$FAKEHOME/.claude/skills/haus/SKILL.md" ] || fail "claude was skipped"
  [ -f "$FAKEHOME/.pi/agent/skills/haus/SKILL.md" ] || fail "pi was skipped"
  [ ! -e "$FAKEHOME/.codex" ] || fail "invented a client that is not installed"
}

@test "an unknown client and an unknown flag are both refused" {
  haus_sh 'cmd_skill_install --client emacs 2>/dev/null'
  [ "$status" -eq 1 ] || fail "accepted an unknown client"
  haus_sh 'cmd_skill_install --force 2>/dev/null'
  [ "$status" -eq 1 ] || fail "accepted an unknown flag"
}

@test "a flag with nothing after it says so" {
  # `shift 2` with one positional left returns 1, and under `set -e` that ends
  # the command with nothing on either stream — a refusal nobody can read.
  haus_sh 'cmd_skill_install --dir 2>&1'
  [ "$status" -eq 1 ] || fail "accepted a bare --dir"
  [[ "$output" == *"--dir needs a path"* ]] || fail "died silently: '$output'"
  haus_sh 'cmd_skill_install --client 2>&1'
  [[ "$output" == *"--client needs one of"* ]] || fail "died silently: '$output'"
}

@test "the client table matches modules/ai's agentHomes" {
  # Core may not read the AI room's config, so this table is that room's
  # `agentHomes` said again in bash. The two move together or `skill install`
  # writes where nothing reads.
  local ai="$BATS_TEST_DIRNAME/../modules/ai/default.nix"
  local c dir
  for c in claude codex opencode pi; do
    haus_sh "skill_client_dir $c"
    # haus.sh answers an absolute path under $HOME; agentHomes writes it
    # home-relative, which is the same string with `$HOME/` off the front
    # (`.claude/skills`). One spelling, derived, so neither side can be matched
    # by an arm that could never fire.
    dir="${output#"$FAKEHOME"/}"
    grep -qF "skills = \"$dir\";" "$ai" \
      || fail "$c: haus.sh says $dir, which modules/ai's agentHomes does not"
  done
  # And the derivation above is doing work: a spelling agentHomes has never
  # carried must fail it.
  grep -qF 'skills = ".emacs/skills";' "$ai" && fail "the grep matches anything"
  return 0
}

# ---- A3: discoverability -----------------------------------------------------

@test "the verb is discoverable: help, the dispatch, and zsh completion" {
  grep -q "^  haus skill " "$SUBJECT" || fail "haus --help does not list skill"
  grep -qE '^  skill\)' "$SUBJECT" || fail "no dispatch arm"
  grep -q "^    'skill:" "$BATS_TEST_DIRNAME/../modules/core/haus-completion.zsh" \
    || fail "zsh completion does not offer skill"
}

@test "skill is exempt from the config-flake guard" {
  # An agent dropped into a fresh checkout, a container or half a bootstrap
  # asking what haus is must not be refused: the answer is one store path and
  # nothing on this machine at all.
  grep -qE '^  [a-z |]*\bskill\b[a-z |]*\) ;;$' "$SUBJECT" \
    || fail "skill is not exempt from the config-flake guard"
  run env HAUS_CONSUMER="$BATS_TEST_TMPDIR/nothing-here" HAUS_SKILL_DIR="$SKILL" \
      HOME="$FAKEHOME" "$BASH" "$SUBJECT" skill
  [ "$status" -eq 0 ] || fail "refused without a config flake: $output"
  [[ "$output" == *"Skill version"* ]] || fail "$output"
}

# ---- A2: haus get --json -----------------------------------------------------

# The listing and the single-path read both evaluate nix, so the two calls that
# would are stubbed: `settings_eval_json` answers from a table, and the option
# surface is taken as read (that check is `settings_option_exists`'s job, and it
# is unchanged by this feature).
get_sh() { # get_sh <snippet>
  haus_sh "
    host_name() { echo testhost; }
    settings_option_exists() { :; }
    settings_eval_json() {
      case \"\$2\" in
        haus.theme.accent) printf '\"mauve\"' ;;
        haus.bar.enable)   printf 'true' ;;
        haus.focus.slack)  printf 'null' ;;
        *) return 1 ;;
      esac
    }
    $1"
}

@test "one path is one object, and the value keeps its JSON type" {
  get_sh 'cmd_get theme.accent --json'
  [ "$status" -eq 0 ] || fail "$output"
  run jq -e '.path == "haus.theme.accent" and .defined == true and .value == "mauve"' <<<"$output"
  [ "$status" -eq 0 ] || fail "wrong shape"

  get_sh 'cmd_get bar.enable --json'
  run jq -e '.value == true' <<<"$output"
  [ "$status" -eq 0 ] || fail "a boolean came back as a string"
}

@test "defined:false is what tells 'nothing names it yet' from 'set to null'" {
  # The pair `haus unset` creates, and the whole reason this is an envelope
  # rather than a bare value.
  get_sh 'cmd_get focus.slack --json'
  run jq -e '.defined == true and .value == null' <<<"$output"
  [ "$status" -eq 0 ] || fail "a real null lost its defined flag: $output"

  get_sh 'cmd_get theme.nothing --json'
  run jq -e '.defined == false and .value == null' <<<"$output"
  [ "$status" -eq 0 ] || fail "an undefined path was not marked: $output"
}

@test "plain output is unchanged by any of this" {
  get_sh 'cmd_get theme.accent'
  [ "$output" = "mauve" ] || fail "the bare value moved: $output"
}

@test "the listing is an array, and an empty overlay is [] rather than prose" {
  mkdir -p "$HAUS_CONSUMER/hosts/testhost/settings"
  get_sh 'cmd_get --json'
  [ "$output" = "[]" ] || fail "an empty overlay printed something jq cannot read: $output"

  local d="$HAUS_CONSUMER/hosts/testhost/settings"
  printf '# Managed by haus set.\n' >"$d/theme.accent.nix"
  printf '# Managed by haus set.\n' >"$d/bar.enable.nix"
  get_sh 'cmd_get --json'
  run jq -e 'length == 2 and ([.[].path] | index("haus.theme.accent")) != null' <<<"$output"
  [ "$status" -eq 0 ] || fail "not the array shape: $output"
}

@test "a settings dir that does not exist is [] too" {
  get_sh 'cmd_get --json'
  [ "$output" = "[]" ] || fail "$output"
}

@test "nothing but JSON reaches stdout" {
  # `info` is fd 1 (the note by the verbs), so the prose lines the plain
  # rendering prints would land INSIDE the document.
  get_sh 'cmd_get --json 2>/dev/null'
  run jq -e . <<<"$output"
  [ "$status" -eq 0 ] || fail "stdout did not parse as JSON: $output"

  get_sh 'cmd_get theme.nothing --json 2>/dev/null'
  run jq -e . <<<"$output"
  [ "$status" -eq 0 ] || fail "stdout did not parse as JSON: $output"
}

@test "a pre-flight that cannot evaluate keeps its prose off stdout" {
  # `get` is a REPORT command, so `settings_option_exists`'s warn — a dozen
  # lines of nix on a config that will not evaluate — draws on fd 1. Under
  # --json that lands INSIDE the document and every caller's jq dies on it.
  haus_sh "
    host_name() { echo testhost; }
    settings_option_exists() { warn 'could not evaluate this machine'; die 'nope'; }
    cmd_get theme.accent --json 2>/dev/null"
  [ -z "$output" ] || fail "the pre-flight's prose reached stdout: $output"
}

@test "an eval that fails says why on stderr, and still answers in JSON" {
  # `defined: false` is "this produced no value", which is usually the undefined
  # key and is not only that. The field says what happened; the stream says why.
  haus_sh "
    host_name() { echo testhost; }
    settings_option_exists() { :; }
    settings_eval_json() { echo 'error: attribute missing' >&2; return 1; }
    cmd_get theme.accent --json 2>/dev/null"
  run jq -e '.defined == false' <<<"$output"
  [ "$status" -eq 0 ] || fail "stdout was not the object: $output"

  haus_sh "
    host_name() { echo testhost; }
    settings_option_exists() { :; }
    settings_eval_json() { echo 'error: attribute missing' >&2; return 1; }
    cmd_get theme.accent --json 2>&1 >/dev/null"
  [[ "$output" == *"attribute missing"* ]] || fail "nix's reason was swallowed: $output"
}

@test "a second path, and an unknown flag, are refused" {
  get_sh 'cmd_get theme.accent bar.enable 2>/dev/null'
  [ "$status" -eq 1 ] || fail "silently ignored a second path"
  get_sh 'cmd_get --pretty 2>/dev/null'
  [ "$status" -eq 1 ] || fail "accepted an unknown flag"
}

@test "the dispatch passes flags through" {
  # `get) cmd_get "${2:-}"` swallowed everything past the first word, so
  # `haus get theme.accent --json` would have been a plain read with no error.
  grep -qE '^  get\)\s+shift; cmd_get "\$@" ;;' "$SUBJECT" \
    || fail "the get arm no longer forwards its arguments"
}

@test "--json is discoverable: help and zsh completion" {
  grep -q -- '--json for an agent' "$SUBJECT" || fail "haus --help does not mention get --json"
  grep -q -- '--json:"one {path,defined,value} object' \
    "$BATS_TEST_DIRNAME/../modules/core/haus-completion.zsh" \
    || fail "zsh completion does not offer get --json"
}
