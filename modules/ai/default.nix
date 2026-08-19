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
# The payload lives here too, as of 2026-08-19. It used to be hosted by the
# rooms that happened to own the two PROFILES it needs — `holt`, the statusline
# pair and `agent-state` by modules/core (a system profile), the instructions
# preamble, the `haus` skill and its `this-machine.md` renderer by
# modules/terminal (a home one) — each gated on this room's switch from a
# distance. That was step 2's deliberate deferral: moving a package between
# profiles is an install change rather than a refactor, so it waited for
# `desktop-projection` (step 4) and a derivation comparison to prove it free.
#
# The home half was expected to be the hard part, on the theory that terminal
# owns `home-manager.users.<name>` and two modules writing one user's profile
# would silently merge. It does not: home-manager merges the two `home.file`
# attrsets, and a collision on a path is an ERROR rather than a last-wins —
# which is the property that makes splitting them safe. Measured with a
# throwaway `home.file` from this module before anything was moved.
#
# What terminal keeps is its own business, not a leftover: the client packages
# a pane needs on PATH, the dotfiles it themes for clients whether or not this
# room is on, and the two activation blocks that merge into a client's
# user-editable JSON.
{
  config,
  lib,
  pkgs,
  username,
  ...
}@args:

let
  cfg = config.haus.ai;
  agentPackages = import ../lib/agent-packages.nix pkgs;

  # This room's own resolved client list, under the name the moved blocks below
  # already used. `clients` (just below) is the same value; both names are kept
  # because the assertions read one and the home payload the other.
  agentClients = config.haus._ai.clients;

  # `hostname` is a specialArg of the full builders (mkHaus and friends), and it
  # is NOT one of a bare `darwinModules.*` import — a consumer wiring
  # `darwinModules.windows` into their own darwinSystem passes whatever they
  # like. This room is in `standaloneModule`'s foundation, so it is evaluated by
  # EVERY export; naming `hostname` in the argument set above would therefore
  # make it mandatory for all of them, and a consumer who never asked for the AI
  # room would get `error: attribute 'hostname' missing` from the tiling module.
  # It is read out of `args` instead, with a fallback, because the only thing it
  # feeds is prose in `this-machine.md` — a skill file that says "this Mac"
  # instead of a name is strictly better than a room nobody imported refusing to
  # evaluate. `networking.hostName` is the second choice rather than the first
  # because it defaults to null (not unset), so it needs the explicit test that
  # an `or` chain would not give it.
  hostname =
    args.hostname or (
      if (config.networking.hostName or null) != null then config.networking.hostName else "this Mac"
    );

  # What this machine actually installs: the written list, gated on the room.
  # Every check below is about the machine rather than about the text, so they
  # all read this — a desktop naming three clients with the room switched off
  # installs none, and must not be refused for it.
  clients = config.haus._ai.clients;

  # nixpkgs ships all three for aarch64-darwin only. That is the whole rice's
  # platform since 26.11 dropped x86_64-darwin, so this never fires today
  # — but it is the difference between a named refusal and an install that
  # silently does nothing, which is exactly the dead-pane failure `ai.clients`
  # exists to end. (The `lib.meta.availableOn` guard it replaces did skip
  # silently.)
  unavailableClients = lib.filter (
    c: !lib.meta.availableOn pkgs.stdenv.hostPlatform agentPackages.${c}
  ) clients;

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
  # ---- the payload: what lands in a home -------------------------------------
  # Moved here from modules/terminal on 2026-08-19, with the path table, the
  # instructions preamble and the whole `this-machine.md` renderer.
  # The one sentence in the generated agent instructions that names the lane
  # chord. These files are what an agent BELIEVES about the machine it is on, so
  # a wrong chord here is worse than none: the agent will confidently tell its
  # user to press a key that does nothing.
  laneChordProse = ''
    `Cmd Return` (⌘↵) — pressed from any Ghostty window, a terminal pane or
        another agent's lane alike — spawns each agent into its own isolated
        checkout on a `worktree-<name>` branch, in its own window, so parallel
        agents never fight over a single checkout.'';

  # One client id → where that client keeps the two files the rice ships into a
  # home: the always-on instructions (`haus.ai.instructions`) and the `haus`
  # skill (`haus.ai.skill`). Every client has both slots under a different
  # name, which is the whole reason those options are named for the room and not
  # for Claude.
  #
  # Verified against the clients themselves rather than their docs, because the
  # cost of a wrong path here is silent — a file written where nothing reads it
  # looks exactly like a working install:
  #
  #   codex debug prompt-input   → ~/.codex/AGENTS.md and ~/.codex/skills/*
  #                                appear in the model-visible prompt
  #   opencode debug skill       → lists ~/.config/opencode/skills/*
  #
  # OpenCode also scans `~/.claude/skills` for Claude Code compatibility, so a
  # machine running both clients has two copies of this skill in its reach. That
  # is safe on purpose: the same probe shows opencode deduplicating by frontmatter
  # `name` and preferring its OWN directory, so the skill is offered once. (Its
  # docs only say "ensure skill names are unique", which is why this was probed.)
  agentHomes = {
    claude = {
      instructions = ".claude/CLAUDE.md";
      skills = ".claude/skills";
    };
    codex = {
      instructions = ".codex/AGENTS.md";
      skills = ".codex/skills";
    };
    opencode = {
      instructions = ".config/opencode/AGENTS.md";
      skills = ".config/opencode/skills";
    };
  };

  # Rice-owned preamble for each client's instructions file. The rice ships
  # `holt` (core) on PATH to every machine, and agent worktrees live OUTSIDE the
  # repo tree (~/.cache/claude-worktrees/…), so a worktree agent's instructions
  # walk never reaches the project/workshop AGENTS.md — only THIS file + the
  # repo's own checked-out one are guaranteed read. So the general `holt`
  # etiquette every agent needs travels HERE, WITH the tool — not just in the
  # workshop repo end users don't have. Prepended to the host's own
  # `haus.ai.instructions`.
  #
  # A function of the client, because the only thing that differs between the
  # three copies is which paths they name — and naming the wrong one is worse
  # than naming none: a Codex pane told to edit `~/.claude/CLAUDE.md` would
  # change a file nothing it runs will ever read.
  #
  # It opens by naming itself as generated, because the file the agent is
  # reading is a read-only store symlink: an agent asked to "add this to your
  # global memory" otherwise edits it (fails), or replaces the symlink with a
  # real file whose contents die at the next rebuild. The scope has to be
  # exact — a host may wire individual skills as out-of-store symlinks, and each
  # client owns its own settings file, so a blanket "this directory is
  # nix-managed" would be wrong.
  clientScopeNote = {
    claude = "`settings.json` is Claude Code's own, and a host may wire individual skills as out-of-store symlinks";
    codex = "`config.toml` and `hooks.json` are Codex's own, and a host may wire individual skills as out-of-store symlinks";
    opencode = "`opencode.json` is OpenCode's own, and a host may wire individual skills or plugins as out-of-store symlinks";
  };

  holtGuidance = client: ''
    # This file is generated by Nix — don't edit it here

    `~/${agentHomes.${client}.instructions}` is a read-only symlink into the Nix
    store, rendered from `haus.ai.instructions` in this machine's host file
    (`~/.config/nix/hosts/${hostname}/default.nix`, unless `HAUS_CONSUMER` says
    otherwise). Change it there, then `haus rebuild` — a hand-edit here either
    fails outright or is reverted by the next rebuild. Every coding agent this
    machine installs gets the same text at its own path, so a change lands for
    all of them at once.

    The same goes for `~/${agentHomes.${client}.skills}/haus/`, generated from
    the haus revision this machine pins (`haus update` regenerates it). It does
    NOT go for everything beside them: ${clientScopeNote.${client}} that you can
    edit live with no rebuild. `ls -l` the path before assuming which kind it is.

    # Agent worktrees & the `holt` tool

    `holt` (shipped by haus, on PATH) manages **agent worktrees** for any
    git repo. ${laneChordProse} Closing a pane never loses work — uncommitted
    edits are parked as
    a `wip:` commit and only already-merged branches are reaped. Resume a parked
    session with `holt` (lists every worktree across all repos) or
    `holt <name>`; sweep landed ones on demand with `holt reap`.

    Checkouts live under `~/.cache/claude-worktrees/<repo>/<name>` whichever
    client you are — the path name is historical, not a claim about who owns it.

    **Cross-repo work uses `holt child`, never a raw `git worktree add`.** To
    work on a DIFFERENT repo than the pane you're in (e.g. a parent pane editing
    a sub-repo), create the worktree with:

        cd "$(holt child /path/to/other/repo)"

    A raw `git worktree add` never touches the registry, so the statusline HUD
    never learns to query that repo's GitHub — the worktree and its PR go
    **invisible in the bar** (they only surface, unattributed with a `◇`, in the
    `~` home pane). `holt child` does the same worktree add but registers it
    under the spawning pane, so its PR shows as a child row where you're working.

    **Setting work aside uses `holt park`, never `git stash`.** The stash stack
    is NOT per-worktree — it lives in the shared `.git` dir, so every agent
    worktree of a repo and the main checkout push and pop the SAME stack, and
    parallel agents routinely pop each other's entries into a tree that never
    asked for them. `holt park [label]` instead commits the whole dirty tree as
    one `wip:` commit on the branch only this pane has checked out (the same
    thing the remove hook does on pane close); `holt unpark` rewinds it, putting
    those changes back uncommitted. It refuses to unpark a wip commit you've
    already pushed, so it can never turn into a force-push.

    **A session that keeps committing after its PR merged needs `holt reship`.**
    GitHub deletes the head branch on merge, so those later commits have no
    remote and no PR — and `holt` deliberately won't reap that branch. `holt`
    marks it `+N` in the state column (`live+3`), the bar shows an orange `N^`
    instead of the ⏏ it used to, and `holt reship [name]` pushes the branch and
    opens the follow-up PR.

    Full guide: https://hausfold.co/docs/haus/rooms/ai/

  '';

  # ---- the haus skill: an agent that can change this machine safely -----
  # A Mac whose config is declarative is the one kind of machine an agent can
  # reconfigure without it being reckless: `haus rebuild` builds before it
  # switches, so a broken edit never reaches the running system, and `haus
  # rollback` undoes an applied one atomically. What was missing was the
  # knowledge — a model left to guess reaches for `brew install` and dotfiles,
  # both of which the next rebuild overwrites, or invents a `haus.*` option
  # that doesn't exist.
  #
  # So the rice ships the knowledge with itself. The option reference inside the
  # skill is RENDERED from this revision's module system (agents/skill.nix), and
  # `this-machine.md` below is rendered from this host's own evaluated config —
  # neither can drift, and `haus update` refreshes both along with the rice.
  #
  # ONE derivation, installed into each client's own skills directory (see
  # agentHomes): the knowledge is about this machine, not about who's reading.
  hausSkill = import ./agents/skill.nix { inherit pkgs; };

  # ---- what lands in each installed client's home ---------------------------
  #
  # Keyed off ai.clients, not "always Claude": writing ~/.claude/CLAUDE.md on
  # a codex-only machine is a file nothing reads, and NOT writing
  # ~/.codex/AGENTS.md on one is the half-truth this fan-out ends — the pane
  # spawned with none of the context the same machine hands Claude.
  #
  # Empty instructions = nothing written for anyone, so a hand-managed
  # instructions file is never clobbered just to inject the rice's note.
  # Who the two files below are written for. Normally `ai.clients` — but an
  # EMPTY list doesn't mean "no agent ever runs here", it means the rice installs
  # none — either nothing named any client, or the AI room is switched off, which
  # empties the resolved list whatever a desktop wrote (`haus._ai.clients`). A
  # machine like that can still have Claude Code from npm or Codex from brew, and
  # before this room existed both files were written unconditionally. So with
  # nothing named, write for every client we know — they are inert markdown, and
  # a skill nothing reads is much cheaper than an agent inventing option names.
  fileClients = if agentClients == [ ] then lib.attrNames agentHomes else agentClients;

  agentInstructionFiles = lib.optionalAttrs (cfg.instructions != "") (
    lib.listToAttrs (
      map (
        client:
        lib.nameValuePair agentHomes.${client}.instructions {
          text = holtGuidance client + cfg.instructions;
        }
      ) fileClients
    )
  );

  # The skill, installed file-by-file rather than as one directory symlink so
  # this-machine.md — rendered from THIS host, not from the rice — can sit inside
  # the same skill alongside the store-built parts.
  #
  # The starter instruction pair for ~/.config/nix rides along INSIDE the skill
  # rather than being written into that repo: it's the user's own git repo, and a
  # read-only store symlink inside it would be a thing they can't commit. `haus
  # doctor` points at these paths, and the skill tells the agent to offer the
  # copy — so they land as real, editable files or not at all. Two files, because
  # that's the shape every repo in the family uses: AGENTS.md carries the rules
  # (Codex, OpenCode, Cursor, Copilot and anything else that speaks agents.md
  # read it natively), and CLAUDE.md is a bare @AGENTS.md import for the one
  # client that reads only that name. Copying just the CLAUDE.md would leave a
  # Codex or OpenCode pane in that repo with no instructions at all.
  agentSkillFiles = lib.optionalAttrs cfg.skill (
    lib.mergeAttrsList (
      map (
        client:
        let
          dir = "${agentHomes.${client}.skills}/haus";
        in
        {
          "${dir}/SKILL.md".source = "${hausSkill}/SKILL.md";
          "${dir}/references/options.md".source = "${hausSkill}/references/options.md";
          # The routing layer ABOVE options.md: which room a sentence belongs
          # to, and whether that room has a runtime verb (`focus on`) as well as
          # options. Rendered from the room registry rather than the module
          # system — see agents/skill.nix.
          "${dir}/references/rooms.md".source = "${hausSkill}/references/rooms.md";
          "${dir}/references/recipes.md".source = "${hausSkill}/references/recipes.md";
          "${dir}/references/this-machine.md".text = thisMachine;
          "${dir}/consumer-AGENTS.md".source = "${hausSkill}/consumer-AGENTS.md";
          "${dir}/consumer-CLAUDE.md".source = "${hausSkill}/consumer-CLAUDE.md";
        }
      ) fileClients
    )
  );

  onOff = b: if b then "on" else "off";

  # `toString 1.0` is "1.000000", which reads like a precision the option
  # doesn't have — and an agent copying it back into a host file writes noise.
  trimZeros = s: if lib.hasSuffix "0" s then trimZeros (lib.removeSuffix "0" s) else s;
  num = n: if lib.isFloat n then lib.removeSuffix "." (trimZeros (toString n)) else toString n;

  # Whichever TCC-protected universalaccess keys the host set directly. Named
  # here because it's the one thing that makes an AGENT's rebuild behave
  # differently from the user's own (see haus rebuild's guard), so the skill
  # should be able to see it without evaluating anything.
  rawUniversalaccess = lib.attrNames (
    lib.filterAttrs (_: v: v != null) config.system.defaults.universalaccess
  );

  # Two halves of the same roster: what has a leader key (the table an agent
  # reads before picking a free letter) and what doesn't (installed, but nothing
  # to press). The install-only half keeps its attr id, since with no key and
  # often no `name` that id is the only handle an edit can grab.
  launcherRoster = lib.sort (a: b: a.order < b.order) config.haus._launchers;
  # Where an entry comes from, in one clause — the question a comment in the host
  # file used to answer badly. Four sources plus `installedBy` for the rice's own
  # bundles; "· cask x" alone would quietly describe everything else as unmanaged.
  sourceOf =
    a:
    if a.cask != null then
      " · cask `${a.cask}`"
    else if a.brew != null then
      " · brew `${a.brew}`"
    else if a.package != null then
      " · nixpkgs (${a.scope} scope)"
    else if a.appStoreId != null then
      " · App Store `${toString a.appStoreId}`"
    else if a.installedBy != null then
      " · installed by `${a.installedBy}`"
    else
      "";
  installOnlyRoster = lib.sort (a: b: a.id < b.id) (
    lib.mapAttrsToList (id: app: { inherit id app; }) (
      lib.filterAttrs (_: app: app.enable && app.key == null) config.haus.roster
    )
  );

  thisMachine = ''
    # This machine

    Rendered from `${hostname}`'s own evaluated configuration when that
    configuration was built. Where this disagrees with something you remember,
    this file is right.

    | | |
    |---|---|
    | hostname | `${hostname}` |
    | user | `${username}` |
    | host file | `~/.config/nix/hosts/${hostname}/default.nix` |
    | config flake | `~/.config/nix` (unless `HAUS_CONSUMER` says otherwise) |
    | haus version | `${lib.fileContents ../../VERSION}` |

    Run `haus status` for the pinned revision and whether it's behind upstream.

    ## Rooms

    | room | what it is | state |
    |---|---|---|
    | windows | window tiling | ${onOff config.haus.windows.enable} |
    | bar | the menu bar | ${onOff config.haus.bar.enable} |
    | pounce | the command palette | ${onOff config.haus.launcher.enable} |
    | focus | Focus / Do Not Disturb | ${onOff config.haus.focus.enable} |
    | perch | the notch file shelf | ${onOff config.haus.shelf.enable} |
    | snippets | text expansion | ${onOff config.haus.snippets.enable} |
    | developer | the dev toolbelt | ${onOff config.haus.developer.enable} |

    A room that's off means its options do nothing until you turn it on — say so
    rather than silently enabling a room to satisfy a small request.

    ## Look

    - theme: `${config.haus.theme.flavor}` flavor, `${config.haus.theme.accent}` accent, `${config.haus.theme.contrast}` contrast
    - `haus.ui.scale` = `${num config.haus.ui.scale}`
    - terminal font: ${config.haus.fonts.mono.name} at ${toString config.haus.fonts.mono.size}pt

    ## Keys

    - leader: `${config.haus.keys.leader}`
    - palette: `${config.haus.keys.palette}`
    - window navigation: `${config.haus.keys.windowNav}`

    ## Apps on the roster

    Leader key → app. Taken keys are taken; pick an unused one when adding.

    ${
      if launcherRoster == [ ] then
        "*(none declared)*"
      else
        lib.concatMapStringsSep "\n" (
          a:
          "- `${a.key}` → ${a.name}"
          + (
            let
              ws = config.haus._appWorkspace.${a.id} or null;
            in
            if ws == null then " *(launcher-only)*" else " (workspace `${ws}`)"
          )
          + sourceOf a
        ) launcherRoster
    }

    ## Also declared, without a leader key

    Same `haus.roster`, no keyboard binding — apps reached another way,
    haus's own (installed by a module rather than a package manager), and
    the fonts and command-line tools that live in the one list too. Adding a
    `key` to any of these is what puts it on the launcher.

    ${
      if installOnlyRoster == [ ] then
        "*(none)*"
      else
        lib.concatMapStringsSep "\n" (
          e:
          "- `${e.id}`"
          + (if e.app.name == null then "" else " → ${e.app.name}")
          + (if sourceOf e.app == "" then " · not installed by haus" else sourceOf e.app)
        ) installOnlyRoster
    }

    ## Rebuild hazards on this host

    ${
      if rawUniversalaccess == [ ] then
        "None. `haus rebuild` will run for you."
      else
        ''
          ⚠ This host sets `system.defaults.universalaccess` directly (${lib.concatStringsSep ", " rawUniversalaccess}).

          That domain is TCC-protected, nix-darwin writes it unguarded, and the
          write needs Full Disk Access on whichever app your session runs under.
          A failure there aborts activation partway and skips every background
          service haus installs.

          So on this host `haus rebuild` checks first, and refuses if this
          session can't write that domain — for anyone, not just an agent, since
          the grant follows the app rather than the person.

          The fix is usually to move those keys to `haus.accessibility.*`, which
          reaches every key in that domain measured to work and writes them
          guarded: a missing grant costs the setting and nothing else, and the
          rebuild runs from anywhere. Otherwise: make the edit, then ask the user
          to run `haus rebuild` in their own terminal. `haus doctor` reports
          whether the grant is present here, and `haus plan` says so before a
          rebuild rather than after.
        ''
    }
  '';
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

  # ---- the payload: the system profile ---------------------------------------
  # `with pkgs` because that is the shape modules/core wrote these in and the
  # comments below name bare `holt`. Nothing here is conditional on another
  # room — a machine with no terminal and no bar still gets a working `holt`
  # and a working `agent-state`.
  environment.systemPackages = lib.mkIf cfg.enable (
    with pkgs;
    [
      # holt — agent worktrees, its own product now (hausfold/holt, taken as
      # a flake input). Every caller the rice owns is on it: terminal's
      # ⌘↵ runs `holt new`, pounce's Spawn Agent goes through `holt spawn`, and
      # the Claude Code WorktreeCreate/WorktreeRemove hooks — which terminal
      # DECLARES into ~/.claude/settings.json and re-asserts on every rebuild
      # (see modules/terminal, home.activation.claudeCodeSettings) — point at
      # `holt hook create` / `holt hook remove`. Its bash predecessor `wt.sh`
      # has been retired entirely; there is no fallback to roll back to.
      holt

      # `claude-statusline` — the agent-worktree HUD for Claude Code's status bar
      # (terminal's claudeCodeSettings points the `statusLine` key here). Row 1 is
      # THIS session's worktree name + one status token (⏏ purge / N^ commits —
      # blue when unmerged, orange when they landed AFTER the PR merged and no PR
      # covers them / +A -D uncommitted); rows below list sister `holt` worktrees across
      # ALL repos, with GitHub PR state. Cheap local git runs in the render path;
      # the cross-repo + `gh` enumeration is done detached by the companion
      # `claude-statusline-refresh` and cached (stale-while-revalidate), so the bar
      # never blocks. Reads `holt`'s registry — same agent-worktree flow, same home.
      # It doubles as the writer for bar's `claudeUsage` pill: Claude Code hands
      # every render the account's 5-hour + weekly rate-limit percentages, so the
      # render path stashes them to ~/.cache/claude-statusline/usage.tsv — the
      # cheapest possible source, with no keychain read and nothing polling.
      (writeShellScriptBin "claude-statusline" (builtins.readFile ./statusline.sh))
      (writeShellScriptBin "claude-statusline-refresh" (builtins.readFile ./statusline-refresh.sh))

      # `agent-state` — the one writer of agent state, feeding bar's `agents`
      # paw. BYTE-FOR-BYTE the script bar also
      # installs as ~/.config/sketchybar/plugins/agents-hook.sh (read from there,
      # so the two can never drift); this copy exists only to give it a stable
      # name on PATH. Claude Code's hooks point at the sketchybar path because the
      # user's own settings.json wires them, but the Codex and Opencode wirings
      # terminal writes are client config files with no business knowing where a bar
      # keeps its plugins — they call
      # `agent-state <working|waiting|idle|remove> <client>` instead.
      (writeShellScriptBin "agent-state" (builtins.readFile ../bar/sketchybar/plugins/agents-hook.sh))
    ]
  );

  # The two files this room ships into every installed client's home. Written
  # into the SAME user modules/terminal writes; home-manager merges the two
  # attrsets, and a collision on one path would be an error rather than a silent
  # last-wins — which is what makes splitting them safe.
  home-manager.users.${username}.home.file = agentInstructionFiles // agentSkillFiles;

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
