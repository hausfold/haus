#!/usr/bin/env bash
# `haus show`'s own suite — the half the `desktop-show` flake check cannot run.
#
# That check pins the READING (class, counts, which room each leaf files under)
# and it is pure lib, so it runs inside a Nix build. Everything this command
# actually IS lives outside one: the script shells out to `nix eval`, which no
# derivation may do, and its whole contract with a publisher's CI is an EXIT
# CODE. So the exit codes, the flags and the JSON envelope are pinned here, run
# from CI's eval job, where a real nix exists.
#
# Runs on Linux: nothing about the desktop rules is a Mac, and a publisher's
# runner isn't one either — which is the case this command exists to serve.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"

# The built wrapper, which is what `nix run …#show` gives a stranger. Overridable
# so a local run can point at a copy it already built and skip the ~10s.
if [ -z "${HAUS_SHOW_BIN:-}" ]; then
  HAUS_SHOW_BIN="$(nix build --no-link --print-out-paths "$repo#show")/bin/haus-show"
fi
show="$HAUS_SHOW_BIN"
[ -x "$show" ] || { printf 'FAIL: no haus-show at %s\n' "$show" >&2; exit 1; }

fixtures="$repo/test/desktops"
tmp="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# Run it and capture all three: stdout, stderr and the status. `set +e` around
# the call only — the status IS the assertion here, so it must never be the
# thing that aborts the suite.
out="" err="" status=0
run() {
  set +e
  out="$("$show" "$@" 2>"$tmp/err")"
  status=$?
  set -e
  err="$(cat "$tmp/err")"
}

expect_status() { [ "$status" = "$1" ] || fail "$2: expected exit $1, got $status"; }
has()   { printf '%s\n' "$out" | grep -qF -- "$1" || fail "$2: expected to find '$1' on stdout"; }
# Diagnostics go to stderr, so a refusal is asserted there and never on stdout.
has_err() { printf '%s\n' "$err" | grep -qF -- "$1" || fail "$2: expected to find '$1' on stderr"; }
lacks() { printf '%s\n' "$out" | grep -qF -- "$1" && fail "$2: expected NOT to find '$1'"; return 0; }

# ---- 0: a valid desktop passes, and says what it sets -------------------------
run "$fixtures/valid-sample.nix"
expect_status 0 "valid desktop"
has "a desktop — data only" "valid desktop"
has "9 options across 6 rooms" "valid desktop"
has "haus.terminal.editorName" "valid desktop"
# Filed under the ROOM a person meets, not the namespace they type. This is the
# one thing the report adds over `checkDesktop` printing `true`.
has "Development" "valid desktop"
has "Shared surfaces" "valid desktop"
# And what stays theirs.
has "Apps · Appearance" "valid desktop"

# ---- 1: a desktop that breaks a rule fails, naming every rule -----------------
run "$fixtures/host-only-secret.nix"
expect_status 1 "host-only desktop"
has "not a desktop" "host-only desktop"
has "2 rules broken" "host-only desktop"
has "haus.secrets.provider is host-only" "host-only desktop"
# The checker prefixes every diagnostic with the file it came from, which is
# right inside a flake check over a directory and noise in a one-file report.
lacks "$fixtures/host-only-secret.nix: haus" "host-only desktop"

# One rule, so the count is not silently plural.
run "$fixtures/unknown-option.nix"
expect_status 1 "unknown option"
has "1 rule broken" "unknown option"

# ---- 3: code, unclaimed — the asymmetry ---------------------------------------
# A module function is reported as code without being asked, because guessing
# "this is code" can only ever be over-cautious. It is NOT a pass: a publisher's
# CI must go red the day their desktop file becomes a function.
run "$fixtures/function.nix"
expect_status 3 "unclaimed room"
has "this is CODE" "unclaimed room"
has "run activation scripts as root" "unclaimed room"
lacks "✓" "unclaimed room"

# Claimed, it is the answer you asked for.
run --room "$fixtures/function.nix"
expect_status 0 "claimed room"
has "this is CODE" "claimed room"

# --room on a DATA file is still a room: a desktop-shaped attrset is a perfectly
# good module, so the flag is a statement about how the file will arrive, and
# nothing is checked when it is given. Never the other way round — no content
# makes haus call something data.
run --room "$fixtures/valid-sample.nix"
expect_status 0 "data claimed as room"
has "this is CODE" "data claimed as room"
lacks "every leaf it sets" "data claimed as room"

