# AGENTS.md

**nebelhaus** — an opinionated macOS rice, built on `haus`, a set of composable
nix-darwin modules. This repo is the "distro": a personal machine consumes it
via `mkNebelhaus` and adds only its own host (identity, private apps, secrets).

> **This repo holds two things, and only one of them is nebelhaus.** **`haus`**
> is the **layer** — the nix-darwin modules, the `haus.*` options and the `haus`
> CLI — and it is what *any* rice builds on, not just this one. **nebelhaus** is
> one rice on that layer: the default *values* those modules ship with
> (nebelung's fog-grey, prowl/sill/hearth turned on the way this desktop likes
> them), the first rice and the developer-focused one. **hausfold** is neither —
> it is the org, the maker and the seller, which is why the repo is
> `hausfold/haus`: the layer names the repo, the org names the owner. That is
> **decision 8** in the workshop's `notes/hausfold-rename.md` (2026-08-10),
> applied to the slug by **decision 9** (2026-08-11) — this repo was
> `hausfold/hausfold` until then, and every old URL still redirects.
>
> Today the two are interleaved in the same files, because the plan's decision 4
> renames first and neutralizes the defaults later (its §7). So the distinction
> is a **writing** rule right now, not a directory boundary: when you touch a
> module, know whether you're changing what every rice gets or only what this
> one looks like, and say which in the commit. The rice's own name never moves —
> §6, and `flake.nix`'s description with it.

> 🚨 **The option namespace is `haus.*`.** Declare every new option under
> `haus.`, in one of the files `modules/options-modules.nix` lists — that list
> is the single source (`modules/default.nix` imports it; don't write the paths
> out again). `nebelhaus.*` still works for CONSUMERS: `modules/renamed.nix`
> generates one `lib.mkRenamedOptionModule` per leaf, so a host or a
> third-party rice on the old spelling keeps evaluating, with a warning. It is
> not a second namespace to add to — a declaration under `nebelhaus.` would
> collide with its own alias.
>
> **Three things stay `nebelhaus`, and they are not drift**: the rice, the
> flake outputs, and the flake input. *(This said "the repo" until 2026-08-10.
> The repo left the name at the 2026-08-09 org migration and is `hausfold/haus`
> since 2026-08-11 — and none of the three examples below was ever a repo
> name.)*
> `nebelhaus.presets.everyday`,
> `nebelhaus.lib.checkRice` and `inputs.nebelhaus.url` are all correct as
> written — flake outputs and an input name, not options. Same for
> `org.nebelhaus.*` launchd labels, `share/nebelhaus/`, the state dirs
> (`~/.local/state/nebelhaus`, `~/.config/nebelhaus/`) and nebelhaus.com
> links; each has its own phase in workshop `notes/hausfold-rename.md`, none
> of them is this one.
>
> The agent skill **used to be on that list and no longer is.** It installs as
> `haus/` inside each client's skills directory (`~/.claude/skills/`,
> `~/.codex/skills/`, `~/.config/opencode/skills/`) and its frontmatter `name:`
> is `haus`, so a `skills/nebelhaus` path anywhere is drift now, not a
> deliberate hold-out.

**This file is the one set of instructions, for every agent.** Claude Code,
Codex, OpenCode, Cursor, Copilot — TUI or GUI — all read *this*, directly or
through a one-line pointer. Nothing harness-specific belongs here; when a flow
needs per-client wiring (a hook, a slash command), the wiring lives in that
client's own file and the *content* stays here or in `.agents/`. The map of
which tool reads which file is [`.agents/README.md`](./.agents/README.md).
(That's the rule for this repo's *own* files. The rice also **ships** agent
config to end users — `haus.agents.instructions`, `haus.agents.skill`, the
`hearth/agents` skill — and that's a product surface, not this layer. It obeys
the same rule one layer out: one body, written once per client at the path that
client reads. Both options were `haus.claude.*` until 2026-08-11, when they
stopped writing Claude's copy alone.)

## Am I in the right repo? (routing)

**This repo (`~/code/workshop/hausfold`) owns THE LAYER AND THE RICE** — `haus`,
the generic, no-identity system + shell modules, and nebelhaus's default values
on top of them. Personal machine config and the pounce/theme sources live
elsewhere.

| Want to change… | Repo |
|---|---|
| the rice: macOS defaults, tiling (prowl), bar (sill), shell (hearth), security (collar), secrets plumbing (secrets), pounce wiring (pounce), notch shelf install (perch), Focus/DND (hush), accent + Light/Dark (theme), the generated desktop (wallpaper), the apps every machine gets + what opens which file type (apps) | `~/code/workshop/hausfold` ← **you are here** |
| the pounce palette app or its command scripts | `~/code/workshop/pounce` |
| colors / the theme palette | `~/code/workshop/nebelung` |
| one machine's personal apps / identity / secrets | `~/.config/nix` (or that machine's own config) |
| user-facing docs / guides (nebelhaus.com) | `~/code/workshop` (`web/`, Astro Starlight) |

