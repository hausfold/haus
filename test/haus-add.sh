#!/usr/bin/env bash
# `haus add` / `haus desktop` / `haus remove` / `haus update`'s own suite —
# acquisition step D. Needs a real `nix flake lock` and `nix eval` against a
# SCAFFOLDED consumer flake, which is exactly what `haus show`'s suite needs
# and exactly why this one runs the same way: `bash modules/core/haus.sh`
# directly (no derivation may shell out to `nix`), from the "eval the example
# host" job, where a real nix exists.
#
# Runs on Linux: none of this is a Mac — it edits a text file and asks Nix to
# resolve inputs. `haus rebuild` is never called; every write here stops one
# step short of it, on purpose, the same as the command it tests.
set -euo pipefail

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

haus() { bash "$root/modules/core/haus.sh" "$@"; }

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
new_consumer
set +e
haus add -y "git+file://$tmp/a-room" >"$tmp/room.out" 2>&1
status=$?
set -e
[ "$status" -ne 0 ] || fail "room: expected a non-zero exit"
has "step F" "$(cat "$tmp/room.out")" "room"
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

printf 'ok — haus add/desktop/remove: %s\n' "$show"
