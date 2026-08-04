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

Any single field is yours to override without forking the pack — but "override"
means `lib.mkForce`, not "the host is imported last". Import order carries no
priority in the module system: a host that sets a field the pack also sets
*conflicts* with it rather than winning. See bite 2 below, which is what that
looks like the first time.

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

## Four things that bite, in order of how much time they cost

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

**2. The consumer already has the app — and that fails differently than a key
clash.** Bite 1 is two entries fighting over a *letter*. This is one entry:
`roster.obsidian` declared by both the pack and the host, which is the likelier
case, because a pack is worth publishing precisely when its apps are popular.
There's no assertion to reach — the module system stops first, per field:

```
error: The option `nebelhaus.roster.obsidian.key' has conflicting definition values:
- In `…/hosts/mbp': "n"
- In `…/packs/writing.nix': "o"
Use `lib.mkForce value` or `lib.mkDefault value` to change the priority…
```

Take that suggestion literally — in the **host**, which unlike a pack is an
ordinary module and can call `lib`. Force only the fields you disagree with:

```nix
{ lib, ... }:                                    # add lib to your host's args
{
  nebelhaus.roster.obsidian.key = lib.mkForce "n";
}
```

The rest of the pack's entry survives intact — Obsidian keeps the pack's
workspace, pill and `appId`, and just answers to your letter. One `mkForce` per
disputed field, not per entry.

What a pack author can do about it: keep entries minimal. Every optional field
you set is a field a consumer may have to force, so leave `workspace`,
`barIcon` and `appId` null unless the pack genuinely needs them.

**3. `appId` is the one field a pack usually can't fill in.** It's the bundle id
AeroSpace matches on to herd a window to its workspace, it isn't in Homebrew's
cask metadata, and a guessed one produces a rule that silently never matches.
Leave it null and say so: null costs *only* auto-assignment — the leader key,
the workspace, the pill and the cheatsheet row all still work. The consumer
closes it once the app is installed, with
`osascript -e 'id of app "Obsidian"'`.

**4. Install from Nixpkgs by NAMING the package, not evaluating it.** All four
sources are expressible: Homebrew (`cask`, `brew`), the App Store (`appStoreId`)
and Nixpkgs — the last one through `packageName`, an attribute path into nixpkgs
written as a string:

```nix
{
  nebelhaus.roster.ripgrep.packageName = "ripgrep";              # pkgs.ripgrep
  nebelhaus.roster.black.packageName = "python3Packages.black";  # dotted paths work
}
```

`roster.*.package` — the derivation-typed one — is still out of reach from a
data-only file, and always will be: it needs `pkgs`, which a pack has no way to
be handed. `packageName` is the same source said in data. Set one or the other,
never both; the build refuses the pair rather than picking a winner. The rice
takes the same shape wherever it takes a package (`fonts.mono.packageName` is
the other one today), and `nix flake check`'s `data-only-surface` fails if a
package-typed option is ever added without its named sibling.

What naming a package does NOT do is widen what a rice can run. The resolver
walks `pkgs` by attribute path — no `import`, no eval of a string as code — so
reading a rice still tells you everything it can do. It installs software you
haven't vetted, exactly like `cask` already did.

## Publishing one

A pack is one file with no dependencies, so it needs no flake of its own: put it
in a gist or a repo and let people fetch it, or expose it from a flake as
`packs.<name>` the way this repo does. Nothing here is privileged — `packs/` goes
through the identical import path a stranger's file would.
