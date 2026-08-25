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

# `root`, not `repo`: the offline section below reassigns `repo` to a throwaway
# git+file:// SOURCE, and anything after it reaching for the checkout would get
# a flakeref instead — silently, since both are strings a `nix build` will try.
root="$(cd "$(dirname "$0")/.." && pwd)"

# The built wrapper, which is what `nix run …#show` gives a stranger. Overridable
# so a local run can point at a copy it already built and skip the ~10s.
if [ -z "${HAUS_SHOW_BIN:-}" ]; then
  HAUS_SHOW_BIN="$(nix build --no-link --print-out-paths "$root#show")/bin/haus-show"
fi
show="$HAUS_SHOW_BIN"
# The checker directory itself, for the two sections that need the files inside
# it rather than the command in front of them: the symlink regression below, and
# the stand-in consumer, which borrows the nixpkgs `lib` staged in it rather than
# fetching one.
check="$(nix build --no-link --print-out-paths "$root#desktop-check")/share/haus/desktop-check"
[ -x "$show" ] || { printf 'FAIL: no haus-show at %s\n' "$show" >&2; exit 1; }

fixtures="$root/test/desktops"
tmp="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT

# Pointed at nothing, on purpose. `show` compares a passing desktop against the
# machine it is run on, so without this every assertion below would depend on
# whatever haus config the person running the suite happens to have — green on
# their Mac, green on CI (which has none), and answering a different question in
# each place. The step C section further down points it at a stand-in it builds.
export HAUS_CONSUMER="$tmp/there-is-no-config-here"

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
has "10 options across 6 rooms" "valid desktop"
has "haus.terminal.editorName" "valid desktop"
# Filed under the ROOM a person meets, not the namespace they type. This is the
# one thing the report adds over `checkDesktop` printing `true`.
has "Development" "valid desktop"
has "Shared surfaces" "valid desktop"
# And what stays theirs.
has "Apps · Appearance" "valid desktop"

# ---- 1a: the grammar this checker reaches OUT of itself for --------------------
# `haus.launcher.items` is the one desktop-safe container whose key rule is not
# spelled in modules/lib/desktop.nix: it is read from the launcher room's mirror
# of pounce's address space (modules/launcher/item-grammar.nix), one directory
# over. `haus show` runs the CHECKER OUT OF THE STORE, flattened into a single
# directory by modules/desktop-check.nix, so that reach has to be staged as well
# as work in the checkout.
#
# Nothing above catches it. Nix is lazy: the grammar is forced only by a file
# that actually sets `haus.launcher.items`, so every flake check, every other
# fixture and every desktop that leaves the palette alone stay green while the
# command dies on exactly the desktops the grammar exists to admit. That is a
# publisher's first command failing on their file and nobody else's.
cat > "$tmp/palette-rows.nix" <<'PALETTE'
{
  haus.launcher.items."mode:filesearch".alias = "ff";
}
PALETTE
run "$tmp/palette-rows.nix"
expect_status 0 "palette rows"
has "a desktop — data only" "palette rows"
has "haus.launcher.items.mode:filesearch.alias" "palette rows"

# And the refusing half of the same reach, so a staging that silently returned
# an empty grammar could not pass by accepting everything.
cat > "$tmp/palette-shortcut.nix" <<'PALETTE'
{
  haus.launcher.items."shortcut:0ECC8F7A-3A52-467A-84C0-511CCE1CB9B7".alias = "s";
}
PALETTE
run "$tmp/palette-shortcut.nix"
expect_status 1 "palette shortcut"
has "one entry in one Mac's Shortcuts library" "palette shortcut"

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
has "10 options across 6 rooms" "repo source"

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
  and (.sets | length) == 10
  and (.rooms | map(.room)) == ["displays","development","bar","launcher","focus","haus"]
  and (.silent | length) == 8
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

# ---- the checker's own path is resolved, not just the subject's ---------------
# On a machine the checker is `/run/current-system/sw/share/haus/desktop-check`,
# which is TWO symlinks away from where it really is. `restrict-eval` judges the
# resolved path, so allowing the logical spelling on `-I` while interpolating it
# into the expression refused every single invocation — local source and remote
# alike — with "access to absolute path '/private/var/run/…/read.nix' is
# forbidden in restricted mode".
#
# Nothing here could see it: the packaged wrapper bakes a STORE path, which has
# no symlink in it to resolve. So the regression is pinned by handing the
# command a symlink on purpose, which is a thing every platform has.
ln -s "$check" "$tmp/link-to-check"
# Exported and unset around the call rather than prefixed to it: `run` is a
# shell FUNCTION, and whether a prefixed assignment survives one depends on
# whether bash is in POSIX mode.
export HAUS_DESKTOP_CHECK="$tmp/link-to-check"
run "$fixtures/valid-sample.nix"
unset HAUS_DESKTOP_CHECK
expect_status 0 "symlinked checker"
has "a desktop — data only" "symlinked checker"

