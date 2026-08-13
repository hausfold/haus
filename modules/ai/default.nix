# The AI room — coding agents, and everything the rice does to make them a
# first-class part of the machine rather than three binaries you happen to have.
#
# This is the first room declared as a CROSS-ROOM CAPABILITY (the contract is
# notes/rooms-desktops.md, "Rooms cooperate"). The room owns the capability: its
# switch, its clients, the `holt` worktree lifecycle and the files written into
# every client's home. What it adds to OTHER rooms — the terminal's agent
# chords, the bar's `agents` pill, the launcher's Spawn Agent — it adds through
# extension points those rooms declare (modules/lib/contrib.nix), so a machine
# without a bar loses the pill and keeps the agents, and turning agents on never
# switches a bar on.
#
# What is deliberately NOT here yet: the payload. `holt`, `agent-state` and the
# statusline are still installed by modules/den (a system profile), and the
# client packages, instructions/skill files and per-client hook wiring by
# modules/hearth (a home profile) — both now gated on THIS room's switch. Those
# are two different profiles with two different plumbings, and moving a package
# between them is an install change, not a refactor. Ownership moved; the code
# follows when there is a projection comparison to prove it moved for free.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.haus.ai;
  agentPackages = import ../lib/agent-packages.nix pkgs;

  # nixpkgs ships all three for aarch64-darwin only. That is the whole rice's
  # platform since 26.11 dropped x86_64-darwin, so this never fires today — but
  # it is the difference between a named refusal and an install that silently
  # does nothing, which is exactly the dead-pane failure `ai.clients` exists
  # to end. (The `lib.meta.availableOn` guard it replaces did skip silently.)
  unavailableClients = lib.filter (
    c: !lib.meta.availableOn pkgs.stdenv.hostPlatform agentPackages.${c}
  ) cfg.clients;

  # Whether this machine actually SPAWNS agents. The room being on is not enough:
  # `ai.clients = [ ]` is a machine the rice installs no client on, and a
  # chord that spawns nothing is the dead-pane failure again, one layer up. So
  # this is what the terminal's chords and the launcher's Spawn Agent follow —
  # the same gate both used before this room existed.
  spawnable = cfg.enable && cfg.clients != [ ];

  # The bar is a different question, and answering it with `spawnable` was
  # wrong: `ai.clients = [ ]` means the RICE installs no client, not that no
  # agent runs here. `agent-state` — the pill's only writer — follows
  # `ai.enable` alone (modules/den), and hearth writes every client's
  # instructions and hooks on exactly that machine, by name, for exactly this
  # case. A Claude Code from npm reports its panes there and the pill works, so
  # dropping it would be the dead-pill failure with the sign flipped.
  reportable = cfg.enable;

  # Every address that asked for the agents pill, on either bar. Both are read
  # because `contributed` filters both (modules/sill/default.nix), and a warning
  # that only knew about the menu bar would leave the second one silent — the
  # exact failure this warning exists to end.
  pillAsks =
    lib.optional config.haus.sill.items.agents "haus.sill.items.agents"
    ++ lib.optional (
      config.haus.sill.bottom.enable && config.haus.sill.bottom.items.agents != false
    ) "haus.sill.bottom.items.agents";
in
{
  # ---- what the room asks of itself -----------------------------------------
  # These were hearth's, because hearth was where the agent options happened to
  # be read. They are the AI room's invariants: they name only `haus.ai.*`,
  # and they must fail the rebuild on a machine that has no terminal room at all.
  assertions = [
    {
      assertion = lib.elem cfg.default cfg.clients || cfg.clients == [ ];
      message =
        "haus.ai.default = \"${cfg.default}\" is not in haus.ai.clients "
        + "(${lib.concatStringsSep ", " cfg.clients}). Pounce's Spawn Agent would create the "
        + "worktree, open the pane, and only then find no ${cfg.default} on PATH — leaving a "
        + "dead pane and a worktree to reap. Add it to ai.clients, or point ai.default "
        + "at one you install.";
    }
    {
      assertion = cfg.clients == [ ] || cfg.enable;
      message =
        "haus.ai.clients is set (${lib.concatStringsSep ", " cfg.clients}) but "
        + "haus.ai.enable is off, so there is no `holt` to make a worktree, park it, or "
        + "resume it. Turn the room on, or empty ai.clients.";
    }
    {
      assertion = unavailableClients == [ ];
      message =
        "haus.ai.clients names ${lib.concatStringsSep ", " unavailableClients}, which "
        + "nixpkgs does not build for ${pkgs.stdenv.hostPlatform.system}. Installing nothing "
        + "would only move the failure into the agent pane; drop it from ai.clients.";
    }
  ];

  # A pill with no room behind it is not a smaller feature, it is a dead one —
  # and the failure is silent, which is the whole reason this room warns by name
  # rather than quietly dropping the item. Not an assertion: the bar is still
  # correct without it, and a rebuild that refuses over a pill would be worse
  # than the pill being absent.
  warnings = lib.optional (pillAsks != [ ] && !reportable) (
    "${lib.concatStringsSep " and " pillAsks} asks for the agents pill, but the AI room is off "
    + "(haus.ai.enable). Nothing "
    + "writes agent-pane state on this machine, so the pill would stay dormant forever and the "
    + "bar leaves it out."
  );

  # ---- what the room contributes to other rooms -------------------------------
  # One write per extension point. Every value here is a fact about the AI room;
  # how it is presented is the receiving room's business, and each of them draws
  # nothing at all when it is itself switched off. That is the whole seam: no
  # room reads `config.haus.ai.*` to decide what to draw any more.
  haus._contrib = {
    # Development — the terminal binds ⌘A / Super-a and aliases `c`, and pounce
    # renders the same table onto its Terminal cards.
    development.agents = {
      enable = spawnable;
      inherit (cfg) default;
    };

    # Bar — the `agents` paw. Still opt-in per host (`haus.sill.items.agents`);
    # this only says whether anything on this machine writes pane state for it.
    bar.agents.enable = reportable;

    # Launcher — Spawn Agent, and the Agent Worktrees cards on the Tips page.
    launcher.agents = {
      enable = spawnable;
      inherit (cfg) default;
    };
  };
}
