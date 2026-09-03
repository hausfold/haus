# The model — layer, room, desktop, host

**haus supplies rooms. A desktop curates them. A host makes one desktop yours.**

| Layer | Owns | Does not own |
|---|---|---|
| **haus** | the module system, room catalogue, shared option types, CLI and safe defaults | a particular person's workflow or taste |
| **room** | one capability, its packages/services, its options and optional integrations with other rooms | whether a particular desktop wants it |
| **desktop** | one complete, data-only selection of rooms and values for their public options | identity, secrets or machine-specific hardware |
| **host** | identity, secrets, hardware facts and personal overrides | reusable upstream opinions |

A person chooses **exactly one base desktop**, then enables or disables rooms
and overrides any room setting in their host. **Whole desktops do not stack.**

The built-in **blank** desktop is the from-scratch choice: no optional rooms and
no opinions beyond haus's safe foundation. It keeps "build my own" inside the
one-desktop model instead of making the absence of a desktop a second mode.

```text
haus foundation
      ↓
one desktop (blank, hacker, everyday, minimal, …)
      ↓
host overrides
      ↓
machine-written `haus set` overrides
```

Later layers win deliberately. **A host must be able to change its desktop with
a plain assignment** — never `lib.mkForce` for ordinary customization.

Those layers are option priorities, and the numbers matter because one ordering
in the middle of them surprises people. Lower wins:

| priority | who | example |
|---|---|---|
| 100 | the host, plain assignment | `haus.ui.scale = 1.0;` ← wins |
| 900 | the desktop's leaves | `haus.ui.scale = 1.2;` |
| 1000 | a room's `mkDefault`, a profile's members included | `haus.ui.scale = 1.4;` |
| 1500 | the option's own declared default | |

So a host beats both a desktop and a room with a plain value, and never needs
`lib.mkForce` to do it.

The surprise: a **room-owned profile** sets its members at `mkDefault` too, so a
desktop that names one of those members beats the profile *even when the host is
what switched the profile on*. `haus.appearance.largePrint` is the one to watch
— a desktop pinning `haus.ui.scale` wins over it, and setting the value itself
in your host is what settles it.

A list-valued option follows the same rule rather than appending: when the host
names the list, its list replaces the desktop's.

## What a room is

A nix-darwin module with a public `haus.<room>` option namespace. It may add
whatever its capability requires: packages, files, services, defaults,
activation work, assertions, and contributions to another room's extension
points.

Every user-visible room has:

- one switch, normally `haus.<room>.enable`;
- a neutral, useful configuration when enabled;
- all of its configurable behaviour under its namespace;
- declared requirements, permissions and side effects;
- clean removal when disabled;
- generated metadata for the catalogue and docs.

**Generic room defaults are conservative.** Keyboard remaps, developer
workflows, personal bar pills and other strong opinions belong to desktops.
Enabling the launcher gives you a working launcher; a *desktop* decides whether
it takes over ⌘Space.

### Not every namespace is a room

The registry classifies every top-level `haus.*` namespace as one of three:

- **room** — owned by one product room in the catalogue;
- **shared** — a surface several rooms consume: keys, the app roster, workspaces;
- **host** — machine- or person-specific, such as identity.

**Classification and desktop-safety are separate questions.** Every public
option also states whether desktop data may set it, and the answer is explicit
rather than inferred from the namespace: most launcher settings belong in a
desktop, while a signing identity belongs only in a host; semantic display
scaling can belong in a desktop, a physical display UUID cannot. Host config may
set any public option; desktop config is rejected when it reaches a host-only
leaf.

**Safety is transitive.** An `attrsOf` or list-of-submodule option is
desktop-safe only when every reachable sub-option is classified and safe.
Freeform attrsets, `anything`, module values, paths that can import code, and
strings later executed as commands default to host-only unless an explicit
recursive validator narrows their payload. **A parent marked safe never blesses
unknown dynamic children.**

## The room catalogue

