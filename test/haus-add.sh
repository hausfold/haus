#!/usr/bin/env bash
# `haus add` / `haus desktop` / `haus remove` / `haus update`'s own suite —
# acquisition step D. Needs a real `nix flake lock` and `nix eval` against a
# SCAFFOLDED consumer flake, which is exactly what `haus show`'s suite needs
# and exactly why this one runs the same way: `modules/core/haus.sh` run
# directly, under the interpreter resolved below (no derivation may shell out to
# `nix`), from the "eval the example host" job, where a real nix exists.
#
# Runs on Linux: none of this is a Mac — it edits a text file and asks Nix to
# resolve inputs. `haus rebuild` is never called; every write here stops one
# step short of it, on purpose, the same as the command it tests.
set -euo pipefail

# ── an interpreter that can actually run haus.sh ─────────────────────────────
# haus.sh is `#!/usr/bin/env bash` and is written for bash 4+ — the contract
# test/phase-painter.bats pins for every script that reaches the painter. A
# bare `bash` is not that: on a Mac it is /bin/bash 3.2, and the subject does
# not degrade under 3.2, it MIS-PARSES. `coproc` is no keyword there, so the
# `}` that closes `coproc SNUG { … }` inside snug_open closes the FUNCTION
# instead, and the lines meant to run inside it run at LOAD time — the first
# being `exec {SNUG_FD}>&"${SNUG[1]}"`, which under `set -u` kills the run
# before the suite has asserted anything. CI never saw it: those runners are
# Linux with bash 5, which is why this only ever bit someone running the suite
# by hand on a Mac.
#
# So the suite re-execs itself under a bash that can read the file, and hands
# that one on as `$BASH` to every `haus` it spawns. Only a candidate that
# ANSWERED 4+ is exec'd, so there is no loop to fall into, and no answer at all
# is a loud failure rather than a suite that skips itself quietly.
#
# The same block is in test/haus-settings.sh and test/haus-plan.sh, and
# test/awake-ui.bats makes the same call as `resolve_bash4`. Copies rather than
# a sourced helper — the size call AGENTS.md makes for the Ghostty pre-warm, and
# a suite that cannot bootstrap its own interpreter is a bad place to add a file
# it has to find first. test/phase-painter.bats pins the INVARIANT rather than
# the bytes, so a fourth suite that spawns the subject cannot opt out quietly.
if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
  for _bash in /run/current-system/sw/bin/bash /opt/homebrew/bin/bash \
               "$(command -v bash || true)" /bin/bash; do
    [ -n "$_bash" ] && [ -x "$_bash" ] || continue
    [ "$("$_bash" -c 'echo ${BASH_VERSINFO[0]}' 2>/dev/null || echo 0)" -ge 4 ] || continue
    exec "$_bash" "$0" "$@"
  done
  printf 'FAIL: haus.sh needs bash 4+ and this is %s — no newer one found\n' \
    "${BASH_VERSION:-?}" >&2
  exit 1
fi

root="$(cd "$(dirname "$0")/.." && pwd)"

# `haus add` shells out to the SAME `haus show` a stranger runs, and to
# `nixfmt` as a parser — neither is on a bare CI runner's PATH, so both are
# resolved the same way this suite resolves everything else: built, not
# assumed.
show="$(nix build --no-link --print-out-paths "$root#show")/bin/haus-show"
check="$(nix build --no-link --print-out-paths "$root#desktop-check")/share/haus/desktop-check"
nixfmt_bin="$(nix build --no-link --print-out-paths nixpkgs#nixfmt)/bin"
export PATH="$nixfmt_bin:$PATH"
export HAUS_SHOW="$show"
export HAUS_DESKTOP_CHECK="$check"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
has()  { printf '%s\n' "$2" | grep -qF -- "$1" || fail "$3: expected to find '$1'"; }
lacks() { printf '%s\n' "$2" | grep -qF -- "$1" && fail "$3: expected NOT to find '$1'"; return 0; }

tmp="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT

