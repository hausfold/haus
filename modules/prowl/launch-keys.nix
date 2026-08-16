# The keys launch mode binds no matter what a host's roster says: the fixed
# actions written into aerospace.toml by hand, plus three chords per numbered
# workspace.
#
# A file of its own, and a FUNCTION of the resolved numbered workspaces, for the
# same reason ./wm-bindings.nix is one — two things render this list and neither
# may guess at it:
#
#   modules/prowl/default.nix   → `builtinLaunchKeys`, which is what refuses a
#                                 roster letter, a workspace key or a
#                                 leaderExtras key that would silently shadow
#                                 one of these bindings.
#   flake.nix → .#launch-keys-json → site data, which is what hausfold.co's
#                                 keybinding tripwire compares its prose
#                                 against.
#
# The tripwire used to read the digits straight out of aerospace.toml, where
# `1`..`4` and their ⇧-forms were literal rows. haus.prowl.numberedWorkspaces
# turned those rows into a generated block, and a token is not a key — the
# tripwire went on passing while it could no longer see the half of launch mode
# this file exists to describe. Published data, not a parse of a template.
{
  lib,
  numbered,
}:

[
  "esc"
  "slash"
  "v"
  "e"
  "z"
  "comma"
  "backtick"
  "minus"
  "equal"
  "left"
  "down"
  "up"
  "right"
  "shift-left"
  "shift-down"
  "shift-up"
  "shift-right"
]
# Per numbered workspace: focus it, throw the focused window there and follow,
# throw it there and stay.
++ lib.concatMap (n: [
  n.key
  "shift-${n.key}"
  "alt-shift-${n.key}"
]) numbered
