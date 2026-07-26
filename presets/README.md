# Presets — and the shape a shared rice has to take

A preset is a **data-only rice**: a `.nix` file that evaluates to an attribute
set whose only top-level key is `nebelhaus`.

That's the whole rule, and it's deliberately mechanical, because it's the
difference between "import this stranger's config" and "run this stranger's
code". A data-only rice takes no `pkgs`, no `lib`, no `config`. It cannot add a
package, write an activation script, or touch anything outside the rice's own
option surface. You can read one in a minute and know the worst it can do.

`nebelhaus.lib.checkRice` enforces exactly that, and `nix flake check` runs it
over every preset here:

```nix
nebelhaus.lib.checkRice ./my-rice.nix   # true, or throws saying which key is stray
```

**The repo's own presets are not special.** They go through the same check and
the same import path a stranger's rice would, which is the point: if the option
surface can't express one of these without reaching around `nebelhaus.*`, it
can't express a community rice either, and we find out here rather than after
publishing a format.

## Using one

```nix
darwinConfigurations.myhost = nebelhaus.mkNebelhaus {
  username = "ada";
  hostname = "myhost";
  host = ./hosts/myhost;
  extraModules = [ nebelhaus.presets.everyday ];
};
```

Your host file still wins — it's imported after, so any option you set there
overrides the preset. Compose several by listing them; later ones win.

## What's here

| preset | for |
|---|---|
| `full` | the whole rice: bar, tiling, palette, developer pack. The default. |
| `minimal` | just the themed shell — no bar, no tiling, no palette. Still a developer machine. |
| `everyday` | the inverse: a Mac for someone who doesn't write code. No developer pack, no Caps-Lock remap. |

`everyday` is the one worth reading if you're designing your own — it's the
first preset that could not be expressed at all before `nebelhaus.developer`
existed, and it's the closest thing here to a rice aimed at somebody other than
its author.

## The limits, honestly

Data-only is a real boundary, not a sandbox. A preset still evaluates arbitrary
Nix *expressions* in its values — it just can't reach outside `nebelhaus.*` to
apply them. It's the difference between a config file and a program, which is
the distinction that matters for reading someone else's rice before running it.

A rice that genuinely needs `pkgs` — its own package, its own activation
script — is a **power module**: an ordinary nix-darwin module, with all the
trust that implies. Those are legitimate; they just aren't this, and shouldn't
be presented as interchangeable.
