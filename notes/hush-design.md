# hush — Focus/DND as a room (design brainstorm)

> Status: v1 implemented — see `modules/hush` (+ the sill pill, pounce
> command, and `nebelhaus.hush.*` options). This note is kept for the
> rationale and the v2 backlog. One toggle in the bar + palette that
> silences notifications (real macOS Focus, so it syncs to your iPhone) and
> sets your Slack status. Declarative where macOS allows; honest where it
> doesn't.

## Shape

`modules/hush/` becomes the seventh room. Like the other rooms it is one
concern with several surfaces, all driven by a single engine:

```
hush (CLI engine, ~/.local/bin)      the state machine: on / off / toggle / status / doctor
├── sill pill                        bell icon, accent-filled when hushed, click = toggle
├── pounce command                   "Toggle Hush" in the palette
└── hooks                            slack (built in) + host-provided scripts, run with "on"/"off"
```

Everything calls the same `hush` script, so the bar, the palette, and the
terminal can never disagree about what a toggle does.

## The hard part: flipping Focus programmatically

Apple ships no public API or CLI to set a Focus — every open-source
"focus CLI" surveyed (arodik/macos-focus-mode, focus-time-app, …) turns
out to be a wrapper around a Shortcuts shortcut. The realistic mechanisms:

| Mechanism | Verdict |
|---|---|
| Symbolic hotkey 175 ("Turn Do Not Disturb On/Off") written declaratively to `com.apple.symbolichotkeys`, keystroke synthesized by **pounce** | **Chosen.** Zero Shortcuts, zero manual UI setup. nix-darwin writes the hotkey (applied via `activateSettings -u`); pounce — already stable-signed with an Accessibility grant for auto-paste — posts the CGEvent. Reaches classic DND only, not named Focus modes. |
| `shortcuts run <name>` against a "Set Focus" Shortcut | Apple-supported and reaches *named* Focus modes, but the Shortcut can't be created declaratively. Softened variant: ship a pre-signed `.shortcut` in the repo (`shortcuts sign --mode anyone`, Apple-notarized), bootstrap `open`s it, user clicks "Add Shortcut" once — no UI authoring, but still a manual click and a Shortcuts runtime dependency. **Fallback / named-Focus opt-in only.** |
| Private XPC to `donotdisturbd` from pounce (Swift) | Technically possible — pounce is unsandboxed and self-signed — and the only path to *set* named Focus without Shortcuts. But no maintained open-source implementation exists to crib from, and private API churn means re-reverse-engineering per macOS major. Rejected: the rice shouldn't own that treadmill. |
| UI-scripting Control Center via System Events | Breaks every macOS release. No. |
| Legacy `defaults`/NotificationCenter hacks, dead third-party CLIs | Dead since Monterey's Focus rewrite. No. |

### The chosen path, concretely

1. **Declare the hotkey.** nix-darwin writes AppleSymbolicHotKeys entry
   **175** = an obscure chord no human types (e.g. ⌃⌥⇧⌘-F19-region
   keycode), enabled. An activation step runs
   `/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u`
   so it applies without logout. This is the "declarative Focus which
   Apple buries in Settings" promise made literal — the binding IS nix
   config.
2. **pounce presses it.** A small pounce feature (lives in the pounce
   repo: `pounce focus toggle`, or a generic `pounce hotkey <chord>`)
   posts the CGEvent. TCC is already solved: the whole stable-signing
   machinery in `modules/pounce` exists precisely so pounce's
   Accessibility grant survives rebuilds. hush rides it — no new grant.
3. `hush` (the CLI engine) shells out to pounce for the flip and runs the
   hooks. Everything else is unchanged.

Requires `pounce.enable` — acceptable coupling: the palette is on by
default, and hush without pounce can fall back to the signed-shortcut
path (or just be off).

Why real Focus instead of faking notification silence: **Share Across
Devices** means the iPhone hushes too, and the "allowed to break through"
list is the user's own Focus config — hush flips the switch, it doesn't
reinvent the switchboard.

### DND-only: the honest limitation

Hotkey 175 toggles the built-in Do Not Disturb, period — named Focus
modes have no symbolic hotkey. If a "Hush" custom Focus with its own
allowlist matters, that's what the signed-shortcut fallback is for
(`hush.mechanism = "shortcut"`). Default stays the hotkey: zero setup
beats a custom allowlist for most.

## Detecting state (keeping the pill truthful)

Hotkey 175 is a blind toggle, and the user can also flip Focus from
Control Center or their phone — so state reading matters more in this
design, not less:

1. **pounce reads `~/Library/DoNotDisturb/DB/Assertions.json`.** The file
   needs **Full Disk Access**, but pounce's stable signing identity means
   an FDA grant survives rebuilds — the exact trick already used for
   Accessibility. One more one-time checkbox alongside
   `--request-accessibility`, and pounce becomes the rice's single
   TCC-privileged agent: it can both flip DND *and* report it
   (`pounce focus status`), making `hush on`/`off` deterministic
   (read, then toggle only if needed) instead of blind. **Chosen.**
   A `WatchPaths` launchd agent on the DB dir fires
   `sketchybar --trigger hush_change` for instant sync even when the
   toggle came from the phone.
2. hush's own state file only — zero TCC but drifts on any external
   toggle, and turns on/off into guesses. Degraded mode when FDA hasn't
   been granted yet (`hush doctor` says so); not the design target.
3. Poll `shortcuts run` "Get Current Focus" — exact and TCC-free, but
   reintroduces the Shortcuts dependency this revision removes. Only
   relevant under `mechanism = "shortcut"`.

