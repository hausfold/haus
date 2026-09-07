# AGENTS.md

**`haus`** — composable nix-darwin modules (the **layer**: the `haus.*` options
and the `haus` CLI) plus the **desktops** built on them: `blank`, `minimal`,
`everyday` and `hacker`, the `mkHaus` default. A machine consumes it via
`mkHaus` and adds only its host (identity, private apps, secrets). **hausfold**
is the org, never the layer; the repo is `hausfold/haus`. Layer and desktop
share files, so say in each commit whether a change is what every desktop gets
or only what `hacker` looks like.

**The option namespace is `haus.*`, and it is the only one.** Declare every
option in a file `modules/options-modules.nix` lists (`modules/default.nix`
imports that list; never write the paths out again). `modules/moved.nix`
aliases only options that changed address inside `haus.*`; `haus.agents.*` has
no alias, so writing it is an eval error. Spellings: `haus.desktops.hacker`,
`haus.lib.checkDesktop`, `inputs.haus.url`, `mkHaus`, `share/haus/`; state in
`~/.local/state/haus`, `~/.config/haus/`, `~/.cache/haus/`,
`/Library/Application Support/haus/`. The agent skill installs as `haus/`
(frontmatter `name: haus`) in `~/.claude/skills/`, `~/.codex/skills/`,
`~/.config/opencode/skills/` and `~/.pi/agent/skills/`.

Per-client wiring is [`.agents/`](./.agents/README.md). haus also *ships* agent
config to users (`haus.ai.instructions`, `haus.ai.skill`, `modules/ai/agents/`)
— a product surface under the same one-body rule.

## Am I in the right repo? (routing)

The workshop's `AGENTS.md` (`~/code/workshop`) is the family routing table.
This repo owns the layer and the desktops.

| Want to change… | Repo |
|---|---|
| a room: macOS defaults, tiling (windows), the menu bar (bar), the shell and what opens which file type (terminal), Touch ID + firewall (security), secrets plumbing (secrets), Pounce wiring (launcher), the notch shelf (shelf), Focus/DND (focus), the GitHub webhook bridge (github), accent + Light/Dark (theme), the generated desktop (wallpaper), the apps every machine gets (apps) | here |
| the pounce app or a generic command script | `~/code/workshop/pounce` |
| colors / the palette | `~/code/workshop/nebelung` |
| one machine's apps / identity / secrets | `~/.config/nix` |
| user-facing docs | `~/code/workshop/hausfold.co`, `content/docs/` — `haus/` for the layer, `hacker/` for the desktop; rooms, not guides (`haus/rooms/bar.mdx`) |

A request for another repo: stop and say so before editing. A change to
user-facing behaviour (an option, a keybind, a workflow) updates its
hausfold.co page in the same round or it drifts. **Never hardcode identity** —
git name/email/signing key are `haus.*` options the host sets (`options.nix`).

## Architecture

