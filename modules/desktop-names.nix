# The desktops this flake ships, as bare names — the one list `flake.nix`
# builds `desktops.<name>` paths from and `desktop-check.nix` stages for
# `haus desktop`'s listing, so the two can't drift apart. `blank` is the
# explicit from-scratch choice and `hacker` the opinionated default;
# `everyday` and `minimal` are the two whole desktops that used to be
# presets, written out as the complete selections they always implied.
[
  "blank"
  "everyday"
  "hacker"
  "minimal"
]
