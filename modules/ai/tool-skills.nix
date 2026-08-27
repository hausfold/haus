# The agent skills that OTHER hausfold tools ship, and the one derivation that
# proves the names below are real.
#
# A tool's `<tool>-skill` derivation lays out `$out/<skill-name>/SKILL.md` (the
# family standard, the workshop's `docs/agent-surface.md`), and a tool may
# ship more than one: scruff ships `scruff` (drive the lane lifecycle) and `handoff`
# (write the brief a `scruff spawn --prompt-file` lane opens on).
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
  scruff-skill,
  trill-skill ? null,
  trillEnabled ? true,
}:
let
  checkedRef = import ../lib/checked-ref.nix { inherit lib pkgs; };

  # The one list. Adding a tool is a name here and an argument above — plus,
  # when the tool is OPTIONAL on a machine, the switch its room is gated on.
  #
  # `enable` is what makes an optional tool's skill honest. scruff is on every
  # haus machine, so its skill is never wrong to have. trill's room is off by
  # default (`haus.notifications.compositor`), and a skill teaching an agent to
  # drive an app
  # this Mac does not have is worse than no skill at all — the workshop's
  # `docs/agent-surface.md`. So the ROOM passes the switch and installs
  # nothing when it is off, while flake.nix passes nothing and takes the default
  # — the `.#tool-skills` check therefore covers every name whatever any one
  # machine turns on, which is the point: a name that rots in trill's output has
  # to fail before a merge, not on the first person who switches the room on.
  # ⚠️ "Before a merge" means a Mac: CI checks this on Linux, where the null
  # below drops trill out entirely. flake.nix's comment above `.#tool-skills`
  # is where that is written down.
  #
  # A null `drv` is the other gate, and it is a platform fact rather than a
  # choice: trill's flake outputs darwin systems only, while this repo's
  # `packages` and `checks` both span allSystems, so flake.nix hands us `null`
  # on Linux and the entry drops out rather than breaking the eval.
  toolSkills = [
    {
      drv = scruff-skill;
      names = [
        "scruff"
        "handoff"
      ];
    }
    {
      drv = trill-skill;
      enable = trillEnabled;
      names = [ "trill" ];
    }
  ];

  # Both the install list and the check below are built from this, so a skill
  # can never be installed from a name the check did not prove.
  active = lib.filter (t: t.drv != null && (t.enable or true)) toolSkills;

  # Flattened to one entry per skill, so the fan-out in the room is a plain
  # product of clients × skills.
  toolSkillList = lib.concatMap (
    t:
    map (name: {
      inherit name;
      inherit (t) drv;
    }) t.names
  ) active;

  # The names above are unverifiable at EVAL time and entirely checkable at
  # BUILD time, and the difference is the whole of this derivation.
  # ../lib/checked-ref.nix is that difference, written out once; what belongs
  # HERE is which name is the promise.
  #
  # `SKILL.md` is what gets CHECKED and the folder is what gets INSTALLED,
  # because the family standard (the workshop's `docs/agent-surface.md`) is
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
