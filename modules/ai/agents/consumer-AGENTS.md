# AGENTS.md

This repo is a **haus consumer** — one Mac's configuration in text. The
layer and the desktop it selects (every module, every default) come from the pinned `haus`
flake input; what lives here is only what's personal to this machine.

```
flake.nix                        pins haus — change with `haus update`, not by hand
flake.lock                       the pinned revision — never hand-edited
hosts/<hostname>/default.nix     THE file you edit by hand
hosts/<hostname>/settings/*.nix  one ordinary module per `haus set` override
```

This file is the one set of instructions, for every agent — Claude Code, Codex,
OpenCode, pi, Cursor, Copilot all read it, directly or through a one-line
pointer.
The `CLAUDE.md` beside it is that pointer and holds no rules of its own.

## Working here

- **Edit only the host config.** Set `haus.*` options in `default.nix`.
  It's an ordinary nix-darwin module, so raw `system.defaults.*` / `homebrew.*`
  also work — but prefer a `haus.*` option when one exists.
- **For options, use `haus set <path> <value> [<path> <value>…]`.** It writes and
  stages a small module per pair under `settings/`, type-checks them, then
  rebuilds once — all-or-nothing, so a two-option intent (light mode is
  `theme.flavor` + `theme.systemAppearance`) is one command and one rebuild. `haus get
  [path]` reads it, `haus unset <path> [<path>…]` writes null for nullable
  options, and `haus reset <path> [<path>…]` removes overrides — both take a LIST
  with the same all-or-nothing single rebuild, so undoing that two-option intent
  is also one command. Only `haus.*` paths are allowed.
- **Address the leaf, not the set it sits in.** A path may go inside an option:
  `haus set bar.items.aiUsage true`, `haus set displays.internal.uiScale
  larger-text`. Naming the whole attribute set (`haus set bar.items
  '{"aiUsage":true}'`) is an `mkForce` over all of it, so every key you didn't
  name falls back to its default.
- **Apply with `haus rebuild`.** It builds first and switches only on success, so
  a broken config never reaches the running system.
- **Undo with `haus rollback`.** Atomic, instant, and it rewinds everything Nix
  manages — but *not* macOS system settings the rebuild wrote, and *not* Homebrew
  casks. For settings: `haus capture` before a change snapshots them so `haus
  revert-settings` can put them back; `haus diff`/`haus plan` show declared vs
  what macOS actually has.
- **Don't invent option names.** The authoritative list for the revision this
  machine is pinned to is `references/options.md` inside the `haus` skill —
  `~/.claude/skills/haus/`, `~/.codex/skills/haus/` or
  `~/.config/opencode/skills/haus/`, `~/.pi/agent/skills/haus/`, whichever your
  client uses. It's plain
  markdown, so read it by path even if your client never loads it as a skill.
- **Ask before touching identity or secrets** — git identity, signing keys,
  `haus.secrets.*`.

## Where the detail lives

The `haus` skill carries the full option reference, worked recipes, and this
machine's current state. Read it before making changes; it is generated from
this machine's pinned haus, so it can't drift from what's actually settable
here. haus installs one copy per client it manages — `~/.claude/skills/`,
`~/.codex/skills/`, `~/.config/opencode/skills/`, `~/.pi/agent/skills/` — and
they are ordinary
markdown, so read whichever one is on disk even if it isn't yours.

`haus doctor` checks the machine's health. <https://hausfold.co/docs/> has the
guides — it documents the *latest* haus, which may be ahead of this pin.
