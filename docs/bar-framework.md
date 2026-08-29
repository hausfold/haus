# The bar framework

> Status: **phase 1 shipped** — `barlib.sh` (the runtime: dispatch, state
> diff, `pill`, tones, `bar_emit`), the `# widget:` parser
> (`modules/bar/manifest.nix`), `frameworkBlock` in `modules/bar/default.nix`,
> and `clock` as the first converted widget, pinned by `test/barlib.bats`.
> Sections below marked **planned** describe what the github conversion adds
> next — popups, the wider component set, the extra manifest keys. The code is
> normative where the two disagree; a planned key is an EVAL ERROR today, not
> a silent no-op, so nothing here can be half-used by accident.

## Why

Every hard-won rule about writing a bar plugin currently lives as prose in
AGENTS.md and conventions scattered through `modules/bar/default.nix` — the
`$SB` router, the `updates=on` one-way door, the `popToggle`+`barpop` ordering,
`mkPluginBlocks`' `${side}` discipline, hand-picked palette hexes. A
contributor writing pill #39 must internalize all of it, and a mistake fails
silently (a pill that stops updating, a popup that won't close, a dropdown on
the wrong bar).

The framework reifies those rules as code. A widget becomes **one
self-describing file** — the same shape as a pounce command (`# pounce:`
header, no registry) — and the runtime owns everything the file doesn't say.

## The shape of a widget

```bash
#!/bin/bash
# widget: interval   = 60
# widget: subscribes = haus.github.delivery

BAR_ITEM=github
source "$HOME/.config/sketchybar/barlib.sh"

fetch() {                       # impure: gather the world, emit state
  emit count=3 tone=warn label="3 PRs"
}

render() {                      # pure: state in, components out
  pill --icon "" --label "$label" --tone "$tone"
}

on_click()     { open "https://github.com/pulls"; }

barlib_main "$@"
```

(`clock.sh` is the real, running version of this shape.)

Everything else — which bar instance, event wiring, `updates=`, state caching,
diffing, tone→hex — belongs to the runtime. A widget script never calls
`sketchybar`, never reads `$BAR_NAME`, never names a hex. `sb_set` is the
low-level escape for raw properties on the widget's own item; leaning on it
for everything is the signal a component is missing.

Two tiers today, so the trivial case stays trivial:

1. **`command`** (exists, unchanged): a script whose stdout is the label,
   run on a timer — `haus.bar.widgets.<name>.command`. No header needed.
2. **framework widget**: the file above. `fetch`/`render` split, optional
   click handlers.

## The manifest (`# widget:` header)

Parsed at Nix eval (`builtins.readFile` over the script), so the header is
the single source for wiring — no parallel table edit. Keys:

| key | type | default | meaning |
|---|---|---|---|
| `interval` | seconds | none | `update_freq`; omit for purely event-driven |
| `subscribes` | list | `system_woke` | bar events and haus signals (see Pubsub) |

Planned keys, landing with the feature that consumes each: `popup` (a
declared dropdown, runtime-owned toggle + barpop — the github conversion),
`permissions` (feeds the deck, replacing the `widgets.nix` column), `movable`
(the bottom-bar gate). The parser's known-key set is grown only in the same
change that implements a key, so writing a planned key today is an eval
error naming the file — never a header that parses green and wires nothing.

Unknown keys are an **eval error**, not a silent ignore — the lesson
`pounce-command-keys` exists to teach, enforced one layer earlier because here
the parser and the scripts live in the same repo, and at eval rather than in
a flake check because the parse IS the emission's input.

Presentation and registry facts that are prose or policy — `description`,
`default` — stay in `widgets.nix`; the header carries only what the runtime
and generator consume.

**Planned**: third-party FRAMEWORK widgets through the open form
(`haus.bar.widgets.<name>` today takes only the timer-driven `command`; a
`script` field whose header is read the same way is the natural extension —
it's a store path, `readFile` works).

## The runtime (`barlib`)

A framework widget sources `barlib.sh` at its top and calls
`barlib_main "$@"` as its last line — the file itself is the `script=`, so
running it by hand (`BAR_ITEM=clock ./clock.sh`) is the debugging story.
`barlib_main`:

1. has `bar.sh` → `$SB` already sourced (the existing router, absorbed
   unchanged), plus `colors.sh`/`sizes.sh`, all guarded so a test harness
   can pre-seed them
2. routes by `$SENDER`:
   - `mouse.clicked` → `on_click` / `on_right_click` / `on_middle_click` /
     `on_{cmd,alt,shift,ctrl}_click` (from `$BUTTON`/`$MODIFIER`; the button
     outranks the modifier, and an unhandled chord falls back to `on_click`)
   - `mouse.scrolled` → `on_scroll`; `mouse.entered`/`exited` →
     `on_hover`/`on_unhover`
   - anything else → `fetch`, then diff, then maybe `render`

**Reactive means: state → diff → render → one batched apply.**

- `emit key=value…` accumulates this tick's state.
- The runtime compares it to the cached state
  (`~/.cache/haus/bar/<widget>.state`). Identical → **zero** sketchybar
  traffic, `render` never runs.
- Changed → state is exported as variables, `render` runs, and every
  component call accumulates `--set`/`--add` arguments into one array.
- One `$SB` invocation applies the batch. (barpop measured the spawn tax:
  ~4 ms per hand-spawned call — twelve `--set`s as one call, not twelve.)

**Components shipped**:

- `pill --icon --label --tone [--label-tone] [--hide]` — the standard
  readout. `--hide` performs the `drawing=off updates=on` pair; the one-way
  door ceases to exist as a mistake a widget can make. An empty `--icon`
  turns the icon off rather than drawing a blank.
- `sb_set <prop>=<val>…` — the raw-property escape, still batched.

**Components planned** (each lands with the first conversion that needs it —
the github pill covers most):

- `two_tone_pill` — github.sh's split count/state pill, promoted.
- `popup_row --text --tone [--icon] [--run <cmd>]` — declarative dropdown
  rows; the runtime does remove/re-add and the `popToggle` + `barpop arm &`
  dance with its load-bearing ordering, plus `popup_heading` and
  `popup toggle|open|close` for handlers.
- `graph`, `slider`, `badge` — wrap sketchybar's own primitives (vitals,
  media already use them by hand).

