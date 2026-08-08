# The annotated host file — every `haus.*` option at its default, with its
# description and a docs link, all commented out. A fresh install is scaffolded
# with it beside `default.nix`; `haus options` regenerates it after an update.
#
# WHY THIS EXISTS. The option surface used to be discoverable in exactly one
# place — nebelhaus.com — and a person editing their host file had to know an
# option existed before they could look it up. AeroSpace solves that by shipping
# a default config with every setting present at its default and a comment above
# it: you learn the surface by reading your own config, and you make it minimal
# by deleting the lines you never touched. This is that, rendered from the
# module system so it can't drift.
#
# WHY A DERIVATION rather than a checked-in file, for the same reason as the
# Claude skill next to it (hearth/claude/skill.nix): built from the revision a
# machine actually pinned, it can only describe options that exist THERE. A
# committed file would offer people options their pin doesn't have — a failed
# rebuild for the least experienced user we have, on their first day.
{
  pkgs,
  lib ? pkgs.lib,
}:

let
  version = lib.fileContents ../VERSION;

  # The same metadata nebelhaus.com's reference and the agent skill are rendered
  # from, carrying groups.json (room order + blurbs) beside options.json.
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

    jq -r \
      --slurpfile groups ${optionsJSON}/share/doc/nixos/groups.json \
      --arg riceVersion ${lib.escapeShellArg version} \
      -f ${./host-template.jq} \
      ${optionsJSON}/share/doc/nixos/options.json \
      > "$tmpl"

    # A template that rendered empty would be worse than none: someone would
    # conclude the rice has no options rather than that the render broke.
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
    # block: teach the renderer to mark the block before teaching this to skip it.)
    sed -E 's|^  # (haus\.)|  \1|' "$tmpl" > uncommented.nix
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
  ''
