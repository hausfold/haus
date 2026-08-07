# AGENTS.md

This repo is a **nebelhaus consumer** — one Mac's configuration in text. The
rice itself (every module, every default) comes from the pinned `nebelhaus`
flake input; what lives here is only what's personal to this machine.

```
flake.nix                        pins the rice — change with `haus update`, not by hand
flake.lock                       the pinned revision — never hand-edited
hosts/<hostname>/default.nix     THE file you edit
```

This file is the one set of instructions, for every agent — Claude Code, Codex,
OpenCode, Cursor, Copilot all read it, directly or through a one-line pointer.
The `CLAUDE.md` beside it is that pointer and holds no rules of its own.

## Working here

- **Edit only the host file.** Set `nebelhaus.*` options there. It's an ordinary
  nix-darwin module, so raw `system.defaults.*` / `homebrew.*` also work — but
  prefer a `nebelhaus.*` option when one exists.
- **Apply with `haus rebuild`.** It builds first and switches only on success, so
  a broken config never reaches the running system.
- **Undo with `haus rollback`.** Atomic, instant, and it rewinds everything Nix
  manages — but *not* macOS system settings the rebuild wrote, and *not* Homebrew
  casks. For settings: `haus capture` before a change snapshots them so `haus
  revert-settings` can put them back; `haus diff`/`haus plan` show declared vs
  what macOS actually has.
- **Don't invent option names.** The authoritative list for the revision this
  machine is pinned to is `~/.claude/skills/nebelhaus/references/options.md`.
  It's plain markdown — read it whatever client you are, even if your client
  doesn't load Claude Code skills.
- **Ask before touching identity or secrets** — git identity, signing keys,
  `nebelhaus.secrets.*`.

## Where the detail lives

The nebelhaus skill at `~/.claude/skills/nebelhaus/` carries the full option
reference, worked recipes, and this machine's current state. Read it before
making changes; it is generated from this machine's pinned rice, so it can't
drift from what's actually settable here. (That directory is Claude Code's skill
location, because that's the client the rice installs it for — but the files are
ordinary markdown, so any agent can and should read them.)

`haus doctor` checks the machine's health. <https://nebelhaus.com> has the
guides — it documents the *latest* rice, which may be ahead of this pin.