```
flake.nix                 # mkHaus + darwinModules outputs + the example host
modules/
  default.nix             # imports every room
  options.nix             # host-set knobs: git.*, theme.accent, wallpaper.*, terminal.*,
                          #   roster, windows.*, bar.*, launcher.*, focus.*, shelf.*,
                          #   tour.enable, homebrew.*, secrets.provider
  options-modules.nix     # the per-room options.nix list, shared by both renderers
  options-groups.nix      # the ROOM REGISTRY: every public namespace + darwinModules export,
                          #   its room, per-leaf desktop-safety, the thirteen rooms' title +
                          #   sentence. `room-registry` fails on anything unmapped
  moved.nix               # aliases for options that moved inside haus.*; some get none
  options-doc.nix         # nixosOptionsDoc → .#options-json and the skill
  site-data.nix           # .#site-data, committed at docs/site-data/ — regenerate + commit
                          #   when it moves, or `site-data-current` goes red
  lib/gui-wait.nix        # cold-boot-safe GUI agent launch: .wrap (executable) + .script
  lib/ui-load.nix         # snug's painter bootstrap: ui_resolve + ui_load
  lib/swift-bin.nix       # swiftBin, the only place `xcrun swiftc` is written
  lib/contrib.nix         # mkExtensionPoint + mkExtensionRegistry — the extension points
  lib/settings-panes.nix  # System Settings deep links, once (a wrong URL lands on the front
                          #   page with no error)
  lib/desktop.nix         # the desktop seam's validators
  desktop/                # haus._desktop.sources + the assertion refusing a second desktop
  lib/namespaces.nix      # who owns haus.<name>: `haus.my.*` is reserved (`namespace-guard`)
                          #   + the unregistered-namespace walk
  namespaces.nix          # that walk as a WARNING on the consumer's Mac, never a refusal
  apps/                   # editorial picks as roster entries; packs/ are
                          #   haus.apps.packs.<name>.enable, our own data (a stranger's
                          #   collection is a room)
  appearance/             # haus.appearance.largePrint: four rooms' options at mkDefault
  ai/                     # haus.ai.*. Owns scruff, factory, the statusline pair, agent-state,
                          #   agent-desktop-guard, scruff-cache, haus-vm-shot, haus-fix
                          #   (system) + the instructions/skill files (home; a path collision
                          #   with terminal's is an error)
    agents/               # the two skills every client in haus.ai.clients gets (agentHomes
                          #   has the paths): `haus` and `hausfold/SKILL.md`, plus the consumer
                          #   starter pair `haus doctor` offers. skill.nix builds the package
                          #   and holds the A4 guard: frontmatter, `name:` vs install dir,
                          #   description length, the 150-LINE CAP, no `@placeholder@`, no
                          #   unshipped references/ pointer — read off $out, since SKILL.md is
                          #   a template. Over the cap: references/, or `haus --help`
  core/                   # macOS defaults, Homebrew framework, GC, and the CLIs haus /
                          #   haus-activate / awake / haus-notify / haus-bar-poke
  roster/                 # haus.roster → the Homebrew/packages it implies
  workspaces/             # haus.workspaces: named AeroSpace workspaces + their roster apps
  snippets/               # haus.snippets: espanso as a cask, not pkgs.espanso (TCC; header)
  displays/               # haus.displays + the hausdisp Swift helper
  theme/                  # accent, flavour, macOS Light/Dark
  wallpaper/              # haus.wallpaper.*; `minimal` is GENERATED by package.nix (resvg +
                          #   ImageMagick), looks/ holds the hand-made PNGs
  terminal/               # zsh, starship, git, yazi, ghostty + zmx + theming; floatring +
                          #   floatpin (haus.terminal.floatBorder, haus.terminal.floatOnTop;
                          #   floating is a LAYOUT in AeroSpace, not a stacking order)
  windows/                # AeroSpace tiling + hausrect (window rects by id, which AeroSpace
                          #   cannot report; scripts/tiling-mode.sh sizes its grid off them)
  bar/                    # SketchyBar + barpop
  security/               # Touch ID sudo + passwordless activation
  launcher/               # the palette daemon (the notarized release app); item-grammar.nix
                          #   mirrors pounce's item-key grammar (`pounce-item-grammar`)
  shelf/                  # perch, via its flake input
  notifications/          # haus.notifications.compositor (the trill bundle; drawing THROUGH
                          #   trill is core's) + mail.nix: haus.mail.*, goimapnotify +
                          #   mail-announce.py — every output a card, no filter option
  focus/                  # Focus/DND: hotkey 175 + Slack + hooks, and haus.focus.scenes
                          #   (`quiet` is built in and reserved). Declarative; no daemon
  github/                 # webhook bridge: loopback receiver behind cloudflared + the one
                          #   SIGNAL GitHub watchers read. No token, never writes;
                          #   `haus.github.hooks` is a declaration `haus doctor` diffs; rooms
                          #   subscribe via haus._contrib.github.subscribers
  secrets/                # secretspec, provider per host; the haus._contrib.secrets deck →
                          #   ~/.config/haus/secretspec.toml, read by `haus-secret`
  portless/               # haus.portless: .localhost URLs; a ROOT daemon on :443, the npm
                          #   tarball with no lockfile
  meridian/               # haus.ai.meridian: loopback Anthropic API off a Claude Max
                          #   subscription. A per-USER agent — it reads Claude Code's OAuth
                          #   token from the login keychain, which root cannot;
                          #   buildNpmPackage against a committed lockfile. Namespace ≠
                          #   directory; its options.nix says why
desktops/                 # hacker (default), blank, everyday, minimal — data, one per host
compat/presets.nix        # the retired preset format as warning aliases; never grow it,
                          #   delete it with the `presets` output
test/desktops/            # one fixture per seam rule, valid and invalid (`desktop-seam`)
hosts/example/            # the template a consumer copies
script/                   # by-hand operator scripts; build-golden-vm.sh bakes the tart image
                          #   `scruff runtime up --backend tart` clones
```

Each `modules/<room>` is a nix-darwin module; home config goes through
`home-manager.users.${username}`, set once per module (a dynamic key can't be
split), as a module function (`{ lib, pkgs, ... }: {...}`) when you need
`lib.hm`. Homebrew is contributed per room; core owns the framework.

### Desktops

The model is [`docs/model.md`](./docs/model.md). `mkHaus` takes `desktop`
(default `./desktops/hacker.nix`); `desktop = null` selects the bare foundation
or makes room for one `lib.desktop` in `extraModules`; a standalone
`darwinModules.<room>` import selects none. Three rules, all enforced:

- **closed shape** — an attrset whose only top-level key is `haus`: no module
  function, `imports`, `_module`, `system.*` or `home-manager.*`.
- **desktop-safe leaves only** — every leaf a public `haus.*` option the
  registry marked desktop-safe, transitively: `haus.roster` yes,
  `haus.roster.<app>.package` host-only; `haus.displays.internal` yes,
  `haus.displays.<uuid>` no.
- **the host wins** — desktop leaves arrive at priority 900, between a host
  assignment (100) and a room's `mkDefault` (1000); never `lib.mkForce`. A
  host's list replaces the desktop's, never appends.

A new rule is a fixture in `test/desktops/` plus its expected diagnostic in
`flake.nix`, and must read correctly in four places: the seam, the flake check,
the generated host file and `haus show` (`modules/desktop-check.nix`).
`haus.lib.checkDesktop` throws, `haus.lib.desktopFailures` lists,
`haus.lib.showDesktop` shows — public so a third party can self-test.

## Build / test

```bash
nix eval .#darwinConfigurations.example.system.drvPath
```

