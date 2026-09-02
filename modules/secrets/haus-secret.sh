#!/usr/bin/env bash
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

# ---- snug's bash painter, loaded only where this draws a report ------------
# `haus-secret` is its own binary and inherits nobody's environment — a launchd
# agent, `haus doctor` and a person at a prompt all exec it directly — so the
# path is substituted at build time the way `focus` takes it, rather than
# inherited from the `haus` wrapper the way `haus show` does. `HAUS_UI_SH` still
# wins when it is set, so a working copy is one variable away.
#
# LAZY, and a function rather than a source at the top, because the hot path
# through this script is `haus-secret NAME` at boot: a room reading one value
# execs it, prints nothing, and must not pay to read a thousand lines of bash
# it will never draw with. Only the report paths call it.
UI_READY=""
ui_load() {
  [ -n "${UI_LOADED:-}" ] && return 0
  UI_LOADED=1
  # ui.sh is bash 4+ — `${role^^}` inside ui_paint_role alone rules 3.2 out —
  # and this script's shebang is `env bash` for exactly that reason. `env` still
  # finds macOS's /bin/bash 3.2 on a launchd PATH with nothing else on it, where
  # sourcing would half-load and leave a painter that answers `type` and then
  # draws nothing. So the version is checked, not assumed, and 3.2 keeps the
  # plain blocks.
  [ "${BASH_VERSINFO[0]:-0}" -ge 4 ] || return 0
  local sh="${HAUS_UI_SH:-@uiSh@}"
  if [ -r "$sh" ]; then
    # shellcheck source=/dev/null
    source "$sh"
  fi
  # Probed rather than assumed: a pin whose ui.sh predates one of these is a
  # `command not found` halfway down the listing, and the plain blocks are still
  # there for exactly that machine.
  # Every verb this script calls, not a sample of them. `--check` reaches
  # `ui_say` and `ui_info` a long way below the listing, and `set -euo pipefail`
  # turns one missing function there into an abort BEFORE the optional-secret
  # loop and before the stamp is written — so `haus-secret --ok` would go on
  # reporting the machine as waiting on you.
  type ui_fail ui_hint ui_say ui_info ui_fold ui_paint_role ui_glyph_bare \
    >/dev/null 2>&1 && UI_READY=1
  return 0
}

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

# The name stays in the message, where `haus.sh`'s own `die` drops it and lets
# the glyph speak: this binary's stderr is a LAUNCHD LOG as often as it is a
# terminal — a room reads a value at boot — and in that log nothing else says
# who refused.
die() {
  ui_load
  if [ -n "$UI_READY" ]; then ui_fail "haus-secret: $1"
  else printf 'haus-secret: %s\n' "$1" >&2; fi
  exit 1
}

no_manifest() {
  ui_load
  if [ -n "$UI_READY" ]; then
    ui_fail "haus-secret: no room on this Mac declares a secret, so there is no manifest at $MANIFEST"
    ui_hint "a room asks for one by writing haus._contrib.secrets.<key>. A PROJECT's own secrets stay in that project's committed secretspec.toml, which secretspec finds by itself."
  else
    cat >&2 <<EOF
haus-secret: no room on this Mac declares a secret, so there is no manifest at
  $MANIFEST

A room asks for one by writing haus._contrib.secrets.<key>. A PROJECT's own
secrets stay in that project's committed secretspec.toml, which secretspec
finds by itself.
EOF
  fi
  exit 1
}

