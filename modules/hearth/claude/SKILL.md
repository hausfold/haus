---
name: nebelhaus
description: Change this Mac's setup on a machine running the nebelhaus rice — install or remove apps, change the theme, fonts, keybindings, window management, the bar, the shell, or macOS settings. Use whenever the user asks you to change how their Mac looks or behaves, or mentions nebelhaus, haus, their host file, or ~/.config/nix. Covers finding the right nebelhaus.* option, editing the host file, applying with `haus rebuild`, and undoing with `haus rollback`.
---

# Changing a nebelhaus machine

This Mac runs **nebelhaus** — its setup is a declarative Nix configuration, not
settings clicked into System Settings. That is good news for you: every change
you make is built before it is applied, and every applied change is a generation
the user can atomically roll back. A mistake here costs one command, not an
afternoon.

It also means the usual moves are wrong. Do not edit dotfiles in `$HOME`, do not
`brew install`, do not `defaults write`. Nearly all of it would be overwritten by
the next rebuild anyway. There is exactly one file you edit.

Skill version: @riceVersion@ (matches the rice revision this machine is pinned to).

## The one file you edit

```
~/.config/nix/hosts/<hostname>/default.nix
```

That is the user's **host file** — the thin personal layer (identity, apps,
preferences) on top of the rice. `haus edit` opens it; `references/this-machine.md`
in this skill names the exact path and what is currently enabled.

Everything else in `~/.config/nix` is the scaffolding around it: `flake.nix`
pins the rice, `flake.lock` pins the revision. Both are managed by commands, not
by hand.

## The loop

1. **Orient.** Read `references/this-machine.md`, then the host file. Run
   `haus status` if the machine's freshness is relevant.
2. **Find the option.** Grep `references/options.md` in this skill. That file is
   rendered from the exact rice revision this machine is pinned to, so it is
   authoritative — if an option is not in it, it does not exist here.
3. **Edit the host file.** Smallest change that does the job; keep the file's
   existing comment style.
4. **Apply.** `haus rebuild` — it builds first and only switches if the build
   succeeded, so a broken config never reaches the running system.
5. **Verify, then hand back.** Say what should now be different and how the user
   can see it. If it is wrong, `haus rollback`.

## Rules

**Never invent an option name.** If `references/options.md` does not list it,
it is not settable on this revision. Say so, and offer `haus update` — the
option may exist upstream and simply be newer than this machine's pin.

**Never hand-edit `flake.lock`, `flake.nix`, or anything under `/nix/store`.**
Pulling a newer rice is `haus update`, which bumps the pin and rebuilds in one
step. The store is read-only by design.

**Never edit the rice itself.** The `nebelhaus.*` options are the entire supported
surface. If the user wants something the options cannot express, say that plainly —
it is a change to the rice (a different repo, upstream), not to their machine.

For a value, prefer `haus set <path> <value>`: it writes an ordinary
module under `hosts/<host>/settings/`, type-checks it, and rebuilds. It takes as
many `<path> <value>` PAIRS as you need and applies them all-or-nothing in ONE
rebuild — so an intent that spans two options (light mode is `theme.flavor` plus
`theme.systemAppearance`) is one command, not two rebuilds with the machine
half-switched in between. Reach for the host file when the change is structural,
not merely multi-valued. `haus get
[path]` reads the declared result, `haus unset <path>` writes null for a nullable
option, and `haus reset <path>` removes the machine override so the host, preset,
or rice value wins again. The commands only accept `nebelhaus.*` paths (the
`nebelhaus.` prefix may be omitted). Edit the host file directly when the change
is structural or needs several related definitions in one module.

**Ask before touching identity or secrets.** `nebelhaus.git.*`, signing keys,
anything under `nebelhaus.secrets.*`, and the pounce signing identity are the
user's, not yours.

**Prefer a `nebelhaus.*` option to a raw nix-darwin setting.** Both work — the
host file is an ordinary nix-darwin module — but the rice's options are the ones
that are documented, checked, and safe. Reach for `system.defaults.*` or
`homebrew.*` directly only when nothing in `nebelhaus.*` covers it, and say that
you did.

## After a successful rebuild

`~/.config/nix` is a git repo — the user's machine in text. `haus set` stages its
one generated module because flakes ignore untracked files. Offer to commit the
change with a message naming what it does. Don't push unless asked.

## When `haus rebuild` refuses

If `haus rebuild` stops with a Full Disk Access message, **do not work around it
and do not retry.** The config sets `system.defaults.universalaccess.*`, a
TCC-protected domain that can only be written by an app holding Full Disk Access.
That grant belongs to whichever app is responsible for the session — this one
doesn't have it, though the user's own terminal very likely does. Worse, when the
write fails it fails mid-activation and aborts the rest, skipping every
background service the rice installs, with a symptom nowhere near the cause.

So: tell the user to run `haus rebuild` themselves in their terminal. The edit is
already written; nothing is lost. (`nebelhaus.accessibility.*` reaches the useful
keys in that domain without the hazard — prefer it if the goal is contrast or
motion, and mention that to the user.)

## What a rollback does and doesn't undo

`haus rollback` returns to the previous generation instantly and atomically. It
rewinds **everything Nix manages**: packages, services, shell config, PATH,
dotfiles the rice writes.

It does **not** rewind:

- **macOS system settings** the rebuild wrote (Dock, keyboard, Finder…). Those
  persist. Reverting them means setting the option back and rebuilding again;
  changing it by hand in System Settings; or, if the user ran `haus capture`
  before the rebuild that changed them, `haus revert-settings` puts the exact
  captured values back. `haus diff` shows what's currently declared vs what
  macOS actually has (effective state, not just the plist) if it's unclear
  what changed at all.
- **Homebrew casks.** They live outside Nix generations entirely.

Say which kind of change you are about to make, so the user knows whether a
rollback will actually undo it.

## The Homebrew trap

Removing an app from `nebelhaus.roster` (or `homebrew.casks`) stops nebelhaus from
*managing* it — it does **not** uninstall it. The app stays on disk. Tell the
user the extra step: `brew uninstall --zap <cask>`.

## When you need more than this skill

- `haus doctor` — health check. Run it before blaming your own change for
  something being broken.
- `haus generations` / `haus rollback [N]` — the undo history.
- <https://nebelhaus.com> — guides and reference. Note it documents the **latest**
  rice; this machine is pinned to a specific revision, so it can describe options
  that are not in `references/options.md` yet. When they disagree, this skill's
  reference wins for what is settable *right now*.

## Files in this skill

| File | What it is |
|---|---|
| `references/options.md` | Every `nebelhaus.*` option on this machine's revision — generated, authoritative. Grep it. |
| `references/recipes.md` | Worked examples for the common asks (install an app, change the theme, resize the UI…). |
| `references/this-machine.md` | This host: name, paths, which rooms are enabled. |
| `consumer-AGENTS.md` | A starter `AGENTS.md` for `~/.config/nix` — the rules themselves, read by Codex, OpenCode, Cursor, Copilot and anything else that speaks agents.md. |
| `consumer-CLAUDE.md` | Its `@AGENTS.md` pointer, for the one client that reads only `CLAUDE.md`. If that repo has neither file, offer to copy **both** in — copying one alone orients only some of the clients that might open a session there. Copy with `install -m 644`, not `cp`: these are Nix store files (`r--r--r--`), and `cp` hands the user a starter they can't edit. |
