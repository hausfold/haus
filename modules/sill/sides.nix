# The bottom bar's groups, in the order they are emitted — SketchyBar's own
# left/center/right regions.
#
# One list, imported by BOTH halves: options.nix builds the enum a pill's value
# is checked against, and default.nix walks it to emit one run per group. Two
# copies would type-check happily while disagreeing — a region added to the enum
# alone accepts the value and then never emits the group, so the pill simply
# isn't drawn and nothing says why. (SketchyBar has `q` and `e` too, either of
# which could plausibly be the fourth.)
#
# The menu bar has no such list: its movable pills are all on the right, because
# its left is the workspace pills, the front app and the leader picker, and its
# center is kept clear for the notch.
[
  "left"
  "center"
  "right"
]
