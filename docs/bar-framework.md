# The bar framework

> Status: **phases 1–4a shipped** — `barlib.sh` (the runtime: dispatch, state
> diff, `pill`, `graph`, tones, the four popup row kinds and their value
> column, `bar_emit`), the `# widget:` parser (`modules/bar/manifest.nix`),
> `frameworkBlock` in `modules/bar/default.nix`, and `clock` + `github` +
> `cpu` + `memory` converted, pinned by `test/barlib.bats`. Sections below marked
> **planned** are what is left: the remaining manifest keys, `slider` and
> `badge`, third-party widgets. The code is normative where the two disagree;
> a planned key is an EVAL ERROR today, not a silent no-op, so nothing here
> can be half-used by accident.

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

(`clock.sh` is the smallest running version of this shape; `github.sh` is the
largest — typed sources, a dropdown, a detached network fetch — and the one
the component set was designed against. `cpu.sh` is the one to read for a
graph, a dropdown of numbers, and a widget that keeps CLI paths beside its
handlers; `memory.sh` is the same shape with a verdict of its own, for a pill
whose colour is not a percentage.)

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
| `popup` | `true`/`false` | `false` | the dropdown frame + align; unlocks `popup_*` |
| `subscribes` | list | `system_woke` | bar events and haus signals (see Pubsub) |
| `graph` | points | none | makes the item an `--add graph` of that width, and needs an `interval` (see `graph` under Components) |

Planned keys, landing with the feature that consumes each: `permissions`
(feeds the deck, replacing the `widgets.nix` column), `movable` (the
bottom-bar gate). The parser's known-key set is grown only in the same change
that implements a key, so writing a planned key today is an eval error naming
the file — never a header that parses green and wires nothing.

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

- `pill --icon --label [--tone] [--label-tone] [--hide]` — the standard
  readout, one or two tones. `--tone` paints the icon and `--label-tone` the
  label, which **is** the two-tone pill (github's octocat saying how bad while
  the number says how many) — there is no separate component, passing both
  flags is it. `--hide` performs the `drawing=off updates=on` pair; the
  one-way door ceases to exist as a mistake a widget can make. **Empty means
  absent for both halves**: an empty `--icon` is `icon.drawing=off`, an empty
  `--label` is `label.drawing=off` *and* re-centres the icon (the bar's
  defaults are 8/4 + 4/8, which reads left-heavy the moment the label goes —
  and for a pill that hides a zero, that is its resting state).
- `graph <percent>` — push one point onto the rolling window drawn behind the
  pill's text, for a widget whose header carries `graph = <width>`. The value
  is clamped to 0…1 by the runtime: sketchybar scales a pushed value against
  the item's height and nothing else, so >1 draws off the top of the pill and
  <0 vanishes, and neither reads as an error.

  **Why a readout would want one.** A percentage in a bar answers "how busy,
  right now" and nothing else: it cannot tell you whether 60% is a spike
  settling or a climb that started five minutes ago, which is the actual
  question you glance up to ask. `graph = <width>` makes the item an
  `--add graph` rather than an `--add item` — a normal pill in every other
  respect, icon and label and popup and click handlers all unchanged, plus a
  rolling window of the last `width` pushed values drawn behind the text. The
  width is a POINT COUNT, which is why the manifest refuses it without an
  `interval`: the window is `width × interval` seconds wide — both shipped
  pills carry 48 points, which is two minutes of cpu at its 2 s tick and four
  minutes of memory at its 5 s one.

  ⚠️ **The history lives in the RUNNING item**, not in any file, so a bar
  reload starts the line empty and it fills in over the next window. Worth
  knowing before you see it: the first reload after a rebuild leaves a graph
  pill flat for a whole window — two minutes on cpu, four on memory — and it
  is drawing exactly what it knows.

  ⚠️ **Call it from `fetch`, not `render`** — the one place the fetch/render
  split does not hold, and structural rather than stylistic. `render` is
  diffed, so a machine sitting at one number would stop advancing the window
  for exactly as long as nothing was happening, and a quiet stretch and a
  stalled pill would draw the same flat line; the window is
  `width × interval` seconds wide only if every tick contributes a point. And
  `fetch` does not run on a click at all, which is what makes the second bug
  unreachable rather than merely discouraged: the graph has no time axis of
  its own — it is the last `width` values, evenly spaced — so a point pushed
  by the POINTER shoves the history sideways at the speed of a mouse. Under
  the hand-written cpu pill that was a guard and a comment; through the
  runtime's own dispatch it is unreachable.

  ⚠️ One handler still reaches fetch on purpose: `barlib_tick`. A graph widget
  offering a refresh gesture is back to pushing a point from the pointer — let
  the next tick draw it, or accept that the row is worth a data point.

  A graph pill costs one `$SB` call per tick even when its state is unchanged:
  the push IS the traffic, where a quiet non-graph pill sends nothing at all.
  It is the same one call the hand-written pill made rather than a new price,
  but the zero-traffic promise elsewhere in this doc is about widgets that do
  not push.

  `graph.color` is the widget's to name **in its Nix style, not its script**,
  and is then never touched again: the line is IDENTITY (which readout is
  this) and the label is STATE (is it bad), so a pill under load must not turn
  into two things flashing different colours at once. `frameworkBlock` derives
  `graph.fill_color` from it — the same hue at `0x33` alpha, so a nebelung
  change reaches the fill in the same rebuild it reaches the line — and a
  `graph` with no `graph.color`, or one naming something other than a
  `colors.sh` entry, is an eval error rather than a line the eye cannot
  attribute to a pill.
