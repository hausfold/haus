# Thanks

## Founding testers

The people who run haus before it is public, on their own machines, with no
help from me while they do it. Each one chooses how they appear here, and the
order is the order they report in. It stays that way.

*The early alpha hasn't started yet.*

What a founding tester gets, and the limits on it, are written down once:
[FOUNDING.md](https://github.com/hausfold/workshop/blob/main/FOUNDING.md).

## Standing on

haus is a thin layer over other people's work. It decides what a Mac should
look like. Almost nothing underneath it is ours.

### The foundation

| | |
|---|---|
| [Nix and nixpkgs](https://github.com/NixOS/nixpkgs) | The package set, and the reason a Mac can be described in a file at all |
| [nix-darwin](https://github.com/LnL7/nix-darwin) | Every `haus.*` option becomes a nix-darwin option, and the generation `haus rollback` returns to is one of theirs |
| [home-manager](https://github.com/nix-community/home-manager) | Everything that lands in your home directory |
| [Determinate Nix](https://determinate.systems) | The Nix the install one-liner puts on the machine |
| [Homebrew](https://brew.sh) | The Mac apps that have to be real bundles in `/Applications` |
| [nix-index-database](https://github.com/nix-community/nix-index-database) | A prebuilt index, so `comma` can run something you haven't installed |

### The desktop

| | |
|---|---|
| [AeroSpace](https://github.com/nikitabobko/AeroSpace) | The tiler. `haus.windows` mostly comes out as an `aerospace.toml` |
| [SketchyBar](https://github.com/FelixKratz/SketchyBar) | Both bars, top and bottom, and every widget on them |
| [sketchybar-app-font](https://github.com/kvndrsslr/sketchybar-app-font) | A different project by a different author, and where the workspace logos and the palette's app icons come from |
| [media-control](https://github.com/ungive/media-control) and [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) | The only way left to read macOS's system-wide now-playing after Apple locked MediaRemote down in 15.4. Without these the media pill is dark, and there is no public API to fall back on |
| [Ghostty](https://ghostty.org) | The terminal |
| [Nerd Fonts](https://www.nerdfonts.com) | Load-bearing, not decoration: starship's prompt, lsd's icons and yazi all draw with patched glyphs that a stock font renders as tofu |
| [espanso](https://espanso.org) | Text expansion |
| [Catppuccin](https://catppuccin.com) and [whiskers](https://whiskers.catppuccin.com) | [nebelung](https://github.com/hausfold/nebelung) is a Catppuccin flavor. Most of what's themed here is a Catppuccin port with our grey in it, the exceptions being the places haus resolves nebelung's keys itself, like the bar's tone ladder |

### The shell, and the small things that each carry a room

The toolbelt haus's shell is built around is other people's work end to end:
[bat](https://github.com/sharkdp/bat), [fzf](https://github.com/junegunn/fzf),
[fd](https://github.com/sharkdp/fd),
[ripgrep](https://github.com/BurntSushi/ripgrep),
[yazi](https://github.com/sxyazi/yazi), [zoxide](https://github.com/ajeetdsouza/zoxide),
[lsd](https://github.com/lsd-rs/lsd), [glow](https://github.com/charmbracelet/glow),
[jq](https://jqlang.github.io/jq/), [tree](https://oldmanprogrammer.net/source.php?dir=projects/tree),
[chafa](https://hpjansson.org/chafa/), [ttyd](https://github.com/tsl0922/ttyd)
and [fastfetch](https://github.com/fastfetch-cli/fastfetch), with
[starship](https://starship.rs) drawing the prompt.

Then four that each carry a room on their own.
[zmx](https://github.com/neurosnap/zmx) holds the sessions your windows
outlive, which is why closing one never loses an agent.
[sleepwatcher](https://www.bernhard-baehr.de/) is how a wake gets noticed, so
your windows go back on the workspaces they were assigned to.
[switchaudio-osx](https://github.com/deweller/switchaudio-osx) is how a focus
scene picks your microphone. And [duti](https://github.com/moretension/duti)
pins the file-type defaults once the editor-opener app has declared those types
itself, which is the half LaunchServices will actually honour.

None of these projects asked to be part of this. If you find haus useful, some
of that belongs upstream.
