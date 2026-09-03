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

```sh
curl -fsSL https://hausfold.co/haus.sh | bash
```

That asks which desktop you want, puts the prerequisites in place, and
scaffolds a thin config of your own at `~/.config/nix`. You never edit this repo
to use it.

## the manual

📖 **[hausfold.co/docs/haus](https://hausfold.co/docs/haus/)** — and it only
lives there: [installing](https://hausfold.co/docs/haus/install/),
[choosing a desktop](https://hausfold.co/docs/haus/desktops/choosing/),
[what each room does](https://hausfold.co/docs/haus/),
[every `haus` command](https://hausfold.co/docs/haus/reference/haus/),
[every option](https://hausfold.co/docs/haus/reference/options/),
[keeping it current](https://hausfold.co/docs/haus/keeping-it-current/) and
[leaving](https://hausfold.co/docs/haus/leaving/).

Taking one room into a flake of your own — the tiling, the bar — is
[how the flakes fit together](https://hausfold.co/docs/haus/internals/flakes/).
Changing your Mac by asking an agent is
[the AI room](https://hausfold.co/docs/haus/rooms/ai/).

## in this repo

- [`AGENTS.md`](./AGENTS.md) — hacking on the house
- [`docs/model.md`](docs/model.md) — the contract the modules are written against: layer, room, desktop, host, and what each one may own
- [`docs/macos-settings.md`](docs/macos-settings.md) — what a desktop can actually set, measured domain by domain
- [`docs/focus.md`](docs/focus.md) — how the focus room flips a real macOS Focus with no public API, and what it deliberately won't do
- [`docs/night-shift-internals.md`](docs/night-shift-internals.md) — the seams an unattended merge shift leans on here, none of them visible from the shift's own side: why the `always` lid hold draws nothing, the fixer-lane endings that leave no record, the nine-column usage feed it meters against, and what a night puts on screen. The operator half is [hausfold.co/docs/haus/night-shift](https://hausfold.co/docs/haus/night-shift)

---

<p align="center"><a href="https://hausfold.co">⌂ hausfold</a></p>