# ---- a scratch third-party desktop, offline (git+file://) --------------------
mkdir -p "$tmp/writer"
git -C "$tmp/writer" init -q
printf '{ haus = { bar.enable = false; }; }\n' > "$tmp/writer/writer.nix"
git -C "$tmp/writer" add writer.nix
git -C "$tmp/writer" -c user.email=t@t -c user.name=t commit -q -m init
writer_rev="$(git -C "$tmp/writer" rev-parse HEAD)"

mkdir -p "$tmp/second"
git -C "$tmp/second" init -q
printf '{ haus = { windows.enable = false; }; }\n' > "$tmp/second/second.nix"
git -C "$tmp/second" add second.nix
git -C "$tmp/second" -c user.email=t@t -c user.name=t commit -q -m init

# A room source — a plain module function, not a `{ haus = …; }` value.
mkdir -p "$tmp/a-room"
git -C "$tmp/a-room" init -q
printf '{ pkgs, ... }: { environment.systemPackages = [ pkgs.hello ]; }\n' > "$tmp/a-room/default.nix"
git -C "$tmp/a-room" add default.nix
git -C "$tmp/a-room" -c user.email=t@t -c user.name=t commit -q -m init

# A real third-party ROOM — a flake with no inputs of its own, exposing
# darwinModules.default: a nix-darwin module under a namespace nothing else on
# the test machine declares, so `haus add --room` claiming it exercises the
# whole path (pin, wire into extraModules, claim the namespace) rather than
# just the flake.nix edit.
mkdir -p "$tmp/room-a"
git -C "$tmp/room-a" init -q
cat > "$tmp/room-a/flake.nix" <<'NIX'
{
  description = "room a";
  outputs = { self }: {
    darwinModules.default = { lib, ... }: {
      options.haus.testroom.enable = lib.mkEnableOption "a test room";
      config.haus.testroom.enable = true;
    };
  };
}
NIX
git -C "$tmp/room-a" add flake.nix
git -C "$tmp/room-a" -c user.email=t@t -c user.name=t commit -q -m init
room_a_rev="$(git -C "$tmp/room-a" rev-parse HEAD)"

# A second, distinct room claiming the SAME namespace under a different
# origin — the collision case needs one, since `haus remove` deliberately
# leaves a namespace claim behind rather than guessing which room it belonged
# to (see cmd_remove).
mkdir -p "$tmp/room-b"
git -C "$tmp/room-b" init -q
cat > "$tmp/room-b/flake.nix" <<'NIX'
{
  description = "room b";
  outputs = { self }: {
    darwinModules.default = { lib, ... }: {
      options.haus.testroom.enable = lib.mkEnableOption "a different test room";
      config.haus.testroom.enable = true;
    };
  };
}
NIX
git -C "$tmp/room-b" add flake.nix
git -C "$tmp/room-b" -c user.email=t@t -c user.name=t commit -q -m init
room_b_rev="$(git -C "$tmp/room-b" rev-parse HEAD)"

# A raw single file, not a flake at all — file+file:// is file+https://'s
# offline sibling, the same substitution haus-show.sh's own suite uses. For
# `--room` this has no revision, so it's the fixture for "haus cannot lock
# what it cannot pin as an input."
printf '{ pkgs, ... }: { environment.systemPackages = [ pkgs.hello ]; }\n' > "$tmp/raw-room.nix"

# ---- a scaffolded consumer, `haus` pinned locally (offline, `path:`) ---------
new_consumer() {
  rm -rf "$tmp/consumer"
  mkdir -p "$tmp/consumer/hosts/testbox"
  printf '{ }\n' > "$tmp/consumer/hosts/testbox/default.nix"
  cat > "$tmp/consumer/flake.nix" <<NIX
{
  description = "test machine";

  inputs.haus.url = "path:$root";

  outputs =
    { haus, ... }:
    {
      darwinConfigurations.testbox = haus.mkHaus {
        username = "tester";
        hostname = "testbox";
        host = ./hosts/testbox;
      };
    };
}
NIX
  ( cd "$tmp/consumer" && nix flake lock >/dev/null 2>&1 )
}
new_consumer
export HAUS_CONSUMER="$tmp/consumer"

