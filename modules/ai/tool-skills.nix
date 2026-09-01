# The agent skills that OTHER hausfold tools ship, and the one derivation that
# proves the names below are real.
#
# A tool's `<tool>-skill` derivation lays out `$out/<skill-name>/SKILL.md` (the
# family standard, the workshop's `docs/agent-surface.md`), and a tool may
# ship more than one: scruff ships `scruff` (drive the lane lifecycle) and `handoff`
# (write the brief a `scruff spawn --prompt-file` lane opens on), factory ships
# `factory` (the merge verbs) and `nightshift` (the loop that drives them).
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
  factory-skill,
  nebelung-skill ? null,
  trill-skill ? null,
  trillEnabled ? true,
  pounce-skill ? null,
  pounceEnabled ? true,
  perch-skill ? null,
  perchEnabled ? true,
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
  # choice: trill's, pounce's and perch's flakes output darwin systems only,
  # while this repo's `packages` and `checks` both span allSystems, so flake.nix
  # hands us `null` on Linux and those entries drop out rather than breaking the
  # eval. nebelung outputs all four systems, so it is null only against a lock
  # older than its skill.
  toolSkills = [
    {
      drv = scruff-skill;
      names = [
        "scruff"
        "handoff"
      ];
    }
    # factory ships two skills and they are not two copies of one: `factory`
    # teaches the verbs (what to run when the user says "merge the safe PRs"),
    # `nightshift` teaches the LOOP that drives them — the cadence, the fixer
    # cap, what to do with each line a pass printed. The tool is one pass at a
    # time on purpose, so the thing that decides to call it again is judgement
    # rather than a flag, and that judgement is what the second skill is.
    #
    # Ungated, like scruff's: the AI room puts `factory` on PATH on every
    # machine that has the room at all, so the skill is never teaching an agent
    # to drive a binary this Mac does not have. Whether a machine has a POLICY
    # to run it against is a `~/.config/factory/config.json` question, outside
    # this layer entirely — and `factory doctor` is what answers it.
    {
      drv = factory-skill;
      names = [
        "factory"
        "nightshift"
      ];
    }
    # nebelung is the one entry with no binary behind it, and it is ungated for
    # that reason: the palette is the machine's theme whatever rooms are on, so
    # there is no switch that could make this skill dishonest. Half of it is
    # rendered from `palette/*.hex.json` at build time, so the hexes an agent
    # quotes are THIS lock's, not a number copied once.
    {
      drv = nebelung-skill;
      names = [ "nebelung" ];
    }
    {
      drv = trill-skill;
      enable = trillEnabled;
      names = [ "trill" ];
    }
    # pounce and perch are the launcher and shelf rooms' apps, both off by
    # default, and the skill follows the ROOM rather than the binary — same
    # reasoning as trill's, and the same consequence: a machine running a
    # hand-installed pounce or perch with the room off gets no skill for it.
    {
      drv = pounce-skill;
      enable = pounceEnabled;
      names = [ "pounce" ];
    }
    {
      drv = perch-skill;
      enable = perchEnabled;
      names = [ "perch" ];
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
  #
  # The collision this file CANNOT catch is a host that hand-wires
  # `~/.claude/skills/<name>` itself: two definitions of one `home.file` path
  # are a home-manager *eval* conflict rather than a last-wins, so such a host
  # drops its own copy in the same rebuild that adds a name here. Every name in
  # the list lands in one shared per-client skills directory, which is what
  # makes that possible at all.
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
