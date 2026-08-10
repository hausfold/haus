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
grep -q '^  haus\.theme\.accent = lib\.mkForce ("teal");$' "$tmp/hosts/test/settings/theme.accent.nix"

# The pre-rename spelling still reaches the same option — modules/renamed.nix
# aliases it — and is normalised to the canonical prefix on the way in, so an
# overlay file written before the rename is upgraded by the next `haus set`
# rather than needing a migration. Both halves matter: accepting it and not
# writing it back.
"${haus[@]}" set nebelhaus.theme.accent sky >/dev/null
test "$("${haus[@]}" get nebelhaus.theme.accent)" = "sky"
grep -q '^  haus\.theme\.accent = lib\.mkForce ("sky");$' "$tmp/hosts/test/settings/theme.accent.nix"
grep -q 'nebelhaus\.' "$tmp/hosts/test/settings/theme.accent.nix" && {
  echo "haus set wrote the pre-rename prefix" >&2; exit 1; }
"${haus[@]}" set theme.accent teal >/dev/null

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

# Phase 1 must not narrate a call it is about to abort. theme.contrast has no
# override (an "already inherits" line), and the hand-written file after it is
# fatal — reporting the first before dying on the second reads as if something
# happened, when nothing did.
printf '%s\n' '{ ... }: { }' >"$tmp/hosts/test/settings/theme.wallpaper.nix"
out="$("${haus[@]}" reset theme.contrast theme.wallpaper 2>&1 || true)"
case "$out" in
  *"already inherits"*)
    echo "haus reset narrated a path before dying on a later one" >&2
    exit 1 ;;
esac
rm -f "$tmp/hosts/test/settings/theme.wallpaper.nix"

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

# unset delegates to set, so without care a rejection from down there quotes
# `haus set`'s pair syntax at someone who typed `haus unset`.
out="$("${haus[@]}" unset theme.contrast theme.contrast 2>&1 || true)"
case "$out" in
  *"usage: haus unset"*) ;;
  *) echo "haus unset reported haus set's usage: $out" >&2; exit 1 ;;
esac

"${haus[@]}" reset lock.requirePassword theme.accent >/dev/null
test "$("${haus[@]}" get theme.accent)" = "mauve"
test ! -e "$tmp/hosts/test/settings/theme.accent.nix"

if "${haus[@]}" set system.defaults.dock.autohide true >/dev/null 2>&1; then
  echo "haus set accepted a path outside haus.*" >&2
  exit 1
fi

if "${haus[@]}" set theme.accent chartreuse >/dev/null 2>&1; then
  echo "haus set accepted an invalid enum value" >&2
  exit 1
fi

# A sub-path of a submodule is an ordinary definition site, and the options tree
# doesn't say so — `options.haus.sill.items` is an option, `…items.aiUsage` is not
# an attribute of anything. Setting ONE pill has to work without the whole-attrset
# form, which resets every key it doesn't name.
"${haus[@]}" set sill.items.aiUsage true >/dev/null
test "$("${haus[@]}" get sill.items.aiUsage)" = "true"
grep -q '^  haus\.sill\.items\.aiUsage = lib\.mkForce (builtins\.fromJSON "true");$' \
  "$tmp/hosts/test/settings/sill.items.aiUsage.nix"
test "$("${haus[@]}" get sill.items.weather)" = "true"   # untouched, still its own default
"${haus[@]}" reset sill.items.aiUsage >/dev/null
test "$("${haus[@]}" get sill.items.aiUsage)" = "false"

# …and a typo underneath one is still refused, which is the half of the old guard
# worth keeping.
if "${haus[@]}" set sill.items.nosuchpill true >/dev/null 2>&1; then
  echo "haus set accepted an undeclared submodule sub-option" >&2
  exit 1
fi

# Running out of path components has to land on an OPTION. `theme` and `sill` are
# namespaces — a whole-room mkForce there evaluates fine and then scatters over
# every option in the room, and with the overlap guard it would lock all of them
# out of `haus set` until someone found the file.
for ns in theme sill; do
  if "${haus[@]}" set "$ns" '{}' >/dev/null 2>&1; then
    echo "haus set accepted the namespace '$ns' as if it were an option" >&2
    exit 1
  fi
done