haus() { "$BASH" "$root/modules/core/haus.sh" "$@"; }

# ---- 0: add pins, selects, and the value actually reaches the machine --------
out="$(haus add -y "git+file://$tmp/writer" 2>&1)"
has "pinned and selected" "$out" "add"
grep -qE '^  inputs\.writer\.url = "git\+file://'"$tmp"'/writer";$' "$tmp/consumer/flake.nix" \
  || fail "add: input line missing or malformed"
grep -qE '^    \{ haus, writer, \.\.\. \}:$' "$tmp/consumer/flake.nix" \
  || fail "add: outputs pattern not bound"
grep -qE '^        desktop = writer \+ "/writer\.nix";$' "$tmp/consumer/flake.nix" \
  || fail "add: desktop line not rewritten"
nixfmt - <"$tmp/consumer/flake.nix" >/dev/null || fail "add: flake.nix does not parse"
locked="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["nodes"]["writer"]["locked"]["rev"])' "$tmp/consumer/flake.lock")"
[ "$locked" = "$writer_rev" ] || fail "add: locked rev does not match the source"
# The claim `add` exists to make true: a stranger's desktop actually lands.
landed="$(cd "$tmp/consumer" && nix eval .#darwinConfigurations.testbox.config.haus.bar.enable)"
[ "$landed" = "false" ] || fail "add: haus.bar.enable did not land ($landed)"

# ---- 1: haus desktop lists built-ins + pinned, marks the selection -----------
out="$(haus desktop)"
has "hacker" "$out" "desktop listing"
has "writer" "$out" "desktop listing"
has "pinned" "$out" "desktop listing"

# ---- 2: switching to a built-in, then back to the pinned input ---------------
haus desktop hacker >/dev/null
grep -qE '^        desktop = haus\.desktops\.hacker;$' "$tmp/consumer/flake.nix" \
  || fail "desktop hacker: line not rewritten"
[ "$(grep -c '        desktop = ' "$tmp/consumer/flake.nix")" = 1 ] \
  || fail "desktop hacker: more than one desktop line"

haus desktop writer >/dev/null
grep -qE '^        desktop = writer \+ "/writer\.nix";$' "$tmp/consumer/flake.nix" \
  || fail "desktop writer: line not rewritten"
[ "$(grep -c '        desktop = ' "$tmp/consumer/flake.nix")" = 1 ] \
  || fail "desktop writer: more than one desktop line"
out="$(haus desktop)"
has $'\xe2\x86\x92' "$out" "desktop listing after switch"

# ---- 3: remove — the selected desktop gets an EXPLICIT replacement -----------
out="$(haus remove writer 2>&1)"
has "set to 'blank' instead" "$out" "remove"
grep -qE '^        desktop = haus\.desktops\.blank;$' "$tmp/consumer/flake.nix" \
  || fail "remove: desktop line not set to blank"
lacks "inputs.writer" "$(cat "$tmp/consumer/flake.nix")" "remove: input line still present"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(1 if "writer" in d["nodes"] else 0)' \
  "$tmp/consumer/flake.lock" || fail "remove: lock still carries the pruned node"

# ---- 4: a second pinned desktop degrades to --print, and touches nothing -----
new_consumer
haus add -y "git+file://$tmp/writer" >/dev/null 2>&1
before="$(cat "$tmp/consumer/flake.nix")"
out="$(haus add -y --as second "git+file://$tmp/second" 2>&1)"
has "add these by hand" "$out" "second add"
has "inputs.second.url" "$out" "second add"
after="$(cat "$tmp/consumer/flake.nix")"
[ "$before" = "$after" ] || fail "second add: flake.nix was touched on the degrade path"

# ---- 5: a name collision refuses rather than double-pinning ------------------
set +e
haus add -y --as writer "git+file://$tmp/second" >"$tmp/collide.out" 2>&1
status=$?
set -e
[ "$status" -ne 0 ] || fail "collision: expected a non-zero exit"
has "already pinned" "$(cat "$tmp/collide.out")" "collision"

