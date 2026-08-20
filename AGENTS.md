# AGENTS.md

**`haus`** — a set of composable nix-darwin modules, plus the desktops built on
them. This repo is the "distro": a personal machine consumes it via `mkHaus` and
adds only its own host (identity, private apps, secrets).

> **This repo holds two things.** **`haus`** is the **layer** — the nix-darwin
> modules, the `haus.*` options and the `haus` CLI — and it is what *any* desktop
> builds on. A **desktop** is one set of values for those modules, and this repo
> ships four: `blank`, `minimal`, `everyday` and **`hacker`** (nebelung's
> fog-grey, windows/bar/terminal turned on the way a developer likes them — the
> first one written, and the one `mkHaus` selects when a consumer names none).
> **hausfold** is neither — it is the org, the maker and the seller, which is why
> the repo is `hausfold/haus`: the layer names the repo, the org names the owner.
> That is **decision 8** (2026-08-10), applied to the slug by **decision 9**
> (2026-08-11) — this repo was `hausfold/hausfold` until then, and every old URL
> still redirects.
>
> Layer and desktop are still interleaved in the same files, because the plan's
> decision 4 renames first and neutralizes the defaults later. So the
> distinction is a **writing** rule right now, not a directory boundary: when you
> touch a module, know whether you're changing what every desktop gets or only
> what `hacker` looks like, and say which in the commit.

> 🚨 **The option namespace is `haus.*`, and it is the only one.** Declare every
> new option under `haus.`, in one of the files `modules/options-modules.nix`
> lists — that list is the single source (`modules/default.nix` imports it;
> don't write the paths out again). There is no second namespace and no alias
> set: `modules/moved.nix` carries only options that changed ADDRESS *inside*
> `haus.*`.
>
> The current spellings, everywhere: `haus.desktops.hacker`,
> `haus.lib.checkDesktop`, `inputs.haus.url`, the builder `mkHaus`, `share/haus/`,
> and the state dirs `~/.local/state/haus`, `~/.config/haus/`, `~/.cache/haus/`,
> `/Library/Application Support/haus/`. The agent skill installs as `haus/`
> inside each client's skills directory (`~/.claude/skills/`, `~/.codex/skills/`,
> `~/.config/opencode/skills/`) and its frontmatter `name:` is `haus`.

**This file is the one set of instructions, for every agent.** Claude Code,
Codex, OpenCode, Cursor, Copilot — TUI or GUI — all read *this*, directly or
through a one-line pointer. Nothing harness-specific belongs here; when a flow
needs per-client wiring (a hook, a slash command), the wiring lives in that
client's own file and the *content* stays here or in `.agents/`. The map of
which tool reads which file is [`.agents/README.md`](./.agents/README.md).
(That's the rule for this repo's *own* files. The rice also **ships** agent
config to end users — `haus.ai.instructions`, `haus.ai.skill`, the
`ai/agents` skill — and that's a product surface, not this layer. It obeys
the same rule one layer out: one body, written once per client at the path that
client reads. Both options were `haus.claude.*` until 2026-08-11, when they
stopped writing Claude's copy alone.)

## Am I in the right repo? (routing)

**This repo (`~/code/workshop/haus`) owns THE LAYER AND THE RICE** — `haus`,
the generic, no-identity system + shell modules, and hacker's default values
on top of them. Personal machine config and the pounce/theme sources live
elsewhere. *(The checkout was `~/code/workshop/hausfold` until 2026-08-11 — it
follows the repo, which is `hausfold/haus`. The desktop is `hacker` since
2026-08-14 — decision 10.)*

| Want to change… | Repo |
|---|---|
| the desktop: macOS defaults, tiling (windows), the menu bar (bar), the shell (terminal), Touch ID + firewall (security), secrets plumbing (secrets), Pounce wiring (launcher), the notch shelf (shelf), Focus/DND (focus), accent + Light/Dark (theme), the generated desktop (wallpaper), the apps every machine gets + what opens which file type (apps) | `~/code/workshop/haus` ← **you are here** |
| the pounce palette app or its command scripts | `~/code/workshop/pounce` |
| colors / the theme palette | `~/code/workshop/nebelung` |
| one machine's personal apps / identity / secrets | `~/.config/nix` (or that machine's own config) |
| user-facing docs / guides (hausfold.co) | `~/code/workshop/hausfold.co` (`content/docs/`, Fumadocs) |

