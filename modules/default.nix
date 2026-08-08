# The whole house. Import this for the full rice, or import individual rooms
# (den / prowl / sill / collar / pounce / perch / hush / secrets) from
# `darwinModules` in the flake.
{
  # Options first, one file per room, each living next to the code that
  # implements it. They're listed separately from the rooms rather than
  # imported by them because several rooms wrap their whole body in
  # `lib.mkIf <room>.enable` — an option declared inside that would vanish
  # exactly when it's needed to decide the condition. modules/options.nix
  # keeps only what no single room owns: the shared app roster.
  #
  # The list itself lives in ./options-modules.nix, which is also what the
  # pure-lib option-surface evaluations import (options-json, the claude skill,
  # flake.nix's pack/preset checks). It used to be written out again here, and a
  # module added to one copy and not the other fails in a way that names
  # neither file: absent from this one, a real system loses the option; absent
  # from that one, only the option-surface evals do.
  imports = (import ./options-modules.nix) ++ [
    # Named workspaces: resolves nebelhaus.workspaces into the internal lookup
    # ./roster folds into each app's resolved workspace membership. Comes
    # first because roster depends on it, though the module system's laziness
    # means the two could import in either order without changing anything.
    ./workspaces
    # The app roster: resolves nebelhaus.roster into the internal lists the rooms
    # below read, and installs whatever each entry names. Ungated on purpose —
    # an entry that only wants to BE installed shouldn't need the tiler on.
    ./roster
    # The editorial picks (a video player, and what opens a video), as roster
    # entries. Right after ./roster because that's all it is — a room whose
    # output is entries in the list above, plus the file types they claim.
    ./apps
    ./den
    ./displays
    ./theme
    # Split out of ./theme rather than folded into it: it's gated on its own
    # option and reads the app roster, not the wallpaper choice.
    ./theme/ports.nix
    ./hearth
    # Split out of ./hearth for the same reason ./theme/ports.nix is split out
    # of ./theme: it's gated on its own option, and what's INSTALLED in the
    # browser is a different job from theming the browser's chrome.
    ./hearth/zen.nix
    ./prowl
    ./sill
    ./collar
    ./pounce
    ./perch
    ./hush
    ./secrets
    ./snippets
  ];
}