# ---- 2: the arguments, and the file ------------------------------------------
run "$tmp/nope.nix"
expect_status 2 "missing file"
printf '%s\n' "$err" | grep -qF "no such file" || fail "missing file: reason not on stderr"

run "$fixtures"
expect_status 2 "a directory"

run --nonsense "$fixtures/valid-sample.nix"
expect_status 2 "unknown flag"

run
expect_status 2 "no argument"

# A file that is not Nix at all.
printf 'this is not nix {{{\n' >"$tmp/broken.nix"
run "$tmp/broken.nix"
expect_status 2 "unparseable"

# A file that parses and then throws. `tryEval` catches this one; a TYPE error
# it would not, which is why the reader tests a value's type before touching it.
printf '{ haus.ui.scale = throw "boom"; }\n' >"$tmp/throws.nix"
run "$tmp/throws.nix"
expect_status 2 "throwing value"
has "could not be read" "throwing value"

# A file that is valid Nix and fails for a reason that is NOT a parse error.
# Every one of these used to be reported as "check it parses", which sends the
# reader to look at the one thing that is fine.
printf '{ haus.apps.extra = (import <nixpkgs> { }).hello; }\n' >"$tmp/needs-nixpkgs.nix"
run "$tmp/needs-nixpkgs.nix"
expect_status 2 "not a parse error"
has "Nix says" "not a parse error"

# ---- the sandbox --------------------------------------------------------------
# Reading a file means evaluating it, and evaluation is not inert. Both of these
# must be REFUSED, and the refusal must say what was reached for — a `haus show`
# that exfiltrates during the run you did to decide whether to trust the file is
# the worst bug this command could have.
printf 'top secret\n' >"$tmp/creds"
printf '{ haus.theme.accent = builtins.readFile "%s/creds"; }\n' "$tmp" >"$tmp/reads.nix"
run "$tmp/reads.nix"
expect_status 2 "reads a sibling file"
lacks "top secret" "reads a sibling file"
printf '%s\n' "$err" | grep -qF "top secret" && fail "reads a sibling file: the secret reached stderr"
has_err "restricted mode" "reads a sibling file"

printf '{ haus.theme.accent = builtins.fetchurl "https://example.invalid/x"; }\n' >"$tmp/fetches.nix"
run "$tmp/fetches.nix"
expect_status 2 "fetches a URL"
has_err "restricted mode" "fetches a URL"

# And `--room` does not evaluate the file AT ALL, which is why the same hostile
# file comes back as a plain room rather than as a sandbox refusal. Declaring
# something to be code and then running it through an evaluator to say so would
# be the one thing this command must not do to a stranger's file.
run --room "$tmp/reads.nix"
expect_status 0 "--room does not evaluate"
lacks "top secret" "--room does not evaluate"

# The checker's own directory has to stay readable, or the sandbox refuses
# everything — including the desktops that are fine. Proven by the valid case
# passing above, and again here on a file in the same directory as the two
# hostile ones, so it is the FILE that is scoped and not the directory.
printf '{ haus.theme.accent = "mauve"; }\n' >"$tmp/fine.nix"
run "$tmp/fine.nix"
expect_status 0 "a good file beside a hostile one"

# A path a naive splice would break, with the two characters that matter: a
# quote closes the Nix string, and `${` opens an interpolation inside it.
mkdir -p "$tmp/od\"d \${x}"
cp "$tmp/fine.nix" "$tmp/od\"d \${x}/desk.nix"
run "$tmp/od\"d \${x}/desk.nix"
expect_status 0 "awkward path"

# ---- the report is a surface too ----------------------------------------------
# `toJSON` escapes quotes, backslashes and the three whitespace controls and
# NOTHING else, so ESC survives a desktop's own values all the way to the
# terminal. `sets` prints after the class line and after the broken-rule list,
# so a file that can move the cursor can repaint "not a desktop" as "a desktop
# - data only, and haus checked it". The exit code stays honest; the screen is
# what a person reads.
#
# Nix's '' strings do not treat a backslash as an escape, so the literal below
# reaches `fromJSON` as JSON and comes back as a real ESC byte.
cat >"$tmp/escape.nix" <<'NIX'
{ haus.focus.scenes.presenting.description = builtins.fromJSON ''"\u001b[7A\u001b[2Kowned"''; }
NIX
run "$tmp/escape.nix"
expect_status 0 "a value that moves the cursor"
printf '%s' "$out" | grep -q $'\033\[7A' && fail "a value that moves the cursor: raw ESC reached stdout"
# The text survives, stripped of the byte that made it a command - a reader
# still sees what the file said.
has "[7A" "a value that moves the cursor"