Instant feedback on our own toggles regardless: the engine fires
`sketchybar --trigger hush_change` after acting, so the pill never waits
for the poll when *we* changed the state.

## The Slack leg

macOS Focus already suppresses Slack banners *on the Mac*. The API leg is
what Focus can't do: tell your **teammates** and silence your **phone**.

- `users.profile.set` → status text + emoji (+ `status_expiration`)
- `dnd.setSnooze` / `dnd.endSnooze` → pauses Slack push on all devices
- Scopes: `users.profile:write`, `dnd:write` on a personal user token
  (one-time: create a tiny personal Slack app, install to workspace)

The token is identity, so per the house rule it never enters the rice: a
`tokenCommand` option the host sets, Keychain-first
(`security find-generic-password -s hush-slack -w`). Same spirit as the
harvest pill's secrets file, but command-shaped so nothing secret ever
touches disk in plaintext.

Slack is implemented as the first built-in **hook** — the extension point
is generic:

```
nebelhaus.hush.hooks = [ ./my-hush-hooks/onair-light.sh ];
# each script is called with "on" or "off"
```

Hook ideas that stay host-side (not shipped): pause Music, turn an Elgato
light red, start a Harvest "deep work" timer, shove distracting apps to a
parking workspace via aerospace.

## Options sketch

```nix
nebelhaus.hush = {
  enable = true;                      # room flag, default on like prowl/sill/pounce
  mechanism = "hotkey";               # "hotkey" (declarative, DND, via pounce) |
                                      # "shortcut" (signed .shortcut, named Focus)
  focus = "Do Not Disturb";           # only meaningful under mechanism = "shortcut"
  slack = {
    enable = false;                   # off by default: needs a token
    tokenCommand = "";                # e.g. "security find-generic-password -s hush-slack -w"
    status = { text = "heads down"; emoji = ":no_bell:"; };
    snooze = true;                    # also dnd.setSnooze while hushed
  };
  hooks = [ ];                        # extra scripts, called with "on"/"off"
};
```

## Surfaces, concretely

- **CLI**: `hush` via `pkgs.writeShellApplication` into home packages.
  Subcommands `on|off|toggle|status|doctor`. `doctor` checks the hotkey is
  registered, pounce's Accessibility + Full Disk Access grants are live,
  the Slack token resolves — and prints the one-time step for whatever is
  missing (under `mechanism = "shortcut"`, it checks `shortcuts list`
  instead).
- **sill**: `modules/sill/sketchybar/plugins/hush.sh` following the elgato
  pattern (icon 󰂚 / 󰂛, `background.color=$ACCENT` when hushed,
  `label.drawing=off`), subscribed to `mouse.clicked` + custom event
  `hush_change`, `update_freq=30`. Emitted into the bar only when
  `hush.enable` — but unlike elgato/harvest it is *not* behind
  `sill.plugins`, because it targets no personal hardware/service. If the
  Shortcuts are missing, a click surfaces "run `hush doctor`" as a
  notification instead of failing silently.
- **pounce**: `modules/pounce/commands/hush.sh` with the usual
  `# pounce:` header ("Toggle Hush", icon `moon.fill`), filtered out of
  `riceCommands` when the room is off.

## v2 candidates (explicitly not v1)

- **Timed hush**: `hush 25` writes an until-timestamp to
  `~/.local/state/hush/`; the poll auto-offs past expiry and the pill label
  shows minutes remaining. Palette grows "Hush 25m / 60m" commands.
- A prowl leader/binding for hush.

## What hush honestly won't do

- **No declarative Focus allowlists.** Which apps/people break through
  lives in `~/Library/DoNotDisturb/DB/ModeConfigurations.json`, which is
  CloudKit-synced and unsupported to write. Curate it once in System
  Settings; hush only flips the switch. (Scope-honesty in the option
  description, same voice as `theme.accent`.)
- **Named Focus modes need the fallback.** The declarative hotkey only
  reaches classic DND; `mechanism = "shortcut"` (pre-signed file, one
  "Add Shortcut" click) covers named Focus for those who want it.
- **One one-time TCC checkbox.** Full Disk Access for pounce (state
  reading) can't be granted programmatically — `hush doctor` and the
  bootstrap interview walk it, and the stable-signing trick makes it
  stick forever after.
- **No Slack app provisioning.** Token creation is a documented one-time
  walkthrough (workshop repo).

## Cross-repo work

The keystroke/state capability lives in the **pounce repo**
(`~/code/workshop/pounce`): a `pounce focus toggle|status` subcommand (or
a generic `pounce hotkey` + `pounce read-file`?  no — keep it
purpose-named, small surface) posting the CGEvent and reading
Assertions.json. This repo wires it: the hotkey defaults write, the hush
engine, the pill, the palette command. Docs land in the workshop repo
(`web/src/content/docs/`): the FDA checkbox, optional named-Focus setup,
the Slack app + Keychain steps.

## Open decisions

1. Chord choice for hotkey 175 — something no keyboard layout or app will
   ever collide with (⌃⌥⇧⌘ + a high function-key code).
2. Should `slack.snooze` and status be independently toggleable, or is one
   `slack.enable` enough for v1? (leaning: one flag, both on.)
3. Pill position on the right side (next to wifi? next to media?).
4. Is a timed hush wanted badly enough to pull into v1?
5. Ship the signed-shortcut fallback in v1, or hotkey-only first and add
   named-Focus support when someone actually asks?
