# The agent skills that OTHER hausfold tools ship, and the one derivation that
# proves the names below are real.
#
# A tool's `<tool>-skill` derivation lays out `$out/<skill-name>/SKILL.md` (the
# family standard, the workshop's notes/agent-surface.md §6), and a tool may
# ship more than one: holt ships `holt` (drive the lane lifecycle) and `handoff`
# (write the brief a `holt spawn --prompt-file` lane opens on).
#
# Split out of modules/ai/default.nix so `nix flake check` can build it. The
# room installs the result as home files, which puts it on every machine's
# rebuild path — and flake.nix already carries, in the comment above
# `.#agent-skill`, the incident that teaches why a derivation on that path with
# no check is the expensive kind: a red one fails `home-manager-files`, then
# `activation-<user>`, then the darwin system, on every `haus rebuild`, from a
# derivation CI never touched.
#
# The tool derivations arrive as named arguments rather than off `pkgs`, so the
# caller decides where they come from: the room reads them from the overlay,
# flake.nix's check from the flake input directly (its `pkgs` is a bare
# `legacyPackages` with no overlays applied).
{
  pkgs,
  lib,
  holt-skill,
}:
let
  checkedRef = import ../lib/checked-ref.nix { inherit lib pkgs; };

  # The one list. Adding a tool is a name here and an argument above.
  toolSkills = [
    {
      drv = holt-skill;
      names = [
        "holt"
        "handoff"
      ];
    }
  ];

  # Flattened to one entry per skill, so the fan-out in the room is a plain
  # product of clients × skills.
  toolSkillList = lib.concatMap (
    t:
    map (name: {
      inherit name;
      inherit (t) drv;
    }) t.names
  ) toolSkills;

  # The names above are unverifiable at EVAL time and entirely checkable at
  # BUILD time, and the difference is the whole of this derivation.
  # ../lib/checked-ref.nix is that difference, written out once; what belongs
  # HERE is which name is the promise.
  #
  # `SKILL.md` is what gets CHECKED and the folder is what gets INSTALLED,
  # because the family standard (the workshop's notes/agent-surface.md §6) is
  # what a name in the list above is a promise about — and an empty folder
  # would satisfy `-e` while teaching an agent nothing.
  #
  # Two tools claiming one skill name is a real collision here rather than a
  # theoretical one, and the helper catches it: they would collide in the
  # room's `listToAttrs` too, and failing at the earlier of the two is the
  # honest one.
  checked = checkedRef.collect {
    name = "haus-tool-skills";
    refs = map (skill: {
      path = "${skill.drv}/${skill.name}/SKILL.md";
      source = "${skill.drv}/${skill.name}";
      install = skill.name;
      problem = [
        "haus.ai.skill: ${skill.drv.name} ships no skill named '${skill.name}'."
        "  expected ${skill.drv}/${skill.name}/SKILL.md"
      ];
      # Three remedies, because they belong to three different people — the
      # question modules/theme/ports.nix asks out loud: who can this check fail
      # on? A haus AUTHOR adds a name to the list above before the lock bump
      # that carries it, or after a tool retires one. A CONSUMER of haus holds
      # the tool input transitively and can do neither, so name the lever that
      # is theirs.
      remedies = [
        "nix flake update <tool> — the skill may land in a revision newer than the one this lock pins"
        "drop the name from modules/ai/tool-skills.nix"
        "haus.ai.skill = false, to install no agent skills at all"
      ];
    }) toolSkillList;
  };
in
{
  inherit toolSkillList checked;
}