# An attrsOf option's keys are the USER's — they can't be in the options tree at
# all, so the walk consumes one component as a key and checks what's under it.
# Display UUIDs are the reason a component may start with a digit, and the reason
# the generated attrpath quotes what isn't a bare Nix identifier.
"${haus[@]}" set displays.internal.uiScale larger-text >/dev/null
test "$("${haus[@]}" get displays.internal.uiScale)" = "larger-text"
"${haus[@]}" set displays.37D8832A-2D66-02CA-B9F7-8F30A301B230.uiScale more-space >/dev/null
grep -q '^  haus\.displays\."37D8832A-2D66-02CA-B9F7-8F30A301B230"\.uiScale = ' \
  "$tmp/hosts/test/settings/displays.37D8832A-2D66-02CA-B9F7-8F30A301B230.uiScale.nix"
test "$("${haus[@]}" get displays.37D8832A-2D66-02CA-B9F7-8F30A301B230.uiScale)" = "more-space"
if "${haus[@]}" set displays.internal.noSuchKnob 1 >/dev/null 2>&1; then
  echo "haus set accepted an undeclared option under an attrsOf key" >&2
  exit 1
fi

# A Nix keyword is all letters and still not a bare identifier, so the attrpath
# has to quote it too — an attrsOf key is any word the user likes.
"${haus[@]}" set displays.with.uiScale more-space >/dev/null
grep -q '^  haus\.displays\."with"\.uiScale = ' "$tmp/hosts/test/settings/displays.with.uiScale.nix"
"${haus[@]}" reset displays.with.uiScale >/dev/null

# Withdrawing the last override that DEFINED an attrsOf key takes the key away
# rather than revealing a value beneath it, so `config.<path>` stops evaluating —
# the reset working, reported as such and not as a failure.
out="$("${haus[@]}" reset displays.37D8832A-2D66-02CA-B9F7-8F30A301B230.uiScale 2>&1)"
case "$out" in
  *"nothing defines it now"*) ;;
  *) echo "haus reset misreported a key it removed: $out" >&2; exit 1 ;;
esac
test ! -e "$tmp/hosts/test/settings/displays.37D8832A-2D66-02CA-B9F7-8F30A301B230.uiScale.nix"

# …and that must not swallow the failure it looks exactly like. Two plain
# definitions of one option conflict the moment the mkForce on top of them goes,
# and the override has to come back.
printf '{ ... }: { haus.theme.wallpaper = "orbits"; }\n' >"$tmp/hosts/test/settings/zz-a.nix"
printf '{ ... }: { haus.theme.wallpaper = "waves"; }\n' >"$tmp/hosts/test/settings/zz-b.nix"
git -C "$tmp" add -A
"${haus[@]}" set theme.wallpaper none >/dev/null
if "${haus[@]}" reset theme.wallpaper >/dev/null 2>&1; then
  echo "haus reset reported success on a path that cannot evaluate without it" >&2
  exit 1
fi
test -e "$tmp/hosts/test/settings/theme.wallpaper.nix"    # restored, not left removed
rm -f "$tmp/hosts/test/settings/zz-a.nix" "$tmp/hosts/test/settings/zz-b.nix"
git -C "$tmp" add -A
"${haus[@]}" reset theme.wallpaper >/dev/null

# A path and one of its ancestors can't both hold an override: they'd be two
# mkForce definitions of the same leaf, and the module system would report that
# from inside the submodule, as a conflict traceable to neither file. Refused in
# both directions, and before anything is written.
if "${haus[@]}" set displays '{"internal":{"uiScale":"more-space"}}' >/dev/null 2>&1; then
  echo "haus set wrote an override over an existing descendant one" >&2
  exit 1
fi
test "$("${haus[@]}" get displays.internal.uiScale)" = "larger-text"
"${haus[@]}" reset displays.internal.uiScale >/dev/null
"${haus[@]}" set displays '{"internal":{"uiScale":"more-space"}}' >/dev/null
if "${haus[@]}" set displays.internal.uiScale larger-text >/dev/null 2>&1; then
  echo "haus set wrote an override under an existing ancestor one" >&2
  exit 1
fi
# …including two pairs of the SAME call, where neither file exists yet.
"${haus[@]}" reset displays >/dev/null
if "${haus[@]}" set displays.internal.uiScale larger-text displays '{}' >/dev/null 2>&1; then
  echo "haus set accepted an overlapping pair within one call" >&2
  exit 1
fi
test ! -e "$tmp/hosts/test/settings/displays.internal.uiScale.nix"

printf 'haus settings: ok\n'