> **Docs live downstream.** The how-to guides users read are the Astro site in
> the `workshop` repo (`web/src/content/docs/`), served at nebelhaus.com. When a
> change here alters user-facing behavior (a new option, a changed keybinding, a
> workflow), update the matching guide there too, or it silently drifts.

> **Whatever agent you are, enforce this.** If a request targets a different repo
> than the one whose files you're in, STOP and say so before editing — e.g.
> "That's a color change; the palette lives in `~/code/workshop/nebelung`. Want
> me to switch?" Never hardcode a user's identity here — it's a `haus.*`
> option the host sets.

## Architecture

```
flake.nix                 # mkNebelhaus builder + darwinModules outputs + example host
modules/
  default.nix             # imports all rooms
  options.nix             # all host-set knobs: git.*, theme.accent, wallpaper.*, hearth.*,
                          #   roster (the shared app list), prowl.*, sill.*, pounce.*,
                          #   hush.*, perch.*, tour.enable, homebrew.*, secrets.provider
  options-modules.nix     # the per-room options.nix list — shared by both renderers below
  options-groups.nix      # the ROOM REGISTRY: every public namespace and darwinModules
                          #   export, its owning room, and whether desktop data may set
                          #   each leaf. `room-registry` fails on anything unmapped
  moved.nix               # aliases for options that changed ADDRESS inside haus.* (the
                          #   claude room → agents; developer.agents.enable → agents.enable).
                          #   renamed.nix next door is the generated nebelhaus.* → haus.*
                          #   set; don't grow that one
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
  apps/                   # the EDITORIAL picks: apps the rice chooses for a finished
                          #   machine (IINA today) + the file types they claim. Roster
                          #   entries, so a cask of the same app still collides loudly
  ai/                     # the AI room: haus.agents.* + the coding-agent capability.
                          #   Pure wiring — its assertions, and what it CONTRIBUTES to
                          #   the terminal, the bar and the launcher through the
                          #   extension points those rooms declare (lib/contrib.nix).
                          #   Its payload is still installed by den (system) and hearth
                          #   (home), gated on haus.agents.enable
  den/                    # system: macOS defaults, Homebrew framework, core CLI, GC
                          #   + on-PATH CLIs: haus / awake / zscratch / statusline
  displays/               # haus.displays: scaled resolution by intent + the
                          #   hausdisp helper (Swift, xcrun-compiled like pounce's)
  theme/                  # the accent, the flavour, macOS Light/Dark
  wallpaper/              # haus.wallpaper.*: the desktop. `minimal` is GENERATED —
                          #   package.nix renders it (resvg for the vector layer,
                          #   ImageMagick for the 16-bit field), looks/ holds the
                          #   hand-made Nebelung PNGs
  hearth/                 # shell: zsh, starship, git, yazi, zellij, ghostty + theming
                          #   + floatring (Swift, xcrun-compiled): the outline every
                          #   window float-term.sh spawns wears (haus.hearth.floatBorder)
    agents/               # the nebelhaus agent skill (haus.agents.skill): hand-written
                          #   SKILL.md + recipes, plus an option reference rendered
                          #   per-revision — see skill.nix for why it's a package. ONE
                          #   skill, installed into every client in haus.agents.clients
                          #   (hearth's agentHomes has the paths; was hearth/claude/ and
                          #   Claude-only until 2026-08-11). Also ships the consumer
                          #   starter pair (consumer-AGENTS.md + its consumer-CLAUDE.md
                          #   pointer) `haus doctor` offers to copy
  prowl/                  # AeroSpace tiling
  sill/                   # SketchyBar + sillpop (Swift, xcrun-compiled): the pill
                          #   dropdowns' click-outside dismissal
  collar/                 # auth policy: Touch ID sudo + passwordless activation
  pounce/                 # the palette daemon (launchd + self-signing)
  perch/                  # the perch notch file shelf, installed via the perch flake input
  hush/                   # Focus/DND one-switch: declarative hotkey 175 + Slack + hooks
  secrets/                # secretspec: declarative secrets, provider chosen per host
hosts/example/            # the template a consumer copies
```