# ---- step C: what this machine becomes ---------------------------------------
# Every run above this point had HAUS_CONSUMER pointed at a directory that does
# not exist, which is not tidiness: without it the suite reads whatever haus
# config the developer running it happens to have, so the same command answers
# differently on two machines and CI is the only place it is hermetic. The
# section below points it at a stand-in built here instead.
#
# The stand-in is a flake whose `darwinConfigurations.testbox` is a plain
# `lib.evalModules` result with a `pkgs.lib` bolted on — NOT a nix-darwin
# system. That is deliberate and it is what the query's contract actually is:
# `pkgs.lib`, `options`, `config`, and `config.haus._desktop.sources`. Four
# attributes, all of which a real darwinConfiguration has, none of which needs a
# Mac, a nixpkgs fetch or a build. It makes the verdicts assertable on the Linux
# runner in about a second; what it cannot catch is nix-darwin changing the
# shape of those four, which is what running the real thing on a Mac is for.
#
# nixpkgs' lib is copied out of the built checker rather than fetched, so this
# stays offline like everything above it.
consumer="$tmp/testbox"
mkdir -p "$consumer"
cp -R "$check/lib" "$consumer/lib"
chmod -R u+w "$consumer/lib"

# The desktop this stand-in machine "has". Read by the query itself, so its
# leaves are what the report calls "turns off" when the candidate drops them.
cat >"$consumer/current-desktop.nix" <<'NIX'
{
  haus = {
    bar.enable = true;
    terminal.editorName = "helix";
    launcher.autoQuit.exclude = [ "from-the-old-one" ];
    displays.internal.uiScale = "default";
    # Set here and NOT by the candidate, so it is the drop case.
    ui.scale = 1.0;
  };
}
NIX

cat >"$consumer/flake.nix" <<'NIX'
{
  description = "a stand-in for a haus machine — options, config and pkgs.lib";
  outputs =
    { self }:
    let
      lib = import ./lib;
      declare = { lib, ... }: {
        _file = "TESTBOX-OPTIONS";
        options.haus = {
          _desktop.sources = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
          };
          ui.scale = lib.mkOption { type = lib.types.float; default = 1.0; };
          bar.enable = lib.mkOption { type = lib.types.bool; default = false; };
          terminal.editorName = lib.mkOption { type = lib.types.str; default = "nano"; };
          launcher.autoQuit.exclude = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
          };
          displays = lib.mkOption {
            default = { };
            type = lib.types.attrsOf (lib.types.submodule {
              options.uiScale = lib.mkOption { type = lib.types.str; default = "default"; };
            });
          };
          focus.scenes = lib.mkOption {
            default = { };
            type = lib.types.attrsOf (lib.types.submodule {
              options.description = lib.mkOption { type = lib.types.str; default = ""; };
              options.preventSleep = lib.mkOption { type = lib.types.bool; default = false; };
            });
          };
        };
      };
      # A plain line in the host file: priority 100, which outranks any desktop.
      host = {
        _file = "TESTBOX-HOST";
        haus.ui.scale = 2.5;
      };
      # The desktop seam: every leaf at 900, plus the record of which file it was.
      desktop =
        { lib, ... }:
        {
          _file = "TESTBOX-DESKTOP";
          haus = {
            bar.enable = lib.mkOverride 900 true;
            terminal.editorName = lib.mkOverride 900 "helix";
            launcher.autoQuit.exclude = lib.mkOverride 900 [ "from-the-old-one" ];
            displays.internal.uiScale = lib.mkOverride 900 "default";
            ui.scale = lib.mkOverride 900 1.0;
            _desktop.sources = [ (toString ./current-desktop.nix) ];
          };
        };
      evaluated = lib.evalModules { modules = [ declare host desktop ]; };
    in
    {
      darwinConfigurations.testbox = evaluated // { pkgs = { inherit lib; }; };
    };
}
NIX

# The candidate. Every leaf here is a real haus option (the checker runs against
# the REAL registry, not the stand-in's), and each one is a different verdict.
cat >"$tmp/becomes.nix" <<'NIX'
{
  haus = {
    ui.scale = 1.35;                                  # the host outranks it
    bar.enable = true;                                # already true
    terminal.editorName = "neovim";                   # changes
    launcher.autoQuit.exclude = [ "a" "b" ];          # changes, and a LIST
    displays.internal.uiScale = "larger-text";        # inside a container
    focus.scenes.presenting.preventSleep = true;      # inside a container, unset today
    bar.widgets.cpu.interval = 10;                    # the stand-in never declared it
  };
}
NIX

