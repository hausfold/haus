# Recipes — the common asks, worked

Every edit below goes in the host file (`~/.config/nix/hosts/<hostname>/default.nix`)
and is applied with `haus rebuild`. Check the option in `options.md` before using
it: this file is hand-written, so it shows the *shape* of a change, while
`options.md` is generated from this machine's own pin and is the authority on
what exists and what values are allowed.

---

## "Install Slack" / "get me Figma"

Add an entry to the app roster rather than running `brew install` or reaching
for `homebrew.casks` — one entry gives the app its launcher key AND installs
it.

```nix
haus.roster.slack = {
  name = "Slack";      # the .app name, for launching
  cask = "slack";      # Homebrew cask — omit if the app is already installed
  key = "s";           # leader → s launches it
  appId = "com.tinyspeck.slackmacgap";  # osascript -e 'id of app "Slack"'
};
```

Pick a `key` that isn't already taken — read the existing `haus.roster.*` in
the host file first. If the app is already on the machine, leave the source
fields unset; the entry is then just metadata.

**A workspace + bar pill is a separate claim, made BY the workspace, not the
app** (so several apps can share one — a "comms" workspace holding Slack, Mail
and Messages):

```nix
haus.workspaces.S = {
  key = "s";                      # leader ⇧s throws + follows; ⌥⇧s throws + stays
  icon = ":slack:";               # falls back to the workspace id ("S")
  apps = [ "slack" ];             # roster ids that herd here — needs appId set
};
```

