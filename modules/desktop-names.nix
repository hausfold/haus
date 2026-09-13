# The desktops this flake ships, as bare names — the one list `flake.nix`
# builds `desktops.<name>` paths from and `desktop-check.nix` stages for
# `haus desktop`'s listing, so the two can't drift apart.
#
# One name. A desktop is a starter template — a complete, opinionated selection
# somebody can install by URL — and `hacker` is the one this repo keeps. The
# installer selects NONE by default (`desktop = null;`, the foundation), and
# `blank`, `everyday` and `minimal` are retired: the first was a name for that
# null, the other two were room sets, which is one host line per room now.
# `flake.nix`'s `retiredDesktops` keeps each old spelling an eval error that
# names its replacement.
[
  "hacker"
]
