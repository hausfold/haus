# The whole house. Import this for the full rice, or import individual rooms
# (den / prowl / sill / collar / pounce / perch / hush / secrets) from
# `darwinModules` in the flake.
{
  imports = [
    # Options first, one file per room, each living next to the code that
    # implements it. They're listed separately from the rooms rather than
    # imported by them because several rooms wrap their whole body in
    # `lib.mkIf <room>.enable` — an option declared inside that would vanish
    # exactly when it's needed to decide the condition. modules/options.nix
    # keeps only what no single room owns: the shared app roster.
    ./options.nix
    ./apps/options.nix
    ./den/options.nix
    ./displays/options.nix
    ./theme/options.nix
    ./hearth/options.nix
    ./prowl/options.nix
    ./sill/options.nix
    ./collar/options.nix
    ./pounce/options.nix
    ./perch/options.nix
    ./hush/options.nix
    ./secrets/options.nix
    ./snippets/options.nix

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