# ---- 6: a room is refused, not silently pinned as data ------------------------
# (Still refuses without --room — acquisition step F changed the message,
# not the behavior, once --room --namespace became the real way in.)
new_consumer
set +e
haus add -y "git+file://$tmp/a-room" >"$tmp/room.out" 2>&1
status=$?
set -e
[ "$status" -ne 0 ] || fail "room: expected a non-zero exit"
has "--room" "$(cat "$tmp/room.out")" "room"
lacks "inputs.a-room" "$(cat "$tmp/consumer/flake.nix")" "room: must not have been pinned"

# ---- 7: --vendor copies the file in and never touches inputs -----------------
new_consumer
out="$(haus add --vendor --as v1 -y "git+file://$tmp/writer" 2>&1)"
has "vendored" "$out" "vendor"
[ -f "$tmp/consumer/desktops/v1.nix" ] || fail "vendor: file was not copied"
grep -qE '^        desktop = \./desktops/v1\.nix;$' "$tmp/consumer/flake.nix" \
  || fail "vendor: desktop line not set to the vendored path"
lacks "inputs.v1" "$(cat "$tmp/consumer/flake.nix")" "vendor: must not add an input"

# ---- 8: remove refuses a name that isn't pinned -------------------------------
set +e
haus remove nope >"$tmp/nope.out" 2>&1
status=$?
set -e
[ "$status" -ne 0 ] || fail "remove nope: expected a non-zero exit"
has "no pinned input" "$(cat "$tmp/nope.out")" "remove nope"

# ---- 9: two host blocks refuses rather than writing a desktop line into BOTH -
# The pre-PR assurance pass caught this one: `$existing` (desktop-line count)
# is 0 for the whole file regardless of how many `host = ` lines it has, so
# "insert after host when nothing exists yet" would insert after EVERY host
# block on a consumer managing more than one Mac from one flake — silently
# handing the second host the first's desktop too, and nixfmt cannot see it
# because two `desktop = ` lines in two different `mkHaus { … }` calls is
# syntactically ordinary Nix.
rm -rf "$tmp/consumer"
mkdir -p "$tmp/consumer/hosts/one" "$tmp/consumer/hosts/two"
printf '{ }\n' > "$tmp/consumer/hosts/one/default.nix"
printf '{ }\n' > "$tmp/consumer/hosts/two/default.nix"
cat > "$tmp/consumer/flake.nix" <<NIX
{
  description = "two machines, one flake";

  inputs.haus.url = "path:$root";

  outputs =
    { haus, ... }:
    {
      darwinConfigurations.one = haus.mkHaus {
        username = "tester";
        hostname = "one";
        host = ./hosts/one;
      };
      darwinConfigurations.two = haus.mkHaus {
        username = "tester";
        hostname = "two";
        host = ./hosts/two;
      };
    };
}
NIX
( cd "$tmp/consumer" && nix flake lock >/dev/null 2>&1 )
before="$(cat "$tmp/consumer/flake.nix")"
out="$(haus add -y "git+file://$tmp/writer" 2>&1)"
has "add these by hand" "$out" "two hosts"
after="$(cat "$tmp/consumer/flake.nix")"
[ "$before" = "$after" ] || fail "two hosts: flake.nix was touched on the degrade path"
[ "$(grep -c '        desktop = ' "$tmp/consumer/flake.nix")" = 0 ] \
  || fail "two hosts: a desktop line leaked into the untouched file"

# ---- 10: --room without --namespace refuses, and touches nothing -------------
new_consumer
before="$(cat "$tmp/consumer/flake.nix")"
set +e
haus add --room "git+file://$tmp/room-a" >"$tmp/noroomns.out" 2>&1
status=$?
set -e
[ "$status" -ne 0 ] || fail "room without --namespace: expected a non-zero exit"
has "--namespace" "$(cat "$tmp/noroomns.out")" "room without --namespace"
after="$(cat "$tmp/consumer/flake.nix")"
[ "$before" = "$after" ] || fail "room without --namespace: flake.nix was touched"

