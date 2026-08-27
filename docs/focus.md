# The focus room — how it flips a real macOS Focus

`haus.focus.*`. One quiet switch that silences notifications through **real
macOS Focus** — so it syncs to your iPhone — sets your Slack status, and can be
generalised into named scenes that a condition enters for you.

Everything routes through one CLI engine, so the bar, the palette and the
terminal can never disagree about what a toggle does:

```
focus  (on / off / toggle / status / scene / auto / doctor)
├── bar pill          moon icon, accent-filled when quiet, click = toggle
├── pounce command    "Toggle Focus" in the palette, plus one row per scene
└── hooks             slack (built in) + host-provided scripts, run with "on"/"off"
```

## Flipping Focus without a public API

Apple ships no public API or CLI for this — every open-source "focus CLI" is a
wrapper around a Shortcuts shortcut. haus takes the declarative route instead:

1. **Declare the hotkey.** nix-darwin writes AppleSymbolicHotKeys entry **175**
   ("Turn Do Not Disturb On/Off") as an obscure chord no human types, and core's
   end-of-activation `activateSettings -u` applies it without a logout. The
   binding *is* Nix config.
2. **pounce presses it.** `pounce focus toggle` posts the CGEvent. **No new TCC
   grant** — the stable-signing machinery in `modules/launcher` exists precisely
   so pounce's Accessibility grant survives rebuilds, and focus rides it.
3. **The engine shells out to pounce** for the flip and runs the hooks.

Requires `launcher.enable`. Why a real Focus rather than faked notification
silence: **Share Across Devices** means the iPhone goes quiet too, and the
"allowed to break through" list is the user's own Focus config. focus flips the
switch; it doesn't reinvent the switchboard.

