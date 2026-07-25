# CLAUDE.md

**nebelhaus** — an opinionated macOS rice as composable nix-darwin modules. This
repo is the "distro": a personal machine consumes it via `mkNebelhaus` and adds
only its own host (identity, private apps, secrets).

## Am I in the right repo? (routing)

**This repo (`~/code/nebelhaus/nebelhaus`) owns THE RICE** — the generic, no-identity
system + shell modules. Personal machine config and the pounce/theme sources live
elsewhere.

| Want to change… | Repo |
|---|---|
| the rice: macOS defaults, tiling (prowl), bar (sill), shell (hearth), security (collar), secrets plumbing (secrets), pounce wiring (pounce), Messages install (trill), Focus/DND (hush), wallpaper/accent (theme) | `~/code/nebelhaus/nebelhaus` ← **you are here** |
| the pounce palette app or its command scripts | `~/code/nebelhaus/pounce` |
| colors / the theme palette | `~/code/nebelhaus/nebelung` |
| one machine's personal apps / identity / secrets | `~/.config/nix` (or that machine's own config) |
| user-facing docs / guides (nebelhaus.com) | `~/code/nebelhaus/workshop` (`web/`, Astro Starlight) |

> **Docs live downstream.** The how-to guides users read are the Astro site in
> the `workshop` repo (`web/src/content/docs/`), served at nebelhaus.com. When a
> change here alters user-facing behavior (a new option, a changed keybinding, a
> workflow), update the matching guide there too, or it silently drifts.

> **Claude: enforce this.** If a request targets a different repo than the one
> whose files you're in, STOP and say so before editing — e.g. "That's a color
> change; the palette lives in `~/code/nebelhaus/nebelung`. Want me to switch?"
> Never hardcode a user's identity here — it's a `nebelhaus.*` option the host sets.

## Architecture

