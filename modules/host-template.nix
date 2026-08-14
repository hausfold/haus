# The annotated host file — every `haus.*` option at its default, with its
# description and a docs link, all commented out. A fresh install is scaffolded
# with it beside `default.nix`; `haus options` regenerates it after an update.
#
# It also emits the OPTIONS CATALOGUE (`options.json`) beside it — the same
# option list, as data rather than as prose, for `haus set`'s picker and the
# zsh completion. One derivation for both because they are the same query, and
# because the count self-check at the bottom then guards both files at once:
# the failure that check exists to catch (a jq edit that silently halves the
# list) is exactly as invisible in the catalogue as in the template.
#
# WHY THIS EXISTS. The option surface used to be discoverable in exactly one
# place — the docs site — and a person editing their host file had to know an
# option existed before they could look it up. AeroSpace solves that by shipping
# a default config with every setting present at its default and a comment above
# it: you learn the surface by reading your own config, and you make it minimal
# by deleting the lines you never touched. This is that, rendered from the
# module system so it can't drift.
#
# WHY A DERIVATION rather than a checked-in file, for the same reason as the
# agent skill next to it (hearth/agents/skill.nix): built from the revision a
# machine actually pinned, it can only describe options that exist THERE. A
# committed file would offer people options their pin doesn't have — a failed
# rebuild for the least experienced user we have, on their first day.
{
  pkgs,
  lib ? pkgs.lib,
}:

let
  version = lib.fileContents ../VERSION;

  # The same metadata hausfold.co's reference and the agent skill are rendered
  # from, carrying groups.json (the room/export/safety registry) beside it.
  optionsJSON = import ./options-doc.nix { inherit pkgs lib; };
in
pkgs.runCommand "nebelhaus-host-template-${version}"
  {
    nativeBuildInputs = [
      pkgs.jq
      pkgs.nixfmt
    ];
    meta = {
      description = "Annotated host file listing every haus.* option at its default";
      inherit version;
    };
  }
  ''
    mkdir -p "$out/share/nebelhaus"
    tmpl="$out/share/nebelhaus/host-options.nix"
    catalogue="$out/share/nebelhaus/options.json"

    jq -r \
      --slurpfile groups ${optionsJSON}/share/doc/nixos/groups.json \
      --arg hausVersion ${lib.escapeShellArg version} \
      -f ${./host-template.jq} \
      ${optionsJSON}/share/doc/nixos/options.json \
      > "$tmpl"

    # The same list as data: type, default, and one line of prose per path, for
    # anything that has to answer "what can I set?" without evaluating the
    # config. See options-catalogue.jq's header.
    jq \
      -f ${./options-catalogue.jq} \
      ${optionsJSON}/share/doc/nixos/options.json \
      > "$catalogue"

    # A template that rendered empty would be worse than none: someone would
    # conclude haus has no options rather than that the render broke.
    grep -q '^  # haus\.' "$tmpl" \
      || { echo "host template rendered no haus.* options — the render is broken" >&2; exit 1; }

    # It must PARSE as it ships — it's imported by the host file, so a syntax
    # error here is a machine that won't rebuild. nixfmt is used purely as a
    # parser (output discarded); the file's comment layout is deliberate and is
    # not reformatted.
    nixfmt < "$tmpl" > /dev/null \
      || { echo "host template is not valid Nix" >&2; exit 1; }

    # And every line must still parse ONCE UNCOMMENTED — the whole promise of
    # the file. This is the guard that catches the failure mode that actually
    # happened while writing it: an option whose `defaultText` is a SENTENCE
    # (`19, scaled by haus.ui.scale`) rendered as `… = 19, scaled by …;`,
    # valid-looking until someone uncommented it. Those are deliberately emitted
    # as a `…` placeholder now, so they're excluded here and everything else has
    # to survive; a new one that slips through as an expression fails the build
    # rather than the user's first rebuild.
    #
    # (The sed uncomments ONE line per option, which is all any default needs
    # today — none of them span lines. The day one does, its continuation lines
    # stay commented and this check fails rather than shipping a half-uncommented
    # block: teach the renderer to mark the block before teaching this to skip it.
    # Until then `defaultText` is the escape hatch — spell the default on one
    # line and this stays true. haus.wallpaper.debug.inputs is the first to need
    # it.)
    #
    # The pattern requires the ` =` as well, and that is not decoration. Every
    # option's own prose is in this file as `  # `-prefixed comment lines, so a
    # description that softwraps to start a line with `haus.theme.accent's hex`
    # reads to a bare `^  # haus\.` exactly like an assignment does — it got
    # uncommented, the file stopped parsing, and the error named the sentence
    # rather than the option whose description it was.
    sed -E 's|^  # (haus\.[A-Za-z0-9._-]+ =)|  \1|' "$tmpl" > uncommented.nix
    grep -v '= …;$' uncommented.nix > parseable.nix
    nixfmt < parseable.nix > /dev/null \
      || { echo "host template does not parse once its option lines are uncommented" >&2; exit 1; }

    # Every option in the JSON that a host file can actually set must be present.
    # Cheap, and it's what stops a jq filter change from silently halving the file.
    want=$(jq -r '[to_entries[]
                   | select(.key | startswith("haus."))
                   | select(.key | test("<|\\*") | not)] | length' \
             ${optionsJSON}/share/doc/nixos/options.json)
    got=$(grep -c '^  haus\.' uncommented.nix || true)
    [ "$got" = "$want" ] \
      || { echo "host template has $got settable options, expected $want" >&2; exit 1; }

    # Same guard on the catalogue, and for a sharper reason: nothing READS it
    # top-to-bottom, so a filter that quietly dropped half the options would
    # surface as a picker that simply doesn't list your option — indistinguish-
    # able from that option not existing at your pin, which is a thing this file
    # is otherwise designed to tell you truthfully.
    got=$(jq 'length' "$catalogue")
    [ "$got" = "$want" ] \
      || { echo "options catalogue has $got entries, expected $want" >&2; exit 1; }

    # Every entry must carry the facts a picker prompts from, WITH THE RIGHT
    # SHAPE. `has()` is not the check to make here: it is true for a key whose
    # value is null, so an entry of four nulls would pass it while the value
    # prompt silently degraded to a free-text box for an enum — the exact
    # failure this is for, and it looks like it worked until the rebuild rejects
    # the value. `default` is the one that legitimately may be null (an option
    # with no default at all), so it is the one checked by presence.
    jq -e 'all(.[]; (.type | type == "string")
                    and (.summary | type == "string")
                    and (.literal | type == "boolean")
                    and has("default"))' \
      "$catalogue" >/dev/null \
      || { echo "options catalogue has entries with a missing or mistyped type/literal/summary" >&2; exit 1; }
  ''