- `sb_set <prop>=<val>…` — the raw-property escape, still batched. Later args
  in the batch win, so an `sb_set` after a `pill` call overrides it.
- **the dropdown** — `popup_rows()` declares the contents; `popup_open` /
  `popup_close` / `popup_toggle` drive it from a click handler. The runtime
  owns the `--remove` of the old rows, the row item ids, the one batched
  `--add`, the `popup.drawing` flip and the `barpop arm &` with its
  load-bearing ordering — and the query gate, where an *unanswered* `--query`
  is treated as closed rather than open, because a busy bar must not swallow
  a click. Closing never rebuilds: a popup that re-lays-out on the way out is
  how you click the wrong row.

  **Four row kinds**, and their typography belongs to the runtime:

  | kind | weight/size | height | for |
  |---|---|---|---|
  | `popup_heading --label [--icon] [--tone] [--count] [--value]` | Bold, label | 32 | a section title; `--count` appends ` · n` when above zero |
  | `popup_row --label [--icon] [--tone] [--value] [--open <url>] [--run <cmd>]` | Regular, small | 25 | a thing you can act on; a `mute` tone dims the text too |
  | `popup_action --label [--icon] [--tone] [--run <cmd>] [--copy <text>]` | Bold, small | 25 | a verb — Refresh, a command to copy |
  | `popup_note --label` | Italic, tiny | 20 | an aside — "nothing", "+4 more" |

  Four because that is what every popup in this bar already was. A widget
  naming `":Bold:${FS_SMALL}"` itself is the hardcoded-hex mistake one layer
  up, so the fifth kind someone needs is a kind to **add**, not a `--font` to
  add to the signature.

  **`--value` makes a row two columns** rather than one sentence: a name on
  the left and a number that lands on the same x as every number above it.
  The arithmetic is the runtime's for the same reason the fonts are — getting
  it wrong is the one dropdown flaw you see immediately — and it is a pixel
  padding derived from the monospace advance, never trailing spaces, because
  sketchybar sizes an item from its TRIMMED label and then draws the untrimmed
  string, so a space-padded row is clipped by exactly the width of its own
  padding. A name longer than the column gets the minimum gap and pushes its
  own value right: one ragged row, rather than a dropdown sized for the worst
  name on the machine.

  ⚠️ **With a `--value` the tone follows the NUMBER, not the glyph** — the
  name is the question (`user`, `load`, `Safari`) and is always dim, the value
  is the answer and is the only thing on the ladder. A two-column row whose
  name climbed to `bad` alongside it would be one row shouting twice. The
  default is `text` rather than `mute`: a measurement with no verdict is a
  live readout, not an absence. A heading is the exception and takes the
  opposite half — its glyph and title travel together in one hue, because they
  are the same mark and splitting them would spend the value's colour on a
  word.

  That heading hue is `dim` unless the widget says otherwise, and the visible
  consequence is worth naming: the ladder has **no rung for a pill's own
  identity colour** — on purpose, since a rung one widget wants is that
  widget's hex laundered through the framework — so a converted pill's
  dropdown title is grey where the hand-written one was often the pill's own.
  Identity survives where it is legible as identity: the bar icon and the
  graph line, both named in Nix. Every row closes the popup on click; `--open` /
  `--run` / `--copy` run *before* that close, and `--open`/`--copy` are
  single-quote-escaped because a PR title is data.