# ---- step B: a source, not a file ---------------------------------------------
# Everything below is OFFLINE. `git+file://` and `file+file://` are the same two
# fetchers `github:` and `file+https://` use, resolved against a throwaway repo
# in $tmp instead of over the network — so CI exercises the real fetch path
# without a network dependency that would make this suite flaky for a reason
# that has nothing to do with haus.
command -v git >/dev/null || fail "step B needs git"

gitc() { git -C "$1" -c user.email=t@haus -c user.name=test "${@:2}"; }
mkrepo() { mkdir -p "$tmp/$1"; git init -q -b main "$tmp/$1"; }
commit() { gitc "$tmp/$1" add -A; gitc "$tmp/$1" commit -qm "$2"; }

mkrepo writer
cp "$fixtures/valid-sample.nix" "$tmp/writer/writer.nix"
printf 'ada-private-notes\n' >"$tmp/writer/NOTES.txt"
commit writer one
repo="git+file://$tmp/writer?ref=main"

run "$repo"
expect_status 0 "repo source"
has "a desktop — data only" "repo source"
has "origin" "repo source"
# The revision is the source's, and so is the date beside it. `lastModified` on
# a git node is the COMMIT's timestamp, not a record of this fetch — measured —
# so the report says which of the two it is rather than leaving a reader to
# assume the friendlier one.
has "$(gitc "$tmp/writer" rev-parse HEAD)" "repo source"
has "the source's own date, not this fetch's" "repo source"
has "stamped here, by the clock" "repo source"
has "writer.nix, out of the fetched tree" "repo source"
has "9 options across 6 rooms" "repo source"

# Reading a fetched desktop is where attribution stops being per-file, so the
# report has to say so — see the granularity assertions below.
has "attributed to the fetched TREE" "repo source"

# ---- which file, when a repo holds more than one ------------------------------
cp "$fixtures/valid-sample.nix" "$tmp/writer/second.nix"
commit writer two

run "$repo"
expect_status 2 "ambiguous repo"
has_err "name one with --file" "ambiguous repo"
has_err "second.nix" "ambiguous repo"
has_err "writer.nix" "ambiguous repo"

run --file second.nix "$repo"
expect_status 0 "--file picks one"
has "second.nix, out of the fetched tree" "--file picks one"

run --file nope.nix "$repo"
expect_status 2 "--file names nothing"

# `..` is refused rather than resolved. The guard below ALLOWS the path it is
# handed, so an escaping --file would not sneak past the sandbox so much as ask
# to have the escape allowed.
run --file ../../etc/passwd "$repo"
expect_status 2 "--file may not escape"
has_err "stay inside the source" "--file may not escape"

# --file is about a fetched tree; there is nothing for it to mean locally.
run --file x.nix "$fixtures/valid-sample.nix"
expect_status 2 "--file on a local path"

# `--file` is refused in a room rather than ignored: nothing reads it, and a
# path that goes unvalidated because "nothing reads it anyway" is a guard
# waiting for the day something does.
run --room --file writer.nix "$repo"
expect_status 2 "--file with --room"

# ---- the raw-file shape, which can answer neither question --------------------
run "file+file://$tmp/writer/writer.nix"
expect_status 0 "raw file source"
has "no revision and no date of any kind" "raw file source"
has "the fetched file" "raw file source"
# The warning is about the UPDATE, not about the missing changelog: nix prints
# the same URL on both sides of its arrow while the content moves underneath.
has "same URL on both sides" "raw file source"
lacks "the source's own date" "raw file source"

# A directory source with no revision is a `tree`, not a `file`. Labelling it
# `file` printed the raw-URL warning ("can only be re-downloaded") over a whole
# directory, and `shape` is a documented JSON key a consumer branches on.
mkdir -p "$tmp/plain"
cp "$fixtures/valid-sample.nix" "$tmp/plain/only.nix"
run --json "path:$tmp/plain"
expect_status 0 "a path: source"
printf '%s' "$out" | jq -e '.origin.shape == "tree" and .origin.rev == null' >/dev/null \
  || fail "a path: source: a directory with no rev is not a file"
