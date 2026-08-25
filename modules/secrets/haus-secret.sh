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

MANIFEST="$HOME/.config/haus/secretspec.toml"
SECRETSPEC=@secretspec@
TABLE=@table@

REPORT_REASON="haus-secret: report which of this machine's declared secrets have a value (no value is read out)"
FILL_REASON="haus-secret --check: fill in the values this machine's rooms are missing"

usage() {
  cat <<'EOF'
haus-secret — the secrets this machine's rooms declared

  haus-secret <NAME>              print one value on stdout
  haus-secret --reason <why> NAME the same, with a reason for the audit log
  haus-secret --list              what the rooms on this Mac need, and why
  haus-secret --status            which of them have a value (never prompts,
                                  never prints a value)
  haus-secret --ok                exit 0 if every REQUIRED value is present
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

# The declarations, rendered at build time: key, name, required, why, obtain.
# Prose rather than a machine format — this is the "what is this Mac asking me
# for, and why" answer, and nothing parses it back.
list() {
  [ -s "$TABLE" ] || no_manifest
  local key name required why obtain kind
  while IFS=$'\t' read -r key name required why obtain; do
    if [ "$required" = "1" ]; then kind=required; else kind=optional; fi
    printf '%s  (%s, for the %s room)\n' "$name" "$kind" "${key%%-*}"
    printf '  %s\n' "$why"
    if [ -n "$obtain" ]; then printf '  where: %s\n' "$obtain"; fi
    printf '\n'
  done <"$TABLE"
}

# /bin/bash is macOS's own 3.2 — no arrays here, so the read path spells the
# reason'd and unreasoned calls out rather than splatting one.
reason=""
if [ "${1:-}" = "--reason" ]; then
  [ $# -ge 3 ] || die "--reason takes a sentence and a secret name"
  reason="$2"
  shift 2
fi

case "${1:-}" in
"" | --help | -h)
  usage
  ;;

--list)
  list
  ;;

--status)
  [ -f "$MANIFEST" ] || no_manifest
  # `check --explain` is a value-free resolution trace: it names which secrets
  # resolve and which are empty, prompts for nothing, and prints no value. It
  # is the only report here that asks the PROVIDER anything, which is what the
  # fixed reason above is for.
  exec "$SECRETSPEC" check --file "$MANIFEST" --explain --reason "$REPORT_REASON"
  ;;

--ok)
  # Nothing declared is nothing missing — a machine with no secret-wanting room
  # is healthy, not unconfigured.
  [ -f "$MANIFEST" ] || exit 0
  exec "$SECRETSPEC" check --file "$MANIFEST" --no-prompt --reason "$REPORT_REASON" \
    >/dev/null 2>&1
  ;;

--check)
  [ -f "$MANIFEST" ] || no_manifest
  list
  # secretspec's own fill loop: it asks for each missing value and writes it to
  # the provider. Interactive on purpose — haus never handles the value.
  exec "$SECRETSPEC" check --file "$MANIFEST" --reason "$FILL_REASON"
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
