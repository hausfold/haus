#!/bin/bash
# The haus menu — what a left click on the far-left logo pill opens: the
# system rows that used to hang off that pill as a popup dropdown, drawn by
# pounce instead.
#
# Why the palette and not a popup. The dropdown this replaces had five rows and
# was never once openable — nothing in the rice ever set `popup.drawing` on that
# item — which is what a menu costs when it is the second implementation of
# things the palette already carries. These rows are the palette's own commands,
# invoked by path, so a fix to one of them lands in both places at once and
# neither can go stale against the other.
#
# It is a picker, not a launcher: `pounce` over stdin, the same shape
# modules/pounce/commands/settings.sh uses. Rows are TAB-separated
# `name<TAB>description<TAB>SF-symbol`.

export PATH="/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# SILL_LOGO_COMMANDS — this rice's pounce commands in the store, GENERATED from
# haus._pounceCommands. Empty when haus.pounce.enable is off, which is also when
# there is no `pounce` binary to draw the list with.
source "$HOME/.config/sketchybar/logo_config.sh"

command -v pounce >/dev/null 2>&1 || exit 0

# Rows that delegate live in $SILL_LOGO_COMMANDS. On a rice with pounce off the
# variable is empty and those rows are simply left out, rather than offered and
# then failing on click.
rows() {
    printf '%s\t%s\t%s\n' 'System Settings' 'Open the Settings app' 'gearshape'
    printf '%s\t%s\t%s\n' 'Activity Monitor' 'What this Mac is busy with' 'chart.line.uptrend.xyaxis'
    printf '%s\t%s\t%s\n' 'Lock Screen' 'Lock now (⌃⌘Q)' 'lock'
    printf '%s\t%s\t%s\n' 'Nix Config' 'Open this host'\''s file in the editor' 'snowflake'
    [ -d "$SILL_LOGO_COMMANDS" ] || return 0
    printf '%s\t%s\t%s\n' 'Haus Settings' 'Text size, light mode, contrast' 'slider.horizontal.3'
    printf '%s\t%s\t%s\n' 'Rebuild System' 'haus rebuild, in a floating terminal' 'arrow.triangle.2.circlepath'
    printf '%s\t%s\t%s\n' 'Reload SketchyBar' 'Re-read the bar'\''s config — both bars' 'arrow.clockwise'
}

choice="$(rows | pounce -p 'haus' -i 'house')"
[ -n "$choice" ] || exit 0

# A generic stdin picker's row commit is "<action>\t<raw-row>", not the raw
# row alone (State.swift's buildCommit, .plain case) — action is enter/cmd/
# opt/ctrl depending which key committed it. Drop that verb before matching
# on the row's own first field, or every row here compares against "enter"
# and none of them ever fire.
choice="${choice#*$'\t'}"

# The first three are pounce's OWN built-ins, which unlike a rice command each
# ship a `pounce-<id>` launcher on PATH (pkgs/pounce-commands wraps `builtinIds`)
# — so they are named, not reimplemented, for the same reason the rice rows go
# through $SILL_LOGO_COMMANDS. `pounce-lock` in particular already IS the
# ⌃⌘Q osascript, and a second copy here would be the one that went stale.
case "${choice%%$'\t'*}" in
'System Settings') exec pounce-preferences ;;
'Activity Monitor') exec pounce-activity ;;
# NB this is the first thing in the rice to drive System Events from a bar
# click. The rows it inherits from the old dropdown were never reachable, so
# none of them has ever run: expect macOS to ask, once, for Automation on
# SketchyBar's behalf, and expect that grant to be keyed to the Homebrew
# binary's VERSIONED path (so `brew upgrade sketchybar` orphans it and it asks
# again). Nothing else on this menu needs a grant — `open -a` never does.
'Lock Screen') exec pounce-lock ;;
# Already a sibling plugin, and hearth's opener underneath it resolves the host
# file and the flake root — so this row is the one that goes through neither
# $SILL_LOGO_COMMANDS nor a pounce built-in.
'Nix Config') exec "$HOME/.config/sketchybar/plugins/nix_open.sh" ;;
'Haus Settings') exec "$SILL_LOGO_COMMANDS/settings.sh" ;;
'Rebuild System') exec "$SILL_LOGO_COMMANDS/rebuild.sh" ;;
'Reload SketchyBar') exec "$SILL_LOGO_COMMANDS/reload-bar.sh" ;;
esac
