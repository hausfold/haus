# The fourteen accent names, by Catppuccin spelling. Imported the same way as
# agents.nix / keys.nix — a plain value, no module system involved.
#
#   accentNames = import ../lib/accents.nix;
#
# The Nebelung palette is a grey-tinted Catppuccin, so these names are the
# palette's own keys: uppercased, each one is also the variable colors.sh
# exports to the bar ("teal" → $TEAL). That correspondence is what lets bar
# take an accent name straight from an option and hand it to SketchyBar.
#
# It lives here because `haus.theme.accent` (modules/theme/options.nix) is no
# longer the only option that takes one — `haus.bar.logo.color` names an accent
# too, and defaults to the theme's. Two hand-typed enums of fourteen strings is
# the shape of a list that ends up being thirteen and fourteen.
#
# NOT the whole palette: the neutral ramp (base, mantle, surface0…) and the
# semantic pair `text`/`subtext0` are palette keys as well, but they aren't
# accents and nothing should offer them as one.
[
  "rosewater"
  "flamingo"
  "pink"
  "mauve"
  "red"
  "maroon"
  "peach"
  "yellow"
  "green"
  "teal"
  "sky"
  "sapphire"
  "blue"
  "lavender"
]
