# Leaving zellij — Ghostty splits + zmx (architecture A)

> Status: **plan only, nothing implemented.** zellij stays the shipped
> multiplexer until Phase 6 flips the default. Every phase below is
> separately shippable and separately revertible; the seam in Phase 2 is
> what makes that true.

## Why

The trigger is images: we want every terminal graphics protocol to render
in a pane, and **no multiplexer can deliver that**, because a multiplexer is
a second terminal emulator in the middle of the pipe. Graphics have to
survive two parsers, and the middle one never keeps up.

Concretely, for zellij:

- kitty graphics: [never](https://github.com/zellij-org/zellij/issues/2814)
  — the maintainers have said so, not "not yet".
- sixel: implemented but
  [buggy and laggy](https://github.com/zellij-org/zellij/issues/3981),
  with artifacts that survive a clear.
- no passthrough mode, so no way to route around it.

`modules/hearth/zellij/image-preview.sh:7` already documents the dead end in
its own header: zellij's VTE parser drops kitty APC outright, and forwards
sixel only when the host terminal advertises it in DA1 — which Ghostty
doesn't. That file renders half-block chafa art *because* of the
multiplexer, and its `fmt=kitty` branch (already written, `:78`) is what
fires when `$ZELLIJ` is unset. The escape hatch is in the tree already.

Four things come along for free once the multiplexer is gone:

| | |
|---|---|
| **The patch treadmill** | Six patches against `zellij-unwrapped` (`modules/hearth/default.nix:781`). Any nixpkgs bump that moves zellij or its deps can break the build, as the file's own comment at `:772` says. |
| **The permission-cache hack** | Four `home.activation` blocks seeding grants straight into zellij's plugin permission cache (`:2178`–`:2208`), because the real path is an interactive y/n prompt a background plugin can never answer. |
| **8,617 lines of Rust** | Four plugin forks we maintain against a moving `zellij-tile` API. |
| **Latency** | One fewer VTE parse + reflow per keystroke, and no wasm plugin tick. |

## The shape

```
Ghostty 1.3+            the terminal AND the pane manager
                        native splits/tabs, kitty graphics, config hot-reload
├── prowl (AeroSpace)   window-level layout — unchanged, already installed
├── zmx                 session persistence ONLY: attach/detach.
│                       No windows, no tabs, no splits, deliberately.
├── AppleScript API     the control surface. holt, pounce, sill, ⌘A, ⌘F
│                       all drive panes through it instead of `zellij action`.
└── sill                absorbs whatever the status-bar plugin used to draw
```

Two pieces make this newly possible, and both landed in 2026:

- **Ghostty 1.3.0** (2026-03-09) exposes
  [every window, tab, split and terminal via AppleScript](https://ghostty.org/docs/features/applescript),
  including a `surface configuration` record that carries working directory,
  command and environment — plus send-text/key/mouse. That is the `zellij
  action` replacement, and it is strictly more capable for spawning.
- **[zmx](https://github.com/neurosnap/zmx)** — Zig, one binary, one unix
  socket per session, `poll(2)` loops. It restores scrollback and terminal
  state through `libghostty-vt`, so reattach is byte-exact rather than a
  reflow. It explicitly does **not** provide windows, tabs or splits.

[gmx](https://github.com/nicosuave/gmx) is the existing proof that the two
compose. We don't adopt it — it's tmux-shaped and we're not — but its
AppleScript layer is worth reading before Phase 1.

## What survives, what moves, what dies

| Surface | Today | After |
|---|---|---|
| `holt` | worktree registry + hooks | **survives untouched** — it manages worktrees, not panes |
| `float-term.sh` + `floatring` | spawns Ghostty windows already | **survives** |
| prowl / AeroSpace | tiles Ghostty windows | **survives**, gains importance |
| `launch.sh` | attach-or-create `main` + self-tile onto workspace T | shrinks to `zmx attach --create` + the same self-tile |
| `image-preview.sh` | chafa `symbols` half-blocks | delete the symbols branch, keep `fmt=kitty`; real pixels |
| 6× `zellij-unwrapped` patches | right-click zoom, naked-click links, selection autoscroll, … | **die** — audit each against Ghostty's native behaviour first (Phase 3) |
| `config.kdl` + `custom.kdl` (750 lines) | keybinds, layout, theme | Ghostty `keybind` + `new_split` actions in `modules/hearth/ghostty/config` |
| `term-bindings.nix` assertion | cross-checks the table against `config.kdl` | retarget to the ghostty config; the table itself and the pounce cheatsheet **survive** |
| `zellijLiveConfig` activation (the mtime hack, `:2126`) | forces a live-mtime real file so zellij's watcher reloads | **dies** — Ghostty reloads its own config |
| 4× plugin permission seeds | `:2178`–`:2208` | **die** |
| **tab-bar** fork | agent-count badge beside the tab name | Ghostty tab title, set via AppleScript or OSC 2 |
| **status-bar** fork | quick-hint block + the tips corpus | sill pill, or dropped. **The biggest single judgement call in this plan.** |
| **link-handler** fork | click an image path → floating preview pane | Ghostty's own OSC 8 + `link` regex config; preview becomes a real kitty render |
| **tab-history** fork | MRU tab switching | no Ghostty equivalent — an AppleScript-driven MRU daemon, or dropped |
| `find.sh` (⌘F overlay) | enumerates panes via `zellij action` | AppleScript enumerates windows/tabs/splits/terminals — a direct port |
| `gh-dash.sh` | `new-pane --borderless true` fullscreen overlay | Ghostty new tab or new window |
| `editor-open-pane.sh` + `EditorOpen.app` | new zellij tab running `$EDITOR` | AppleScript `new tab` with a surface configuration |
| `agents-hook.sh` | `zellij pipe` broadcast to the tab-bar plugin (`:123`) | AppleScript set-title, or sill-only |
| `statusline.sh` | keys rows on `$ZELLIJ_PANE_ID` (`:179`) | `$ZMX_SESSION` or the Ghostty surface id |
| `spawn-agent.sh` (pounce) | `holt` + `zellij` tab for the repo (`:83`) | AppleScript `new tab` with cwd + env in the surface config |
| `zscratch` | throwaway zellij server to test plugin wasm without a rebuild | **loses its reason to exist** — Ghostty hot-reloads config and there is no wasm. Retire it, or re-scope it to "boot a Ghostty window with an overlay config" |

## The four real risks

**1 · No sixel. 4/5, and it is the one that can kill the plan.**
Ghostty is kitty-protocol only —
[sixel is still an open discussion](https://github.com/ghostty-org/ghostty/discussions/2496),
and `image-preview.sh:9` already states it as fact. So "renders all
protocols" becomes "renders the one protocol that matters plus iTerm2".
If a sixel-emitting tool is load-bearing for you, **stop here** — that is
WezTerm (the only terminal doing all three) and a different, larger plan
that replaces Ghostty too. Decide this before Phase 1, not after Phase 4.

**2 · Ghostty has no plugin system, and won't. 4/5.**
Everything the four forks draw must move to sill, become a title string, or
be dropped. The tips corpus in `status-bar/src/tip/` has no natural home —
it is the rice's voice, and a bar pill is a worse surface for it than a
status line. Budget a real decision here, not a port.

**3 · zmx is young. 3/5 — but packaged.**
Already in nixpkgs as `pkgs/by-name/zm/zmx/package.nix`, **v0.7.0**, built
with `zig_0_15` and explicitly Darwin-aware (it wraps `xcrun`/`xcode-select`
so Ghostty's Zig build can find the SDK inside the sandbox). So there is no
packaging cost — `haus.hearth` just adds it to `home.packages`. What stays
risky is the youth: single maintainer, sub-1.0, and a `libghostty-vt`
dependency that makes it inherit Ghostty's release cadence. Fallback if it
doesn't hold up: `dtach`, older and dumber, at the price of losing
scrollback restore.

**4 · AppleScript is the only control surface, and it is a preview API. 3/5.**
Every pane operation becomes an `osascript` round trip. This repo has
already measured that cost once — `modules/sill`'s note that a sketchybar
call through Foundation `Process` costs ~85 ms against ~4 ms spawned by
hand, which is why `sillpop` reads rects at arm time. The same discipline
applies: batch, cache, and never put an osascript in a hot path.
[Ghostty #11457](https://github.com/ghostty-org/ghostty/issues/11457) shows
the API is still settling.

## The path

Each phase ends shippable. Nothing before Phase 6 changes what a rebuild
gives you by default.

**Phase 0 — probe, no rice change. ~1 session.**
`nix run nixpkgs#zmx` (it's packaged — see risk 3), then live in Ghostty
splits + AeroSpace for a working day with zellij still installed and
untouched. The question this answers is not "does it work" — it's "do I
miss the four plugins by evening". If the answer is yes for the status bar,
Phase 5 gets scoped up front instead of discovered late. Answer open
questions 1 and 3 here.

**Phase 1 — prove the control surface. ~1 session.**
One scratch script, outside the rice: spawn an agent pane the way ⌘A does
today — AppleScript `new tab` with a surface configuration carrying the
worktree cwd and env, running `zmx attach --create <session>`. Measure the
round trip. If it's over ~150 ms, the whole spawn path needs a resident
helper and that changes Phase 4's shape.

**Phase 2 — the seam. ~1 session.**
`haus.hearth.multiplexer = "zellij" | "none"`, defaulting to `zellij`.
Everything after this lands behind it, so `main` is never half-migrated and
a bad day is one option flip back. Room-registry entry + desktop-safety
decision in the same PR (`modules/options-groups.nix`).

**Phase 3 — Ghostty pane config + keybind parity. ~2 sessions.**
Port `config.kdl`'s binds to Ghostty `keybind` entries; retarget the
`term-bindings.nix` assertion at the new file so the pounce cheatsheet
can't drift. Audit the six patches one at a time against Ghostty's native
behaviour and record, in this file, which ones Ghostty gives us free and
which are genuinely lost.

**Phase 4 — retarget the consumers. ~2 sessions.**
`launch.sh`, `spawn-agent.sh`, `agents-hook.sh`, `statusline.sh`,
`find.sh`, `gh-dash.sh`, `editor-open-pane.sh`. All mechanical once Phase 1
settled the idiom. `holt` is untouched.

**Phase 5 — the plugin surfaces. ~2 sessions.**
Agent badge → tab title. Quick-hints/tips → sill or retired. Image preview
→ delete the chafa branch. tab-history → MRU daemon or retired. This is the
phase where taste, not mechanics, decides how much survives.

**Phase 6 — flip the default. ~1 session.**
`multiplexer = "none"` by default, zellij still selectable. Live on it.

**Phase 7 — delete. ~1 session.**
Drop the option, the four forks, the six patches, the KDL, the activations,
and `zscratch` (or re-scope it). ~10k lines out of the tree. Update
`AGENTS.md`'s architecture map and the nebelhaus.com guides in the
workshop's `web/src/content/docs/` in the same PR.

**Total ≈ 10 sessions**, with a genuine off-ramp at the end of Phase 0 and
a cheap revert at any point before Phase 7.

## What we're deliberately not doing

| | |
|---|---|
| **tmux** | sixel since 3.4, kitty [an open issue with a PoC branch](https://github.com/tmux/tmux/issues/4902). Costs the same rewrite and loses on every other axis. No. |
| **WezTerm** | the only terminal rendering kitty + sixel + iTerm2, with a real built-in mux and deep Lua. But it replaces Ghostty too — hearth's theming, `floatring`, `term-bindings.nix` all move — and its stable cadence has gone quiet with the maintainer calling it a spare-time project. Revisit only if risk 1 kills this plan. |
| **Superlogical** | Hashimoto's new company, announced 2026-07-30: a libghostty session multiplexer with web/iOS reattach. Same primitives, same problem, unknown license, unshipped. **Recheck before Phase 3** — if it lands open, zmx's role is exactly what it replaces. |

## Open questions

1. **Is sixel actually needed?** (risk 1). Nothing proceeds honestly until
   this is answered.
2. **Does the status-bar tips corpus survive, and where?** A sill pill is a
   worse home than a status line. It might just retire.
3. **Splits or windows?** AeroSpace can tile Ghostty windows directly, which
   would make Ghostty splits redundant and the whole thing simpler — at the
   cost of every pane being a real macOS window (Mission Control noise,
   slower spawn). Phase 0 should feel both.
4. **Does `zmx` belong in the rice at all** if every pane is an AeroSpace-tiled
   window that never needs to detach? Persistence matters for long agent runs;
   it may not matter for anything else.