# The declarations, rendered at build time: key(s), name, required, why, obtain.
# Prose rather than a machine format — this is the "what is this Mac asking me
# for, and why" answer, and nothing parses it back.
list() {
  [ -s "$TABLE" ] || no_manifest
  ui_load
  local keys name required why obtain kind kindrole
  local pname pkind pline mark w i
  while IFS=$'\t' read -r keys name required why obtain; do
    if [ "$required" = "1" ]; then kind=required; kindrole=warn
    else kind=optional; kindrole=muted; fi
    if [ -n "$UI_READY" ]; then
      # `UI_OUT_` and not `UI_` — this is the report and it lands on fd 1, and a
      # report is painted for the stream it is written to. Redirect it and the
      # profile answers `none`, which is the same decision the fold below makes
      # when it declines to fit a pipe to a window it does not have.
      #
      # The header carries the NAME and nothing else that could have been
      # folded, which is why `wanted by` moved down a line: a header of
      # name + kind + keys ran to 64 cells and soft-wrapped in any window
      # narrower than that, and a line built out of three painted segments
      # cannot be folded afterwards — the escapes are content to a fold.
      # A name alone still overflows a very narrow window, and it is left to
      # wrap on purpose: this is the string a person is about to type at
      # `haus-secret <NAME>`, and a `…` through the middle of it is worse than
      # a wrap. `github-signal` makes the same call for the `gh api` line it
      # prints whole.
      ui_paint_role pname subject     "$name" UI_OUT_
      ui_paint_role pkind "$kindrole" "$kind" UI_OUT_
      printf '%s  (%s)\n' "$pname" "$pkind"
      # Everything under the header hangs at two cells and folds at the window.
      # This is the one thing the plain shape got wrong: a `why` long enough to
      # soft-wrap came back at column 0 and read as the next entry's header.
      w=$(( UI_OUT_AVAIL - 2 )); [ "$w" -lt 1 ] && w=1
      ui_fold "$w" "wanted by $keys"
      for i in "${!UI_FOLD[@]}"; do
        ui_paint_role pline field "${UI_FOLD[$i]}" UI_OUT_
        printf '  %s\n' "$pline"
      done
      ui_fold "$w" "$why"
      for i in "${!UI_FOLD[@]}"; do printf '  %s\n' "${UI_FOLD[$i]}"; done
      if [ -n "$obtain" ]; then
        # Folded only when there is somewhere to fold. `obtain` is one of two
        # things: a bare URL, or a sentence telling you how to make the value.
        # ui_fold HARD-BREAKS a word wider than the line — deliberately, since
        # overflowing is the one thing it never allows — and a real newline
        # through a URL is a URL that no longer survives being copied. A lone
        # token is therefore printed whole and left to the terminal, which wraps
        # without putting a newline in the buffer; a sentence folds at its
        # spaces like every other line in the block.
        ui_glyph_bare mark hint
        case "$obtain" in
        *[[:space:]]*)
          # The MARK and the label go into the fold with the text, or the first
          # line is budgeted for the text alone and comes back nine cells wider
          # than the window. Folded two narrower than the body above it so that
          # a continuation, which hangs at four, still lands inside the window.
          ui_fold "$(( w - 2 ))" "$mark where: $obtain"
          for i in "${!UI_FOLD[@]}"; do
            ui_paint_role pline muted "${UI_FOLD[$i]}" UI_OUT_
            if [ "$i" -eq 0 ]; then printf '  %s\n' "$pline"
            else printf '    %s\n' "$pline"; fi
          done
          ;;
        *)
          ui_paint_role pline muted "$mark where: $obtain" UI_OUT_
          printf '  %s\n' "$pline"
          ;;
        esac
      fi
    else
      printf '%s  (%s)\n' "$name" "$kind"
      printf '  wanted by %s\n' "$keys"
      printf '  %s\n' "$why"
      if [ -n "$obtain" ]; then printf '  where: %s\n' "$obtain"; fi
    fi
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

# The OPTIONAL half of the same table, as `name<TAB>why`. `secretspec check`
# reports these (`○ NAME … (optional)`) but never asks for one — its whole job
# is the required set — so `--check` asks about them itself, or a value a room
# declared as "nice to have" could only ever be entered by hand.
optional() {
  local keys name required why obtain
  while IFS=$'\t' read -r keys name required why obtain; do
    if [ "$required" != "1" ]; then printf '%s\t%s\n' "$name" "$why"; fi
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
  ui_load
  list
  # secretspec's own fill loop: it asks for each missing value and writes it to
  # the provider. Interactive on purpose — haus never handles the value.
  "$SECRETSPEC" check --file "$MANIFEST" --reason "$FILL_REASON"
  # The optional ones, one question each. Asked every run rather than only when
  # empty: knowing which are already set means reading them, and on the login
  # keychain that is a dialog per secret — a cost worth paying when a person
  # typed `--check`, but not one to pay for a question they can answer with a
  # keystroke. Entering a value again simply overwrites it with itself.
  while IFS=$'\t' read -r name why; do
    if [ -n "$UI_READY" ]; then
      printf '\n' >&2
      ui_say "$name is optional — $why"
      printf 'Set it now? [y/N] ' >&2
    else
      # fd 2 in BOTH branches. The question is narration whether or not a
      # painter drew it, and a `--check >log` that swallowed the prompt on a
      # bash-3.2 machine and showed it everywhere else would be two contracts
      # wearing one verb's name.
      printf '\n%s is optional — %s\n' "$name" "$why" >&2
      printf 'Set it now? [y/N] ' >&2
    fi
    # No tty (a script, a hook, `haus doctor`) is a no, quietly.
    # 2>… BEFORE the </dev/tty it silences: redirections are applied left to
    # right, so the other order reports the failure to the real stderr first.
    read -r answer 2>/dev/null </dev/tty || answer=""
    case "$answer" in
    [yY]*) "$SECRETSPEC" set --file "$MANIFEST" --reason "$FILL_REASON" "$name" ;;
    *)
      if [ -n "$UI_READY" ]; then ui_info 'Skipped. `haus-secret --check` asks again.'
      else printf 'Skipped. `haus-secret --check` asks again.\n' >&2; fi
      ;;
    esac
  done < <(optional)
  # What the run confirmed, for the deck's sake. Written only on success, and
  # only ever read on a provider this machine may not interrogate quietly.
  # REQUIRED names only: an optional one that was skipped is not a machine
  # waiting on anybody.
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
