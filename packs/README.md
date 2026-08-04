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

Any single field is yours to override without forking the pack, and — unlike a
preset — plainly: **your host outranks a pack.** Set `roster.obsidian.key` in
your own host file and it wins, no `lib.mkForce`, while the rest of the pack's
entry (its workspace, its pill, the cask that installs it) stays. That is not
"the host is imported last", which is not a thing — import order carries no
priority in the module system. It's the *seam*: `nebelhaus.packs.<name>` hands
you the pack through `nebelhaus.lib.pack`, which lowers every field it defines
to `lib.mkDefault` on the way in. See bite 2, including what happens if you
import a pack file directly and skip that seam.

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

Self-test before publishing — the same checks CI runs:

```nix
nebelhaus.lib.checkRice ./my-pack.nix   # data-only: only a `nebelhaus` key
nebelhaus.lib.checkPack ./my-pack.nix   # pack-shaped: only `nebelhaus.roster`
```

`checkPack` is the narrower of the two and exists because `lib.pack` carries
only `roster` through: a `theme.accent` line in a pack file would be dropped
without a word, so it's refused instead. If your file wants to say what kind of
machine this is as well as what's on it, that's a preset — ship it as one.

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

**2. The consumer already has the app — your host just wins, and that is worth
understanding rather than enjoying.** Bite 1 is two entries fighting over a
*letter*. This is one entry: `roster.obsidian` declared by both the pack and the
host, which is the likelier case, because a pack is worth publishing precisely
when its apps are popular.

```nix
# your host file — no lib, no mkForce, nothing special
{
  nebelhaus.roster.obsidian.key = "n";
}
```

Obsidian answers to your letter and keeps the pack's workspace, pill and cask.
One field, one winner; the rest of the entry is untouched.

**How, and the one place it doesn't apply.** A pack is data-only, so it cannot
lower its own priority — writing `lib.mkDefault` would make the file a function,
which `checkRice` refuses. The priority is applied by the seam that imports it,
`nebelhaus.lib.pack`, which puts every field at `mkDefault`. `packs.<name>` is
pre-wrapped. **A pack file imported as a bare path is not**, and still conflicts
the old way:

```nix
extraModules = [
  ./vendored/writer-pack.nix                    # ← conflicts with your host
  (nebelhaus.lib.pack ./vendored/writer-pack.nix)  # ← your host wins
];
```

Same file, different behaviour, so vendor packs through `lib.pack` — that is
what the wrapper is for.

**Two packs that name the same app still stop the build**, and should: the
consumer can't be expected to know what's inside a pack, but two pack authors
are equals and nobody else can settle it. Naming that app in your own host
settles it — a plain assignment outranks both packs at once.

What a pack author can do about it: keep entries minimal. Every optional field
you set is one a consumer silently overrides, so leave `workspace`, `barIcon`
and `appId` null unless the pack genuinely needs them. And note the trade this
makes for you: **you are not told when a consumer disagrees with you.** A pack
suggests; the machine's owner decides.

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

Tell people to import it through `nebelhaus.lib.pack ./your-pack.nix` (or expose
it already-wrapped, as `packs.<name>`), and say so in your README. It is the
difference between "install this and your own settings still win" and "install
this and your build might stop on a field you never mentioned".
