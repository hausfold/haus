#!/bin/bash
# pounce: name = Haus Settings
# pounce: description = Text size, light mode, and contrast — saved as Nix
# pounce: icon = slider.horizontal.3
# pounce: submenu = true
#
# A small front door onto the machine-writable `haus set` overlay. The palette
# only chooses an intent; haus owns path validation, the ordinary Nix module,
# type-checking, and the rebuild. Keep those mechanics in one place.

export PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/etc/profiles/per-user/$USER/bin:/usr/bin:/bin:/usr/sbin:/sbin"

choice="$({
  printf '%s\t%s\t%s\n' 'Make text bigger' 'haus.ui.scale → 1.35' 'textformat.size.larger'
  printf '%s\t%s\t%s\n' 'Switch to light mode' 'haus AND macOS → light' 'sun.max.fill'
  printf '%s\t%s\t%s\n' 'High contrast on' 'haus.theme.contrast → high' 'circle.lefthalf.filled'
} | pounce -p 'Haus Settings' -i 'slider.horizontal.3')"

# A generic stdin picker's row commit is "<action>\t<raw-row>", not the raw row
# alone (State.swift's buildCommit, .plain case) — action is enter/cmd/opt/ctrl
# depending which key committed it. Drop that verb before matching on the row's
# own first field, or every row here compares against "enter", falls through to
# the `*)` arm, and the menu silently does nothing. Same rule, same fix as
# modules/bar/sketchybar/plugins/haus_menu.sh.
choice="${choice#*$'\t'}"

# Each action is a list of `haus set` PAIRS. Light mode needs two of them, and
# needs them in one `haus set`: theme.flavor alone recolours haus's own tools
# and leaves System Settings ▸ Appearance dark, which is the half-done state
# this row exists to avoid — and two `haus set` calls would be two rebuilds with
# the machine sitting in exactly that state in between.
case "${choice%%$'\t'*}" in
  'Make text bigger') pairs=(ui.scale 1.35) ;;
  'Switch to light mode') pairs=(theme.flavor latte theme.systemAppearance flavor) ;;
  'High contrast on') pairs=(theme.contrast high) ;;
  *) exit 0 ;;
esac

runner="$(mktemp "${TMPDIR:-/tmp}/haus-setting.XXXXXX")"
{
  printf '%s\n' '#!/bin/bash'
  # $0 belongs to the generated runner, not this script.
  # shellcheck disable=SC2016
  printf '%s\n' 'trap '\''rm -f -- "$0"'\'' EXIT'
  printf 'export PATH=%q\n' "$PATH"
  printf 'haus set'; printf ' %q' "${pairs[@]}"; printf '\n'
  printf '%s\n' 'echo' 'echo "Press any key to close…"' 'read -n 1 -s'
} >"$runner"
chmod 700 "$runner"
xattr -d com.apple.quarantine "$runner" 2>/dev/null || true
cleanup() { rm -f -- "$runner"; }
trap cleanup EXIT

exec "$HOME/.config/haus/term/float-term.sh" spawn \
  --title quick-terminal-settings \
  --w 750 --h 400 --cols 80 --rows 20 \
  --pin \
  --command "bash $runner"
