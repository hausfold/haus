# Recipes — the common asks, worked

Every edit below goes in the host file (`~/.config/nix/hosts/<hostname>/default.nix`)
and is applied with `haus rebuild`. Check the option in `options.md` before using
it: this file is hand-written, so it shows the *shape* of a change, while
`options.md` is generated from this machine's own rice and is the authority on
what exists and what values are allowed.

---

## "Install Slack" / "get me Figma"

Add an entry to the app roster rather than running `brew install` or reaching
for `homebrew.casks` — one entry gives the app its launcher key, its workspace,
its bar pill AND installs it.

```nix
nebelhaus.roster.slack = {
  name = "Slack";      # the .app name, for launching
  cask = "slack";      # Homebrew cask — omit if the app is already installed
  key = "s";           # leader → s launches it
  workspace = "S";     # the tiling workspace it owns (omit for launcher-only)
};
```

Pick a `key` that isn't already taken — read the existing `nebelhaus.roster.*` in
the host file first. If the app is already on the machine, leave the source
fields unset; the entry is then just metadata.

**Everything installable goes here, not only launcher apps.** Omit `key` and the
entry claims no leader letter, no cheatsheet row and no pill — it is simply
installed. That is what keeps this one list instead of two:

```nix
nebelhaus.roster = {
  framer     = { name = "Framer"; cask = "framer"; };   # app, no hotkey
  ical-buddy = { brew = "ical-buddy"; };                # a formula, no .app
  orbstack   = { name = "OrbStack"; package = pkgs.orbstack; };
  ripgrep    = { package = pkgs.ripgrep; scope = "system"; };
};
```

`scope` only applies to `package`: `"user"` (default) is home-manager's
`home.packages`; `"system"` is `environment.systemPackages`, which is what a
tool needs to be on PATH for root, launchd jobs and non-login shells.

App Store apps take `appStoreId` (the digits in the store URL). Recording it is
free; `nebelhaus.appStore.install = true` makes a rebuild fetch it. That can
only ever be half-automatic — `mas` cannot sign in, and cannot make a first-time
purchase — so buy a paid app once in App Store.app; free ones it fetches itself.

```nix
nebelhaus.roster.xcode = { name = "Xcode"; appStoreId = 497799835; };
```

## "Uninstall it" / "I don't use that any more"

```nix
nebelhaus.roster.slack.enable = false;
```

That un-declares it: the launcher key, the pill and the cask entry go away. **The
app itself stays on disk** — nebelhaus never deletes apps behind your back
(`nebelhaus.homebrew.cleanup` defaults to `"none"`). Tell the user the second step:

```sh
brew uninstall --zap slack
```

## "Everything is too small"

One number moves the whole interface:

```nix
nebelhaus.ui.scale = 1.35;
```

It sets *defaults*, so anything pinned by hand still wins — if the host file also
sets `nebelhaus.fonts.mono.size`, the terminal keeps that size. Read the option's
description in `options.md`: it lists exactly what scale does and doesn't move.

For a genuinely large-print machine the rice ships a preset (`large-print`), but
it's imported in `flake.nix` via `extraModules`, so suggest it rather than
editing `flake.nix` unprompted.

## "Switch to light mode"

```nix
nebelhaus.theme.flavor = "latte";   # "mocha" is the dark default
```

## "Change the accent colour"

```nix
nebelhaus.theme.accent = "sapphire";
```

The value must be one of the fourteen Catppuccin names — `options.md` lists them.
Note the honest scope in that option's description: it recolours the tools the
rice injects colour into, not literally everything.

## "Use a different terminal font"

Set the name **and** the package, or the family won't exist on the machine and
Ghostty falls back silently:

```nix
nebelhaus.fonts.mono.name = "FiraCode Nerd Font";
nebelhaus.fonts.mono.package = pkgs.nerd-fonts.fira-code;
```

`pkgs` must be in scope — if the host file's header is `{ ... }:`, change it to
`{ pkgs, ... }:`.

## "Turn off the bar / the tiling / the palette"

Each room is one switch:

```nix
nebelhaus.sill.enable = false;      # the menu bar
nebelhaus.prowl.enable = false;     # window tiling
nebelhaus.pounce.enable = false;    # the command palette
```

## "Show the battery in the bar" / "hide the weather"

The bar's pills are individual booleans under `nebelhaus.sill.items.*` — the full
list is in `options.md`:

```nix
nebelhaus.sill.items.battery = true;
nebelhaus.sill.items.weather = false;
```

## "Bind a key to run this"

To launch an app, use `nebelhaus.roster` (above). For anything else — a script, a
URL, an AppleScript — use a leader extra:

```nix
nebelhaus.keys.leaderExtras = [
  {
    key = "n";
    command = "open -a Notes";
    caption = "Notes";      # shown in the cheatsheet
  }
];
```

It's a list, so if the host file already sets `leaderExtras`, add to that list
rather than writing a second assignment — two assignments to the same list option
conflict, and the build will tell you so.

## "Expand @@ to my email"

```nix
nebelhaus.snippets.enable = true;
nebelhaus.snippets.matches = [
  { trigger = "@@"; replace = "ada@example.com"; }
];
```

## "It's hard to read" / accessibility

Two different layers, and the difference matters:

```nix
nebelhaus.theme.contrast = "high";                # the rice's own palette — always safe
nebelhaus.accessibility.increaseContrast = true;  # macOS's system-wide setting
```

Prefer the theme axis. The `nebelhaus.accessibility.*` options write a
TCC-protected macOS domain that needs Full Disk Access on whichever app runs the
rebuild. The rice guards those writes, so a missing grant costs the setting and
nothing else — but the grant follows the app your session runs under, so they may
simply not apply when *you* are the one rebuilding. `haus doctor` reports whether
this session has it; say so rather than retrying.

Never reach past these into raw `system.defaults.universalaccess.*`. That path is
unguarded upstream: without Full Disk Access it aborts activation partway and
skips every background service the rice installs. `haus rebuild` refuses to run
under an agent when the config sets it.

## "Update everything"

```sh
haus update      # bump the rice pin, refresh the family apps, rebuild
```

Never a hand edit of `flake.lock`. Afterwards this skill is regenerated from the
new revision, so re-read `options.md` before using anything new.

---

## When nothing fits

The host file is an ordinary nix-darwin module, so raw settings work:

```nix
system.defaults.dock.autohide = true;
homebrew.casks = [ "some-cask" ];   # but for an APP, use nebelhaus.roster
```

Do that only when no `nebelhaus.*` option covers the request, and say that you
did — the rice's options are the surface that's documented, checked, and carried
across upgrades. If the user is asking for something the rice *should* express as
an option, name it: that's a change upstream, not something to bolt onto their
machine.
