# Leaving zellij — Ghostty windows + AeroSpace + zmx (architecture A)

> Status: **done, 2026-08-19.** zellij is gone from the repo, the closure and
> the machine. What follows is kept as the record of WHY, and of what each piece
> cost — the phase plan below was written before any of it shipped, so read it as
> the argument rather than as the state. Where a phase's answer changed on
> contact, the change is recorded in place.
>
> **What actually happened, against the plan.** Phase 0 and 1 ran as written and
> Phase 2's `multiplexer` seam was never built: the lane half had already shipped
> unconditionally (below), the machine had lived on it for three days, and a
> seam exists to make a bad day one flip back — which is worth paying for when
> you don't yet know, and not when you do. Phases 3–8 landed as one change
> instead of six, for the same reason risk 3 predicted: the identity retarget,
> the spawners and the option ripple are not separable. `main` was never
> half-migrated because it went in one PR, which is the other way to get what
> the seam was for.
>
> **The four answers the plan wanted, as measured:**
>
> | | |
> |---|---|
> | Every window is a `zmx` session | `term.<n>`, lowest free n, claimed by `scripts/launch.sh`. NOT because of detach — because Ghostty's AppleScript API cannot READ a surface, and ⌘F/⌘L/peek all read one. `zmx history` is the whole scrollback, which is MORE than `dump-screen --full` gave. |
> | The chord layer is pounce's | `ghostty +list-actions` on 1.3.1: 85 actions, none runs a command. Every chord that does something is an app-scoped `appHotkeys` entry. |
> | Two chords died rather than moving | ⌘⇧T ("new tab at this pane's cwd" — that is what ⌘N means now) and ⌥[/⌥] (zellij swap layouts; windows has its own). ⌘W went back to Ghostty's `close_window`, which is safe now: closing a window DETACHES its session. |
> | The window→session join | A lane by its forced `--title`; everything else by a `window=` label `launch.sh` stamps with the AeroSpace id it tiled. `scripts/focused-session.sh` is the one implementation. |
>
> **What was lost, and it is exactly what risk 4 said.** `copy-clean.pl` — the
> `copy_command` filter that stripped zellij's wrapped-line padding on a mouse
> selection — has no Ghostty counterpart and is not ported; ⌘C over a ⇧-drag
> selection is the whole copy story now. `naked-click-links` went with it: inside
> a mouse-tracking program the click belongs to the program (an SGR mouse report
> has no super bit), so ⌘⇧+click is the only way into Ghostty's own opener. The
> other four patches were moot rather than lost — the per-patch verdicts are in
> `modules/terminal/default.nix`, where the overlay used to be.
>
> **One bug found on the way out**, unrelated to the plan and older than it: both
> `zmx ls` readers looked only for a `cwd=` field, and zmx 0.7.0 emits
> `start_dir=` instead. Every zmx row reached the holt join with an empty path,
> and `lane-cwd.sh`'s zmx branch always fell through to `$HOME`.
>
> **What the pre-PR assurance pass caught, because it is the shape of mistake
> this migration makes.** All four are the same mistake: a chord that used to
> run INSIDE the terminal, ported to a layer that has no terminal around it.
>
> - **⌃⌥⇧A was taught in five places and bound in none.** It was
>   `bind "Ctrl Alt Shift a" { Run <client>; }` in config.kdl, the deletion took
>   it, and nothing re-hosted it — while `term-bindings.nix` still drew the row
>   and four option descriptions still promised it, which meant it would have
>   rendered onto hausfold.co's options reference as a live key. It is
>   `cmd:agent-here` on the Ghostty tap now. *(Retired 2026-08-19: the chord
>   and its command are both gone — `c` in the window's shell is the same act.)*
> - **⌘Y rooted yazi at the pounce daemon's cwd.** Every other moved chord got a
>   `lane-cwd.sh` call; peek was ported without one, so the worktree→main hop —
>   the entire difference between ⌘Y and ⌘⇧Y — was evaluating against launchd's
>   idea of a working directory.
> - **A folded cheatsheet row reserved half its chords.** "⌘ F / ⌘ ⇧ F" exported
>   one `chord`, so ⌘⇧F, ⌘⇧Y and ⌃⇧⇥ were armed with nothing holding them
>   against a `haus.launcher.items` hotkey — a clash that builds green and dies
>   only inside Ghostty.
> - **⌘N windows had no session.** `shell-here.sh` spawned a bare login shell
>   rather than `launch.sh`, so the window you press ⌘F in most often was the
>   one window ⌘F could not read. Under zellij a ⌘N pane was in the session by
>   construction; nothing replaced that until this.
>
> The measurement the last risk wanted: **Ghostty 1.3.1's `command` splitter
> honours single quotes exactly** — a `zsh -c '…'` payload carrying
> `a b.rs:12`, `+12` and `has$dollar` came back out as those three argv entries.
> So `new-window.sh` quotes with single quotes rather than `printf %q`, whose
> backslash form would have needed a second assumption nobody had checked.


## Three decisions, settled 2026-08-14

They were the plan's open questions. All three are answered, and all three
simplify it:

1. **Kitty protocol only. Sixel is not needed.** Ghostty has no sixel
   ([open discussion #2496](https://github.com/ghostty-org/ghostty/discussions/2496))
   and that is an accepted loss, not a risk to manage. This permanently
   removes WezTerm from consideration — being the only terminal that
   renders all three protocols was its entire advantage over Ghostty here.
2. **Windows, not splits.** A "pane" becomes a real Ghostty window that
   AeroSpace tiles. Ghostty's own splits go unused. `launch.sh:44` already
   self-tiles each new Ghostty window onto workspace `T`, so the mechanism
   is proven in-tree — this promotes it from workaround to architecture.
3. **The status-bar fork retires wholesale. Nothing ports.** Its tips are
   *upstream zellij's own* — `quicknav`, `use_mouse`, `compact_layout`,
   `sync_tab`, `zellij_setup_check` and six more, all teaching zellij
   actions through `zellij_tile::prelude` — inherited with the fork, not
   written here. They teach a multiplexer that is going away, and they are
   bound to an API that goes with it. The other half of that plugin, the
   bottom-right quick-hint block, exists only to tell you you are in Locked
   mode and how to leave (`modules/terminal/options.nix:233`); without
   zellij there are no input modes, so it has nothing left to hint. The
   pounce cheatsheet keeps the "what does this key do" job on its own.

Decision 2 pays for itself three times over: pane enumeration becomes
`aerospace list-windows` (a fast CLI, not an osascript round trip), pane
focus becomes `aerospace focus --window-id`, and the navigation chords
already exist and are already on the cheatsheet in
`modules/windows/wm-bindings.nix`. Most of the keybind work becomes deletion
rather than translation.

Decision 3 collapses what looked like this plan's hardest problem into
nothing: **5,991 of the 8,617 forked Rust lines are the status-bar**, and
they now leave with no replacement work at all. What remains needing a home
is the agent-count badge alone, and bar already has the pill for it.

## Decision 4, forced by use, 2026-08-16 — a spawn chord cannot live in the terminal

The plan says "chords move to AeroSpace, not to Ghostty" and files it under
Phase 4. Running one lane backend on zmx brought it forward for a single
chord, because **⌘A stopped working the moment a lane stopped being a pane**,
in two ways that turn out to be the same way:

- **zellij can only run a command by opening a pane for it.** `Run` is the
  only action of its kind. Under the zellij backend that pane WAS the lane,
  so it cost nothing; under zmx `holt new` returns as soon as it has asked
  for a window, so the pane appeared, flashed and was torn down again. That
  is not a bug in the bind. It is a pane being used as a process launcher.
- **⌘A only ever reached zellij by falling through Ghostty.**
  `ghostty/config` unbinds `cmd+a` so the multiplexer can see it — and a zmx
  lane's own window has no multiplexer in it. So the chord worked in exactly
  the windows that already had an agent, and not in the ones spawned from it.

Ghostty cannot take it over: **`ghostty +list-actions` on 1.3.1 lists 85
actions and none of them runs a command** (measured, not read). There is no
`exec`, no shell action, nothing that shells out. This is worth recording
because it closes off the obvious alternative for the whole Phase 4 keymap,
not just this chord: every chord that *does something* — as opposed to
something Ghostty itself implements — has to be an AeroSpace bind.

So the chord is **⌃⌘A**, in `modules/windows/wm-bindings.nix`, running
`modules/terminal/lanes/lane-spawn.sh`, wired through a new
`haus._contrib.windows.agents` extension point. Not ⌘A: a *global* ⌘A would
take select-all away from every application on the machine, which is the
price of one keystroke and far too high. Rejected alongside it: AeroSpace
`on-focus-changed` switching into a terminal-only binding mode so ⌘A could
be app-scoped — AeroSpace modes do not inherit, so every main-mode bind
would have to be duplicated into it, and the mode switch races the focus
change, so a fast ⌘A right after clicking a window lands in the wrong mode.

> **Superseded 2026-08-18, on the key but not the argument.** The chord is
> **⌘↵** now, and it is held by *pounce's* Ghostty-scoped tap
> (`modules/launcher`, `appHotkeys` → `cmd:lane-here` → the same
> `lane-spawn.sh`); `haus._contrib.windows.agents` is gone with it. Everything
> above still holds — a lane is a window, zellij can't run a command without a
> pane, Ghostty can't run one at all — except the conclusion that the chord
> must therefore be *global*. App-scoping is the third option this section
> didn't have when it was written: it arrived for ⌘P/⌘⇧P a phase later (see
> the ⌃⇥ / shell-window note above), and it turns out to fit the spawn chord
> too, because every window worth pressing it from is a Ghostty window.
> ⌘↵ needs it: unlike ⌃⌘A it is *send* in half the Mac, so a global grab was
> never available. The same phase moved the shell-window pair ⌘P/⌘⇧P → ⌘N/⌘⇧N;
> read every ⌘P below as ⌘N.

**The cost this pays, and how it is paid.** A zellij bind inherited the
focused pane's directory for free; a window-layer chord has no directory at
all. The window TITLE is the join in both worlds:

| focused window | what the title is | where cwd comes from |
|---|---|---|
| a zmx lane | `holt.<repo>.<lane>`, forced by lane-open.sh's `--title` | `zmx ls` → that session's `cwd` (a `file://` URL, same strip `agents.sh` does) |
| a zellij window | the zellij **session name** — verified, `aerospace list-windows` prints `Ghostty\|main` | `zellij action dump-layout` → the focused tab's focused pane |
| anything else | — | falls back to `$HOME`; "⌘A from anywhere" beats a refusal |

`dump-layout`'s pane `cwd` is **live, not launch-time** — measured: a pane
whose client had chdir'd into a worktree reported the worktree. Exactly one
tab carries `focus=true` and exactly one pane inside it does, so the parse is
"the focused pane of the focused tab" with brace-depth tracking to stop a
focused pane in another tab from winning.

## The spawn measurement — open question 1, answered

Measured 2026-08-16 on Ghostty 1.3.1, wall-clock from issuing the command to
the window appearing in `aerospace list-windows` (so both numbers carry the
poll loop's own overhead; the **difference** is the signal):

| | time | processes |
|---|---|---|
| `open -na Ghostty.app --args --title=… --initial-command=…` | **366 ms** | spawns a SECOND Ghostty process per lane |
| AppleScript `new window with configuration` | **252 ms** | reuses the running instance |

Two things fall out of that, and the second matters more than the timing:

1. **`ghostty +new-window` is still refused on macOS** ("not supported on
   this platform", 1.3.1), so the CLI is not the third option.
2. **`open -n` means one Ghostty *process* per lane.** `pgrep` during the
   measurement shows the second instance running with the lane's `--title` on
   its argv. That is also *why* the title trick works — `title` is
   instance-global config, forced for every surface in that instance — so the
   forced title and the extra process are the same fact.

Which sets up the trade that risk 1 didn't anticipate. AppleScript is faster
and shares one instance, and its `surface configuration` carries
`initial working directory`, `command`, `environment variables` and
`wait after command` natively — which would delete lane-open.sh's temp
launcher script, its three levels of `printf %q` quoting, and its `bash -lc`
(the login shell that currently drags a stale `~/.profile` into every lane
window). But the record has **no title property, and window `name` is
read-only**, so "the name is the join" would need a different mechanism:
either an OSC 2 the client can clobber, or a spawn-time
`window-id ↔ session` map — which is the per-pane state file the zmx design
set out to abolish.

**Decided 2026-08-16, and measured twice over: lanes stay on `open -na`;
everything else spawns by AppleScript.** `set_surface_title` via
`perform action` does set a title AeroSpace reads — which briefly made the
AppleScript path look free — but it is a **starting value, not a lock**: the
next OSC 2 out of the client overwrites it, and OSC 2 passes straight through
zmx (both measured on 1.3.1, a scripted window retitled by an inner
`printf '\033]2;…'` behind `zmx attach`). Claude Code retitles constantly, so
the machine-readable `holt.*` name would survive only until the client's first
thought. The forced `--title` — and the second Ghostty process it drags in,
since `title` is instance-global config — is therefore the price of the join
itself, paid only by lane windows. The plain shell windows ⌘P/⌘⇧P spawn carry
no name anything joins on, so they take the fast path: AppleScript
`new window with configuration`, cwd and (for ⌘⇧P) `HAUS_STAY=1` in the
surface configuration.

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

`modules/terminal/zellij/image-preview.sh:7` already documents the dead end in
its own header: zellij's VTE parser drops kitty APC outright, and forwards
sixel only when the host terminal advertises it in DA1 — which Ghostty
doesn't. That file renders half-block chafa art *because* of the
multiplexer, and its `fmt=kitty` branch (already written, `:78`) is what
fires when `$ZELLIJ` is unset. The escape hatch is in the tree already.

Four things come along for free once the multiplexer is gone:

| | |
|---|---|
| **The patch treadmill** | Six patches against `zellij-unwrapped` (`modules/terminal/default.nix:781`). Any nixpkgs bump that moves zellij or its deps can break the build, as the file's own comment at `:772` says. |
| **The permission-cache hack** | Four `home.activation` blocks seeding grants straight into zellij's plugin permission cache (`:2178`–`:2208`), plus a fifth site in `modules/core/zscratch.sh:65`, because the real path is an interactive y/n prompt a background plugin can never answer. |
| **8,617 lines of Rust** | Four plugin forks we maintain against a moving `zellij-tile` API — 5,991 of them the status-bar, which decision 3 retires outright. |
| **Latency** | One fewer VTE parse + reflow per keystroke, and no wasm plugin tick. |

## The shape

```
Ghostty 1.3+          the terminal. One window per pane, kitty graphics,
                      config hot-reload. Splits unused.
├── windows (AeroSpace) LAYOUT + ENUMERATION + FOCUS.
│                     `list-windows`, `focus --window-id`, workspace T.
│                     Already installed, already bound, already on the cheatsheet.
├── zmx               IDENTITY + PERSISTENCE + READ. One session per pane.
│                     `ls --where`, `history --vt`, `tail`, `send`, `run`.
│                     No windows, no tabs, no splits, deliberately.
├── AppleScript       SPAWN only. `new window` with a surface configuration
│                     carrying cwd/command/env, plus `perform action`.
└── bar              absorbs every status surface the plugins used to draw
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
| ⌘L links picker | same (`modules/launcher/commands/links.sh:88`) | `zmx history <session>` |
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
the gate is harder than it looks. `modules/bar/sketchybar/plugins/agents-hook.sh:53`
is a bare `[ -n "${ZELLIJ_PANE_ID:-}" ] || exit 0` — so under
`multiplexer = "none"` **every agent lifecycle hook from every client exits
at that line**, and the paw pill, the statusline HUD and the tab badge all
go dark at once. That file is also what core `readFile`s to put `agent-state`
on `PATH` (`modules/core/default.nix:647`), so it is one edit with three
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
| windows / AeroSpace | tiles Ghostty windows | **survives and grows**: layout + enumeration + focus |
| `modules/windows/wm-bindings.nix` | the WM chord table + cheatsheet cards | **survives**, absorbs the pane-navigation rows |
| `launch.sh` | attach-or-create `main`, self-tile onto workspace T | shrinks to `zmx attach --create` + the same self-tile |
| `image-preview.sh` | chafa `symbols` half-blocks | delete the symbols branch, keep `fmt=kitty`; real pixels |
| 6× `zellij-unwrapped` patches | right-click zoom, naked-click links, selection autoscroll, … | **die** — audit each against Ghostty's native behaviour (Phase 4) |
| `config.kdl` + `custom.kdl` (750 lines) | keybinds, layout, theme | mostly **deleted**; chords move to AeroSpace, not to Ghostty |
| `modules/terminal/ghostty/config` | ~15 `unbind` entries exist to let chords **fall through to zellij** (`:108-186`); `:174-179` refuses `new_split` on purpose; `:18` `command = …/launch.sh`; `:70-87` padding tuned to seat zellij's status row | **highest-churn single file.** Most unbinds survive but now feed AeroSpace's global hotkeys; `command` and the padding change |
| `term-bindings.nix` + its assertion (in `default.nix:190-193`, message `:546`) | cross-checks the chord table against `config.kdl` | retarget at the ghostty config; the table and the pounce cheatsheet **survive** |
| `zellijLiveConfig` activation (the mtime hack, `:2126`) | forces a live-mtime real file so zellij's watcher reloads | **dies** — Ghostty reloads its own config |
| 5× permission seeds | `:2178`–`:2208` + `zscratch.sh:65` | **die** |
| **tab-bar** fork | agent-count badge beside the tab name | **bar only.** `macos-titlebar-style = hidden` (`ghostty/config:20`) means there is no visible window title to hang a badge on |
| **status-bar** fork (5,991 lines) | quick-hint block + 11 tip data files | **retires wholesale — decision 3.** Tips are upstream zellij's, teaching zellij; the quick-hint block only ever explained Locked mode |
| **link-handler** fork | click an image path → floating preview pane | Ghostty's own OSC 8 + `link` regex; preview becomes a real kitty render in a floated window |
| **tab-history** fork | MRU tab switching | **dies for free** — AeroSpace already has focus history |
| `find.sh` (⌘F) | `list-panes` + `dump-screen --full` | `aerospace list-windows` + `zmx history` |
| `links.sh` (⌘L, pounce) | `list-sessions` / `list-clients` / `dump-screen` (`:62`, `:69`, `:88`) | `zmx ls` + `zmx history`; moves **with** `statusline.sh`'s map |
| `agents.sh` (bar pill) | `action focus-pane-id` (`:143`), `action list-panes` liveness reaper (`:175`) | `aerospace focus --window-id`; reaper → `zmx ls`. The reaper is what stops the pill accreting ghosts (`modules/bar/options.nix:35`) |
| `agents-peek.sh` | `subscribe --pane-id --ansi -s 300` (`:17`) | `zmx tail` / `history --vt` |
| `agents-hook.sh` | `$ZELLIJ_PANE_ID` gate (`:53`), `zellij pipe` broadcast (`:123`) | zmx session id; broadcast drops (no plugin to feed) |
| `statusline.sh` | keys rows on `$ZELLIJ_PANE_ID` (`:179`), writes the transcript map (`:177-192`) | zmx session id — **same PR as `links.sh`** |
| `spawn-agent.sh` (pounce) | `holt` + a zellij tab for the repo (`:83`) | AppleScript `new window` + surface configuration |
| `new-tab-here.sh` (⌘⇧T) | new zellij tab, cwd inherited | AppleScript `new window`, cwd in the surface config |
| `peek.sh` / `peek-run.sh` (Super-y) | yazi peek in a tab; `modules/terminal/yazi/plugins/peek-open.yazi/main.lua:8` depends on the tab spawn | new window; the yazi plugin moves with it |
| `pounce-terminal.sh` | `POUNCE_TERMINAL_LAUNCHER` (`modules/launcher/default.nix:785`) | new window |
| `nix-config-open.sh` | called by `pounce/commands/nix-config.sh:8` and `bar/…/nix_open.sh:5` | new window |
| `editor-open-pane.sh` + `EditorOpen.app` | new zellij tab running `$EDITOR` | AppleScript `new window` with a surface configuration |
| `gh-dash.sh` | `new-pane --borderless true` fullscreen overlay | its own Ghostty window, floated fullscreen by AeroSpace |
| `copy-clean.pl` | a zellij `copy_command` filter | **lost, not ported.** Ghostty has no copy hook. See risk 4 |
| `zscratch` | throwaway zellij server to test plugin wasm without a rebuild | **loses its reason to exist** — no wasm, and Ghostty hot-reloads. Retire or re-scope |

## The risks

Decision 3 removed what was the 4/5 here. What's left is ordered by
severity, and nothing in it is a blocker on its own.

**1 · Window sprawl and spawn cost. 3/5. New with decision 2.**
Every pane is now a real macOS window: Mission Control gets noisy, and
window creation is heavier than a pane split. AeroSpace's workspace model
absorbs most of the first problem; the second is unmeasured and is Phase 1's
job. If a spawn costs more than ~250 ms the ⌘A flow will feel worse than it
does today, and that changes Phase 5's shape (a resident helper, or
pre-warmed windows).

**2 · zmx is young, and now load-bearing three ways. 3/5 — but packaged.**
Already in nixpkgs as `pkgs/by-name/zm/zmx/package.nix`, **v0.7.0**, built
with `zig_0_15` and explicitly Darwin-aware (it wraps `xcrun`/`xcode-select`
so Ghostty's Zig build finds the SDK inside the sandbox). No packaging cost.
But this revision makes it identity *and* read API *and* persistence, so a
regression there is not a graceful degradation any more. Sub-1.0, single
maintainer, and a `libghostty-vt` dependency that inherits Ghostty's
cadence. `dtach` is no longer a fallback — it has no `history`/`tail`. If
zmx fails us the fallback is writing the read path ourselves against a PTY
log, which is a project.

**3 · Removing the options is a bigger ripple than removing the code. 3/5.**
`haus.terminal.zellijStartLocked` is public and desktop-safe
(`modules/terminal/options.nix:218`, registered `modules/options-groups.nix:92`,
aliased `modules/renamed.nix:124-125`) and **both shipped desktops set it** —
`desktops/hacker.nix:44` and `desktops/minimal.nix:39` — with pins in
`test/desktop-projection.nix:83` and `test/projections/example.json:26` and
publication in `docs/site-data/options.json`. `haus.terminal.rightClickFullscreen`
is the same story one notch down (`options.nix:239`, `options-groups.nix:91`,
`desktops/hacker.nix:43`, consumed by `modules/launcher/default.nix:324` →
`term-bindings.nix:210` to conditionally draw a cheatsheet row). Deleting a
leaf the rice's *default* desktop names needs a `moved.nix`/`renamed.nix`
decision, a desktop-projection golden regen, and a `site-data` regen or
`site-data-current` goes red. `flake.nix:1281` and `:1324` also carry a
zellij row in the accent-reach golden table.

**4 · Small behaviours with no Ghostty equivalent. 2/5, but they add up.**
`copy-clean.pl` is the clear one: a zellij `copy_command` filter with no
Ghostty counterpart, so that cleanup is lost rather than ported. The six
patches are the same shape — Phase 4 must audit each and record here which
Ghostty gives us free and which are genuinely gone, rather than discovering
it in use.

**5 · One plugin surface still needs a home. 2/5, down from 4/5.**
Ghostty has no plugin system and won't, and `macos-titlebar-style = hidden`
(`ghostty/config:20`) means there is no window title to fall back on either.
But after decision 3 the list is short: status-bar retires, tab-history dies
free (AeroSpace has focus history), link-handler has a native replacement
(OSC 8 + `link` regex). That leaves the **agent-count badge**, and bar
already draws the paw pill it belongs on — a count is an increment, not a
port.

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
`haus.terminal.multiplexer = "zellij" | "none"`, defaulting to `zellij`.
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

**Phase 6 — the one remaining plugin surface. ~1 session.**
Agent badge → a count on bar's existing paw pill. Image preview → delete
the chafa branch. link-handler → Ghostty OSC 8 + `link` regex. status-bar
and tab-history need nothing (decision 3; AeroSpace has focus history).

**Phase 7 — flip the default. ~1 session.**
`multiplexer = "none"` by default, zellij still selectable. Live on it.

**Phase 8 — delete. ~2 sessions.**
Drop the four forks, six patches, the KDL, the activations, `copy-clean.pl`
and `zscratch` (or re-scope it) — ~10k lines out. Then the ripple risk 3
describes: retire `zellijStartLocked` and `rightClickFullscreen` through
`moved.nix`/`renamed.nix`, edit both shipped desktops, regen the
desktop-projection goldens and `docs/site-data/`, fix `flake.nix:1281`
and `:1324`. Docs in the same PR: `AGENTS.md`'s architecture map,
`docs/modules.md:98-102` (the "Iterating on a zellij edit" section),
`README.md:118-119`, `bootstrap.sh:385`, and the guides in the workshop's
`web/src/content/docs/`.

**Total ≈ 12 sessions**, with a genuine off-ramp at the end of Phase 0, a
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

1. ~~**What does a Ghostty window cost to spawn?**~~ **Answered 2026-08-16** —
   366 ms via `open -na` (plus a whole second Ghostty process per lane),
   252 ms via AppleScript into the running instance. See "The spawn
   measurement" above. Both are over risk 1's ~250 ms line as measured,
   though the poll loop is inside both numbers. The narrower follow-up —
   does losing the forced title cost more than the 114 ms and the extra
   process? — ~~is open~~ **answered the same day: yes, for lanes.**
   `set_surface_title` turned out to be clobbered by the client's next OSC 2
   (which zmx forwards), so the forced `--title` is the only title nothing
   inside the window can take away, and lane windows keep `open -na`.
   Windows that carry no joinable name (⌘P/⌘⇧P shells) use the AppleScript
   path.
2. **How much Mission Control noise is too much?** Phase 0 answers it by
   feel, not by argument.
3. **Do the six patches have Ghostty equivalents?** Unknown per-patch until
   Phase 4 audits them; `copy-clean.pl` is already known lost.
