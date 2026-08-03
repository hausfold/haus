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

Your host file can override anything a preset sets, but "imported after" is not
the mechanism — import order carries no priority in the module system. An option
the preset leaves alone is yours to set outright; an option it *does* set is a
conflict until you say `lib.mkForce`:

```nix
{ lib, ... }:                                   # add lib to your host's args
{
  nebelhaus.ui.scale = lib.mkForce 1.0;         # large-print sets this
  nebelhaus.git.email = "you@example.com";      # no preset sets this — plain
}
```

Composing several presets follows the same rule, so it works exactly as far as
they stay out of each other's way. `everyday` + `large-print` compose because
they answer different questions; `everyday` + `minimal` do not — they both
answer "is pounce on this machine", and the build stops with a conflict on
`nebelhaus.pounce.enable` rather than quietly taking the last one. That's the
intended behaviour: two presets disagreeing about the machine is a question only
you can settle.

## What's here

| preset | for |
|---|---|
| `full` | the whole rice: bar, tiling, palette, developer pack. The default. |
| `minimal` | just the themed shell — no bar, no tiling, no palette. Still a developer machine. |
| `everyday` | the inverse: a Mac for someone who doesn't write code. No developer pack, no Caps-Lock remap. |
| `large-print` | bigger and sharper: one UI scale, the high-contrast palette, macOS's own contrast lift. |

The first three are **whole rices** — pick one. `large-print` is a **layer**: it
describes seeing rather than the person, so it stacks:

```nix
extraModules = [ nebelhaus.presets.everyday nebelhaus.presets.large-print ];
```

That the two compose instead of one having to restate the other is the point.
A layer preset is a shape the format supports for free — later ones win, and a
preset that only sets what it's about doesn't collide with one that sets
something else.

`everyday` is the one worth reading if you're designing your own — it's the
first preset that could not be expressed at all before `nebelhaus.developer`
existed, and it's the closest thing here to a rice aimed at somebody other than
its author. `large-print` is worth reading for the opposite reason: its comment
block is explicit about what it does NOT reach (system-wide text size, the menu
bar, the palette, a different font family), which is the honest form for a rice
whose whole promise is legibility.

## The limits, honestly

Data-only is a real boundary, not a sandbox. A preset still evaluates arbitrary
Nix *expressions* in its values — it just can't reach outside `nebelhaus.*` to
apply them. It's the difference between a config file and a program, which is
the distinction that matters for reading someone else's rice before running it.

A rice that genuinely needs `pkgs` — its own package, its own activation
script — is a **power module**: an ordinary nix-darwin module, with all the
trust that implies. Those are legitimate; they just aren't this, and shouldn't
be presented as interchangeable.
