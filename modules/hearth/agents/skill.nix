# The nebelhaus agent skill, as a derivation.
#
# ONE skill, installed into whichever clients this machine runs — Claude Code,
# Codex and OpenCode all read a `<dir>/<name>/SKILL.md` of exactly this shape,
# and hearth (agentHomes) knows each one's directory. It lived under
# hearth/claude/ and was called the Claude skill until 2026-08-11; nothing in
# its content ever was.
#
# WHY THIS IS GENERATED, NOT COMMITTED
# ------------------------------------
# The obvious shape for "teach an agent about nebelhaus" is a SKILL.md someone
# writes and keeps up to date. That file is stale the first time an option is
# added, and a confidently-wrong option name costs the user a failed rebuild and
# a rollback. So the half that can drift — every `haus.*` name, type,
# default and description — is RENDERED from the module system, the same source
# the nebelhaus.com reference is rendered from.
#
# Because it's a derivation, it's built from the rice revision the machine has
# actually pinned. The skill on disk therefore describes the options that exist
# HERE, not the ones on upstream main — which is the whole point: an agent that
# reads latest-main docs will offer a user options their pin doesn't have.
#
# The hand-written half (SKILL.md, recipes, the consumer starter pair) is the part
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
pkgs.runCommand "nebelhaus-agent-skill-${version}"
  {
    nativeBuildInputs = [ pkgs.jq ];
    meta = {
      description = "Agent skill teaching a coding agent to change a nebelhaus machine's config";
      inherit version;
    };
  }
  ''
    mkdir -p "$out/references"

    substitute ${./SKILL.md} "$out/SKILL.md" --subst-var-by riceVersion ${lib.escapeShellArg version}
    cp ${./recipes.md}          "$out/references/recipes.md"

    # The starter pair for a consumer repo: the rules in AGENTS.md, which every
    # client reads, plus the CLAUDE.md that is nothing but an @AGENTS.md import
    # (Claude Code reads only that name). Both are copied so a user who takes
    # them lands with the same one-body-many-pointers shape the family repos
    # use — a lone CLAUDE.md would be invisible to a Codex or OpenCode pane.
    cp ${./consumer-AGENTS.md}  "$out/consumer-AGENTS.md"
    cp ${./consumer-CLAUDE.md}  "$out/consumer-CLAUDE.md"

    jq -r -f ${./options-md.jq} \
      ${optionsJSON}/share/doc/nixos/options.json \
      > "$out/references/options.md"

    # A skill whose option reference silently rendered empty would be worse than
    # no skill: the agent would conclude the rice has no options rather than
    # that the render broke. Fail the build instead.
    grep -q '^haus\.' "$out/references/options.md" \
      || { echo "options.md rendered no haus.* options — the render is broken" >&2; exit 1; }
  ''