# ---- 11: --namespace without --room refuses -----------------------------------
set +e
haus add --namespace testroom "git+file://$tmp/writer" >"$tmp/nsnoroom.out" 2>&1
status=$?
set -e
[ "$status" -ne 0 ] || fail "namespace without --room: expected a non-zero exit"
has "only applies to --room" "$(cat "$tmp/nsnoroom.out")" "namespace without --room"

# ---- 12: the reserved 'my' namespace refuses -----------------------------------
set +e
haus add --room --namespace my "git+file://$tmp/room-a" >"$tmp/nsmy.out" 2>&1
status=$?
set -e
[ "$status" -ne 0 ] || fail "namespace my: expected a non-zero exit"
has "reserved" "$(cat "$tmp/nsmy.out")" "namespace my"

# ---- 13: a namespace this machine already has refuses -------------------------
set +e
haus add --room --namespace bar "git+file://$tmp/room-a" >"$tmp/nsbar.out" 2>&1
status=$?
set -e
[ "$status" -ne 0 ] || fail "namespace bar: expected a non-zero exit"
has "already exists" "$(cat "$tmp/nsbar.out")" "namespace bar"

# ---- 14: a room with no revision refuses — nothing for the typed confirmation
# to name, and nothing 'nix flake lock' could pin as an ordinary input anyway --
set +e
haus add --room --namespace testroom "file+file://$tmp/raw-room.nix" >"$tmp/noshaperoom.out" 2>&1
status=$?
set -e
[ "$status" -ne 0 ] || fail "shapeless room: expected a non-zero exit"
has "revision" "$(cat "$tmp/noshaperoom.out")" "shapeless room"

# ---- 15: without the confirming env var, a room add refuses non-interactively,
# and flake.nix is untouched — the prompt gates BEFORE the edit, not just the lock
new_consumer
before="$(cat "$tmp/consumer/flake.nix")"
set +e
haus add --room --namespace testroom "git+file://$tmp/room-a" >"$tmp/noconfirm.out" 2>&1
status=$?
set -e
[ "$status" -ne 0 ] || fail "room no confirm: expected a non-zero exit"
has "HAUS_ADD_ROOM_" "$(cat "$tmp/noconfirm.out")" "room no confirm"
after="$(cat "$tmp/consumer/flake.nix")"
[ "$before" = "$after" ] || fail "room no confirm: flake.nix was touched"

# ---- 16: a room is pinned, wired into extraModules, and its namespace lands ---
new_consumer
out="$(HAUS_ADD_ROOM_ROOMA="$room_a_rev" haus add --room --as rooma --namespace testroom "git+file://$tmp/room-a" 2>&1)"
has "pinned and wired" "$out" "room add"
lacks "flake = false" "$(grep -A1 'inputs\.rooma\.url' "$tmp/consumer/flake.nix")" "room add: must not carry flake = false"
grep -qE '^  inputs\.rooma\.url = "git\+file://'"$tmp"'/room-a";$' "$tmp/consumer/flake.nix" \
  || fail "room add: input line missing or malformed"
grep -qE '^    \{ haus, rooma, \.\.\. \}:$' "$tmp/consumer/flake.nix" \
  || fail "room add: outputs pattern not bound"
grep -qE '^        extraModules = \[ rooma\.darwinModules\.default \];$' "$tmp/consumer/flake.nix" \
  || fail "room add: extraModules line missing"
nixfmt - <"$tmp/consumer/flake.nix" >/dev/null || fail "room add: flake.nix does not parse"
locked="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["nodes"]["rooma"]["locked"]["rev"])' "$tmp/consumer/flake.lock")"
[ "$locked" = "$room_a_rev" ] || fail "room add: locked rev does not match the source"
claimed="$(cd "$tmp/consumer" && nix eval --raw .#darwinConfigurations.testbox.config.haus._rooms.claimed.testroom)"
[ "$claimed" = "git+file://$tmp/room-a" ] || fail "room add: namespace claim did not land ($claimed)"
landed="$(cd "$tmp/consumer" && nix eval .#darwinConfigurations.testbox.config.haus.testroom.enable)"
[ "$landed" = "true" ] || fail "room add: haus.testroom.enable did not land ($landed)"

