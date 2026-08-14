# `docs/site-data/` — generated, do not edit

Three files, none of them hand-written:

| File | What it is |
|---|---|
| `options.json` | every `haus.*` option — type, default, example, description, and the file that declares it |
| `groups.json` | the export/namespace registry (`modules/options-groups.nix`): ownership, reading order, blurbs and per-option desktop safety — plus a `rooms` catalogue, the twelve rooms a person meets, each with a title, a sentence, and its derived namespaces, exports and option count. Two of its entries carry `kind = "shared"` / `"host"` instead of `"room"`, for the namespaces that belong to no single room; a catalogue filters on that. Top-level namespace aliases temporarily preserve the previous renderer contract |
| `wm-bindings.json` | the static tiling/workspace/service binding table, resolved for the **default** keymap |

They are `nix build .#site-data`, committed. Regenerate from the repo root:

```sh
out=$(nix build --no-link --print-out-paths .#site-data)
install -m644 "$out"/*.json docs/site-data/
```

The `site-data-current` flake check fails if these differ from the derivation,
so a hand edit here is guaranteed to be reverted. To change an option's
description, edit its declaration in `modules/<room>/options.nix` and
regenerate. **Note it only fires when the check is BUILT** — `nix flake check
--no-build` passes it vacuously. CI runs the full check; locally use
`nix build .#checks.aarch64-darwin.site-data-current`.

## Why a committed copy exists at all

The docs site renders its options reference and its keybinding tripwire from
this rice. Reading the derivations directly means the site's CI needs Nix, a
flake pin and a nixpkgs fetch just to check its own pages — fine while the site
lived in a repo that had Nix anyway, and not fine once it moves to its own repo
(the workshop's `notes/hausfold-rename.md` §5.1).

So the rice publishes the data and keeps the drift check next to the derivation
that defines it. The site reads three plain files out of a checkout.

`modules/site-data.nix` has the rest of the reasoning, including why the option
set is filtered to `haus.*` and why everything is `jq -S`'d.
