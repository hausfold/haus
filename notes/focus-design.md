# focus — Focus/DND as a room (design brainstorm)

> Status: v1 implemented — see `modules/focus` (+ the bar pill, pounce
> command, and `haus.focus.*` options). This note is kept for the
> rationale and the v2 backlog. One toggle in the bar + palette that
> silences notifications (real macOS Focus, so it syncs to your iPhone) and
> sets your Slack status. Declarative where macOS allows; honest where it
> doesn't.
>
> ★ **v2's first piece shipped 2026-08-16: `haus.focus.scenes`** — quiet
> generalised into named states (`focus scene recording`), with quiet itself as
> the built-in one. The trigger half is deliberately still unbuilt; see "Scenes"
> below.
>
> ⚠️ **This note did not know that was coming, and that is worth a line.** The
> plan of record for it lived in the *workshop's* `notes/options-roadmap.md`
> §5.8, one repo over, from that file's first commit on 2026-07-25 until today —
> three weeks — while the "v2 candidates" list below,
> the file sitting next to the code, named two other things and not this one.
> Two plans for one room in two repos is exactly the drift §5.14 of that file
> describes (*the work happens in four repos and the doc lives in a fifth*), and
> a reader here would have concluded scenes were nobody's idea. When a roadmap
> item names a room, the room's own note is where it has to be written down.

## Shape

`modules/focus/` becomes the seventh room. Like the other rooms it is one
concern with several surfaces, all driven by a single engine:

```
focus (CLI engine, ~/.local/bin)      the state machine: on / off / toggle / status / doctor
├── bar pill                        bell icon, accent-filled when quiet, click = toggle
├── pounce command                   "Toggle Focus" in the palette
└── hooks                            slack (built in) + host-provided scripts, run with "on"/"off"
```

