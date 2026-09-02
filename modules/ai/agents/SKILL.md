---
name: haus
description: Change this Mac's setup on a machine managed by haus — the hacker desktop, or any other desktop built on it. Install or remove apps, change the theme, fonts, keybindings, window management, the bar, the shell, or macOS settings. Use whenever the user asks you to change how their Mac looks or behaves, or mentions haus, a "rice" (the older word for a desktop), their host file, or ~/.config/nix. Covers finding the right haus.* option, editing the host file, applying with `haus rebuild`, and undoing with `haus rollback`.
---

# Changing a haus machine

This Mac runs **haus** — its setup is a declarative Nix configuration, not
settings clicked into System Settings. Every change is built before it is applied
and lands as a generation the user can atomically roll back, so a mistake costs
one command rather than an afternoon. It also means the usual moves are wrong: no
dotfile edits in `$HOME`, no `brew install`, no `defaults write` — nearly all of
it is overwritten by the next rebuild. One file is what you edit.

Skill version: @hausVersion@ (matches the haus revision this machine is pinned to).

## The one file you edit

```
~/.config/nix/hosts/<hostname>/default.nix
```

The user's **host file** — the thin personal layer (identity, apps, preferences)
on top of haus. `haus edit` opens it; `references/this-machine.md` names the exact
path and what is currently enabled. Everything else in `~/.config/nix` is
scaffolding: `flake.nix` pins haus, `flake.lock` pins the revision, both managed
by commands rather than by hand.

## The loop

1. **Orient.** Read `references/this-machine.md`, then the host file. Run
   `haus status` if the machine's freshness is relevant.
2. **Find the room, then the option.** `references/rooms.md` maps what the user
   said onto one room, and says whether that room has a **runtime verb** as well
   as options — `focus on` makes the Mac quiet *now*, where `haus.focus.*`
   decides what quiet means from the next rebuild on. Get that fork right first,
   and where a room has a verb use **that** rather than the tool underneath it.
   Then grep `references/options.md` for the leaf; it is rendered from this
   machine's pinned revision, so an option missing from it does not exist here.
   Straight to the flat option search is how an agent invents a plausible name.
3. **Edit the host file**, or use `haus set` for a value (below). Smallest change
   that does the job; keep the file's existing comment style.
4. **Apply.** `haus rebuild` — it builds first and only switches if the build
   succeeded, so a broken config never reaches the running system.
5. **Verify, then hand back.** Say what should now be different and how the user
   can see it. If it is wrong, `haus rollback`.
6. **Offer to commit.** `~/.config/nix` is a git repo — the user's machine in
   text — and `haus set` stages its generated module because flakes ignore
   untracked files. Name what the change does. Don't push unless asked.

## Rules

**Never invent an option name.** If `references/options.md` does not list it, it
is not settable on this revision. Say so, and offer `haus update` — the option
may exist upstream and simply be newer than this machine's pin.

**Never hand-edit `flake.lock`, `flake.nix`, `/nix/store`, or haus itself.**
Pulling a newer haus is `haus update`, which bumps the pin and rebuilds in one
step; the store is read-only by design. The `haus.*` options are the entire
supported surface, so if the user wants something they cannot express, say that
plainly — it is a change to haus (a different repo, upstream), not to their Mac.

**Prefer a `haus.*` option to a raw nix-darwin setting.** Both work — the host
file is an ordinary nix-darwin module — but haus's options are the documented,
checked ones. Reach for `system.defaults.*` or `homebrew.*` only when nothing in
`haus.*` covers it, and say that you did.

**Ask before touching identity or secrets.** `haus.git.*`, signing keys, anything
under `haus.secrets.*`, and the launcher signing identity are the user's.

**For a value, prefer `haus set <path> <value>` to a hand edit.** It writes an
ordinary module under `hosts/<host>/settings/`, type-checks it and rebuilds, and
takes as many PAIRS as you need — all-or-nothing in ONE rebuild, so an intent
spanning two options (light mode is `theme.flavor` plus `theme.systemAppearance`)
never leaves the machine half-switched. `haus get [path] --json` reads back
`{path, defined, value}`, where `defined: false` is what no bare value can say:
settable, but nothing has named it yet — not an option set to null. `haus unset`
and `haus reset` take a LIST under that same rule. Edit the host file directly
when the change is structural rather than merely multi-valued.

