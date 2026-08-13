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
  cfg = config.haus.agents;
  agentPackages = import ../lib/agent-packages.nix pkgs;

  # nixpkgs ships all three for aarch64-darwin only. That is the whole rice's
  # platform since 26.11 dropped x86_64-darwin, so this never fires today — but
  # it is the difference between a named refusal and an install that silently
  # does nothing, which is exactly the dead-pane failure `agents.clients` exists
  # to end. (The `lib.meta.availableOn` guard it replaces did skip silently.)
  unavailableClients = lib.filter (
    c: !lib.meta.availableOn pkgs.stdenv.hostPlatform agentPackages.${c}
  ) cfg.clients;

  # Whether this machine actually runs agents. The room being on is not enough:
  # `agents.clients = [ ]` is a machine the rice installs no client on, and a
  # chord that spawns nothing is the dead-pane failure again, one layer up.
  running = cfg.enable && cfg.clients != [ ];
in
{
  # ---- what the room asks of itself -----------------------------------------
  # These were hearth's, because hearth was where the agent options happened to
  # be read. They are the AI room's invariants: they name only `haus.agents.*`,
  # and they must fail the rebuild on a machine that has no terminal room at all.
  assertions = [
    {
      assertion = lib.elem cfg.default cfg.clients || cfg.clients == [ ];
      message =
        "haus.agents.default = \"${cfg.default}\" is not in haus.agents.clients "
        + "(${lib.concatStringsSep ", " cfg.clients}). Pounce's Spawn Agent would create the "
        + "worktree, open the pane, and only then find no ${cfg.default} on PATH — leaving a "
        + "dead pane and a worktree to reap. Add it to agents.clients, or point agents.default "
        + "at one you install.";
    }
    {
      assertion = cfg.clients == [ ] || cfg.enable;
      message =
        "haus.agents.clients is set (${lib.concatStringsSep ", " cfg.clients}) but "
        + "haus.agents.enable is off, so there is no `holt` to make a worktree, park it, or "
        + "resume it. Turn the room on, or empty agents.clients.";
    }
    {
      assertion = unavailableClients == [ ];
      message =
        "haus.agents.clients names ${lib.concatStringsSep ", " unavailableClients}, which "
        + "nixpkgs does not build for ${pkgs.stdenv.hostPlatform.system}. Installing nothing "
        + "would only move the failure into the agent pane; drop it from agents.clients.";
    }
  ];

  # A pill with no agents to count is not a smaller feature, it is a dead one —
  # and the failure is silent, which is the whole reason this room warns by name
  # rather than quietly dropping the item. Not an assertion: the bar is still
  # correct without it, and a rebuild that refuses over a pill would be worse
  # than the pill being absent.
  warnings = lib.optional (config.haus.sill.items.agents && !running) (
    "haus.sill.items.agents is on but the AI room has no client to report on "
    + (
      if cfg.enable then
        "(haus.agents.clients is empty)"
      else
        "(haus.agents.enable is off — it was haus.developer.agents.enable before 2026-08-13)"
    )
    + ". The pill would stay dormant forever, so the bar leaves it out."
  );

  # ---- what the room contributes to other rooms -------------------------------
  # One write per extension point. Every value here is a fact about the AI room;
  # how it is presented is the receiving room's business, and each of them draws
  # nothing at all when it is itself switched off. That is the whole seam: no
  # room reads `config.haus.agents.*` to decide what to draw any more.
  haus._contrib = {
    # Development — the terminal binds ⌘A / Super-a and aliases `c`, and pounce
    # renders the same table onto its Terminal cards.
    development.agents = {
      enable = running;
      inherit (cfg) default clients;
    };

    # Bar — the `agents` paw. Still opt-in per host (`haus.sill.items.agents`);
    # this only says whether there is anything behind it.
    bar.agents.enable = running;

    # Launcher — Spawn Agent, and the Agent Worktrees cards on the Tips page.
    launcher.agents = {
      enable = running;
      inherit (cfg) default;
    };
  };
}
