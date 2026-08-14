# Leaving zellij — Ghostty windows + AeroSpace + zmx (architecture A)

> Status: **plan only, nothing implemented.** zellij stays the shipped
> multiplexer until Phase 7 flips the default. Every phase below is
> separately shippable and separately revertible; the seam in Phase 2 is
> what makes that true.

## Two decisions, settled 2026-08-14

They were the plan's open questions 1 and 3. Both are now answered, and
both simplify it:

1. **Kitty protocol only. Sixel is not needed.** Ghostty has no sixel
   ([open discussion #2496](https://github.com/ghostty-org/ghostty/discussions/2496))
   and that is an accepted loss, not a risk to manage. This permanently
   removes WezTerm from consideration — being the only terminal that
   renders all three protocols was its entire advantage over Ghostty here.
2. **Windows, not splits.** A "pane" becomes a real Ghostty window that
   AeroSpace tiles. Ghostty's own splits go unused. `launch.sh:44` already
   self-tiles each new Ghostty window onto workspace `T`, so the mechanism
   is proven in-tree — this promotes it from workaround to architecture.

Decision 2 pays for itself three times over: pane enumeration becomes
`aerospace list-windows` (a fast CLI, not an osascript round trip), pane
focus becomes `aerospace focus --window-id`, and the navigation chords
already exist and are already on the cheatsheet in
`modules/prowl/wm-bindings.nix`. Most of the keybind work becomes deletion
rather than translation.

## Why

The trigger is images: we want graphics to render in a pane, and **no
multiplexer can deliver that**, because a multiplexer is a second terminal
emulator in the middle of the pipe. Graphics have to survive two parsers,
and the middle one never keeps up.

Concretely, for zellij:

- kitty graphics: [never](https://github.com/zellij-org/zellij/issues/2814)
  — the maintainers have said so, not "not yet".
- sixel: implemented but
  [buggy and laggy](https://github.com/zellij-org/zellij/issues/3981),
  with artifacts that survive a clear. Moot now anyway (decision 1).
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
| **The permission-cache hack** | Four `home.activation` blocks seeding grants straight into zellij's plugin permission cache (`:2178`–`:2208`), plus a fifth site in `modules/den/zscratch.sh:65`, because the real path is an interactive y/n prompt a background plugin can never answer. |
| **8,617 lines of Rust** | Four plugin forks we maintain against a moving `zellij-tile` API. |
| **Latency** | One fewer VTE parse + reflow per keystroke, and no wasm plugin tick. |

## The shape

```
Ghostty 1.3+          the terminal. One window per pane, kitty graphics,
                      config hot-reload. Splits unused.
├── prowl (AeroSpace) LAYOUT + ENUMERATION + FOCUS.
│                     `list-windows`, `focus --window-id`, workspace T.
│                     Already installed, already bound, already on the cheatsheet.
├── zmx               IDENTITY + PERSISTENCE + READ. One session per pane.
│                     `ls --where`, `history --vt`, `tail`, `send`, `run`.
│                     No windows, no tabs, no splits, deliberately.
├── AppleScript       SPAWN only. `new window` with a surface configuration
│                     carrying cwd/command/env, plus `perform action`.
└── sill              absorbs every status surface the plugins used to draw
```

Two things landed in 2026 that make this newly possible:

- **Ghostty 1.3.0** (2026-03-09) exposes windows, tabs, splits and
  terminals via [AppleScript](https://ghostty.org/docs/features/applescript),
  including a `surface configuration` record carrying working directory,
  command and environment, plus `input text` / `send key` / `perform action`
  (which executes keybind action strings). Object model is
  `application → windows → tabs → terminals`; readable properties are
  `id`, `name`, `working directory`.
- **[zmx](https://github.com/neurosnap/zmx)** — Zig, one binary, one unix
  socket per session, `poll(2)` loops, `libghostty-vt` for state.

**zmx is not just detach.** That is the load-bearing realisation of this
revision, and it is what makes the plan close. Ghostty's AppleScript API
can create and focus surfaces but **cannot read one** — there is no
`dump-screen` equivalent, no scrollback, no text property. Three shipped
features depend on reading a pane:

| Feature | Today | After |
|---|---|---|
| ⌘F find overlay | `zellij action dump-screen --full -p <id>` (`find.sh:33`) | `zmx history <session>` |
| ⌘L links picker | same (`modules/pounce/commands/links.sh:88`) | `zmx history <session>` |
| agents peek popup | `zellij … subscribe --pane-id --ansi -s 300` (`agents-peek.sh:17`) | `zmx tail <session>` / `history --vt` |

`zmx history` takes `--vt`, which preserves the escape sequences
`agents-peek.sh` currently asks zellij for with `--ansi`. So the read API
survives the migration intact — through zmx, not through Ghostty. Answering
"do we even need zmx if every pane is a window?" with **yes, emphatically**:
it is the pane identity scheme and the pane contents API, and detach is
the least of what it does for us.

[gmx](https://github.com/nicosuave/gmx) is the existing proof that Ghostty
and zmx compose. We don't adopt it — it's tmux-shaped, split-based, and
we're neither — but its AppleScript layer is worth reading before Phase 1.

## The keystone: pane identity

Everything agent-related in the rice is keyed on `$ZELLIJ_PANE_ID`, and
the gate is harder than it looks. `modules/sill/sketchybar/plugins/agents-hook.sh:53`
is a bare `[ -n "${ZELLIJ_PANE_ID:-}" ] || exit 0` — so under
`multiplexer = "none"` **every agent lifecycle hook from every client exits
at that line**, and the paw pill, the statusline HUD and the tab badge all
go dark at once. That file is also what den `readFile`s to put `agent-state`
on `PATH` (`modules/den/default.nix:647`), so it is one edit with three
consumers.

The replacement is a zmx session name per pane, with labels
(`zmx ls --where k=v`) carrying repo / worktree / client. This is the
migration's real keystone, not a mechanical retarget, which is why it gets
its own phase (Phase 3) ahead of everything that depends on it:
`statusline.sh:177-192` writes the pane→transcript map, and
`links.sh` reads it — retarget one without the other and ⌘L breaks silently.

## What survives, what moves, what dies

| Surface | Today | After |
|---|---|---|
| `holt` | worktree registry + hooks | **survives untouched** — worktrees, not panes |
| `float-term.sh` + `floatring` | spawns Ghostty windows already | **survives** — zero zellij references |
| prowl / AeroSpace | tiles Ghostty windows | **survives and grows**: layout + enumeration + focus |
| `modules/prowl/wm-bindings.nix` | the WM chord table + cheatsheet cards | **survives**, absorbs the pane-navigation rows |
| `launch.sh` | attach-or-create `main`, self-tile onto workspace T | shrinks to `zmx attach --create` + the same self-tile |
| `image-preview.sh` | chafa `symbols` half-blocks | delete the symbols branch, keep `fmt=kitty`; real pixels |
| 6× `zellij-unwrapped` patches | right-click zoom, naked-click links, selection autoscroll, … | **die** — audit each against Ghostty's native behaviour (Phase 4) |
| `config.kdl` + `custom.kdl` (750 lines) | keybinds, layout, theme | mostly **deleted**; chords move to AeroSpace, not to Ghostty |
| `modules/hearth/ghostty/config` | ~15 `unbind` entries exist to let chords **fall through to zellij** (`:108-186`); `:174-179` refuses `new_split` on purpose; `:18` `command = …/launch.sh`; `:70-87` padding tuned to seat zellij's status row | **highest-churn single file.** Most unbinds survive but now feed AeroSpace's global hotkeys; `command` and the padding change |
| `term-bindings.nix` + its assertion (in `default.nix:190-193`, message `:546`) | cross-checks the chord table against `config.kdl` | retarget at the ghostty config; the table and the pounce cheatsheet **survive** |
| `zellijLiveConfig` activation (the mtime hack, `:2126`) | forces a live-mtime real file so zellij's watcher reloads | **dies** — Ghostty reloads its own config |
| 5× permission seeds | `:2178`–`:2208` + `zscratch.sh:65` | **die** |
| **tab-bar** fork | agent-count badge beside the tab name | **sill only.** `macos-titlebar-style = hidden` (`ghostty/config:20`) means there is no visible window title to hang a badge on |
| **status-bar** fork | quick-hint block + the tips corpus | sill pill, or retired. **The biggest judgement call in this plan.** |
| **link-handler** fork | click an image path → floating preview pane | Ghostty's own OSC 8 + `link` regex; preview becomes a real kitty render in a floated window |
| **tab-history** fork | MRU tab switching | **dies for free** — AeroSpace already has focus history |
| `find.sh` (⌘F) | `list-panes` + `dump-screen --full` | `aerospace list-windows` + `zmx history` |
| `links.sh` (⌘L, pounce) | `list-sessions` / `list-clients` / `dump-screen` (`:62`, `:69`, `:88`) | `zmx ls` + `zmx history`; moves **with** `statusline.sh`'s map |
| `agents.sh` (sill pill) | `action focus-pane-id` (`:143`), `action list-panes` liveness reaper (`:175`) | `aerospace focus --window-id`; reaper → `zmx ls`. The reaper is what stops the pill accreting ghosts (`modules/sill/options.nix:35`) |
| `agents-peek.sh` | `subscribe --pane-id --ansi -s 300` (`:17`) | `zmx tail` / `history --vt` |
| `agents-hook.sh` | `$ZELLIJ_PANE_ID` gate (`:53`), `zellij pipe` broadcast (`:123`) | zmx session id; broadcast drops (no plugin to feed) |
| `statusline.sh` | keys rows on `$ZELLIJ_PANE_ID` (`:179`), writes the transcript map (`:177-192`) | zmx session id — **same PR as `links.sh`** |
| `spawn-agent.sh` (pounce) | `holt` + a zellij tab for the repo (`:83`) | AppleScript `new window` + surface configuration |
| `new-tab-here.sh` (⌘⇧T) | new zellij tab, cwd inherited | AppleScript `new window`, cwd in the surface config |
| `peek.sh` / `peek-run.sh` (Super-y) | yazi peek in a tab; `modules/hearth/yazi/plugins/peek-open.yazi/main.lua:8` depends on the tab spawn | new window; the yazi plugin moves with it |
| `pounce-terminal.sh` | `POUNCE_TERMINAL_LAUNCHER` (`modules/pounce/default.nix:785`) | new window |
| `nix-config-open.sh` | called by `pounce/commands/nix-config.sh:8` and `sill/…/nix_open.sh:5` | new window |
| `editor-open-pane.sh` + `EditorOpen.app` | new zellij tab running `$EDITOR` | AppleScript `new window` with a surface configuration |
| `gh-dash.sh` | `new-pane --borderless true` fullscreen overlay | its own Ghostty window, floated fullscreen by AeroSpace |
| `copy-clean.pl` | a zellij `copy_command` filter | **lost, not ported.** Ghostty has no copy hook. See risk 4 |
| `zscratch` | throwaway zellij server to test plugin wasm without a rebuild | **loses its reason to exist** — no wasm, and Ghostty hot-reloads. Retire or re-scope |

## The risks

**1 · Ghostty has no plugin system, and won't. 4/5. The real cost.**
Everything the four forks draw must move to sill, or be dropped — and with
`macos-titlebar-style = hidden` there isn't even a window title to fall back
on. tab-history dies free and link-handler has a native replacement, so the
live question is the **status-bar tips corpus**: it is the rice's voice, it
has no natural home in a bar pill, and porting it is a decision about taste,
not a mechanical translation. Budget a real judgement in Phase 6.

**2 · Window sprawl and spawn cost. 3/5. New with decision 2.**
Every pane is now a real macOS window: Mission Control gets noisy, and
window creation is heavier than a pane split. AeroSpace's workspace model
absorbs most of the first problem; the second is unmeasured and is Phase 1's
job. If a spawn costs more than ~250 ms the ⌘A flow will feel worse than it
does today, and that changes Phase 5's shape (a resident helper, or
pre-warmed windows).

**3 · zmx is young, and now load-bearing three ways. 3/5 — but packaged.**
Already in nixpkgs as `pkgs/by-name/zm/zmx/package.nix`, **v0.7.0**, built
with `zig_0_15` and explicitly Darwin-aware (it wraps `xcrun`/`xcode-select`
so Ghostty's Zig build finds the SDK inside the sandbox). No packaging cost.
But this revision makes it identity *and* read API *and* persistence, so a
regression there is not a graceful degradation any more. Sub-1.0, single
maintainer, and a `libghostty-vt` dependency that inherits Ghostty's
cadence. `dtach` is no longer a fallback — it has no `history`/`tail`. If
zmx fails us the fallback is writing the read path ourselves against a PTY
log, which is a project.

**4 · Small behaviours with no Ghostty equivalent. 2/5, but they add up.**
`copy-clean.pl` is the clear one: a zellij `copy_command` filter with no
Ghostty counterpart, so that cleanup is lost rather than ported. The six
patches are the same shape — Phase 4 must audit each and record here which
Ghostty gives us free and which are genuinely gone, rather than discovering
it in use.

**5 · Removing the options is a bigger ripple than removing the code. 3/5.**
`haus.hearth.zellijStartLocked` is public and desktop-safe
(`modules/hearth/options.nix:218`, registered `modules/options-groups.nix:92`,
aliased `modules/renamed.nix:124-125`) and **both shipped desktops set it** —
`desktops/nebelhaus.nix:44` and `desktops/minimal.nix:39` — with pins in
`test/desktop-projection.nix:83` and `test/projections/example.json:26` and
publication in `docs/site-data/options.json`. `haus.hearth.rightClickFullscreen`
is the same story one notch down (`options.nix:239`, `options-groups.nix:91`,
`desktops/nebelhaus.nix:43`, consumed by `modules/pounce/default.nix:324` →
`term-bindings.nix:210` to conditionally draw a cheatsheet row). Deleting a
leaf the rice's *default* desktop names needs a `moved.nix`/`renamed.nix`
decision, a desktop-projection golden regen, and a `site-data` regen or
`site-data-current` goes red. `flake.nix:1281` and `:1324` also carry a
zellij row in the accent-reach golden table.

## The path

Each phase ends shippable. Nothing before Phase 7 changes what a rebuild
gives you by default.

**Phase 0 — probe, no rice change. ~1 session.**
`nix run nixpkgs#zmx`, then live a working day in AeroSpace-tiled Ghostty
windows with zellij still installed and untouched. Both design questions are
already settled, so this is purely about feel: does one-window-per-pane read
as better or as Mission Control soup, and do the four plugins get missed by
evening. If the status bar is missed, Phase 6 gets scoped up front instead
of discovered late.

**Phase 1 — prove both control surfaces, and measure. ~1 session.**
Two scratch scripts, outside the rice.
*Spawn*: AppleScript `new window` with a surface configuration carrying a
worktree cwd + env, running `zmx attach --create <session>`, then
`aerospace move-node-to-workspace`. **Time it** (risk 2).
*Read*: `zmx history --vt` and `zmx tail` against a live session, checked
against what `find.sh` and `agents-peek.sh` actually need. If either fails,
the plan stops here rather than at Phase 5.

**Phase 2 — the seam. ~1 session.**
`haus.hearth.multiplexer = "zellij" | "none"`, defaulting to `zellij`.
Everything after this lands behind it, so `main` is never half-migrated and
a bad day is one option flip back. Room-registry entry + desktop-safety
decision in the same PR (`modules/options-groups.nix`).

**Phase 3 — the identity scheme. ~2 sessions.**
`$ZELLIJ_PANE_ID` → zmx session name + labels, everywhere at once:
`agents-hook.sh:53` (the gate) and `:123`, `statusline.sh:177-192`,
`links.sh`, `agents.sh`, `agents-peek.sh`, `test/statusline.bats:46`. Nothing
downstream is safe to touch before this lands. Do it *dual-path* under the
Phase 2 option so both schemes work during the overlap.

**Phase 4 — Ghostty config + the keybind inversion. ~2 sessions.**
Invert `ghostty/config:108-186`: the unbinds stop feeding zellij and start
feeding AeroSpace's global hotkeys — most survive as unbinds, a few
(⌘W, ⌘D) change meaning. Repoint `:18` `command` at the new launcher, retune
`:70-87` padding now that no status row is seated. Retarget the
`term-bindings.nix` assertion in `default.nix:190-193`. Audit the six patches
one at a time and record the verdicts in this file.

**Phase 5 — retarget the spawners. ~2 sessions.**
`launch.sh`, `spawn-agent.sh`, `new-tab-here.sh`, `peek.sh`/`peek-run.sh`
(plus `yazi/plugins/peek-open.yazi/main.lua:8`), `pounce-terminal.sh`,
`nix-config-open.sh`, `editor-open-pane.sh`, `gh-dash.sh`, `find.sh`.
Mechanical once Phase 1 settled the idiom and Phase 3 settled the ids.

**Phase 6 — the plugin surfaces. ~2 sessions.**
Agent badge → sill. Quick-hints/tips → sill or retired. Image preview →
delete the chafa branch. link-handler → Ghostty OSC 8 + `link` regex.
tab-history → nothing, AeroSpace has it. Taste, not mechanics.

**Phase 7 — flip the default. ~1 session.**
`multiplexer = "none"` by default, zellij still selectable. Live on it.

**Phase 8 — delete. ~2 sessions.**
Drop the four forks, six patches, the KDL, the activations, `copy-clean.pl`
and `zscratch` (or re-scope it) — ~10k lines out. Then the ripple risk 5
describes: retire `zellijStartLocked` and `rightClickFullscreen` through
`moved.nix`/`renamed.nix`, edit both shipped desktops, regen the
desktop-projection goldens and `docs/site-data/`, fix `flake.nix:1281`
and `:1324`. Docs in the same PR: `AGENTS.md`'s architecture map,
`docs/modules.md:98-102` (the "Iterating on a zellij edit" section),
`README.md:118-119`, `bootstrap.sh:385`, and the guides in the workshop's
`web/src/content/docs/`.

**Total ≈ 13 sessions**, with a genuine off-ramp at the end of Phase 0, a
hard stop at Phase 1 if the read path doesn't hold, and a cheap revert at
any point before Phase 8.

## What we're deliberately not doing

| | |
|---|---|
| **tmux** | sixel since 3.4, kitty [an open issue with a PoC branch](https://github.com/tmux/tmux/issues/4902). Costs the same rewrite and loses on every other axis. No. |
| **WezTerm** | **off the table as of decision 1.** Its one advantage over Ghostty here was rendering all three protocols; with sixel unwanted, all that's left is a second terminal to re-theme and a maintainer who calls it a spare-time project. |
| **Ghostty splits** | **off the table as of decision 2.** AeroSpace already tiles, already enumerates, already has focus history and already owns the chord table. A second nested layout model would duplicate all four. |
| **Superlogical** | Hashimoto's new company, announced 2026-07-30: a libghostty session multiplexer with web/iOS reattach. Same primitives, same problem, unknown license, unshipped. **Recheck before Phase 3** — it would replace zmx's role exactly, and Phase 3 is where we'd be committing to zmx's identity scheme. |

## Open questions

1. **Does the status-bar tips corpus survive, and where?** A sill pill is a
   worse home than a status line. It might simply retire. (Risk 1.)
2. **What does a Ghostty window cost to spawn?** Unmeasured, and it sets
   whether ⌘A still feels instant. (Risk 2, Phase 1.)
3. **How much Mission Control noise is too much?** Phase 0 answers it by
   feel, not by argument.
4. **Do the six patches have Ghostty equivalents?** Unknown per-patch until
   Phase 4 audits them; `copy-clean.pl` is already known lost.
