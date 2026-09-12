# The focus room — how it flips a real macOS Focus

`haus.focus.*`. The user-facing half — the switch, the Slack setup, scenes and
their `when` conditions — is
[hausfold.co/docs/haus/rooms/focus](https://hausfold.co/docs/haus/rooms/focus).
This is the design record for a room built against an API Apple does not ship.

Everything routes through one CLI engine (`focus on / off / toggle / status /
scene / auto / doctor`), so the bar pill, the palette rows and the terminal can
never disagree about what a toggle does. Hooks — `slack` built in, plus
host-provided scripts — are run by the engine with `on` or `off`.

## Flipping Focus without a public API

Apple ships no public API or CLI for this — every open-source "focus CLI" is a
wrapper around a Shortcuts shortcut. haus takes the declarative route instead:

1. **Declare the hotkey.** nix-darwin writes AppleSymbolicHotKeys entry **175**
   ("Turn Do Not Disturb On/Off") as an obscure chord no human types, and core's
   end-of-activation `activateSettings -u` applies it without a logout. The
   binding *is* Nix config.
2. **pounce presses it.** `pounce focus toggle` posts the CGEvent. **No new TCC
   grant** — the daemon runs the notarized release app, whose Developer ID
   requirement anchors on hausfold's team, so pounce's Accessibility grant
   survives rebuilds and focus rides it.
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

**No declarative allowlists.** Which apps and people break through lives in
`~/Library/DoNotDisturb/DB/ModeConfigurations.json`, which is CloudKit-synced
and unsupported to write.

## Keeping the pill truthful

Hotkey 175 is a blind toggle, and the user can also flip Focus from Control
Center or their phone — so **reading** state matters more here, not less.

pounce reads `~/Library/DoNotDisturb/DB/Assertions.json`. That needs **Full Disk
Access**, and because the daemon runs the Developer-ID-signed release app, the
grant survives rebuilds the same way Accessibility does. So pounce is the one
TCC-privileged agent: it can both flip DND and report it
(`pounce focus status`), which makes `focus on`/`off` deterministic — read, then
toggle only if needed — rather than blind. Without FDA the engine falls back to
its own state file; `focus doctor` says so, and it is a degraded mode, not the
design.

A `WatchPaths` launchd agent on the DB dir fires `sketchybar --trigger
focus_change`, so the pill syncs instantly even when the toggle came from the
phone. The engine fires the same trigger after acting, so the pill never waits
for a poll when *we* changed the state.

## The Slack leg

macOS Focus already suppresses Slack banners *on the Mac*. The API leg is what
Focus can't do: tell your **teammates** and silence your **phone**.

- `users.profile.set` → status text + emoji (+ `status_expiration`)
- `dnd.setSnooze` / `dnd.endSnooze` → pauses Slack push on all devices
- Scopes: `users.profile:write`, `dnd:write`, on a personal user token

## The timer

`focus 25` is the same switch with a fuse: quiet now, quiet off again in
twenty-five minutes. What gets written down is the **until-timestamp**, never
the sleeping process, so a logout, a reboot or a rebuild takes the process and
leaves the fact — the agent's `RunAtLoad` picks the file back up with whatever
is left of it, and a fuse whose moment passed while the Mac was shut fires on
the way back up. It is a launchd one-shot per arm rather than a poll, for the
same reason `awake` is one: nothing ticks on a Mac where nobody set a timer.

A fuse is a **claim on the quiet it armed**, and it burns only while that claim
stands — the same "reverse only the lever you pulled" rule the scene engine
follows, one level down. Three things void it, and each resolves to *forget the
fuse*, never to *act anyway*:

1. **The quiet counter moved.** Every write of the quiet state bumps it, so a
   quiet you switched off and on again while the fuse slept is a different
   quiet — one you chose, which nothing may end for you.
2. **The Mac is no longer quiet.** Nothing left to end.
3. **A scene is on.** A scene owns the whole state while it runs. Arming
   refuses under one; entering one afterwards drops the fuse.

Arming over a quiet you set by hand still arms, and that is deliberate rather
than an exception to the rule above: typing `focus 25` at an already-quiet Mac
is choosing an end time, not being given one. The distinction the rule is
actually about is **a quiet the fuse never armed** — and unlike the trigger
daemon, which acts with nothing on screen, the countdown has been on the bar
since you set it, so nothing the fuse does is a surprise.

One blind spot, the room's existing one: DND toggled from Control Center or
your phone never reaches the counter, so quiet switched off and on again *that*
way leaves the fuse burning. It ends the quiet at the minute the pill has been
counting down to all along.

## Scenes

`haus.focus.scenes.<name>` is the same machinery with the member list opened
up — `dnd`, `preventSleep`, `audio.input`, `apps.open`, `apps.closeOnExit`,
`hooks`, `restorePreviousState`. Four rules are load-bearing:

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
4. **`focus off` and `focus toggle` release an active scene**, hold and
   microphone included: a pill that un-quiets while a caffeinate hold and a
   switched microphone stay behind is lying about what it just did. A
   `preventSleep` assertion is a `caffeinate` process, so its pid file is checked
   against the running process before anything is signalled, and
   `switchaudio-osx` (for `SwitchAudioSource`) enters the closure only when some
   scene names an `audio.input` — macOS ships no CLI for it, and a room
   shouldn't grow a closure for a field nobody set.

### A scene's key is generated, not written

Every other surface a scene gets is made out of the scene: a `Scene: <name>`
palette command, a cheatsheet row beside it, a `focus scene list` entry. A KEY
was the exception — the host wrote a `haus.keys.leaderExtras` entry whose
`command` repeated the scene's name inside a shell string, which stops being
true the moment the scene is renamed. `haus.focus.scenes.<name>.key` closes
that: one leaf, and the binding, the script AeroSpace execs and the cheatsheet
row are all made from it.

It crosses two rooms, because two different things are made out of one fact and
neither room may read the other. Launch mode is AeroSpace's, so the binding is
the windows room's (`_contrib.windows.leaderActions`, a registry — a key is
exactly the sort of thing a second room will want). The cheatsheet is pounce's,
so the row is the launcher's (`_contrib.launcher.focus.scenes.<name>.key`).
Focus writes both, one `mapAttrs` apart, so the key and the line that teaches it
cannot drift.