Everything calls the same `focus` script, so the bar, the palette, and the
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
   keycode), enabled. core's end-of-activation
   `/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u`
   (run once for every preference the rice writes, focus's included)
   makes it apply without logout. This is the "declarative Focus which
   Apple buries in Settings" promise made literal — the binding IS nix
   config.
2. **pounce presses it.** A small pounce feature (lives in the pounce
   repo: `pounce focus toggle`, or a generic `pounce hotkey <chord>`)
   posts the CGEvent. TCC is already solved: the whole stable-signing
   machinery in `modules/launcher` exists precisely so pounce's
   Accessibility grant survives rebuilds. focus rides it — no new grant.
3. `focus` (the CLI engine) shells out to pounce for the flip and runs the
   hooks. Everything else is unchanged.

Requires `launcher.enable` — acceptable coupling: the palette is on by
default, and focus without pounce can fall back to the signed-shortcut
path (or just be off).

Why real Focus instead of faking notification silence: **Share Across
Devices** means the iPhone goes quiet too, and the "allowed to break through"
list is the user's own Focus config — focus flips the switch, it doesn't
reinvent the switchboard.

### DND-only: the honest limitation

Hotkey 175 toggles the built-in Do Not Disturb, period — named Focus
modes have no symbolic hotkey. If a custom Focus named "Focus" with its own
allowlist matters, that's what the signed-shortcut fallback is for
(`focus.mechanism = "shortcut"`). Default stays the hotkey: zero setup
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
   (`pounce focus status`), making `focus on`/`off` deterministic
   (read, then toggle only if needed) instead of blind. **Chosen.**
   A `WatchPaths` launchd agent on the DB dir fires
   `sketchybar --trigger focus_change` for instant sync even when the
   toggle came from the phone.
2. focus's own state file only — zero TCC but drifts on any external
   toggle, and turns on/off into guesses. Degraded mode when FDA hasn't
   been granted yet (`focus doctor` says so); not the design target.
3. Poll `shortcuts run` "Get Current Focus" — exact and TCC-free, but
   reintroduces the Shortcuts dependency this revision removes. Only
   relevant under `mechanism = "shortcut"`.

Instant feedback on our own toggles regardless: the engine fires
`sketchybar --trigger focus_change` after acting, so the pill never waits
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
(`security find-generic-password -s focus-slack -w`). Same spirit as the
harvest pill's secrets file, but command-shaped so nothing secret ever
touches disk in plaintext.

Slack is implemented as the first built-in **hook** — the extension point
is generic:

```
haus.focus.hooks = [ ./my-focus-hooks/onair-light.sh ];
# each script is called with "on" or "off"
```

Hook ideas that stay host-side (not shipped): pause Music, turn an Elgato
light red, start a Harvest "deep work" timer, shove distracting apps to a
parking workspace via aerospace.

## Options sketch

```nix
haus.focus = {
  enable = true;                      # room flag, default on like windows/bar/pounce
  mechanism = "hotkey";               # "hotkey" (declarative, DND, via pounce) |
                                      # "shortcut" (signed .shortcut, named Focus)
  focus = "Do Not Disturb";           # only meaningful under mechanism = "shortcut"
  slack = {
    enable = false;                   # off by default: needs a token
    tokenCommand = "";                # e.g. "security find-generic-password -s focus-slack -w"
    status = { text = "heads down"; emoji = ":no_bell:"; };
    snooze = true;                    # also dnd.setSnooze while quiet
  };
  hooks = [ ];                        # extra scripts, called with "on"/"off"
};
```

## Surfaces, concretely

- **CLI**: `focus` via `pkgs.writeShellApplication` into home packages.
  Subcommands `on|off|toggle|status|doctor`. `doctor` checks the hotkey is
  registered, pounce's Accessibility + Full Disk Access grants are live,
  the Slack token resolves — and prints the one-time step for whatever is
  missing (under `mechanism = "shortcut"`, it checks `shortcuts list`
  instead).
- **bar**: `modules/bar/sketchybar/plugins/focus.sh` following the elgato
  pattern (icon 󰂚 / 󰂛, `background.color=$ACCENT` when quiet,
  `label.drawing=off`), subscribed to `mouse.clicked` + custom event
  `focus_change`, `update_freq=30`. Emitted into the bar only when
  `focus.enable` — but unlike elgato/harvest it is *not* behind
  `bar.plugins`, because it targets no personal hardware/service. If the
  Shortcuts are missing, a click surfaces "run `focus doctor`" as a
  notification instead of failing silently.
- **pounce**: `modules/launcher/commands/focus.sh` with the usual
  `# pounce:` header ("Toggle Focus", icon `moon.fill`), filtered out of
  `riceCommands` when the room is off.

## Scenes — shipped 2026-08-16

`focus` was always a scene with one member: it has hooks, an external
integration, a bar pill, a CLI and transient state. `haus.focus.scenes.<name>`
is the same machinery with the member list opened up — `dnd`, `preventSleep`,
`audio.input`, `apps.open`, `hooks`, `restorePreviousState` — entered with
`focus scene <name>` and left with `focus scene off`. One at a time.

Four decisions worth keeping, because each had a plausible other answer:

1. **Scenes live INSIDE the focus room, not in a `haus.scenes` room of their
   own.** The roadmap sketched the second shape and it stopped being available
   on 2026-08-16, when every room was renamed for what it does and `hush`
   became **`focus`**: a `scenes` room beside a `focus` room would be two rooms
   for one job, and the sketch's own fix for that — demote `focus.*` to an alias
   — would retire a room name on the day it was given. Apple's word for a
   named machine state is *Focus*, so the room was already called the right
   thing.
2. **`quiet` is reserved rather than declared.** It is what `focus on`, the
   pill and the palette command already enter, and its state is read from the
   OS, not from a state file. A host-declared `scenes.quiet` would be a second
   thing with that name that no surface but the CLI could reach, so the module
   asserts on it.
3. **A scene is data, read at runtime** (`focus-scenes.json`), not a generated
   shell fragment. Every field would otherwise be a place where a desktop's
   string becomes code, and a desktop is a file whose whole promise is that it
   holds none.
4. **No trigger engine, on purpose.** Wi-Fi SSID, time of day, power source and
   display-attach are all real triggers and all need a daemon; the declarative
   half costs one option and one subcommand. Build the daemon after one
   hand-written scene has proved useful — which is why this repo ships the
   mechanism and no desktop ships a scene.

And two the assurance pass pulled out of the first draft, both about the same
mistake — **reading the exit off the scene table**, which is a file that can
change while a scene is running:

5. **A scene reverses the levers it TOOK, not the ones it declares**, and what
   it took is written to `scene-prev.json` on entry. Two consequences, one of
   which was a bug: entering a quiet scene while already quiet takes nothing,
   so the Slack leg doesn't re-stash your (already-quiet) status as the one to
   restore later — and leaving a scene the host has since deleted from the
   table still puts DND and the input device back, because nothing on the exit
   path asks the table anything. That second case is a rebuild between entering
   and leaving, which is an ordinary afternoon here.
   `restorePreviousState` keeps exactly one job under that rule: `false` makes
   leaving end quiet-off even when you were quiet before.
6. **`focus off` and `focus toggle` release an active scene.** Both are what the
   bar pill and the palette command call, and a pill that un-quiets while a
   caffeinate hold and a switched microphone stay behind is a pill lying about
   what it just did — the failure mode this room's whole state-reading design
   exists to avoid, arriving through the one door nobody had shut.

Honest scope, all of it in the option descriptions too: exiting a scene never
closes the apps it opened; `audio.input` needs `SwitchAudioSource` (pulled in
only when some scene names a device, since macOS ships no CLI for it); and a
`preventSleep` assertion is a `caffeinate` process, so its pid file is checked
against the running process before anything is signalled.

## v2 candidates (explicitly not v1)

- **Triggers for scenes**: Pounce command, time, Wi-Fi SSID, power source,
  display attach. The daemon half of the item above.
- **Timed focus**: `focus 25` writes an until-timestamp to
  `~/.local/state/focus/`; the poll auto-offs past expiry and the pill label
  shows minutes remaining. Palette grows "Focus 25m / 60m" commands.
- A windows leader/binding for focus. (A scene needs one more than quiet does —
  quiet has a pill and a palette row; a scene has neither, and today it is
  reachable only from a terminal or a `haus.keys.leaderExtras` chord the host
  writes.)

## What focus honestly won't do

- **No declarative Focus allowlists.** Which apps/people break through
  lives in `~/Library/DoNotDisturb/DB/ModeConfigurations.json`, which is
  CloudKit-synced and unsupported to write. Curate it once in System
  Settings; focus only flips the switch. (Scope-honesty in the option
  description, same voice as `theme.accent`.)
- **Named Focus modes need the fallback.** The declarative hotkey only
  reaches classic DND; `mechanism = "shortcut"` (pre-signed file, one
  "Add Shortcut" click) covers named Focus for those who want it.
- **One one-time TCC checkbox.** Full Disk Access for pounce (state
  reading) can't be granted programmatically — `focus doctor` and the
  bootstrap interview walk it, and the stable-signing trick makes it
  stick forever after.
- **No Slack app provisioning.** Token creation is a documented one-time
  walkthrough (workshop repo).

## Cross-repo work

The keystroke/state capability lives in the **pounce repo**
(`~/code/workshop/pounce`): a `pounce focus toggle|status` subcommand (or
a generic `pounce hotkey` + `pounce read-file`?  no — keep it
purpose-named, small surface) posting the CGEvent and reading
Assertions.json. This repo wires it: the hotkey defaults write, the focus
engine, the pill, the palette command. Docs land in the workshop repo
(`web/src/content/docs/`): the FDA checkbox, optional named-Focus setup,
the Slack app + Keychain steps.

## Open decisions

1. Chord choice for hotkey 175 — something no keyboard layout or app will
   ever collide with (⌃⌥⇧⌘ + a high function-key code).
2. Should `slack.snooze` and status be independently toggleable, or is one
   `slack.enable` enough for v1? (leaning: one flag, both on.)
3. Pill position on the right side (next to wifi? next to media?).
4. Is a timed focus wanted badly enough to pull into v1?
5. Ship the signed-shortcut fallback in v1, or hotkey-only first and add
   named-Focus support when someone actually asks?
