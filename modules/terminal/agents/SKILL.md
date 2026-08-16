---
name: haus
description: Change this Mac's setup on a machine managed by haus — the hacker desktop, or any other desktop built on it. Install or remove apps, change the theme, fonts, keybindings, window management, the bar, the shell, or macOS settings. Use whenever the user asks you to change how their Mac looks or behaves, or mentions haus, a "rice" (the older word for a desktop), their host file, or ~/.config/nix. Covers finding the right haus.* option, editing the host file, applying with `haus rebuild`, and undoing with `haus rollback`.
---

# Changing a haus machine

This Mac runs **haus** — its setup is a declarative Nix configuration, not
settings clicked into System Settings. That is good news for you: every change
you make is built before it is applied, and every applied change is a generation
the user can atomically roll back. A mistake here costs one command, not an
afternoon.

It also means the usual moves are wrong. Do not edit dotfiles in `$HOME`, do not
`brew install`, do not `defaults write`. Nearly all of it would be overwritten by
the next rebuild anyway. There is exactly one file you edit.

Skill version: @hausVersion@ (matches the haus revision this machine is pinned to).

## The one file you edit

```
~/.config/nix/hosts/<hostname>/default.nix
```

That is the user's **host file** — the thin personal layer (identity, apps,
preferences) on top of haus. `haus edit` opens it; `references/this-machine.md`
in this skill names the exact path and what is currently enabled.

Everything else in `~/.config/nix` is the scaffolding around it: `flake.nix`
pins haus, `flake.lock` pins the revision. Both are managed by commands, not
by hand.

## The loop

1. **Orient.** Read `references/this-machine.md`, then the host file. Run
   `haus status` if the machine's freshness is relevant.
2. **Find the room, then the option.** `references/rooms.md` maps what the user
   said onto one room, and tells you whether that room has a **runtime verb** as
   well as options — `focus on` makes the Mac quiet *now*, where
   `haus.focus.*` decides what quiet means from the next rebuild on. Get that
   fork right before you edit anything, and when a room has a runtime verb use
   **that** rather than the tool underneath it. Then grep `references/options.md` for
   the leaf: it is rendered from the exact haus revision this machine is pinned
   to, so it is authoritative — if an option is not in it, it does not exist
   here. Going straight to the flat option search is how an agent ends up
   inventing a plausible name.
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
Pulling a newer haus is `haus update`, which bumps the pin and rebuilds in one
step. The store is read-only by design.

**Never edit haus itself.** The `haus.*` options are the entire supported
surface. If the user wants something the options cannot express, say that plainly —
it is a change to haus (a different repo, upstream), not to their machine.

For a value, prefer `haus set <path> <value>`: it writes an ordinary
module under `hosts/<host>/settings/`, type-checks it, and rebuilds. It takes as
many `<path> <value>` PAIRS as you need and applies them all-or-nothing in ONE
rebuild — so an intent that spans two options (light mode is `theme.flavor` plus
`theme.systemAppearance`) is one command, not two rebuilds with the machine
half-switched in between. Reach for the host file when the change is structural,
not merely multi-valued. `haus get
[path]` reads the declared result, `haus unset <path> [<path>…]` writes null for
nullable options, and `haus reset <path> [<path>…]` removes machine overrides so
the host, desktop, or room value wins again. Those two take a LIST the way `set`
takes pairs, with the same all-or-nothing single rebuild — so undoing light mode
is one `haus reset theme.flavor theme.systemAppearance`, not two rebuilds with
the machine half-undone in between. The commands only accept `haus.*` paths (the
`haus.` prefix may be omitted). Edit the host file directly when the change is structural or needs
several related definitions in one module.

**A path may go INSIDE an option, and usually should.** `haus set
bar.items.aiUsage true` switches one pill; `haus set displays.internal.uiScale
larger-text` scales one screen. Naming the enclosing attribute set instead —
`haus set bar.items '{"aiUsage":true}'` — is an `mkForce` over the WHOLE set, so
every key the user didn't name falls back to its default and a bar they arranged
over several commands goes back to stock. Setting the leaf touches only the leaf.