Three things the shape rests on:

1. **It is a LEADER key, not a global hotkey.** `haus.launcher.items.<key>.hotkey`
   is registered process-wide and beats Ghostty's own bindings; a collision
   across AeroSpace, pounce and macOS's symbolic hotkeys is silent, and the
   loser simply stops firing. A launch-mode key can only collide inside launch
   mode, where the roster letters, the numbered workspaces' three chords each,
   the fixed actions and `haus.keys.leaderExtras` already refuse each other at
   eval. So the contributed keys join that list BEFORE anything renders, and the
   assertion prints the option address rather than the key alone — the two
   halves are written in different files by different people.
2. **It is desktop-safe, unlike the `leaderExtras` entry it replaces.** That
   leaf is host-only for running an arbitrary command; this one names a key, and
   what it runs is this room's own verb. So a shared desktop can ship a scene
   complete with its key and still carry no code. The price is that a downloaded
   desktop can write the string that is spelled into a single-quoted TOML
   literal and into a filename under `~/.config/aerospace` — hence the shape
   assertion beside the collision one, which nothing needed while the only
   writer was a host file.
3. **The key TOGGLES.** `focus scene toggle <name>`, not the bare enter the
   palette row runs. ⌘Space can afford **Leave Scene** beside every **Scene**
   row; one keystroke has nowhere to put a second half, and a key that could
   only ever enter would lie about what the second press does. It reads through
   `focus scene status` rather than the scene file, so `quiet` — the built-in,
   which is not in the table — toggles too instead of quietening an
   already-quiet Mac forever.

## Triggers

`haus.focus.scenes.<name>.when` is a set of conditions ANDed together, and
`focus auto` is one launchd tick asking each scene whether its conditions hold.
The agent exists only on a machine where some scene declared one;
`haus.focus.triggers.interval` (default 30 s) is how often.

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
