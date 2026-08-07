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

"${haus[@]}" unset lock.requirePassword >/dev/null
test "$("${haus[@]}" get lock.requirePassword)" = "null"

"${haus[@]}" reset theme.accent >/dev/null
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