run "path:$tmp/plain"
expect_status 0 "a path: source, rendered"
lacks "can only be re-downloaded" "a path: source, rendered"

# ---- the guard, at store granularity ------------------------------------------
# Step A's rule — one file allowed, never its parent — is exactly right outside
# the store and does not survive a fetch: restrict-eval's unit is the STORE
# PATH. These two rows pin both halves, because a guard believed to be tighter
# than it is is what a later step would build on.
mkrepo hostile
cat >"$tmp/hostile/sibling.nix" <<'NIX'
{ haus.theme.accent = builtins.readFile ./ACCENT; }
NIX
printf 'mauve' >"$tmp/hostile/ACCENT"
cat >"$tmp/hostile/outside.nix" <<'NIX'
{ haus.theme.accent = builtins.readFile /etc/hostname; }
NIX
commit hostile h
hostile="git+file://$tmp/hostile?ref=main"

# ALLOWED, and deliberately: what it opens is the publisher's own tree.
run --file sibling.nix "$hostile"
expect_status 0 "a fetched desktop reads its own sibling"
has "mauve" "a fetched desktop reads its own sibling"

# BLOCKED, which is the half that was load-bearing: nothing outside the store.
run --file outside.nix "$hostile"
expect_status 2 "a fetched desktop reaches outside the store"
has_err "/etc/hostname" "a fetched desktop reaches outside the store"
has_err "restricted mode" "a fetched desktop reaches outside the store"

# ---- fetch and read are two acts ----------------------------------------------
# `show` FETCHES a tree; it never locks. Locking a source that is a flake
# evaluates its flake.nix to find its own inputs — measured — so a command that
# locked would run a stranger's code before printing a word about it. This repo
# throws from `inputs`, so the marker below appears if that ever regresses.
mkrepo aroom
cat >"$tmp/aroom/flake.nix" <<'NIX'
{ inputs.nixpkgs.url = builtins.throw "PUBLISHER-CODE-RAN"; outputs = { ... }: { }; }
NIX
cat >"$tmp/aroom/photo.nix" <<'NIX'
{ lib, ... }: { }
NIX
commit aroom r

run --room "git+file://$tmp/aroom?ref=main"
expect_status 0 "a remote room"
has "this is CODE" "a remote room"
has "Fetched, not locked" "a remote room"
# Nothing was read, and the report does not guess which file WOULD have been.
has "nothing was evaluated" "a remote room"
lacks "PUBLISHER-CODE-RAN" "a remote room"
printf '%s\n' "$err" | grep -qF "PUBLISHER-CODE-RAN" && fail "a remote room: its flake.nix was evaluated"

# ---- the errors a fetch produces ----------------------------------------------
# A bare https URL is a TARBALL flakeref to Nix, so pointing one at a .nix fails
# with "Unrecognized archive format" — a message that says nothing about the
# prefix that is missing. Refused with the spellings, and never rewritten: the
# string typed here is the string `haus add` will write into flake.nix.
run https://example.org/writer.nix
expect_status 2 "bare url"
has_err "file+https://example.org/writer.nix" "bare url"
has_err "git+https://example.org/writer.nix" "bare url"

# A source that cannot be fetched reports Nix's own SENTENCE. Step A took the
# last non-blank line of stderr, which is right for a parse error and wrong for
# a fetch: Nix prints its message and then appends the server's response body
# under it, so a 404 came back as `}`. The message is the last `error:` line
# now, with any response body cut off first.
run "git+file://$tmp/definitely-not-a-repo?ref=main"
expect_status 2 "unfetchable source"
has_err "could not fetch" "unfetchable source"
printf '%s\n' "$err" | grep -qE 'does not exist|No such file' \
  || fail "unfetchable source: the reason is not Nix's sentence"

# An explicit path spelling is a path even when it does not exist — a mistyped
# ./file must not turn into a fetch attempt.
run ./definitely-not-here.nix
expect_status 2 "a mistyped local path"
has_err "no such file" "a mistyped local path"

# ---- B's exit gate: the consumer is not touched -------------------------------
# Not "we didn't mean to" — measured, from inside a directory that HAS a
# consumer flake, which is where someone would actually run this.
mkdir -p "$tmp/consumer"
printf '{ inputs = { }; outputs = { ... }: { }; }\n' >"$tmp/consumer/flake.nix"
consumer_before="$(find "$tmp/consumer" -type f -exec cksum {} + | sort)"
(cd "$tmp/consumer" && "$show" "$repo" --file writer.nix >/dev/null 2>&1) || \
  fail "consumer untouched: show failed from a consumer directory"
