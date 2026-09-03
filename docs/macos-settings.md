# macOS settings — what a desktop can actually set

**Measured on this machine, not recalled from docs.** macOS 26.6, aarch64,
nix-darwin. Every domain touched was exported first and byte-compared after.

Method: `defaults` for the plist layer, plus a compiled Swift `NSWorkspace`
probe for *effective* system state — **a plist read only proves the file
changed, not that macOS listened.** The probes are re-runnable and live in the
workshop's [`script/probes/`](https://github.com/hausfold/workshop/tree/main/script/probes);
rerun them on every macOS bump.

Scope: what a desktop can set *itself*. Settings no local write can reach —
TCC grants, background-item allow-lists, notification style — sit behind a
user-approved MDM enrollment and are a different question.

## The three failure modes to know

A domain here is in one of four states, and only the first is safe to build on:

| | means |
|---|---|
| **effective** | the write lands and an oracle confirms macOS honours it |
| **by-eye** | it works, but no programmatic oracle exists — a human checked once, and nothing can re-check it on your Mac |
| **writes and lies** | the plist takes the value and the machine ignores it. **The worst failure mode for a shared desktop**: `haus rebuild` succeeds, a `diff`-style check reports "applied", and nothing changed |
| **refused** | a hard write refusal, exit 1 |

## `com.apple.universalaccess` — works, gated on Full Disk Access

The domain **refuses writes from a process without FDA**. Not flaky, not
needing a restart: `Could not write domain com.apple.universalaccess; exiting`,
exit 1. With FDA held by the invoking app it writes *and* macOS honours it.

> ⚠️ **The asymmetry that matters here.** The grant is on the *responsible app*,
> so **an agent-driven `haus rebuild` and a rebuild from your own terminal are
> not equivalent.** Ghostty has FDA; an agent client typically does not. If a
> host sets one of these options, your rebuilds succeed and every agent rebuild
> **aborts activation partway** — skipping all launchd setup — for a config that
> "works on my machine".

**Oracle-backed, no restart needed:**

| key | haus option | nix-darwin typed? |
|---|---|---|
| `reduceMotion` | `haus.ui.motion` | ✅ |
| `reduceTransparency` | `haus.ui.transparency` | ✅ |
| `increaseContrast` | `haus.accessibility.increaseContrast` | ❌ → `CustomUserPreferences` |
| `differentiateWithoutColor` | `haus.accessibility.differentiateWithoutColor` | ❌ → `CustomUserPreferences` |

**By-eye, and only live after `killall universalaccessd`:**

| key | haus option | what to look for |
|---|---|---|
| `mouseDriverCursorSize` | `haus.accessibility.mouseDriverCursorSize` | pointer visibly larger at `3.0` |
| `closeViewScrollWheelToggle` | scroll-to-zoom | ⌃+scroll magnifies the display |
| `closeViewZoomFollowsFocus` | zoom follows focus | ⇥ to an off-screen input snaps the viewport to it |

> ⚠️ **Isolate the last one properly if you re-check it.** Panning the zoomed
> view by pushing the *pointer* at a screen edge is zoom's default behaviour and
> happens with the key off. The test that means anything: park the pointer, move
> **keyboard** focus out of the viewport.
>
> ⚠️ **The domain grows keys on its own.** Using zoom once leaves
> `universalaccessd`'s bookkeeping behind (`closeViewDesiredZoomFactor`,
> `closeViewZoomedIn`, …). Anything that diffs this domain sees drift that was
> never configuration.

`modules/lib/restart-map.nix` fires `universalaccessd` **per key**, so a rebuild
that only sets `increaseContrast` doesn't bounce the daemon.

One key in this domain is the exception and writes-and-lies:
`FontSizeCategory`, below.

## Domains and keys that write and lie

### `com.apple.Accessibility` — inert

Writable, holds the modern keys (`ReduceMotionEnabled`,
`DifferentiateWithoutColor`, `DarkenSystemColors`,
`EnhancedBackgroundContrastEnabled`, `FullKeyboardAccessEnabled`,
`InvertColorsEnabled`, `GrayscaleDisplay`, `ButtonShapesEnabled`). Writing it
changes the plist and **nothing else** — unchanged after a settle and after
poking `com.apple.accessibility.cache.ax`. Any accessibility option built on
this domain ships a lie. `haus diff` flags a hand-declared write here.

### `NSGlobalDomain AppleInterfaceStyle` — inert, and it lies *back*

Inert in both directions, and unlike the above it is where macOS **mirrors the
appearance it is showing**. So a plist read-back reports the write you just
made, a naive diff calls an inert write "applied", and the usual tiebreaker — a
freshly launched process — *also* fails. The appearance lives in session state
the WindowServer owns; `defaults` never reaches it.