# ---- 17: remove strips the input AND the extraModules line, and warns that the
# namespace claim is left behind rather than guessed at -------------------------
out="$(haus remove rooma 2>&1)"
has "extraModules entry" "$out" "room remove"
has "haus._rooms.claimed" "$out" "room remove"
lacks "inputs.rooma" "$(cat "$tmp/consumer/flake.nix")" "room remove: input line still present"
lacks "extraModules" "$(cat "$tmp/consumer/flake.nix")" "room remove: extraModules line still present"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(1 if "rooma" in d["nodes"] else 0)' \
  "$tmp/consumer/flake.lock" || fail "room remove: lock still carries the pruned node"
claimed="$(cd "$tmp/consumer" && nix eval --raw .#darwinConfigurations.testbox.config.haus._rooms.claimed.testroom)"
[ "$claimed" = "git+file://$tmp/room-a" ] || fail "room remove: claim file was unexpectedly touched"

# ---- 18: a second, different room claiming the SAME namespace still pins and
# wires (the edit machinery doesn't know about claims), but the claim itself
# refuses to overwrite a DIFFERENT origin's still-standing claim -----------------
out="$(HAUS_ADD_ROOM_ROOMB="$room_b_rev" haus add --room --as roomb --namespace testroom "git+file://$tmp/room-b" 2>&1)"
has "claim didn't write" "$out" "room collision"
grep -qE '^        extraModules = \[ roomb\.darwinModules\.default \];$' "$tmp/consumer/flake.nix" \
  || fail "room collision: extraModules line wasn't rewired to the new room"
claimed="$(cd "$tmp/consumer" && nix eval --raw .#darwinConfigurations.testbox.config.haus._rooms.claimed.testroom)"
[ "$claimed" = "git+file://$tmp/room-a" ] || fail "room collision: the OLD claim should have survived untouched ($claimed)"

# ---- 19: a second SIMULTANEOUS room degrades to --print, touching nothing -----
new_consumer
HAUS_ADD_ROOM_ROOMA="$room_a_rev" haus add --room --as rooma --namespace testroom "git+file://$tmp/room-a" >/dev/null 2>&1
before="$(cat "$tmp/consumer/flake.nix")"
out="$(HAUS_ADD_ROOM_ROOMB="$room_b_rev" haus add --room --as roomb --namespace otherns "git+file://$tmp/room-b" 2>&1)"
has "add these by hand" "$out" "second room"
after="$(cat "$tmp/consumer/flake.nix")"
[ "$before" = "$after" ] || fail "second room: flake.nix was touched on the degrade path"

# ---- 20: --module is validated like --as and --namespace, not written raw ----
# (found by the pre-PR assurance pass: --module landed in flake.nix with no
# check at all, unlike every other token this command writes there — a
# publisher's own install instructions are exactly the untrusted text this
# design otherwise guards, so a malformed --module must never reach the file.)
new_consumer
before="$(cat "$tmp/consumer/flake.nix")"
set +e
HAUS_ADD_ROOM_ROOMA="$room_a_rev" haus add --room --as rooma --namespace testroom \
  --module '"default" or (builtins.trace "pwned" null)' "git+file://$tmp/room-a" \
  >"$tmp/badmodule.out" 2>&1
status=$?
set -e
[ "$status" -ne 0 ] || fail "bad --module: expected a non-zero exit"
has "legal Nix identifier" "$(cat "$tmp/badmodule.out")" "bad --module"
after="$(cat "$tmp/consumer/flake.nix")"
[ "$before" = "$after" ] || fail "bad --module: flake.nix was touched"

printf 'ok — haus add/desktop/remove: %s\n' "$show"
