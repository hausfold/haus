# nebelhaus modules

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

Most rooms are exported as a `darwinModule` — den, hearth, prowl, sill, collar,
pounce, hush, secrets. Pull just what you want into your own flake:

```nix
{
  inputs.nebelhaus.url = "github:hausfold/haus";

  # in your darwinSystem modules list:
  modules = [
    inputs.nebelhaus.darwinModules.prowl   # just the tiling
    inputs.nebelhaus.darwinModules.sill    # just the bar
    { nixpkgs.hostPlatform = "aarch64-darwin"; }  # rooms don't pick a platform for you
  ];
}
```

**theme, wallpaper, perch, snippets and apps aren't standalone modules** — they ride
along with the full `mkNebelhaus` house. (apps needs the roster resolver next to
it to install anything, which is the same reason the roster isn't exported
either.)

## Or take the whole house

```nix
darwinConfigurations.mymac = inputs.nebelhaus.mkNebelhaus {
  username = "ada";
  hostname = "mymac";
  host = ./hosts/mymac;
};
```

## Identity knobs

- **pounce signing** — set `haus.pounce.signingIdentity` to a codesigning
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

- **perch** — `haus.perch.enable` installs through Nix via its flake
  input and copies to a fixed `/Applications/Perch.app` path.

- **hush** — `haus.hush.*` for the Focus/DND hotkey, Slack status, and
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

Iterating on a **zellij** edit splits in two. A `config.kdl` change (a keybind, a
theme colour, an option) needs nothing special — `bench try switch`, and zellij's
own config watcher applies it to the running server in about a second, tabs and
panes intact, because hearth installs that file with a live mtime rather than as
a store symlink. A plugin `.wasm`, a patched zellij binary, or a layout change to
a tab that already exists can't hot-reload at all; for those there's `zscratch` —
a dev CLI shipped in this repo's `modules/den` — which boots your candidate in a
throwaway session in its own Ghostty window, so you feel the change without a
rebuild or losing your working session's tabs. See [`AGENTS.md`](../AGENTS.md)
for the full flag set and the mtime gotcha behind the split.
