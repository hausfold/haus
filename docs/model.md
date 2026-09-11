# The model — layer, room, desktop, host

**haus supplies rooms. A desktop curates them. A host makes one desktop yours.**

The reader's half of that sentence is
[choosing a desktop](https://hausfold.co/docs/haus/desktops/choosing) — the
stack diagram, "exactly one", and `blank` as the from-scratch choice — and
[creating one](https://hausfold.co/docs/haus/desktops/creating) is where the
closed shape, the host-only list and `haus show` are written for the person
writing a desktop. What is here is the half underneath: who owns what, and the
priorities that decide a disagreement.

| Layer | Owns | Does not own |
|---|---|---|
| **haus** | the module system, room catalogue, shared option types, CLI and safe defaults | a particular person's workflow or taste |
| **room** | one capability, its packages/services, its options and optional integrations with other rooms | whether a particular desktop wants it |
| **desktop** | one complete, data-only selection of rooms and values for their public options | identity, secrets or machine-specific hardware |
| **host** | identity, secrets, hardware facts and personal overrides | reusable upstream opinions |

Those layers are option priorities, and the numbers matter because one ordering
in the middle of them surprises people. Lower wins:

| priority | who | example |
|---|---|---|
| 50 | `haus set`'s override file, written `lib.mkForce` | `haus.ui.scale = 0.9;` ← wins |
| 100 | the host, plain assignment | `haus.ui.scale = 1.0;` |
| 900 | the desktop's leaves | `haus.ui.scale = 1.2;` |
| 1000 | a room's `mkDefault`, a profile's members included | `haus.ui.scale = 1.4;` |
| 1500 | the option's own declared default | |

A host beats both a desktop and a room with a plain value, and never needs
`lib.mkForce` to do it. A list-valued option follows the same rule rather than
appending: when the host names the list, its list replaces the desktop's.

`haus set`'s file is the one place haus itself writes `lib.mkForce`, because
what the palette and an agent write is the machine owner's explicit answer and
has to beat the desktop they chose. `haus reset` deletes that answer and reveals
the host/desktop/room value underneath; `haus unset` is a different operation,
writing `null` explicitly, so it only succeeds for a nullable option. A person
still writes `lib.mkForce` by hand where a `mkDefault` cannot be said otherwise
— `package = lib.mkForce null` is the documented way to say a roster entry has
no source at all.

The surprise: a **room-owned profile** sets its members at `mkDefault` too, so a
desktop that names one of those members beats the profile *even when the host is
what switched the profile on*. `haus.appearance.largePrint` is the one to watch
— a desktop pinning `haus.ui.scale` wins over it, and setting the value itself
in your host is what settles it.

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

**The catalogue is `modules/options-groups.nix`, never a second list.** It
carries every room's title and sentence; `modules/lib/show.nix` reads `rooms`
for `haus show`, `docs/site-data/groups.json` carries the namespace half to the
site's options reference, and `room-registry` fails on a namespace it does not
map. A hand-kept copy in a doc drifts into naming one room per namespace, with
module names where a product name belongs.

**Rooms are named for what they do.** The house-and-cat code names are gone, and
an old name in a config is an **eval error**, not a style nit:

| was | is |
|---|---|
| `sill` | `bar` |
| `prowl` | `windows` |
| `hearth` | `terminal` |
| `pounce` | `launcher` |
| `perch` | `shelf` |
| `hush` | `focus` |
| `collar` | `security.touchId` |

### Not every namespace is a room

The registry classifies every top-level `haus.*` namespace as one of three:

- **room** — owned by one product room in the catalogue;
- **shared** — a surface several rooms consume: keys, the app roster, workspaces;
- **host** — machine- or person-specific, such as identity.

**Classification and desktop-safety are separate questions.** Every public
option also states whether desktop data may set it, and the answer is explicit
rather than inferred from the namespace: semantic display scaling can belong in
a desktop, a physical display UUID cannot. Host config may set any public
option; desktop config is rejected when it reaches a host-only leaf.

**Safety is transitive.** An `attrsOf` or list-of-submodule option is
desktop-safe only when every reachable sub-option is classified and safe.
Freeform attrsets, `anything`, module values, paths that can import code, and
strings later executed as commands default to host-only unless an explicit
recursive validator narrows their payload. **A parent marked safe never blesses
unknown dynamic children.**

## Rooms cooperate

Through explicit extension points, `haus._contrib.<receiver>.<feature>`.
**Rooms do not silently enable each other**, and no room reads
`config.haus.ai.*` to decide what to draw.

**The source room owns the feature; the receiving room owns the extension
point.** A missing optional receiver removes that presentation without disabling
the source room. A *hard* dependency must be declared instead, and fail with a
message naming both rooms. `modules/lib/contrib.nix` is the mechanism, AGENTS.md
lists what is wired today, and
[rooms offer, never reach](https://hausfold.co/docs/haus/rooms/creating) is the
same rule for someone writing a third-party room.

**Three joins predate the extension points and read the other room's `config`
directly**, which is why the rule above names `haus.ai.*` rather than every
room: Bar draws its workspace pills off `config.haus.windows.*`
(`BAR_GRAVITY`/`BAR_PAGES`/`BAR_TILING`, generated in `modules/bar`), Windows
carves reserved screen space for a bar at an unreserved edge (`outerBottom`),
and the Launcher builds or deletes its gh-dash row off
`config.haus.terminal.ghDash.enable`. Appearance is the fourth shape: it supplies
tokens, and each room decides how its own surfaces consume them. Convert one on
touch; do not add a fifth.

## What a desktop is

A complete answer to "what should this Mac feel like?" It chooses rooms and
configures their exposed options. The evaluated value has one closed shape: **a
plain attrset whose only top-level key is `haus`**, setting only desktop-safe
public leaves. It is not a module function and has no `imports`, `_module`,
`system.*` or `home-manager.*`. Structural validation enforces that shape
*before* a full host evaluation proves the remaining option names and values are
valid.

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

Choose a desktop, review the rooms it enables, add or remove rooms, tune their
options, add identity and secrets in the host, then preview and rebuild.

Docs describe intent first and Nix second. *"Add the AI room"* is the user
action; which modules install scruff, write Codex hooks and contribute a bar pill
is implementation detail.
