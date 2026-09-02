# `docs/site-data/` — generated, do not edit

Six files, none of them hand-written:

| File | What it is |
|---|---|
| `options.json` | every `haus.*` option — type, default, example, description, and the file that declares it |
| `groups.json` | the export/namespace registry (`modules/options-groups.nix`): ownership, reading order, blurbs and per-option desktop safety (each host-only option naming a reason out of the `hostOnlyReasons` table beside it, the way a `recursive` one names a validator) — plus a `rooms` catalogue, the thirteen rooms a person meets, each with a title, a sentence, and its derived namespaces, exports and option count. Two of its entries carry `kind = "shared"` / `"host"` instead of `"room"`, for the namespaces that belong to no single room; a catalogue filters on that. Top-level namespace aliases temporarily preserve the previous renderer contract |
| `wm-bindings.json` | the static tiling/workspace/service binding table, resolved for the **default** keymap |
| `launch-keys.json` | launch mode's own keys — the leader actions that exist before any roster letter, plus three chords per numbered workspace. **A list whose order is the order they are bound in** |
| `bar-tones.json` | the bar's tone ladder (`modules/bar/tones.nix`) — each rung's `name`, the nebelung `key` it resolves to (`null` for `accent`, which follows `haus.theme.accent`), the `stub` hex `test/barlib.bats` writes, and its `meaning`. **A list whose order is part of the answer**: the ladder runs quietest first, and the page that renders it reads top-to-bottom in that order |
| `bar-marks.json` | the identity axis beside it (`modules/bar/marks.nix`), same four fields. Every `key` here is disjoint from every fixed tone `key` — identity and status never share a hue, which `bar-marks` in `flake.nix` enforces |

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
haus. Reading the derivations directly means the site's CI needs Nix, a
flake pin and a nixpkgs fetch just to check its own pages — fine while the site
lived in a repo that had Nix anyway, and not fine once it moved to its own
repo (`hausfold/hausfold.co`, 2026-08-08).

So haus publishes the data and keeps the drift check next to the derivation
that defines it. The site reads six plain files out of a checkout.

`modules/site-data.nix` has the rest of the reasoning, including why the option
set is filtered to `haus.*` and why everything is `jq -S`'d.

## Who reads which

| File | Read by |
|---|---|
| `options.json`, `groups.json` | hausfold.co `scripts/gen-options.mjs` → its options reference |
| `wm-bindings.json`, `launch-keys.json` | hausfold.co `scripts/check-rice-bindings.mjs` — a tripwire, not a renderer: the keybinding pages are prose and it fails when haus's bindings move past what they were last checked against |
| `bar-tones.json`, `bar-marks.json` | hausfold.co `scripts/check-bar-tables.mjs`, the same shape — it holds the two tables on `/docs/haus/rooms/bar-widgets` to these names and this order exactly, and snapshots the `meaning` column so a rewording here lands as a docs task rather than as a page that quietly disagrees |
