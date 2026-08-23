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
  #
  # LISTING what a tool ships needs `builtins.readDir` on a store output —
  # import-from-derivation, which would force a build every time somebody runs
  # `haus get` to READ their config. ASSERTING that a listed name is there needs
  # no eval-time read at all: copying the listed folders through one
  # `runCommand` makes each name a build DEPENDENCY rather than a promise.
  #
  # Without it a name the pinned revision doesn't ship installs a DANGLING
  # symlink in the user's home, silently — eval, `nix flake check` and the
  # home-files build all green, because a home.file source pointing inside a
  # store output is never existence-checked. You find it the way you find any
  # broken pointer: months later, wondering why the agent never learned the tool.
  #
  # Third site of one class, and the second fix of it copied from the first:
  # modules/theme/ports.nix does exactly this for a nebelung port path, and
  # terminal's `glowPlugin` for glow's. `SKILL.md` rather than the directory,
  # since the family standard is what the name is a promise about, and an empty
  # folder would satisfy `-e`.
  checked = pkgs.runCommand "haus-tool-skills" { } (
    ''
      mkdir -p $out
    ''
    + lib.concatMapStrings (skill: ''
      if [ ! -e "${skill.drv}/${skill.name}/SKILL.md" ]; then
        echo "haus.ai.skill: ${skill.drv.name} ships no skill named '${skill.name}'." >&2
        echo "  expected ${skill.drv}/${skill.name}/SKILL.md" >&2
        # Three remedies, because they belong to three different people — the
        # question modules/theme/ports.nix asks out loud: who can this check
        # fail on? A haus AUTHOR adds a name here before the lock bump that
        # carries it, or after a tool retires one. A CONSUMER of haus holds the
        # tool input transitively and can do neither, so name the lever that
        # is theirs.
        echo "Fix it whichever way is yours:" >&2
        echo "  · nix flake update <tool> — the skill may land in a revision" >&2
        echo "    newer than the one this lock pins" >&2
        echo "  · drop the name from modules/ai/tool-skills.nix" >&2
        echo "  · haus.ai.skill = false, to install no agent skills at all" >&2
        exit 1
      fi
      # `mkdir` first, so two tools claiming one skill name fail here rather
      # than nesting into $out/<name>/<name>. They would collide in the room's
      # `listToAttrs` too; failing at the earlier of the two is the honest one.
      mkdir "$out/${skill.name}"
      cp -R "${skill.drv}/${skill.name}/." "$out/${skill.name}/"
    '') toolSkillList
  );
in
{
  inherit toolSkillList checked;
}
