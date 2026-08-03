# Packs — a shareable list of apps

A **pack** is a data-only rice that touches one option family: `nebelhaus.roster`.

Same file format as a [preset](../presets/README.md), same `checkRice` rule, same
`nix flake check`. The separate name is about scope, not mechanism:

|  | answers | example |
|---|---|---|
| **preset** | what kind of machine is this | `everyday`, `large-print` |
| **pack** | what's on it | `writing` |

Because they answer different questions they don't collide, and you stack them:

```nix
darwinConfigurations.myhost = nebelhaus.mkNebelhaus {
  username = "ada";
  hostname = "myhost";
  host = ./hosts/myhost;
  extraModules = [
    nebelhaus.presets.everyday      # a Mac for someone who doesn't write code
    nebelhaus.presets.large-print   # …that you can read
    nebelhaus.packs.writing         # …with these four apps on it
  ];
};
```

Your host file is imported last and wins, so any single field is yours to
override without forking the pack.

## What's here

| pack | what it puts on the machine |
|---|---|
| `writing` | Obsidian, Zotero, Anki, calibre — a Mac that reads and writes rather than compiles |

## Writing one

Declaring an app in the roster is what installs it, so a pack is both the app
list and the install instruction. The whole file:

```nix
{
  nebelhaus.roster = {
    obsidian = {
      key = "o";                # leader, then o
      name = "Obsidian";        # as `open -a` spells it
      workspace = "O";          # owns a workspace and a bar pill
      barIcon = ":obsidian:";   # a sketchybar-app-font ligature
      cask = "obsidian";        # declaring it installs it
    };
    calibre = { name = "calibre"; cask = "calibre"; };   # install-only
  };
}
```

Self-test before publishing — the same check CI runs:

```nix
nebelhaus.lib.checkRice ./my-pack.nix
```

## Three things that bite, in order of how much time they cost

**1. `key` collides, and there are two ways it can.** Against another roster
entry — including one from the consumer's own host or another pack — and against
a built-in leader action. Both fail the build with a message naming the letter,
which is the good case; the second one only started failing in the PR that added
this directory, and before that it silently dropped one of the two bindings.

The letters the rice already owns in leader mode, so a pack must not claim them:

```
v  clipboard      e  emoji        z  reopen last closed app
,  System Settings         `  re-sort windows
-  =  resize      1-4  workspaces      ⇧1-4  throw to workspace
arrows  navigate  esc  exit    /  cheatsheet
```

A pack author can't know what the *consumer's* roster uses, so expect the
occasional clash and say in your README that the fix is one line:
`nebelhaus.roster.<id>.key = "y";` — or `null`, which keeps the app installed and
reachable from ⌘Space while claiming no letter at all.

**2. `appId` is the one field a pack usually can't fill in.** It's the bundle id
AeroSpace matches on to herd a window to its workspace, it isn't in Homebrew's
cask metadata, and a guessed one produces a rule that silently never matches.
Leave it null and say so: null costs *only* auto-assignment — the leader key,
the workspace, the pill and the cheatsheet row all still work. The consumer
closes it once the app is installed, with
`osascript -e 'id of app "Obsidian"'`.

**3. A pack cannot install from Nixpkgs.** `roster.*.package` is typed as a
package, and reaching `pkgs` is exactly what data-only forbids — the same limit
the rice hit on `fonts.mono.package`. Homebrew (`cask`, `brew`) and the App Store
(`appStoreId`) are fully expressible; a pack of Nixpkgs tools is not, today.

## Publishing one

A pack is one file with no dependencies, so it needs no flake of its own: put it
in a gist or a repo and let people fetch it, or expose it from a flake as
`packs.<name>` the way this repo does. Nothing here is privileged — `packs/` goes
through the identical import path a stranger's file would.