consumer_after="$(find "$tmp/consumer" -type f -exec cksum {} + | sort)"
[ "$consumer_before" = "$consumer_after" ] || fail "show wrote into the consumer's config"
[ -e "$tmp/consumer/flake.lock" ] && fail "show locked the consumer's flake"

# ---- --json -------------------------------------------------------------------
run --json "$fixtures/valid-sample.nix"
expect_status 0 "json valid"
printf '%s' "$out" | jq -e '
  .schemaVersion == 1
  and .class == "desktop"
  and .checked == true
  and .ok == true
  and (.sets | length) == 9
  and (.rooms | map(.room)) == ["displays","development","bar","launcher","focus","haus"]
  and (.silent | length) == 7
' >/dev/null || fail "json valid: envelope is not the documented shape"
# Data on stdout, diagnostics on stderr, and NO human rendering mixed in.
lacks "🌫" "json valid"
[ -z "$err" ] || fail "json valid: stderr should be empty, got '$err'"

# `origin` is null for a local file and an object for a source, and the schema
# version did NOT move for it: a bump is owed when an existing input's answer
# changes, and every input schemaVersion 1 could accept still gets exactly the
# answer it got before.
printf '%s' "$out" | jq -e '.origin == null' >/dev/null || fail "json valid: a local file has no origin"

run --json "$repo" --file writer.nix
expect_status 0 "json remote"
printf '%s' "$out" | jq -e '
  .schemaVersion == 1
  and .origin.shape == "repo"
  and .origin.file == "writer.nix"
  and (.origin.rev | length) == 40
  and (.origin.lastModified | type) == "number"
  and (.origin.fetchedAt >= .origin.lastModified)
  and (.origin.tree | startswith("/nix/store/"))
  and .file == (.origin.tree + "/writer.nix")
' >/dev/null || fail "json remote: origin is not the documented shape"
[ -z "$err" ] || fail "json remote: stderr should be empty, got '$err'"

run --json "file+file://$tmp/writer/writer.nix"
expect_status 0 "json raw file"
printf '%s' "$out" | jq -e '
  .origin.shape == "file" and .origin.rev == null
  and .origin.lastModified == null and .origin.file == null
  and (.origin.narHash | startswith("sha256-"))
' >/dev/null || fail "json raw file: the shape that can answer neither question"

run --json "$fixtures/unknown-option.nix"
expect_status 1 "json failing"
printf '%s' "$out" | jq -e '.ok == false and (.failures | length) == 1' >/dev/null \
  || fail "json failing: failures not reported"

# `checked` is said out loud rather than inferred from an empty failure list,
# because a room and a clean desktop otherwise look identical in JSON — which is
# the one confusion this command must never cause.
run --json --room "$fixtures/function.nix"
expect_status 0 "json room"
printf '%s' "$out" | jq -e '.class == "room" and .checked == false and .ok == null' >/dev/null \
  || fail "json room: a room must not read as a checked pass"

# The same rule for a file nothing could be read from: `ok` is null, never true,
# and the reason survives into `failures` rather than being thrown away with the
# exit code as the only evidence.
run --json "$tmp/throws.nix"
expect_status 2 "json unreadable"
printf '%s' "$out" | jq -e '
  .class == "unreadable" and .checked == false and .ok == null
  and (.failures | length) >= 1
  and (.failures | join(" ") | test("boom"))
' >/dev/null || fail "json unreadable: ok/failures are not the documented shape"

# ---- it really does write nothing --------------------------------------------
# `cksum` rather than md5sum/md5, whose names differ by platform — and content,
# not just the file list, because the failure worth catching is a checker that
# rewrites what it read.
snapshot() { find "$fixtures" -type f -exec cksum {} + | sort; }
before="$(snapshot)"
run "$fixtures/valid-sample.nix"
after="$(snapshot)"
[ "$before" = "$after" ] || fail "show changed the directory it read"

# ---- --help --------------------------------------------------------------------
run --help
expect_status 0 "help"
has "exit codes" "help"
has "never infers that something is safe" "help"
has "two acts" "help"
has "unreadable" "help"

printf 'ok — haus show: %s\n' "$show"
