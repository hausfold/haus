# Thanks

## Founding testers

The people who ran haus before it was public, on their own machines, with no
help from me while they did it. Each one chose how they appear here, and the
order is the order they reported in. It stays that way.

*The early alpha hasn't started yet. This is where the list goes.*

What a founding tester gets, and the limits on it, are written down once:
[FOUNDING.md](https://github.com/hausfold/workshop/blob/main/FOUNDING.md).

## Standing on

haus is a thin layer over other people's work. It decides what a Mac should
look like. Almost nothing underneath it is ours.

### The foundation

| | |
|---|---|
| [Nix and nixpkgs](https://github.com/NixOS/nixpkgs) | The package set, and the reason a Mac can be described in a file at all |
| [nix-darwin](https://github.com/LnL7/nix-darwin) | Every `haus.*` option becomes a nix-darwin option, and `haus rebuild` is a `darwin-rebuild` underneath. The generation you roll back to is one of theirs |
| [home-manager](https://github.com/nix-community/home-manager) | Everything that lands in your home directory |
| [Determinate Nix](https://determinate.systems) | The Nix the install one-liner puts on the machine |
| [Homebrew](https://brew.sh) | The Mac apps that have to be real bundles in `/Applications` |

### The desktop

| | |
|---|---|
| [AeroSpace](https://github.com/nikitabobko/AeroSpace) | The tiler. `haus.windows` is mostly a generated `aerospace.toml` |
| [SketchyBar](https://github.com/FelixKratz/SketchyBar) | Both bars, top and bottom, and every widget on them |
| [Ghostty](https://ghostty.org) | The terminal |
| [espanso](https://espanso.org) | Text expansion |
| [Catppuccin](https://catppuccin.com) and [whiskers](https://whiskers.catppuccin.com) | [nebelung](https://github.com/hausfold/nebelung) is a Catppuccin flavor rendered through Catppuccin's own templates. Every themed file here is a Catppuccin port with our grey in it |

### The shell, and the small things that do real work

[zellij](https://zellij.dev) and [zmx](https://github.com/neurosnap/zmx) hold the
sessions your windows outlive. [starship](https://starship.rs),
[fzf](https://github.com/junegunn/fzf), [zoxide](https://github.com/ajeetdsouza/zoxide),
[bat](https://github.com/sharkdp/bat), [ripgrep](https://github.com/BurntSushi/ripgrep),
[jq](https://jqlang.github.io/jq/) and [glow](https://github.com/charmbracelet/glow)
are in the shell you get. [duti](https://github.com/moretension/duti) is how a
desktop claims a file type, [sleepwatcher](https://www.bernhard-baehr.de/) is how
the lid gets noticed, and
[switchaudio-osx](https://github.com/deweller/switchaudio-osx) is how the audio
row in the palette switches anything at all.

None of these projects know we exist. If you find haus useful, some of that
belongs upstream.