| Room | Scope |
|---|---|
| **Apps** | the roster, install sources, App Store policy |
| **Appearance** | theme, wallpaper, fonts, interface scale |
| **Displays** | resolution and per-display behaviour |
| **Development** | terminal, shell, multiplexer, editor, Git, CLI toolbelt, language runtimes |
| **Windows** | tiling, workspaces, window navigation |
| **Bar** | placement, pills, readouts |
| **Launcher** | Pounce installation, daemon, commands, every Pounce setting haus exposes |
| **Shelf** | Perch installation and every declarative Perch setting haus exposes |
| **Focus** | Do Not Disturb, status, hooks |
| **AI** | agent clients, scruff, factory, lifecycle/state wiring, instructions, the haus skill and every other tool's |
| **Text expansion** | snippets and their expansion engine |
| **Security** | Touch ID, lock behaviour, firewall, secret-provider policy |

These are product groupings *and* the spellings. Code may stay split into
smaller modules where that keeps ownership clear; the generated catalogue maps
those modules and namespaces onto the room a person understands.

**Rooms are named for what they do.** The house-and-cat code names are gone:

| was | is |
|---|---|
| `sill` | `bar` |
| `prowl` | `windows` |
| `hearth` | `terminal` |
| `pounce` | `launcher` |
| `perch` | `shelf` |
| `hush` | `focus` |
| `collar` | `security.touchId` |

An old name in a config is an **eval error**, not a style nit.

## Rooms cooperate

Through explicit extension points. **They do not silently enable each other.**

- AI contributes agent lifecycle bindings when Development is enabled.
- AI contributes agent pills when Bar is enabled.
- AI contributes agent commands when Launcher is enabled.
- Windows contributes workspace pills when Bar is enabled.
- Bar requests reserved screen space from Windows when it draws at an
  unreserved edge.
- Focus contributes controls to Bar and Launcher when either is present.
- Appearance supplies tokens; rooms decide how their own surfaces consume them.

**The source room owns the feature; the receiving room owns the extension
point.** A missing optional receiver removes that presentation without disabling
the source room. A *hard* dependency must be declared and fail with a message
naming both rooms.

## What a desktop is

A complete answer to "what should this Mac feel like?" It chooses rooms and
configures their exposed options.

A shareable desktop is **data-only** and may set only options marked safe for
desktop data:

```nix
{
  haus = {
    development.enable = true;
    windows.enable = true;
    bar.enable = true;
    launcher.enable = true;

    theme.accent = "mauve";
    keys.palette = "cmd-space";
  };
}
```

The evaluated value has one closed shape: **a plain attrset whose only top-level
key is `haus`**. A desktop is not a module function, has no `imports` or
`_module`, cannot name `system.*`, `home-manager.*` or activation hooks, and
sets only desktop-safe public `haus.*` leaves. Identity, secrets, account
coordinates, signing identities and hardware identifiers are host-only even when
a room uses them. Structural validation enforces the closed shape *before* a
full host evaluation proves the remaining option names and values are valid.

**One desktop per host** removes desktop-versus-desktop precedence from the user
model. What would have been presets or layers become room-owned profiles when
they stay useful — large print belongs to Appearance. The Apps room may call a
saved app collection a **pack**, but a pack is not a peer of room or desktop and
is not a shareable format: the collections behind `haus.apps.packs.<name>.enable`
are haus's own data, and a stranger's app collection is a **room**.

**There are exactly two things a person can publish: a desktop, and a room.**
Nix already spells the difference — a desktop is data, a room is code — and that
is what decides the trust warning each one gets on acquisition.

## The user journey

1. Choose a desktop: hacker, another published desktop, or blank.
2. Review the rooms it enables and the visible choices it makes.
3. Add or remove rooms.
4. Tune the options those rooms surface.
5. Add private identity, secrets and hardware details in the host.
6. Preview and rebuild.

Docs describe intent first and Nix second. *"Add the AI room"* is the user
action; which modules install scruff, write Codex hooks and contribute a bar pill
is implementation detail.