**Ask before touching identity or secrets.** `haus.git.*`, signing keys,
anything under `haus.secrets.*`, and the pounce signing identity are the
user's, not yours.

**Prefer a `haus.*` option to a raw nix-darwin setting.** Both work — the
host file is an ordinary nix-darwin module — but haus's options are the ones
that are documented, checked, and safe. Reach for `system.defaults.*` or
`homebrew.*` directly only when nothing in `haus.*` covers it, and say that
you did.

## After a successful rebuild

`~/.config/nix` is a git repo — the user's machine in text. `haus set` stages its
one generated module because flakes ignore untracked files. Offer to commit the
change with a message naming what it does. Don't push unless asked.

## When `haus rebuild` refuses

If `haus rebuild` stops with a Full Disk Access message, **do not work around it
and do not retry.** The config sets `system.defaults.universalaccess.*`, a
TCC-protected domain that can only be written by an app holding Full Disk Access.
That grant belongs to whichever app is responsible for the process — not to you,
and not to root. So this is **not** "agents are refused": a human in a terminal
nobody has granted is refused identically, and a session running inside a
terminal that HAS the grant is not refused at all. When the write fails it fails
mid-activation and aborts the rest, skipping every background service haus
installs, with a symptom nowhere near the cause. That is what is being prevented.

Two ways on, in this order:

1. **Move those keys to `haus.accessibility.*`.** It reaches every key in that
   domain measured to take effect — `increaseContrast`,
   `differentiateWithoutColor`, `reduceMotion`, `reduceTransparency`,
   `mouseDriverCursorSize`, `closeViewScrollWheelToggle`,
   `closeViewZoomFollowsFocus` — through a guarded write, so without the grant
   you lose that setting and nothing else, and the rebuild runs from anywhere.
   This is usually the real fix, and it is an edit you can make. Since
   2026-08-14 that list covers **every key nix-darwin types here**, so a config
   using the raw form has no key that needs it.
2. **If the grant is genuinely wanted anyway** — say the user set some other key
   in this domain through `system.defaults.CustomUserPreferences` — tell them to
   run `haus rebuild` themselves in a terminal that holds it. The edit is
   already written; nothing is lost.

`haus doctor` reports whether this app has the grant; `haus plan` says which
grant a rebuild wants before it runs.

## What a rollback does and doesn't undo

`haus rollback` returns to the previous generation instantly and atomically. It
rewinds **everything Nix manages**: packages, services, shell config, PATH,
dotfiles haus writes.

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

Removing an app from `haus.roster` (or `homebrew.casks`) stops haus from
*managing* it — it does **not** uninstall it. The app stays on disk. Tell the
user the extra step: `brew uninstall --zap <cask>`.

## When you need more than this skill

- `haus doctor` — health check. Run it before blaming your own change for
  something being broken.
- `haus generations` / `haus rollback [N]` — the undo history.
- <https://hausfold.co/docs/> — guides and reference. Note it documents the **latest**
  haus; this machine is pinned to a specific revision, so it can describe options
  that are not in `references/options.md` yet. When they disagree, this skill's
  reference wins for what is settable *right now*.

## Files in this skill

| File | What it is |
|---|---|
| `references/rooms.md` | Which room a sentence belongs to, and whether that room has a runtime verb as well as options — generated. **Read this before options.md**, not after. |
| `references/options.md` | Every `haus.*` option on this machine's revision — generated, authoritative. Grep it. |
| `references/recipes.md` | Worked examples for the common asks (install an app, change the theme, resize the UI…). |
| `references/this-machine.md` | This host: name, paths, which rooms are enabled. |
| `consumer-AGENTS.md` | A starter `AGENTS.md` for `~/.config/nix` — the rules themselves, read by Codex, OpenCode, Cursor, Copilot and anything else that speaks agents.md. |
| `consumer-CLAUDE.md` | Its `@AGENTS.md` pointer, for the one client that reads only `CLAUDE.md`. If that repo has neither file, offer to copy **both** in — copying one alone orients only some of the clients that might open a session there. Copy with `install -m 644`, not `cp`: these are Nix store files (`r--r--r--`), and `cp` hands the user a starter they can't edit. |
