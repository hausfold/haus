# AGENTS.md

**`haus`** — a set of composable nix-darwin modules, plus the desktops built on
them. This repo is the "distro": a personal machine consumes it via `mkHaus` and
adds only its own host (identity, private apps, secrets).

> **This repo holds two things.** **`haus`** is the **layer** — the nix-darwin
> modules, the `haus.*` options and the `haus` CLI — and it is what *any*
> desktop builds on. A **desktop** is one set of values for those modules, and
> this repo ships four: `blank`, `minimal`, `everyday` and **`hacker`**
> (nebelung's fog-grey, windows/bar/terminal turned on the way a developer likes
> them, and the one `mkHaus` selects when a consumer names none). **hausfold**
> is neither — it is the org, the maker and the seller, which is why the repo is
> `hausfold/haus`: the layer names the repo, the org names the owner.
>
> Layer and desktop are still interleaved in the same files, so the distinction
> is a **writing** rule rather than a directory boundary: when you touch a
> module, know whether you're changing what every desktop gets or only what
> `hacker` looks like, and say which in the commit.

> 🚨 **The option namespace is `haus.*`, and it is the only one.** Declare every
> new option under `haus.`, in one of the files `modules/options-modules.nix`
> lists — that list is the single source (`modules/default.nix` imports it;
> don't write the paths out again). There is no second namespace and no alias
> set: `modules/moved.nix` carries only options that changed ADDRESS *inside*
> `haus.*`, and `haus.agents.*` deliberately has none, so writing it is an eval
> error rather than a warning.
>
> The current spellings, everywhere: `haus.desktops.hacker`,
> `haus.lib.checkDesktop`, `inputs.haus.url`, the builder `mkHaus`,
> `share/haus/`, and the state dirs `~/.local/state/haus`, `~/.config/haus/`,
> `~/.cache/haus/`, `/Library/Application Support/haus/`. The agent skill
> installs as `haus/` inside each client's skills directory
> (`~/.claude/skills/`, `~/.codex/skills/`, `~/.config/opencode/skills/`,
> `~/.pi/agent/skills/`) and
> its frontmatter `name:` is `haus`.

**This file is the one set of instructions, for every agent** — Claude Code,
Codex, OpenCode, pi, Cursor, Copilot alike, directly or through a one-line
pointer.
Per-client wiring lives in that client's own file; the content stays here or in
[`.agents/`](./.agents/README.md). That's the rule for this repo's *own* files.
haus also **ships** agent config to end users — `haus.ai.instructions`,
`haus.ai.skill`, the `ai/agents` skill — which is a product surface obeying the
same rule one layer out: one body, written once per client at the path that
client reads.

## Am I in the right repo? (routing)

**This repo owns THE LAYER AND THE DESKTOPS** — the generic, no-identity system
+ shell modules, and hacker's default values on top of them. Personal machine
config and the pounce/theme sources live elsewhere.

| Want to change… | Repo |
|---|---|
| the desktop: macOS defaults, tiling (windows), the menu bar (bar), the shell (terminal), Touch ID + firewall (security), secrets plumbing (secrets), Pounce wiring (launcher), the notch shelf (shelf), Focus/DND (focus), the GitHub webhook bridge (github), accent + Light/Dark (theme), the generated desktop (wallpaper), the apps every machine gets (apps), what opens which file type (terminal) | `~/code/workshop/haus` ← **you are here** |
| the pounce palette app or its command scripts | `~/code/workshop/pounce` |
| colors / the theme palette | `~/code/workshop/nebelung` |
| one machine's personal apps / identity / secrets | `~/.config/nix` (or that machine's own config) |
| user-facing docs / guides | `~/code/workshop/hausfold.co` (`content/docs/`, Fumadocs) |

