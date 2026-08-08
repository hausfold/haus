#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/hosts/test"
git -C "$tmp" init -q

cat >"$tmp/flake.nix" <<EOF
{
  inputs.nebelhaus.url = "path:$repo";
  outputs = { self, nebelhaus }: {
    darwinConfigurations.test = nebelhaus.mkNebelhaus {
      username = "you";
      hostname = "test";
      host = ./hosts/test;
    };
  };
}
EOF
printf '%s\n' '{ ... }: { }' >"$tmp/hosts/test/default.nix"
git -C "$tmp" add flake.nix hosts/test/default.nix

haus=(env HAUS_CONSUMER="$tmp" HAUS_HOST=test HAUS_NO_REBUILD=1 bash "$repo/modules/den/haus.sh")

"${haus[@]}" set theme.accent teal >/dev/null
test "$("${haus[@]}" get theme.accent)" = "teal"
grep -q 'nebelhaus.theme.accent = lib.mkForce ("teal");' "$tmp/hosts/test/settings/theme.accent.nix"

"${haus[@]}" set ui.scale 1.35 >/dev/null
test "$("${haus[@]}" get ui.scale)" = "1.35"

# Several pairs in one call — what the palette's "Switch to light mode" runs, and
# the reason `haus set` is variadic (one rebuild, not two, with no half-done state
# in between).
"${haus[@]}" set theme.flavor latte theme.systemAppearance flavor >/dev/null
test "$("${haus[@]}" get theme.flavor)" = "latte"
test "$("${haus[@]}" get theme.systemAppearance)" = "flavor"

# …and it is all-or-nothing. A bad value in the SECOND pair must roll the first
# one back, not leave it applied: a partial write is the failure the single-pair
# version's restore-on-failure existed to prevent, and more pairs make it worse.
if "${haus[@]}" set theme.flavor mocha theme.systemAppearance chartreuse >/dev/null 2>&1; then
  echo "haus set accepted an invalid value in a later pair" >&2
  exit 1
fi
test "$("${haus[@]}" get theme.flavor)" = "latte"        # rolled back, not "mocha"
test "$("${haus[@]}" get theme.systemAppearance)" = "flavor"

# A path named twice would make the second write's "backup" the first write's
# file, so a rollback would silently keep the first value.
if "${haus[@]}" set theme.flavor mocha theme.flavor latte >/dev/null 2>&1; then
  echo "haus set accepted the same path twice" >&2
  exit 1
fi

if "${haus[@]}" set theme.flavor >/dev/null 2>&1; then
  echo "haus set accepted an odd number of arguments" >&2
  exit 1
fi
if "${haus[@]}" set theme.flavor mocha theme.contrast >/dev/null 2>&1; then
  echo "haus set accepted a trailing path with no value" >&2
  exit 1
fi

# The transaction must cover more than a rejected VALUE. A stale index.lock makes
# settings_stage's `git add` fail — a bare `set -e` abort partway through the
# writes — and with several pairs that would leave file 1 written, staged,
# unvalidated and un-restored: the exact half-done machine this command exists to
# prevent, with no error the user can act on. The EXIT trap is what covers it.
: >"$tmp/.git/index.lock"
"${haus[@]}" set theme.wallpaper orbits theme.contrast high >/dev/null 2>&1 || true
rm -f "$tmp/.git/index.lock"
test ! -e "$tmp/hosts/test/settings/theme.wallpaper.nix"
test ! -e "$tmp/hosts/test/settings/theme.contrast.nix"
test "$("${haus[@]}" get theme.wallpaper)" = "none"
test "$("${haus[@]}" get theme.contrast)" = "normal"

# reset is variadic for the same arithmetic as set: the light-mode intent took
# two options to make, so it must take ONE command to undo — two calls is two
# rebuilds with the machine half-undone in between.
"${haus[@]}" reset theme.flavor theme.systemAppearance >/dev/null
test "$("${haus[@]}" get theme.systemAppearance)" = "unmanaged"
test ! -e "$tmp/hosts/test/settings/theme.flavor.nix"
test ! -e "$tmp/hosts/test/settings/theme.systemAppearance.nix"

# A path with no override is not fatal — the caller asked for it to inherit and
# it already does, so the paths that DO have one still get withdrawn.
"${haus[@]}" set theme.flavor latte >/dev/null
"${haus[@]}" reset theme.contrast theme.flavor >/dev/null
test "$("${haus[@]}" get theme.flavor)" = "mocha"
test ! -e "$tmp/hosts/test/settings/theme.flavor.nix"

# …but naming one twice is, for the same reason it is in set: the second
# removal's "backup" would be a file the first removal already took away.
"${haus[@]}" set theme.flavor latte >/dev/null
if "${haus[@]}" reset theme.flavor theme.flavor >/dev/null 2>&1; then
  echo "haus reset accepted the same path twice" >&2
  exit 1
fi
test "$("${haus[@]}" get theme.flavor)" = "latte"        # refused before any removal
"${haus[@]}" reset theme.flavor >/dev/null

if "${haus[@]}" reset >/dev/null 2>&1; then
  echo "haus reset accepted no arguments" >&2
  exit 1
fi

# unset is variadic too, expanding to `<path> null` pairs through set — so it
# inherits set's all-or-nothing: an option whose type has no null takes the whole
# call down rather than leaving the others written.
"${haus[@]}" unset lock.requirePassword >/dev/null
test "$("${haus[@]}" get lock.requirePassword)" = "null"

if "${haus[@]}" unset lock.requirePasswordDelay theme.accent >/dev/null 2>&1; then
  echo "haus unset accepted a non-nullable option" >&2
  exit 1
fi
test "$("${haus[@]}" get theme.accent)" = "teal"         # rolled back, still set
test ! -e "$tmp/hosts/test/settings/lock.requirePasswordDelay.nix"

if "${haus[@]}" unset >/dev/null 2>&1; then
  echo "haus unset accepted no arguments" >&2
  exit 1
fi

"${haus[@]}" reset lock.requirePassword theme.accent >/dev/null
test "$("${haus[@]}" get theme.accent)" = "mauve"
test ! -e "$tmp/hosts/test/settings/theme.accent.nix"

if "${haus[@]}" set system.defaults.dock.autohide true >/dev/null 2>&1; then
  echo "haus set accepted a path outside nebelhaus.*" >&2
  exit 1
fi

if "${haus[@]}" set theme.accent chartreuse >/dev/null 2>&1; then
  echo "haus set accepted an invalid enum value" >&2
  exit 1
fi

printf 'haus settings: ok\n'
