#!/usr/bin/env bats
# `haus report` — the in-product door to haus's bug form (modules/core/haus.sh's
# `cmd_report` and its two helpers), and the palette row that is one line into it.
#
# What this suite is FOR. There is no telemetry in anything haus ships, so the
# issue form is the only feedback channel it has — and EVERY way this door can
# break leaves a working-looking command behind:
#
#   * `?template=bug.yml` vs `?title=&body=`. A `body=` prefill opens GitHub's
#     BLANK editor and walks past the form, its fields, its "wrong repo? file it
#     anyway" preamble and its labels. An issue is still filed. It just arrives
#     shapeless, every time, and nothing errors — which is exactly what the row
#     this replaced did for as long as it existed.
#   * the encoder. An encoder built from a "characters allowed in a query" set
#     leaves `+` LITERAL, and the receiving server reads a literal `+` back as a
#     space. Nothing fails; the diagnostics field just quietly says the wrong
#     thing on every line that had one.
#   * the redaction. The block lands in a PUBLIC issue, and a field haus filled
#     in is a weaker kind of consent than one the reporter typed. A home
#     directory that stops being rewritten is a username published for as long
#     as nobody re-reads the diff.
#   * the length cap. Past it the form opens EMPTY, so the branch that puts the
#     block somewhere the reporter can reach is the whole feature on a finished
#     machine — `haus doctor` already encodes to ~6.9 KB on a full hacker Mac.
#
# ⚠️ Every stub here is a FUNCTION, not a script on PATH, for the reason
# test/rebuild-fix-cta.bats spells out: haus.sh prepends the system profile to
# PATH at load, so on a machine that has shipped this feature a real `open` and a
# real `haus-notify` are ahead of any directory a test could add. `command -v`
# finds a function first, so that is the one seam that actually shadows them.

bats_require_minimum_version 1.5.0

setup() {
  SUBJECT="$BATS_TEST_DIRNAME/../modules/core/haus.sh"

  # haus.sh refuses to load without a config flake. This one carries the two
  # landmarks the header reads: the `desktop = ` line `haus add` writes, and a
  # lock pinning haus (the four fields report_header asks flake.lock for).
  export HAUS_CONSUMER="$BATS_TEST_TMPDIR/consumer"
  mkdir -p "$HAUS_CONSUMER"
  cat >"$HAUS_CONSUMER/flake.nix" <<'NIX'
{
  outputs = { haus, ... }: haus.lib.mkHaus {
        desktop = haus.desktops.hacker;
  };
}
NIX
  cat >"$HAUS_CONSUMER/flake.lock" <<'JSON'
{
  "nodes": {
    "haus": {
      "locked": { "rev": "0123456789abcdef0123456789abcdef01234567", "lastModified": 1756684800 },
      "original": { "owner": "hausfold", "repo": "haus" }
    }
  }
}
JSON

  export OPENED="$BATS_TEST_TMPDIR/opened"
  export COPIED="$BATS_TEST_TMPDIR/copied"
  export NOTIFIED="$BATS_TEST_TMPDIR/notified"
}