- `barlib_tick` — run fetch/diff/render now, for a handler that just changed
  the world (github's right-click refresh). Still diffed: a refresh that turns
  up the same numbers costs nothing.

⚠️ **A widget that detaches a copy of itself must strip `$SENDER`** (and
`$BUTTON`/`$MODIFIER`) from the child's environment, and must not let that
child reach `barlib_main`. The runtime routes on `SENDER` and the child
inherits it, so a copy spawned from a click re-enters the handler that
spawned it — an unbounded fork loop past every lock the parent has already
released. Measured on github's right-click before it was fixed: 41 full `gh`
passes and still climbing, against 3 after. `spawn_fetch` is the worked
example (`env -u SENDER -u BUTTON -u MODIFIER`, plus a CLI mode that ends
`barlib_tick; exit 0`), and `test/barlib.bats` pins the shape.

`barlib.sh` itself is shellchecked in CI, because everything it gets wrong is
invisible — a widget's stderr goes to sketchybar's log and nowhere a person
looks. The **widgets** are deliberately not: `fetch` emits state that `render`
reads as plain variables, so every framework widget trips SC2154 by design.

**Components planned** (each lands with the first conversion that needs it,
and that rule is what the two below are still waiting on rather than a
backlog):

- `slider` — media's scrub bar, and it is a **popup row kind** rather than a
  bar component: the only slider in this bar is `media.popup.seek`, added
  inside the dropdown. So it lands beside `popup_row`, when media converts.
- `badge` — no consumer. The one thing in this bar called a badge is media's
  app-icon overlay on the ARTWORK, composited into an image rather than drawn
  by sketchybar, so it is not this component under another name. Left listed
  because a count riding the corner of a pill is a shape the bar will
  eventually want; building it before something asks would be the guess the
  manifest's known-key rule exists to refuse.

## Tones, not colors

Widgets name a **tone**; nothing else is accepted. The ladder started as
github.sh's and is now the WHOLE BAR's — it was widened by surveying what
every pill already spends its colours on, converted or not, because a
vocabulary drawn from one widget is that widget's palette with the serial
numbers filed off. It still matches the agents pill and snug's role system:

| tone | meaning |
|---|---|
| `mute` | nothing there — inactive, stale, no verdict |
| `dim` | present but subordinate — a heading, a row's name, a descriptor |
| `text` | a live readout carrying no alarm — the ordinary foreground |
| `ok` | green, nothing needed |
| `busy` | the machine has it, not you |
| `watch` | worth knowing, nothing to do yet |
| `warn` | wants a human here |
| `bad` | the load-bearing thing is broken |
| `action` | a thing you press — an affordance, not a status |
| `accent` | the rice's own mark — identity, never status |

The ladder is `modules/bar/tones.nix`, and that file is the argument as well
as the list: each rung names the pills that earned it, because **what earns a
rung is a colour the bar already spends, in more than one pill, on one job.**
A rung only one widget wants is that widget's hex laundered through the
framework — the mapping onto an existing rung was already right.

Four of the ten are worth knowing before you pick one:

- **Two dim steps.** `mute` is OFF; `dim` is quiet but present. Six pills
  already use both as a hierarchy — agents paints a popup section glyph
  `overlay1` and the meta row under it `overlay0` (as vitals_lib did before
  the runtime took its rows), and `ai_usage.sh` writes that same two-tier rule
  down as `descr` vs `meta`. One
  rung cannot say both, and a widget with only `mute` can only ever get
  greyer.
- **`text` is deliberately not a verdict** — the way back to neutral after
  painting peach. github's `info` sources are it: a count that is news
  without being bad news.
- **Four severity steps, not three:** ok → `watch` → `warn` → `bad`.
  `vitals_lib.sh` and `ai_usage.sh` each wrote `GREEN → YELLOW → PEACH → RED`
  in a comment and then in code, on identical thresholds, and battery spends
  yellow across its whole 20–80% band. 50% CPU is not "wants a human here",
  and without a name for it the first of those pills to convert would have had
  to keep a hardcoded hex.
- 🚨 **`action` is a thing you press; `accent` is identity and nothing else.**
  `accent` follows `haus.theme.accent`, an enum of fourteen names that
  contains `red`, `peach`, `yellow`, `green` and `sky` — so on somebody's
  machine that tone *is* every verdict rung, and a Refresh row wearing it is
  unreadable there and nowhere else. It also breaks a promise the option's own
  doc makes and `accent-reach` pins: the logo is the only pill that follows
  the accent. Calendar's "Join", caffeinate's stop row and github's Refresh
  all reached for a fixed sapphire independently; that is `action`.

Tone→hex resolves as `TONE_*` exports in the generated `colors.sh`, off the
same nebelung palette everything else uses — the single-resolver rule the
theme room already enforces. An unknown tone paints mute and warns on stderr:
a typo costs a grey pill, never a pill that stops painting.

⚠️ **A rung lives in four files**, and three of them fail silently if you
forget one — the warning above goes to sketchybar's log, where nobody looks,
and the pill just paints grey. So the ladder is defined once in
`modules/bar/tones.nix` and the rest is generated or diffed against it: the
`TONE_*` exports in `modules/bar/default.nix`'s `colorsSh` are **generated**
from it, and the `bar-tones` flake check diffs `tone()`'s case arms in
`barlib.sh`, the table above, and the `colors.sh` stub in
`test/barlib.bats`'s `setup()` — names *and* order — against the same list.
Adding a rung means editing `tones.nix` and then the three the check names
for you.

## Pubsub

`subscribes =` unifies the buses that already exist:

- **sketchybar events** (`system_woke`, `display_change`, …): subscribed
  directly.
- **custom events** (`github_update`, and by convention `haus.<room>.<event>`
  for anything new): the generator emits one `--add event` per name that is
  not one of SketchyBar's own and subscribes the widget. The built-in list
  lives in `manifest.nix` and the split is a **difference against it**, not a
  prefix rule — subscribing to an event nobody declared is silent, and so is
  `--add event volume_change` shadowing the built-in of that name. Producers
  fire them with `bar_emit <event> [key=value…]` (a barlib helper that
  triggers BOTH bars — the "anything that pokes a bar pokes both" rule, in
  code). **Planned**: bridging the remaining producers in — focus changes,
  `agent-state` — so a widget can subscribe to them by name.
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
3. ✅ **github** — the maximal pill (sources, popup, ladder, two-tone), which
   is what the popup components and the `popup` key were designed against.
   Five things it changed on the way through, each because the pill needed it
   and none of which the schema had guessed: the `text` tone; `pill`'s
   empty-label rule (so "hide the zero" stopped being four padding numbers a
   widget had to know); `--count` on a heading; custom events split by
   difference rather than by prefix (a `haus.`-prefix rule left
   `github_update` undeclared — silently); and the runtime stripping
   `<item>.popup.<n>` back to the pill, because a popup row's `click_script`
   re-enters the widget with `NAME` set to the ROW.
4. ✅ **cpu** — the first GRAPH pill, and the first dropdown of numbers.
   Two components came out of it, each because the pill needed one: `graph`,
   whose real design question was not how to push a point but WHICH HALF of
   the fetch/render split it belongs to (fetch — a diffed graph stalls, and a
   graph reachable from a click gets shoved sideways by the pointer); and
   `--value` on the popup rows, because a dropdown of measurements is two
   columns and the alignment is arithmetic no widget should be doing twice.
   It is also the first pill to spend the four severity rungs: `vitals_tone`
   maps the ladder `vitals_color` had climbed in hexes, one to one, which is
   what those rungs were widened for.
5. ✅ **memory** — cpu's twin, and the conversion that ADDED nothing: it
   spends `graph`, `--value`, `dim` and three of the four severity rungs
   exactly as it found them, which is the first evidence the component set is
   a set rather than one pill's needs generalized on the way past. What it
   took away is the point of it — `vitals_lib.sh` lost `vitals_color`, the
   four row builders,
   `vitals_pop_add`, the popup show/open pair, `vitals_pill_of`,
   `vitals_metrics`/`vitals_name_pad`/`vitals_px` and `vitals_fraction`, and
   is now one sample, one ladder and the two things a row can DO.
   It is also the pill that proves a widget may keep a verdict of its own: its
   colour is the kernel's memory-pressure level rather than the percentage, so
   it is the one vitals pill that never calls `vitals_tone` — it maps its own
   three levels onto `ok`/`warn`/`bad` instead. Naming a TONE is all the
   framework asks; where the tone comes from is the widget's business.
6. `permissions` / `movable` manifest keys, third-party framework widgets
   through `haus.bar.widgets`.
7. Long tail: convert on touch. A converted pill's entry in `mkPluginBlocks`
   shrinks to a `frameworkBlock` call carrying only what is IDENTITY — its
   hue, its padding — because the ladder deliberately has no rung for "this
   widget's own colour". The framework wins when every entry in
   `mkPluginBlocks` is one of those.