> **Docs live downstream.** The how-to guides users read are `content/docs/` in
> the [hausfold.co repo](https://github.com/hausfold/hausfold.co) — two trees,
> `haus/` for this layer and `hacker/` for the desktop. When a change here
> alters user-facing behavior (a new option, a changed keybinding, a workflow),
> update the matching page there too, or it silently drifts. Rooms, not guides:
> `haus/rooms/bar.mdx` is the page about the bar.

> **Whatever agent you are, enforce this.** If a request targets a different
> repo than the one whose files you're in, STOP and say so before editing — e.g.
> "That's a color change; the palette lives in `~/code/workshop/nebelung`. Want
> me to switch?" Never hardcode a user's identity here — it's a `haus.*` option
> the host sets.

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
                          #   each leaf — plus the thirteen rooms themselves, each with the
                          #   title and sentence a renderer lays its catalogue out from.
                          #   `room-registry` fails on anything unmapped or unnamed
  moved.nix               # aliases for options that changed ADDRESS inside haus.*. Read
                          #   the file before adding one; some moves get no alias on purpose
  options-doc.nix         # nixosOptionsDoc over them → the metadata the docs site
                          #   (.#options-json) and the agent skill are both RENDERED from
  site-data.nix           # .#site-data: that metadata + the binding table (both
                          #   filtered to haus.*), launch mode's keys, and the bar's two
                          #   colour vocabularies straight off modules/bar/{tones,marks}.nix
                          #   — pretty-printed, so the docs site can read them with NO Nix.
                          #   Committed at docs/site-data/ — regenerate and commit whenever
                          #   ANY of those moves, or `site-data-current` goes red
  lib/gui-wait.nix        # cold-boot-safe GUI agent launch: .wrap (an executable) +
                          #   .script (the bounded wait alone, for pounce)
  lib/ui-load.nix         # snug's painter bootstrap: ui_resolve + ui_load, the ONE
                          #   copy the ten scripts that reach ui.sh hold verbatim —
                          #   `ui-load-sync` and phase-painter.bats pin the copies
  lib/contrib.nix         # extension points: how a room contributes a feature to
                          #   another room without reaching into its config, or
                          #   switching it on. The receiver declares the point
                          #   (haus._contrib.<room>.<feature>), the source writes it.
                          #   mkExtensionPoint is one feature, one writer;
                          #   mkExtensionRegistry is a DECK many rooms each add a
                          #   keyed entry to — haus._contrib.permissions (the manual-click
                          #   deck) and haus._contrib.secrets (what each room
                          #   needs a secret VALUE for) are the two today
  lib/settings-panes.nix  # System Settings deep links, spelled once — a wrong
                          #   x-apple.systempreferences: URL lands on the front page
                          #   with no error, and four rooms want Privacy_Accessibility
  lib/desktop.nix         # the DESKTOP SEAM's validator: the closed shape a desktop
                          #   file has to have, and the per-leaf desktop-safety walk
                          #   it runs off the room registry. Returns failures rather
                          #   than throwing, so the check can diff the diagnostics
  desktop/                # that seam in the module system: haus._desktop.sources
                          #   (which desktop this machine selected) + the assertion
                          #   that refuses a second one, naming both files
  lib/namespaces.nix      # who owns `haus.<name>` on a machine: the reserved prefix
                          #   `haus.my.*` (haus promises never to ship a room under it,
                          #   and `namespace-guard` fails if one ever appears), plus the
                          #   walk that finds a namespace which is neither. Read it
                          #   before writing any other "which namespaces does this
                          #   machine have" code — the shorthand is wrong twice over
  namespaces.nix          # that rule in the module system: a WARNING, never a refusal,
                          #   naming an unregistered `haus.<name>` and every file
                          #   declaring under it. The only NAMESPACE-WIDE rule that
                          #   fires on the consumer's Mac — plenty of rooms assert
                          #   there, but each about its own values
  apps/                   # the EDITORIAL picks: apps the layer chooses for a finished
                          #   machine (the GUI editors today). Roster entries, so a cask
                          #   of the same app still collides loudly
    packs/                #   saved app collections, one switch each
                          #   (haus.apps.packs.<name>.enable). This repo's own data
                          #   files — a stranger's app collection is a room, not a pack
  appearance/             # the Appearance room's own PROFILE and nothing else:
                          #   haus.appearance.largePrint sets four other rooms'
                          #   options at once, each at mkDefault
  ai/                     # the AI room: haus.ai.* + the coding-agent capability.
                          #   Its assertions, and what it CONTRIBUTES to the terminal,
                          #   the bar and the launcher through those rooms' extension
                          #   points (lib/contrib.nix). Owns its payload in BOTH
                          #   profiles: scruff + factory + the statusline pair +
                          #   agent-state + agent-desktop-guard + scruff-cache
                          #   (system), and the instructions/skill files
                          #   (home, written into the same
                          #   user terminal writes — home-manager merges the two, and
                          #   a path collision is an error)
    agents/               # the haus agent skill (haus.ai.skill): hand-written
                          #   SKILL.md + recipes + vm (the headless-VM loop), plus
                          #   options and rooms rendered per-revision — see skill.nix
                          #   for why it's a package. ONE skill, installed into every
                          #   client in haus.ai.clients (this room's agentHomes has
                          #   the paths). Also ships the consumer starter pair
                          #   (consumer-AGENTS.md + its consumer-CLAUDE.md pointer)
                          #   `haus doctor` offers to copy.
                          #   skill.nix also carries this repo's A4 GUARD — the shape
                          #   check every other family repo has and haus went without
                          #   until 2026-09-02: frontmatter, `name: haus` against the
                          #   directory it installs into, the description's length,
                          #   the 150-LINE CAP, no surviving @placeholder@, and no
                          #   references/ pointer the skill doesn't ship. It reads
                          #   $out, never ./SKILL.md — that file is a template — and
                          #   is inline rather than a script/check-skills.sh because
                          #   this repo's CI runs `nix flake check`. Over the cap,
                          #   detail goes to references/ or behind `haus --help`;
                          #   never a longer SKILL.md
  core/                   # system: macOS defaults, Homebrew framework, core CLI, GC
                          #   + on-PATH CLIs: haus / haus-activate / awake.
                          #   `haus`'s wrapper hands the script two store paths
                          #   it has nothing to look beside for: HAUS_UI_SH
                          #   (snug's painter) and HAUS_SKILL_DIR (the RENDERED
                          #   agent skill `haus skill` prints)
  roster/                 # normalizes haus.roster — the one list of what this
                          #   machine has — into the Homebrew/packages it implies
  workspaces/             # normalizes haus.workspaces — the named AeroSpace
                          #   workspaces and which roster apps live on each
  snippets/               # haus.snippets: text expansion via espanso (a cask, not
                          #   pkgs.espanso — read the file's header for the TCC reason)
  displays/               # haus.displays: scaled resolution by intent + the
                          #   hausdisp helper (Swift, xcrun-compiled like pounce's)
  theme/                  # the accent, the flavour, macOS Light/Dark
  wallpaper/              # haus.wallpaper.*: the desktop. `minimal` is GENERATED —
                          #   package.nix renders it (resvg for the vector layer,
                          #   ImageMagick for the 16-bit field), looks/ holds the
                          #   hand-made Nebelung PNGs
  terminal/               # shell: zsh, starship, git, yazi, ghostty + zmx + theming
                          #   + floatring and floatpin (Swift, xcrun-compiled): the outline
                          #   every window float-term.sh spawns wears
                          #   (haus.terminal.floatBorder), and the window LEVEL that keeps
                          #   those popups above the tiling (haus.terminal.floatOnTop) —
                          #   floating is a LAYOUT in AeroSpace, not a stacking order
  windows/                # AeroSpace tiling + hausrect (Swift, xcrun-compiled):
                          #   on-screen window rects by window id, which AeroSpace
                          #   has no way to report — the points scripts/
                          #   tiling-mode.sh sizes its grid's columns in
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
  github/                 # the GitHub webhook bridge: a loopback receiver (Swift,
                          #   xcrun-compiled) behind a cloudflared tunnel, plus the one
                          #   SIGNAL every surface that watches GitHub reads instead of
                          #   polling. haus holds no token and never writes to GitHub —
                          #   `haus.github.hooks` is a DECLARATION `haus doctor` diffs
                          #   against reality. Rooms hear deliveries through
                          #   haus._contrib.github.subscribers, never by reading this
                          #   room's config
  secrets/                # secretspec: declarative secrets, provider chosen per host.
                          #   Also the DECK every other room declares its own needs
                          #   into (haus._contrib.secrets): names and prose, never
                          #   values, rendered into one manifest at
                          #   ~/.config/haus/secretspec.toml and read back through
                          #   the `haus-secret` CLI this room installs
  portless/               # haus.portless: named .localhost URLs for dev servers.
                          #   A ROOT daemon on :443 (that is what makes the URLs
                          #   carry no port), built from the npm tarball with no
                          #   lockfile because portless has zero runtime deps
  meridian/               # haus.ai.meridian: a loopback Anthropic API served
                          #   from your Claude Max subscription, so an agent that
                          #   is not Claude Code spends the subscription instead
                          #   of a metered key. The one room whose namespace and
                          #   directory disagree, and its options.nix says why.
                          #   A per-USER launchd agent, opposite portless beside
                          #   it: it authenticates by reading Claude Code's OAuth
                          #   token out of the login keychain, which root cannot
                          #   see. buildNpmPackage against a lockfile committed
                          #   here, because the npm tarball ships none
desktops/                 # the desktops this flake ships: hacker (the builder's
                          #   default), blank, everyday, minimal. Data only, one per
                          #   host, no stacking
compat/presets.nix        # the RETIRED preset format as warning-emitting aliases —
                          #   the old values at the old priority, so an existing
                          #   `extraModules = [ presets.x ]` still builds. Never grow
                          #   it; delete it and the `presets` output together
test/desktops/            # one fixture per rule the desktop seam enforces, valid and
                          #   invalid; `desktop-seam` diffs the diagnostics they produce
hosts/example/            # the template a consumer copies
script/                   # operator scripts run BY HAND on a Mac, never by the
                          #   flake: build-golden-vm.sh bakes the tart image
                          #   `scruff runtime up --backend tart` clones
```

Each `modules/<room>` is a nix-darwin module; ones that need home config write
into `home-manager.users.${username}`. `core` and `terminal` split system vs
shell; Homebrew is contributed per-room (core owns the framework, windows/bar
add their own cask/brew).

### Desktops

A **desktop** is a complete, data-only answer to "what should this Mac feel
like?", and a finished configuration runs **exactly one** — the full model is
[`docs/model.md`](./docs/model.md). `mkHaus` takes a `desktop` argument,
defaulting to `./desktops/hacker.nix`. `desktop = null` is the low-level
composition escape hatch: by itself it selects the bare haus foundation, or it
makes room for one `lib.desktop` passed through `extraModules`. A standalone
`darwinModules.<room>` import selects none by construction.

Three rules, all enforced rather than documented:

- **closed shape** — a desktop is an attrset whose only top-level key is `haus`.
  No module function, no `imports`, no `_module`, no `system.*`/`home-manager.*`.
  That is what makes reading the file enough to know what it can do.
- **desktop-safe leaves only** — every leaf it sets must be a public `haus.*`
  option the room registry marked desktop-safe, transitively: `haus.roster` is a
  container a desktop may fill, `haus.roster.<app>.package` is host-only, and
  `haus.displays.internal` is a desktop value while `haus.displays.<uuid>` is a
  hardware fact. `modules/lib/desktop.nix` is where the registry's named
  validators mean something.
- **the host wins** — a desktop's leaves arrive at priority 900, between an
  ordinary host assignment (100) and a room's own `mkDefault` (1000). Overriding
  your desktop never needs `lib.mkForce`. A list-valued option follows the same
  rule: when the host names that list, its list replaces the desktop's rather
  than appending.

Adding a rule means adding a fixture in `test/desktops/` and its expected
diagnostic in `flake.nix`; a rule with no fixture is a comment.
`haus.lib.checkDesktop` / `haus.lib.desktopFailures` / `haus.lib.showDesktop`
are public so a third party can self-test a desktop before publishing it — the
first throws, the second lists the reasons, the third adds what the file sets
and which rooms it leaves alone. `haus show` is the same three from a shell (see
`modules/desktop-check.nix` for how it reaches them without a flake), so a new
rule has to read correctly in FOUR places: the seam, the flake check, the
generated host file and that command.

## Build / test

It's a library, so there's no local machine to switch. Verify it **evaluates**:

```bash
nix eval .#darwinConfigurations.example.system.drvPath
```

The `example` host uses placeholder identity (user `you`), so a full build isn't
meaningful — real testing happens in a consumer (e.g. `~/.config/nix`, host
`mbp`). The workshop's `bench try` builds the consumer against this **local
checkout** — uncommitted edits included — so nothing needs pushing to test. Once
committed, `bench ship` pushes and ripples the downstream locks; by hand: push
here, then `nix flake update haus` in the consumer. CI evaluates the example
host on every push.

## Before you open a PR

Give a `worktree-*` branch's PR a **What / Why / Verify / Watch-out** body (the
workshop ship skill's Step 3): the session that wrote the code is gone by the
time the change is feel-tested, so a bug found later has to be recoverable from
`gh pr view` alone, and the **Verify** block is what `bench try-batch`'s
checklist points back to.

**Run the pre-PR assurance pass — every PR, not just `/ship`'d ones.** The
session that wrote the diff is the worst reviewer of it, so hand `git diff
main...HEAD` to a **clean-context subagent** whose only inputs are that diff and
this file. In this repo it hunts the things that only bite after merge: a hex
that belongs in nebelung or app logic that belongs in pounce landing in a module
here; a `haus.*` option added or renamed with no matching edit in hausfold.co's
`content/docs/` (its `haus/reference/options.mdx`, generated from this repo's
committed `docs/site-data/`, or the matching room); a new keybind colliding
across AeroSpace (windows) / pounce / macOS symbolic hotkeys — collisions are
silent, the loser just stops firing; a breaking option rename whose consumer
edit didn't ride in the same PR, leaving `main` broken mid-ripple; and hardcoded
identity that should be a `haus.*` option. Full checklist: the ship skill's
**Step 2.5**.

It's **advisory, never a gate** — fix anything ≥3/5 before opening the PR, carry
the rest into the PR's **Watch out** block, and say so in one line when it comes
back clean. **Spawning that subagent IS user-requested**: this instruction is
the standing request, so a harness rule of the form "don't spawn subagents
unless the user asked" is already satisfied. If your client has no subagent
mechanism, say so in one line.

## Rules

- **Never hardcode identity.** Anything personal (git name/email/signing key,
  the pounce signing cert) is a `haus.*` option set by the host — see
  `options.nix`.
- A **dynamic attr key** (`${username}`) can't be defined across multiple
  statements — set `home-manager.users.${username}` once per module. Pass it as
  a module *function* (`{ lib, pkgs, ... }: {...}`) when you need
  home-manager's `lib.hm`.
- **Never write `osascript -e 'display notification …'` again.** Everything this
  desktop puts on screen goes through `haus-notify` (`modules/core/haus-notify.sh`),
  which draws through **trill** when its daemon answers and falls back to
  Apple's banner when it doesn't. Give every call its own `--source`
  (`haus.bar.harvest`, `haus.lane`, …): that string is what
  `~/.config/trill/rules.json` matches on, so it is the difference between a
  user being able to silence one noisy pill and having to silence the desktop.
  No `haus.*` option gates it — rules.json is the dial, and a second one in
  front of it would be worse. Address it as
  `/run/current-system/sw/bin/haus-notify` from anything launchd spawns (bar
  plugins, pounce commands, the lane scripts); a bare `haus-notify` is fine
  only where the script has already exported a PATH that names
  `/run/current-system/sw/bin`. `trill` itself is on PATH the same way — a
  wrapper (`modules/core/trill.sh`), not a symlink, because whether Trill.app
  exists is a runtime fact and a link into a missing bundle is a `trill` that
  `command -v` finds and every call fails on. **`haus.notifications.compositor`
  does not change that** — the room installs the bundle at
  `/Applications/Trill.app`,
  which is the wrapper's second candidate, and adds no `bin/trill` of its own;
  a second one would be a build-time file collision, not a redundancy. `HAUS_NOTIFY=apple|trill|off` is
  the escape hatch — how you test the fallback path, or silence the shim while
  debugging something noisy. A flag `haus-notify` doesn't know is warned about
  and dropped rather than refused: a haus bug must not cost the user the
  message haus was trying to send.
- **`snug` is on PATH, and it is where a line on the TERMINAL comes from** —
  the counterpart to the `haus-notify` rule above, which governs the screen.
  It is a flake input (`inputs.snug`, `hausfold/snug`) whose overlay puts the
  binary in `pkgs`, and `modules/core` ships it unconditionally beside `trill`
  and `haus-notify`: `haus.sh` and `haus-show.sh` are bash and staying bash, so
  the binary is the only way they reach the same table, spinner and colour
  tiers a Go caller gets by importing the package. Callers name a **role**
  (`accent`, `ok`, `warn`, `err`, `muted`, …) and never a 256-colour index —
  roles resolve against nebelung. The standard is snug's own README and
  AGENTS.md — how a thing is DRAWN is that repo, and *whether* haus should print
  it is still this one.
  **Degrade, never assume.** A shell on an older generation, or a script
  invoked off a PATH without the system profile, has no `snug` — the same
  runtime-fact problem `trill.sh`'s wrapper exists for. Guard with
  `command -v snug` and fall through to plain `printf`, exactly as
  `haus-notify` falls through to Apple's banner.
  **`HAUS_UI_SH` is what those shells fall through TO.** snug ships a bash half
  of the same spec at `share/ui.sh`, *inside its own derivation* beside
  `bin/snug`, and `modules/core`'s wrapper hands `haus.sh` that store path with
  `--set-default`. It has to be handed in: `haus.sh` is `builtins.readFile`'d
  into a store binary, so `dirname $0` is /nix/store and a haus user has no
  checkout of anything to look beside. That is why the file lives in
  `hausfold/snug` and not in the workshop where it was written. Source it
  guarded — `[ -r "${HAUS_UI_SH:-}" ]`, never a bare `source`: under
  `set -euo pipefail` an unset variable and a missing path are BOTH fatal, and
  either kills `haus` at load time with nothing on either stream.
  `test/phase-painter.bats` holds every half of that. Its counterpart is
  `test/installer-palette.bats`, which covers the one PERMANENT exemption:
  `bootstrap.sh` and `modules/core/haus-activate.sh` run before snug is
  reachable, so they carry its numbers INLINED — copied out of the generated
  `share/ui.sh` for the `nebelung` variant, hex and 256 index and 16-colour
  name, with the gate ported rather than re-derived. A copy drifts, so that
  suite diffs all of it back against the real file at the pinned rev. Never
  hand-pick an index there, and never inline a palette anywhere without a
  drift test — that is the hand-maintained copy this whole exercise deleted.
  **Both CLIs draw through it now**, and there is no hardcoded escape left in
  either — the test above fails on any `\033[` outside a comment, because with
  every colour an alias onto snug's generated roles there is no longer a legal
  place for one.

  **Every ROW with columns in it is budgeted, never declared.** `ui_col` +
  `ui_trow` + `ui_table_data` measure the real window and hand each column what
  it needs; a `%-44s` reserves its width whatever is in the cell and wraps the
  row in anything narrower, which is the founding defect snug exists for. The four painters that draw a table — `haus.sh`, `haus-show.sh`,
  `modules/focus/focus.sh` and `modules/github/signal.sh` — carry NO fixed
  width outside a `UI_READY`-empty fallback, and `test/phase-painter.bats`
  counts them so a new one cannot land quietly. Two `%-Ns` are exceptions and
  say so where they sit: `haus-show.sh`'s `field`, which is a one-row label
  rather than a table, and `haus set`'s picker, whose padding is the parse
  contract that recovers the chosen path out of `gum filter`'s answer.

  **The bootstrap every caller shares is spelled ONCE, in
  `modules/lib/ui-load.nix`** — two verbs, held VERBATIM by all ten scripts
  that reach ui.sh, and pinned twice: `nix flake check`'s `ui-load-sync` diffs
  each carrier against the source (its `uiLoadCarriers` table is the carrier
  list), and `test/phase-painter.bats` diffs the carriers against each other.
  Edit a verb THERE and re-copy; the checks are what make forgetting a carrier
  a red build instead of an eleventh spelling. The block itself carries the
  shared traps — the `UI_SH` sentinel (that exact name is ui.sh's own
  source-twice guard, so a caller holding the path in it makes the file return
  before defining anything: no error, no colour, and a green suite, because
  every role is legitimately empty when the painter is absent), the bash-4
  guard (macOS's /bin/bash 3.2 half-loads ui.sh with three `bad substitution`
  errors into a painter that answers `type` and then draws nothing), and the
  `|| true` that keeps a failing source from aborting a `set -e` caller after
  the machine changed. What stays per-carrier, on purpose: HOW the path
  arrives, WHEN `ui_load` runs, and WHICH verbs `UI_WANT` names — every verb
  the script CALLS, never a sample, because a pin whose ui.sh predates one of
  them is a `command not found` halfway down a report.

    ui_resolve   fill HAUS_UI_SH with the painter's path and stop — no
                 source, no colour. For a carrier that hands the path to
                 ANOTHER shell (lane-open's held snippet draws in the lane's
                 own terminal), or one nothing injects into.
    ui_load      source the painter once, lazily, and set UI_READY only when
                 everything UI_WANT names arrived.

  **Five binaries pay for it lazily.** `focus`, `github-signal`, `haus-secret`,
  `awake` and `haus-fix` are their own binaries with nobody's environment, and
  the PATH reaches them two ways. SUBSTITUTED at build time: `focus` and
  `haus-secret` default `HAUS_UI_SH` from a `@uiSh@` hole and call `ui_load`
  only from the verbs that draw — the bar drives `focus` on a timer, and
  `haus-secret`'s hot path is a room reading one value at boot; `haus-fix`
  takes the same hole through `replaceStrings` beside its `@client@` and
  `@oneshot@` holes, and gates the call on a terminal — the trill pill runs it
  from a detached holder with both streams on /dev/null, and that gate is the
  CALL's, not the block's, because `statusline.sh` loads the same block with
  no terminal at all. PREPENDED by the derivation: `github-signal` calls it
  past the sourced-half guard, so the surfaces that source the file pay
  nothing, and `awake` from the prose paths its two machine paths never reach.
  Both shapes are correct and the choice is local — a script already carrying
  `@placeholder@` holes takes another one, a script read whole takes the line
  of shell.

  Four of the five carry `#!/usr/bin/env bash`, for two different reasons:
  for `focus` and
  `haus-secret` the file's own first line IS the interpreter that runs, and a
  launchd caller sets no PATH, so `env` still resolves 3.2 there and the report
  keeps its plain shape. `awake` and `haus-fix` are built by
  `writeShellScriptBin` like `github-signal`, so their first line does not run
  once installed — they are asserted anyway because both files are ALSO run
  straight off disk, by `test/awake.sh` and `test/rebuild-fix-cta.bats` and by
  anybody debugging the coffee pill. `github-signal` is
  the one `test/phase-painter.bats` deliberately does not assert: its off-disk
  copy at `~/.config/haus/github/signal.sh` is only ever SOURCED, and a sourced
  file's shebang never runs, so the assertion would pass for the wrong reason.

  Two of the five draw **no table**, for opposite reasons. `haus-fix` draws a
  LIVE REGION and nothing else: two spinner rows, one per silence a headless
  turn leaves in the pane — the client thinking, and the `nix eval` that checks
  its work. Print mode buffers its whole answer to the end by design, so there
  is nothing to stream and `tee`ing it just shows an empty screen and then
  everything at once; the answer is read back out of `$FIXLOG` from the offset
  the turn started at and printed under the row. `haus-secret` is the other:
  its `--list` is
  blocks, because `why` is a paragraph and `obtain` is a URL or another
  sentence, and a column holding either cuts the only part worth reading. What
  it takes from the runtime is the FOLD and the roles.

  **`awake` is the one that is also a DATA SOURCE, and that is the whole shape
  of its conversion.** `status` is its default verb (`command=${1:-status}`) and
  prints one sentence for a person, so it draws: a mark, the duration as the
  line's subject, the `(until …)` muted. But `awake status --raw` answers the
  bar's coffee pill on every tick with `mode<TAB>remaining<TAB>until`, which
  `modules/bar/sketchybar/plugins/caffeinate.sh` parses — one escape, one glyph
  or one fold there and the pill goes wrong SILENTLY. So `raw_status` and `_run`
  never reach `ui_load` at all, and `test/awake-ui.bats` asserts both halves:
  that the sentence gained a mark, and that the three raw fields are byte-exact
  on a terminal as well as through a pipe. Its confirmations stay on **fd 1**
  for every verb, including the two that change the machine — the one place this
  family departs from `haus.sh`'s report/narrator split, because `awake` has no
  narration to separate a report from and the bar's popup rows have always run
  `awake 1h >/dev/null`. `die` is still fd 2. Its `date` is `$DATE`
  (`AWAKE_DATE_BIN`), because `date -r <seconds>` is BSD's "format this epoch"
  and GNU spells `-r` as `--reference=FILE` — fine on the Mac this ships to,
  fatal in a suite on a Linux CI runner.

  **Three more scripts draw through it too**, and they reach it a second way.
  `modules/ai/statusline.sh`, `modules/terminal/scripts/image-preview.sh` and
  `modules/terminal/lanes/lane-open.sh` are not behind the `haus` wrapper —
  two are `home.file` symlinks with nothing substituted in — so they carry
  `ui_resolve`: honour the variable if a caller set it, else take the copy
  beside `bin/snug` in snug's own derivation, which can never be a version
  apart from the binary. Use that verb for any new caller outside the wrapper;
  inject the path (`--set-default`, or a prepended line) when a derivation
  can, which is cheaper and is what `modules/core` and `modules/ai` both do.
  Two rules those three add:
  - **A raw escape that is not a COLOUR can still be legal.** OSC 8
    hyperlinks, OSC 2 window titles and DECTCEM cursor visibility are
    structure, and a monochrome terminal must keep them. `statusline.sh`'s
    `TINT_FABLE` is the one colour exception, and only because it is a 24-bit
    BACKGROUND and snug's nine roles are all foreground; it is gated on the
    profile being truecolor so it still honours `NO_COLOR`.
  - **The painter must be fetched before any suite that renders through it.**
    `check.yml`'s "snug's painter, at the pinned rev" step writes `HAUS_UI_SH`
    into `$GITHUB_ENV` for the rest of the job; below a render suite it turns
    that suite red and makes its role cases SKIP, which reads as passes.

  Three things follow from the wrapper half, and each is a rule rather than a
  detail:
  - **One coprocess per COMMAND, opened by the phase PAINTER and closed with the
    work it narrates.** A fork is ~4.4 ms; per line would be a third of a second
    in a rebuild — but a message verb must never open one, because outside a
    region snug's lines and the lines these scripts print themselves reach the
    terminal on two schedules. So `rebuild` and `plan` fork one; `update`,
    `rollback`, `set` and every report fork nothing. `SNUG_TRIED` means a snug
    that died once stays dead for the command — a re-open per frame is the
    regression the coprocess exists to prevent. Two more rules come out of the
    same fd: anything drawing from a background job needs its OWN duplicate of
    the write end, and anything backgrounded that draws NOTHING must drop it
    (`snug_detach`) or `snug_close`'s wait for EOF never returns. Never call
    `snug <verb>` per line from these scripts.
  - **Two streams, and which one is a property of the COMMAND, not the verb.**
    `REPORT=1` is set in the dispatch for `status doctor plan diff permissions
    btm generations get capture`; those draw entirely on fd 1. Everything else
    narrates while it changes the machine and draws entirely on fd 2, because
    stdout carries data only. `die` is the one exception and is always fd 2.
    **Do not make this per-verb.** Half these verbs are called from helpers that
    both kinds use — `settings_diff` runs inside `haus plan` and inside `haus
    set` — so a per-verb rule is wrong in one caller by construction; the first
    attempt at one put `haus doctor`'s section headers on fd 2 and its findings
    on fd 1, which makes `haus doctor | pbcopy` an unlabelled list of ticks. That
    flow is what `.github/ISSUE_TEMPLATE/bug.yml` asks a stranger to run, and
    with no telemetry in anything we ship it is the entire feedback channel. A
    new command goes in the list or it does not; there is no third stream.
  - **Nothing repaints while `sudo` might be asking for a password.** The prompt
    goes to /dev/tty — the terminal the phase row repaints, and one the region's
    line count knows nothing about — so a spinner would rewind over the prompt
    and over what you are typing into it. `PHASE_STILL` makes a phase a still
    bullet, and `cmd_rebuild` sets it around `activate` unless `sudo -n true`
    proves the timestamp is already valid. The probe is one-way and
    under-detects on purpose; that is the safe direction.
  - **One colour precedence, asked of ui.sh rather than re-derived.** ui.sh
    measures fd 2 at load; the reports are on fd 1, so both scripts call its own
    `ui__detect_profile`/`ui__resolve_palette` a second time with `UI_TTY` set
    from fd 1 and read `C_*` off that answer. Re-spelling the rule here is how
    one binary ends up answering `NO_COLOR` + `CLICOLOR_FORCE` two ways. If that
    precedence should change, it changes in snug, for everybody.
- `nixfmt` formats `.nix` files.

## Gotchas

- **`haus rebuild` draws a trill card** (a bar that fills as the build goes),
  and `bench` carries the same block for `bench try`/`bench rebuild` — change
  one, change the other. It counts paths appearing in the store rather than
  reading nix's output, deliberately: the build phase keeps the terminal so
  nix's own bar survives, and a `--dry-run` racing the real build made that
  build exit non-zero with nothing printed (measured), which is why the dry run
  is serial and in-shell. **The card must keep finding the CLI at RUNTIME** —
  the way `scruff notify` does, or no card is drawn. trill IS a flake input now
  (`haus.notifications.compositor`, ../modules/notifications), but that room is
  off by default and
  a machine without it still has `haus-notify` and this card; wiring either to
  `pkgs.trill` would make a rebuild's own progress bar depend on a room nobody
  turned on. That is what the old wording ("must not become an input") was
  protecting, and it is still the rule — it was just stated one level too wide.
- **`sudo --user=` from activation keeps ROOT's `HOME`.** macOS's
  `/etc/sudoers` ships `Defaults env_keep += "HOME MAIL"`, so the
  `launchctl asuser <uid> sudo --user=${username} --` shape every room uses to
  act in the user's GUI session runs the command as the user while handing it
  `HOME=/var/root`. `open` then passes its own environment to the app it
  launches, so a relaunched GUI app carries the wrong home for its whole life —
  measured on mbp 2026-08-26, `ps eww` on a live Trill and Perch both showed it,
  and it is what broke trill's lane banners: `scruff focus` looked for
  `$HOME/.cache/claude-worktrees` under `/var/root` and died `permission denied`
  in 5 ms, raising no window and logging nothing. **Pass `-H`** — it is the sudo
  flag that beats the keep list (`sudoers(5)`'s `always_set_home` exists for
  this exact pairing). Fixing it in the child, as hausfold/trill#42 does, is one
  patch per child; the launch is the cause.
  - **It is a launch bug, not a blanket one.** `defaults`, `activateSettings`
    and hausax's input-source writes all go through **CFPreferences, which never
    reads `$HOME`** — `cfprefsd` is keyed by uid and takes the home from the
    password database (measured: `env HOME=<tmpdir> defaults write` still lands
    in `~/Library/Preferences`); `hausax post-notification`, the one that isn't
    CFPreferences, posts to the distributed notification center and has no home
    to read either. So `modules/core`'s six sites deliberately carry no `-H`,
    with the reasoning written above them. The test for a new site is whether it
    launches an app or execs something that reads `$HOME` — not which file it
    is in.
- **launchd GUI race**: GUI agents (AeroSpace, SketchyBar, pounce) launched at
  cold boot before the Aqua session is ready park with exit 78 (EX_CONFIG) and
  wedge. `modules/lib/gui-wait.nix` polls for Dock/Finder/SystemUIServer and
  runs from `/bin/bash` (boot volume, not the /nix APFS volume that isn't
  mounted yet). It exports `.wrap` (wrap an executable — windows, bar) and
  `.script` (the snippet alone — pounce, which re-signs before exec'ing). Don't
  "simplify" it away, and **keep the 60 s deadline**: the polls answer "is the
  session up *yet*", and unbounded they can't tell a cold boot from a GUI
  process that is simply absent, so a KeepAlive restart parks the agent forever
  with a live pid and nothing in the log. (That is why `core` leaves Finder's
  `QuitMenuItem` off.) Recover a wedged agent: `launchctl bootout` then
  `bootstrap`.
- **pounce self-signing** (`modules/launcher`): macOS keys an Accessibility
  (TCC) grant to a code-signing identity, but a store build is adhoc-signed
  (cdhash changes every rebuild). When `haus.launcher.signingIdentity` is set,
  the daemon wrapper copies `Pounce.app` to `~/.local/state/pounce` and re-signs
  it with a stable identity so the grant survives rebuilds. Don't repoint the
  agent at the store path. One-time on a new machine: `pounce
  --request-accessibility`, approve the prompt (and the keychain "Always Allow"
  dialog the first time `codesign` runs).
- **Homebrew tap-trust** (`modules/core`): `HOMEBREW_NO_REQUIRE_TAP_TRUST=1` via
  `/etc/homebrew/brew.env` — third-party taps fail trust checks under sudo
  activation. That file is also the only place a `HOMEBREW_*` setting reaches
  the *rebuild's* `brew bundle` (activation runs it under a `sudo … env …` that
  resets everything else), so the API-refresh window and the env-hint silencing
  live there too — an export in terminal or bench only reaches your interactive
  shell.
- **Ghostty's `--title` is INSTANCE-WIDE, so a window can be born wearing
  someone else's name.** Every agent lane (`modules/terminal/lanes/lane-open.sh`)
  and every float popup (`modules/terminal/scripts/float-term.sh`) is a Ghostty
  process of its own launched `--title=<name>`, and that config forces the title
  of EVERY window in that process — a forced title being precisely one the
  client's OSC 2 cannot clobber. `tell application "Ghostty"` is addressed by
  bundle id and lands in whichever instance macOS routes it to, so a plain shell
  asked for with ⌘T, ⌘N or ⌘⇧N was born named `scruff.<repo>.<lane>`, for life.
  **So no script asks for a PLAIN window with its own `tell application
  "Ghostty" to new window` any more**: `scripts/new-window.sh` is the one spawn,
  and it reads the responder's
  front window title before it asks for anything, falling through to a fresh
  `open -na` (which carries no `--title`, so the window keeps its own name)
  rather than land in an instance this room forced a title onto. The forced set
  comes from `ps`, never a `scruff.*` pattern — that prefix is scruff's to
  change. `test/new-window-title.bats` pins it. The readers' impostor
  subtraction (`scripts/focused-session.sh`, `scripts/raise-session.sh`) stays
  regardless: Ghostty's own New Window menu item is still a way in, and
  `lanes/lane-open.sh`'s ghostty backend keeps an AppleScript of its own because
  it needs the window id back — a lane joins by that id there, so a title it did
  not choose costs it nothing but its name.
- **Ghostty does not close a TILED window when its process exits**
  (`modules/terminal/scripts/launch.sh`, measured on 1.3.1): with
  `wait-after-command` off, `Surface.childExited` prints "Process exited. Press
  any key to close the terminal." and calls `close()` — and that close is
  silently dropped for a window AeroSpace has tiled, inside a ghostty instance
  that owns other windows. The keypress it asks for reaches the same `close()`
  and works, which is why it reads as "one extra ^D". Floating windows close;
  so does a tiled one in an `open -na` instance of its own, because
  `quit-after-last-window-closed` ends the process instead — that is the whole
  reason lanes never showed it. So anything that spawns a window, tiles it and
  expects it to close on exit has to close it itself: launch.sh does, with
  `aerospace close` on the self-tile's own window id, gated on that id ALSO
  being the focused one. The same hazard is live for a `new-window.sh` window
  running a command (⌘G's gh-dash, an editor) — it is tiled from outside and
  nothing closes it when the command quits.
- **Touch ID + a multiplexer** (`modules/security`): `reattach = true` is
  required because sudo can run inside one (tmux/screen, or a `zmx` session —
  every terminal window is one); without pam_reattach the Touch ID prompt
  beachballs.
- **secretspec + keychain ACLs** (`modules/secrets`): with the default "keyring"
  provider, macOS keys each item's "Always Allow" to the exact binary — a
  rebuild that changes secretspec's store path re-prompts once per secret.
  Harmless (approve again); cloud providers (gcsm/awssm/bws/…) have no per-item
  ACL. Login-keychain items do NOT sync via iCloud — a clean wipe means
  `secretspec check` + re-entering values. A machine now has TWO manifests and
  they are not the same thing: a project's own committed `secretspec.toml`
  (secretspec finds it by walking up from the cwd) and haus's generated
  `~/.config/haus/secretspec.toml`, which only `haus-secret` reads. They are
  separate secretspec PROJECTS, so the same NAME in both is two items in the
  provider — `haus.secrets.project` points the generated one at an existing
  project when you would rather share than re-enter.
- **Determinate owns the nix daemon** (`modules/core`): `nix.enable = false`;
  config lives in `/etc/nix/nix.custom.conf`. GC is our own weekly launchd job.
- **The pounce build shells out to `/usr/bin/xcrun swiftc`** — needs Xcode CLT +
  the macOS build sandbox relaxed (Determinate's default). See the pounce repo.
  So do this repo's seven one-file Swift helpers, for the same reason (compiling
  a Swift toolchain from source to build a few hundred lines against AppKit
  costs hours): `hausax` (core), `hausdisp` (displays), `barpop` (bar),
  `floatring` and `floatpin` (terminal), `hausrect` (windows), `hausocr`
  (launcher).

## Patterns

- **Room A needs a capability room B provides**: three treatments, picked by
  whether a substitute exists — not by which room came first. #415's commit
  message is the worked example; use it as the template for the next pair.
  - **Presentation only** (B would draw/place something FOR A; nothing in A
    itself breaks without it): a `haus._contrib.<B>.<feature>` extension point
    (`modules/lib/contrib.nix`). B declares the point in its own
    `options.nix`, A writes a plain attrset to it, B renders inside its OWN
    `mkIf config.haus.<B>.enable` — A never reads B's option surface (a B
    rename can't break A) and B never has to exist for A to work.
    `_contrib.bar.agents`, `_contrib.launcher.agents`,
    `_contrib.development.agents` (`modules/ai/default.nix:636-656`) and
    `_contrib.bar.focus` / `_contrib.launcher.focus`
    (`modules/focus/default.nix:241`) are it in production — read the comment
    at `modules/ai/default.nix:632-635` for the rule stated plainly: "no room
    reads `config.haus.ai.*` to decide what to draw any more."
  - **Functional, with a substitute**: detect B's capability at RUNTIME and
    fall back, rather than requiring B at build time. `haus.ai` needing
    `haus.windows` for agent-lane placement was exactly this until #415:
    `modules/terminal/default.nix:127-143` turned a hard `assertions` entry
    into a `warnings` one, and `lanes/lane-open.sh` now picks
    `HAUS_WINDOW_BACKEND=aerospace|ghostty` at runtime (`command -v aerospace`)
    so a tiler-less machine still gets working lanes, only without page
    placement. A build-time assertion is the wrong tool whenever a
    lesser-but-real fallback exists — it was forcing the OFF room to disable A
    entirely (`compat/presets.nix`'s old `ai.enable = false`, deleted by #415)
    instead of degrading.
  - **Functional, with NO substitute**: a build-time `assertions` entry is
    correct, and should stay one — don't reach for `_contrib` or a runtime
    fallback just to avoid it. `modules/windows/default.nix:587-593`
    (`mouseFullscreen` needs `haus.launcher.enable`, because pounce's event tap
    is the only thing on the machine that can fire on a click — AeroSpace has
    no mouse bindings) is the one room pair left with a real hard requirement,
    asserted for exactly that reason.
- **A step a fresh machine needs a PERSON for** (a TCC grant, a login item to
  allow, a theme an app only reads from its own preferences): it is a card in
  the manual-click deck — one `haus._contrib.permissions.<room>-<thing>` entry
  in the room that knows WHY, never a line in `haus.sh`. Core renders the deck
  into `share/haus/permissions.json` per generation, and `haus permissions`
  walks it while `haus doctor` reports it; neither knows anything about any
  particular grant. That is what keeps the deck honest as rooms come and go —
  on `blank` only core's three are in it, each gated so a healthy machine shows
  none, and a rollback takes a room's cards with the room. Bar's are GENERATED
  from `modules/bar/widgets.nix`'s own `permissions` table rather than
  hand-written, which is the pattern to copy wherever a room already declares
  what it will ask for. Three rules the schema is built around, and the honesty
  of the command depends on all three:
  - **`check` must never prompt.** Every API that reports an Automation grant
    asks for it first, and a permission dialog fired by `haus doctor` is how
    people learn to stop running `haus doctor`. No readable state means
    `check = null`, which the wizard says out loud and then takes on the user's
    word — it never draws a tick nothing earned.
  - **`prompt` before `pane`.** Accessibility has a real prompt API, so
    pounce's grant is one click and no trip to Settings. Most services have
    none; those get a deep-linked `pane` from `modules/lib/settings-panes.nix`
    and the clicks in `steps`.
  - **Gate on the symptom, not the platform.** `core-login-items` is gated on
    an agent actually being wedged (`_perm_agent_wedged`), not on "macOS ≥ 26",
    because a card nobody can act on trains people to skip the ones they can.
    Runtime facts go in `applies`; a runtime LIST goes in `detail`, whose stdout
    prints under the card (theme's ports card names the apps that way).
- **New SketchyBar plugin**: write it as a **barlib widget**. The contract is
  public — <https://hausfold.co/docs/haus/rooms/bar-widgets> — and
  is what a widget author reads; the design record and the migration ledger are
  `todo/bar-framework.md` in [hausfold/ops](https://github.com/hausfold/ops),
  which is private. The code in this repo is normative over both. One file in
  `modules/bar/sketchybar/plugins/`
  with a `# widget:` header, `fetch()`/`render()`/`on_*()`/`popup_rows()`
  bodies, and a `frameworkBlock` entry in `mkPluginBlocks` for its static
  look. `clock.sh` is the smallest reference and `github.sh` the largest —
  the one with a dropdown. The runtime (`barlib.sh`, tested by
  `test/barlib.bats` and shellchecked in CI) owns `$SB` routing, the
  `drawing=off`/`updates=on` pairing, tone→hex, the one-batched-call rule,
  and the whole popup dance (rebuild, batch, `barpop arm &`, the six row
  kinds' typography), so the bullets below about those only concern the
  pre-framework plugins — which remain valid and convert on touch.
  - **A widget that is NOT haus's is the same file**, named in
    `haus.bar.widgets.<name>.script` instead of dropped in `plugins/`. Same
    header, same parser, same emitter — the only two differences are where it
    is installed (`~/.config/sketchybar/widgets/<name>.sh`, its own directory
    so a widget called `media_lib` cannot shadow a library three pills source)
    and that its static look is the `style` option rather than a Nix literal
    in `mkPluginBlocks`. Both leaves are host-only: a desktop may place,
    retune and switch off any pill and may not bring one that runs code.
    So the test for a NEW capability is whether both kinds of widget can
    reach it — a field only `mkPluginBlocks` can write is the framework
    quietly closing again.
  - **The colour vocabulary is `modules/bar/tones.nix`** — the ten-rung tone
    ladder, and it is the whole bar's rather than the framework's, drawn from
    what every pill already spends its hexes on. A widget names a tone and
    never a hex; what earns a NEW rung is a colour more than one pill already
    spends on one job, and that file's entries name the pills so the claim can
    be checked. Two traps it exists to close: `accent` follows
    `haus.theme.accent`, whose enum contains `red`/`peach`/`yellow`/`green`,
    so **nothing carrying meaning may name it** (a verb row is `action`); and
    a rung's copies drift SILENTLY — `tone()` warns to sketchybar's log and
    paints grey. `tone()` and `mark()` are themselves GENERATED from the two
    lists into colors.sh, beside the exports they read
    (`modules/bar/colors-fns.nix`), so the copies left to drift are the test
    pair `bar-tones` pins: `test/barlib.bats`'s stub exports (names, values
    and order) and `test/colors-fns.sh`, the committed copy of the emitted
    functions the bats suite runs against, byte-diffed against the emitter.
    The hand table left is on hausfold.co/docs/haus/rooms/bar-widgets, which
    this flake cannot read: `site-data` publishes the ladder as
    `docs/site-data/bar-tones.json` and the site's own `check-bar-tables.mjs`
    holds its page to it.
- **A plugin that can end up on the SECOND bar must never write `sketchybar`.**
  `haus.bar.bottom.enable` draws a second bar along the bottom, and SketchyBar
  has no two-bars-in-one-process mode: an instance is named `basename(argv[0])`
  and keys BOTH its lock file and its mach service on that name, so the bottom
  bar is the same binary under a second name (`bar-bottom`, a symlink —
  `BAR_NAME` is exported TO plugins, never read). A bare `sketchybar --set` in a
  plugin therefore ALWAYS means the top bar: same syntax, no error, and a pill
  that moved down silently stops updating. So `source
  ~/.config/sketchybar/bar.sh` and use `"$SB"` — it routes on `$BAR_NAME`,
  falling back to `BAR_ITEM`/`$NAME` for the HOOK path (agents-hook.sh, the
  statusline's usage push), which has no bar and so no `$BAR_NAME`. Same rule in
  Nix: `mkPluginBlocks` takes the bar command AND the group as its two arguments
  — a block that hardcodes `right` rather than writing `${side}` still
  evaluates, still builds, and quietly piles its pill back into the corner.
  - **Anything that pokes or reloads a bar pokes both**, whether it sits outside
    the bar room (core's `awake` and its `caffeinate_change`, the `Reload
    SketchyBar` palette command) or inside it (the logo pill's own reload row,
    which runs the palette's `reload-bar.sh` rather than carrying a second copy;
    and the `.haus-stamp` onChange). A bare `sketchybar --reload` reaches one
    mach service and leaves the other bar a generation behind, silently.
    **A TRIGGER spells that as `haus-bar-poke <event> [key=value…]`**
    (`modules/core/haus-bar-poke.sh`, on PATH, pinned by `test/bar-poke.bats`)
    rather than writing the pair out — `focus`, `awake`, the focus watcher's
    launchd argv, the AI room's `agentAwakePoke`, `aerospace-notify.sh`'s
    `workspace` arm and barlib's `bar_emit` are all one call to it now. It is a
    binary and not a shell helper because two of those are a `writeShellScript`
    and a launchd `ProgramArguments`, which can source nothing, and `bar_emit`
    lives in a file only a framework widget reads; core owns it because it reads
    the ROSTER for the bar's binary, so it ships and exits 0 on a machine with no
    bar. Two trigger shapes are deliberately NOT this, and
    `ops/todo/bar-framework.md`'s Pubsub section says which: one that only wakes
    `aerospace_watcher.sh` on the top bar (the OTHER two arms of that same
    file), and one that repaints a single pill on `$SB` alone.
  - **Every reload names its rc** (`--reload
    ~/.config/sketchybar/bar-bottomrc`). `--reload` with no path re-runs the
    config path the instance resolved AT STARTUP, and SketchyBar resolves it
    through the symlink to `/nix/store`, so a bar launched with `--config`
    replays the generation it BOOTED on — every reload, exit 0, `configuration
    loaded..` in the log. That is `bar-bottom` and only `bar-bottom` (the menu
    bar carries no `--config`, so it re-resolves the live path by accident).
    Which bar is exposed is `ps -o command= -p <pid>` — a `--config` in the argv
    is the whole risk, and `lsof -p <pid> -a -d cwd` showing `/nix/store` says
    the same thing. Neither tells you whether it's *currently* stale; for that,
    read the bar against the generation — `bar-bottom --query bar` vs
    `~/.config/sketchybar/sizes.sh`.
  - Every movable pill is emitted from that one table; the coupled left-side
    workspace/leader group and the tour stay on the menu bar. On the MENU bar
    those pills are all `right` (its left and center are spoken for); the bottom
    bar hands out all three of SketchyBar's groups from `haus.bar.bottom.items`,
    whose sides list lives in `modules/bar/sides.nix` — imported by both
    `options.nix` and `default.nix` so the enum and the emission can't disagree.
    macOS reserves the top strip of a display and reserves NOTHING at the
    bottom, so windows's `outerBottom` carves the room instead.
- **Any pill that starts `drawing=off` must also set `updates=on`.** BOTH bars'
  `--default` carries `updates=when_shown`, and SketchyBar applies that to EVENT
  delivery, not just to `update_freq` ticks: a hidden item is not dispatched to
  at all, so the very script that would turn its drawing back on never runs.
  Starting hidden is a one-way door under the inherited default. It hides well,
  too: a hand-run `--update` (`SENDER=forced`) DOES reach a hidden item, so
  poking the pill by hand repaints it perfectly and only the live event path
  fails. `media` carries `updates=on` on the movable side; `page` and
  `bar_position` do among the pills `sketchybarrc` writes by hand.
- **A new default app pick** (an app the layer thinks a finished machine has,
  not one a room needs to do its job): it goes in `modules/apps` — one
  `haus.apps.<thing>.enable` knob in its `options.nix`, and one roster entry
  (never a bare `home.packages` line). An app a room NEEDS (AeroSpace,
  SketchyBar, espanso) belongs to that room.
  - **It does not get to claim a file type.** `haus.terminal.hijackFileAssociations`
    is the only list of types haus binds, and keeping it the only one is the
    rule: two haus-owned apps claiming one type never settles, because both
    claims re-run on every activation and macOS stops to ask which app wins —
    every rebuild, forever. That is measured. The video player pick claimed
    thirteen extensions until 2026-08-31, and because `.mts` and `.m2ts` resolve
    to ONE shared AVCHD UTI the dialog came back on every single rebuild until
    the two lists were reconciled by UTI rather than by spelling. If a pick
    genuinely must own a type, add it to terminal's `editorExts` neighbourhood
    where the one list lives — and know that a nixpkgs bundle needs
    `lsregister` in the same activation, since its store path moves on every
    version bump and binding a type LaunchServices hasn't seen is a silent `-50`.
- **A pill with a dropdown toggles it as usual, then arms `barpop` in the
  background** — `sketchybar --set <item> popup.drawing=toggle; barpop arm
  <item> &` (the `popToggle` helper in `modules/bar/default.nix` writes exactly
  that; plugin scripts spell out the literal
  `/run/current-system/sw/bin/barpop`). A **framework widget writes none of
  this**: `popup_open`/`popup_toggle` are the runtime's, and everything below
  is why they exist rather than something a widget re-derives. SketchyBar hears clicks on its own items
  and nothing else, so a popup it opened could otherwise only be closed by
  clicking that pill again. `barpop` (`modules/bar/barpop.swift`, built by
  `barpop.nix`) is the missing half: an AppKit global mouse-down monitor
  (Accessibility-gated for KEY events only, so no TCC prompt) that closes the
  popup on the first click outside the bar and outside the popup's own rows. One
  process, alive only while a dropdown is; opening one closes any other.
  - **The ordering and `&` are load-bearing, and so is the absence of Foundation
    `Process` inside the binary.** A sketchybar round trip costs ~4 ms spawned
    by hand and ~85 ms through `Process`. The toggle runs first and alone, the
    popup's row rects are read once at arm time, and the dismissing call is
    fired without waiting: ~12 ms to open, ~30 ms from click to closed. Arming
    inline and scanning rects on the click instead costs ~200 ms to open and
    over a second to close a 16-row pill.
  - **The arming gate WAITS for the bar to answer, and an unanswered `--query`
    is not a closed popup.** A pill that REBUILDS its rows before toggling
    (`--remove`, then one `--add` per row — 44 of them on a busy agents popup)
    leaves sketchybar's mach service unable to answer for ~150 ms, and in that
    window `--query <item>` returns an EMPTY STRING rather than `drawing: off`.
    So `popupDrawing` returns `Bool?` with `nil` meaning "no answer", the gate
    polls (backing off, since each retry is a spawn aimed into the busy window)
    up to 600 ms for a real one, and the click path and watchdog test `== false`
    so a busy bar can't reap a guard for a popup still on screen. None of the
    numbers above move: arming is still backgrounded, so the wait is never on
    the open path.
- **Theme**: `haus.theme.{flavor,contrast}` are the single source of truth, and
  **`modules/lib/nebelung.nix` is the only place that resolves them.** It
  returns the themes-package `root` to source rendered files from, the `palette`
  (name → hex), and the `flavor` — which is load-bearing, not decoration:
  whiskers names its output after the flavor it rendered
  (`catppuccin-latte.conf`, `Catppuccin Latte.tmTheme`, `zen/themes/Latte/`), so
  paths are built from `nb.flavor`, never the literal `"mocha"`. terminal, bar
  and theme all import it; `catppuccin.flavor` in terminal follows it. Getting a
  path wrong here is INVISIBLE at eval (it's just a store path that doesn't
  exist), which is why `nix flake check`'s `theme-variants` pins the
  flavor/contrast → variant/subdir table as a golden file — and why the same
  rule lives in exactly one place on each side of the repo boundary (nebelung's
  `variantDir`, this file). **A path you spell INTO any store output — a
  nebelung port, another tool's skill folder — gets
  `modules/lib/checked-ref.nix`**, whose header has the why: unchecked, a wrong
  one is green at eval, green at `nix flake check`, green through the
  home-files build, and lands a DANGLING SYMLINK in the user's `~`, found
  months later. `guard` for a builder with other work to do, `collect` when a
  `home.file` source has to point at the result. Raw dotfiles nix can't inject into (ghostty
  `config`) reference the *rendered file*, not the flavor, so they need no
  per-flavor edit.
  - Adding a flavor means: a nebelung `VARIANTS` entry, one enum value in
    `modules/theme/options.nix`, one row in the `theme-variants` golden table,
    and a `nix flake update nebelung`. Nothing else *for colour*. One non-colour
    line does want you: `modules/theme/default.nix`'s `appearanceWanted` maps
    flavor → macOS Light/Dark for `theme.systemAppearance = "flavor"`, and a
    flavor it doesn't know silently gets Dark. That's a polarity question rather
    than a palette one, which is why it isn't in `modules/lib/nebelung.nix`.
- **Iterating on a terminal edit costs nothing.** `bench try switch`, and
  Ghostty's own watcher applies the new keybinds, theme and options to every
  running window in about a second. Windows, sessions and live agents stay put —
  and a window's shell lives in a `zmx` session that outlives the window, so
  even a restart comes back to the same scrollback.
- **The chord layer is pounce's, not Ghostty's** (`modules/launcher`'s
  `appHotkeys`, cross-referenced by `modules/terminal/ghostty/config` and taught
  by `modules/terminal/term-bindings.nix`). Every terminal chord that *does*
  something — ⌘F, ⌘L, ⌘Y, ⌘N, ⌘↵, ⌘G, ⌘B — is an app-scoped entry in pounce's
  event tap, consumed only while Ghostty is frontmost. This is measured, not
  stylistic: `ghostty +list-actions` on 1.3.1 lists 85 actions and **none of
  them runs a command**, so a chord that shells out has nowhere else to live.
  Ghostty's config unbinds each of them so the tap is not racing a built-in;
  those three files move together or the cheatsheet starts lying.
  - ONE chord is the exception, and it is the shape of exception to look for:
    **⌘⇧R is bound by GHOSTTY**, in `modules/terminal/ghostty/config`, because
    `reset` is one of those 85 actions — a terminal chord that shells out to
    nothing has no reason to ride the tap. It still belongs in
    `term-bindings.nix`, and its `chords` entry matters MORE rather than less:
    `haus.launcher.items` hotkeys are registered GLOBALLY, so one on ⌘⇧R would
    beat a Ghostty keybind as surely as it beats an app-scoped tap. The rule is
    "a chord that runs a COMMAND is pounce's", not "every chord is".
- **Every window is a `zmx` session** (`modules/terminal/scripts/launch.sh`,
  which is Ghostty's `command`). Persistence is the small half — the
  load-bearing half is that Ghostty's AppleScript API can create a surface but
  cannot READ one, and three shipped features read a window: ⌘F find, ⌘L links,
  and the bar's agent peek. `zmx history` / `zmx tail` is that read API. **The
  `zmx ls` / `zmx get` wire format is read through
  `~/.config/haus/term/zmx-rows.sh` alone** — its traps (the attached-row
  marker glued to the first key, the 0.7.0 `start_dir` rename, `zmx get`
  going space-separated) each broke a hand parse silently before it existed,
  so never parse either by hand again; its header is the spec. One byte-pinned
  exception stands: raise-session.sh's `window=` claim list, which
  `test/raise-session-lane-join.bats` extracts verbatim by sed — worth more
  as a test that keeps working than as a dedup. The
  session is named `term.<n>`, lowest n that no session holds; a lane is
  `scruff.<repo>.<lane>` and belongs to `lanes/lane-open.sh`. **That prefix is
  not haus's name to choose.** The tool keys a lane's parked trill fin as
  `scruff/<repo>/<lane>` (`askKeyPrefix` in `internal/commands/notify.go`) and
  names its marker file after that key with the slashes flattened to dots, so
  the session name IS the marker name and the two have to match byte for byte.
  Rename either half here and `lanes/lane-seen.sh` silently stops joining: no
  error, no log, and every lane's fin stays parked forever.
  - ⚠️ **Moving that prefix takes two releases, not one.** It was `holt.`
    until scruff 1.2.0, and the way it moved is the pattern to reuse: each
    half wrote the new spelling and kept READING the old one for one release,
    then dropped the read arm at 1.3.0. Not compat for other people's machines
    — for the rebuild itself, because a Ghostty window carries its FORCED
    title until it is closed and a fin already on trill's ledge can only be
    resolved by the key that put it up. Without the arm, every lane open at
    the moment of the switch loses its window-sort and its banner-resolve.
    Write one spelling, read two, and date the arm in the comment that adds it.
  `scripts/focused-session.sh` is the one window→session join — by window id,
  which is the `lwindow=` label lanes/lane-open.sh stamps for a lane and the
  `window=` one launch.sh stamps for everything else, and only then by the
  forced window title, for a lane that carries no stamp. AeroSpace's
  `on-focus-changed` runs `lanes/lane-seen.sh` over that join (wired in
  `modules/windows`), which is how a lane's parked trill fin comes down when you
  go to its window YOURSELF instead of clicking the banner — scruff's own hooks
  only see the session move, not you arriving.
  - **A NEW window is always a NEW session, and only `restore-windows.sh` ever
    reattaches one.** "Lowest n that no session holds", not "lowest n that is
    not ATTACHED": a `term.<n>` left by a closed window is a live shell in some
    other directory, so the chord whose whole promise is "a shell HERE" would
    hand you an old one somewhere else. Walking back in is
    `scripts/restore-windows.sh` — one window per `clients=0` session,
    automatically for the FIRST window of a Ghostty
    (`haus.terminal.restoreWindows`, and "first" means nothing is attached
    anywhere) and on demand from the palette. It hands lane sessions to
    `raise-session.sh`, because only `open -na --title` forces the title the
    AeroSpace join reads, and spawns `term.*` itself with `HAUS_ZMX_ATTACH` in
    the environment — a forced title on a plain window would freeze the title
    its program is supposed to own. The user-facing half of the same fact: **⌃D
    ends a shell and frees its number, ⌘W parks it for the next start.**
- **The core CLIs** (`modules/core`, each on `PATH` via `writeShellScriptBin`,
  source beside `default.nix`): **`haus.sh`** (the end-user machine driver:
  rebuild/update/rollback/doctor/status — knows nothing of the family repos),
  **`haus-activate.sh`** (the privileged half of a rebuild: `haus` and `bench`
  build as YOU, then hand the built store path to `sudo haus-activate <system>`,
  which sets the system profile and runs that system's own `darwin-rebuild
  activate`. It exists so root never evaluates the config a SECOND time —
  `darwin-rebuild switch --flake` builds again, against root's separate caches
  under `/var/root/.cache/nix`, costing ~3 s after a host edit and ~15 s
  whenever a flake input moved. Its stable `/run/current-system/sw/bin` path is
  load-bearing: security's NOPASSWD rule must name a literal path),
  **`awake.sh`** (launchd-owned timed/indefinite macOS caffeinate assertions;
  bar's optional coffee pill is only its controller), and
  **`haus-bar-poke.sh`** (`haus-bar-poke <event> [key=value…]` — the both-bars
  trigger, the one copy of the pill-repaint rule above. Core's for the same
  reason `awake` is: it reads `haus.roster.sketchybar.binPath` rather than the
  bar room, so three rooms call it without knowing whether a bar exists).
  - **`haus skill` is core's, and it is the one place core names a path inside
    another room.** A3 of the family agent-surface standard (the workshop's
    `docs/agent-surface.md`) says every tool prints its own skill and can
    install it — on every machine, whatever rooms that machine runs. So
    `modules/core/default.nix` imports `../ai/agents/skill.nix` and hands the
    result to the wrapper as `HAUS_SKILL_DIR`. That is an import of a
    DERIVATION, a pure package expression taking only `pkgs` — the direction
    three rooms already import `modules/lib/nebelung.nix` in — and it is not the
    `config.haus.ai.*` read the `haus-fix` rule below forbids: modules/ai still
    owns whether the skill is INSTALLED into a client, core only owns whether it
    can be PRINTED. It must be handed in and never looked for beside the script:
    `agents/SKILL.md` is a TEMPLATE whose version line is the literal
    `@hausVersion@`, and `haus.sh` is `readFile`'d into a store binary, so a
    haus user has no checkout to read the source from anyway. The price, paid
    knowingly: a machine with the AI room off now builds that one small
    derivation, and `darwinModules.core` no longer stands alone without
    `modules/ai/agents/` beside it.
  - **`haus skill install`'s client table exists once**:
    `modules/ai/agents/homes.nix`, pure data the same way `skill.nix` is a pure
    derivation, because core may not read that room's config to ask. modules/ai
    imports it as `agentHomes`; core renders it into the wrapper as
    `HAUS_AGENT_SKILL_DIRS` (`claude=.claude/skills:codex=…`), which haus.sh
    PARSES — there is deliberately no bash copy left to rot, so off the wrapper
    the script refuses in words rather than guessing.
    `test/agent-surface.bats` asserts that wiring, end to end.

  Five more live in **`modules/ai`**, which writes the system profile they land
  in, because the room that owns a capability owns its payload:
  **`statusline.sh`** / `statusline-refresh.sh` (the agent HUD, reading `scruff`'s
  registry), **`agent-state`** (the one writer of agent state behind bar's
  `agents` pill), **`scruff-cache`** (the one warm copy of `scruff --json`) and
  **`haus-fix`** (`modules/ai/fix.sh` — "Fix it with AI" for a rebuild that
  failed).
  - `haus-fix` is the one that reaches BACK into core, and the direction is what
    keeps it legal. A failed `haus rebuild` writes
    `~/.local/state/haus/last-failure` (the phase, the host, the log offset, the
    derivation — registered in `modules/lib/state-files.nix`), puts one offer in
    front of the person, and `haus fix` is a line of dispatch onto this binary.
    **Core's whole test is `command -v haus-fix`** — never
    `config.haus.ai.*`, which core may not read — so the room's own switch is
    what decides whether there is a fixer to find, and a machine without one
    prints the failure exactly as it always did. The CTA also needs `$CONSUMER`
    to be a git repo, because the undo for everything the agent does is
    `git -C ~/.config/nix revert HEAD`, and it runs the client with its
    permission gate open on that basis alone. `haus.ai.default` and
    `modules/lib/agent-oneshot.nix` are substituted in at build time; the script
    verifies with `nix eval` rather than taking the agent's word, and never
    activates — `haus rebuild` stays the person's.
  - `agent-state` has no source file of its own: `modules/ai` `readFile`s
    `modules/bar/sketchybar/plugins/agents-hook.sh`, the same script bar
    installs into the bar's plugin dir, so the PATH copy and the bar copy can
    never drift. Every client's hooks call it (`agent-state
    <working|waiting|idle|remove> <client>`), which is why the wirings the AI
    room writes for opencode and codex never need to know where a bar keeps
    its plugins. pi has an extension API rather than a hook file, so its
    wiring is a FILE terminal writes —
    `~/.pi/agent/extensions/haus-agent-state.ts`
    (`modules/terminal/pi/agent-state.ts`) — and being the one seam pi has, it
    carries the LANE BANNERS too: it hands `scruff hook notify` the same
    Claude-shaped payload the four Claude Code hooks do, so a pi lane's trill
    fin is keyed, focused and resolved by that one code path rather than a
    second copy of it. Two events with no Claude counterpart get a banner of
    their own through `haus-notify` (a failed compaction, a provider refusing
    the session); the file's header is the whole event map.
  - `scruff-cache` exists because `scruff --json` is an investigation rather than a
    listing — `scruff list` self-heals through a parked reap sweep on the way in,
    and that sweep AND the JSON encoder each dump `lsof -d cwd` machine-wide
    before any lane's landed/PR verdict touches git or `gh`, so it costs seconds
    with zero lanes registered. Neither consumer can pay that inline (the bar's
    agents popup redraws on a 10 s tick; the Lanes palette opens inside pounce's
    8-second loading skeleton), so the TTL + one-winner lock live in front of
    both.

  One more lives in **`modules/secrets`** for the same reason:
  **`haus-secret`** — the single door to the values the ROOMS declared
  (`haus._contrib.secrets` → `~/.config/haus/secretspec.toml`). A room's wiring
  says `haus-secret <NAME>` and never learns which provider this Mac uses;
  `--list` / `--status` / `--check` are the person's half. It deliberately does
  NOT invent a `--reason` for a read: secretspec's `require_reason` policy is
  what makes an agent write down why before it may read a value, and a wrapper
  that supplied one would hand every agent on the machine a blanket excuse.

  All are plain bash embedded via `builtins.readFile`, so a rebuild re-installs
  them on `PATH`. Agent worktrees themselves are **`scruff`**
  ([its own repo](https://github.com/hausfold/scruff)), taken as a flake input.
  `haus`, the workshop's `bench` and `scruff` are named apart on purpose so they
  never shadow each other — `haus` = your machine, `bench` = the family repos,
  `scruff` = the worktree tool. (User-facing docs: the
  [AI room](https://hausfold.co/docs/haus/rooms/ai/) and the
  [haus reference](https://hausfold.co/docs/haus/reference/haus/).)
- **New pounce command**: generic ones live in the
  [pounce repo](https://github.com/hausfold/pounce)
  (`pkgs/pounce-commands/commands`); layer/machine-specific ones live HERE in
  `modules/launcher/commands/` — one self-describing script each (metadata in a
  `# pounce: key = value` header), layered onto the palette via
  `pounce-commands.override { extraCommandDirs … }`. No registry to edit in
  either repo; drop the script and rebuild.
  - **A script that draws its own list with `pounce` over stdin gets back
    `<action>\t<raw-row>`, not the row** (pounce's `State.swift`, `buildCommit`'s
    `.plain` case) — `action` is `enter`/`cmd`/`opt`/`ctrl`, whichever key
    committed. A `case` on field 1 of that answer matches the literal `enter`
    every time, falls through the catch-all arm, and the menu does nothing at
    all — no error, no log. So the parse is written ONCE:
    `commands/lib/menu-commit.sh`'s `menu_commit` splits the answer into
    `MENU_ACTION`/`MENU_ROW`, and `menu_field "$MENU_ROW" <n>` indexes the row
    with the same field numbers your printf gave it. Source it at
    `$(dirname "$0")/lib/menu-commit.sh` and never re-strip the verb by hand —
    `test/menu-commit.bats` counts the consumers, so a private parse goes red.
    (A `--dial` answer carries one extra middle field; that grammar belongs to
    the caller that passed the flag — see `spawn-agent.sh`'s `dial_agent`.)
  - **A row with nothing to act on can absent itself**, with `# pounce: whenFile
    = <path>`: pounce hides it while that file's first line is `0`. `pages.sh`
    is the one that does — the file is `~/.local/state/haus/any-page`, written
    by `windows/scripts/workspace-mru.sh push` on every workspace change, so
    `Pages` is missing from a Mac with no page anywhere and back with the first
    one. `resort-windows.sh` calls that same `push` on its way out, because it
    CREATES pages and ends on the workspace it started on — the one path that
    makes pages without a workspace change. A FILE and not a command because the
    daemon's registry refresh runs on the ⌘Space keystroke
    (`CommandRegistry.refresh()` inside `presentLauncher`) and may not fork;
    only a literal `0` hides, so a tiler that is not running, an empty answer
    and a machine that never writes the file all leave the row listed — hiding
    is the direction that takes a working row away and says nothing. It is the
    "is there anything here at all" question;
    `haus.launcher.items.<key>.workspaces` is the cheaper "where are you" one
    (pounce matches a name from a file, no fork), used by `cmd:lane-here` and
    the `shell-here` pair. A hidden row still needs a cheatsheet card that says
    so, which is `# pounce: cheatWhen = …` — ours, not pounce's, read by
    `riceCommandRows`.
  - **A `# pounce:` key the DAEMON does not parse is ignored in silence**, and
    the daemon is the only path ⌘Space takes. `nix flake check`'s
    `pounce-command-keys` diffs every key `./commands` uses against
    `CommandRegistry.swift` in the LOCKED pounce for that reason — the bash
    `pounce-palette` has its own copy of the parser, and implementing a key
    there alone ships a feature that never runs.
- **The haus tour** (first-run tutor): ONE state machine,
  `modules/bar/sketchybar/plugins/tour.sh`, drives a single bar pill. The
  leader-mode scripts + `aerospace-notify.sh` feed it `tour.sh event <name>`
  behind a `[ -f ~/.local/state/haus/tour ]` guard — one stat when idle; keep it
  that cheap. `haus tour` and the pounce `tour` command are just doors into it.
  Gated by `haus.tour.enable` via the generated `tour_item.sh` /
  `tour_config.sh` (see `modules/bar/default.nix`).
