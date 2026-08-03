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
  inputs.nebelhaus.url = "github:nebelhaus/nebelhaus";

  # in your darwinSystem modules list:
  modules = [
    inputs.nebelhaus.darwinModules.prowl   # just the tiling
    inputs.nebelhaus.darwinModules.sill    # just the bar
    { nixpkgs.hostPlatform = "aarch64-darwin"; }  # rooms don't pick a platform for you
  ];
}
```

**theme, trill, perch, snippets and apps aren't standalone modules** — they ride
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

- **pounce signing** — set `nebelhaus.pounce.signingIdentity` to an Apple
  Development identity's SHA-1 (`security find-identity -v -p codesigning`) so
  the palette's Accessibility grant survives rebuilds. Leave empty to run
  unsigned. See the [pounce README](https://github.com/nebelhaus/pounce) for the
  one-time accessibility approval.

- **git / GPG / YubiKey** — commit signing is configured in your host's
  home-manager block; key material and any smartcard/YubiKey setup live outside
  Nix (gpg-agent + pinentry-mac).

- **trill / perch** — `nebelhaus.trill.enable` and `nebelhaus.perch.enable`
  install through Nix via their flake inputs and copy to fixed
  `/Applications/Trill.app` and `/Applications/Perch.app` paths.

- **hush** — `nebelhaus.hush.*` for the Focus/DND hotkey, Slack status, and
  shell hooks.

- **theme** — `nebelhaus.theme.accent` and `nebelhaus.theme.wallpaper`.

The full option list is [Making it
yours](https://nebelhaus.com/guides/making-it-yours/) and
[Options reference](https://nebelhaus.com/reference/options/) on nebelhaus.com.

## New to the parts?

[AeroSpace](https://github.com/nikitabobko/AeroSpace) is a tiling window manager
for macOS — windows arrange themselves, keyboard moves them.
[SketchyBar](https://github.com/FelixKratz/SketchyBar) replaces the menu bar.
[Nix](https://nixos.org) makes the whole setup reproducible: the entire machine
is described in text files, and one command makes reality match them.

## Hacking on the house

This repo is one of a family. The
[workshop](https://github.com/nebelhaus/workshop) checks them all out side by
side and ships a `bench` CLI for the cross-repo flow — most usefully `bench try`,
which builds your real machine against your **local, uncommitted** checkouts, so
you never push to find out whether something works.

Iterating on a **zellij** edit (a keybind in `config.kdl`, a theme colour, a
freshly-built plugin `.wasm`) is even lighter: `zscratch` — a dev CLI shipped in
this repo's `modules/den` — boots your candidate in a throwaway session in its
own Ghostty window, so you feel the change without a rebuild or losing your
working session's tabs. `bench try switch` does the real activation once, at the
end. See [`AGENTS.md`](../AGENTS.md) for the full flag set.