The `example` host is placeholder identity (user `you`); real testing is a
consumer (`~/.config/nix`, host `mbp`) through `bench try`, which builds
against this checkout, uncommitted edits included; `bench ship` ripples the
locks once committed. CI (`.github/workflows/check.yml`) evaluates the example
host and runs `nix flake check`, shellcheck and the `test/` suites (`bats
test/*.bats`, `bash test/*.sh`). A suite that renders through snug needs
`HAUS_UI_SH` first — CI's "snug's painter, at the pinned rev" step writes it
into `$GITHUB_ENV`; below a render suite the role cases SKIP, which reads as
green. `nixfmt` formats `.nix` files.

## Before you open a PR

The workshop's `AGENTS.md` has the PR shape and the standing request to spawn
the pre-PR assurance subagent — this instruction satisfies any "only when
asked" harness rule. What that clean-context pass hunts for HERE: a hex that
belongs in nebelung or logic that belongs in pounce; a `haus.*` option added or
renamed with no edit to hausfold.co's `content/docs/`
(`haus/reference/options.mdx` is generated from `docs/site-data/`); a keybind
colliding across AeroSpace / pounce / macOS symbolic hotkeys (silent — the
loser stops firing); a breaking rename whose consumer edit isn't in the same
PR; hardcoded identity. Advisory, never a gate.

## Rules

- **Never `osascript -e 'display notification …'`.** Everything on screen goes
  through `haus-notify` (`modules/core/haus-notify.sh`): trill when its daemon
  answers, Apple's banner otherwise. Every call names its own `--source`
  (`haus.bar.harvest`, `haus.lane`, …) — what `~/.config/trill/rules.json`
  matches on; no `haus.*` option gates it. From anything launchd spawns, address
  `/run/current-system/sw/bin/haus-notify` in full. `trill` on PATH is a wrapper
  (`modules/core/trill.sh`), not a symlink; `haus.notifications.compositor`
  installs `/Applications/Trill.app`, the wrapper's second candidate, and adds
  no `bin/trill`. `HAUS_NOTIFY=apple|trill|off` tests the fallback or silences
  the shim; an unknown flag is warned about and dropped, never refused.
- **`snug` is where a line on the TERMINAL comes from** (the screen is
  `haus-notify`'s): a flake input (`inputs.snug`, `hausfold/snug`) on PATH
  unconditionally from `modules/core`. Callers name a role (`accent`, `ok`,
  `warn`, `err`, `muted`, …), never a 256-colour index, and degrade — guard with
  `command -v snug`, fall through to plain `printf`. How a thing is DRAWN, and
  colour precedence, are snug's README and AGENTS.md; whether haus prints it is
  this repo's. The haus half:
  - **`HAUS_UI_SH`** is snug's bash half (`share/ui.sh`, beside `bin/snug` in
    its derivation), handed to `haus.sh` by `modules/core`'s wrapper with
    `--set-default`; `haus.sh` is `builtins.readFile`'d into a store binary, so
    `dirname $0` is useless. Source it guarded, `[ -r "${HAUS_UI_SH:-}" ]`,
    never bare — under `set -euo pipefail` either failure kills `haus` at load
    with nothing on either stream. `test/phase-painter.bats` fails on any
    `\033[` outside a comment in `haus.sh` / `haus-show.sh`.
  - **The one PERMANENT exemption**: `bootstrap.sh` and
    `modules/core/haus-activate.sh` run before snug is reachable and carry its
    numbers INLINED (hex, 256 index, 16-colour name, the gate ported);
    `test/installer-palette.bats` diffs them against the generated `share/ui.sh`
    for the `nebelung` variant at the pinned rev. Never hand-pick an index, and
    never inline a palette anywhere without a drift test.
  - **A suite that RUNS `haus.sh` names an interpreter that can**: /bin/bash
    3.2 has no `coproc`, so `test/haus-settings.sh`, `test/haus-plan.sh` and
    `test/haus-add.sh` re-exec under a bash 4+ and spawn the subject as `$BASH`
    (`test/phase-painter.bats`'s `haus_sh` handle pins it for every plain
    suite). CI runs the first two under bash 5 and cannot run
    `bash test/haus-settings.sh` at all.
  - **Every ROW with columns is budgeted, never declared**: `ui_col` +
    `ui_trow` + `ui_table_data` measure the real window. The four table
    painters — `haus.sh`, `haus-show.sh`, `modules/focus/focus.sh`,
    `modules/github/signal.sh` — carry no fixed width outside a
    `UI_READY`-empty fallback (`test/phase-painter.bats` counts them). Two
    `%-Ns` are named exceptions: `haus-show.sh`'s `field`, a one-row label, and
    `haus set`'s picker, the parse contract for `gum filter`'s answer.
  - **The bootstrap is spelled ONCE, in `modules/lib/ui-load.nix`** —
    `ui_resolve` (fill `HAUS_UI_SH` and stop) and `ui_load` (source once,
    lazily; `UI_READY` only when everything `UI_WANT` names arrived), held
    verbatim by all ten carriers. `ui-load-sync` diffs each against the source
    (`uiLoadCarriers` is the list), `test/phase-painter.bats` diffs them against
    each other. Edit there, re-copy. Per carrier: how the path arrives, when
    `ui_load` runs, and `UI_WANT` naming every verb the script CALLS.
  - **Five binaries pay lazily** — `focus`, `github-signal`, `haus-secret`,
    `awake`, `haus-fix`. Substituted: `focus` and `haus-secret` default
    `HAUS_UI_SH` from a `@uiSh@` hole and call `ui_load` only from verbs that
    draw; `haus-fix` takes the hole through `replaceStrings` beside `@client@`
    and `@oneshot@` and gates the CALL on a terminal. Prepended by the
    derivation: `github-signal` past its sourced-half guard, `awake` from the
    prose paths only. Four carry `#!/usr/bin/env bash`: `focus` and
    `haus-secret` because that line IS the interpreter under launchd, `awake`
    and `haus-fix` because `test/awake.sh` and `test/rebuild-fix-cta.bats` run
    them off disk. `github-signal` is not asserted — its
    `~/.config/haus/github/signal.sh` copy is only sourced.
  - **`awake` is also a DATA SOURCE.** `status` (the default,
    `command=${1:-status}`) draws; `awake status --raw` answers the coffee pill
    (`modules/bar/sketchybar/plugins/caffeinate.sh`) with
    `mode<TAB>remaining<TAB>until`, so `raw_status` and `_run` never reach
    `ui_load`; `test/awake-ui.bats` asserts both halves. Confirmations stay on
    fd 1 for every verb, `die` on fd 2. Its `date` is `$DATE`
    (`AWAKE_DATE_BIN`): `date -r <seconds>` is BSD.
  - **Three more carry `ui_resolve`**: `modules/ai/statusline.sh`,
    `modules/terminal/scripts/image-preview.sh`,
    `modules/terminal/lanes/lane-open.sh` — not behind the wrapper, so they take
    the copy beside `bin/snug`. A new caller outside the wrapper uses
    `ui_resolve`; inside a derivation, inject it. A raw escape that is not a
    COLOUR is legal (OSC 8, OSC 2, DECTCEM);
    `statusline.sh`'s `TINT_FABLE` is the one colour exception, a 24-bit
    background gated on truecolor so `NO_COLOR` holds.
  - **One coprocess per COMMAND**, opened by the phase painter: `rebuild` and
    `plan` fork one; `update`, `rollback`, `set` and every report fork nothing.
    `SNUG_TRIED` keeps a snug that died dead for the command. A background job
    that draws needs its own duplicate of the write end; one that draws nothing
    must `snug_detach`, or `snug_close` never returns.
  - **Two streams, per COMMAND, never per verb.** `REPORT=1` is set in the
    dispatch for `status doctor plan diff permissions services btm generations
    get capture`; those draw on fd 1. Everything else narrates on fd 2, stdout
    carrying data only. Per-verb is wrong by construction — `settings_diff` runs
    inside both `haus plan` and `haus set`.
  - **Nothing repaints while `sudo` might prompt**: `PHASE_STILL` makes a phase
    a still bullet; `cmd_rebuild` sets it around `activate` unless
    `sudo -n true` proves the timestamp valid. Reports are on fd 1, so both
    scripts re-run `ui__detect_profile` / `ui__resolve_palette` with `UI_TTY`
    from fd 1 and read `C_*` off that.

