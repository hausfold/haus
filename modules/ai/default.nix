# The AI room — coding agents, and everything the rice does to make them a
# first-class part of the machine rather than three binaries you happen to have.
#
# This is the first room declared as a CROSS-ROOM CAPABILITY (the contract is
# `docs/model.md`, "Rooms cooperate"). The room owns the capability: its
# switch, its clients, the `scruff` worktree lifecycle and the files written into
# every client's home. What it adds to OTHER rooms — the terminal's agent
# chords, the bar's `agents` pill, the launcher's Spawn Agent — it adds through
# extension points those rooms declare (modules/lib/contrib.nix), so a machine
# without a bar loses the pill and keeps the agents, and turning agents on never
# switches a bar on.
#
# The payload lives here too, as of 2026-08-19. It used to be hosted by the
# rooms that happened to own the two PROFILES it needs — `scruff`, the statusline
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

  # How to run one client for ONE headless turn — the table `haus-fix` is built
  # from. It checks itself against modules/lib/agents.nix on import, so a client
  # added there and forgotten there throws with both file names rather than
  # failing on whichever machine happened to default to it.
  agentOneshot = import ../lib/agent-oneshot.nix;

  # `haus-fix` — the binary behind the "Fix it" pill on a failed `haus rebuild`
  # (modules/core/haus.sh's `rebuild_failed`), and behind `haus fix`, which is
  # one line of dispatch onto it. It lives HERE, in the room that owns coding
  # agents, because core must not read `config.haus.ai.*` — so core's whole test
  # is `command -v haus-fix`, and this room's own switch is what decides whether
  # there is one to find. Two substitutions: which client, and the argv that
  # runs it once with its permission gate open.
  hausFix = pkgs.writeShellScriptBin "haus-fix" (
    builtins.replaceStrings
      [ "@client@" "@oneshot@" ]
      [
        cfg.default
        (lib.escapeShellArgs agentOneshot.${cfg.default})
      ]
      (builtins.readFile ./fix.sh)
  );

  # `haus-fix-github` — the binary behind the github pill's "Fix with AI"
  # rows (modules/bar/sketchybar/plugins/github.sh passes it a row's failure
  # verbatim). Same room, same reason haus-fix lives here: the bar must not
  # read `config.haus.ai.*`, so the whole gate is `command -v haus-fix-github`
  # — which is exactly what the bar's BAR_GITHUB_FIX names, and only when the
  # room wrote `_contrib.bar.fix-agent` underneath it. It spawns a lane via
  # scruff, so it also needs the repo roots the pounce daemon reads from its
  # launchd environment — a bar plugin has none, hence the substitution.
  hausFixGithub = pkgs.writeShellScriptBin "haus-fix-github" (
    builtins.replaceStrings
      [ "@repoRoots@" ]
      [ (lib.escapeShellArg (lib.concatStringsSep ":" cfg.repoRoots)) ]
      (builtins.readFile ./fix-github.sh)
  );

  # The pi release that first accepted `--`. Named once, read by the assertion
  # below and by nothing else; the pin that satisfies it is in that same file.
  piFloor = "0.84.3";

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
  #   pi --verbose               → names the context files and skills it loaded
  #
  # OpenCode also scans `~/.claude/skills` for Claude Code compatibility, so a
  # machine running both clients has two copies of this skill in its reach. That
  # is safe on purpose: the same probe shows opencode deduplicating by frontmatter
  # `name` and preferring its OWN directory, so the skill is offered once. (Its
  # docs only say "ensure skill names are unique", which is why this was probed.)
  #
  # pi has the same overlap and one more of its own: besides `~/.pi/agent/skills`
  # it reads `~/.agents/skills` unconditionally, and it implements the Agent
  # Skills standard, so it would find a haus skill written anywhere in that set.
  # Its own directory is still the one named here, because that is the one this
  # room can promise is haus's — `~/.agents/skills` is a shared address several
  # clients read and the user's own hand-wired skills live in.
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
    # pi keeps everything under one agent directory, `~/.pi/agent`, and reads
    # `AGENTS.md` there as its global context file. `CLAUDE.md` works too — pi
    # accepts either name — but AGENTS.md is the one the family standardises on
    # and the one pi's own docs name first.
    pi = {
      instructions = ".pi/agent/AGENTS.md";
      skills = ".pi/agent/skills";
    };
  };

  # Rice-owned preamble for each client's instructions file. The rice ships
  # `scruff` (core) on PATH to every machine, and agent worktrees live OUTSIDE the
  # repo tree (~/.cache/claude-worktrees/…), so a worktree agent's instructions
  # walk never reaches the project/workshop AGENTS.md — only THIS file + the
  # repo's own checked-out one are guaranteed read. So the general `scruff`
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
    pi = "`settings.json`, `models.json` and `trust.json` are pi's own — haus merges a few keys into the first at rebuild and owns none of the three — and a host may wire individual skills or extensions as out-of-store symlinks";
  };

  hausGuidance = client: ''
    # This file is generated by Nix — don't edit it here

    `~/${agentHomes.${client}.instructions}` is a read-only symlink into the Nix
    store, rendered from `haus.ai.instructions` in this machine's host file
    (`~/.config/nix/hosts/${hostname}/default.nix`, unless `HAUS_CONSUMER` says
    otherwise). Change it there, then `haus rebuild` — a hand-edit here either
    fails outright or is reverted by the next rebuild. Every coding agent this
    machine installs reads the same text at its own path.

    `~/${agentHomes.${client}.skills}/haus/` is generated too, from the haus
    revision this machine pins (`haus update` regenerates it), as is every other
    skill haus installed. `scruff/` and `handoff/` are scruff's, edited in
    hausfold/scruff; `factory/` and `nightshift/` are factory's, edited in
    hausfold/factory;${lib.optionalString config.haus.notifications.compositor " `trill/` is trill's, here because `haus.notifications.compositor` is on;"} they arrive on a lock bump. Not everything beside them
    is generated: ${clientScopeNote.${client}} that you can edit live with no
    rebuild. `ls -l` the path before assuming which kind it is.

    # Agent worktrees & the `scruff` tool

    `scruff` (shipped by haus, on PATH) manages **agent worktrees** for any git
    repo. ${laneChordProse} Checkouts live under
    `~/.cache/scruff/<repo>/<name>` whichever client you are.

    Closing a pane never loses work: uncommitted edits are parked as a `wip:`
    commit, and only already-merged branches are reaped. Resume with `scruff`
    (lists every worktree across all repos) or `scruff <name>`; sweep landed ones
    on demand with `scruff reap`.

    **Cross-repo work uses `scruff child`, never a raw `git worktree add`.** To
    work on a DIFFERENT repo than the pane you're in (e.g. a parent pane editing
    a sub-repo):

        cd "$(scruff child /path/to/other/repo)"

    A raw `git worktree add` never touches the registry, so the statusline HUD
    never learns to query that repo's GitHub and the worktree and its PR go
    **invisible in the bar**. `scruff child` registers it under the spawning pane,
    so its PR shows as a child row where you're working.

    **Setting work aside uses `scruff park`, never `git stash`.** The stash stack
    is NOT per-worktree — it lives in the shared `.git` dir, so every agent
    worktree of a repo and the main checkout push and pop the SAME stack, and
    parallel agents routinely pop each other's entries into a tree that never
    asked for them. `scruff park [label]` instead commits the whole dirty tree as
    one `wip:` commit on the branch only this pane has checked out; `scruff
    unpark` rewinds it, putting those changes back uncommitted. Unpark refuses a
    wip commit you've already pushed, so it can never become a force-push.

    **A session that keeps committing after its PR merged needs `scruff reship`.**
    GitHub deletes the head branch on merge, so those later commits have no
    remote and no PR, and `scruff` deliberately won't reap that branch. It marks
    the lane `+N` in the state column (`live+3`) and the bar shows an orange
    `N^`; `scruff reship [name]` pushes the branch and opens the follow-up PR.

    # The screen belongs to the person at it

    This Mac is in use while you work on it. Anything that moves the pointer,
    takes focus or redraws the desktop interrupts someone mid-sentence, and
    unlike a bad edit they can't undo it.

    - **To SEE it work, take a VM, not the screen.** A lane boots its own
      headless macOS and can be driven as hard as you like — click, type,
      `killall Dock`, `haus rebuild`, screenshot — because none of it renders
      here. That is the answer to "can I try the palette / the bar / this
      keybind / the installer", and it is the FIRST thing to reach for:
      `scruff runtime up <lane> --backend tart`, then drive the guest over `ssh`.
      The haus skill's **Seeing your change without taking the screen** has the
      whole loop.
    - **Spawning a lane never takes the screen.** Put `HAUS_LANE_BACKGROUND=1`
      in front of `scruff spawn` — the same binary the handoff skill's
      `/handoff spawn` drives — and the lane opens without the user feeling it: on a
      tiled machine the window is born off-screen and walked to `T/<repo>`, the
      client still starts on its prompt, and focus stays where it was. The
      palette's **Spawn Agent** sets it on a plain ↵ and clears it on ⌃↵, the
      "spawn and follow it" chord; do the same, and clear it only when the user
      asked to be TAKEN to the new lane. This is *how* to spawn when asked, not
      licence to spawn unasked. With nothing on screen, the line you report —
      repo, lane, branch — is their only receipt that it took.
    - **Prefer looking to touching.** `screencapture -x` is silent and steals
      nothing; a screenshot-only `computer_batch` is the same. Reach for those
      before a click.
    - **`open -g` does not promise a window.** It launches without activating
      and exits 0 either way, because it returns the moment LaunchServices
      accepts — `open -g -na Ghostty.app --args --initial-command=…` leaves a
      live process with no window and never runs the command. Use `-g` to make
      something RUN, a VM to SEE it, and ask before bringing anything forward.
    - **Hand feel-tests back, and ask when in doubt.** "Press ⌘Space and tell me
      what you see" costs two seconds; driving the palette yourself costs them
      their train of thought.

    **Asking for THIS screen is the last resort.** It is earned only by
    something a VM cannot show: the user's own windows, their real data or
    accounts, hardware and display differences, a guest that won't boot, or a
    grant that exists only on this Mac. "Faster on the host", "only one click"
    and "just to check" are not reasons. If the VM is out of reach (no `tart`,
    no image on disk), say so in one line and hand the feel-test back rather
    than falling through to the pointer.

    ${
      lib.optionalString (client == "claude") ''
        `agent-desktop-guard` backs this up on Claude Code panes: a PreToolUse
        hook that re-opens the permission prompt before a call that would move the
        pointer, take focus or redraw the desktop — those panes otherwise run in
        permission mode `auto`. It refuses nothing, and `HAUS_DESKTOP_OK=1` in a
        pane's environment turns it off for a long unattended run. It is a
        backstop, not permission to skip the above: a prompt you triggered is
        still an interruption.
      ''
    }${
      lib.optionalString (client == "pi") ''
        `agent-desktop-guard` backs this up on pi panes, reached from `tool_call`
        by the `haus-desktop-guard` extension: the same ruleset Claude Code's
        panes run behind, in front of a bash command that would move the pointer,
        take focus or redraw the desktop. pi has no permission prompt of its own,
        so the question goes up as a `trill ask` with Allow/Deny pills AND as a
        dialog in this pane at once — whichever is answered first decides, and an
        unanswered banner parks on the screen edge rather than dropping. The only
        thing it refuses outright is a call it has nowhere to ask about (a
        `pi -p` on a machine with no trill), and `HAUS_DESKTOP_OK=1` in a pane's
        environment turns it off for a long unattended run. It is a backstop, not
        permission to skip the above: a question you triggered is still an
        interruption.
      ''
    }${
      lib.optionalString (client == "claude" || client == "pi") ''

        The line is THIS screen, not the command. Work you run over `ssh` on
        another machine — a lane's own headless VM most of all — is never gated,
        however loudly it redraws over there. Booting that VM with a window on
        this display (`tart run` without `--no-graphics`) is.
      ''
    }

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
          text = hausGuidance client + cfg.instructions;
        }
      ) fileClients
    )
  );

  # ---- every OTHER hausfold tool's skill ------------------------------------
  #
  # This is step 3 of the family agent-surface standard, and until haus#473 it
  # was simply absent — the derivation existed and nothing linked it, so a haus
  # machine had scruff on PATH and no agent on it knew scruff existed. The whole
  # claim of the standard is that a haus user does nothing to get these.
  #
  # The list, and the derivation that proves the names in it are real, live in
  # ./tool-skills.nix — split out so `nix flake check` can build the thing this
  # room puts on every machine's rebuild path (`.#tool-skills`).
  #
  # `trillEnabled` is the one thing this file adds to the list: scruff is on every
  # machine, trill's room is off by default, and an agent skill for an app this
  # Mac doesn't have is worse than none (the workshop's `docs/agent-surface.md`
  # §4). Gated HERE rather than in that file so the `.#tool-skills` check still
  # proves trill's skill name whatever any one machine turns on.
  toolSkills = import ./tool-skills.nix {
    inherit pkgs lib;
    inherit (pkgs) scruff-skill factory-skill trill-skill;
    trillEnabled = config.haus.notifications.compositor;
  };
  inherit (toolSkills) toolSkillList;

  # One directory symlink per skill, into each installed client's own skills
  # directory — the same fan-out the haus skill gets, and the reason the
  # derivation names its own folders: what lands in ~/.claude/skills is decided
  # by the TOOL, not by this file.
  #
  # A directory symlink, not file-by-file: haus's own skill is split up only
  # because this-machine.md is rendered per host and has to sit beside the
  # store-built parts. Nothing here is per-host.
  #
  # Pointed at the checked copy rather than at the tool's own output, so the
  # name in the path above is one the build has already found.
  toolSkillFiles = lib.optionalAttrs cfg.skill (
    lib.listToAttrs (
      lib.concatMap (
        client:
        map (
          skill:
          lib.nameValuePair "${agentHomes.${client}.skills}/${skill.name}" {
            source = "${toolSkills.checked}/${skill.name}";
          }
        ) toolSkillList
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

  # scruff's tart runtime adapter (SPEC.md §5.5 in hausfold/scruff) — the "real
  # tart backend" hausfold/scruff#52's own commit message left as a follow-up here.
  # `scruff runtime up|enter|down --backend tart` is otherwise a dead end: the
  # command exists but every machine refuses it with "no runtime adapter
  # tart" because nothing has ever written the TOML it looks for.
  #
  # Text + a script, machine-wide (not per-client the way the two blocks
  # above are — a VM isn't a thing Claude vs. Codex each get their own copy
  # of), gated on this room's own switch since that's what installs `scruff`
  # and `tart` in the first place. It does NOT pull a base image: that is the
  # real cost here (tart's macOS base images run tens of GB), it is a choice
  # about which OS a lane tests on, and a machine that never runs `scruff
  # runtime up` should not pay for it just because the AI room is on. The
  # adapter refuses with the exact commands when `SCRUFF_TART_BASE` is unset,
  # so the missing half names itself the first time somebody needs it.
  agentRuntimeAdapterFiles = lib.optionalAttrs cfg.enable (
    let
      # System-config scope has no `config.home.homeDirectory` — that's a
      # home-manager submodule field, and this whole block is a flat
      # `home-manager.users.${username}.home.file` assignment, not a nested
      # home-manager function like terminal's. "/Users/${username}" is the
      # same literal core/windows/bar/launcher already use at this scope.
      script = "/Users/${username}/.config/haus/runtime/tart-adapter.sh";
    in
    {
      ".config/haus/runtime/tart-adapter.sh" = {
        source = ./runtime/tart-adapter.sh;
        executable = true;
      };
      # setup/enter/teardown are each ONE argv scruff execs with no shell (same
      # shape as scruff's own hooks), so all three just hand off to the script
      # above with a subcommand — see its header for why the multi-step tart
      # dance can't live in this file directly.
      ".config/scruff/adapters/runtime/tart.toml".text = ''
        # Generated from haus.ai — edit modules/ai/default.nix (this text) or
        # modules/ai/runtime/tart-adapter.sh (the script), not this copy.
        #
        # `tart` itself comes with this room. The one-time setup left, which
        # this file can't do for you, is the IMAGE:
        #   tart pull ghcr.io/cirruslabs/macos-tahoe-base:latest
        #   build-golden-vm.sh              # in haus's script/ — bakes haus INTO an image
        #   export SCRUFF_TART_BASE=haus-golden
        #
        # Tahoe, not Sequoia: the guest findings this depends on — SIP off, the
        # TCC rows that let `screencapture`/`osascript` work over SSH, the
        # macOS 26 capture prompt — were all measured on 26.x. Cloning a bare
        # base works too, but a lane that clones one has no haus to test.
        kind     = "runtime"
        id       = "tart"
        setup    = ["${script}", "setup", "{{.Name}}", "{{.Path}}"]
        enter    = ["${script}", "enter", "{{.Name}}"]
        teardown = ["${script}", "teardown", "{{.Name}}"]
      '';
    }
  );

  # ---- keeping the Mac awake while agents work (haus.ai.keepAwake) ----------
  # The lever this room owns is the SHALLOW one: a `caffeinate` assertion, which
  # needs no privilege and so runs as a per-user launchd agent here rather than
  # as a root daemon in core. The deep lever (`pmset disablesleep`, the only
  # thing that crosses a lid close) stays entirely core's; all this room does
  # about it is ASK, by writing `haus.power.lidAwake.enable` at mkDefault below.
  #
  # The loop itself is core's `lidawake.sh`, read rather than copied, for the
  # same reason `agent-state` reads bar's `agents-hook.sh`: two copies of three
  # time-dependent failsafes would drift, and the drift would be invisible. What
  # differs between the two installs is four environment variables, not a line
  # of code.
  keepAwakeOn = cfg.enable && cfg.keepAwake != "off";

  # Every path this agent owns lives under the user's own state dir. The marker
  # in particular must NOT be core's: at `sleep` depth nothing ever writes it,
  # and pointing the two installs at one path would let a user agent mistake the
  # root daemon's receipt for its own (test/lidawake.sh scenario 11b). $STAMP and
  # $CAPSTAMP derive from it, which is the only reason it is named at all.
  keepAwakeMarker = "/Users/${username}/.local/state/haus/lidawake/agent";

  lidHolds =
    let
      f = (import ../lib/state-files.nix).lidawake-holds;
    in
    "/Users/${username}/${f.dir}/${f.name}";

  # What bar's caffeinate pill stats to know an agent hold is up. Registered in
  # state-files.nix because it crosses a room boundary; see the note there for
  # why the lid half has no equivalent.
  lidHolding =
    let
      f = (import ../lib/state-files.nix).lidawake-holding;
    in
    "/Users/${username}/${f.dir}/${f.name}";

  agentAwake = pkgs.writeShellScriptBin "haus-agent-awake" (builtins.readFile ../core/lidawake.sh);

  # Repaint the coffee pill the moment a hold changes, rather than leaving it to
  # that pill's own 30s tick -- a cup that appears half a minute after the turn
  # started reads as a broken pill rather than a slow one.
  #
  # BOTH bars, for the reason `awake`'s own poke_bar gives: haus.bar.bottom.items
  # can move that pill to the second SketchyBar instance, which is a different
  # binary with its own mach service, and a trigger for an event a bar never
  # registered is a harmless no-op. The `[ -x ]` guards are what let the AI room
  # write this without knowing whether the bar room is on at all -- on a machine
  # with no bar the script runs, finds nothing, and exits 0.
  #
  # `binPath or null` for the reason focus's copy spells out: `or` catches a
  # missing ATTRIBUTE, not a null VALUE, and both happen -- no roster entry, and
  # an entry that installs nothing.
  agentAwakePoke =
    let
      p = config.haus.roster.sketchybar.binPath or null;
    in
    pkgs.writeShellScript "haus-agent-awake-poke" ''
      for bar in ${
        lib.escapeShellArg (if p == null then "" else p)
      } /run/current-system/sw/bin/bar-bottom; do
        [ -n "$bar" ] && [ -x "$bar" ] && "$bar" --trigger caffeinate_change >/dev/null 2>&1
      done
      exit 0
    '';

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
    | ai | coding-agent tooling (`scruff`, the lane VM) | ${onOff config.haus.ai.enable} |

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
  # ---- what the room hears from the GitHub bridge ----------------------------
  # A lane's row is mostly a question about its pull request, which is the
  # expensive half of `scruff --json` and the reason scruff-cache exists at all.
  # Where haus.github's bridge covers every lane's repo, that question has a
  # push answer: this wakes the cache, and scruff-cache's own gate decides whether
  # there is anything to fetch (it has just been told there is).
  #
  # A poke rather than the work: `kick` is already the throttled, one-winner,
  # detached door, and a subscriber that ran `scruff --json` itself would be a
  # second one racing it.
  haus._contrib.github.subscribers.ai-lanes = lib.mkIf cfg.enable {
    events = [
      "pull_request"
      "pull_request_review"
      "workflow_run"
    ];
    command = "scruff-cache kick 5 >/dev/null 2>&1";
  };

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
    # The one client with a VERSION floor, and the tripwire for the override in
    # modules/lib/agent-packages.nix rather than a check on nixpkgs.
    #
    # `--` — end-of-options — reached pi in 0.84.3, and every earlier version
    # answers `Error: Unknown option: --`. scruff's pi spec puts a `--` before the
    # first-turn prompt (a brief typed into Spawn Agent very often starts with a
    # dash, which is a flag otherwise), so an older pi turns every PROMPTED lane
    # into a pane that dies before the agent draws. A lane opened with no prompt
    # would keep working, which is what makes this worth asserting instead of
    # leaving to be discovered: the failure is intermittent by workflow.
    #
    # This passes today because that file pins 0.84.3 itself. It is here for the
    # day someone deletes the pin — when nixpkgs has caught up, this stays quiet;
    # when it has not, this is the named refusal instead of the dead pane.
    {
      assertion = !(lib.elem "pi" clients) || lib.versionAtLeast agentPackages.pi.version piFloor;
      message =
        "haus.ai.clients names pi, but this pkgs builds pi ${agentPackages.pi.version} and "
        + "scruff needs ${piFloor} or later: `--` (end-of-options) landed in ${piFloor}, and "
        + "without it every lane spawned WITH a prompt dies on `Error: Unknown option: --` "
        + "before the agent draws. Restore the version pin in "
        + "modules/lib/agent-packages.nix, or drop pi from ai.clients.";
    }
  ];

  # ---- the profile: what this room ASKS of the power room --------------------
  # modules/appearance/default.nix is the pattern and its header is the full
  # argument; the ladder is the same one:
  #
  #   100   the host       haus.power.lidAwake.enable = false;  ← wins
  #   900   the desktop
  #   1000  here           haus.power.lidAwake.enable = true;
  #   1500  the option's own default (false)
  #
  # mkDefault and not mkForce, deliberately. "The host wins" is the invariant the
  # whole desktop seam is built on, and an AI-room switch that silently overrode
  # a host's own `lidAwake.enable = false` would break it in the one direction
  # nobody could debug: a Mac that stopped sleeping on a lid close, with the
  # option that supposedly controls that set to false in the file you are
  # reading. So the host keeps the last word and gets TOLD, in the warning
  # below, that it used it. What it does not lose is the shallow lever -- the
  # `idle` half runs regardless, so contradicting this option degrades the
  # feature instead of switching it off.
  haus.power.lidAwake.enable = lib.mkIf (cfg.enable && cfg.keepAwake == "lid") (lib.mkDefault true);

  # A pill with no room behind it is not a smaller feature, it is a dead one —
  # and the failure is silent, which is the whole reason this room warns by name
  # rather than quietly dropping the item. Not an assertion: the bar is still
  # correct without it, and a rebuild that refuses over a pill would be worse
  # than the pill being absent.
  warnings =
    lib.optional (pillAsks != [ ] && !reportable) (
      "${lib.concatStringsSep " and " pillAsks} asks for the agents pill, but the AI room is off "
      + "(haus.ai.enable). Nothing "
      + "writes agent-pane state on this machine, so the pill would stay dormant forever and the "
      + "bar leaves it out."
    )
    # The host used its last word, which it is entitled to -- but the two
    # options now say opposite things and only one of them is doing anything, so
    # say which. Not an assertion: what you get is the shallower half of what you
    # asked for, which is a working machine rather than a broken one.
    ++ lib.optional (cfg.enable && cfg.keepAwake == "lid" && !config.haus.power.lidAwake.enable) (
      "haus.ai.keepAwake = \"lid\" asks for the lid to be held, but this machine sets "
      + "haus.power.lidAwake.enable = false and a host outranks the AI room's request. "
      + "Agents still hold an idle-sleep assertion, so a run survives an untouched keyboard "
      + "-- it does not survive closing the lid. Drop the lidAwake.enable line to get both, "
      + "or set haus.ai.keepAwake = \"idle\" to say the shallower thing on purpose."
    )
    # The hold signal comes from the agent hooks this room installs. With the
    # room off there is no hook, so the agent would poll an empty directory
    # forever -- a launchd job doing nothing, which is worse than absent because
    # it looks like the feature is on.
    ++ lib.optional (!cfg.enable && cfg.keepAwake != "off") (
      "haus.ai.keepAwake = \"${cfg.keepAwake}\" needs haus.ai.enable. The signal it waits on is "
      + "written by the agent hooks this room installs, so with the room off nothing would ever "
      + "report a turn and nothing is installed."
    );

  # ---- the payload: the system profile ---------------------------------------
  # `with pkgs` because that is the shape modules/core wrote these in and the
  # comments below name bare `scruff`. Nothing here is conditional on another
  # room — a machine with no terminal and no bar still gets a working `scruff`
  # and a working `agent-state`.
  # ---- the payload: the idle-sleep half, as a per-user agent -----------------
  # Runs at BOTH stops, `idle` and `lid`, and that is on purpose rather than an
  # oversight: `lid` is defined as "the idle half plus the lid", so the shallow
  # assertion is never conditional on how the deep one went. It costs one poll
  # loop and it means the tier that is guaranteed to work is always the one
  # holding -- including on battery, where core's daemon releases by default
  # (haus.power.lidAwake.requirePower), and in the window after a host has
  # overruled the profile above.
  #
  # An AGENT, not a daemon, because `caffeinate` needs no privilege — the
  # mirror image of the argument in core's header for why the lid half must be
  # a daemon. KeepAlive for the reason core gives too: this is a poll loop, and
  # a StartInterval respawning it every five seconds would be worse on every
  # axis. It is deliberately NOT wrapped in gui-wait: it talks to no GUI
  # process, so the cold-boot race those wrappers exist for cannot reach it.
  launchd.user.agents.haus-agent-awake = lib.mkIf keepAwakeOn {
    serviceConfig = {
      Label = "com.hausfold.agent-awake";
      ProgramArguments = [ "${agentAwake}/bin/haus-agent-awake" ];
      KeepAlive = true;
      RunAtLoad = true;
      ProcessType = "Background";
      StandardOutPath = "/tmp/haus-agent-awake.out.log";
      StandardErrorPath = "/tmp/haus-agent-awake.err.log";
      EnvironmentVariables = {
        LIDAWAKE_DEPTH = "sleep";
        LIDAWAKE_HOLD_DIR = lidHolds;
        LIDAWAKE_MARKER = keepAwakeMarker;
        LIDAWAKE_HELD_FILE = lidHolding;
        LIDAWAKE_ON_CHANGE = "${agentAwakePoke}";
        # The SHAPE of a hold is the power room's to tune and this agent reads
        # the same dial rather than growing a second one -- `haus.ai.keepAwake`
        # is a switch, not a copy of the knobs. Two of the five are deliberately
        # not inherited: `while` just below, and `requirePower`, which the
        # script ignores at this depth anyway (it is a guard about a closed
        # laptop in a bag, and here the lid still sleeps the Mac).
        # NOT `haus.power.lidAwake.while`. That option's other stop, `always`,
        # means plain closed-display mode -- hold regardless of what any agent
        # is doing -- and it is a coherent thing to want from the LID feature.
        # Inheriting it here would turn `haus.ai.keepAwake = "idle"` into a
        # permanent, agent-independent caffeinate, uncapped as well (maxHold
        # does not apply to `always`, which has no signal that could get stuck).
        # This option's only word is "while my agents work", at both stops, so
        # the signal is spelled out rather than borrowed.
        LIDAWAKE_MODE = "agents";
        LIDAWAKE_LINGER = toString (config.haus.power.lidAwake.linger * 60);
        LIDAWAKE_MAX_HOLD =
          if config.haus.power.lidAwake.maxHold == "never" then
            "0"
          else
            toString (config.haus.power.lidAwake.maxHold * 60);
      };
    };
  };

  environment.systemPackages = lib.mkIf cfg.enable (
    with pkgs;
    [
      # scruff — agent worktrees, its own product now (hausfold/scruff, taken as
      # a flake input). Every caller the rice owns is on it: terminal's
      # ⌘↵ runs `scruff new --open` (bare `scruff new` only prints the path since
      # scruff 0.2.94), pounce's Spawn Agent goes through `scruff spawn`, and
      # the Claude Code WorktreeCreate/WorktreeRemove hooks — which terminal
      # DECLARES into ~/.claude/settings.json and re-asserts on every rebuild
      # (see modules/terminal, home.activation.claudeCodeSettings) — point at
      # `scruff hook create` / `scruff hook remove`. Its bash predecessor `wt.sh`
      # has been retired entirely; there is no fallback to roll back to.
      scruff

      # `factory` — the same capability from the other end. scruff opens the
      # lanes; factory closes the pull requests nobody needed to read, merging
      # only what a filter the user typed can vouch for and leaving everything
      # with taste in it for the morning. On PATH beside `scruff` because the
      # two agent skills this room installs (`factory`, `nightshift`) are
      # instructions for driving it, and an instruction whose binary is not
      # there is worse than no instruction — the same argument `tart` below
      # rides on.
      #
      # Nothing here configures it, and that is deliberate rather than an
      # omission: what may merge is AUTHORITY, so it lives in a machine-local
      # `~/.config/factory/config.json` and a lease file that no pull request
      # can edit. A repo-shaped `haus.*` option would be the wrong shape even
      # if it were safe — the policy describes a fleet, not a machine's
      # desktop. `factory doctor` is what tells a machine whether it can run a
      # shift; this room only guarantees the verb exists.
      factory

      # `tart` — the VM half of the same tool. A lane that needs to SEE a
      # change work (the palette, the bar, a keybind, an installer run) takes
      # its own headless macOS rather than the screen the user is sitting in
      # front of, and the instructions this room writes now say so in the
      # first bullet of "the screen belongs to the person at it". An
      # instruction whose binary isn't there is worse than no instruction:
      # the agent reads it, tries, fails, and reaches for the pointer
      # anyway. So `tart` arrives WITH `scruff`, not as a manual step beside
      # it — the room already writes the adapter that drives it.
      #
      # The disk cost this room was once careful about is the IMAGES (tens of
      # GB each), not this binary, and no image is pulled until someone runs
      # `scruff runtime up` — see the adapter's own `SCRUFF_TART_BASE` refusal.
      # nixpkgs marks tart unfree (Fair Source); modules/core already sets
      # `nixpkgs.config.allowUnfree`, so this evaluates on any haus machine.
      tart

      # `claude-statusline` — the agent-worktree HUD for Claude Code's status bar
      # (terminal's claudeCodeSettings points the `statusLine` key here). Row 1 is
      # THIS session's worktree name + one status token (⏏ purge / N^ commits —
      # blue when unmerged, orange when they landed AFTER the PR merged and no PR
      # covers them / +A -D uncommitted); rows below list sister `scruff` worktrees across
      # ALL repos, with GitHub PR state. Cheap local git runs in the render path;
      # the cross-repo + `gh` enumeration is done detached by the companion
      # `claude-statusline-refresh` and cached (stale-while-revalidate), so the bar
      # never blocks. Reads `scruff`'s registry — same agent-worktree flow, same home.
      # It doubles as the writer for bar's `aiUsage` pill: Claude Code hands
      # every render the account's 5-hour + weekly rate-limit percentages, so the
      # render path stashes them to ~/.cache/claude-statusline/usage-claude.tsv —
      # the cheapest source there is, and still the primary one. It is no longer
      # the ONLY one: a statusline is a TUI feature and the macOS app renders
      # none, so the refresher also polls the account itself, which is the only
      # source that counts what the GUI burned. See its Claude block.
      # `HAUS_UI_SH` injected rather than resolved, and this is the one caller
      # where that is worth a line of Nix: the script runs on EVERY prompt, and
      # its own fallback costs a `command -v` + `readlink -f` + two `dirname`s
      # per render (~5.5 ms of a ~110 ms budget) to rediscover a path that is
      # constant for the life of the generation. modules/core does the same for
      # `haus.sh` through `wrapProgram --set-default`; there is no wrapper here,
      # so it is prepended as a line of shell instead.
      #
      # Prepended by CONCATENATION, never by an interpolated Nix block:
      # statusline.sh is full of shell expansions Nix would read as its own.
      # The escape below is `\${`, the DOUBLE-quoted form — `''${` is the
      # indented-string form and would land here as literal text. `:-` keeps a
      # caller's own value winning, which is what the suite overrides.
      (writeShellScriptBin "claude-statusline" (
        "HAUS_UI_SH=\"\${HAUS_UI_SH:-${snug}/share/ui.sh}\"\n" + builtins.readFile ./statusline.sh
      ))
      (writeShellScriptBin "claude-statusline-refresh" (builtins.readFile ./statusline-refresh.sh))

      # `agent-state` — the one writer of agent state, feeding bar's `agents`
      # pill. BYTE-FOR-BYTE the script bar also installs as
      # ~/.config/sketchybar/plugins/agents-hook.sh (read from there,
      # so the two can never drift); this copy exists only to give it a stable
      # name on PATH. Claude Code's hooks point at the sketchybar path because the
      # user's own settings.json wires them, but the Codex and Opencode wirings
      # terminal writes are client config files with no business knowing where a bar
      # keeps its plugins — they call
      # `agent-state <working|waiting|idle|remove> <client>` instead.
      (writeShellScriptBin "agent-state" (builtins.readFile ../bar/sketchybar/plugins/agents-hook.sh))

      # `agent-desktop-guard` — the PreToolUse hook terminal wires into
      # ~/.claude/settings.json (terminal's claudeCodeSettings both declares the
      # hook and sets the permission mode this counterweights). That mode is
      # "auto", which is right for files and wrong for the screen: an agent that
      # decides to foreground an app or click something just does it, mid-sentence,
      # while you are typing into something else. The guard re-opens the permission
      # prompt for exactly that slice — pointer/keyboard/focus/redraw — and returns
      # no opinion on everything else, so auto-mode is intact everywhere it was
      # already fine. It never refuses anything; the only verdict it can return is
      # "ask". It reads the target, not the text: a segment that runs over ssh on
      # another machine is dropped before the patterns see it, so a lane driving
      # its own headless VM (`scruff runtime up --backend tart`) is never prompted
      # for a desktop nobody is looking at. HAUS_DESKTOP_OK=1 in a pane turns the
      # whole thing off, the way BENCH_AGENT_SWITCH=1 does for activation.
      # test/desktop-guard.bats pins both sides of the line; details in the
      # script's header.
      #
      # TWO clients read this one binary. pi reaches it from `tool_call`
      # (terminal's `haus-desktop-guard.ts`), handing it the same hook-shaped
      # JSON Claude Code's hook does and reading the same verdict back, so the
      # line lives in one file and one bats suite for both. What differs is only
      # where the question is put: Claude re-opens its own prompt in the pane, pi
      # has no prompt to re-open and raises a `trill ask` beside its in-pane
      # dialog. Anything that changes this script's stdin or stdout contract
      # moves both — the extension parses `permissionDecision` by name.
      (writeShellScriptBin "agent-desktop-guard" (builtins.readFile ./desktop-guard.sh))

      # `scruff-cache` — one warm copy of `scruff --json` for everything that reads
      # lanes. `scruff --json` self-heals on the way in and dumps `lsof` twice
      # before it answers, which is seconds even with no lanes registered; the
      # bar's agents popup redraws on a 10s tick and the Lanes palette opens
      # under pounce's 8-SECOND loading skeleton, so neither can run it inline.
      # Both call this instead. It lives here rather than in bar, where the
      # block started, because the room that owns the capability owns its
      # payload — and because the launcher's picker needs it on a machine whose
      # bar is off. Its header has the numbers.
      (writeShellScriptBin "scruff-cache" (builtins.readFile ./scruff-cache.sh))

    ]
    # `haus-fix` — "Fix it with AI" for a rebuild that just failed. haus.sh
    # writes a breadcrumb and puts the CTA up; this is what the pill runs. See
    # its header for the boundary (the cwd plus one git commit, undone with
    # `git -C ~/.config/nix revert HEAD`) and modules/lib/agent-oneshot.nix for
    # the argv it runs a client with.
    #
    # Gated on the DEFAULT CLIENT being installed, not on the room, and that is
    # the same failure the assertion above exists to end one layer up:
    # `ai.clients = [ ]` with the room on is a legal machine, and there
    # `command -v haus-fix` would succeed, the offer would be drawn, and
    # pressing it would answer "claude is not on PATH". core's whole test is
    # that `command -v`, so a fixer that cannot fix must not be ON the PATH to
    # find — the alternative is a refusal you only discover by pressing the
    # button, which is exactly what the duplicated git gate in haus.sh exists
    # to avoid.
    #
    # `gum`, the CTA's in-pane surface, is deliberately NOT here: modules/core
    # already suffixes it onto `haus`'s own PATH for `haus set`'s picker, so a
    # second copy would be a package this room does not need — and the rows are
    # drawn by `haus`, not by anything this room installs.
    ++ lib.optional (lib.elem cfg.default clients) hausFix
    # `haus-fix-github` — see its header and hausFix's gate above: the same
    # "the default client must actually be installed" question, because a
    # button whose spawn opens a dead pane is the dead-pane failure with a
    # bar row in front of it instead of a palette behind it.
    ++ lib.optional (lib.elem cfg.default clients) hausFixGithub
  );

  # What this room ships into home: per-client instructions and skill files,
  # plus the machine-wide tart runtime adapter. Written into the SAME user
  # modules/terminal writes; home-manager merges the attrsets, and a
  # collision on one path would be an error rather than a silent last-wins —
  # which is what makes splitting them safe.
  home-manager.users.${username}.home.file =
    agentInstructionFiles // agentSkillFiles // toolSkillFiles // agentRuntimeAdapterFiles;

  # ---- what the room contributes to other rooms -------------------------------
  # One write per extension point. Every value here is a fact about the AI room;
  # how it is presented is the receiving room's business, and each of them draws
  # nothing at all when it is itself switched off. That is the whole seam: no
  # room reads `config.haus.ai.*` to decide what to draw any more.
  haus._contrib = {
    # Development — the terminal aliases `c` to this client, and pounce renders
    # the same table onto its Terminal cards. The LANE chord is pounce's own
    # (⌘↵, Ghostty-scoped → `cmd:lane-here`); it was windows' ⌃⌘A, through a
    # _contrib.windows.agents that no longer exists. The resident-agent chord
    # ⌃⌥⇧A was retired 2026-08-19 — `c` in that window's shell is the same act.
    development.agents = {
      enable = spawnable;
      inherit (cfg) default namer;
    };

    # Bar — the `agents` pill. Still opt-in per host (`haus.bar.items.agents`);
    # this only says whether anything on this machine writes pane state for it.
    bar.agents.enable = reportable;

    # Bar — the github pill's "Fix with AI" rows. Gated on the SAME condition
    # hausFixGithub's install uses (default client present), not just on the
    # room: enable without the bin would draw buttons that run a missing
    # binary, and bin without enable is the seam's normal direction (the
    # receiver draws what it finds).
    bar.fix-agent.enable = cfg.enable && lib.elem cfg.default clients;

    # Launcher — Spawn Agent, and the Agent Worktrees cards on the Tips page.
    launcher.agents = {
      enable = spawnable;
      inherit (cfg) default repoRoots namer;
    };
  };
}
