#!/bin/bash
# The fixture for the ONE header mistake that used to be silent: a `widget:`
# declaration glued to the tail of a prose comment line instead of standing on
# its own. `bar-widget-header` in flake.nix parses this file and expects the
# throw — not a pill, not installed anywhere, and deliberately never valid.
#
# The clock shipped exactly this line shape and sat frozen for weeks, so the
# fixture keeps the shape rather than a paraphrase of it. widget: interval = 10

BAR_ITEM=glued
source "$HOME/.config/sketchybar/barlib.sh"

fetch() { emit label=frozen; }
render() { pill --label "$label"; }

barlib_main "$@"
