#!/bin/bash
# The fixture a THIRD-PARTY framework widget is pinned by — not a pill, and not
# installed on any machine. `bar-third-party-widget` in flake.nix declares it
# through `haus.bar.widgets.<name>.script` and diffs what the bar's item file
# comes out as, so the one thing that only breaks for a widget haus does not
# ship — the path it is READ from at eval versus the path the bar RUNS — cannot
# regress silently.
#
# It carries one of each header key on purpose: an interval, a dropdown, and a
# custom event nobody else declares, so the emission has something to get wrong
# in each of the three places it could.
# widget: interval   = 30
# widget: popup      = true
# widget: subscribes = haus.example.tick

BAR_ITEM=pomodoro
source "$HOME/.config/sketchybar/barlib.sh"

fetch() { emit left="12m" tone=ok; }
render() { pill --icon "" --label "$left" --tone "$tone"; }
popup_rows() { popup_heading "pomodoro"; }

barlib_main "$@"