Measured 2026-08-08, all four directions: writing `Dark` from a light session
does nothing, deleting the key from a dark one does nothing, `activateSettings
-u` does not help either, and no `AppleInterfaceThemeChangedNotification` is
posted. That key is a mirror the appearance system writes, not a lever.

Only **System Events** moves it, in ~0.3 s, firing
`AppleInterfaceThemeChangedNotification`. `haus.theme.systemAppearance` drives
it that way from home-manager activation; `hausax` has an `appearance` key so
the effect is confirmed against AppKit.

This means `system.defaults.NSGlobalDomain.AppleInterfaceStyle` — a *typed*
nix-darwin option — is **dead on macOS 26**. The reachability cost is an
**Automation** grant for whatever app runs the rebuild; refused means the
appearance doesn't move, not that activation dies.

### `com.apple.universalaccess FontSizeCategory` — stores, notifies nobody

macOS's own text-size setting. The key takes the value and holds it, and **no
change notification is posted**, so no running app re-reads it and nothing on
screen moves. There is no restart that fixes it either: the apps that would
honour a larger text size read the category once.

Display scaling is the lever that works, which is why
`haus.appearance.largePrint` reaches apps outside haus through
`haus.displays.main.uiScale` and not through this key.

## Domains that work, and what has to restart

| Domain | Restart | Notes |
|---|---|---|
| `com.apple.dock` | `killall Dock` — nix-darwin does this | 33 typed keys incl. hot corners |
| `com.apple.finder` | `killall Finder` — nix-darwin does **not** | 20 typed keys |
| `com.apple.screencapture` | none | 7 typed keys, applies to next capture |
| `NSGlobalDomain` | varies per key | 53 typed keys (minus `AppleInterfaceStyle`) |
| `com.apple.AppleMultitouchTrackpad` | none | 22 typed keys |
| `com.apple.WindowManager` | **logout** — no live-reload path exists | 12 typed keys, behind `haus.windows.{stageManager,nativeTiling,desktop}.*` |
| `com.apple.loginwindow` | **logout**, and unavailable rather than absent — `loginwindow` owns the session | 11 typed keys |
| `com.apple.controlcenter` | `killall ControlCenter` | ByHost domain |
| `com.apple.universalaccess` | `killall universalaccessd`, per key | FDA-gated, above |