Omit the whole `haus.workspaces` entry for a launcher-only app (opens in
whatever workspace you're already on, no pill, no dedicated throw).

**Everything installable goes here, not only launcher apps.** Omit `key` and the
entry claims no leader letter, no cheatsheet row and no pill — it is simply
installed. That is what keeps this one list instead of two:

```nix
haus.roster = {
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
free; `haus.appStore.install = true` makes a rebuild fetch it. That can
only ever be half-automatic — `mas` cannot sign in, and cannot make a first-time
purchase — so buy a paid app once in App Store.app; free ones it fetches itself.

```nix
haus.roster.xcode = { name = "Xcode"; appStoreId = 497799835; };
```

## "Uninstall it" / "I don't use that any more"

```nix
haus.roster.slack.enable = false;
```

That un-declares it: the launcher key, the pill and the cask entry go away. **The
app itself stays on disk** — haus never deletes apps behind your back
(`haus.homebrew.cleanup` defaults to `"none"`). Tell the user the second step:

```sh
brew uninstall --zap slack
```

## "Videos open in the wrong app" / "I don't want IINA"

haus ships IINA as the video player and hands it the video types macOS gives
QuickTime, TV and your browser. Both halves are switches:

```nix
haus.apps.videoPlayer.enable = false;          # don't install it at all
haus.apps.videoPlayer.claimFileTypes = false;  # install it, touch no associations
```

The associations are the ordinary user default (what Finder's Get Info ▸ Change
All writes), so a rebuild with `claimFileTypes = false` stops re-applying them
but does not put the old handler back — the user picks one once, in Finder.

Only the everyday extensions are claimed (mp4, m4v, mov, mpg, mpeg, mkv, webm,
avi, wmv, flv, 3gp, ogv, vob). Audio, `.gif`, playlists and the transport-stream
trio `.ts`/`.mts`/`.m2ts` are never touched — the last three belong to the
editor hijack, and letting IINA claim them too made macOS ask which app should
win on every rebuild. To give a *different* player the same treatment, turn this
off and add your own roster entry.

## "Everything is too small"

One number moves the whole interface:

```nix
haus.ui.scale = 1.35;
```

It sets *defaults*, so anything pinned by hand still wins — if the host file also
sets `haus.fonts.mono.size`, the terminal keeps that size. Read the option's
description in `options.md`: it lists exactly what scale does and doesn't move.

For a genuinely large-print machine, say that instead of tuning `ui.scale` by
hand — it also lifts the palette's contrast, macOS's own contrast setting and the
screen's scaled resolution, which is the only lever that reaches apps haus never
installed:

```nix
haus.appearance.largePrint = true;
```

An ordinary host line, no `flake.nix` edit. It sets defaults too, so any single
value pinned in the host still wins.

## "Switch to light mode"

```nix
haus.theme.flavor = "latte";            # "mocha" is the dark default
haus.theme.systemAppearance = "flavor"; # …and move macOS itself with it
```

Suggest both lines together. The first recolours the tools haus themes; the
second moves System Settings ▸ Appearance, which haus leaves alone by
default — without it a light desktop looks half-done on a dark Mac.

## "Change the accent colour"

```nix
haus.theme.accent = "sapphire";
```

The value must be one of the fourteen Catppuccin names — `options.md` lists them.
Note the honest scope in that option's description: it recolours the tools
haus injects colour into, not literally everything.

## "Use a different terminal font"

Set the name **and** the package, or the family won't exist on the machine and
Ghostty falls back silently:

```nix
haus.fonts.mono.name = "FiraCode Nerd Font";
haus.fonts.mono.package = pkgs.nerd-fonts.fira-code;
```

`pkgs` must be in scope — if the host file's header is `{ ... }:`, change it to
`{ pkgs, ... }:`.

## "Turn off the bar / the tiling / the palette"

Each room is one switch:

```nix
haus.bar.enable = false;      # the menu bar
haus.windows.enable = false;     # window tiling
haus.launcher.enable = false;    # the command palette
```

## "Show the battery in the bar" / "hide the weather"

The bar's pills are individual booleans under `haus.bar.items.*` — the full
list is in `options.md`:

```nix
haus.bar.items.battery = true;
haus.bar.items.weather = false;
```

## "Bind a key to run this"

To launch an app, use `haus.roster` (above). For anything else — a script, a
URL, an AppleScript — use a leader extra:

```nix
haus.keys.leaderExtras = [
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
haus.snippets.enable = true;
haus.snippets.matches = [
  { trigger = "@@"; replace = "ada@example.com"; }
];
```

## "My dev servers keep fighting over port 3000"

```nix
haus.portless.enable = true;
```

Every dev server gets a name instead of a number — `https://myapp.localhost`,
real HTTPS, no port suffix. One proxy on :443 hands out the ports, so two
projects that both default to 3000 stop colliding and a restarted server keeps
the browser tab you already had open.

The reason it is worth turning on even for one project is agent lanes. `holt`
puts several agents in several worktrees of the SAME repo, so several copies of
the same `npm run dev` want the same port; the second one dies, or quietly takes
the next number while every hardcoded URL still points at the first. With this
on, each lane gets its own hostname: run `portless-lane` in a lane instead of
`npm run dev` and it serves at `<lane>.<repo>.localhost` — `wiggly-crane.haus.localhost`.
Outside a lane, plain `portless` is the same thing without the renaming.

One click is needed once: `haus permissions` has a card for trusting portless'
local certificate authority, which is what stops the browser warning. haus will
not install a CA for you during a rebuild.

## "It's hard to read" / accessibility

Two different layers, and the difference matters:

```nix
haus.theme.contrast = "high";                # haus's own palette — always safe
haus.accessibility.increaseContrast = true;  # macOS's system-wide setting
```

Prefer the theme axis. The `haus.accessibility.*` options write a
TCC-protected macOS domain that needs Full Disk Access on whichever app runs the
rebuild. haus guards those writes, so a missing grant costs the setting and
nothing else — but the grant follows the app your session runs under, so they may
simply not apply when *you* are the one rebuilding. `haus doctor` reports whether
this session has it; say so rather than retrying.

Never reach past these into raw `system.defaults.universalaccess.*`. That path is
unguarded upstream: without Full Disk Access it aborts activation partway and
skips every background service haus installs. `haus rebuild` refuses outright
when the config sets it and the current app can't write it — agent or human alike,
because the grant follows the app and not the person. Every key in that domain
measured to take effect has a `haus.accessibility.*` option, so the guarded route
costs nothing worth having — and since 2026-08-14 that includes cursor size and
the closeView pair, which were watched working by hand and promoted. The raw form
now reaches strictly less than the options do. (Those three need a
`universalaccessd` restart to be visible at all; haus fires it for whichever
route wrote them, which is more than nix-darwin does on its own.)

## "Update everything"

```sh
haus update      # bump the haus pin, refresh the family apps, rebuild
```

Never a hand edit of `flake.lock`. Afterwards this skill is regenerated from the
new revision, so re-read `options.md` before using anything new.

---

## When nothing fits

The host file is an ordinary nix-darwin module, so raw settings work:

```nix
system.defaults.dock.autohide = true;
homebrew.casks = [ "some-cask" ];   # but for an APP, use haus.roster
```

Do that only when no `haus.*` option covers the request, and say that you
did — haus's options are the surface that's documented, checked, and carried
across upgrades. If the user is asking for something haus *should* express as
an option, name it: that's a change upstream, not something to bolt onto their
machine.