```
flake.nix                 # mkNebelhaus builder + darwinModules outputs + example host
modules/
  default.nix             # imports all rooms
  options.nix             # all host-set knobs: git.*, theme.{accent,wallpaper}, hearth.*,
                          #   claude.globalMd, apps.* (the shared roster), prowl.*, sill.*, pounce.*,
                          #   hush.*, trill.enable, tour.enable, homebrew.*, secrets.provider
  lib/gui-wait.nix        # withGUIWait: cold-boot-safe GUI agent launch wrapper
  den/                    # system: macOS defaults, Homebrew framework, core CLI, GC
                          #   + on-PATH CLIs: haus / awake / wt / zscratch / statusline
  theme/                  # desktop wallpaper + accent-derived bold wordmark
  hearth/                 # shell: zsh, starship, git, yazi, zellij, ghostty + theming
  prowl/                  # AeroSpace tiling
  sill/                   # SketchyBar
  collar/                 # Touch ID sudo
  pounce/                 # the palette daemon (launchd + self-signing)
  trill/                  # the trill Messages client, installed via the trill flake input
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
The workshop's `bench try` (from `~/code/nebelhaus`) builds the consumer against
this **local checkout** — uncommitted edits included — so nothing needs pushing
to test. Once committed, `bench ship` pushes and ripples the downstream lock
updates; hand-rolled alternative: push here, then `nix flake update nebelhaus`
in the consumer. CI evaluates the example host on every push.

When you open the PR for a `worktree-*` branch, give it a **What / Why / Verify / Watch-out**
body (see the workshop ship skill's Step 3) — the session that wrote the code is gone by the
time the change is feel-tested, so a bug found later has to be recoverable from `gh pr view`
alone, and the **Verify** block is exactly what the workshop's `bench try-batch` checklist
points back to when it feels several PRs together.

## Rules

- **Never hardcode identity.** Anything personal (git name/email/signing key, the
  pounce signing cert) is a `nebelhaus.*` option set by the host — see `options.nix`.
- A **dynamic attr key** (`${username}`) can't be defined across multiple statements —
  set `home-manager.users.${username}` once per module. Pass it as a module *function*
  (`{ lib, pkgs, ... }: {...}`) when you need home-manager's `lib.hm`.
- `nixfmt` formats `.nix` files.

## Gotchas

- **launchd GUI race**: GUI agents (AeroSpace, SketchyBar, pounce) launched at cold
  boot before the Aqua session is ready park with exit 78 (EX_CONFIG) and wedge.
  `withGUIWait` (`modules/lib/gui-wait.nix`) polls for Dock/Finder/SystemUIServer and
  runs from `/bin/bash` (boot volume, not the /nix APFS volume that isn't mounted yet).
  Don't "simplify" it away. Recover a wedged agent: `launchctl bootout` then `bootstrap`.
- **pounce self-signing** (`modules/pounce`): macOS keys an Accessibility (TCC) grant
  to a code-signing identity, but a store build is adhoc-signed (cdhash changes every
  rebuild). When `nebelhaus.pounce.signingIdentity` is set, the daemon wrapper copies
  `Pounce.app` to `~/.local/state/pounce` and re-signs it with a stable identity so the
  grant survives rebuilds. Don't repoint the agent at the store path. One-time on a new
  machine: `pounce --request-accessibility`, approve the prompt (and the keychain
  "Always Allow" dialog the first time `codesign` runs).
- **Homebrew tap-trust** (`modules/den`): `HOMEBREW_NO_REQUIRE_TAP_TRUST=1` via
  `/etc/homebrew/brew.env` — third-party taps fail trust checks under sudo activation.
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
  macOS build sandbox relaxed (Determinate's default). See the pounce repo.

## Patterns

- **New SketchyBar plugin**: add `modules/sill/sketchybar/plugins/<name>.sh`, wire it
  into `modules/sill/sketchybar/sketchybarrc`. Follow an existing plugin.
- **Theme**: `catppuccin.flavor` (in `hearth`) is the single source of truth; the
  Nebelung palette is injected from the `nebelung` input. Raw dotfiles nix can't inject
  into (ghostty `config`, zellij `config.kdl`) name the flavor manually — keep in sync.
- **Iterating on a zellij edit** (config.kdl / a layout / a freshly-built
  plugin `.wasm`): don't `bench try switch` + restart `main` just to feel a
  keybind or colour — that nukes every tab. Use **`zscratch`** (`modules/den`):
  it renders your candidate over a copy of the live `~/.config/zellij` into a
  temp `--config-dir` and boots a throwaway session in its own Ghostty window,
  so the working multiplexer is untouched. `zscratch --config FILE` /
  `--layout FILE` / `--theme FILE` / `--plugin tab-bar=WASM`; `zscratch clean`
  reaps it. The final real activation still needs `bench try switch` — but you
  do it once, already knowing it works. A brand-new session name = a new zellij
  *server*, which recompiles plugin wasm from disk (a running server caches it
  in memory for its lifetime).
- **The den CLIs** (`modules/den`, each on `PATH` via `writeShellScriptBin`, source
  beside `default.nix`): the rice ships five dev/user CLIs — **`haus.sh`** (the
  end-user machine driver: rebuild/update/rollback/doctor/status — knows nothing of
  the family repos), **`awake.sh`** (launchd-owned timed/indefinite macOS
  caffeinate assertions; Sill's optional coffee pill is only its controller),
  **`wt.sh`** (Claude Code agent worktrees for *any* repo; the
  `WorktreeCreate`/`WorktreeRemove` hooks call it — `wt` lists, `wt <name>` resumes,
  `wt reap` sweeps landed ones, `wt child <repo>` makes a cross-repo child worktree),
  **`zscratch.sh`** (above), and **`statusline.sh`** / `statusline-refresh.sh` (the
  agent HUD, reading `wt`'s registry). They're plain bash embedded via
  `builtins.readFile`, so a rebuild re-installs them on `PATH`. `haus` and the
  workshop's `bench` are named apart on purpose so they never shadow each other —
  `haus` = your machine, `bench` = the family repos, `wt`/`zscratch` = dev tools the
  rice puts on `PATH` regardless. (User-facing docs: the [wt guide](https://nebelhaus.com/guides/claude-agents/)
  and [haus reference](https://nebelhaus.com/reference/haus/) on nebelhaus.com.)
- **New pounce command**: generic ones live in the
  [pounce repo](https://github.com/nebelhaus/pounce) (`pkgs/pounce-commands/commands`);
  rice/machine-specific ones live HERE in `modules/pounce/commands/` — one
  self-describing script each (metadata in a `# pounce: key = value` header),
  layered onto the palette via `pounce-commands.override { extraCommandDirs … }`.
  No registry to edit in either repo; drop the script and rebuild.
- **The haus tour** (first-run tutor): ONE state machine,
  `modules/sill/sketchybar/plugins/tour.sh`, drives a single bar pill. The
  leader-mode scripts + `aerospace-notify.sh` feed it `tour.sh event <name>`
  behind a `[ -f ~/.local/state/nebelhaus/tour ]` guard — one stat when idle;
  keep it that cheap. `haus tour` and the pounce `tour` command are just doors
  into it. Gated by `nebelhaus.tour.enable` via the generated
  `tour_item.sh` / `tour_config.sh` (see `modules/sill/default.nix`).
```
