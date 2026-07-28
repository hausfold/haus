# The nebelhaus Claude Code skill, as a derivation.
#
# WHY THIS IS GENERATED, NOT COMMITTED
# ------------------------------------
# The obvious shape for "teach an agent about nebelhaus" is a SKILL.md someone
# writes and keeps up to date. That file is stale the first time an option is
# added, and a confidently-wrong option name costs the user a failed rebuild and
# a rollback. So the half that can drift — every `nebelhaus.*` name, type,
# default and description — is RENDERED from the module system, the same source
# the nebelhaus.com reference is rendered from.
#
# Because it's a derivation, it's built from the rice revision the machine has
# actually pinned. The skill on disk therefore describes the options that exist
# HERE, not the ones on upstream main — which is the whole point: an agent that
# reads latest-main docs will offer a user options their pin doesn't have.
#
# The hand-written half (SKILL.md, recipes, the consumer CLAUDE.md) is the part
# that DOESN'T drift: the edit → rebuild → rollback loop, the boundaries, the
# traps. Keep it that way — if you find yourself listing option names in prose
# here, that belongs in the generated half.
{
  pkgs,
  lib ? pkgs.lib,
}:

let
  version = lib.fileContents ../../../VERSION;

  # The same option metadata nebelhaus.com's reference is rendered from — one
  # evaluation, so the page and the skill can't disagree about what an option is.
  optionsJSON = import ../../options-doc.nix { inherit pkgs lib; };
in
pkgs.runCommand "nebelhaus-claude-skill-${version}"
  {
    nativeBuildInputs = [ pkgs.jq ];
    meta = {
      description = "Claude Code skill teaching an agent to change a nebelhaus machine's config";
      inherit version;
    };
  }
  ''
    mkdir -p "$out/references"

    substitute ${./SKILL.md} "$out/SKILL.md" --subst-var-by riceVersion ${lib.escapeShellArg version}
    cp ${./recipes.md}          "$out/references/recipes.md"
    cp ${./consumer-CLAUDE.md}  "$out/consumer-CLAUDE.md"

    jq -r -f ${./options-md.jq} \
      ${optionsJSON}/share/doc/nixos/options.json \
      > "$out/references/options.md"

    # A skill whose option reference silently rendered empty would be worse than
    # no skill: the agent would conclude nebelhaus has no options rather than
    # that the render broke. Fail the build instead.
    grep -q '^nebelhaus\.' "$out/references/options.md" \
      || { echo "options.md rendered no nebelhaus.* options — the render is broken" >&2; exit 1; }
  ''