## Tones, not colors

Widgets name a **tone**; nothing else is accepted. The ladder is github.sh's,
promoted to the framework vocabulary because it already matches the agents
pill and snug's role system:

| tone | meaning |
|---|---|
| `mute` | no verdict / inactive |
| `ok` | green, nothing needed |
| `busy` | the machine has it, not you |
| `warn` | wants a human here |
| `bad` | the load-bearing thing is broken |
| `accent` | the rice's accent, for identity not status |

Tone→hex resolves as `TONE_*` exports in the generated `colors.sh`, off the
same nebelung palette everything else uses — the single-resolver rule the
theme room already enforces. An unknown tone paints mute and warns on stderr:
a typo costs a grey pill, never a pill that stops painting. **Planned**: a
flake check pinning the tone table the way `theme-variants` pins the flavor
table.

## Pubsub

`subscribes =` unifies the buses that already exist:

- **sketchybar events** (`system_woke`, `display_change`, …): subscribed
  directly.
- **haus signals** (`haus.<room>.<event>`): the generator emits one
  `--add event` per distinct name and subscribes the widget. Producers fire
  them with `bar_emit <event> [key=value…]` (a barlib helper that triggers
  BOTH bars — the "anything that pokes a bar pokes both" rule, in code).
  **Planned**: bridging the existing producers in — the github room's
  delivery signal, focus changes, `agent-state` — so a widget can subscribe
  to them by name. No widget subscribes to a haus signal yet, so this path
  is wired but unexercised until then.
- Widgets may `bar_emit` too — inter-widget signaling without knowing names.

## Why not SbarLua

Evaluated 2026-08 (FelixKratz/SbarLua at `dba9cc42`). The architecture is
genuinely better — the Lua config becomes a resident mach-IPC event server,
zero fork/exec per event, and `sbar.set_bar_name` clears our two-bar
requirement. But it is effectively unmaintained: ~10 commits since Feb 2024,
and three substantive bug-fix PRs (Jul–Aug 2026) sit unreviewed for bugs that
are disqualifying on a machine haus ships to: a **permanent mach send
deadlock** that freezes the bar until force-quit (PR #64), a **zombie leak
that can exhaust `kern.maxprocperuid`** and break every `fork()` on the host
(PR #63), and transaction desyncs (PR #62). Single event-handler thread, and
the binary module tracks Lua interpreter versions (the 5.4→5.5 bump broke
downstreams). Adoption is real but niche (nixpkgs `sbarlua`, home-manager
`configType = "lua"`, ~338 stars) and the reference framework is one person's
dotfiles.

Revisit if upstream maintenance resumes; the manifest schema here is what a
Lua (or Go daemon) runtime would consume, so nothing built now is thrown away.

## What does NOT change

- `bar.sh`, `$BAR_NAME`, the two-instance model — barlib sits on top.
- `haus.bar.items` / `bar.bottom.items` sugar, `widgets.nix` as the
  registry of bundled names, `reservedItemIds`.
- Existing plugins keep working untouched. Migration is opportunistic —
  one pill per touch, never a big bang.

## Migration order

1. ✅ **barlib.sh + runtime + tone table** — pure addition, nothing breaks.
2. ✅ **clock** — smallest pill, proves the end-to-end path (header →
   generator → runtime → render). `test/barlib.bats` pins the runtime.
3. **github** — the maximal pill (sources, popup, ladder, two-tone); proves
   the API is *sufficient*. Gaps found here change the schema — that's why
   it's next, before the schema calcifies, and it brings the `popup` key and
   the popup components with it.
4. `permissions` / `movable` manifest keys, the tone-table golden check,
   third-party framework widgets through `haus.bar.widgets`.
5. Long tail: convert on touch. A converted pill deletes its block from
   `mkPluginBlocks`; the framework wins when `mkPluginBlocks` is empty.
