#!/bin/bash
# haus-secret — the one door to the secrets THIS MACHINE'S ROOMS declared.
#
# Rooms don't fetch secrets themselves and don't learn which provider this Mac
# uses: a room writes a declaration to `haus._contrib.secrets`, the secrets room
# renders every declaration into ~/.config/haus/secretspec.toml, and this reads
# that manifest. So a room's wiring says `haus-secret GITHUB_WEBHOOK_SECRET` and
# keeps saying it whether the values live in the login keychain, in Google
# Secret Manager or in 1Password.
#
# A wrapper rather than "just call secretspec": `secretspec get` finds its
# manifest by walking UP from the current directory, and the things that want a
# value here are launchd agents, which have no meaningful cwd. Spelling --file
# once is also what lets the manifest move without touching every room.
#
# On --reason: secretspec's own policy (`require_reason`, "agents" by default)
# makes an agent write down why before it may read a value, recorded by
# providers that keep an audit log. This wrapper deliberately does NOT invent
# one for the read path — that would hand every agent on the machine a blanket
# excuse. A room that reads a value at boot passes its own; a person at a
# terminal is not gated by the default policy at all. The report paths do carry
# a fixed reason, because what they resolve is presence and what they print is
# never a value.
set -euo pipefail

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
MANIFEST="$CONFIG_HOME/haus/secretspec.toml"
STAMP="${XDG_STATE_HOME:-$HOME/.local/state}/haus/secrets/confirmed"
SECRETSPEC=@secretspec@
TABLE=@table@
# 1 when this Mac's provider keys an "always allow" to the READING BINARY, the
# way the macOS login keychain does — see `ok` below for why that decides how
# this machine is allowed to answer "is it filled in?".
PROVIDER_ITEM_ACL=@providerItemAcl@

REPORT_REASON="haus-secret: report which of this machine's declared secrets have a value (no value is read out)"
FILL_REASON="haus-secret --check: fill in the values this machine's rooms are missing"

usage() {
  cat <<'EOF'
haus-secret — the secrets this machine's rooms declared

  haus-secret <NAME>              print one value on stdout
  haus-secret --reason <why> NAME the same, with a reason for the audit log
  haus-secret --list              what the rooms on this Mac need, and why
  haus-secret --wanted            just the names, one per line (asks nothing)
  haus-secret --status            which of them have a value (never prompts,
                                  never prints a value)
  haus-secret --ok                exit 0 if nothing is waiting on you
  haus-secret --check             fill in what is missing, interactively
EOF
}

die() {
  printf 'haus-secret: %s\n' "$1" >&2
  exit 1
}

no_manifest() {
  cat >&2 <<EOF
haus-secret: no room on this Mac declares a secret, so there is no manifest at
  $MANIFEST

A room asks for one by writing haus._contrib.secrets.<key>. A PROJECT's own
secrets stay in that project's committed secretspec.toml, which secretspec
finds by itself.
EOF
  exit 1
}

# The declarations, rendered at build time: key(s), name, required, why, obtain.
# Prose rather than a machine format — this is the "what is this Mac asking me
# for, and why" answer, and nothing parses it back.
list() {
  [ -s "$TABLE" ] || no_manifest
  local keys name required why obtain kind
  while IFS=$'\t' read -r keys name required why obtain; do
    if [ "$required" = "1" ]; then kind=required; else kind=optional; fi
    printf '%s  (%s, wanted by %s)\n' "$name" "$kind" "$keys"
    printf '  %s\n' "$why"
    if [ -n "$obtain" ]; then printf '  where: %s\n' "$obtain"; fi
    printf '\n'
  done <"$TABLE"
}

# Names only, and REQUIRED names only — the set `--ok` answers about. Reads the
# build-time table and nothing else, so it is safe anywhere: no provider, no
# prompt, no network.
wanted() {
  local keys name required why obtain
  while IFS=$'\t' read -r keys name required why obtain; do
    if [ "$required" = "1" ]; then printf '%s\n' "$name"; fi
  done <"$TABLE"
}

# "Is anything waiting on me?", answered two different ways on purpose.
#
# With a provider that has no per-item ACL (any of the cloud ones), asking it is
# free and truthful, so ask: a value rotated away underneath the machine shows
# up immediately.
#
# With the login keychain it is NOT free. macOS keys each item's "always allow"
# to the exact binary that read it, so the first read after secretspec's store
# path moves raises a modal dialog per secret — and `haus doctor` /
# `haus permissions` are the two callers here. A wizard that fires permission
# dialogs is the thing the manual-click deck exists to end, so on that provider
# this answers from a STAMP `--check` wrote instead: your word, recorded, rather
# than a green tick nothing earned. `--status` is the live look, and it is only
# ever run because a person typed it.
ok() {
  [ -f "$MANIFEST" ] || return 0 # nothing declared is nothing missing
  if [ "$PROVIDER_ITEM_ACL" != "1" ]; then
    if "$SECRETSPEC" check --file "$MANIFEST" --no-prompt --reason "$REPORT_REASON" \
      >/dev/null 2>&1; then return 0; else return 1; fi
  fi
  local name
  while read -r name; do
    [ -f "$STAMP" ] || return 1
    grep -qxF "$name" "$STAMP" || return 1
  done < <(wanted)
  return 0
}

reason=""
if [ "${1:-}" = "--reason" ]; then
  [ $# -ge 3 ] || die "--reason takes a sentence and a secret name"
  reason="$2"
  shift 2
fi

case "${1:-}" in
--help | -h)
  usage
  ;;

"")
  usage >&2
  exit 2
  ;;

--list)
  list
  ;;

--wanted)
  [ -s "$TABLE" ] || no_manifest
  wanted
  ;;

--status)
  [ -f "$MANIFEST" ] || no_manifest
  # `check --explain` is a value-free resolution trace: it names which secrets
  # resolve and which are empty, prompts for nothing, and prints no value. On
  # the login keychain it can still raise a keychain dialog (see `ok`), which is
  # why nothing runs this on your behalf.
  exec "$SECRETSPEC" check --file "$MANIFEST" --explain --reason "$REPORT_REASON"
  ;;

--ok)
  ok
  ;;

--check)
  [ -f "$MANIFEST" ] || no_manifest
  list
  # secretspec's own fill loop: it asks for each missing value and writes it to
  # the provider. Interactive on purpose — haus never handles the value.
  "$SECRETSPEC" check --file "$MANIFEST" --reason "$FILL_REASON"
  # What the run confirmed, for the deck's sake. Written only on success, and
  # only ever read on a provider this machine may not interrogate quietly.
  mkdir -p "$(dirname "$STAMP")"
  wanted >"$STAMP"
  ;;

-*)
  die "unknown option: $1"
  ;;

*)
  [ -f "$MANIFEST" ] || no_manifest
  if [ -n "$reason" ]; then
    exec "$SECRETSPEC" get --file "$MANIFEST" --reason "$reason" "$1"
  fi
  exec "$SECRETSPEC" get --file "$MANIFEST" "$1"
  ;;
esac
