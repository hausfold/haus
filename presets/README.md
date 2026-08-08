# Presets — and the shape a shared rice has to take

A preset is a **data-only rice**: a `.nix` file that evaluates to an attribute
set whose only top-level key is `haus`. (`nebelhaus` is still accepted, as the
pre-rename spelling of the same namespace; new files should use `haus`.)

That's the whole rule, and it's deliberately mechanical, because it's the
difference between "import this stranger's config" and "run this stranger's
code". A data-only rice takes no `pkgs`, no `lib`, no `config`. It cannot write
an activation script, define a package, or touch anything outside the rice's own
option surface. You can read one in a minute and know the worst it can do.

It *can* ask for a package by name — `roster.<name>.packageName = "ripgrep"`,
`fonts.mono.packageName = "nerd-fonts.fira-code"` — which the rice resolves as
an attribute path into nixpkgs. That's still data: the resolver looks the
attribute up and nothing else, no string ever becomes code. The line it draws is
"a rice you can read", not "a rice that installs nothing you haven't vetted" —
`cask` could always fetch arbitrary software, and naming a nixpkgs attribute is
the same trust, not a new one.

`nebelhaus.lib.checkRice` enforces exactly that, and `nix flake check` runs it
over every preset here:

```nix
nebelhaus.lib.checkRice ./my-rice.nix   # true, or throws saying which key is stray
```

**The repo's own presets are not special.** They go through the same check and
the same import path a stranger's rice would, which is the point: if the option
surface can't express one of these without reaching around `haus.*`, it
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
the preset leaves alone is yours to set outright; an option it sets to a
*different* value is a conflict until you say `lib.mkForce`. (Setting one to the
value it already holds is not a conflict — identical definitions merge, so
restating something a preset already decided costs nothing but the line.)

```nix
{ lib, ... }:                                   # add lib to your host's args
{
  haus.ui.scale = lib.mkForce 1.0;         # large-print sets this
  haus.git.email = "you@example.com";      # no preset sets this — plain
}
```

Composing several presets follows the same rule, and the rule is **two presets
compose unless they disagree** — sharing an option is fine, holding different
opinions about it is not. `everyday` + `large-print` compose because they answer
different questions. `everyday` + `minimal` do not: they share five options and
disagree about four of them (they both want prowl off, so that one merges), and
the build stops naming the option and both files rather than quietly taking the
last one. That's the intended behaviour — two presets disagreeing about the
machine is a question only you can settle.

**One thing that is quiet, and worth knowing before you compose two rices you
didn't write:** an option holding a *list or a set* — `tour.steps`, `roster` —
never conflicts. Those definitions are combined, with no error and no warning, so
two rices that each author a first-run tour give you a tour with both, in an
order neither of them chose.

Every claim in this section is pinned by `nix flake check`'s
**`preset-composition`**, which composes all six pairs of the presets below —
plus a host that agrees, one that disagrees, one that says `mkForce`, one that
joins an argument two presets are already having, and two rices that each add a
tour step and an app — and diffs the result against a golden table. The counts in the paragraph above are in that table. If editing one of
these files breaks a pair the format advertises as stackable, that check is what
tells you, rather than a stranger's first `extraModules` line.

**Packs are the deliberate exception.** A [pack](../packs/README.md) reaches you
through `nebelhaus.lib.pack`, which lowers every field it sets to `mkDefault`, so
your host beats it with a plain assignment and no `mkForce`. A preset isn't
wrapped that way: it answers what kind of machine this is, which is a claim worth
colliding over, while a pack only proposes what's on it.

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
A layer preset is a shape the format supports for free, and *only* because of
the rule above: nothing arbitrates a disagreement, so a preset that sets just
what it's about is the one kind that always stacks.

`everyday` is the one worth reading if you're designing your own — it's the
first preset that could not be expressed at all before `haus.developer`
existed, and it's the closest thing here to a rice aimed at somebody other than
its author. `large-print` is worth reading for the opposite reason: its comment
block is explicit about what it does NOT reach (system-wide text size, the menu
bar, the palette, a different font family), which is the honest form for a rice
whose whole promise is legibility.

## The limits, honestly

Data-only is a real boundary, not a sandbox. A preset still evaluates arbitrary
Nix *expressions* in its values — it just can't reach outside `haus.*` to
apply them. It's the difference between a config file and a program, which is
the distinction that matters for reading someone else's rice before running it.

A rice that genuinely needs `pkgs` — its own package, its own activation
script — is a **power module**: an ordinary nix-darwin module, with all the
trust that implies. Those are legitimate; they just aren't this, and shouldn't
be presented as interchangeable.