export HAUS_CONSUMER="$consumer"
run --json "$tmp/becomes.nix"
expect_status 0 "becomes"
printf '%s' "$out" | jq -e '
  (.machine.leaves | map({ key: .path, value: .verdict }) | from_entries) as $v
  | .machine.host == "testbox"
  and .machine.desktop == "current-desktop.nix"
  # The line a reader can get from neither file: your own config outranks a
  # desktop, so this one does not move whatever it says.
  and $v["haus.ui.scale"] == "overridden"
  and $v["haus.bar.enable"] == "unchanged"
  and $v["haus.terminal.editorName"] == "changes"
  and $v["haus.launcher.autoQuit.exclude"] == "changes"
  # No option node to rank, so the values compare and the winner does not.
  and $v["haus.displays.internal.uiScale"] == "unranked"
  and $v["haus.focus.scenes.presenting.preventSleep"] == "unranked"
  # A leaf this machine has never heard of is a VERSION gap, not a bad desktop:
  # it passed the checker, which read the registry this pin ships.
  and $v["haus.bar.widgets.cpu.interval"] == "unknown"
' >/dev/null || fail "becomes: verdicts are not the documented shape"

# Values on both sides, rendered by the same printer, and the container leaf
# that is simply not set here says so rather than inventing a current value.
printf '%s' "$out" | jq -e '
  (.machine.leaves | map({ key: .path, value: . }) | from_entries) as $l
  | $l["haus.ui.scale"].current == "2.5"
  and $l["haus.ui.scale"].proposed == "1.35"
  and $l["haus.terminal.editorName"].current == "\"helix\""
  and $l["haus.launcher.autoQuit.exclude"].type == "listOf"
  and $l["haus.displays.internal.uiScale"].inside == "haus.displays"
  and $l["haus.focus.scenes.presenting.preventSleep"].current == null
' >/dev/null || fail "becomes: values/type/inside are not the documented shape"

# What stops being set, with the value it is leaving — and NOT with the value it
# lands on, which the module system does not keep: only the winning definition
# survives, so the room default under the current desktop is not in the tree.
printf '%s' "$out" | jq -e '
  (.machine.drops | map(.path)) == ["haus.ui.scale"] | not
' >/dev/null || fail "becomes: a leaf the candidate also sets must not be a drop"

# The human rendering says the two things the JSON cannot: the list warning and
# the reason a container leaf has no verdict about who wins.
run "$tmp/becomes.nix"
expect_status 0 "becomes rendering"
has "your own config outranks" "becomes rendering"
has "replaced whole, not merged" "becomes rendering"
has "inside haus.displays" "becomes rendering"
has "never heard of" "becomes rendering"
has "not a rebuild preview" "becomes rendering"

# --no-diff, and a machine with no config at all: both are silence, not a
# failure. A publisher's CI is the second case and must never see a word of it.
run --no-diff --json "$tmp/becomes.nix"
expect_status 0 "no-diff"
printf '%s' "$out" | jq -e '.machine == null' >/dev/null || fail "no-diff: machine should be null"
unset HAUS_CONSUMER
export HAUS_CONSUMER="$tmp/there-is-no-config-here"
run --json "$tmp/becomes.nix"
expect_status 0 "no consumer"
printf '%s' "$out" | jq -e '.machine == null' >/dev/null || fail "no consumer: machine should be null"

# A lock that would have to change is a REFUSAL, not a silently recomputed
# answer — and the refusal does not touch the exit code, because that code is
# the publisher's contract and their CI has no machine.
export HAUS_CONSUMER="$consumer"
lockprint() { find "$consumer" -maxdepth 1 -type f -exec cksum {} + | sort; }
before="$(lockprint)"
run "$tmp/becomes.nix"
expect_status 0 "writes nothing"
[ "$before" = "$(lockprint)" ] || fail "writes nothing: show changed the consumer's flake directory"

# A FAILING desktop gets no diff at all: its leaf names are names the registry
# has not vouched for, and "what would this become" is not the answer to "this
# is not a desktop".
run --json "$fixtures/unknown-option.nix"
expect_status 1 "failing gets no diff"
printf '%s' "$out" | jq -e '.machine == null' >/dev/null || fail "failing gets no diff"
unset HAUS_CONSUMER
export HAUS_CONSUMER="$tmp/there-is-no-config-here"

# ---- --help --------------------------------------------------------------------
run --help
expect_status 0 "help"
has "exit codes" "help"
has "never infers that something is safe" "help"
has "two acts" "help"
has "unreadable" "help"

printf 'ok — haus show: %s\n' "$show"