> **Docs live downstream, and since 2026-08-14 that means `hausfold.co`.** The
> how-to guides users read are `content/docs/` in the
> [hausfold.co repo](https://github.com/hausfold/hausfold.co) — two trees,
> `haus/` for this layer and `hacker/` for the desktop. When a change here
> alters user-facing behavior (a new option, a changed keybinding, a workflow),
> update the matching page there too, or it silently drifts.
>
> ⚠️ **Not the workshop's `web/`.** That was the answer until the docs were
> rebuilt on Fumadocs; that tree is **deleted** and there is nothing to route a
> docs fix to but hausfold.co. Rooms, not guides: `haus/rooms/bar.mdx` is what
> `guides/the-bar` became.

> **Whatever agent you are, enforce this.** If a request targets a different repo
> than the one whose files you're in, STOP and say so before editing — e.g.
> "That's a color change; the palette lives in `~/code/workshop/nebelung`. Want
> me to switch?" Never hardcode a user's identity here — it's a `haus.*`
> option the host sets.

## Architecture

```
flake.nix                 # mkHaus builder + darwinModules outputs + example host
modules/
  default.nix             # imports all rooms
  options.nix             # all host-set knobs: git.*, theme.accent, wallpaper.*, terminal.*,
                          #   roster (the shared app list), windows.*, bar.*, launcher.*,
                          #   focus.*, shelf.*, tour.enable, homebrew.*, secrets.provider
  options-modules.nix     # the per-room options.nix list — shared by both renderers below
  options-groups.nix      # the ROOM REGISTRY: every public namespace and darwinModules
                          #   export, its owning room, and whether desktop data may set
                          #   each leaf — plus the twelve rooms themselves, each with the
                          #   title and sentence a renderer lays its catalogue out from.
                          #   `room-registry` fails on anything unmapped or unnamed
  moved.nix               # aliases for options that changed ADDRESS inside haus.* (today:
                          #   the claude room → ai). The 2026-08-13 agents → ai move got
                          #   NO alias on purpose — read the file for why
  options-doc.nix         # nixosOptionsDoc over them → the metadata the docs site
                          #   (.#options-json) and the agent skill are both RENDERED from
  site-data.nix           # .#site-data: that metadata + the binding table, filtered to
                          #   haus.* and pretty-printed, so the docs site can read it with
                          #   NO Nix. Committed at docs/site-data/ — regenerate and commit
                          #   whenever an option moves, or `site-data-current` goes red
  lib/gui-wait.nix        # cold-boot-safe GUI agent launch: .wrap (an executable) +
                          #   .script (the bounded wait alone, for pounce)
  lib/contrib.nix         # extension points: how a room contributes a feature to
                          #   another room without reaching into its config, or
                          #   switching it on. The receiver declares the point
                          #   (haus._contrib.<room>.<feature>), the source writes it
  lib/desktop.nix         # the DESKTOP SEAM's validator: the closed shape a desktop
                          #   file has to have, and the per-leaf desktop-safety walk
                          #   it runs off the room registry. Returns failures rather
                          #   than throwing, so the check can diff the diagnostics
  desktop/                # that seam in the module system: haus._desktop.sources
                          #   (which desktop this machine selected) + the assertion
                          #   that refuses a second one, naming both files
  apps/                   # the EDITORIAL picks: apps the rice chooses for a finished
                          #   machine (IINA today) + the file types they claim. Roster
                          #   entries, so a cask of the same app still collides loudly
    packs/                #   saved app collections, one switch each
                          #   (haus.apps.packs.<name>.enable). This repo's own data
                          #   files — `pack` stopped being a top-level concept in step
                          #   5 of the rooms plan, and `lib.pack`, the seam that let a
                          #   STRANGER publish the same shape, was retired 2026-08-17.
                          #   A stranger's app collection is a room now
  appearance/             # the Appearance room's own PROFILE and nothing else:
                          #   haus.appearance.largePrint sets four other rooms'
                          #   options at once, each at mkDefault. Was
                          #   presets/large-print.nix
  ai/                     # the AI room: haus.ai.* + the coding-agent capability.
                          #   Pure wiring — its assertions, and what it CONTRIBUTES to
                          #   the terminal, the bar and the launcher through the
                          #   extension points those rooms declare (lib/contrib.nix).
                          #   Owns its payload too, in BOTH profiles (2026-08-19):
                          #   holt + the statusline pair + agent-state +
                          #   agent-desktop-guard (system),
                          #   and the instructions/skill files (home, written into
                          #   the same user terminal writes — home-manager merges
                          #   the two, and a path collision is an error)
    agents/               # the haus agent skill (haus.ai.skill): hand-written
                          #   SKILL.md + recipes, plus an option reference rendered
                          #   per-revision — see skill.nix for why it's a package. ONE
                          #   skill, installed into every client in haus.ai.clients
                          #   (this room's agentHomes has the paths; was terminal/claude/
                          #   and Claude-only until 2026-08-11, then terminal/agents/
                          #   until 2026-08-19). Also ships the consumer
                          #   starter pair (consumer-AGENTS.md + its consumer-CLAUDE.md
                          #   pointer) `haus doctor` offers to copy
  core/                   # system: macOS defaults, Homebrew framework, core CLI, GC
                          #   + on-PATH CLIs: haus / haus-activate / awake
                          #   (the statusline pair and agent-state left for ai/)
  displays/               # haus.displays: scaled resolution by intent + the
                          #   hausdisp helper (Swift, xcrun-compiled like pounce's)
  theme/                  # the accent, the flavour, macOS Light/Dark
  wallpaper/              # haus.wallpaper.*: the desktop. `minimal` is GENERATED —
                          #   package.nix renders it (resvg for the vector layer,
                          #   ImageMagick for the 16-bit field), looks/ holds the
                          #   hand-made Nebelung PNGs
  terminal/               # shell: zsh, starship, git, yazi, ghostty + zmx + theming
                          #   + floatring (Swift, xcrun-compiled): the outline every
                          #   window float-term.sh spawns wears (haus.terminal.floatBorder)
  windows/                # AeroSpace tiling
  bar/                    # SketchyBar + barpop (Swift, xcrun-compiled): the pill
                          #   dropdowns' click-outside dismissal
  security/               # auth policy: Touch ID sudo + passwordless activation
  launcher/               # the palette daemon (launchd + self-signing);
                          #   item-grammar.nix mirrors pounce's item-key grammar,
                          #   pinned to the LOCKED pounce by `pounce-item-grammar`
  shelf/                  # the perch notch file shelf, installed via the perch flake input
  focus/                  # Focus/DND one-switch: declarative hotkey 175 + Slack + hooks,
                          #   plus haus.focus.scenes — the same switch with more than one
                          #   member (quiet is the built-in, and the name is reserved).
                          #   Declarative only: a person enters a scene, no trigger daemon
  secrets/                # secretspec: declarative secrets, provider chosen per host
desktops/                 # the desktops this flake ships: hacker (the one the
                          #   builder selects by default), blank, everyday, minimal.
                          #   Data only, one per host, no stacking
compat/presets.nix        # the RETIRED preset format as warning-emitting aliases —
                          #   the old values at the old priority, so an existing
                          #   `extraModules = [ presets.x ]` still builds. Never grow
                          #   it; delete it and the `presets` output together
test/desktops/            # one fixture per rule the desktop seam enforces, valid and
                          #   invalid; `desktop-seam` diffs the diagnostics they produce
hosts/example/            # the template a consumer copies
```

Each `modules/<room>` is a nix-darwin module; ones that need home config write into
`home-manager.users.${username}`. `core` and `terminal` split system vs shell; Homebrew
is contributed per-room (core owns the framework, windows/bar add their own cask/brew).

### Desktops

A **desktop** is a complete, data-only answer to "what should this Mac feel like?",
and a finished configuration runs **exactly one** (the model is the workshop's
`notes/rooms-desktops.md`). `mkHaus` takes a `desktop` argument, defaulting to
`./desktops/hacker.nix`, so every existing consumer's call means what it always
meant. `desktop = null` is the low-level composition escape hatch: by itself it
selects the bare haus foundation, or it makes room for one `lib.desktop` passed
through `extraModules`. A standalone `darwinModules.<room>` import still selects
none by construction.

Three rules, all enforced rather than documented:

- **closed shape** — a desktop is an attrset whose only top-level key is `haus`. No
  module function, no `imports`, no `_module`, no `system.*`/`home-manager.*`. That is
  what makes reading the file enough to know what it can do.
- **desktop-safe leaves only** — every leaf it sets must be a public `haus.*` option
  the room registry marked desktop-safe, transitively: `haus.roster` is a container a
  desktop may fill, `haus.roster.<app>.package` is host-only, and
  `haus.displays.internal` is a desktop value while `haus.displays.<uuid>` is a
  hardware fact. `modules/lib/desktop.nix` is where the registry's named validators
  mean something.
- **the host wins** — a desktop's leaves arrive at priority 900, between an ordinary
  host assignment (100) and a room's own `mkDefault` (1000). Overriding your desktop
  never needs `lib.mkForce`. A list-valued option follows the same rule: when the host
  names that list, its list replaces the desktop's rather than appending to it.

Adding a rule means adding a fixture in `test/desktops/` and its expected diagnostic
in `flake.nix`; a rule with no fixture is a comment. `haus.lib.checkDesktop` /
`haus.lib.desktopFailures` are public so a third party can self-test a desktop before
publishing it.

## Build / test

It's a library, so there's no local machine to switch. Verify it **evaluates**:

```bash
nix eval .#darwinConfigurations.example.system.drvPath
```

The `example` host uses placeholder identity (user `you`), so a full build isn't
meaningful — real testing happens in a consumer (e.g. `~/.config/nix`, host `mbp`).
The workshop's `bench try` (from `~/code/workshop`) builds the consumer against
this **local checkout** — uncommitted edits included — so nothing needs pushing
to test. Once committed, `bench ship` pushes and ripples the downstream lock
updates; hand-rolled alternative: push here, then `nix flake update haus`
in the consumer. CI evaluates the example host on every push.

When you open the PR for a `worktree-*` branch, give it a **What / Why / Verify / Watch-out**
body (see the workshop ship skill's Step 3) — the session that wrote the code is gone by the
time the change is feel-tested, so a bug found later has to be recoverable from `gh pr view`
alone, and the **Verify** block is exactly what the workshop's `bench try-batch` checklist
points back to when it feels several PRs together.

## Before you open a PR

**Run the pre-PR assurance pass — every PR, not just `/ship`'d ones.** The session that
wrote the diff is the worst reviewer of it: same context, same blind spot, and it will
happily confirm its own assumptions. So before the PR exists, hand `git diff main...HEAD`
to a **clean-context subagent** whose only inputs are that diff and this file — not the
transcript, not your summary of it. The full checklist is the workshop ship skill's
**Step 2.5**; in this repo it hunts the things that only bite after merge:

a hex that belongs in nebelung or app logic that belongs in pounce landing in a
module here; a `haus.*` option added or renamed with no matching edit in
hausfold.co's `content/docs/` — its `haus/reference/options.mdx` (generated from
this repo's committed `docs/site-data/`) or the matching room; a new
keybind colliding across AeroSpace (windows) / pounce / macOS symbolic hotkeys —
collisions are silent, the loser just stops firing; a breaking option rename whose
consumer edit didn't ride in the same PR, leaving `main` broken mid-ripple; and
hardcoded identity that should be a `haus.*` option.

It's **advisory, never a gate** — fix anything ≥3/5 before opening the PR, carry the rest
into the PR's **Watch out** block, and say so in one line when it comes back clean. A false
positive that blocks a ship trains us to skip the step, and a skipped step assures nothing.

**Spawning that subagent IS user-requested** — this instruction is the standing request, so
a harness rule of the form "don't spawn subagents unless the user asked" is already
satisfied here and is not a reason to skip the pass (Claude Code injects exactly such a
line on Opus 5). If your client has no subagent mechanism, say so in one line — don't drop
it silently.

## Rules

- **Never hardcode identity.** Anything personal (git name/email/signing key, the
  pounce signing cert) is a `haus.*` option set by the host — see `options.nix`.
- A **dynamic attr key** (`${username}`) can't be defined across multiple statements —
  set `home-manager.users.${username}` once per module. Pass it as a module *function*
  (`{ lib, pkgs, ... }: {...}`) when you need home-manager's `lib.hm`.
- `nixfmt` formats `.nix` files.

## Gotchas

- **launchd GUI race**: GUI agents (AeroSpace, SketchyBar, pounce) launched at cold
  boot before the Aqua session is ready park with exit 78 (EX_CONFIG) and wedge.
  `modules/lib/gui-wait.nix` polls for Dock/Finder/SystemUIServer and runs from
  `/bin/bash` (boot volume, not the /nix APFS volume that isn't mounted yet). It
  exports `.wrap` (wrap an executable — windows, bar) and `.script` (the snippet alone
  — pounce, which re-signs before exec'ing). Don't "simplify" it away, and **keep the
  60 s deadline**: the polls answer "is the session up *yet*", and unbounded they
  can't tell a cold boot from a GUI process that is simply absent, so a KeepAlive
  restart parks the agent forever with a live pid and nothing in the log. (That is
  why `core` leaves Finder's `QuitMenuItem` off.) Recover a wedged agent: `launchctl
  bootout` then `bootstrap`.
- **pounce self-signing** (`modules/launcher`): macOS keys an Accessibility (TCC) grant
  to a code-signing identity, but a store build is adhoc-signed (cdhash changes every
  rebuild). When `haus.launcher.signingIdentity` is set, the daemon wrapper copies
  `Pounce.app` to `~/.local/state/pounce` and re-signs it with a stable identity so the
  grant survives rebuilds. Don't repoint the agent at the store path. One-time on a new
  machine: `pounce --request-accessibility`, approve the prompt (and the keychain
  "Always Allow" dialog the first time `codesign` runs).
- **Homebrew tap-trust** (`modules/core`): `HOMEBREW_NO_REQUIRE_TAP_TRUST=1` via
  `/etc/homebrew/brew.env` — third-party taps fail trust checks under sudo activation.
  That file is also the only place a `HOMEBREW_*` setting reaches the *rebuild's*
  `brew bundle` (activation runs it under a `sudo … env …` that resets everything
  else), so the API-refresh window and the env-hint silencing live there too — an
  export in terminal or bench only ever reaches your interactive shell.
- **Touch ID + a multiplexer** (`modules/security`): `reattach = true` is required
  because sudo can run inside one (tmux/screen, or a `zmx` session — every terminal
  window is one); without pam_reattach the Touch ID prompt beachballs.
- **secretspec + keychain ACLs** (`modules/secrets`): with the default "keyring"
  provider, macOS keys each item's "Always Allow" to the exact binary — a rebuild that
  changes secretspec's store path re-prompts once per secret. Harmless (approve again);
  cloud providers (gcsm/awssm/bws/…) have no per-item ACL. Login-keychain items do NOT
  sync via iCloud — a clean wipe means `secretspec check` + re-entering values.
- **Determinate owns the nix daemon** (`modules/core`): `nix.enable = false`; config
  lives in `/etc/nix/nix.custom.conf`. GC is our own weekly launchd job.
- **The pounce build shells out to `/usr/bin/xcrun swiftc`** — needs Xcode CLT + the
  macOS build sandbox relaxed (Determinate's default). See the pounce repo. So do the
  rice's own four one-file Swift helpers, for the same reason (compiling a Swift
  toolchain from source to build a few hundred lines against AppKit costs hours):
  `hausax` (core), `hausdisp` (displays), `barpop` (bar), `floatring` (terminal).

## Patterns

- **New SketchyBar plugin**: add `modules/bar/sketchybar/plugins/<name>.sh`, wire it
  into `modules/bar/sketchybar/sketchybarrc`. Follow an existing plugin.
- **A plugin that can end up on the SECOND bar must never write `sketchybar`.**
  `haus.bar.bottom.enable` draws a second bar along the bottom of the screen,
  and SketchyBar has no two-bars-in-one-process mode: an instance is named
  `basename(argv[0])` and keys BOTH its lock file and its mach service on that
  name, so the bottom bar is the same binary under a second name (`bar-bottom`,
  a symlink — `BAR_NAME` is exported TO plugins, never read, so setting it on the
  way in does nothing). The consequence is that a bare `sketchybar --set` in a
  plugin ALWAYS means the top bar: same syntax, no error, and a pill that moved
  down just silently stops updating. So `source ~/.config/sketchybar/bar.sh` and
  use `"$SB"` — it routes on `$BAR_NAME`, falling back to `BAR_ITEM`/`$NAME` for
  the HOOK path (agents-hook.sh, the statusline's usage push), which has no bar
  and so no `$BAR_NAME`. Same rule in Nix: `mkPluginBlocks` takes the bar command
  AND the group as its two arguments — a block that hardcodes `right` rather than
  writing `${side}` still evaluates, still builds, and quietly piles its pill back
  into the corner, so thread both through — and **anything that pokes or reloads
  a bar pokes both**, whether it sits outside the bar room (core's `awake` and its
  `caffeinate_change`, the `Reload SketchyBar` palette command) or inside it
  (the logo pill's own `Reload SketchyBar` row — which now runs the palette's
  `reload-bar.sh` rather than carrying a second copy of it — and the
  `.haus-stamp` onChange that
  reloads on rebuild). A bare `sketchybar --reload` reaches one mach service and
  leaves the other bar a generation behind, silently — this list has gained a
  member every time that was forgotten. And **every reload names its rc**
  (`--reload ~/.config/sketchybar/bar-bottomrc`), which is a second, separate
  trap: `--reload` with no path re-runs the config path the instance resolved AT
  STARTUP, and SketchyBar resolves it through the symlink to `/nix/store`, so a
  bar launched with `--config` replays the generation it BOOTED on — every
  reload, exit 0, `configuration loaded..` in the log. That is `bar-bottom` and
  only `bar-bottom` (the menu bar carries no `--config`, so it re-resolves the
  live path by accident), and it cost a day of hausfold#279's `topmost=window`
  never reaching the screen. Which bar is exposed is `ps -o command= -p <pid>` —
  a `--config` in the argv is the whole risk, and `lsof -p <pid> -a -d cwd`
  showing `/nix/store` says the same thing (SketchyBar chdir'd to the resolved
  rc). Neither tells you whether it's *currently* stale, because both stay true
  after a correct reload; for that, read the bar against the generation —
  `bar-bottom --query bar` vs `~/.config/sketchybar/sizes.sh`. Every
  movable pill is emitted from that one table; the coupled left-side
  workspace/leader group and the tour stay on the menu bar. On the MENU bar those
  pills are all `right` (its left and center are spoken for); the bottom bar
  hands out all three of SketchyBar's groups from `haus.bar.bottom.items`, whose
  sides list lives in `modules/bar/sides.nix` — imported by both `options.nix`
  and `default.nix` so the enum and the emission can't disagree.
  macOS reserves the top strip of a display and
  reserves NOTHING at the bottom, so windows's `outerBottom` carves the room instead.
- **Any pill that starts `drawing=off` must also set `updates=on`.** BOTH
  bars' `--default` carries `updates=when_shown` (`sketchybarrc` and
  `bar-bottomrc` alike), and SketchyBar applies that to EVENT delivery, not just
  to `update_freq` ticks: a hidden item is not dispatched to at all, so the very
  script that would turn its drawing back on never runs. Starting hidden is a
  one-way door under the inherited default — which is exactly what kept the
  `page` pill invisible from the day it landed, on the very pages it exists to
  label. It hides well, too: a hand-run `--update` (`SENDER=forced`) DOES reach
  a hidden item, so poking the pill by hand repaints it perfectly and only the
  live event path fails. `media` carries `updates=on` for this on the movable
  side, and `page` and `bar_position` do among the pills `sketchybarrc` writes
  by hand — `page` starts hidden on every workspace that has no pages.
- **A new default app pick** (an app the rice thinks a finished machine has, not one a
  room needs to do its job): it goes in `modules/apps` — one
  `haus.apps.<thing>.enable` knob in its `options.nix`, one roster entry (never a
  bare `home.packages` line), and if it should own file types, `duti` pins in the same
  activation that `lsregister`s the bundle — binding a type LaunchServices hasn't seen
  yet is a silent `-50`. An app a room NEEDS (AeroSpace, SketchyBar, espanso) still
  belongs to that room.
- **A pill with a dropdown toggles it as usual, then arms `barpop` in the
  background** — `sketchybar --set <item> popup.drawing=toggle; barpop arm
  <item> &` (the `popToggle` helper in `modules/bar/default.nix` writes exactly
  that; plugin scripts spell it out with the literal
  `/run/current-system/sw/bin/barpop`). SketchyBar hears clicks on its own items
  and nothing else, so a popup it opened could otherwise only be closed by
  clicking that pill again, while every other dropdown on the Mac closes on a
  click anywhere. `barpop` (`modules/bar/barpop.swift`, built by
  `barpop.nix`) is the missing half: it holds an AppKit global mouse-down monitor
  (Accessibility-gated for KEY events only, so no TCC prompt) and closes the popup
  on the first click outside the bar and outside the popup's own rows. One
  process, alive only while a dropdown is; opening one dropdown closes any other.
  - **The ordering and `&` are load-bearing, and so is the absence of Foundation
    `Process` inside the binary.** A sketchybar round trip costs ~4 ms spawned by
    hand and ~85 ms through `Process` — the first cut armed the guard inline and
    scanned the popup's row rects on the click, which made opening a dropdown take
    ~200 ms and closing the 16-row usage pill over a second. Now the toggle runs
    first and alone, the rects are read once at arm time, and the dismissing call
    is fired without waiting: ~12 ms to open, ~30 ms from click to closed.
  - **The arming gate WAITS for the bar to answer, and an unanswered `--query`
    is not a closed popup.** A pill that REBUILDS its rows before toggling
    (`--remove`, then one `--add` per row — 44 of them on a busy agents popup)
    leaves sketchybar's mach service unable to answer for ~150 ms, and in that
    window `--query <item>` returns an EMPTY STRING rather than
    `drawing: off`. Reading that as "nothing opened" is how the tallest
    dropdowns on the bar became the only ones a click outside never dismissed —
    the guard exited before it ever armed. So `popupDrawing` returns
    `Bool?` with `nil` meaning "no answer", the gate polls (backing off, since
    each retry is a spawn aimed into the busy window) up to 600 ms for a real
    one, and the click path and watchdog test `== false` so a busy bar can't
    reap a guard for a popup still on screen. None of the numbers above move:
    arming is still backgrounded, so the wait is never on the open path.
- **Theme**: `haus.theme.{flavor,contrast}` are the single source of truth, and
  **`modules/lib/nebelung.nix` is the only place that resolves them.** It returns the
  themes-package `root` to source rendered files from, the `palette` (name → hex),
  and the `flavor` — which is load-bearing, not decoration: whiskers names its output
  after the flavor it rendered (`catppuccin-latte.conf`, `Catppuccin Latte.tmTheme`,
  `zen/themes/Latte/`), so paths are built from `nb.flavor`, never the literal
  `"mocha"`. terminal, bar and theme all import it; `catppuccin.flavor` in terminal
  follows it. Getting a path wrong here is INVISIBLE at eval (it's just a store path
  that doesn't exist), which is why `nix flake check`'s `theme-variants` pins the
  flavor/contrast → variant/subdir table as a golden file — and why the same rule
  lives in exactly one place on each side of the repo boundary (nebelung's
  `variantDir`, this file). Raw dotfiles nix can't inject into (ghostty `config`)
  reference the *rendered file*, not the flavor, so they need no per-flavor edit.
  - Adding a flavor means: a nebelung `VARIANTS` entry, one enum value in
    `modules/theme/options.nix`, one row in the `theme-variants` golden table, and a
    `nix flake update nebelung`. Nothing else *for colour* — that's the point of the
    factoring. One non-colour line does want you: `modules/theme/default.nix`'s
    `appearanceWanted` maps flavor → macOS Light/Dark for
    `theme.systemAppearance = "flavor"`, and a flavor it doesn't know silently gets
    Dark. That's a polarity question rather than a palette one, which is why it isn't
    in `modules/lib/nebelung.nix` with the rest — but it is the one place the list
    above doesn't cover.
- **Iterating on a terminal edit costs nothing.** `bench try switch`, and
  Ghostty's own watcher applies the new keybinds, theme and options to every
  running window in about a second. Windows, sessions and live agents stay put —
  and a window's shell lives in a `zmx` session that outlives the window, so even
  a restart comes back to the same scrollback.

  This used to be a two-branch story and both branches left with zellij, which is
  worth recording because the workarounds looked like architecture. A running
  zellij server cached plugin wasm in memory for its whole lifetime, so a plugin
  edit needed a FRESH server — that is what `zscratch` (deleted) existed for. And
  zellij decided "config changed" by mtime, while every `/nix/store` file carries
  mtime = epoch 1, so a home-manager symlink made each rebuild look *older* than
  what the server had already parsed and nothing reloaded — that is why terminal
  installed `config.kdl` as a real file through a `home.activation` block instead
  of `home.file`. Ghostty has no plugins and watches a store symlink happily; both
  hacks are gone and neither should come back.
- **The chord layer is pounce's, not Ghostty's** (`modules/launcher`'s
  `appHotkeys`, cross-referenced by `modules/terminal/ghostty/config` and taught
  by `modules/terminal/term-bindings.nix`). Every terminal chord that *does*
  something — ⌘F, ⌘L, ⌘Y, ⌘N, ⌘↵, ⌘G, ⌘B — is an app-scoped entry in pounce's
  event tap, consumed only while Ghostty is frontmost. This is measured, not
  stylistic: `ghostty +list-actions` on 1.3.1 lists 85 actions and **none of them
  runs a command**, so a chord that shells out has nowhere else to live.
  Ghostty's config unbinds each of them so the tap is not racing a built-in;
  those three files move together or the cheatsheet starts lying.
- **Every window is a `zmx` session** (`modules/terminal/scripts/launch.sh`, which
  is Ghostty's `command`). Persistence is the small half — the load-bearing half
  is that Ghostty's AppleScript API can create a surface but cannot READ one, and
  three shipped features read a window: ⌘F find, ⌘L links, and the bar's agent
  peek. `zmx history` / `zmx tail` is that read API. The session is named
  `term.<n>`, lowest n that no session holds; a lane is `holt.<repo>.<lane>` and
  belongs to `lanes/lane-open.sh`. `scripts/focused-session.sh` is the one
  window→session join — by forced window title for a lane, by a `window=` label
  for everything else.
  - **A NEW window is always a NEW session, and only `restore-windows.sh` ever
    reattaches one.** The claim used to read "lowest n that is not ATTACHED",
    which quietly made ⌘N a lottery: a `term.<n>` left by a closed window is a
    live shell in some other directory, so the chord whose whole promise is "a
    shell HERE" handed you an old one somewhere else, about as often as you had
    parked a window. Walking back in is `scripts/restore-windows.sh` — one
    window per `clients=0` session, automatically for the FIRST window of a
    Ghostty (`haus.terminal.restoreWindows`, and "first" means nothing is
    attached anywhere) and on demand from the palette. It hands `holt.*` to
    `raise-session.sh`, because only `open -na --title` forces the title the
    AeroSpace join reads, and spawns `term.*` itself with `HAUS_ZMX_ATTACH` in
    the environment — a forced title on a plain window would freeze the title
    its program is supposed to own. The user-facing half of the same fact:
    **⌃D ends a shell and frees its number, ⌘W parks it for the next start.**
- **The core CLIs** (`modules/core`, each on `PATH` via `writeShellScriptBin`, source
  beside `default.nix`): core ships three dev/user CLIs — **`haus.sh`** (the
  end-user machine driver: rebuild/update/rollback/doctor/status — knows nothing of
  the family repos), **`haus-activate.sh`** (the privileged half of a rebuild:
  `haus` and `bench` build as YOU, then hand the built store path to
  `sudo haus-activate <system>`, which sets the system profile and runs that
  system's own `darwin-rebuild activate`. It exists so root never evaluates the
  config a SECOND time — `darwin-rebuild switch --flake` builds again, against
  root's separate caches under `/var/root/.cache/nix`, costing ~3 s after a host
  edit and ~15 s whenever a flake input moved. Its stable
  `/run/current-system/sw/bin` path is load-bearing: security's NOPASSWD rule must
  name a literal path), **`awake.sh`** (launchd-owned timed/indefinite macOS
  caffeinate assertions; Bar's optional coffee pill is only its controller),
  Three more were listed here until 2026-08-19 and are the **AI room's** now —
  **`statusline.sh`** / `statusline-refresh.sh` (the
  agent HUD, reading `holt`'s registry) and **`agent-state`** (the one writer of
  agent state behind bar's paw pill) live in `modules/ai`, which writes the
  system profile they land in, because the room that owns a capability owns its
  payload. The last one still
  has no source file of its own: `modules/ai` `readFile`s
  `modules/bar/sketchybar/plugins/agents-hook.sh`, the same script bar installs
  into the bar's plugin dir, so the PATH copy and the bar copy can never drift.
  Every client's hooks call it (`agent-state <working|waiting|idle|remove>
  <client>`) — which is why the wirings the AI room writes for opencode and codex
  never need to know where a bar keeps its plugins.
  They're plain bash embedded via
  `builtins.readFile`, so a rebuild re-installs them on `PATH`. Agent worktrees
  themselves are **`holt`** — [its own repo](https://github.com/hausfold/holt),
  taken as a flake input rather than a core-sourced script, ejected from the
  incubator 2026-08-03 with all 79 acceptance tests green. It replaces the old
  bash `wt.sh`, which has been retired entirely — its registry format, hooks,
  and every caller (Claude Code's `WorktreeCreate`/`WorktreeRemove`, pounce's
  Spawn Agent, `bench status`) now point at `holt` alone; there is no fallback
  to roll back to. `haus` and the workshop's `bench` are named apart on purpose
  so they never shadow each other — `haus` = your machine, `bench` = the family
  repos, `holt` = the worktree tool the rice puts on `PATH` regardless.
  (User-facing docs: the [AI room](https://hausfold.co/docs/haus/rooms/ai/) and the
  [haus reference](https://hausfold.co/docs/haus/reference/haus/) on hausfold.co.)
- **New pounce command**: generic ones live in the
  [pounce repo](https://github.com/hausfold/pounce) (`pkgs/pounce-commands/commands`);
  rice/machine-specific ones live HERE in `modules/launcher/commands/` — one
  self-describing script each (metadata in a `# pounce: key = value` header),
  layered onto the palette via `pounce-commands.override { extraCommandDirs … }`.
  No registry to edit in either repo; drop the script and rebuild.
  - **A script that draws its own list with `pounce` over stdin gets back
    `<action>\t<raw-row>`, not the row** (pounce's `State.swift`,
    `buildCommit`'s `.plain` case) — `action` is `enter`/`cmd`/`opt`/`ctrl`,
    whichever key committed. So the row's own name is field **2**, and a `case`
    on field 1 matches the literal `enter` every time, falls through the
    catch-all arm, and the menu does nothing at all — no error, no log, just a
    row that shrugs. Either strip the verb first (`choice="${choice#*$'\t'}"`,
    what `haus_menu.sh` and `settings.sh` do) or index past it (`field "$sel"
    2`, what `add-app.sh` and `spawn-agent.sh` do). It has cost two silent menus
    so far (#310, and the Haus Settings submenu after it).
- **The haus tour** (first-run tutor): ONE state machine,
  `modules/bar/sketchybar/plugins/tour.sh`, drives a single bar pill. The
  leader-mode scripts + `aerospace-notify.sh` feed it `tour.sh event <name>`
  behind a `[ -f ~/.local/state/haus/tour ]` guard — one stat when idle;
  keep it that cheap. `haus tour` and the pounce `tour` command are just doors
  into it. Gated by `haus.tour.enable` via the generated
  `tour_item.sh` / `tour_config.sh` (see `modules/bar/default.nix`).