Rejected, with reasons that still hold: private XPC to `donotdisturbd` (no
maintained implementation to crib from, private-API churn means
re-reverse-engineering per macOS major); UI-scripting Control Center (breaks
every release); legacy `defaults` hacks (dead since Monterey's Focus rewrite).

**Hotkey 175 reaches classic DND only** — named Focus modes have no symbolic
hotkey. `mechanism = "shortcut"` (a pre-signed `.shortcut`, one "Add Shortcut"
click) is the opt-in that covers them.

## Keeping the pill truthful

Hotkey 175 is a blind toggle, and the user can also flip Focus from Control
Center or their phone — so **reading** state matters more here, not less.

pounce reads `~/Library/DoNotDisturb/DB/Assertions.json`. That needs **Full Disk
Access**, and pounce's stable signing identity means the grant survives
rebuilds — the same trick as Accessibility. So pounce is the one TCC-privileged
agent: it can both flip DND and report it (`pounce focus status`), which makes
`focus on`/`off` deterministic (read, then toggle only if needed) rather than
blind.

A `WatchPaths` launchd agent on the DB dir fires `sketchybar --trigger
focus_change`, so the pill syncs instantly even when the toggle came from the
phone. The engine fires the same trigger after acting, so the pill never waits
for a poll when *we* changed the state.

Without FDA the engine falls back to its own state file, which drifts on any
external toggle. `focus doctor` says so; it is a degraded mode, not the design.

## The Slack leg

macOS Focus already suppresses Slack banners *on the Mac*. The API leg is what
Focus can't do: tell your **teammates** and silence your **phone**.

- `users.profile.set` → status text + emoji (+ `status_expiration`)
- `dnd.setSnooze` / `dnd.endSnooze` → pauses Slack push on all devices
- Scopes: `users.profile:write`, `dnd:write`, on a personal user token

## Scenes

`haus.focus.scenes.<name>` is the same machinery with the member list opened
up — `dnd`, `preventSleep`, `audio.input`, `apps.open`, `hooks`,
`restorePreviousState`. Entered with `focus scene <name>`, left with `focus
scene off`. **One at a time.**

Five rules that are load-bearing:

1. **`quiet` is reserved, not declarable.** It is what `focus on`, the pill and
   the palette already enter, and its state is read from the OS rather than from
   a state file. A host-declared `scenes.quiet` would be a second thing with
   that name that the pill could never reach. The module asserts on it.
2. **A scene is data, read at runtime** (`focus-scenes.json`), never a generated
   shell fragment. Every field would otherwise be a place where a desktop's
   string becomes code, and a desktop is a file whose whole promise is that it
   holds none.
3. **A scene reverses the levers it TOOK, not the ones it declares.** What it
   took is written to `scene-prev.json` on entry, so leaving a scene the host
   has since deleted from the table still puts DND and the input device back —
   a rebuild between entering and leaving is an ordinary afternoon.
   `restorePreviousState = false` makes leaving end quiet-off even when you were
   quiet before.
4. **`focus off` and `focus toggle` release an active scene.** Both are what the
   pill and the palette call, and a pill that un-quiets while a caffeinate hold
   and a switched microphone stay behind is lying about what it just did.
5. **Honest scope, stated in the option descriptions too.** Exiting a scene
   never closes the apps it opened; `audio.input` needs `SwitchAudioSource`
   (pulled in only when some scene names a device, since macOS ships no CLI for
   it); a `preventSleep` assertion is a `caffeinate` process, so its pid file is
   checked against the running process before anything is signalled.

## Triggers

`haus.focus.scenes.<name>.when` is a set of CONDITIONS — a daily window,
weekdays, a Wi-Fi SSID, the power source, how many displays are attached —
**ANDed** together. `focus auto` is one launchd tick asking each scene whether
its condition holds. The agent exists only on a machine where some scene
declared one; `haus.focus.triggers.interval` (default 30 s) is how often.

**The whole feature rests on one promise: the daemon never overrides a state you
chose.** A background process that moves your Mac around is only tolerable if it
loses every argument. Three mechanics carry it:

1. **Entry is edge-triggered, not level-triggered.** A scene is entered on the
   tick where its condition turns true, never because it is still true. Level
   triggering is unusable: leave an auto-entered scene at 09:10 and it comes
   back at 09:10:30, forever.
2. **It enters only from a neutral Mac** — no scene on, not quiet. A scene you
   entered by hand and a quiet you switched on are both opinions. The edge is
   spent either way, so it doesn't pounce half an hour later when you go
   neutral.
3. **It leaves only what it entered**, tracked as `owner` in
   `~/.local/state/focus/auto.json`. The moment what's active isn't the owner,
   the daemon has nothing to reverse and forgets it.

And five smaller ones:

4. **The conditions live ON the scene**, not in a `triggers.<name>` table — a
   second place a scene name is written is a place the two can disagree. It is
   also why `triggers` has no `enable`: declaring a condition *is* the request
   for the thing that checks it.
5. **`when.displays` is a COUNT, not a display's name.** Which panel is on your
   desk is a fact about one machine (the reason `haus.displays.<uuid>` is
   host-only), while "two or more screens" is a shape any desktop can share. So
   `displays` is desktop-safe and `wifi` is not — an SSID names one router in
   one building. That asymmetry is why a docked trigger is publishable.
6. **Two conditions rising in one tick resolve by name**, lexicographically
   first. Any rule is arbitrary; this one is deterministic, printable and stable
   across rebuilds, and `focus auto --probe` shows which scenes hold so the
   loser is visible rather than mysterious.
7. **Ownership is a name AND the entry counter it was entered under.** On the
   name alone, leaving and re-entering the same scene between two ticks is
   invisible, and the daemon would evict a scene you had just chosen.
8. **`RunAtLoad = false`.** A tick can `open -a` an app and talk to System
   Events, both of which park at cold boot before the Aqua session is up.
   Waiting one interval costs at most 30 s after login and loses nothing: the
   first tick after a fresh state file treats whatever holds as an edge.

### The probes have three answers, not two

Each probe answers `""` for **"I could not tell"**, and that is a third answer,
not a no. `scene_matches` returns *holds* / *definitely does not* / *cannot
say* — entering needs the first, leaving needs the second.

This matters because `networksetup` reports no network during sleep/wake, AP
roaming and VPN reconnects, and `CGGetActiveDisplayList` under-counts while
monitors re-negotiate — all things launchd's `StartInterval` lands directly on
top of. With two answers, one blank read leaves the scene and the next re-enters
it: hooks off then on, the caffeinate hold dropped and retaken, DND and the
Slack status flipped twice.

## What focus honestly won't do

- **No declarative Focus allowlists.** Which apps and people break through lives
  in `~/Library/DoNotDisturb/DB/ModeConfigurations.json`, which is
  CloudKit-synced and unsupported to write. Curate it once in System Settings;
  focus only flips the switch.
- **Named Focus modes need the shortcut fallback.** The declarative hotkey
  reaches classic DND only.
- **One one-time TCC checkbox.** Full Disk Access for pounce can't be granted
  programmatically. `focus doctor` and the bootstrap interview walk it; the
  stable-signing trick makes it stick forever after.
- **No Slack app provisioning.** Token creation is a one-time documented
  walkthrough.

## Not built

- **Timed focus** — `focus 25` writes an until-timestamp; the poll auto-offs
  past expiry and the pill label shows minutes remaining. The palette grows
  "Focus 25m / 60m" rows.
- **A leader chord for focus.** A scene already gets a generated palette row and
  a cheatsheet line; what is missing is a *key*, and a
  `haus.keys.leaderExtras` chord is still hand-written by the host.
