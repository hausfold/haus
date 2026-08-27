# Renders the evaluated option set into the agent-facing option reference that
# ships inside the haus agent skill.
#
# Deliberately NOT the same rendering as hausfold.co's options page (which is
# rendered from the same data by that repo's scripts/gen-options.mjs).
# That page is for a person reading top-to-bottom: prose blurbs per room, links
# into the repo, Fumadocs components. This one is for a model that will `grep`
# it — so it leads with a flat name index (the whole namespace in one screen,
# which is what stops an agent inventing an option that doesn't exist), then one
# uniform stanza per option with the fields on their own lines.
#
# Same source of truth either way: a description edit lands in the room's
# options.nix and both surfaces follow.
#
# Reads `optionsNix` — the same attrset nixosOptionsDoc serialises into
# options.json — straight from the evaluation, so the render happens in Nix and
# nothing has to parse JSON back out at build time.
{ lib }:

optionsNix:

let
  # A default or example as the reference should show it: whatever the module
  # author wrote for a `literalExpression`, and JSON otherwise. A bare string
  # renders quoted, which is what makes `"right"` read as a value and not prose.
  lit =
    v:
    if builtins.isAttrs v && v ? _type then
      (if v ? text then v.text else builtins.toJSON v.value)
    else
      builtins.toJSON v;

  # A value on its own line, or fenced when it spans lines — an attrset default
  # rendered inline turns into an unreadable single-line blob.
  field =
    label: t:
    if lib.hasInfix "\n" t then "${label}:\n\n```nix\n${t}\n```\n" else "${label}: `${t}`\n";

  # Descriptions arrive with a trailing blank line more often than not; the
  # stanza supplies its own spacing.
  stripTrailingNewlines =
    s:
    let
      m = builtins.match "(.*[^\n])\n*" s;
    in
    if m == null then "" else builtins.head m;

  room = key: builtins.elemAt (lib.splitString "." key) 1;

  # Internal options (`haus._apps.*`) are already pruned upstream, in
  # options-doc.nix — the public reference and this one are fed the same surface,
  # so there's deliberately no second filter here to drift out of step with it.
  #
  # `attrNames` is already sorted, and every key shares the `haus.` prefix, so
  # rooms land in contiguous runs: grouping is a fold over neighbours rather
  # than a second sort that could disagree with the name index above.
  keys = builtins.filter (k: lib.hasPrefix "haus." k) (builtins.attrNames optionsNix);

  groups = builtins.foldl' (
    acc: key:
    let
      here = room key;
    in
    if acc != [ ] && (lib.last acc).room == here then
      (lib.init acc) ++ [ ((lib.last acc) // { keys = (lib.last acc).keys ++ [ key ]; }) ]
    else
      acc ++ [ { room = here; keys = [ key ]; } ]
  ) [ ] keys;

  stanza =
    key:
    let
      o = optionsNix.${key};
    in
    "#### `${key}`\n\n"
    + field "type" o.type
    + (if o ? default then field "default" (lit o.default) else "default: *none — this option must be set*\n")
    + (if o.readOnly or false then "read-only: `true`\n" else "")
    + field "declared in" (builtins.concatStringsSep ", " (o.declarations or [ ]))
    + "\n"
    + stripTrailingNewlines (o.description or "*(undocumented)*")
    + "\n"
    + (if o ? example then "\nexample:\n\n```nix\n${lit o.example}\n```\n" else "");

  section = g: "### haus.${g.room}\n\n" + builtins.concatStringsSep "\n" (map stanza g.keys);
in
"# haus.* — every option this machine has\n\n"
+ "Generated from haus's own module system at build time, so this file "
+ "describes the EXACT revision this machine is pinned to — not the latest "
+ "upstream. If an option you expect isn't here, it landed after this pin: say "
+ "so and offer `haus update`. Never set an option that isn't listed below.\n\n"
+ "Set these in `~/.config/nix/hosts/<hostname>/default.nix`, then apply with "
+ "`haus rebuild`.\n\n"
+ "## The whole namespace\n\n```\n"
+ builtins.concatStringsSep "\n" keys
+ "\n```\n\n"
+ "## Details\n\n"
+ builtins.concatStringsSep "\n" (map section groups)
# The trailing newline `jq -r` used to add. Kept so the rendered file is
# byte-identical to what every pinned machine already has.
+ "\n"
