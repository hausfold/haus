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
# statusline are still installed by modules/core (a system profile), and the
# client packages, instructions/skill files and per-client hook wiring by
# modules/terminal (a home profile) — both now gated on THIS room's switch. Those
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

  # What this machine actually installs: the written list, gated on the room.
  # Every check below is about the machine rather than about the text, so they
  # all read this — a desktop naming three clients with the room switched off
  # installs none, and must not be refused for it.
  clients = config.haus._ai.clients;

  # nixpkgs ships the three it has for aarch64-darwin only. That is the whole
  # rice's platform since 26.11 dropped x86_64-darwin, so this never fires today
  # — but it is the difference between a named refusal and an install that
  # silently does nothing, which is exactly the dead-pane failure `ai.clients`
  # exists to end. (The `lib.meta.availableOn` guard it replaces did skip
  # silently.)
  #
  # A `null` in the table is not "unavailable": it is a client nixpkgs has no
  # derivation for, which this room installs from Homebrew below. Asking
  # `availableOn` about a null throws, so the filter drops them first.
  unavailableClients = lib.filter (
    c: agentPackages.${c} != null && !lib.meta.availableOn pkgs.stdenv.hostPlatform agentPackages.${c}
  ) clients;

  # The clients that come from Homebrew instead of nixpkgs, as roster entries —
  # the same shape bar uses for SketchyBar: a fully-qualified formula, plus the
  # tap declared beside it. Both halves, because `brew bundle` resolving a
  # qualified name is not the same thing as the tap being present, and the
  # rebuild that finds out is a fresh machine's. mkDefault on the formula so a
  # host that spells it its own way (a pinned tap, a local build) keeps its
  # version rather than colliding with this one.
  brewedClients = {
    jcode.brew = lib.mkDefault "1jehuang/jcode/jcode";
  };
  brewedClientTaps = {
    jcode = "1jehuang/jcode";
  };

  # Whether this machine actually SPAWNS agents. The room being on is not enough:
  # `ai.clients = [ ]` is a machine the rice installs no client on, and a
  # chord that spawns nothing is the dead-pane failure again, one layer up. So
  # this is what the terminal's chords and the launcher's Spawn Agent follow —
  # the same gate both used before this room existed.
  spawnable = cfg.enable && clients != [ ];

  # The bar is a different question, and answering it with `spawnable` was
  # wrong: `ai.clients = [ ]` means the RICE installs no client, not that no
  # agent runs here. `agent-state` — the pill's only writer — follows
  # `ai.enable` alone (modules/core), and terminal writes every client's
  # instructions and hooks on exactly that machine, by name, for exactly this
  # case. A Claude Code from npm reports its panes there and the pill works, so
  # dropping it would be the dead-pill failure with the sign flipped.
  reportable = cfg.enable;

  # Every address that asked for the agents pill, on either bar. Both are read
  # because `contributed` filters both (modules/bar/default.nix), and a warning
  # that only knew about the menu bar would leave the second one silent — the
  # exact failure this warning exists to end.
  pillAsks =
    lib.optional config.haus.bar.items.agents "haus.bar.items.agents"
    ++ lib.optional (
      config.haus.bar.bottom.enable && config.haus.bar.bottom.items.agents != false
    ) "haus.bar.bottom.items.agents";
in
{
  # ---- what the room asks of itself -----------------------------------------
  # These were terminal's, because terminal was where the agent options happened to
  # be read. They are the AI room's invariants: they name only `haus.ai.*`,
  # and they must fail the rebuild on a machine that has no terminal room at all.
  assertions = [
    {
      assertion = lib.elem cfg.default clients || clients == [ ];
      message =
        "haus.ai.default = \"${cfg.default}\" is not in haus.ai.clients "
        + "(${lib.concatStringsSep ", " clients}). Pounce's Spawn Agent would create the "
        + "worktree, open the pane, and only then find no ${cfg.default} on PATH — leaving a "
        + "dead pane and a worktree to reap. Add it to ai.clients, or point ai.default "
        + "at one you install.";
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

  # ---- the clients nixpkgs doesn't build --------------------------------------
  # A roster entry rather than a bare `homebrew.brews` line, for the reason the
  # roster exists: a host that also declares jcode (as this machine's did while
  # it was a hand-installed experiment) MERGES on the shared id instead of
  # installing it twice. Keyed off the resolved client list, so a machine that
  # doesn't name jcode never taps a tap for it.
  haus.roster = lib.filterAttrs (id: _: lib.elem id clients) brewedClients;
  homebrew.taps = lib.attrValues (lib.filterAttrs (id: _: lib.elem id clients) brewedClientTaps);

  # ---- what the room contributes to other rooms -------------------------------
  # One write per extension point. Every value here is a fact about the AI room;
  # how it is presented is the receiving room's business, and each of them draws
  # nothing at all when it is itself switched off. That is the whole seam: no
  # room reads `config.haus.ai.*` to decide what to draw any more.
  haus._contrib = {
    # Development — the terminal binds ⌃⌥⇧A (the resident agent) and aliases
    # `c`, and pounce renders the same table onto its Terminal cards. The LANE
    # chord is pounce's own (⌘↵, Ghostty-scoped → `cmd:lane-here`); it was
    # windows' ⌃⌘A, through a _contrib.windows.agents that no longer exists.
    development.agents = {
      enable = spawnable;
      inherit (cfg) default;
    };

    # Bar — the `agents` paw. Still opt-in per host (`haus.bar.items.agents`);
    # this only says whether anything on this machine writes pane state for it.
    bar.agents.enable = reportable;

    # Launcher — Spawn Agent, and the Agent Worktrees cards on the Tips page.
    launcher.agents = {
      enable = spawnable;
      inherit (cfg) default;
    };
  };
}
