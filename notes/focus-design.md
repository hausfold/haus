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
> the built-in one.
>
> ★ **And its second on 2026-08-20: `scenes.<name>.when`** — the trigger half,
> which every version of this note called "explicitly not v1" until the thing it
> was waiting for happened (a scene proved useful). See "Triggers" below; the
> one sentence that matters is that the daemon **never overrides a state you
> chose**, and the three mechanics that make that true are what the section is
> about.
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
├── bar pill                        moon icon, accent-filled when quiet, click = toggle
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
`tokenCommand` option the host sets. SINCE the secrets room grew a deck, the
default is to set nothing — the room declares SLACK_USER_TOKEN, `haus-secret
--check` asks for it once, and `tokenCommand` is only for fetching the value
some other way. Same spirit as the harvest pill's secrets file, but nothing
secret ever touches disk in plaintext.

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
    tokenCommand = "";                # empty = haus holds it (haus-secret --check)
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
  pattern (icon 󰽥 / 󰖔, `background.color=$ACCENT` when quiet,
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
   thing with that name — one the pill could never reach, and whose generated
   `Scene: quiet` palette row (since 2026-08-16 a scene gets one) would
   silently enter built-in quiet instead, since `focus scene quiet` is an
   alias of `focus on`. So the module asserts on it.
3. **A scene is data, read at runtime** (`focus-scenes.json`), not a generated
   shell fragment. Every field would otherwise be a place where a desktop's
   string becomes code, and a desktop is a file whose whole promise is that it
   holds none.
4. **No trigger engine, on purpose.** Wi-Fi SSID, time of day, power source and
   display-attach are all real triggers and all need a daemon; the declarative
   half costs one option and one subcommand. Build the daemon after one
   hand-written scene has proved useful — which is why this repo ships the
   mechanism and no desktop ships a scene.
   → ✅ **Its condition was met and the daemon shipped 2026-08-20** (Triggers,
   below). Worth keeping as written rather than rewriting: the precondition did
   its job. Four days of a scene with no way to enter it but a CLI is what
   turned up the reachability gap (the palette row, haus#381) and
   `apps.closeOnExit` (haus#408) — two things a trigger daemon built in the same
   week would have hidden, because nothing fires a trigger by hand often enough
   to notice that leaving a scene left OBS running.

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

## Triggers — shipped 2026-08-20

`haus.focus.scenes.<name>.when` is a set of CONDITIONS — a daily window, a set
of weekdays, a Wi-Fi SSID, the power source, how many displays are attached —
ANDed together, and `focus auto` is one launchd tick that asks each scene
whether its condition holds. The agent exists only on a machine where some
scene declared one; `haus.focus.triggers.interval` (default 30s) is how often.

The whole feature rests on one promise — **the daemon never overrides a state
you chose** — because a background process that moves your Mac around is only
tolerable if it loses every argument. Three mechanics carry it, and each had a
plausible other answer:

1. **Entry is edge-triggered, not level-triggered.** A scene is entered on the
   tick where its condition turns true, never because it is still true. Level
   triggering is the obvious implementation and it is unusable: leave an
   auto-entered scene at 09:10 and it comes back at 09:10:30, forever, with no
   way to say no short of editing your config. Edge triggering makes "I left
   this" a state the daemon can represent without storing an override list.
2. **It enters only from a neutral Mac** — no scene on, not quiet. A scene you
   entered by hand and a quiet you switched on are both opinions. The edge is
   spent either way, so it does not pounce the moment you go neutral half an
   hour later; that would be the same surprise arriving late.
3. **It leaves only what it entered**, tracked as `owner` in
   `~/.local/state/focus/auto.json`. This is the scene engine's own "reverse
   only the levers you pulled" rule, one level up: the moment what's active
   isn't the owner, the daemon has nothing to reverse and forgets it.

Five smaller decisions, same treatment:

4. **The conditions live ON the scene, not in a `haus.focus.triggers.<name>`
   table of their own.** A trigger table would be a second place a scene name
   is written, and the two could disagree — a trigger for a scene that no
   longer exists is a thing the module system would have to check for. `when`
   beside `dnd` and `apps.open` reads as what it is: another thing the scene
   knows about itself. It is also why `triggers` has no `enable`; declaring a
   condition IS the request for the thing that checks it, and a flag beside the
   data is a switch that can contradict it.
5. **`when.displays` is a COUNT, not a display's name.** Which panel is on your
   desk is a fact about one machine — the reason `haus.displays.<uuid>` is
   host-only — while "two or more screens" is a shape any desktop can share. So
   `displays` is desktop-safe and `wifi` is not: an SSID names one router in one
   building. That asymmetry is the whole reason a docked trigger is publishable.
6. **Two conditions rising in one tick resolve by name**, lexicographically
   first. Any rule here is arbitrary; this one is at least deterministic,
   printable and stable across rebuilds, and `focus auto --probe` shows which
   scenes hold so the loser is visible rather than mysterious.
7. **Ownership is a name AND the entry it was entered under.** A counter bumps
   on every entry, by hand or by the daemon, and the daemon remembers the value
   it entered at. On the name alone, leaving and re-entering the same scene
   between two ticks is invisible — and the daemon would then evict a scene YOU
   had just chosen, breaking the one promise the feature makes, in a window
   exactly one interval wide.
8. **`RunAtLoad = false`.** A tick can enter a scene, and entering one can
   `open -a` an app and talk to System Events — both of which park at cold boot
   before the Aqua session is up (`modules/lib/gui-wait.nix`). Waiting one
   interval costs at most 30 seconds after login and needs none of that
   machinery, and it loses nothing: the first tick after a fresh state file
   treats whatever holds as an edge, so logging in at 09:30 inside a 09:00
   window still lands in the scene.

### What the probes can and can't do

Each probe answers `""` for "I could not tell", and **that is a third answer,
not a no** — `scene_matches` returns *holds* / *definitely does not* / *cannot
say*, entering needs the first and leaving needs the second. The two-answer
version was written first and the assurance pass killed it: it is conservative
only on the entering side, and maximally aggressive on the other. `networksetup`
reports no network during sleep/wake, AP roaming and VPN reconnects, and
CGGetActiveDisplayList under-counts while monitors re-negotiate — all of which
launchd's `StartInterval` lands directly on top of. One blank read would have
left the scene and the next one re-entered it: hooks off then on, the caffeinate
hold dropped and retaken, DND and the Slack status flipped twice, and with
`apps.closeOnExit` **the scene's apps quit and relaunched** — OBS, mid-recording,
on this room's own example scene. A tick that cannot tell changes nothing, and
does not even record a transition, because writing "false" for an unknown would
manufacture a rising edge on the way back.

| Fact | Read by | Honest scope |
|---|---|---|
| clock, weekday | `date` | exact |
| power source | `pmset -g batt` | exact |
| Wi-Fi SSID | `networksetup -getairportnetwork <dev>`, device looked up rather than assumed | **macOS can refuse it** (Location Services), and it refuses by saying you are not associated — indistinguishable from being on no network |
| display count | `hausdisp list` when the displays room is on, else `system_profiler SPDisplaysDataType` | **not the same count.** The helper reports `CGGetActiveDisplayList`, which drops a sleeping panel; the fallback counts what the GPU driver knows about, which on a clamshell-docked laptop usually still includes the built-in one. So `displays = 2` can read 1 with the displays room and 2 without it on the same Mac. The fallback is also slow enough to notice, which is what `triggers.interval` says to raise the interval for |

`focus auto --probe` prints all four and what each scene's condition makes of
them, and `focus doctor` calls out an SSID that reads empty. Both exist for the
same reason: **"no match" and "no answer" look identical from the outside**, and
a trigger that silently never fires is the failure mode this room already has a
rule about.

Two things that follow from the probes rather than from the design, and are the
ones to check on a real Mac: the SSID read is the one macOS is entitled to
refuse, and the `system_profiler` shape is a JSON parse of a report Apple owns.
`test/focus-auto.sh` stubs all four — it proves the DECISIONS, and says nothing
about the READS.

## v2 candidates (explicitly not v1)

- ~~**Triggers for scenes**~~ — shipped 2026-08-20, above. What is still not
  built is the one trigger in the original list that isn't a condition: a
  **Pounce command** as a trigger. It never belonged with the other four — a
  palette row that enters a scene already exists (the launcher generates one per
  scene), so "trigger" there just means "a person pressed something".
- **Timed focus**: `focus 25` writes an until-timestamp to
  `~/.local/state/focus/`; the poll auto-offs past expiry and the pill label
  shows minutes remaining. Palette grows "Focus 25m / 60m" commands.
- A windows leader/binding for focus. (Narrowed 2026-08-16: a scene now has a
  generated palette row and a cheatsheet line — the launcher builds both from
  `haus.focus.scenes` — so what remains of this bullet is a *key*: a
  `haus.keys.leaderExtras` chord is still hand-written by the host.)

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