# Load haus.sh as a library in a fresh shell, stub everything that would touch
# the machine, and run a snippet. `DOCTOR` is what the stubbed `haus doctor`
# prints, so each case below sets the block it wants to reason about.
haus_sh() { # haus_sh <VAR=val…> <snippet>
  local snippet="${!#}"
  # ⚠️ No backticks anywhere in this string, in a comment least of all: it is
  # double-quoted, so a backtick pair is a command substitution run by THIS
  # shell — and on a Mac the first thing a stray one finds is /usr/bin/say,
  # which blocks reading stdin and hangs the whole suite. (Measured. It is also
  # a text-to-speech binary, so the failure mode is worse than a hang.)
  #
  # The stubbed doctor draws with the REAL painters rather than a printf: say is
  # the verb whose stream depends on REPORT, and ok is the one that wears the
  # palette, so a block captured with either wrong shows up here rather than in
  # a public issue.
  run env "${@:1:$#-1}" HAUS_CONSUMER="$HAUS_CONSUMER" HAUS_LIB=1 "$BASH" -c "
    set -uo pipefail
    source '$SUBJECT'
    REPORT=1
    cmd_doctor() { say 'haus doctor'; ok \"\${DOCTOR:-all fine}\"; }
    sw_vers() { case \"\$1\" in -productVersion) echo 26.0.1 ;; *) echo 25A354 ;; esac; }
    sysctl() { echo Mac16,10; }
    open() { printf '%s\n' \"\$1\" >>'$OPENED'; }
    pbcopy() { cat >>'$COPIED'; }
    haus-notify() { printf '%s\n' \"\$*\" >>'$NOTIFIED'; }
    $snippet"
}

fail() { printf '%s\n' "$*" >&2; return 1; }   # not a bats builtin

# The link, which is always the last line of the block-and-link pair.
url() { printf '%s\n' "$output" | grep '^https://' | tail -1; }

# ---- the form, not the blank editor -----------------------------------------

@test "the link opens bug.yml, and prefills nothing but diagnostics" {
  haus_sh 'cmd_report --print'
  [ "$status" -eq 0 ] || fail "$output"
  local u; u="$(url)"
  [[ "$u" == "https://github.com/hausfold/haus/issues/new?template=bug.yml&diagnostics="* ]] \
    || fail "not the form: $u"
  # The three that mean the blank editor, and the one that means haus put words
  # in the reporter's mouth. `labels=` is bug.yml's own job.
  local bad
  for bad in 'body=' 'title=' 'labels=' 'what=' 'area='; do
    [[ "$u" != *"$bad"* ]] || fail "$bad is back in the URL: $u"
  done
}

@test "the block is printed before the link, whatever else happens" {
  # The door's promise is that nothing is sent — which is only inspectable if
  # the reporter can read every line first. It is also the ssh path: on a Mac
  # reached over a terminal there is no browser for the URL to reach.
  haus_sh DOCTOR='  ✓ a finding worth reading' 'cmd_report --print'
  [[ "$output" == *"a finding worth reading"* ]] || fail "$output"
  [[ "$output" == *$'\n\nhttps://github.com/'* ]] || fail "the link is not below the block: $output"
}

@test "doctor's own section headers are part of the block" {
  # `say` goes to fd 2 unless REPORT is set (the note by the verbs in haus.sh),
  # and the capture is a command substitution that only takes fd 1. cmd_report
  # therefore sets REPORT inside it rather than trusting the caller — without
  # that, the block arrives as an unlabelled list of ticks and the reporter
  # pastes a diagnostics field with no sections in it. stderr is discarded here
  # so this can tell the two streams apart at all.
  haus_sh 'REPORT=""; cmd_report --print 2>/dev/null'
  [[ "$output" == *"haus doctor"* ]] || fail "the header went to the wrong stream: $output"
}

@test "the header names the pinned revision, the Mac and the selected desktop" {
  haus_sh 'cmd_report --print'
  [[ "${lines[0]}" == "haus 0123456789ab"* ]] || fail "no revision: ${lines[0]}"
  [[ "$output" == *"macOS 26.0.1 (25A354)"* ]] || fail "no macOS build: $output"
  [[ "$output" == *"Mac16,10"* ]] || fail "no model: $output"
  [[ "$output" == *"desktop: hacker"* ]] || fail "no desktop: $output"
}

@test "a missing config flake is reported, not refused" {
  # The door has to survive the thing it exists to report. A bootstrap that
  # stopped half way leaves no consumer flake, and every other verb dies at the
  # guard above the dispatch — so `report` is exempt there, and the header says
  # "unknown" rather than desktop_selected's `hacker`, which would be a guess
  # dressed as a fact in a public issue.
  # The arm, not its neighbours: `haus skill` joined it and others may. What
  # this pins is that `report` is still IN it.
  grep -qE '^  [a-z |]*\breport\b[a-z |]*\) ;;$' "$SUBJECT" \
    || fail "report is no longer exempt from the config-flake guard"
  haus_sh 'FLAKE=/nope/flake.nix; cmd_report --print'
  [ "$status" -eq 0 ] || fail "$output"
  [[ "$output" == *"desktop: unknown"* ]] || fail "claimed a desktop it could not read: $output"
  [[ "$output" == *"diagnostics="* ]] || fail "no link at all: $output"
}

@test "a pinned FORK is named, and hausfold/haus is not" {
  # A bug in a fork is not a bug here, and the only place that shows is the
  # lock. Silent on the usual machine, so the usual report carries no noise.
  haus_sh 'cmd_report --print'
  [[ "${lines[0]}" != *from* ]] || fail "named the origin for the normal pin: ${lines[0]}"

  local lock="$HAUS_CONSUMER/flake.lock"
  sed -i.bak 's/"owner": "hausfold"/"owner": "ada"/' "$lock"
  haus_sh 'cmd_report --print'
  [[ "${lines[0]}" == *"from ada/haus"* ]] || fail "the fork is invisible: ${lines[0]}"
}

# ---- the encoder ------------------------------------------------------------

@test "a literal + never reaches the query" {
  # The bug the whole family's doors carry a comment about: `+` is a legal
  # character in a query and the server decodes it back as a SPACE. haus prints
  # it in `Tahoe+`, and a report that went through a lax encoder says "Tahoe "
  # with no error anywhere.
  haus_sh DOCTOR='  ⚠ on Tahoe+ this is often BTM: haus btm' 'cmd_report --print'
  local u q; u="$(url)"; q="${u#*diagnostics=}"
  [[ "$q" == *%2B* ]] || fail "the + was not encoded: $q"
  [[ "$q" != *+* ]] || fail "a literal + rode through: $q"
}

@test "every reserved character is percent-encoded, UTF-8 byte by byte" {
  haus_sh DOCTOR='  ✓ a & b = c # d "e"' 'cmd_report --print'
  local u q; u="$(url)"; q="${u#*diagnostics=}"
  [[ "$q" == *%E2%9C%93* ]] || fail "✓ is not UTF-8 encoded: $q"   # the glyph every doctor line wears
  [[ "$q" == *%26* ]] || fail "& rode through: $q"
  [[ "$q" == *%23* ]] || fail "# rode through: $q"
  [[ "$q" == *%0A* ]] || fail "the newlines are gone: $q"
  [[ "$q" != *' '* ]] || fail "a raw space rode through: $q"
}

@test "the query decodes back to exactly the block that was printed" {
  command -v python3 >/dev/null || skip "needs python3"
  haus_sh DOCTOR='  ✓ ünïcode, a & b, cmd+space, 100%' 'cmd_report --print'
  local u; u="$(url)"
  local block; block="${output%$'\n\n'"$u"}"
  run python3 -c '
import sys, urllib.parse
url, block = sys.argv[1], sys.argv[2]
q = urllib.parse.parse_qs(urllib.parse.urlparse(url).query, keep_blank_values=True)
sys.exit(0 if q["diagnostics"][0] == block else 1)
' "$u" "$block"
  [ "$status" -eq 0 ] || fail "the round trip lost something"
}

# ---- what may not reach a public issue ---------------------------------------

@test "the reporter's home directory is written back as ~" {
  haus_sh DOCTOR="  ⓘ nothing orients an agent opened in $HOME/.config/nix" 'cmd_report --print'
  [[ "$output" == *"~/.config/nix"* ]] || fail "not redacted: $output"
  [[ "$output" != *"$HOME/.config/nix"* ]] || fail "the home directory is still in it: $output"
}

@test "a nonsense HOME rewrites nothing" {
  # The guard, not decoration: an empty or `/` home would rewrite every path in
  # the report — and every `/` in its prose — into nonsense.
  haus_sh HOME=/ DOCTOR='  ⓘ /run/current-system/sw/bin/haus' 'cmd_report --print'
  [[ "$output" == *"/run/current-system/sw/bin/haus"* ]] || fail "mangled: $output"
}

@test "no colour escape can ride into the issue" {
  # The C_* are resolved ONCE at load, against the real fd 1 — a command
  # substitution never re-measures them, so a report captured from a terminal
  # would carry an escape on every line of a public issue. cmd_report empties
  # them inside the capture; this is that, asserted with a sentinel rather than
  # a real escape (haus.sh may not contain one, and neither may its tests).
  haus_sh 'C_OK=XCOLORX; C_FOG=XCOLORX; C_OFF=XCOLORX; cmd_report --print'
  [[ "$output" != *XCOLORX* ]] || fail "the palette leaked into the block: $output"
}

# ---- the length cap ----------------------------------------------------------

@test "an oversized block drops the prefill rather than opening a broken link" {
  # GitHub refuses a long URL — and for a signed-OUT reporter the login redirect
  # it is bounced through breaks first, with a 500. Better an empty field the
  # reporter is told about than a link that errors.
  haus_sh DOCTOR="$(printf 'x%.0s' {1..9000})" 'cmd_report --print'
  [ "$(url)" = "https://github.com/hausfold/haus/issues/new?template=bug.yml" ] \
    || fail "the prefill survived the cap: $(url)"
  [[ "$output" == *"too long to prefill"* ]] || fail "it said nothing: $output"
}

@test "a block that fits is not truncated" {
  haus_sh 'cmd_report --print'
  [[ "$(url)" == *diagnostics=* ]] || fail "dropped a prefill that fit: $(url)"
  [[ "$output" != *"too long"* ]] || fail "claimed an overflow that did not happen"
}

@test "--print never touches the pasteboard, overflowing or not" {
  # `haus report --print | pbcopy` must not find the clipboard already taken by
  # a copy it never asked for.
  haus_sh DOCTOR="$(printf 'x%.0s' {1..9000})" 'cmd_report --print'
  [ ! -e "$COPIED" ] || fail "it wrote the clipboard anyway: $(cat "$COPIED")"
  [ ! -e "$NOTIFIED" ] || fail "it drew a banner: $(cat "$NOTIFIED")"
}

@test "the palette row gets the block on the clipboard, and is told so" {
  # No terminal, no stdout anyone will read, and a browser about to open on a
  # form whose diagnostics field is empty. The banner is the only way the person
  # learns there is something to paste.
  haus_sh DOCTOR="$(printf 'x%.0s' {1..9000})" 'cmd_report'
  [ "$status" -eq 0 ] || fail "$output"
  [ -s "$COPIED" ] || fail "nothing on the clipboard"
  grep -q 'xxxx' "$COPIED" || fail "the clipboard did not get the block"
  grep -q -- '--source haus.report' "$NOTIFIED" || fail "no banner: $(cat "$NOTIFIED" 2>/dev/null)"
  # The kind is the difference between arriving and not: under a Focus, trill's
  # standard policy banners `fault` and files everything else in the inbox, so a
  # `note` here would be silently filed on the machine most likely to be in one.
  grep -q -- '--kind fault' "$NOTIFIED" || fail "the banner is filable: $(cat "$NOTIFIED")"
}

@test "the clipboard write is gated on BOTH streams" {
  # `haus report >out.txt` from a terminal leaves fd 2 in front of a person, so
  # a clipboard they did not ask for is a clipboard we took. This suite has no
  # pty to prove that with (bats hands `run` two pipes), so the decision is
  # pinned where it is written — the same way phase-painter.bats pins the
  # REPORT arm of the dispatch.
  grep -qF 'if [ -t 1 ] || [ -t 2 ] || [ -n "$quiet" ]; then' "$SUBJECT" \
    || fail "the overflow branch no longer asks about both streams"
}

# ---- opening, and not opening ------------------------------------------------

@test "a plain run opens exactly the link it printed" {
  haus_sh 'cmd_report'
  [ "$status" -eq 0 ] || fail "$output"
  [ "$(cat "$OPENED")" = "$(url)" ] || fail "opened $(cat "$OPENED"), printed $(url)"
}

@test "--print opens nothing" {
  haus_sh 'cmd_report --print'
  [ ! -e "$OPENED" ] || fail "it opened $(cat "$OPENED")"
}

@test "an unknown flag is refused, on stderr, with nothing on stdout" {
  # One spelling. A report command draws on fd 1; an error is not part of a
  # report and stays on fd 2 (the note by the verbs in haus.sh).
  haus_sh 'cmd_report --json 2>/dev/null'
  [ "$status" -eq 1 ] || fail "accepted --json"
  [ -z "$output" ] || fail "the refusal landed on stdout: $output"
}

# ---- the palette row ---------------------------------------------------------

@test "the verb is discoverable: help, and zsh completion" {
  # A door nobody can find is the same as no door. haus-completion.zsh's own
  # header says "an arm missing here is a command nobody discovers", and nothing
  # in CI checks that list against the dispatch — so at least this arm is pinned
  # from the side that cares.
  grep -q "^  haus report " "$SUBJECT" || fail "haus --help does not list report"
  grep -q "^    'report:" "$BATS_TEST_DIRNAME/../modules/core/haus-completion.zsh" \
    || fail "zsh completion does not offer report"
}

@test "the palette row is one exec into the verb, by absolute path" {
  # pounce's daemon inherits launchd's bare PATH, so a bare `haus` there is a
  # row that does nothing. And the row must not grow a second URL of its own:
  # the last time it had one, every report it filed for a year was shapeless.
  local row="$BATS_TEST_DIRNAME/../modules/launcher/commands/report-issue-haus.sh"
  grep -q '^exec /run/current-system/sw/bin/haus report$' "$row" \
    || fail "the row no longer execs the verb: $(grep -v '^#' "$row")"
  grep -vE '^\s*#|^\s*$' "$row" | grep -q 'github.com' \
    && fail "the row builds a URL again"
  return 0
}
