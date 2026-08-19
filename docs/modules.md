# haus modules

How to take the whole house, or just one room.

## The full rebuild incantation

The bootstrap scaffolds `~/.config/nix` for you, but the raw command — always
build-first, so a failed build never touches the system — is:

```sh
cd ~/.config/nix
nix build .#darwinConfigurations.<hostname>.system \
  && sudo ./result/sw/bin/darwin-rebuild switch --flake .#<hostname>
```

After the first switch, `haus rebuild` does this for you.

## Steal one room

Most rooms are exported as a `darwinModule` — core, terminal, windows, bar, security,
launcher, focus, secrets. Pull just what you want into your own flake:

```nix
{
  inputs.haus.url = "github:hausfold/haus";

  # in your darwinSystem modules list:
  modules = [
    inputs.haus.darwinModules.windows   # just the tiling
    inputs.haus.darwinModules.bar       # just the bar
    { nixpkgs.hostPlatform = "aarch64-darwin"; }  # rooms don't pick a platform for you
  ];
}
```

**theme, wallpaper, shelf, snippets and apps aren't standalone modules** — they ride
along with the full `mkHaus` house. (apps needs the roster resolver next to
it to install anything, which is the same reason the roster isn't exported
either.)

## Or take the whole house

```nix
darwinConfigurations.mymac = inputs.haus.mkHaus {
  username = "ada";
  hostname = "mymac";
  host = ./hosts/mymac;
};
```

## Identity knobs

- **pounce signing** — set `haus.launcher.signingIdentity` to a codesigning
  identity's **full common name** (`security find-identity -v -p codesigning`,
  e.g. `Developer ID Application: Jane Doe (ABCDE12345)`) so the palette's
  Accessibility grant survives rebuilds. Prefer the name over a SHA-1: the
  designated requirement it produces anchors on the stable team OU, so the grant
  outlives a certificate renewal, while a hardcoded hash silently falls back to
  unsigned. Leave empty to run unsigned. See the
  [pounce README](https://github.com/hausfold/pounce) for the one-time
  accessibility approval.

- **git / GPG / YubiKey** — commit signing is configured in your host's
  home-manager block; key material and any smartcard/YubiKey setup live outside
  Nix (gpg-agent + pinentry-mac).

- **perch** — `haus.shelf.enable` installs through Nix via its flake
  input and copies to a fixed `/Applications/Perch.app` path. Its command
  line door, `perch add <path>...`, lands on `PATH` as a link into that
  bundle.

- **focus** — `haus.focus.*` for the Focus/DND hotkey, Slack status, and
  shell hooks.

- **theme** — `haus.theme.{flavor,contrast,accent,systemAppearance}`.

- **wallpaper** — `haus.wallpaper.*`: the desktop, including the generated
  `minimal` look.

The full option list is [Making it
yours](https://hausfold.co/docs/haus/desktops/customizing/) and
[Options reference](https://hausfold.co/docs/haus/reference/options/) on hausfold.co.

## New to the parts?

[AeroSpace](https://github.com/nikitabobko/AeroSpace) is a tiling window manager
for macOS — windows arrange themselves, keyboard moves them.
[SketchyBar](https://github.com/FelixKratz/SketchyBar) replaces the menu bar.
[Nix](https://nixos.org) makes the whole setup reproducible: the entire machine
is described in text files, and one command makes reality match them.

## Hacking on the house

This repo is one of a family. The
[workshop](https://github.com/hausfold/workshop) checks them all out side by
side and ships a `bench` CLI for the cross-repo flow — most usefully `bench try`,
which builds your real machine against your **local, uncommitted** checkouts, so
you never push to find out whether something works.

Iterating on a **terminal** edit needs nothing special any more: `bench try
switch`, and Ghostty's own config watcher applies the new keybinds, theme and
options to every running window in about a second. Windows, sessions and the
agents in them all stay put — a window's shell lives in a `zmx` session that
outlives the window, so even the ones that DO restart come back to the same
scrollback.

That used to be a two-branch story with a dev CLI (`zscratch`) behind the second
branch, and both halves left with zellij: a running zellij server cached plugin
wasm in memory for its whole lifetime, so a plugin edit needed a fresh server,
and its config only reloaded on a live mtime — which is why terminal had to
install `config.kdl` as a real file rather than a store symlink. Ghostty has no
plugins and watches a symlink happily.