Each `modules/<room>` is a nix-darwin module; ones that need home config write into
`home-manager.users.${username}`. `den` and `hearth` split system vs shell; Homebrew
is contributed per-room (den owns the framework, prowl/sill add their own cask/brew).

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
updates; hand-rolled alternative: push here, then `nix flake update nebelhaus`
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
`reference/options.md` or the guides in the workshop's `web/src/content/docs/`; a new
keybind colliding across zellij / AeroSpace (prowl) / pounce / macOS symbolic hotkeys —
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
  exports `.wrap` (wrap an executable — prowl, sill) and `.script` (the snippet alone
  — pounce, which re-signs before exec'ing). Don't "simplify" it away, and **keep the
  60 s deadline**: the polls answer "is the session up *yet*", and unbounded they
  can't tell a cold boot from a GUI process that is simply absent, so a KeepAlive
  restart parks the agent forever with a live pid and nothing in the log. (That is
  why `den` leaves Finder's `QuitMenuItem` off.) Recover a wedged agent: `launchctl
  bootout` then `bootstrap`.
- **pounce self-signing** (`modules/pounce`): macOS keys an Accessibility (TCC) grant
  to a code-signing identity, but a store build is adhoc-signed (cdhash changes every
  rebuild). When `haus.pounce.signingIdentity` is set, the daemon wrapper copies
  `Pounce.app` to `~/.local/state/pounce` and re-signs it with a stable identity so the
  grant survives rebuilds. Don't repoint the agent at the store path. One-time on a new
  machine: `pounce --request-accessibility`, approve the prompt (and the keychain
  "Always Allow" dialog the first time `codesign` runs).
- **Homebrew tap-trust** (`modules/den`): `HOMEBREW_NO_REQUIRE_TAP_TRUST=1` via
  `/etc/homebrew/brew.env` — third-party taps fail trust checks under sudo activation.
  That file is also the only place a `HOMEBREW_*` setting reaches the *rebuild's*
  `brew bundle` (activation runs it under a `sudo … env …` that resets everything
  else), so the API-refresh window and the env-hint silencing live there too — an
  export in hearth or bench only ever reaches your interactive shell.
- **Touch ID + zellij** (`modules/collar`): `reattach = true` is required because sudo
  runs inside zellij; without pam_reattach the Touch ID prompt beachballs.
- **secretspec + keychain ACLs** (`modules/secrets`): with the default "keyring"
  provider, macOS keys each item's "Always Allow" to the exact binary — a rebuild that
  changes secretspec's store path re-prompts once per secret. Harmless (approve again);
  cloud providers (gcsm/awssm/bws/…) have no per-item ACL. Login-keychain items do NOT
  sync via iCloud — a clean wipe means `secretspec check` + re-entering values.
- **Determinate owns the nix daemon** (`modules/den`): `nix.enable = false`; config
  lives in `/etc/nix/nix.custom.conf`. GC is our own weekly launchd job.
- **The pounce build shells out to `/usr/bin/xcrun swiftc`** — needs Xcode CLT + the
  macOS build sandbox relaxed (Determinate's default). See the pounce repo. So do the
  rice's own four one-file Swift helpers, for the same reason (compiling a Swift
  toolchain from source to build a few hundred lines against AppKit costs hours):
  `hausax` (den), `hausdisp` (displays), `sillpop` (sill), `floatring` (hearth).

## Patterns

- **New SketchyBar plugin**: add `modules/sill/sketchybar/plugins/<name>.sh`, wire it
  into `modules/sill/sketchybar/sketchybarrc`. Follow an existing plugin.
- **A plugin that can end up on the SECOND bar must never write `sketchybar`.**
  `haus.sill.bottom.enable` draws a second bar along the bottom of the screen,
  and SketchyBar has no two-bars-in-one-process mode: an instance is named
  `basename(argv[0])` and keys BOTH its lock file and its mach service on that
  name, so the bottom bar is the same binary under a second name (`sill-bottom`,
  a symlink — `BAR_NAME` is exported TO plugins, never read, so setting it on the
  way in does nothing). The consequence is that a bare `sketchybar --set` in a
  plugin ALWAYS means the top bar: same syntax, no error, and a pill that moved
  down just silently stops updating. So `source ~/.config/sketchybar/bar.sh` and
  use `"$SB"` — it routes on `$BAR_NAME`, falling back to `SILL_ITEM`/`$NAME` for
  the HOOK path (agents-hook.sh, the statusline's usage push), which has no bar
  and so no `$BAR_NAME`. Same rule in Nix: `mkPluginBlocks` takes the bar command
  AND the group as its two arguments — a block that hardcodes `right` rather than
  writing `${side}` still evaluates, still builds, and quietly piles its pill back
  into the corner, so thread both through — and **anything that pokes or reloads
  a bar pokes both**, whether it sits outside sill (den's `awake` and its
  `caffeinate_change`, the `Reload SketchyBar` palette command) or inside it
  (the logo pill's own `Reload SketchyBar` row — which now runs the palette's
  `reload-bar.sh` rather than carrying a second copy of it — and the
  `.haus-stamp` onChange that
  reloads on rebuild). A bare `sketchybar --reload` reaches one mach service and
  leaves the other bar a generation behind, silently — this list has gained a
  member every time that was forgotten. And **every reload names its rc**
  (`--reload ~/.config/sketchybar/sill-bottomrc`), which is a second, separate
  trap: `--reload` with no path re-runs the config path the instance resolved AT
  STARTUP, and SketchyBar resolves it through the symlink to `/nix/store`, so a
  bar launched with `--config` replays the generation it BOOTED on — every
  reload, exit 0, `configuration loaded..` in the log. That is `sill-bottom` and
  only `sill-bottom` (the menu bar carries no `--config`, so it re-resolves the
  live path by accident), and it cost a day of hausfold#279's `topmost=window`
  never reaching the screen. Which bar is exposed is `ps -o command= -p <pid>` —
  a `--config` in the argv is the whole risk, and `lsof -p <pid> -a -d cwd`
  showing `/nix/store` says the same thing (SketchyBar chdir'd to the resolved
  rc). Neither tells you whether it's *currently* stale, because both stay true
  after a correct reload; for that, read the bar against the generation —
  `sill-bottom --query bar` vs `~/.config/sketchybar/sizes.sh`. Every
  movable pill is emitted from that one table; the coupled left-side
  workspace/leader group and the tour stay on the menu bar. On the MENU bar those
  pills are all `right` (its left and center are spoken for); the bottom bar
  hands out all three of SketchyBar's groups from `haus.sill.bottom.items`, whose
  sides list lives in `modules/sill/sides.nix` — imported by both `options.nix`
  and `default.nix` so the enum and the emission can't disagree.
  macOS reserves the top strip of a display and
  reserves NOTHING at the bottom, so prowl's `outerBottom` carves the room instead.
- **A new default app pick** (an app the rice thinks a finished machine has, not one a
  room needs to do its job): it goes in `modules/apps` — one
  `haus.apps.<thing>.enable` knob in its `options.nix`, one roster entry (never a
  bare `home.packages` line), and if it should own file types, `duti` pins in the same
  activation that `lsregister`s the bundle — binding a type LaunchServices hasn't seen
  yet is a silent `-50`. An app a room NEEDS (AeroSpace, SketchyBar, espanso) still
  belongs to that room.
- **A pill with a dropdown toggles it as usual, then arms `sillpop` in the
  background** — `sketchybar --set <item> popup.drawing=toggle; sillpop arm
  <item> &` (the `popToggle` helper in `modules/sill/default.nix` writes exactly
  that; plugin scripts spell it out with the literal
  `/run/current-system/sw/bin/sillpop`). SketchyBar hears clicks on its own items
  and nothing else, so a popup it opened could otherwise only be closed by
  clicking that pill again, while every other dropdown on the Mac closes on a
  click anywhere. `sillpop` (`modules/sill/sillpop.swift`, built by
  `sillpop.nix`) is the missing half: it holds an AppKit global mouse-down monitor
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
- **Theme**: `haus.theme.{flavor,contrast}` are the single source of truth, and
  **`modules/lib/nebelung.nix` is the only place that resolves them.** It returns the
  themes-package `root` to source rendered files from, the `palette` (name → hex),
  and the `flavor` — which is load-bearing, not decoration: whiskers names its output
  after the flavor it rendered (`catppuccin-latte.conf`, `Catppuccin Latte.tmTheme`,
  `zen/themes/Latte/`), so paths are built from `nb.flavor`, never the literal
  `"mocha"`. hearth, sill and theme all import it; `catppuccin.flavor` in hearth
  follows it. Getting a path wrong here is INVISIBLE at eval (it's just a store path
  that doesn't exist), which is why `nix flake check`'s `theme-variants` pins the
  flavor/contrast → variant/subdir table as a golden file — and why the same rule
  lives in exactly one place on each side of the repo boundary (nebelung's
  `variantDir`, this file). Raw dotfiles nix can't inject into (ghostty `config`,
  zellij `config.kdl`) reference the *rendered file*, not the flavor, so they need
  no per-flavor edit.
  - Adding a flavor means: a nebelung `VARIANTS` entry, one enum value in
    `modules/theme/options.nix`, one row in the `theme-variants` golden table, and a
    `nix flake update nebelung`. Nothing else *for colour* — that's the point of the
    factoring. One non-colour line does want you: `modules/theme/default.nix`'s
    `appearanceWanted` maps flavor → macOS Light/Dark for
    `theme.systemAppearance = "flavor"`, and a flavor it doesn't know silently gets
    Dark. That's a polarity question rather than a palette one, which is why it isn't
    in `modules/lib/nebelung.nix` with the rest — but it is the one place the list
    above doesn't cover.
- **Iterating on a zellij edit** — two cases, and only one of them costs you
  anything.
  - **config.kdl (keybinds, theme, options) hot-reloads. Just
    `bench try switch`.** zellij watches the active config and applies most
    fields to the *running* server in about a second; your tabs, panes and live
    Claude sessions stay exactly where they are. This works because hearth
    installs `~/.config/zellij/config.kdl` as a real file with a live mtime
    (`home.activation.zellijLiveConfig`) instead of a home-manager symlink —
    every `/nix/store` file carries mtime = epoch 1, so a symlinked config makes
    every rebuild look *older* than what zellij already parsed and nothing
    reloads. That one stat is why a rebuild used to mean
    `zellij delete-all-sessions`; don't reintroduce a `home.file` entry for this
    path. (There is no reload chord any more — `Super r` and the `zreload`
    command are gone.)
  - **Plugin `.wasm`, a patched zellij binary, and layout changes to tabs that
    already exist do NOT hot-reload** — a running server caches plugin wasm in
    memory for its lifetime. That's what **`zscratch`** (`modules/den`) is for:
    it renders your candidate over a copy of the live `~/.config/zellij` into a
    temp `--config-dir` and boots a throwaway session in its own Ghostty window,
    so the working multiplexer is untouched. `zscratch --config FILE` /
    `--layout FILE` / `--theme FILE` / `--plugin tab-bar=WASM` / `--bin
    /path/to/zellij`; `zscratch clean` reaps it. A brand-new session name = a new
    zellij *server*, which recompiles plugin wasm from disk. Feel it there, then
    `bench try switch` once, already knowing it works.
- **The four zellij plugin forks** (`modules/hearth/zellij/{tab-bar,status-bar,
  link-handler,tab-history}`) are Rust → wasm32-wasip1, and hearth builds them
  **from source** on every rebuild (`zellijPlugins`, via `pkgsCross.wasi32`) —
  there is no checked-in `.wasm` to re-vendor, so editing `src/` is the whole
  job. Each dir's `build.sh` is only the dev shortcut: it prints a candidate
  `.wasm` path to feed `zscratch --plugin <name>="$(./build.sh)"`.
- **The den CLIs** (`modules/den`, each on `PATH` via `writeShellScriptBin`, source
  beside `default.nix`): the rice ships six dev/user CLIs — **`haus.sh`** (the
  end-user machine driver: rebuild/update/rollback/doctor/status — knows nothing of
  the family repos), **`haus-activate.sh`** (the privileged half of a rebuild:
  `haus` and `bench` build as YOU, then hand the built store path to
  `sudo haus-activate <system>`, which sets the system profile and runs that
  system's own `darwin-rebuild activate`. It exists so root never evaluates the
  config a SECOND time — `darwin-rebuild switch --flake` builds again, against
  root's separate caches under `/var/root/.cache/nix`, costing ~3 s after a host
  edit and ~15 s whenever a flake input moved. Its stable
  `/run/current-system/sw/bin` path is load-bearing: collar's NOPASSWD rule must
  name a literal path), **`awake.sh`** (launchd-owned timed/indefinite macOS
  caffeinate assertions; Sill's optional coffee pill is only its controller),
  **`zscratch.sh`** (above), **`statusline.sh`** / `statusline-refresh.sh` (the
  agent HUD, reading `holt`'s registry), and **`agent-state`** — the one writer of
  agent-pane state behind sill's paw pill and the zellij tab badge. That last one
  has no source file of its own here: den `readFile`s
  `modules/sill/sketchybar/plugins/agents-hook.sh`, the same script sill installs
  into the bar's plugin dir, so the PATH copy and the bar copy can never drift.
  Every client's hooks call it (`agent-state <working|waiting|idle|remove>
  <client>`) — which is why the wirings hearth writes for opencode and codex never
  need to know where a bar keeps its plugins. They're plain bash embedded via
  `builtins.readFile`, so a rebuild re-installs them on `PATH`. Agent worktrees
  themselves are **`holt`** — [its own repo](https://github.com/hausfold/holt),
  taken as a flake input rather than a den-sourced script, ejected from the
  incubator 2026-08-03 with all 79 acceptance tests green. It replaces the old
  bash `wt.sh`, which has been retired entirely — its registry format, hooks,
  and every caller (Claude Code's `WorktreeCreate`/`WorktreeRemove`, pounce's
  Spawn Agent, `bench status`) now point at `holt` alone; there is no fallback
  to roll back to. `haus` and the workshop's `bench` are named apart on purpose
  so they never shadow each other — `haus` = your machine, `bench` = the family
  repos, `holt`/`zscratch` = dev tools the rice puts on `PATH` regardless.
  (User-facing docs: the [agent worktree guide](https://nebelhaus.com/guides/claude-agents/)
  and [haus reference](https://nebelhaus.com/reference/haus/) on nebelhaus.com.)
- **New pounce command**: generic ones live in the
  [pounce repo](https://github.com/hausfold/pounce) (`pkgs/pounce-commands/commands`);
  rice/machine-specific ones live HERE in `modules/pounce/commands/` — one
  self-describing script each (metadata in a `# pounce: key = value` header),
  layered onto the palette via `pounce-commands.override { extraCommandDirs … }`.
  No registry to edit in either repo; drop the script and rebuild.
- **The haus tour** (first-run tutor): ONE state machine,
  `modules/sill/sketchybar/plugins/tour.sh`, drives a single bar pill. The
  leader-mode scripts + `aerospace-notify.sh` feed it `tour.sh event <name>`
  behind a `[ -f ~/.local/state/nebelhaus/tour ]` guard — one stat when idle;
  keep it that cheap. `haus tour` and the pounce `tour` command are just doors
  into it. Gated by `haus.tour.enable` via the generated
  `tour_item.sh` / `tour_config.sh` (see `modules/sill/default.nix`).