## Gotchas

- **`haus rebuild` draws a trill card**, and `bench` carries the same block for
  `bench try` / `bench rebuild` — change one, change the other. It counts paths
  appearing in the store rather than reading nix's output, so the dry run is
  serial and in-shell, and it finds the CLI at RUNTIME — never wire it or
  `haus-notify` to `pkgs.trill`, or a rebuild's progress depends on
  `haus.notifications.compositor`, off by default.
- **`sudo --user=` from activation keeps ROOT's `HOME`** (`/etc/sudoers`:
  `Defaults env_keep += "HOME MAIL"`), so the `launchctl asuser <uid> sudo
  --user=${username} --` shape hands a relaunched GUI app `HOME=/var/root` for
  life. **Pass `-H`** wherever the child launches an app or execs something that
  reads `$HOME`. `defaults`, `activateSettings` and hausax's writes go through
  CFPreferences, keyed by uid, so `modules/core`'s six sites carry no `-H`.
- **launchd GUI race**: GUI agents (AeroSpace, SketchyBar, pounce) launched
  before the Aqua session is up park with exit 78 (EX_CONFIG).
  `modules/lib/gui-wait.nix` polls for Dock/Finder/SystemUIServer from
  `/bin/bash` (the /nix volume isn't mounted yet): `.wrap` for windows and bar,
  `.script` for pounce. **Keep the 60 s deadline** — unbounded, a KeepAlive
  restart parks forever with a live pid, which is why `core` leaves Finder's
  `QuitMenuItem` off. Recover: `launchctl bootout`, then `bootstrap`.
- **pounce release delivery** (`modules/launcher`): TCC keys an Accessibility
  grant to the signing requirement, so the daemon runs the notarized release app
  (`pkgs.pounce-app`, pinned by pounce's `nix/release.nix`); a source build is
  adhoc-signed and loses the grant every rebuild — only `bench try`'s dev-app
  injection runs one, re-signed. New machine: `pounce --request-accessibility`.
- **Homebrew tap-trust** (`modules/core`): `HOMEBREW_NO_REQUIRE_TAP_TRUST=1` in
  `/etc/homebrew/brew.env` — the only place a `HOMEBREW_*` setting reaches the
  rebuild's `brew bundle` (activation runs it under `sudo … env …`); the
  API-refresh window and env-hint silencing live there too.
- **Ghostty's `--title` is INSTANCE-WIDE.** Lanes
  (`modules/terminal/lanes/lane-open.sh`) and float popups
  (`modules/terminal/scripts/float-term.sh`) are own processes launched
  `--title=<name>`, so a plain ⌘T / ⌘N / ⌘⇧N window routed into one is born
  `scruff.<repo>.<lane>` for life. `scripts/new-window.sh` is the one plain
  window spawn: it reads the responder's front title first and falls through to
  `open -na`. The forced set comes from `ps`, never a `scruff.*` pattern
  (`test/new-window-title.bats` pins it). `scripts/focused-session.sh` and
  `scripts/raise-session.sh` keep their impostor subtraction; `lane-open.sh`'s
  ghostty backend keeps its own AppleScript, which returns the window id.
- **Ghostty does not close a TILED window when its process exits** (1.3.1,
  `quit-after-last-window-closed` off) inside an instance that owns other
  windows. `modules/terminal/scripts/launch.sh` runs `aerospace close` on its
  own window id, gated on that id also being focused. A `new-window.sh` window
  running a command (⌘G's gh-dash, an editor) has the same hazard.
- **The Ghostty pre-warm is three copies on purpose, pinned by INVARIANT**
  (`test/ghostty-prewarm.bats`): `new-window.sh`, `lanes/lane-open.sh` and
  `raise-session.sh` carry the same four-line `pgrep -ix ghostty` poll;
  `float-term.sh` and `focused-session.sh` carry none, and the suite pins those
  absences. Don't promote it to a sourced helper — size is the reason, not
  reachability (`$HOME/.config/haus/term/zmx-rows.sh` proves a sibling is
  reachable). An invariant rather than a byte-diff, because `pgrep -x Ghostty`
  was wrong identically in two files.
- **Touch ID + a multiplexer** (`modules/security`): `reattach = true` — every
  window is a `zmx` session; without pam_reattach the prompt beachballs.
- **secretspec + keychain ACLs** (`modules/secrets`): the keyring provider keys
  "Always Allow" to the binary, so a store-path change re-prompts once per
  secret (harmless; gcsm/awssm/bws have no per-item ACL). Login-keychain items
  don't sync via iCloud: a wipe is `secretspec check` + re-entering. A project's
  own `secretspec.toml` and haus's `~/.config/haus/secretspec.toml` are separate
  projects, so one NAME is two items; `haus.secrets.project` points ours at an
  existing project.
- **Determinate owns the nix daemon** (`modules/core`): `nix.enable = false`;
  config in `/etc/nix/nix.custom.conf`; GC is our own weekly launchd job.
- **Every Swift helper goes through `modules/lib/swift-bin.nix`** —
  `swiftBin = pkgs.callPackage ../lib/swift-bin.nix { };` then `swiftBin { name;
  src; description; }` in the room's `default.nix` (`grep -rln swift-bin.nix
  modules` finds them all). It shells out to `/usr/bin/xcrun swiftc` (Xcode CLT
  + Determinate's relaxed sandbox). `swift-bin` fails on any `xcrun swiftc`
  under `modules/` outside the builder, no allowlist — a helper needing a flag
  or `-framework` grows `swift-bin.nix`. `src` is the ONE `.swift` file, never
  its directory. Two keep a package file: `modules/core/package-hausax.nix`
  (core and theme both build it) and `modules/terminal/zen-tabs/package.nix`.

## Patterns

- **Room A needs a capability room B provides** — pick by whether a substitute
  exists:
  - *Presentation only*: a `haus._contrib.<B>.<feature>` extension point
    (`modules/lib/contrib.nix`). B declares it in its `options.nix`, A writes a
    plain attrset, B renders it inside its own `mkIf config.haus.<B>.enable`
    (`modules/ai/default.nix`, `modules/focus/default.nix`). No room reads
    `config.haus.ai.*` to decide what to draw.
  - *Functional, with a substitute*: detect at RUNTIME and fall back —
    `lanes/lane-open.sh` picks `HAUS_WINDOW_BACKEND=aerospace|ghostty` by
    `command -v aerospace`; `modules/terminal/default.nix` warns, not asserts.
  - *Functional, no substitute*: a build-time `assertions` entry —
    `modules/windows/default.nix`'s `mouseFullscreen` needs
    `haus.launcher.enable`.
- **A step a fresh machine needs a PERSON for** (a TCC grant, a login item, an
  app-private theme) is a card in the manual-click deck:
  `haus._contrib.permissions.<room>-<thing>` in the room that knows why, never a
  line in `haus.sh`. Core renders `share/haus/permissions.json`; `haus
  permissions` walks it, `haus doctor` reports it. Bar's are GENERATED from
  `modules/bar/widgets.nix`'s `permissions` table. **`check` must never prompt**
  (`check = null` when nothing is readable). **`prompt` before `pane`** — panes
  from `modules/lib/settings-panes.nix`, clicks in `steps`. **Gate on the
  symptom, not the platform**: `core-login-items` is gated on
  `_perm_agent_wedged`, not "macOS ≥ 26"; runtime facts go in `applies`, a
  runtime list in `detail`.
- **A room that installs a LAUNCHD JOB** adds
  `haus._contrib.services.<launchd attr name>` beside it, never a line in
  `haus.sh`. Core joins the deck to `config.launchd` and renders
  `share/haus/services.json`; `haus services` draws it, `haus doctor` reports
  what wants attention. The entry carries only `title`, `why`, `cost`, `domain`
  — label, log path and liveness are READ off the plist. Gate it exactly as the
  job is gated (an eval-time assertion otherwise). Keep it greppable:
  `services-deck` reads both sides out of the source, so a job is spelled
  `launchd.user.agents.<name> =` or `launchd.daemons.<name> =` on its own line,
  never inside `// lib.optionalAttrs`.
- **New SketchyBar plugin: a barlib widget.** Contract:
  <https://hausfold.co/docs/haus/rooms/bar-widgets>; design record
  `todo/bar-framework.md` in hausfold/ops (private); the code is normative. One
  file in `modules/bar/sketchybar/plugins/` with a `# widget:` header,
  `fetch()`/`render()`/`on_*()`/`popup_rows()` bodies and a `frameworkBlock`
  entry in `mkPluginBlocks`; `clock.sh` is the smallest reference, `github.sh`
  the largest. `barlib.sh` (`test/barlib.bats`, shellchecked in CI) owns `$SB`
  routing, the `drawing=off`/`updates=on` pairing, tone→hex, the
  one-batched-call rule, the popup grid and its row kinds, and the popup dance
  (`barpop arm &`). Pre-framework plugins convert on touch.
  - **The header is the pill's tick**: `# widget: interval = <seconds>` is where
    `update_freq` comes from and what `intervalOverride` compares
    `haus.bar.widgets.<name>.interval` against; `modules/bar/widgets.nix`'s
    `interval` is only that option's DEFAULT and must agree —
    `bar-widget-intervals` refuses a disagreement, `manifest.nix`'s
    `bar-widget-header` a header the parser can't see. Only battery, wifi,
    volume, elgato, trill and focus have no header. A `style` writing
    `--set update_freq` beside a header interval throws in `frameworkItem`;
    `calendar` is the legal shape (`haus.bar.calendar.refresh` through `style`).
  - **A stranger's widget is the same file**, named in
    `haus.bar.widgets.<name>.script`, installed at
    `~/.config/sketchybar/widgets/<name>.sh`, its look the `style` option; both
    leaves host-only. A field only `mkPluginBlocks` can write is the framework
    closing again.
  - **The colour vocabulary is `modules/bar/tones.nix`** — a widget names a
    tone, never a hex; a new rung is a colour more than one pill already spends
    on one job. `accent` follows `haus.theme.accent` (its enum holds
    `red`/`peach`/`yellow`/`green`), so nothing carrying meaning names it — a
    verb row is `action`. `tone()`/`mark()` are generated into colors.sh
    (`modules/bar/colors-fns.nix`); `bar-tones` pins `test/barlib.bats`'s stub
    exports and `test/colors-fns.sh` against the emitter; `site-data` publishes
    `docs/site-data/bar-tones.json` for the site's `check-bar-tables.mjs`.
- **A plugin that can land on the SECOND bar never writes `sketchybar`.**
  `haus.bar.bottom.enable` runs the same binary as `bar-bottom` (a symlink;
  `$BAR_NAME` is exported TO plugins, never read), and a bare `sketchybar --set`
  always means the top bar. `source ~/.config/sketchybar/bar.sh` and use `"$SB"`,
  which falls back to `BAR_ITEM`/`$NAME` on the hook path. `mkPluginBlocks` takes
  the bar command AND the group; a block hardcoding `right` instead of `${side}`
  piles its pill into the corner.
  - **Anything that pokes or reloads a bar pokes both**, spelled `haus-bar-poke
    <event> [key=value…]` (`modules/core/haus-bar-poke.sh`, on PATH, pinned by
    `test/bar-poke.bats`). Core's, because it reads the roster for the bar's
    binary and exits 0 with no bar. Two triggers are deliberately not this: one
    that only wakes `aerospace_watcher.sh` on the top bar, and a single-pill
    repaint on `$SB`.
  - **Every reload names its rc** (`--reload
    ~/.config/sketchybar/bar-bottomrc`): a bare `sketchybar --reload` replays the
    generation `bar-bottom` BOOTED on. Diagnose with `ps -o command= -p <pid>`
    and `bar-bottom --query bar` against `~/.config/sketchybar/sizes.sh`.
  - Every movable pill comes from one table; the workspace/leader group and the
    tour stay on the menu bar, all `right`. The bottom bar hands out all three
    groups from `haus.bar.bottom.items`, sides in `modules/bar/sides.nix`;
    windows's `outerBottom` carves its room.
- **Any pill that starts `drawing=off` also sets `updates=on`**: both bars'
  `--default` carries `updates=when_shown`, which gates EVENT delivery, so a
  hidden item's own script never runs — and a hand `--update` still reaches it,
  hiding the bug. `media` does; `page` and `bar_position` do in `sketchybarrc`.
- **A new default app pick** goes in `modules/apps`: one
  `haus.apps.<thing>.enable` in its `options.nix` and one roster entry, never a
  bare `home.packages` line. An app a room NEEDS (AeroSpace, SketchyBar,
  espanso) belongs to that room. **It does not claim a file type**:
  `haus.terminal.hijackFileAssociations` is the only list haus binds — two
  haus-owned claims on one UTI re-run every activation and macOS asks forever
  (`.mts` and `.m2ts` share one AVCHD UTI; reconcile by UTI, not spelling). A
  pick that must own a type joins terminal's `editorExts`; a nixpkgs bundle
  needs `lsregister` in the same activation, or a silent `-50`.
- **A pill with a dropdown toggles, then arms `barpop` in the background**:
  `sketchybar --set <item> popup.drawing=toggle; barpop arm <item> &` (the
  `popToggle` helper in `modules/bar/default.nix`; plugin scripts spell
  `/run/current-system/sw/bin/barpop`). A framework widget writes none of it —
  `popup_open`/`popup_toggle` are the runtime's. `barpop`
  (`modules/bar/barpop.swift`, via `swiftBin`) is an AppKit global mouse-down
  monitor, Accessibility-gated for KEY events only so there is no TCC prompt.
  The ordering and the `&` are load-bearing, and so is no Foundation `Process`
  in the binary. The arming gate WAITS for a real answer — `--query <item>`
  returns an EMPTY STRING while a pill rebuilds its rows, so `popupDrawing` is
  `Bool?`, the gate polls up to 600 ms, and the click path and watchdog test
  `== false`.
- **Theme**: `haus.theme.{flavor,contrast}` are the source of truth and
  **`modules/lib/nebelung.nix` is the only place that resolves them** — `root`,
  `palette`, `flavor`. Build paths from `nb.flavor`, never the literal
  `"mocha"`: whiskers names output after the flavor (`catppuccin-latte.conf`,
  `Catppuccin Latte.tmTheme`, `zen/themes/Latte/`), and `catppuccin.flavor` in
  terminal follows it. A wrong path is invisible at eval, so `theme-variants`
  pins the flavor/contrast → variant/subdir table as a golden file (nebelung's
  `variantDir` is the other side). **A path spelled INTO any store output gets
  `modules/lib/checked-ref.nix`** — `guard` for a builder, `collect` for a
  `home.file` source; unchecked, a wrong one is green everywhere and lands a
  dangling symlink in `~`. Raw dotfiles nix can't inject into (ghostty `config`)
  reference the rendered file. Adding a flavor: a nebelung `VARIANTS` entry, an
  enum value in `modules/theme/options.nix`, a `theme-variants` row, `nix flake
  update nebelung`, and `modules/theme/default.nix`'s `appearanceWanted` — an
  unknown flavor silently gets Dark.
- **The chord layer is pounce's, not Ghostty's** (`modules/launcher`'s
  `appHotkeys`, cross-referenced by `modules/terminal/ghostty/config`, taught by
  `modules/terminal/term-bindings.nix`): every terminal chord that runs a
  command — ⌘F, ⌘L, ⌘Y, ⌘N, ⌘↵, ⌘G, ⌘B — is an app-scoped tap entry, unbound in
  Ghostty's config, because none of `ghostty +list-actions`' 85 actions runs a
  command. The three files move together or the cheatsheet lies. **⌘⇧R is bound
  by GHOSTTY** (`reset` is an action), still listed in `term-bindings.nix`, and
  its `chords` entry matters more: `haus.launcher.items` hotkeys are GLOBAL and
  would beat it.
- **Every window is a `zmx` session** (`modules/terminal/scripts/launch.sh`,
  Ghostty's `command`): `zmx history` / `zmx tail` are the read API ⌘F, ⌘L and
  the bar's agent peek need — Ghostty's AppleScript can create a surface but not
  read one. **`zmx ls` / `zmx get` are parsed only through
  `~/.config/haus/term/zmx-rows.sh`**; its header is the spec, and the
  attached-row marker, the 0.7.0 `start_dir` rename and `zmx get` going
  space-separated each broke a hand parse. One byte-pinned exception:
  `raise-session.sh`'s `window=` claim list, which
  `test/raise-session-lane-join.bats` extracts by sed. Sessions are `term.*` —
  `term.<n>`, the lowest n no session holds; a lane is `scruff.<repo>.<lane>`,
  from `lanes/lane-open.sh`. **That prefix is scruff's**: it keys a parked fin as
  `scruff/<repo>/<lane>` (`askKeyPrefix` in `internal/commands/notify.go`) and
  names the marker file after that key with dots, so `lanes/lane-seen.sh` must
  match byte for byte or every fin stays parked, silently. Moving it takes two
  releases: write the new spelling, read both for one, then drop the read arm,
  dated in its comment. `scripts/focused-session.sh` is the one window→session
  join (`lwindow=` for a lane, `window=` for the rest, then the forced title);
  AeroSpace's `on-focus-changed` runs `lanes/lane-seen.sh` over it.
  - **A NEW window is a NEW session; only `scripts/restore-windows.sh`
    reattaches** — one window per `clients=0` session, automatically for the
    FIRST window of a Ghostty (`haus.terminal.restoreWindows`) and on demand from
    the palette. Lanes go through `raise-session.sh`, since only
    `open -na --title` forces the title the AeroSpace join reads; `term.*` spawn
    with `HAUS_ZMX_ATTACH` in the environment. **⌃D ends a shell and frees its
    number, ⌘W parks it for the next start.**
- **The core CLIs** are on PATH via `writeShellScriptBin`, source beside
  `modules/core/default.nix`. `haus.sh` knows nothing of the family repos.
  `haus-activate.sh` is the privileged half — `haus` and `bench` build as you,
  then `sudo haus-activate <system>` sets the profile and runs `darwin-rebuild
  activate`, so root never evaluates twice; its `/run/current-system/sw/bin`
  path is what security's NOPASSWD rule names. `awake.sh` owns the launchd
  caffeinate assertions; the coffee pill is only its controller.
  - **`haus skill` is core's** — A3 of the family agent-surface standard (the
    workshop's `docs/agent-surface.md`). `modules/core/default.nix` imports
    `../ai/agents/skill.nix` as `HAUS_SKILL_DIR`; modules/ai owns whether the
    skill is INSTALLED, core only whether it can be PRINTED. `agents/SKILL.md`
    is a template (`@hausVersion@`), so it is handed in, never looked for beside
    the script. `haus skill install`'s client table is
    `modules/ai/agents/homes.nix` (`agentHomes`), rendered as
    `HAUS_AGENT_SKILL_DIRS` (`claude=.claude/skills:codex=…`), which haus.sh
    parses — no bash copy; off the wrapper it refuses in words.
    `test/agent-surface.bats` asserts it end to end.
  - **The AI room's own**: `statusline.sh` / `statusline-refresh.sh` (the HUD,
    reading `scruff`'s registry), `agent-state` (the one writer behind bar's
    `agents` pill), `scruff-cache` (the one warm `scruff --json`, which dumps
    `lsof -d cwd` machine-wide — too slow inline, so TTL + one-winner lock),
    `haus-vm-shot` (the tart adapter's `screenshot`; stdout is a path for
    `gh … --attach`, no painter) and `haus-fix` (`modules/ai/fix.sh`).
  - `haus-fix` reaches back into core legally: a failed `haus rebuild` writes
    `~/.local/state/haus/last-failure` (`modules/lib/state-files.nix`), offers
    once, and `haus fix` dispatches onto the binary. **Core's whole test is
    `command -v haus-fix`** — never `config.haus.ai.*`, which core may not read.
    The CTA needs `$CONSUMER` to be a git repo; the undo is `git -C
    ~/.config/nix revert HEAD`. `haus.ai.default` and
    `modules/lib/agent-oneshot.nix` are substituted at build; it verifies with
    `nix eval` and never activates.
  - `agent-state` has no source of its own: `modules/ai` `readFile`s
    `modules/bar/sketchybar/plugins/agents-hook.sh`, the script bar installs.
    Every client's hooks call `agent-state <working|waiting|idle|remove>
    <client>`. pi's is an extension terminal writes,
    `~/.pi/agent/extensions/haus-agent-state.ts`
    (`modules/terminal/pi/agent-state.ts`), which also hands `scruff hook notify`
    the Claude-shaped payload and sends its two pi-only events through
    `haus-notify`; its header is the event map.
  - **`haus-secret`** (`modules/secrets`) is the single door to the values rooms
    declared: a room says `haus-secret <NAME>` and never learns the provider;
    `--list` / `--status` / `--check` are the person's half. It never invents a
    `--reason` — secretspec's `require_reason` makes an agent say why.
  - User docs: the [AI room](https://hausfold.co/docs/haus/rooms/ai/) and the
    [haus reference](https://hausfold.co/docs/haus/reference/haus/).
- **New pounce command**: generic ones live in pounce
  (`pkgs/pounce-commands/commands`); layer-specific ones HERE in
  `modules/launcher/commands/`, one self-describing script (`# pounce: key =
  value` header) layered via `pounce-commands.override { extraCommandDirs … }`.
  No registry to edit.
  - A script that lists with `pounce` over stdin gets back `<action>\t<raw-row>`
    (`enter`/`cmd`/`opt`/`ctrl`), so the parse is written once:
    `commands/lib/menu-commit.sh`'s `menu_commit` → `MENU_ACTION`/`MENU_ROW`,
    then `menu_field "$MENU_ROW" <n>`. Source it at
    `$(dirname "$0")/lib/menu-commit.sh`; `test/menu-commit.bats` counts the
    consumers. A `--dial` answer's extra middle field is the caller's
    (`spawn-agent.sh`'s `dial_agent`).
  - `# pounce: whenFile = <path>` hides a row while the file's first line is
    `0`: `pages.sh` on `~/.local/state/haus/any-page`, written by
    `windows/scripts/workspace-mru.sh push` and by `resort-windows.sh`. A file,
    because the registry refresh runs on the ⌘Space keystroke
    (`CommandRegistry.refresh()` in `presentLauncher`) and may not fork; only a
    literal `0` hides. `haus.launcher.items.<key>.workspaces` is the cheaper
    "where are you" (`cmd:lane-here`, the `shell-here` pair). A hidden row still
    needs `# pounce: cheatWhen = …`, ours, read by `riceCommandRows`.
  - A `# pounce:` key the daemon doesn't parse is ignored in silence;
    `pounce-command-keys` diffs every key `./commands` uses against the LOCKED
    pounce's `CommandRegistry.swift` (the bash `pounce-palette` has its own
    parser).
- **The haus tour**: ONE state machine,
  `modules/bar/sketchybar/plugins/tour.sh`, one pill. The leader-mode scripts
  and `aerospace-notify.sh` feed it `tour.sh event <name>` behind
  `[ -f ~/.local/state/haus/tour ]` — one stat when idle; keep it that cheap.
  `haus tour` and the pounce `tour` command are doors. Gated by
  `haus.tour.enable` via the generated `tour_item.sh` / `tour_config.sh`.
