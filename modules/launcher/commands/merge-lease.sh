#!/bin/bash
# pounce: name = Merge Lease
# pounce: description = Grant or revoke factory's unattended merge authority
# pounce: icon = arrow.triangle.merge
# pounce: submenu = true
#
# The four `factory lease` verbs, from the palette. The bar's `factory` pill
# (bar/sketchybar/plugins/factory.sh) offers the same four and reads the same
# `lease status --json`; this is the door for a machine that does not draw that
# pill, and the faster one when your hands are already on the keyboard.
#
# It chooses an INTENT and nothing else. What may merge is authority, and it
# lives in a machine-local `~/.config/factory/config.json` and a lease file no
# pull request can edit — so this script spells four verbs, reads one status,
# and never touches either file.
#
# ── the 8-second cliff ───────────────────────────────────────────────────────
# A submenu command commits with pounce's `.loading` disposition, and
# `Window.startLoading`'s fallback fades the window out after eight seconds if
# step 2 never calls present(). So every exit here either prints rows or prints
# a row that SAYS what happened — a bare `exit 0` leaves the palette pulsing at
# a skeleton and then vanishing, which is what "the command does nothing" looks
# like from the outside. lanes.sh's own box has the long version.
set -u

# A palette command runs under the pounce daemon's launchd environment, whose
# PATH is bare. Same prelude as the other commands here.
export PATH="/run/current-system/sw/bin:/etc/profiles/per-user/${USER:-$(id -un)}/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# The one parse of a pounce menu answer — menu_commit / menu_field.
. "$(dirname "$0")/lib/menu-commit.sh"

PROMPT_ICON="arrow.triangle.merge"

notify() { # notify <body> [symbol]
  haus-notify --source haus.launcher.factory --symbol "${2:-arrow.triangle.merge}" \
    --title "Merge lease" --body "$1" >/dev/null 2>&1 || true
}

# This room installs the command only where the AI room is on, so a missing
# binary here means a generation mid-rebuild or a profile that has moved — rare,
# and still a row rather than a silent skeleton.
if ! command -v factory >/dev/null 2>&1; then
  printf '%s\t%s\t%s\n' "factory is unavailable" \
    "Rebuild haus, then try again" "exclamationmark.triangle" |
    pounce -p "Merge Lease" -i "$PROMPT_ICON" >/dev/null
  exit 1
fi

# `factory lease status --json` exits 1 when there is no live lease, which is
# the ordinary state and not an error — hence the `|| true`. Its `line` is
# factory's own sentence about the lease ("lease: none", "lease: tier 1 · 3h 58m
# left · until Tue 09:12"), and it is the prompt rather than a row because the
# rows are the four things you can DO and this is the one thing you need to know
# before choosing between them.
line="$(factory lease status --json 2>/dev/null | jq -r '.line // ""')" || line=""
[ -n "$line" ] || line="lease: unknown"
prompt="Merge ${line}"

sel="$({
  printf '%s\t%s\t%s\n' '4 hours' \
    'Tier-1 PRs may merge unattended until then' '4.circle'
  printf '%s\t%s\t%s\n' '12 hours' \
    'A night of it, the usual grant' '12.circle'
  printf '%s\t%s\t%s\n' 'Until revoked' \
    'No expiry; the shift runs until you stop it' 'infinity'
  printf '%s\t%s\t%s\n' 'Revoke' \
    'Stop now; everything queues at "PR open" again' 'xmark.circle'
} | pounce -p "$prompt" -i "$PROMPT_ICON")" || exit 0
[ -n "$sel" ] || exit 0

menu_commit "$sel"
case "$(menu_field "$MENU_ROW" 1)" in
  '4 hours') verb=(grant 4h) ;;
  '12 hours') verb=(grant 12h) ;;
  'Until revoked') verb=(grant indefinitely) ;;
  'Revoke') verb=(revoke) ;;
  # Free text that matched no row. There is nothing sensible to do with it —
  # a duration typed here would be a fifth verb this list deliberately doesn't
  # offer — so it is a dismissal.
  *) exit 0 ;;
esac

# stderr only: factory reports every refusal there and every ✓ on stdout, so
# this captures the sentence worth repeating and drops the one the banner below
# is about to say better.
if ! err="$(factory lease "${verb[@]}" 2>&1 >/dev/null)"; then
  notify "${err:-factory lease ${verb[*]} failed}" exclamationmark.triangle
  exit 1
fi

# The banner is factory's OWN reading of the lease after the change, not this
# script's guess at what it should now be: a grant that landed and a grant whose
# runner refused to start are the same exit code, and only the status line
# afterwards can tell them apart.
after="$(factory lease status --json 2>/dev/null | jq -r '.line // ""')" || after=""
notify "${after#lease: }"

# Both bars, so the pill agrees with the palette immediately rather than up to
# one 30-second tick later. Exits 0 on a machine with no bar at all.
haus-bar-poke factory_change >/dev/null 2>&1 || true
