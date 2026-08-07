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
  printf '%s\t%s\t%s\n' 'Make text bigger' 'nebelhaus.ui.scale → 1.35' 'textformat.size.larger'
  printf '%s\t%s\t%s\n' 'Switch to light mode' 'nebelhaus.theme.flavor → latte' 'sun.max.fill'
  printf '%s\t%s\t%s\n' 'High contrast on' 'nebelhaus.theme.contrast → high' 'circle.lefthalf.filled'
} | pounce -p 'Haus Settings' -i 'slider.horizontal.3')"

case "${choice%%$'\t'*}" in
  'Make text bigger') path='ui.scale'; value='1.35' ;;
  'Switch to light mode') path='theme.flavor'; value='latte' ;;
  'High contrast on') path='theme.contrast'; value='high' ;;
  *) exit 0 ;;
esac

runner="$(mktemp "${TMPDIR:-/tmp}/nebelhaus-setting.XXXXXX")"
{
  printf '%s\n' '#!/bin/bash'
  # $0 belongs to the generated runner, not this script.
  # shellcheck disable=SC2016
  printf '%s\n' 'trap '\''rm -f -- "$0"'\'' EXIT'
  printf 'export PATH=%q\n' "$PATH"
  printf 'haus set %q %q\n' "$path" "$value"
  printf '%s\n' 'echo' 'echo "Press any key to close…"' 'read -n 1 -s'
} >"$runner"
chmod 700 "$runner"
xattr -d com.apple.quarantine "$runner" 2>/dev/null || true

exec "$HOME/.config/zellij/float-term.sh" spawn \
  --title quick-terminal-settings \
  --w 750 --h 400 --cols 80 --rows 20 \
  --pin \
  --command "bash $runner"
