# ⌂ haus

**One flake raises the whole Mac.**

<sub>**pre-release** · Nothing here changes your Mac without a way back: every rebuild is a Nix generation `haus rollback` returns to, and macOS's own settings — the one thing a rollback can't reach — are what `haus capture` and `haus revert-settings` are for. That's the intent, not a warranty: run it on a machine you can afford to rebuild, and tell us what breaks.</sub>

---

Tiling windows, a status bar, a ⌘Space palette, the terminal, Touch ID for
`sudo`, and every app you actually use — declared in one file, applied by one
command, native to the grain of the Mac rather than a Linux desktop bolted onto
it. Wipe the machine, run one line, and the house stands again exactly as it
was, down to the [fog-grey](https://github.com/hausfold/nebelung).

**`haus`** is the layer: nix-darwin modules, the `haus.*` options you set, the
`haus` CLI you run. A **desktop** is one complete set of answers to those
options. **hacker** is the first desktop — grey, quiet, developer-shaped.
This repo ships both; **hausfold** is the org that makes them, which is why the
repo is `hausfold/haus`.

📖 [hausfold.co/haus](https://hausfold.co/haus/) — what it is, and the [docs](https://hausfold.co/docs/haus/): [installing](https://hausfold.co/docs/haus/install/), the rooms, and [pounce](https://hausfold.co/docs/pounce/), the palette

## install

```sh
curl -fsSL https://hausfold.co/haus.sh | bash
```

That asks which desktop you want. Swapping the URL answers it instead:

| | |
|---|---|
| `curl -fsSL https://hausfold.co/hacker.sh \| bash` | the whole house — tiling, bar, palette, shelf, agents |
| `curl -fsSL https://hausfold.co/everyday.sh \| bash` | a Mac for someone who doesn't write code |
| `curl -fsSL https://hausfold.co/minimal.sh \| bash` | just the themed shell, on otherwise stock macOS |

Already have Nix? `nix run github:hausfold/haus#bootstrap -- --desktop=minimal`.
→ [choosing a desktop](https://hausfold.co/docs/haus/desktops/choosing/)

The installer puts the prerequisites in place (Xcode CLT, Determinate Nix), then
scaffolds a **thin config of your own** at `~/.config/nix`: an ~18-line flake
consuming this repo, plus one host file for what's personal — git identity,
signing keys, secrets, your private apps. You never edit this repo to use it.

Beside it lands `hosts/<host>/options.nix` — **every `haus.*` option there is, at
its default, with its type and a docs link, all commented out.** You discover
options by reading your own config, and it's rendered from the revision you
pinned, so it can't offer you one you don't have.

## the CLI

```sh
haus rebuild                # build, then switch — a bad edit never reaches the running system
haus update                 # pull the latest haus and its apps, then rebuild
haus rollback               # back one generation, atomically
haus edit                   # open your host file
haus options                # re-render that catalogue against the revision you're on
haus set                    # search every option this Mac has, then pick the value
haus set theme.accent teal  # or say it outright: type-checked, then one rebuild
haus plan                   # what the next rebuild would change, without building it
haus diff                   # what you declared vs what macOS actually has right now
haus doctor                 # Nix, the CLT, the GUI agents, Homebrew drift
```

→ [every command](https://hausfold.co/docs/haus/reference/haus/) · [every option](https://hausfold.co/docs/haus/reference/options/)

## the rooms

Twelve capabilities, each a switch: **Apps · Appearance · Displays ·
Development · Windows · Bar · Launcher · Shelf · Focus · AI · Text expansion ·
Security**. Your desktop decides which are on; one line in your host overrules
it. Six of them are also exported as standalone nix-darwin modules, so you can
take the tiling or the bar into a flake of your own and leave the house behind.

→ [what each room does](https://hausfold.co/docs/haus/) · [stealing one](docs/modules.md)

## ask an agent to change it

A declarative machine is the one kind an agent can safely reconfigure — the
rebuild builds before it switches, so a bad edit never reaches the running
system. What was missing was knowledge: left to guess, a model reaches for `brew
install` and dotfiles the next rebuild overwrites.

So the layer ships it. `haus.ai.skill` writes a skill for every hausfold tool
on the machine into the directory each client you named actually reads
(`~/.claude/skills/…`, `~/.codex/skills/…`, `~/.config/opencode/skills/…`).
The `haus` one carries an option reference **generated from the revision you're
pinned to**, so it can only describe options you have — "install Slack" or "make
everything bigger" becomes an edit to your host file, applied and verifiable.
Beside it, `holt` and `handoff` come from holt: "what worktrees do I have open?"
and "hand this off to a fresh session" work without you wiring anything.
→ [coding agents](https://hausfold.co/docs/haus/rooms/ai/)

## more

- [Modules](docs/modules.md) — one room in your own flake, `mkHaus`, the identity knobs
- [Making it yours](https://hausfold.co/docs/haus/desktops/customizing/) · [Keeping it current](https://hausfold.co/docs/haus/keeping-it-current/) · [Leaving](https://hausfold.co/docs/haus/leaving/)
- [`AGENTS.md`](./AGENTS.md) — hacking on the house

---

<p align="center"><a href="https://hausfold.co">⌂ hausfold</a></p>