**nix-darwin's entire post-write restart logic is one line** (`killall -qu
<user> Dock`, only when a `dock` option changed) and there is no
`activateSettings -u` anywhere in the module. **haus owns this** —
`modules/lib/restart-map.nix`, keyed by exactly the domain names above, and
`modules/lib/login-map.nix` renders the `logout` verb into each affected
option's own description.

**The animation keys are the one family shipped without a per-key sweep**
(`haus.animations`: `autohide-time-modifier`, `expose-animation-duration`,
`launchanim`, `mineffect`, `NSAutomaticWindowAnimationsEnabled`). That is the
honest limit of this method — there is no oracle for "did the Dock slide
faster". The one measurable claim about them is negative and *is* checked: none
of the five touches `NSWorkspace.accessibilityDisplayShouldReduceMotion`, the
flag browsers read as `prefers-reduced-motion`, which is why haus curates these
five rather than `universalaccess reduceMotion`.

⚠️ `NSAutomaticWindowAnimationsEnabled` is read by each app **at launch**, and
`activateSettings -u` cannot reach back into a running `NSApplication`.

**Typed-option surface: 193 keys**, not "several hundred" — NSGlobalDomain 53,
dock 33, trackpad 22, finder 20, WindowManager 12, loginwindow 11,
menuExtraClock 8, screencapture 7, controlcenter 7, universalaccess 5,
ActivityMonitor 5, and eight domains with 1–2 each.

## Sound

Oracle: `osascript -e 'get volume settings'` → CoreAudio's live alert volume.

| key | nix-darwin | state |
|---|---|---|
| `com.apple.sound.beep.volume` | ✅ typed float | effective, live, **no FDA gate** |
| `com.apple.sound.beep.sound` | ❌ → `CustomUserPreferences` | effective, **with a trap** |
| `com.apple.sound.beep.feedback` | ✅ typed bool | writable, no oracle |
| `com.apple.sound.uiaudio.enabled` | ❌ → `CustomUserPreferences` | writable, no oracle |
| startup chime | — | `nvram StartupMute`, root. Firmware, outside `system.defaults` |

**The volume leaf is `e^(slider − 1)`, not a percentage.**

| written | 1.0 | 0.7788 | 0.6065 | 0.5 | 0.4724 | 0.3679 | 0.0 |
|---|---|---|---|---|---|---|---|
| alert volume | 100 | 75 | 50 | **31** | 25 | **0** | 0 |

Everything at or below `e⁻¹ ≈ 0.3679` is silence. nix-darwin's docstring lists
75/50/25% as three magic constants and never says the curve, so `0.5` reads as
"half" and is 31%. A curated option takes 0–100 and converts; exposing the raw
float would ship a silent lie.

**It is a two-writers key.** `set volume alert volume 60` — what the Sound pane
and the volume keys use — writes into the *same* `NSGlobalDomain` key. So a
declared value silently reverts a hand-set volume at every rebuild, and a later
drag of the slider silently diverges from the declaration.

⚠️ **A bad `beep.sound` path is SILENCE, not a fallback** — verified by ear. The
plist reads exactly like a working configuration while the machine has stopped
making a sound you asked for. A curated option must validate the path at eval
time, or take an enum of the 14 names in `/System/Library/Sounds` and build the
path itself.

## Locale and input sources

Oracle: `locale-effective.swift` — Foundation + Carbon TIS in a **fresh**
process.

| key | nix-darwin | effect on a fresh process |
|---|---|---|
| `AppleICUForce24HourTime` | ✅ typed | ✅ hour skeleton `h a` → `HH` |
| `AppleMetricUnits` | ✅ typed | ✅ measurement system |
| `AppleTemperatureUnit` | ✅ typed | ✅ 20 °C → 68 °F |
| `AppleLocale` | ❌ → `CustomUserPreferences` | ✅ moves hour format, measurement system **and** first weekday together |
| `AppleLanguages` | ❌ → `CustomUserPreferences` | ✅ UI language follows on app **relaunch** |
| `AppleMeasurementUnits` | ✅ typed | ❌ **nothing moves** |
| `AppleFirstWeekday` (dict) | ❌ | ❌ **lands and lies** — stored, no error, `Calendar` ignores it |

The piece nothing in nix-darwin can express is a **distributed notification**;
without it, running apps never see the change.

## Power

`power.sleep.{computer,display,harddisk,allowSleepByPowerButton}` and
`power.restartAfter{PowerFailure,Freeze}` are typed — but they are **not**
`system.defaults`. nix-darwin shells out to `systemsetup` in its own activation
script, so there is no plist and none of this file's `defaults`-based evidence
applies.

Two limits:

1. **No power-source selector exists, and the missing selector is not neutral.**
   Every `systemsetup` sleep verb is source-blind while macOS stores the two
   sources separately. Measured: `-setcomputersleep 17` wrote the **AC** profile
   and left battery alone, *while the machine was on battery*. So the typed
   options cannot express "sleep at 5 min on battery, never on AC" — the only
   opinion a laptop desktop has — and what they do write goes somewhere the
   config never named.
2. **Every call ends in `&> /dev/null`.** A refusal, an unsupported verb and a
   success are indistinguishable. Not hypothetical: `systemsetup` emits an
   Admin-framework `-99` on stderr even when the write succeeds.

Unreachable through `system.defaults` entirely: Low Power Mode
(`pmset -a lowpowermode`), per-source anything (`pmset -b`/`-c`), lid and
clamshell (`lidwake`, `disablesleep`), `hibernatemode`, `womp`. All root-only
writes into a root-owned plist, so `haus.power.*` belongs in the
`security.firewall` family — an activation step of our own — not in the
`hotCorners`/`screenshots`/`menuBar` family.

## Display scaling

`displayplacer` is **not in nixpkgs** (it is a Homebrew formula), and the public
CoreGraphics API covers the whole job — haus ships a ~40-line Swift helper
instead of taking the dependency.

- **A stable identifier exists.** `CGDisplayCreateUUIDFromDisplayID` (needs
  `import ColorSync`) returns a persistent UUID, so `haus.displays.<key>` is
  keyed by UUID rather than by a reorderable index.
- `CGDisplaySetDisplayMode` is public API.
- ⚠️ Modes are duplicated ~6× (refresh rate × colour depth). Dedupe by point
  size and pick the highest refresh.

`hausdisp list` prints what's attached, each display's persistent UUID, and its
distinct HiDPI "looks-like" sizes.

## Open

- [ ] Confirm the by-eye `universalaccess` rows on a fresh macOS release —
      cursor size at `3.0`, ⌃+scroll zoom. It is the difference between
      "persists" and "works".
- [ ] Whether `systemsetup -setdisplaysleep` is AC-only like
      `-setcomputersleep`. The probe now prints both sources for that row, so
      the next run settles it.
- [ ] Report to `LnL7/nix-darwin`: `power.sleep.*` writes only one power profile
      on macOS 26, and `system.activationScripts.power` discards stderr, so
      nothing surfaces. `power-sweep.sh` is the reproducer.
- [ ] Have `haus doctor --matrix` run the probes, so "does this still hold on
      27?" is one command.