**A path may go INSIDE an option, and usually should.** `haus set
bar.items.aiUsage true` switches one pill; `haus set displays.internal.uiScale
larger-text` scales one screen. Naming the enclosing attribute set instead —
`haus set bar.items '{"aiUsage":true}'` — is an `mkForce` over the WHOLE set, so
every key the user didn't name falls back to its default and a bar they arranged
over several commands goes back to stock. Setting the leaf touches only the leaf.

## Traps

**A rollback does not undo everything.** `haus rollback` rewinds what Nix manages
— packages, services, shell config, PATH, dotfiles haus writes — instantly and
atomically. It does **not** rewind the macOS settings a rebuild wrote (Dock,
keyboard, Finder…) or Homebrew casks. Undoing one of those means setting the
option back and rebuilding, changing it by hand, or `haus revert-settings` if the
user ran `haus capture` first; `haus diff` shows declared versus actual. Say which
kind of change you are making, so the user knows whether a rollback undoes it.

**Removing an app from `haus.roster` does not uninstall it.** It stops haus
*managing* it — the app stays on disk. Tell the user the extra step:
`brew uninstall --zap <cask>`.

**A rebuild that stops on Full Disk Access is not "agents are refused".** The
config sets `system.defaults.universalaccess.*`, a TCC-protected domain only an
app with that grant can write, so an ungranted human is refused identically. Do
not work around it and do not retry — the write fails mid-activation and skips
every background service haus installs, with a symptom nowhere near the cause.
The fix is usually to move those keys to `haus.accessibility.*`, whose guarded
writes reach every key nix-darwin types there; `references/recipes.md` has both.

**Do not verify by taking the user's screen.** Someone is sitting in front of
this Mac; `agent-desktop-guard` puts any call that foregrounds an app, moves the
pointer or sends a keystroke back to a human. Boot a headless VM instead —
`references/vm.md` is that whole loop, and what to do when it cannot answer.

## When you need more than this skill

- `haus --help` — every verb and flag, from the revision this machine has.
- `haus doctor` — health check, including whether this app holds Full Disk
  Access. Run it before blaming your own change. `haus plan` previews a rebuild.
- `haus report` — for a fault that is haus's own rather than this config's: opens
  its bug form with the diagnostics filled in. `--print` prints the block and the
  link and opens nothing, which is the form for a pane. Nothing is sent either
  way until the user presses Submit.
- `haus generations` / `haus rollback [N]` — the undo history.
- `haus show <src> [--json]` — inspect a `.nix` the user was handed or linked to.
  Reads only; a source is fetched into the store and read there, so it is safe on
  something they intend to refuse. `class: "desktop"` with `ok: true` means haus
  PROVED it can set nothing but public, desktop-safe options; `class: "room"`
  means it is code that runs as root — **never report that as safe**.
- <https://hausfold.co/docs/> — guides and reference for the **latest** haus, so
  it can describe options this pin does not have. When the two disagree, this
  skill's reference wins for what is settable right now.

## Files in this skill

`haus skill` prints this page and `haus skill <name>` one of the references, so
you can read either without knowing where the client keeps them. `haus skill
install` writes them into a client that has none.

| File | What it is |
|---|---|
| `references/rooms.md` | Which room a sentence belongs to, and whether that room has a runtime verb as well as options — generated. **Read this before options.md**, not after. |
| `references/options.md` | Every `haus.*` option on this machine's revision — generated, authoritative. Grep it. |
| `references/recipes.md` | Worked examples for the common asks (install an app, change the theme, resize the UI…). |
| `references/vm.md` | Seeing your change without taking the user's screen: the headless VM loop, and what to do when it can't answer. |
| `references/this-machine.md` | This host: name, paths, which rooms are enabled. Rendered per HOST rather than per revision, so it is the one page not in the store copy. |
| `consumer-AGENTS.md` | A starter `AGENTS.md` for `~/.config/nix` — the rules themselves, read by Codex, OpenCode, Cursor, Copilot and anything else that speaks agents.md. |
| `consumer-CLAUDE.md` | Its `@AGENTS.md` pointer, for the one client that reads only `CLAUDE.md`. If that repo has neither file, offer to copy **both** in — one alone orients only some of the clients that might open a session there. Copy with `install -m 644`, not `cp`: these are Nix store files (`r--r--r--`), and `cp` hands the user a starter they can't edit. |
