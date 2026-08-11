# Hearth — the warm interior of the den. The terminal experience: zsh, a
# Nebelung-tinted starship prompt, git, and a themed CLI toolbelt (bat, delta,
# lazygit, lsd, yazi, zoxide, fzf), plus the ghostty / zellij / yazi dotfiles.
#
# Identity is NOT baked in: git name/email/signing come from `haus.git.*`
# (set in your host), and secrets stay out of the store — load them in your
# host's zsh initContent from ~/.secrets or similar.
{
  config,
  lib,
  pkgs,
  username,
  hostname,
  ...
}:

let
  gitCfg = config.haus.git;
  hearthCfg = config.haus.hearth;
  ghDashCfg = hearthCfg.ghDash;
  agentsCfg = config.haus.agents;
  accent = config.haus.theme.accent; # a Catppuccin accent name, e.g. "mauve"
  devCfg = config.haus.developer;
  agentDefault = agentsCfg.default;

  # How the zellij binds and the `c` alias spell "start an agent". Only Claude
  # Code can make its own worktree (`--worktree`, which fires the WorktreeCreate
  # hook); for the others `holt new` does it from the outside, so Super a
  # behaves the same whichever client the machine defaults to. Holt reads the
  # persisted default rendered below, rather than the Zellij server's
  # launch-time environment. Rendered into config.kdl's @AGENT_NEW@
  # (@AGENT_HERE@ is just agentDefault).
  agentNewRun = if agentDefault == "claude" then ''"claude" "--worktree"'' else ''"holt" "new"'';

  # One client id → one package. Nothing else in the rice may name these
  # derivations: a host that wants a patched build overlays `claude-code` (or
  # `codex`, or `opencode`) so this reference picks the patched one up. Adding
  # a second derivation of the same client beside this one puts two `bin/claude`
  # in one profile, which is a collision, not an override.
  agentPackages = {
    claude = pkgs.claude-code;
    codex = pkgs.codex;
    opencode = pkgs.opencode;
  };
  agentClients = agentsCfg.clients;

  # One client id → where that client keeps the two files the rice ships into a
  # home: the always-on instructions (`haus.agents.instructions`) and the `haus`
  # skill (`haus.agents.skill`). Every client has both slots under a different
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

  # nixpkgs ships all three for aarch64-darwin only. That is the whole rice's
  # platform since 26.11 dropped x86_64-darwin, so this never fires today — but
  # it is the difference between a named refusal and an install that silently
  # does nothing, which is exactly the dead-pane failure this option exists to
  # end. (The `lib.meta.availableOn` guard it replaces did skip silently.)
  unavailableClients = lib.filter (
    c: !lib.meta.availableOn pkgs.stdenv.hostPlatform agentPackages.${c}
  ) agentClients;
  fontsCfg = config.haus.fonts; # terminal font family/size (den installs the package)

  # ---- the terminal's hotkeys, and the proof they're documented --------------
  #
  # ./term-bindings.nix is the one table of zellij chords + captions; pounce
  # renders the Terminal cards on the cheatsheet from it. The kdl stays
  # hand-written (its bind bodies carry Run options and the reasoning behind
  # each), so the two are kept honest here instead: every chord config.kdl binds
  # must be taught or explicitly listed as mode-internal, and every chord the
  # table teaches must actually be bound. Either half failing is the drift that
  # left the cheatsheet teaching ⌘C for agents long after they moved to ⌘A.
  termBindings = import ./term-bindings.nix {
    inherit lib agentDefault;
    agentsEnabled = agentClients != [ ];
    ghDashEnabled = ghDashCfg.enable;
  };
  ghDashBind = lib.optionalString ghDashCfg.enable ''
    // Super g — GitHub's review queue in a borderless, full-window
    // floating pane. It has the same overlay shape as Super f: the
    // tiled pane underneath is untouched, and quitting gh-dash drops
    // straight back into it. A 1% launcher is necessary because KDL's
    // Run action cannot request a borderless pane; gh-dash.sh opens the
    // real overlay through `zellij action new-pane --borderless true`.
    bind "Super g" {
        Run "@HOME@/.config/zellij/gh-dash.sh" {
            floating true
            close_on_exit true
            name "github-launch"
            x "100%"; y "100%"; width "1%"; height "1%"
        }
    }
  '';
  zellijConfigTemplate = builtins.replaceStrings [ "@GH_DASH_BIND@" ] [ ghDashBind ] (
    builtins.readFile ./zellij/config.kdl
  );
  ghDashGhosttyBind = lib.optionalString ghDashCfg.enable ''
    # cmd+g → zellij "Super g": gh-dash as a clean fullscreen overlay.
    # Ghostty owns this chord as search-next by default, so it must be released
    # explicitly before the multiplexer can see it. This is Cmd-G, not Zellij's
    # Ctrl-G lock toggle; those are distinct chords and coexist.
    keybind = cmd+g=unbind
  '';
  ghosttyConfigTemplate = builtins.replaceStrings [ "@GH_DASH_GHOSTTY_BIND@" ] [ ghDashGhosttyBind ] (
    builtins.readFile ./ghostty/config
  );
  # Chords bound in config.kdl. Only the quoted words BEFORE the block open — a
  # bind body can carry its own strings (`bind "Super t" { NewTab { layout "…" } }`)
  # and those are not chords.
  kdlChords = lib.concatMap (
    line:
    let
      m = builtins.match "[[:space:]]*bind ([^{]*)\\{.*" line;
      quoted = lib.splitString "\"" (builtins.head m);
    in
    if m == null then
      [ ]
    else
      map (p: p.v) (lib.filter (p: lib.mod p.i 2 == 1) (lib.imap0 (i: v: { inherit i v; }) quoted))
  ) (lib.splitString "\n" zellijConfigTemplate);
  untaughtChords = lib.subtractLists (termBindings.chords ++ termBindings.modeOnly) (
    lib.unique kdlChords
  );
  unboundChords = lib.subtractLists kdlChords termBindings.chords;

  # Our four zellij plugin forks, built FROM SOURCE at rebuild time. They're
  # wasm32-wasip1 binaries, so they come out of the wasi32 cross set — the same
  # way nixpkgs builds its own zellijPlugins (each ./zellij/<name>/default.nix
  # carries the lld/wasm-ld pin that needs).
  #
  # This used to be four hand-vendored `.wasm` blobs under ./zellij/plugins/,
  # copied in by each plugin's build.sh. That made "edit the Rust, forget to
  # re-run build.sh" a silent failure: the module installed the stale blob, the
  # rebuild succeeded, and the bar just kept rendering the old code. It bit us
  # twice (#195 for status-bar, #202 for tab-bar, which shipped 2 days of
  # rebuilds without #177's typography). Nix tracking the source removes the
  # step there was to forget.
  zellijPlugins =
    let
      build = name: pkgs.pkgsCross.wasi32.callPackage (./zellij + "/${name}") { };
    in
    lib.genAttrs [
      "tab-bar"
      "status-bar"
      "link-handler"
      "tab-history"
    ] (name: "${build name}/bin/zellij-${name}.wasm");

  # Rice-owned preamble for each client's instructions file. The rice ships
  # `holt` (den) on PATH to every machine, and agent worktrees live OUTSIDE the
  # repo tree (~/.cache/claude-worktrees/…), so a worktree agent's instructions
  # walk never reaches the project/workshop AGENTS.md — only THIS file + the
  # repo's own checked-out one are guaranteed read. So the general `holt`
  # etiquette every agent needs travels HERE, WITH the tool — not just in the
  # workshop repo end users don't have. Prepended to the host's own
  # `haus.agents.instructions`.
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
    store, rendered from `haus.agents.instructions` in this machine's host file
    (`~/.config/nix/hosts/${hostname}/default.nix`, unless `HAUS_CONSUMER` says
    otherwise). Change it there, then `haus rebuild` — a hand-edit here either
    fails outright or is reverted by the next rebuild. Every coding agent this
    machine installs gets the same text at its own path, so a change lands for
    all of them at once.

    The same goes for `~/${agentHomes.${client}.skills}/haus/`, generated from
    the rice revision this machine pins (`haus update` regenerates it). It does
    NOT go for everything beside them: ${clientScopeNote.${client}} that you can
    edit live with no rebuild. `ls -l` the path before assuming which kind it is.

    # Agent worktrees & the `holt` tool

    `holt` (shipped by this rice, on PATH) manages **agent worktrees** for any
    git repo. `Super a` (⌘A) spawns each agent into its own isolated checkout on
    a `worktree-<name>` branch, so parallel agents never fight over a single
    checkout. Closing a pane never loses work — uncommitted edits are parked as
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

    Full guide: https://nebelhaus.com/guides/claude-agents/

  '';

  # ---- the nebelhaus skill: an agent that can change this machine safely -----
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
  # Keyed off agents.clients, not "always Claude": writing ~/.claude/CLAUDE.md on
  # a codex-only machine is a file nothing reads, and NOT writing
  # ~/.codex/AGENTS.md on one is the half-truth this fan-out ends — the pane
  # spawned with none of the context the same machine hands Claude.
  #
  # Empty instructions = nothing written for anyone, so a hand-managed
  # instructions file is never clobbered just to inject the rice's note.
  # Who the two files below are written for. Normally `agents.clients` — but an
  # EMPTY list doesn't mean "no agent ever runs here", it means the rice installs
  # none: `developer.enable = false` empties the list, and `agents.clients` can't
  # be set without `developer.agents.enable` (the assertion below). A machine like
  # that can still have Claude Code from npm or Codex from brew, and before this
  # room existed both files were written unconditionally. So with nothing named,
  # write for every client we know — they are inert markdown, and a skill nothing
  # reads is much cheaper than an agent inventing option names.
  fileClients = if agentClients == [ ] then lib.attrNames agentHomes else agentClients;

  agentInstructionFiles = lib.optionalAttrs (agentsCfg.instructions != "") (
    lib.listToAttrs (
      map (
        client:
        lib.nameValuePair agentHomes.${client}.instructions {
          text = holtGuidance client + agentsCfg.instructions;
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
  agentSkillFiles = lib.optionalAttrs agentsCfg.skill (
    lib.mergeAttrsList (
      map (
        client:
        let
          dir = "${agentHomes.${client}.skills}/haus";
        in
        {
          "${dir}/SKILL.md".source = "${hausSkill}/SKILL.md";
          "${dir}/references/options.md".source = "${hausSkill}/references/options.md";
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

    Rendered from `${hostname}`'s own evaluated configuration when the rice was
    built. Where this disagrees with something you remember, this file is right.

    | | |
    |---|---|
    | hostname | `${hostname}` |
    | user | `${username}` |
    | host file | `~/.config/nix/hosts/${hostname}/default.nix` |
    | config flake | `~/.config/nix` (unless `HAUS_CONSUMER` says otherwise) |
    | rice version | `${lib.fileContents ../../VERSION}` |

    Run `haus status` for the pinned revision and whether it's behind upstream.

    ## Rooms

    | room | what it is | state |
    |---|---|---|
    | prowl | window tiling | ${onOff config.haus.prowl.enable} |
    | sill | the menu bar | ${onOff config.haus.sill.enable} |
    | pounce | the command palette | ${onOff config.haus.pounce.enable} |
    | hush | Focus / Do Not Disturb | ${onOff config.haus.hush.enable} |
    | perch | the notch file shelf | ${onOff config.haus.perch.enable} |
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
    the rice's own (installed by a module rather than a package manager), and
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
          + (if sourceOf e.app == "" then " · not installed by the rice" else sourceOf e.app)
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
          service the rice installs.

          So on this host `haus rebuild` checks first, and refuses if this
          session can't write that domain. If it refuses: make the edit, then
          ask the user to run `haus rebuild` in their own terminal. `haus doctor`
          reports whether the grant is present here.
        ''
    }
  '';
in
{
  assertions = [
    {
      assertion = lib.elem agentDefault agentClients || agentClients == [ ];
      message =
        "haus.agents.default = \"${agentDefault}\" is not in haus.agents.clients "
        + "(${lib.concatStringsSep ", " agentClients}). Pounce's Spawn Agent would create the "
        + "worktree, open the pane, and only then find no ${agentDefault} on PATH — leaving a "
        + "dead pane and a worktree to reap. Add it to agents.clients, or point agents.default "
        + "at one you install.";
    }
    {
      assertion = agentClients == [ ] || devCfg.agents.enable;
      message =
        "haus.agents.clients is set (${lib.concatStringsSep ", " agentClients}) but "
        + "haus.developer.agents.enable is off, so there is no `holt` to make a worktree, "
        + "park it, or resume it. Turn the tooling on, or empty agents.clients.";
    }
    {
      assertion = untaughtChords == [ ] && unboundChords == [ ];
      message =
        "modules/hearth/term-bindings.nix and zellij/config.kdl disagree: "
        + lib.concatStringsSep "; " (
          lib.optional (untaughtChords != [ ]) (
            "config.kdl binds ${lib.concatMapStringsSep ", " (c: "\"${c}\"") untaughtChords} "
            + "but nothing teaches it — add a row (or list it in `modeOnly` if it only exists "
            + "inside a submode)"
          )
          ++ lib.optional (unboundChords != [ ]) (
            "the cheatsheet teaches ${lib.concatMapStringsSep ", " (c: "\"${c}\"") unboundChords} "
            + "but config.kdl binds nothing to it"
          )
        )
        + ". The cheatsheet is the one document whose only job is to be true about the keys, "
        + "so a chord and its caption move together or not at all.";
    }
    {
      assertion = !ghDashCfg.enable || devCfg.git.enable;
      message =
        "haus.hearth.ghDash.enable is on but haus.developer.git.enable is off. gh-dash has no "
        + "login of its own — it reads the token `gh auth login` wrote — and the Git pack is what "
        + "installs `gh`, so the dashboard would open on a machine with nothing to authenticate "
        + "it, and every tab would be an error. Turn the Git pack on, or the dashboard off.";
    }
    {
      assertion = unavailableClients == [ ];
      message =
        "haus.agents.clients names ${lib.concatStringsSep ", " unavailableClients}, which "
        + "nixpkgs does not build for ${pkgs.stdenv.hostPlatform.system}. Installing nothing "
        + "would only move the failure into the agent pane; drop it from agents.clients.";
    }
  ];

  # Drag-to-select autoscroll. Upstream zellij scrolls exactly ONE line per
  # inbound mouse-motion event and has no repeat timer anywhere (server or
  # client), so parking the cursor past a pane edge scrolls at whatever rate
  # your hand's micro-movement happens to produce — the terminal only emits a
  # motion report when the CELL under the pointer changes. Selecting a long
  # scrollback meant jittering the mouse to manufacture events.
  #
  # Two halves. A repeat timer in screen.rs re-posts the held drag position
  # every 16ms while the pointer sits inside the scroll zone, so a parked cursor
  # scrolls at all. That is the half that removes the jittering. The other half
  # is that the speed is a RATE IN LINES PER SECOND rather than a line per
  # event: because the debt accumulator bills elapsed wall-clock time, a
  # jittered mouse and a parked one move at exactly the same speed — the thing
  # the first cut of this couldn't do.
  #
  # The zone GROWS with the selection. Three rows swept arms the last three pane
  # rows; by two thirds of a pane swept it covers everything but a three-row
  # brake strip at the FAR edge. So a long selection scrolls with the pointer
  # parked comfortably inside a fullscreen Ghostty window — no edge to reach —
  # while a short selection near an edge stays precise. Pulling back to the
  # brake strip is how you stop a long drag without releasing the button; it
  # can't be "drag back towards where you started", because for a long selection
  # the anchor has long since scrolled off the top.
  #
  # Speed is then two signals. How much of the selection is ON SCREEN sets the
  # ceiling — a fraction of the pane, not a line count, so the same gesture means
  # the same speed in a 25-row zoomed-in pane and an 80-row one. How deep into
  # the zone the pointer sits picks the rate under that ceiling, live: on a
  # 37-row pane, ~5 lines/s a few rows in, ~48 mid-pane, 360 (about ten
  # screenfuls) jammed against the edge. The pane is the speed dial.
  #
  # On-screen height, specifically, and not the total rows swept: scrolling is
  # what grows the total, so feeding it back in as the speed is a loop with
  # itself — every drag, however short, would run away to the ceiling in about
  # half a second with no way down but releasing the button.
  #
  # Pointer depth only became usable once the zone reached inside the pane. Past
  # the edge it is close to useless: terminals clamp a drag that leaves the
  # window to the edge cell (ghostty: src/renderer/size.zig, `@max(0, …)` /
  # `@min(…, rows - 1)`), so above a fullscreen pane there's exactly one row of
  # travel to measure. Inside the pane there are thirty.
  #
  # The curve is the mean of the linear and squared terms, not the square. The
  # first cut squared it, which measured out (on a 28-row pane, instrumented)
  # as: break-even against upstream's flat one-line-per-event at 29% of the
  # pane, and every gesture below that bunched into 0.39–0.70 lines per event —
  # one flat crawl, indistinguishable, which is exactly what it felt like.
  #
  # The second patch kills ctrl+scroll pane resize. Upstream turns one wheel
  # notch with ctrl held into a resize of whatever pane the pointer happens to
  # be over (`MouseAction::ResizeScrollUp/Down`, zellij-server tab/mouse_handler.rs)
  # — an accidental gesture, not a chosen one, since ctrl is held for half the
  # shortcuts a terminal app owns, and there is no undo for the layout it just
  # reshaped. Ctrl+wheel now falls through to plain scroll; deliberate resizing
  # is still the resize-mode keys and ctrl+drag on a pane frame.
  #
  # It has to be a patch. `mouse_scroll_resize false` — which lived in
  # config.kdl from 2026-07-31 to 2026-08-03 — is not a zellij option and never
  # was: it is absent from 0.44.3's source and binary, and zellij silently
  # accepts unknown top-level keys (`zellij setup --check` reports "CONFIG FILE:
  # Well defined" with it present), so it did nothing for the three days it was
  # in the tree. `advanced_mouse_actions false` is a real option and is NOT the
  # one either — it gates pane grouping and hover effects only (screen.rs's
  # group_toggle/group_add/ungroup arms, mouse_handler.rs's hover arm). The
  # ctrl+wheel branch in mouse_handler.rs is gated on nothing at all.
  #
  # The third patch adds ctrl+click-to-zoom: clicking anywhere in a pane's BODY
  # with ctrl held toggles that pane fullscreen — the pointer-driven twin of
  # Super Enter, for when the hand is already on the trackpad and reaching back
  # to the keyboard is the slow part.
  #
  # It has to be a patch, and no config or plugin can substitute: zellij's
  # keybind system is keyboard-only. Mouse buttons are not bindable in
  # config.kdl at all (modifier+scroll isn't either — zellij-org/zellij#4838),
  # and plugins get no mouse-input API, so a bind or a plugin would have
  # nothing to hook.
  #
  # It is deliberately the smallest patch that can exist for this. Upstream
  # already routes ctrl+left-press into its own branch of
  # `determine_mouse_action` and, once it has ruled out a frame drag (the
  # resize gesture), does NOTHING with it — every body click falls through to
  # `MouseAction::NoAction`. So this fills an inert `else` rather than taking a
  # gesture off anything: frame drags still resize, and the running program
  # never saw the click either way, since that branch returns before any of the
  # SendToTerminal arms. Three additive hunks — an enum variant, that `else`,
  # and a match arm calling the same `toggle_active_pane_fullscreen` the
  # keybind path calls — with no upstream line deleted, so a nixpkgs bump can
  # only break it by rewriting mouse_handler.rs wholesale.
  #
  # The fourth patch unsticks the mouse in a tab that has stopped answering it.
  # The symptom is unmistakable and, until now, unrecoverable: one tab stops
  # responding to the wheel and to clicks — its tab bar included — while its
  # neighbours are fine, and a healthy tab's bar can still click INTO the dead
  # one. Only the keyboard works there.
  #
  # One `Option<PaneId>` explains all of it. A left-press that doesn't go to a
  # mouse-tracking application starts a text selection and records the pane in
  # `Tab::selecting_with_mouse_in_pane`; while that is set, every mouse event in
  # THAT TAB is read as "the drag continues", so `determine_mouse_action`
  # answers `NoAction` to anything that isn't a left-motion or a left-release
  # (zellij-server tab/mouse_handler.rs). It is per-tab state, which is why the
  # damage is per-tab. Upstream clears it in exactly one place: the branch of
  # `execute_end_selection` that ends a text selection. So two ordinary things
  # leave it set forever —
  #
  #   · the pane is gone by the time the button comes up (a `close_on_exit`
  #     float like the find/links overlays, a command pane that exited, a click
  #     that closed the thing it landed on). The pane lookup fails, the whole
  #     `if let` is skipped, and no later Release can ever clear it either,
  #     because that lookup will keep failing.
  #   · the pane's application turned mouse tracking ON between the press and
  #     the release. The release is then forwarded to the application by the
  #     OTHER branch — the one with no reset in it.
  #
  # Both hunks are one line of behaviour each: drop a `selecting_with_mouse_in_pane`
  # that points at a pane which no longer exists, and `take` the field at the
  # top of `execute_end_selection` instead of assigning `None` on one branch
  # near the bottom — the button is up, so the drag is over whichever branch
  # runs and whichever of their `?`s bails out first. The first hunk is the one
  # that matters for a tab that is ALREADY wedged: it heals on the next mouse
  # event of any kind, where the `take` needs a left click-and-release, the one
  # event a wedged tab still routes anywhere.
  #
  # Everything that reads the field wants it false once the button is up:
  # `determine_mouse_action`'s early return, the `MouseEventContext` literal,
  # and — ours — `track_selection_autoscroll` in screen.rs, added by the first
  # patch above. That last one is the reason a wedged tab was costing more than
  # a dead mouse: the autoscroll thread arms on held-left-motion while a
  # selection is in progress and re-posts the held position at 16ms forever, so
  # a wedged tab left a timer thread spinning for the life of the session. The
  # resize twin next to it (`pane_being_resized_with_mouse`) already clears
  # unconditionally — this only brings selection into line.
  #
  # What it still doesn't cover: a release that never arrives at all for a pane
  # that is still alive (the button let go while the terminal wasn't focused,
  # say). Hunk one only heals once the pane is gone.
  #
  # It has to be a patch: the field is private tab state with no option, no
  # keybind and no plugin surface anywhere near it. Upstream carries the same
  # bug on main (checked 2026-08-09), so this is a candidate to send upstream
  # rather than a local preference.
  #
  # All four patched at zellij-unwrapped, not zellij: the latter is a thin
  # wrapper derivation with no source of its own. It rebuilds from source on
  # every nixpkgs bump that moves zellij or its deps.
  nixpkgs.overlays = [
    (_final: prev: {
      zellij-unwrapped = prev.zellij-unwrapped.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
          ./zellij/patches/selection-autoscroll.patch
          ./zellij/patches/no-ctrl-scroll-resize.patch
          ./zellij/patches/ctrl-click-fullscreen.patch
          ./zellij/patches/unstick-mouse-selection.patch
        ];
      });
    })
  ];

  # The one thing hearth installs that isn't shell config: the tool the
  # file-association hijack drives. In the roster because that's where
  # everything this machine HAS lives — visible in `this-machine.md`,
  # overridable by app id from a host, and (see the note by home.packages) able
  # to collide loudly with a cask of the same name instead of silently.
  #
  # IINA used to sit here too, purely because this room's hijack code was next
  # door. It's an editorial pick, not shell config, so it lives in modules/apps
  # now — the room whose whole job is the apps the rice chooses for you.
  haus.roster = {
    duti = {
      package = lib.mkDefault pkgs.duti;
    };
  };

  # The nebelung ports this room wires itself, so the roster pass in
  # modules/theme/ports.nix leaves them alone instead of dropping a second,
  # blunter copy beside the integration below. Most are sourced from the
  # rendered theme tree; starship, fzf and lazygit take the palette as Nix
  # values instead (they want colours inline in a config this room already
  # owns, not a file to point at) — either way the tool is handled here.
  # An assertion in theme/ports.nix checks every name is still a real port.
  #
  # gh-dash is the one conditional entry: unlike the rest, its integration is
  # opt-in (haus.hearth.ghDash.enable), and claiming a port this room only
  # sometimes wires would tell the roster pass "handled" on a machine where
  # nothing wires it — so a host that installed gh-dash itself would get no
  # theme AND no manual-step nudge from `haus doctor`.
  haus.theme.ports.handled = [
    "bat"
    "delta"
    "ghostty"
    "glow"
    "helix"
    "lsd"
    "obsidian"
    "opencode"
    "yazi"
    "zellij"
    "zen"
    "zsh-syntax-highlighting"
    "starship"
    "fzf"
    "lazygit"
  ]
  ++ lib.optional ghDashCfg.enable "gh-dash";

  home-manager.users.${username} =
    {
      config,
      lib,
      pkgs,
      osConfig,
      nebelung,
      ...
    }:
    let
      # haus.theme.{flavor,contrast} select which rendered variant everything
      # below reads — see ../lib/nebelung.nix, which owns that resolution for
      # hearth, sill and theme alike (it was duplicated in all three the moment
      # `contrast` landed; the `flavor` axis would have made that six blocks).
      #
      # nbFlavor is not decoration. whiskers names its output after the flavor it
      # rendered, so every path below that used to say "mocha" is now built from
      # nbFlavor and a latte rice resolves to catppuccin-latte.conf under the latte
      # root. Getting one wrong is invisible: the path just doesn't exist.
      nb = import ../lib/nebelung.nix {
        inherit lib nebelung;
        theme = osConfig.haus.theme;
      };
      nebelungRoot = nb.root;
      nebelungPalette = nb.palette;

      # The outline around the floating Ghostty popups (haus.hearth.floatBorder),
      # baked into float-term.sh below. "grey" is surface0 — the same step off the
      # background the bar's dropdowns take — and "off" renders an empty colour,
      # which is the one thing float-term.sh's ring() checks, so the binary is
      # never even launched.
      floatring = pkgs.callPackage ./package-floatring.nix { };
      floatBorderColor =
        {
          grey = nebelungPalette.surface0;
          accent = nebelungPalette.${osConfig.haus.theme.accent};
          off = "";
        }
        .${hearthCfg.floatBorder};
      nbFlavor = nb.flavor; # "mocha" | "latte"
      # The bat theme's name AND its filename, which whiskers title-cases:
      # "Catppuccin Mocha" / "Catppuccin Mocha.tmTheme". Named once because three
      # places reference it — bat's own config, delta's syntax-theme (inside the
      # rendered gitconfig) and yazi's syntect_theme — and they must agree exactly.
      batTheme = "Catppuccin ${nb.title}";
      # Yazi preview: pipe code/text through bat (via piper) so previews match
      # the catppuccin-themed `cat` alias — colours + line numbers.
      batPreviewer = ''piper -- bat --color=always --paging=never --style=numbers --tabs=2 --terminal-width=$w "$1"'';

      # Nebelung glamour port (markdown styling for glow), selected from the
      # same flavor + accent matrix as yazi itself. glow ignores
      # $GLAMOUR_STYLE in its default "auto" mode (glow 2.x), so the style must
      # be passed explicitly with `-s`: baked into the yazi previewer plugin
      # (@glowStyle@ placeholder) and the `glow -p` opener below.
      glowStyle = "${nebelungRoot}/glow/themes/${nbFlavor}/catppuccin-${nbFlavor}-${accent}.json";
      glowPlugin = pkgs.runCommand "glow.yazi" { } ''
        cp -r ${./yazi/plugins/glow.yazi} $out
        chmod -R +w $out
        substituteInPlace $out/main.lua --subst-var-by glowStyle ${glowStyle}
      '';

      # A deliberately finite Git vocabulary, using the names that recur most
      # often in Oh My Zsh and other common alias sets. Avoid the notoriously
      # ambiguous one- and two-letter collisions (`gl` is pull or log, `gr` is
      # remote or rebase, `gs` is status or stash depending on the framework).
      # Hosts can add/replace entries — or set one to null — through
      # haus.git.shellAliases, without loading a shell framework.
      defaultGitShellAliases = {
        g = "git";

        ga = "git add";
        gaa = "git add --all";
        gapa = "git add --patch";

        gb = "git branch";
        gba = "git branch --all";
        gbd = "git branch --delete";
        gbD = "git branch --delete --force";
        gbm = "git branch --move";

        gco = "git checkout";
        gcb = "git checkout -b";
        gcl = "git clone";
        gsw = "git switch";
        gswc = "git switch -c";

        gc = "git commit --verbose";
        gca = "git commit --verbose --all";
        gcam = "git commit --all --message";
        gcp = "git cherry-pick";
        gcpa = "git cherry-pick --abort";
        gcpc = "git cherry-pick --continue";
        gcmsg = "git commit --message";
        gcn = "git commit --verbose --no-edit";

        gd = "git diff";
        gds = "git diff --staged";
        gdw = "git diff --word-diff";

        gf = "git fetch";
        gfa = "git fetch --all --tags --prune";
        gfo = "git fetch origin";

        glo = "git log --oneline --decorate";
        glog = "git log --oneline --decorate --graph";
        gloga = "git log --oneline --decorate --graph --all";

        gm = "git merge";
        gma = "git merge --abort";
        gmc = "git merge --continue";
        gmff = "git merge --ff-only";

        gpl = "git pull";
        gpr = "git pull --rebase";
        gp = "git push";
        gpf = "git push --force-with-lease";
        gpsup = "git push --set-upstream origin HEAD";

        grb = "git rebase";
        grba = "git rebase --abort";
        grbc = "git rebase --continue";
        grbi = "git rebase --interactive";
        grbs = "git rebase --skip";
        grt = "cd \"$(git rev-parse --show-toplevel)\"";
        grv = "git remote --verbose";

        gst = "git status";
        gss = "git status --short";
        gsb = "git status --short --branch";

        gsta = "git stash push";
        gstl = "git stash list";
        gstp = "git stash pop";
        gsts = "git stash show --patch";

        gt = "git tag";

        gwt = "git worktree";
        gwta = "git worktree add";
        gwtl = "git worktree list";
        gwtr = "git worktree remove";
      };
      gitShellAliases = lib.filterAttrs (_name: command: command != null) (
        defaultGitShellAliases // gitCfg.shellAliases
      );

      # The accent colour (haus.theme.accent, default mauve) as the hex the
      # tools nebelhaus injects colours into use for their accent.
      accentColor = nebelungPalette.${accent};
      # Zen browser accent. The nebelung zen port renders every accent under
      # themes/<Flavor>/<Accent>/ (both capitalised); yazi uses lowercase for both.
      zenAccent = lib.toUpper (lib.substring 0 1 accent) + lib.substring 1 (lib.stringLength accent) accent;
      zenTheme = "${nebelungRoot}/zen/themes/${nb.title}/${zenAccent}";
      obsidianTheme = "${nebelungRoot}/obsidian/Nebelung";
      ghDashTheme = "${nebelungRoot}/gh-dash/themes/${nbFlavor}/catppuccin-${nbFlavor}-${accent}.yml";

      # The house queue, in two halves, because only one of them needs an owner.
      #
      # A gh-dash section is a GitHub search filter, and the PR tabs below are
      # scoped by `org:` — so haus.git.org is what makes them shippable at all,
      # and with no owner set Hearth writes none of them rather than guessing.
      # The self tabs (`@me`, `is:unread`) name no owner, so gating them on one
      # would only take four good tabs away from the machine that reads several
      # owners at once — exactly the machine the option tells to leave it empty.
      #
      # Everything else about a queue — which repos are checked out where,
      # which key runs which command, how wide the columns are — describes a
      # machine rather than an owner, and stays the host's in
      # programs.gh-dash.settings.
      #
      # Each list is separately mkDefault: a host replacing prSections keeps
      # the issue and notification tabs, and vice versa. Per-list rather than
      # per-tab by necessity — gh-dash reads a section list as a whole, and
      # there is no merge of two tab lists that isn't a guess about order.
      ghDashOrgTabs = {
        # Ordered by how often you look at them.
        #
        # `is:open`, NOT `is:unmerged`: unmerged means "not merged", which is
        # true of every closed-without-merging PR forever, so the live tabs
        # slowly fill with abandoned branches. `is:open` is open + draft and
        # nothing else — exactly the working queue. `shipped` is the only tab
        # here that looks at finished PRs.
        prSections = lib.mkDefault [
          {
            title = "open";
            filters = "org:${gitCfg.org} is:pr is:open";
          }
          # green and red sit side by side because together they ARE the merge
          # decision: green is the queue a ship can take, red is the queue that
          # needs a session reopened. `status:` reads the check state of a PR's
          # head commit, so a branch still building shows in neither — which is
          # the point, that's the "come back in a minute" bucket.
          {
            title = "green";
            filters = "org:${gitCfg.org} is:pr is:open status:success";
          }
          {
            title = "red";
            filters = "org:${gitCfg.org} is:pr is:open status:failure";
          }
          # One week of landings. `nowModify` is gh-dash's own template
          # function; GitHub's `merged:` qualifier wants the rendered date
          # immediately after >=, with no spaces around the operator.
          {
            title = "shipped";
            filters = ''is:pr is:merged org:${gitCfg.org} merged:>={{ nowModify "-7d" }}'';
            limit = 10;
          }
        ];

      };

      # The half that asks who you are rather than where you work, and so ships
      # with the dashboard itself.
      ghDashSelfTabs = {
        # Not org-scoped, unlike the PR tabs: an issue you filed or were handed
        # matters wherever it is, and the one in somebody else's repo is the one
        # you're most likely to forget.
        issuesSections = lib.mkDefault [
          {
            title = "mine";
            filters = "is:open author:@me";
          }
          {
            title = "assigned";
            filters = "is:open assignee:@me";
          }
        ];

        # gh-dash ships EIGHT notification tabs. Two.
        #
        # `is:unread` rather than an empty filter, even though the tab is
        # already called unread: with no filters gh-dash matches GitHub's own
        # default and returns read notifications too (that's
        # `includeReadNotifications`, which defaults to true). An explicit
        # `is:unread` overrides it for this section, so the tab's count is a
        # number of things you haven't seen — the only number worth a tab.
        notificationsSections = lib.mkDefault [
          {
            title = "unread";
            filters = "is:unread";
          }
          {
            title = "participating";
            filters = "reason:participating";
          }
        ];
      };

      # Two edits to gh-dash, for two different surfaces.
      #
      # 1. The CLI banner (`gh dash --help`) hardcodes gh-dash's own wordmark.
      #    Once Hearth owns the dashboard integration, the house mark belongs
      #    there: patch the same-width glyphs in place. --replace-fail makes an
      #    upstream redraw a loud build failure instead of silently putting the
      #    stock mark back. This is the ONLY place the mark survives — the TUI
      #    no longer draws it at all (see below) — and it keeps gh-dash's own
      #    hardcoded cyan, because the theme-following colour we used to inject
      #    only ever applied to the TUI copy that's now gone.
      #
      # 2. plain-chrome.patch strips the TUI's decoration. gh-dash spends its
      #    header's right slot on the wordmark + version string, and a whole
      #    bottom row on a coloured bar carrying a view switcher, repo/user
      #    pills and a donate link. In a full-window Cmd-G overlay none of that
      #    is information — the section tabs already say which view you're in,
      #    and the version renders as "dev" no matter what nixpkgs stamps into
      #    `cmd.Version`, because the TUI takes its version from
      #    `debug.ReadBuildInfo()` (ui.go) and a from-source Go build leaves
      #    `Main.Sum` empty. So: the header slot carries the `? help` hint
      #    instead, and the footer bar goes unstyled. The footer ROW is
      #    deliberately kept (one blank line): it is also where y/N prompt
      #    confirmations, the list pager and running-task status are drawn —
      #    each still carrying its own background, so they read as an island on
      #    a bare row — and it is what `?` expands the full keymap out of.
      #    Blanking it outright would hide a prompt that still eats the
      #    keypress. A patch file rather than more substituteInPlace because the
      #    edits are multi-line Go; it fails just as loudly on an upstream bump,
      #    which is the point — a nixpkgs bump that reshapes footer.go or
      #    tabs.go now fails the whole system build on a ghDash host.
      #
      # One thing deliberately NOT wired into this override, with the reason kept
      # so nobody has to rediscover it: gh-dash has a FOURTH view — the local
      # repo's branches, each with its PR and checks — behind an `FF_REPO_VIEW`
      # env-var feature flag, and it looks like the git-side twin of the agent
      # HUD (holt's branches, seen from GitHub). It is not usable yet, in two
      # distinct ways, both measured on 4.25.2 rather than guessed:
      #
      #   1. Flag on, cwd outside a git repo → gh-dash doesn't degrade, it EXITS
      #      on startup with `FATA … failed parsing config file … not a git
      #      repository`. The message is a lie about which thing failed (ui.go
      #      reuses one `showError` closure for the config parse and for the
      #      git-remote lookup), and it means `gh-dash` from ~ simply quits.
      #      Survivable — a wrapper could set the flag only inside a repo.
      #   2. Flag on, cwd inside a repo, press `s` three times to reach the view
      #      → nil-pointer panic in `branch.(*Branch).renderRepoName`
      #      (branch/branch.go:170), taking the whole TUI down. Reproduced in two
      #      different repos; the 3-view cycle with the flag off is fine, so it's
      #      the view, not the key. That one no wrapper can fix.
      #
      # So this stays stock until upstream ships the view unflagged. Retesting is
      # two commands (`FF_REPO_VIEW=1 gh-dash` in a repo, then `sss`) — worth
      # doing on a gh-dash bump, because the view is genuinely wanted.
      ghDashPkg = pkgs.gh-dash.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ./gh-dash/patches/plain-chrome.patch ];
        postPatch = (old.postPatch or "") + ''
          substituteInPlace internal/tui/constants/constants.go \
            --replace-fail '▜▔▚▐▔▌▚▔▐ ▌' '▐ ▌▐▔▌▐ ▌▚▔' \
            --replace-fail '▟▁▞▐▔▌▁▚▐▔▌' '▐▔▌▐▔▌▙▁▟▁▚'
        '';
      });

      # The zellij custom layout, rendered from the in-repo template. Only two
      # tokens remain: the login name for the tab-bar's username pill, and
      # $HOME for the plugin paths. Bar/tab colours no longer ride in here —
      # our tab-bar + status-bar plugins read the zellij "nebelung" theme
      # directly (the old zjstatus couldn't, so its colours used to be injected
      # here). Shared by custom.kdl and its $HOME-pinned home.kdl variant below.
      zellijLayout =
        builtins.replaceStrings [ "@username@" "@HOME@" ]
          [
            (builtins.substring 0 6 username)
            config.home.homeDirectory
          ]
          (builtins.readFile ./zellij/custom.kdl);

      # The rendered config.kdl. Unlike every other dotfile here it is NOT handed
      # to home.file — see the zellijLiveConfig activation below for why it has
      # to reach ~/.config as a real file instead of a store symlink.
      #
      # config.kdl bakes absolute script paths (zellij doesn't expand $HOME in
      # copy_command / Run / layout), so render @HOME@ → the user's home.
      zellijConfigFile = pkgs.writeText "zellij-config.kdl" (
        builtins.replaceStrings
          [ "@HOME@" "@DEFAULT_MODE@" "@BASE_MODE@" "@AGENT_NEW@" "@AGENT_HERE@" ]
          [
            config.home.homeDirectory
            (if hearthCfg.zellijStartLocked then "locked" else "normal")
            # The same choice, capitalised: SwitchToMode takes a Mode name, not
            # default_mode's lowercase spelling. The scroll/search binds exit
            # through it, because upstream's all exit to Normal — which on a
            # locked host silently leaves every submode leader hot afterwards.
            (if hearthCfg.zellijStartLocked then "Locked" else "Normal")
            agentNewRun
            ''"${agentDefault}"''
          ]
          zellijConfigTemplate
      );

      # Seeds a zellij plugin's grants into the permission cache (see the
      # home.activation entries near the end of this file for the why).
      seedZellijPluginPermissions =
        wasm: perms:
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          permissions="$HOME/Library/Caches/org.Zellij-Contributors.Zellij/permissions.kdl"
          plugin="$HOME/.config/zellij/plugins/${wasm}"
          run sh -c '
            permissions="$0" plugin="$1" tmp="$0.hm-seed"
            mkdir -p "''${permissions%/*}"
            if [ -f "$permissions" ]; then
              # /usr/bin path: home-manager activation runs with a bare PATH
              /usr/bin/awk -v open="\"$plugin\" {" \
                "\$0 == open { skip = 1; next } skip && \$0 == \"}\" { skip = 0; next } !skip" \
                "$permissions" > "$tmp"
            else
              : > "$tmp"
            fi
            printf "%s\n" \
              "\"$plugin\" {" \
              ${lib.concatMapStrings (p: "\"    ${p}\" \\\n              ") perms}"}" >> "$tmp"
            mv "$tmp" "$permissions"
          ' "$permissions" "$plugin"
        '';
    in
    {
      home.sessionVariables = {
        CLICOLOR = "1";
        HOMEBREW_NO_ENV_HINTS = "1";
        EDITOR = hearthCfg.editor;
        VISUAL = hearthCfg.editor;
        NEBELHAUS_AGENT_DEFAULT = agentDefault;
      };

      # A lean terminal/dev toolbelt, gated by the developer pack. Personal
      # choices (AI CLIs, orbstack, your language toolchains) belong in your
      # host file, not the public rice.
      home.packages =
        with pkgs;
        # duti is a roster entry (below, at the darwin level) rather than a
        # bare package — the room that installs an app declares it, and the
        # roster is what makes a second copy from a cask a build warning
        # instead of the silent duplicate IINA was for months (modules/apps
        # owns that pick now; modules/roster tells the story).
        lib.optionals devCfg.toolbelt.enable [
          chafa # fast terminal image previewer / layout engine
          glow # markdown renderer; yazi's glow previewer shells out to it
          fd # fast finder; used by yazi/zoxide navigation
        ]
        # Editing the rice's own Nix is a developer activity; `haus edit` still
        # works without a formatter. `nixfmt`, not `nixfmt-rfc-style`: nixpkgs
        # aliased the latter to the former and now warns on every eval.
        ++ lib.optional devCfg.enable nixfmt
        ++ lib.optionals (builtins.elem "node" devCfg.languages) [
          bun
          fnm # node version manager (used by the initContent below)
        ]
        # The coding-agent clients, one package per `agents.clients` entry.
        # Unlisted means uninstalled, and `agents.default` is asserted to be a
        # member — so the client the palette is about to spawn is on PATH by
        # construction, rather than discovered missing inside the pane.
        ++ map (c: agentPackages.${c}) agentClients;

      programs.zsh = {
        enable = true;
        enableCompletion = true;
        autosuggestion.enable = true;
        syntaxHighlighting.enable = true;

        # ~/.zshenv — sourced by EVERY zsh (interactive or not, login or not),
        # before zshrc and before home-manager's zoxide init. Keeping _ZO_DOCTOR
        # here rather than in initContent means non-interactive shells (Claude
        # agents, anything that shells out) also silence zoxide's false-positive
        # doctor warning — zshrc is interactive-only, so it never reached them.
        envExtra = ''
          export _ZO_DOCTOR=0
        '';

        # Each alias follows its own pack: aliasing `cat` to a bat that is not
        # installed would leave a shell that greets you with "command not found".
        shellAliases =
          lib.optionalAttrs devCfg.git.enable (gitShellAliases // { lg = "lazygit"; })
          # `c` is "the agent", not "claude" — it follows haus.agents.default
          # so a Codex or Opencode machine doesn't alias a client it never installs.
          // lib.optionalAttrs devCfg.agents.enable { c = agentDefault; }
          // lib.optionalAttrs devCfg.toolbelt.enable {
            cat = "bat --style=header,grid --tabs=2";
            ls = "lsd";
          }
          // {
          # mdcat's replacement: the same themed glow yazi's previewer uses, so
          # a terminal `mdcat file.md` renders markdown identically to the yazi
          # right-pane preview (Nebelung glamour port, tables and all).
          mdcat = ''glow -s "${glowStyle}"'';
        };

        history = {
          size = 5000;
          save = 5000;
          ignoreDups = true;
          ignoreSpace = true;
          path = "$HOME/.zsh_history";
        };

        historySubstringSearch.enable = true;

        plugins = [
          {
            name = "fzf-tab";
            src = pkgs.zsh-fzf-tab;
            file = "share/fzf-tab/fzf-tab.plugin.zsh";
          }
        ];

        initContent = lib.mkMerge [
          (lib.mkBefore ''
            export GPG_TTY=$(tty)

            # zoxide's doctor wants its init to be the LAST thing in the zshrc,
            # but home-manager injects `zoxide init` early — and we deliberately
            # add chpwd hooks after it (fnm --use-on-cd, the zellij tab-namer).
            # Those coexist fine with zoxide's `cd` override (see programs.zoxide
            # below), so the doctor is a false positive; it's silenced via
            # _ZO_DOCTOR=0 in the envExtra above (~/.zshenv) so agent shells —
            # which never source the interactive-only zshrc — get it too.

            # Homebrew (Apple Silicon)
            eval "$(/opt/homebrew/bin/brew shellenv)"

            # Secrets: prefer secretspec (ships with the rice) — a project
            # declares its secrets in a committed secretspec.toml and
            # `secretspec run -- cmd` injects the values from your provider
            # (haus.secrets.provider) into just that process, nothing
            # plaintext on disk. Anything you truly need in EVERY shell,
            # export in your HOST file's initContent (this is the public rice).
          '')
          ''
            # Nebelung zsh-syntax-highlighting colours (replaces catppuccin's
            # port). Sourced before the plugin loads — like catppuccin did —
            # which is fine: ZSH_HIGHLIGHT_STYLES is read at highlight time.
            source ${nebelungRoot}/zsh-syntax-highlighting/themes/catppuccin_${nbFlavor}-zsh-syntax-highlighting.zsh

            # Custom completions
            fpath=(~/.zsh-completions $fpath)

            ${lib.optionalString (builtins.elem "node" devCfg.languages) ''
              # fnm (Node version manager)
              export PATH="$HOME/.fnm:$PATH"
              eval "$(fnm env --use-on-cd --shell zsh)"
            ''}

            bindkey -e

            setopt appendhistory
            setopt sharehistory
            setopt hist_ignore_space
            setopt hist_ignore_all_dups
            setopt hist_save_no_dups
            setopt hist_ignore_dups
            setopt hist_find_no_dups

            zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
            zstyle ':completion:*' list-colors "''${(s.:.)LS_COLORS}"
            zstyle ':completion:*' menu no

            # Auto-name the current zellij tab after the repo whenever you cd.
            if [[ -n "$ZELLIJ" ]]; then
              # New panes inherit the focused pane's cwd (Super p), as do the
              # cwd-injecting new-tab spawns (Super Shift t, the peek Enter-on-dir
              # tab) — which, next to a claude --worktree pane, is the agent's
              # throwaway checkout under ~/.cache/claude-worktrees. A fresh
              # interactive shell has no business starting there: hop to the repo
              # the worktree belongs to (the parent of the shared .git).
              # $CLAUDECODE spares the agent's own subshells, and $ZJ_STAY spares
              # the deliberate "stay here" spawns — Super Shift p, and the
              # Enter-on-dir tab of a Super-Shift-y (--stay) peek, which bakes
              # ZJ_STAY=1 into the layout it generates. Those must stay in the
              # worktree; the Super-y peek's Enter tab is NOT spared, because
              # that peek was rooted at the main checkout to begin with. Both
              # fire once at shell birth, so unset ZJ_STAY afterward to keep it
              # out of child processes and later cd's.
              if [[ -z "$CLAUDECODE" && -z "$ZJ_STAY" && "$PWD" == "$HOME/.cache/claude-worktrees/"* ]]; then
                _wt_main="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
                [[ -n "$_wt_main" ]] && cd "''${_wt_main:h}"
                unset _wt_main
              fi
              unset ZJ_STAY

              # "~" is what fresh tabs are born as (custom.kdl) — cd-ing back
              # to ~ returns the tab to that name instead of the login name.
              _zj_name_tab() {
                local root name
                if [[ "$PWD" == "$HOME" ]]; then
                  name="~"
                else
                  root=$(git rev-parse --show-toplevel 2>/dev/null)
                  name=''${''${root:-$PWD}:t}
                fi
                command zellij action rename-tab "$name" 2>/dev/null
              }
              autoload -Uz add-zsh-hook
              add-zsh-hook chpwd _zj_name_tab
            fi
          ''
        ];
      };

      # Starship, tinted with the Nebelung palette instead of the stock flavor (the
      # whiskers starship port emits exactly this [palettes.catppuccin_<flavor>]
      # table; we inject the same name->#hex map so there's no duplication).
      programs.starship = {
        enable = true;
        enableZshIntegration = true;
        settings = {
          gcloud.disabled = true;
          palette = "catppuccin_${nbFlavor}";
          palettes."catppuccin_${nbFlavor}" = nebelungPalette;
        };
      };

      # Git — identity comes from haus.git.* (your host sets it).
      programs.git = {
        enable = devCfg.git.enable;

        # Nebelung delta theme: defines [delta "catppuccin-<flavor>"] (referenced
        # by programs.delta.options.features below). Rendered by whiskers in the
        # nebelung flake; replaces the catppuccin.delta module's include.
        #
        # Gotcha worth keeping: this ONE file carries a section for all four
        # catppuccin flavors, and only the flavor it was rendered as holds Nebelung
        # colours — the other three are stock upstream. So `features` below must
        # name the same flavor as the variant root this include came from, or delta
        # silently themes itself in stock Catppuccin. Both read nbFlavor, which is
        # what keeps them agreeing.
        includes = [ { path = "${nebelungRoot}/delta/catppuccin.gitconfig"; } ];
        signing = lib.mkIf (gitCfg.signingKey != "") {
          key = gitCfg.signingKey;
          signByDefault = true;
        };
        settings = {
          user.name = gitCfg.name;
          user.email = gitCfg.email;
          color.ui = "auto";
          push.autoSetupRemote = true;
          tag.gpgSign = gitCfg.signingKey != "";
        };
      };

      programs.delta = {
        enable = devCfg.git.enable;
        enableGitIntegration = true;
        options = {
          side-by-side = false;
          line-numbers = true;
          # Nebelung delta styles: the [delta "catppuccin-<flavor>"] feature is
          # defined in the whiskers-rendered gitconfig included via
          # programs.git.includes above (see the flavor gotcha there). Its
          # syntax-theme points at the matching bat theme, in Nebelung colours.
          features = "catppuccin-${nbFlavor}";
        };
      };

      # Nebelung theme (mauve accent) injected straight into settings from
      # nebelungPalette — mirrors catppuccin/lazygit's theme for the selected
      # flavor in Nebelung colours (see the lazygit port in the nebelung repo for
      # the file form). Injected rather than sourced, so it follows the palette
      # without needing the flavor in a path.
      programs.lazygit = {
        enable = devCfg.git.enable;
        settings.gui = {
          theme = {
            activeBorderColor = [
              accentColor
              "bold"
            ];
            inactiveBorderColor = [ nebelungPalette.subtext0 ];
            searchingActiveBorderColor = [ nebelungPalette.yellow ];
            optionsTextColor = [ nebelungPalette.blue ];
            selectedLineBgColor = [ nebelungPalette.surface0 ];
            inactiveViewSelectedLineBgColor = [ nebelungPalette.overlay0 ];
            cherryPickedCommitFgColor = [ accentColor ];
            cherryPickedCommitBgColor = [ nebelungPalette.surface1 ];
            markedBaseCommitFgColor = [ nebelungPalette.blue ];
            markedBaseCommitBgColor = [ nebelungPalette.yellow ];
            unstagedChangesColor = [ nebelungPalette.red ];
            defaultFgColor = [ nebelungPalette.text ];
          };
          authorColors."*" = nebelungPalette.lavender;
        };
      };

      programs.lsd.enable = devCfg.toolbelt.enable;
      programs.lsd.enableZshIntegration = false;

      # Theme is the Nebelung-coloured "Catppuccin <Flavor>" tmTheme from the
      # nebelung flake. The UPSTREAM name is kept (rather than renamed to
      # "Nebelung") because delta's syntax-theme and yazi's syntect_theme both
      # reference it by that name — and the whiskers-rendered files on the other end
      # of those references are flavor-named too, so all three move together.
      # programs.bat.themes rebuilds the bat cache on activation so it's picked up.
      programs.bat = {
        enable = devCfg.toolbelt.enable;
        config = {
          style = "header,grid";
          tabs = "2";
          theme = batTheme;
        };
        themes.${batTheme} = {
          src = "${nebelungRoot}/bat/themes";
          file = "${batTheme}.tmTheme";
        };
      };

      programs.yazi = {
        enable = devCfg.toolbelt.enable;
        enableZshIntegration = true;
        shellWrapperName = "yy";
        settings.mgr.show_hidden = true;
        settings.mgr.ratio = [
          2
          5
          6
        ];
        # Default preview caps (600×900 px) leave kitty-protocol previews soft
        # on a retina display; size them for the near-fullscreen peek window.
        settings.preview.max_width = 2400;
        settings.preview.max_height = 1800;
        plugins = {
          # Vendored: nixpkgs' glow plugin still uses the pre-26 Lua API and
          # crashes on yazi 26.x. This copy ports it to the current API, and
          # bakes the Nebelung glamour style path in (glowPlugin, see the let).
          glow = glowPlugin;
          piper = pkgs.yaziPlugins.piper;
          # Vendored (not in nixpkgs yet): copy the hovered/selected file(s)'
          # contents — not their path — to the clipboard. `setup` makes
          # home-manager emit the require(...):setup() call in init.lua;
          # notification = a toast on copy so there's UI feedback.
          copy-file-contents = {
            package = ./yazi/plugins/copy-file-contents.yazi;
            setup = true;
            settings = {
              append_char = "\n";
              notification = true;
            };
          };
          # peek-open: Enter inside the Super-y peek overlay. On a directory it
          # spawns a new zellij tab cwd'd there (the old browse-and-pick tab
          # picker, folded in here); on a file it pages as normal. Gated on
          # PEEK=1 (set only by
          # peek-run.sh), so in a plain `yy` session it's a no-op passthrough to
          # yazi's default Enter. See yazi/plugins/peek-open.yazi.
          peek-open.package = ./yazi/plugins/peek-open.yazi;
        };
        keymap.mgr.prepend_keymap = [
          {
            on = "<Esc>";
            run = "quit";
            desc = "Close the peek browser";
          }
          {
            # cmd+c can't reach a TUI (the terminal eats the Cmd modifier), so
            # copy-contents lives on Y. `desc` surfaces it in yazi's help (~).
            on = "Y";
            run = "plugin copy-file-contents";
            desc = "Copy file contents to clipboard";
          }
          {
            # Enter routes through peek-open: in the peek overlay a directory
            # opens a new zellij tab there, a file pages fullscreen; everywhere
            # else it's plain `open` (yazi's default Enter). See peek-open.yazi.
            on = "<Enter>";
            run = "plugin peek-open";
            desc = "Peek: open dir as tab / page file (else default open)";
          }
        ];
        settings.plugin.prepend_previewers = [
          {
            url = "*.md";
            run = "glow";
          }
          {
            url = "*.mdx";
            run = "glow";
          }
          {
            mime = "text/*";
            run = batPreviewer;
          }
          {
            mime = "*/{xml,javascript,x-wine-extension-ini}";
            run = batPreviewer;
          }
          {
            mime = "application/{json,ndjson}";
            run = batPreviewer;
          }
        ];
        settings.opener = {
          read = [
            {
              # glow otherwise reads its global width (80 columns by default),
              # even though Enter has suspended yazi and given it the whole
              # terminal. Resolve the live terminal width at open time so the
              # fullscreen pager wraps where the visible window ends.
              run = ''glow -s "${glowStyle}" -w "$(tput cols)" -p "$@"'';
              block = true;
              desc = "glow";
            }
          ];
          pager = [
            {
              run = ''bat --style=full --paging=always "$@"'';
              block = true;
              desc = "bat";
            }
          ];
          image_preview = [
            {
              run = ''~/.config/zellij/image-preview.sh "$@"'';
              block = true;
              desc = "Preview";
            }
          ];
          open = [
            {
              run = ''open "$@"'';
              orphan = true;
              desc = "Open";
            }
          ];
        };
        settings.open.rules = [
          {
            mime = "image/*";
            use = "image_preview";
          }
          {
            mime = "video/*";
            use = "open";
          }
          {
            mime = "audio/*";
            use = "open";
          }
          {
            mime = "application/pdf";
            use = "open";
          }
          {
            url = "*.md";
            use = "read";
          }
          {
            url = "*.mdx";
            use = "read";
          }
          {
            url = "*";
            use = "pager";
          }
        ];
      };

      programs.zoxide = {
        enable = devCfg.toolbelt.enable;
        enableZshIntegration = true;
        # Let zoxide take over `cd`: `cd proj` jumps by frecency, `cdi` opens
        # the interactive fzf picker. The chpwd hooks below (zellij tab-naming)
        # still fire — zoxide's cd triggers the same chpwd event as builtin cd.
        options = [ "--cmd cd" ];
      };

      # Nebelung colours injected from nebelungPalette (matches catppuccin/fzf's
      # --color mapping for the selected flavor, blue muted out). home-manager turns
      # these into the --color flags in FZF_DEFAULT_OPTS.
      programs.fzf = {
        enable = devCfg.toolbelt.enable;
        enableZshIntegration = true;
        colors = {
          "bg+" = nebelungPalette.surface0;
          "bg" = nebelungPalette.base;
          "spinner" = nebelungPalette.rosewater;
          "hl" = nebelungPalette.red;
          "fg" = nebelungPalette.text;
          "header" = nebelungPalette.red;
          "info" = accentColor;
          "pointer" = nebelungPalette.rosewater;
          "marker" = nebelungPalette.lavender;
          "fg+" = nebelungPalette.text;
          "prompt" = accentColor;
          "hl+" = nebelungPalette.red;
          "selected-bg" = nebelungPalette.surface1;
          "border" = nebelungPalette.overlay0;
          "label" = nebelungPalette.text;
        };
      };

      programs.helix = {
        enable = true;
        settings = {
          theme = "nebelung";
          editor = {
            line-number = "relative";
            mouse = true;
            cursorline = true;
            color-modes = true;
            cursor-shape = {
              normal = "block";
              insert = "bar";
              select = "underline";
            };
            file-picker = {
              hidden = false;
            };
            lsp = {
              display-messages = true;
            };
            statusline = {
              left = [
                "mode"
                "spinner"
              ];
              center = [ "file-name" ];
              right = [
                "diagnostics"
                "selections"
                "position"
                "file-encoding"
                "file-line-ending"
                "file-type"
              ];
              separator = "│";
              mode = {
                normal = "NORMAL";
                insert = "INSERT";
                select = "SELECT";
              };
            };
          };
        };
      };

      programs.zellij.enable = true;

      # Opt-in because a GitHub dashboard is not something to hand someone who
      # never asked for one. Hearth supplies the patched binary, the Nebelung
      # include, the Cmd-G overlay and the self tabs; the PR tabs come from
      # haus.git.org (see above), and with no owner set Hearth writes none of
      # them rather than guessing — gh-dash keeps its own, and a host composing
      # its own PR queue in programs.gh-dash.settings has nothing to fight.
      programs.gh-dash = lib.mkIf ghDashCfg.enable {
        enable = true;
        package = lib.mkDefault ghDashPkg;
        settings = lib.mkMerge [
          { include = lib.mkBefore [ ghDashTheme ]; }
          ghDashSelfTabs
          (lib.mkIf (gitCfg.org != "") ghDashOrgTabs)
        ];
      };

      # Catppuccin: `catppuccin.flavor` is the single source of truth — every
      # integration follows it. Raw dotfiles nix can't inject into (ghostty
      # config, zellij config.kdl) name the flavor manually; keep them in sync.
      # Every port here is themed by Nebelung instead of stock catppuccin —
      # either by pointing the program at a whiskers-rendered file from the
      # nebelung flake (bat/delta/lsd/yazi), or by injecting nebelungPalette
      # colours straight into the program's settings (starship/fzf/lazygit).
      # Each catppuccin integration is disabled so it doesn't clobber our wiring.
      # Colours are Nebelung; the upstream catppuccin *names* are kept (nebelung's
      # own convention — its ghostty output is literally catppuccin-<flavor>.conf),
      # which is why nbFlavor turns up in so many paths here.
      catppuccin.autoEnable = true;
      catppuccin.enable = true;
      catppuccin.flavor = nbFlavor;
      catppuccin.bat.enable = false;
      catppuccin.starship.enable = false;
      catppuccin.delta.enable = false;
      catppuccin.fzf.enable = false;
      catppuccin.glamour.enable = false; # GLAMOUR_STYLE wired to nebelung above
      catppuccin.helix.enable = false;
      catppuccin.lazygit.enable = false;
      catppuccin.lsd.enable = false;
      catppuccin.yazi.enable = false;
      catppuccin.gh-dash.enable = false;
      catppuccin.zsh-syntax-highlighting.enable = false;
      catppuccin.zellij.enable = false; # managed as a raw dotfile below

      # nix-index + comma (`, foo` runs a program without installing it):
      # unambiguously developer tooling, and the index is not small, so a
      # machine with the pack off shouldn't carry it.
      programs.nix-index = {
        enable = devCfg.enable;
        enableZshIntegration = devCfg.enable;
      };
      programs.nix-index-database.comma.enable = devCfg.enable;

      programs.home-manager.enable = true;

      # Zen browser — drop the Nebelung userChrome/userContent into every Zen
      # profile. Zen's chrome lives INSIDE the (randomly-named) browser profile,
      # not under XDG, so home.file can't target it — we symlink into each
      # Profiles/*/chrome at activation instead. Symlinks (not copies) so a
      # palette rebuild propagates like every other port. Also flips on Firefox's
      # legacy userChrome/userContent stylesheets, which fresh profiles ship off.
      # Zen isn't installed here (themed-but-manual); the loop no-ops if absent.
      home.activation.zenNebelung = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        zenProfiles="$HOME/Library/Application Support/zen/Profiles"
        if [ -d "$zenProfiles" ]; then
          for prof in "$zenProfiles"/*/; do
            [ -d "$prof" ] || continue
            chrome="$prof"chrome
            $DRY_RUN_CMD mkdir -p "$chrome"
            $DRY_RUN_CMD ln -sf "${zenTheme}/userChrome.css" "$chrome/userChrome.css"
            $DRY_RUN_CMD ln -sf "${zenTheme}/userContent.css" "$chrome/userContent.css"
            userjs="$prof"user.js
            if [ ! -e "$userjs" ] || ! ${pkgs.gnugrep}/bin/grep -qF \
                'toolkit.legacyUserProfileCustomizations.stylesheets' "$userjs"; then
              printf '%s\n' 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);' \
                | $DRY_RUN_CMD tee -a "$userjs" >/dev/null
            fi
          done
        fi
      '';

      # Obsidian stores theme choice inside each vault rather than in one app
      # config. Only touch explicitly listed, already-existing vaults: copy the
      # generated full theme from the store, then JSON-merge our two appearance
      # choices so Obsidian keeps ownership of every unrelated setting. Copies
      # are deliberate: these directories often sync through iCloud, where a
      # /nix/store symlink would be dangling on every other device.
      home.activation.obsidianNebelung = lib.mkIf (hearthCfg.obsidianVaults != [ ]) (
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          installObsidianNebelung() {
            vaultRel="$1"
            vault="$HOME/$vaultRel"
            obsidian="$vault/.obsidian"

            if [ ! -d "$obsidian" ]; then
              echo "warning: Obsidian vault has no .obsidian directory; skipping: $vault" >&2
              return 0
            fi

            themeDir="$obsidian/themes/Nebelung"
            $DRY_RUN_CMD mkdir -p "$themeDir"
            $DRY_RUN_CMD install -m 0644 "${obsidianTheme}/theme.css" "$themeDir/theme.css"
            $DRY_RUN_CMD install -m 0644 "${obsidianTheme}/manifest.json" "$themeDir/manifest.json"

            run sh -c '
              appearance="$0"
              tmp="$appearance.hm-seed"
              base="$appearance"
              if [ ! -s "$appearance" ]; then
                base="$tmp.base"
                printf "{}\n" > "$base"
              fi
              if ! ${pkgs.jq}/bin/jq ".cssTheme = \"Nebelung\"
                | .theme = \"obsidian\"
                | .enabledCssSnippets = ((.enabledCssSnippets // []) | map(select(. != \"nebelung\")))" \
                "$base" > "$tmp"; then
                rm -f "$tmp" "$tmp.base"
                exit 1
              fi
              mv "$tmp" "$appearance"
              rm -f "$tmp.base"
            ' "$obsidian/appearance.json"
          }

          ${lib.concatMapStringsSep "\n" (
            vault: "installObsidianNebelung ${lib.escapeShellArg vault}"
          ) hearthCfg.obsidianVaults}
          unset -f installObsidianNebelung
        ''
      );

      # ---- dotfiles + Nebelung theme drops ----
      # agentInstructionFiles / agentSkillFiles — the two things the rice ships
      # into every installed client's home: the host's instructions and the
      # `haus` skill, one copy each per entry in agents.clients. Built in the
      # `let` beside agentHomes, because what differs between clients is a path
      # table, not a dotfile.
      home.file = agentInstructionFiles // agentSkillFiles // {

        # opencode
        ".config/opencode/themes/nebelung.json".source = "${nebelungRoot}/opencode/nebelung.json";
        ".config/opencode/tui.json".text = ''
          {
            "$schema": "https://opencode.ai/tui.json",
            "theme": "nebelung"
          }
        '';
      }
      // lib.optionalAttrs devCfg.agents.enable {
        # Holt's durable machine default. The zellij server and launchd daemons
        # can outlive the environment that started them, so `holt new` resolves
        # this generated file instead of inheriting a stale client selection.
        # A standalone Holt install can own the same file by hand.
        ".config/holt/config.toml".text = ''
          # Generated from haus.agents.default — edit that option, not here.
          agent = "${agentDefault}"
        '';

        # Opencode's half of the agent-pane status the bar and the zellij tab-bar
        # draw. Claude Code's equivalent is four hooks in ~/.claude/settings.json,
        # which the USER wires (Claude owns that file and rewrites it, so the rice
        # never has); opencode instead auto-loads every file under this directory,
        # so the rice can own the whole wiring and a fresh machine gets working
        # paws for opencode panes with nothing to configure.
        # @AGENT_STATE@ → den's `agent-state` by absolute path: a plugin runs
        # inside opencode's server process, which is given no PATH guarantees.
        ".config/opencode/plugin/nebelhaus-agent-state.js".text =
          builtins.replaceStrings [ "@AGENT_STATE@" ] [ "/run/current-system/sw/bin/agent-state" ]
            (builtins.readFile ./opencode/agent-state.js);
      }
      // {

        # Helix nebelung theme, from the nebelung flake. This used to be a
        # hand-written [palette] block inheriting helix's BUILT-IN
        # catppuccin_<flavor>; nebelung now carries the real catppuccin/helix
        # port, so the theme comes rendered like every other tool here and the
        # syntax scopes track upstream instead of whatever helix ships.
        # Kept under the `nebelung` name that programs.helix.settings.theme
        # points at (the port also renders a no_italics/ sibling).
        ".config/helix/themes/nebelung.toml".source =
          "${nebelungRoot}/helix/themes/default/catppuccin_${nbFlavor}.toml";

        # ghostty (config lives in Application Support; theme lookup is XDG)
        # ghostty's `command` runs the zellij launcher by absolute path; render
        # @HOME@ → the user's home so it isn't pinned to one account.
        "Library/Application Support/com.mitchellh.ghostty/config".text =
          builtins.replaceStrings
            [ "@HOME@" "@FONT_FAMILY@" "@FONT_SIZE@" ]
            [
              config.home.homeDirectory
              fontsCfg.mono.name
              (toString fontsCfg.mono.size)
            ]
            ghosttyConfigTemplate;
        ".config/ghostty/themes/nebelung".source =
          "${nebelungRoot}/ghostty/themes/catppuccin-${nbFlavor}.conf";

        # lsd colours (replaces catppuccin.lsd). lsd auto-reads this file.
        ".config/lsd/colors.yaml".source = "${nebelungRoot}/lsd/themes/catppuccin-${nbFlavor}/colors.yaml";

        # yazi theme (replaces catppuccin.yazi): mgr/status/mode palette (mauve
        # accent) plus the syntect theme its syntect_theme line points at —
        # reusing the Nebelung bat tmTheme so previews match bat.
        ".config/yazi/theme.toml".source =
          "${nebelungRoot}/yazi/themes/${nbFlavor}/catppuccin-${nbFlavor}-${accent}.toml";
        # This target's NAME is pinned by the rendered theme.toml above: its
        # syntect_theme line reads ~/.config/yazi/Catppuccin-<flavor>.tmTheme, so it
        # has to carry the flavor or yazi's code previews lose their colours.
        ".config/yazi/Catppuccin-${nbFlavor}.tmTheme".source =
          "${nebelungRoot}/bat/themes/${batTheme}.tmTheme";

        # zellij
        # NOTE: config.kdl is deliberately absent from this block — it is
        # installed as a real file by the zellijLiveConfig activation instead,
        # so a rebuild hot-reloads into the running session. See there.
        ".config/zellij/themes/nebelung.kdl".source = "${nebelungRoot}/zellij/themes/nebelung.kdl";
        # Custom layout, rendered from the in-repo template (see zellijLayout
        # in the let above).
        ".config/zellij/layouts/custom.kdl".text = zellijLayout;
        # The same layout with the content tab pinned to $HOME — the Super-t
        # NewTab bind opens tabs from this file, so a plain new tab always starts
        # at ~ no matter where the focused pane lives (Super-Shift-t is the "…at
        # the focused dir" variant — new-tab-here.sh). Tab-level cwd is the only
        # form zellij honors under a default_tab_template (peek-run.sh and
        # new-tab-here.sh pull the same trick per-pick); the assert trips at eval
        # time if custom.kdl's
        # content-tab line ever changes shape, instead of silently shipping a
        # layout that no-ops back to cwd inheritance.
        ".config/zellij/layouts/home.kdl".text =
          let
            pinned =
              builtins.replaceStrings
                [ "\n    tab name=\"~\" {\n" ]
                [ "\n    tab cwd=\"${config.home.homeDirectory}\" name=\"~\" {\n" ]
                zellijLayout;
          in
          assert pinned != zellijLayout;
          pinned;
        # The four plugin forks, each built from ./zellij/<name>/src by the
        # zellijPlugins derivations in the let above — never a checked-in blob,
        # so a source edit can't be shipped half-applied. The install paths stay
        # exactly these four names: config.kdl / custom.kdl reference them by
        # path, and so does the permission-cache seed below (keyed on the
        # expanded ~/.config/zellij/plugins/<name>.wasm), so renaming one here
        # silently un-grants the plugin.
        ".config/zellij/plugins/link-handler.wasm".source = zellijPlugins.link-handler;
        # tab-history (see zellij/tab-history/): background plugin that makes
        # Ctrl(+Shift)+Tab walk tabs in most-recently-used order (browser-style
        # back/forward) instead of by position. Loaded via config.kdl's
        # load_plugins; grants seeded below.
        ".config/zellij/plugins/tab-history.wasm".source = zellijPlugins.tab-history;
        # Our status-bar fork (see zellij/status-bar/): the bottom-right quick
        # hints are condensed to one flat Super-key block (agent, find, optional
        # gh-dash, pounce-links, pane, tab, yazi-peek, fullscreen — keys only,
        # no labels/ribbons, listed alphabetically by the key that shows).
        ".config/zellij/plugins/status-bar.wasm".source = zellijPlugins.status-bar;
        # Our tab-bar fork (see zellij/tab-bar/): the top bar, replacing the
        # third-party zjstatus that used to sit here. Same active-anchored tab
        # scroll viewport as upstream zellij:tab-bar (so tabs stay readable on a
        # thin pane instead of clipping under the right-hand widgets, which is
        # what zjstatus did), themed to nebelung, with a username pill + a
        # Ctrl+Tab / swap-layout right side.
        ".config/zellij/plugins/tab-bar.wasm".source = zellijPlugins.tab-bar;
        ".config/zellij/launch.sh" = {
          source = ./zellij/launch.sh;
          executable = true;
        };
        ".config/zellij/image-preview.sh" = {
          source = ./zellij/image-preview.sh;
          executable = true;
        };
        # Both peek binds run this one script: Super y hops out of an agent
        # worktree to the repo's main checkout, Super Shift y passes --stay and
        # doesn't. See config.kdl's pair of binds.
        ".config/zellij/peek.sh" = {
          source = ./zellij/peek.sh;
          executable = true;
        };
        ".config/zellij/peek-run.sh" = {
          source = ./zellij/peek-run.sh;
          executable = true;
        };
        # Super-Shift-t: open a new tab cwd'd at the focused pane's dir (clones
        # the active layout + injects a tab-level cwd). See config.kdl's bind.
        ".config/zellij/new-tab-here.sh" = {
          source = ./zellij/new-tab-here.sh;
          executable = true;
        };
        # ⌘F / ⌘⇧F: full-text search over every pane in the session —
        # agent panes through their Claude transcript (the alt-screen has no
        # scrollback to search), everything else through dump-screen. See the
        # script header for why this isn't zellij's native search.
        ".config/zellij/find.sh" = {
          source = ./zellij/find.sh;
          executable = true;
        };
        # Cmd-G: the tiny launcher that asks zellij for the real full-window,
        # borderless gh-dash pane. The bind is rendered only when ghDash is on.
        ".config/zellij/gh-dash.sh" = {
          source = ./zellij/gh-dash.sh;
          executable = true;
        };
        # The one floating-Ghostty helper (geom + spawn + ring); peek.sh, the
        # Rebuild System pounce command, and the agent-peek popup all route
        # through it. The outline's binary/colour/width are baked in rather than
        # passed per caller, so haus.hearth.floatBorder moves all three at once
        # — and so the pounce command, which runs on launchd's bare PATH, gets
        # floatring by store path instead of hoping it's installed.
        ".config/zellij/float-term.sh" = {
          text =
            builtins.replaceStrings
              [
                "@floatring@"
                "@ring_color@"
                "@ring_width@"
              ]
              [
                "${floatring}/bin/floatring"
                floatBorderColor
                "2"
              ]
              (builtins.readFile ./zellij/float-term.sh);
          executable = true;
        };
        # The one "open in the editor" launcher — a new zellij tab running
        # haus.hearth.editor (baked into @editor@). Shared by the "Nix
        # Config" palette/bar commands and the file-association hijack.
        ".config/zellij/editor-open-pane.sh" = {
          text = builtins.replaceStrings [ "@editor@" ] [ hearthCfg.editor ] (
            builtins.readFile ./zellij/editor-open-pane.sh
          );
          executable = true;
        };
        # pounce's terminal launcher (POUNCE_TERMINAL_LAUNCHER, wired in
        # modules/pounce) — opens `ssh <host>` etc. in a new `main`-session tab,
        # same flow as editor-open-pane.sh above.
        ".config/zellij/pounce-terminal.sh" = {
          source = ./zellij/pounce-terminal.sh;
          executable = true;
        };
        # The one "open the nix config" opener — resolves this host's
        # hosts/@hostname@/default.nix and hands it to the launcher above with
        # the flake root as cwd. The "Nix Config" palette command (pounce) and
        # the bar's nix pill (sill) both exec this.
        ".config/zellij/nix-config-open.sh" = {
          text = builtins.replaceStrings [ "@hostname@" ] [ hostname ] (
            builtins.readFile ./zellij/nix-config-open.sh
          );
          executable = true;
        };
        ".config/zellij/copy-clean.pl" = {
          source = ./zellij/copy-clean.pl;
          executable = true;
        };
      };

      # config.kdl is INSTALLED, not linked — the one dotfile in this module that
      # isn't a store symlink, and the reason a rebuild no longer costs you your
      # tabs.
      #
      # zellij watches the active config and applies most fields to the running
      # server within a second: keybinds, theme, pane_frames, the lot. It decides
      # "changed" by the file's mtime. Every /nix/store file carries mtime =
      # epoch 1, so a home.file symlink defeats that completely — activation
      # repoints the link at a NEW store path with the SAME 1970 timestamp, the
      # watcher reads it as older than what it already parsed, and nothing
      # happens. That single stat is the whole reason a rebuild used to mean
      # `zellij delete-all-sessions` (and the reason zreload existed).
      #
      # Measured on 0.44.3 against a live session, four ways. Diagnosis:
      # repointing the symlink at a file with a fresh mtime reloaded in ~1s;
      # repointing between two files with identical epoch mtimes never fired at
      # all; and `touch`ing one file — same path, same bytes, mtime the only
      # thing that moved — reloaded in <1s. Then the shipped mechanism itself:
      # four consecutive install+rename cycles against one live session all
      # reloaded, in 1-2s each. That last one matters because rename gives the
      # path a NEW INODE every time — the watcher is keyed on the path and
      # re-arms, so this doesn't silently work once and then stop.
      #
      # `install` writes a fresh regular file with the current mtime, so every
      # activation looks new. Mode 0444 keeps the read-only semantics the store
      # symlink had, so zellij still can't persist runtime edits into a file nix
      # owns; the write goes to a temp name and renames into place, because
      # rename() needs write on the DIRECTORY, not on the 0444 file it replaces.
      # entryAfter linkGeneration: home-manager removes the symlink it used to
      # manage here during that step, so we must land after it, not before.
      # Absolute /bin and /usr/bin paths throughout — activation runs with a bare
      # PATH (same reason the plugin-permission seed above spells out
      # /usr/bin/awk).
      home.activation.zellijLiveConfig = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        run /bin/mkdir -p "$HOME/.config/zellij"
        zcfg="$HOME/.config/zellij/config.kdl"
        # Rewrite only when it would change something: the path is still
        # home-manager's symlink (the migration case, and the one a plain content
        # compare would wrongly skip), or it's missing, or the bytes actually
        # moved. Without this every no-op `haus rebuild` would hand the running
        # server a pointless reload.
        if [ -L "$zcfg" ] || [ ! -e "$zcfg" ] || ! /usr/bin/cmp -s ${zellijConfigFile} "$zcfg"; then
          run /bin/rm -f "$zcfg.new"
          run /usr/bin/install -m 0444 ${zellijConfigFile} "$zcfg.new"
          run /bin/mv -f "$zcfg.new" "$zcfg"
        fi
        # Rollback safety. `home-manager.backupFileExtension = "backup"` (see
        # flake.nix) means an older generation that still wants to LINK this path
        # moves our real file to config.kdl.backup rather than refusing — good,
        # but only once: check-link-targets aborts activation outright if that
        # backup already exists, so a rollback → rebuild → rollback sequence would
        # fail on the second one. Clear it here; the file is always regenerable
        # from the store, so there is nothing to lose.
        run /bin/rm -f "$zcfg.backup"
      '';

      # zellij grants plugin permissions through an interactive (y/n) prompt in
      # the plugin's pane — but none of our forks can answer it: link-handler is
      # a background plugin (load_plugins) with no pane, status-bar never calls
      # request_permission (built-ins don't need to, and we keep the fork diff
      # minimal), and tab-bar's "pane" is a 1-line borderless bar you can't
      # select — so its prompt renders in the bar but no keystroke ever reaches
      # it. An ungranted plugin therefore sits event-less forever (zellij only
      # auto-grants when EVERY requested permission is cached).
      # Seed the grants straight into zellij's permission cache instead (keyed
      # by the plugin's expanded path): replace our plugin's block wholesale so
      # permission-list changes propagate, but never own the file — zellij
      # rewrites it when other plugins are granted interactively, so those
      # entries must survive.
      #
      # OPERATIONAL GOTCHA — a live server can clobber a fresh seed, and only a
      # bounce fixes it. zellij re-reads this file whenever a plugin requests
      # permission, so a seed normally takes effect on the next plugin load. But
      # a running server also *rewrites* the file from its own in-memory
      # snapshot (whenever any plugin is granted), which can drop a grant this
      # activation just wrote. So when a rebuild changes a bar plugin's wasm,
      # the next new tab can surface the un-answerable prompt above even though
      # the seed ran — the seed and the running server race for the file. The
      # seed alone can't win that race (zellij owns the file at runtime); the
      # fix is to bounce the server so it reloads the seeded file cleanly:
      #     zellij kill-session <name> && zellij attach --create <name>
      # serialize_pane_viewport is on, so pane layouts + scrollback resurrect
      # (live processes don't — re-run them). `bench try switch` (or any
      # rebuild) re-runs this seed; the bounce is what makes an already-running
      # server honour it.
      home.activation.zellijLinkHandlerPermissions = seedZellijPluginPermissions "link-handler.wasm" [
        "ReadApplicationState"
        "ChangeApplicationState"
        "FullHdAccess"
        "RunCommands"
        "ReadSessionEnvironmentVariables"
      ];
      # ModeUpdate/TabUpdate/PaneUpdate — everything the bar renders from —
      # are gated on ReadApplicationState (zellij's check_event_permission).
      home.activation.zellijStatusBarPermissions = seedZellijPluginPermissions "status-bar.wasm" [
        "ReadApplicationState"
      ];
      # tab-history reads TabUpdate (ReadApplicationState) to track focus order
      # and calls go_to_tab (ChangeApplicationState) to switch tabs; both are
      # pre-seeded because it's a background plugin with no pane to prompt in.
      home.activation.zellijTabHistoryPermissions = seedZellijPluginPermissions "tab-history.wasm" [
        "ReadApplicationState"
        "ChangeApplicationState"
      ];
      # tab-bar renders from TabUpdate/ModeUpdate/PaneUpdate (ReadApplicationState)
      # and switches tabs on a mouse click via switch_tab_to
      # (ChangeApplicationState). ReadCliPipes is for the agent-status paw beside
      # a tab name: sill's agents-hook.sh broadcasts each agent pane's state over
      # `zellij pipe`, and without this permission that pipe never reaches the
      # plugin. NOTE it can't be treated as optional — zellij only auto-grants
      # when EVERY requested permission is cached, so if this list falls behind
      # the wasm's request_permission() the whole bar goes event-less, not just
      # the paws. It's the top bar, so its prompt would render in a 1-line
      # borderless pane you can't select — un-answerable (see the note above),
      # which is exactly why it must be seeded rather than left to prompt.
      home.activation.zellijTabBarPermissions = seedZellijPluginPermissions "tab-bar.wasm" [
        "ReadApplicationState"
        "ChangeApplicationState"
        "ReadCliPipes"
      ];

      # Keep nix-installed .app bundles findable by LaunchServices.
      #
      # A GUI app from nixpkgs (IINA, which modules/apps ships) is linked
      # into ~/Applications/Home Manager Apps as a SYMLINK, and LaunchServices
      # resolves that to the /nix/store path when it registers the bundle — so
      # every record it keeps is pinned to a store hash. Bump the package and the
      # hash changes: the "Open With" entry, the default-handler binding, and
      # `open -b <bundle-id>` all still name a path that garbage collection is
      # about to remove, and the app quietly stops being the handler for its own
      # file types. (Masked for anyone who ALSO has the app from a cask — the
      # /Applications copy keeps answering for the shared bundle id, which is how
      # a machine can carry two copies of one app and never notice.)
      #
      # Re-registering on every activation is the fix, because activation is
      # exactly when the store path changes. `-f` forces a refresh of records
      # that already exist, `-r` walks the directory; both are cheap on a handful
      # of symlinks, and neither touches which app is the DEFAULT for a type —
      # that binding is by bundle id and is the user's to set (duti, or Finder's
      # Get Info), so this only makes sure the id keeps resolving.
      home.activation.nixAppsLaunchServices = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        nixApps="$HOME/Applications/Home Manager Apps"
        if [ -d "$nixApps" ]; then
          $DRY_RUN_CMD /System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister \
            -f -r "$nixApps" 2>/dev/null || true
        fi
      '';

      # File-association hijack — opt-in (haus.hearth.hijackFileAssociations).
      # Off by default: silently making EditorOpen.app the handler for a dozen
      # extensions is a jarring, hard-to-undo surprise on someone else's machine.
      # It opens files in the rice editor (haus.hearth.editor) via the same
      # zellij launcher the palette/bar use.
      home.activation.editorOpenApp = lib.mkIf hearthCfg.hijackFileAssociations (
        lib.hm.dag.entryAfter [ "writeBoundary" ] (
          let
            # Extensions EditorOpen.app claims as an Editor (see the "declare in
            # the app" note in the script). Deliberately EXCLUDES web-content
            # types (html/htm/xhtml — browsers own public.html and won't yield,
            # and you want those in a browser anyway) and image types (handled by
            # the zellij link-handler's image preview).
            #
            # The rice owns each of these EXCLUSIVELY, and that is a rule, not a
            # coincidence: modules/apps keeps `ts`, `mts` and `m2ts` out of
            # IINA's video list precisely so nothing here is contested. Two
            # rice-owned apps claiming one type never settles — both claims
            # re-run on every activation and macOS stops to ask the user which
            # app wins, every rebuild, forever. So before adding an extension,
            # check it against `iinaVideoExts` in modules/apps/default.nix — by
            # UTI, not by spelling, since one UTI can carry several extensions
            # (claiming `mts` drags `.m2ts` along; AVCHD gives them one).
            editorExts = [
              "json" "jsonc" "txt" "md" "mdx" "markdown" "rst" "adoc" "org"
              "ts" "tsx" "mts" "cts" "js" "jsx" "mjs" "cjs"
              "rs" "go" "py" "rb" "lua" "pl" "php" "java" "kt" "kts" "swift" "scala" "clj"
              "c" "h" "cc" "cpp" "hpp" "hh" "cs"
              "nix" "toml" "yaml" "yml" "kdl" "conf" "ini" "cfg" "properties" "env"
              "css" "scss" "sass" "less" "styl"
              "vue" "svelte" "astro"
              "sh" "bash" "zsh" "fish" "vim" "ps1"
              "sql" "graphql" "gql" "prisma" "proto"
              "xml" "csv" "tsv" "diff" "patch" "log" "lock" "tex" "bib"
              "editorconfig" "gitignore" "gitattributes" "dockerignore" "npmrc"
            ];
            # NOTE on extensionless executables (`bench` & friends): they're
            # typed public.unix-executable and RUN in Terminal on click. That one
            # can't be automated here — macOS gates changing the executable
            # handler behind an INTERACTIVE confirmation dialog that
            # `darwin-rebuild switch` can't answer (and neither declaration nor
            # lsregister overrides Terminal's claim). To send them to the editor,
            # run once by hand and click through the prompt:
            #   duti -s org.nebelhaus.editoropen public.unix-executable all
            plistBuddy = "/usr/libexec/PlistBuddy";
            lsregister = "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister";
            # One PlistBuddy "Add …:CFBundleTypeExtensions:<i> string <ext>" per
            # extension, index-ordered.
            declareExts = lib.concatStringsSep "\n" (lib.imap0 (
              i: ext:
              ''$DRY_RUN_CMD ${plistBuddy} -c "Add :CFBundleDocumentTypes:0:CFBundleTypeExtensions:${toString i} string ${ext}" "$PL"''
            ) editorExts);
            dutiPins = lib.concatStringsSep "\n" (map (
              t: ''$DRY_RUN_CMD "${pkgs.duti}/bin/duti" -s org.nebelhaus.editoropen "${t}" all 2>/dev/null || true''
            ) editorExts);
          in
          ''
            appDir="$HOME/Applications"
            $DRY_RUN_CMD mkdir -p "$appDir"
            $DRY_RUN_CMD /usr/bin/osacompile -o "$appDir/EditorOpen.app" -e 'on open theFiles' -e 'repeat with theFile in theFiles' -e 'set file_path to POSIX path of theFile' -e 'do shell script "$HOME/.config/zellij/editor-open-pane.sh " & quoted form of file_path' -e 'end repeat' -e 'end open'
            PL="$appDir/EditorOpen.app/Contents/Info.plist"
            $DRY_RUN_CMD /usr/bin/plutil -replace CFBundleIdentifier -string "org.nebelhaus.editoropen" "$PL"

            # Declare the file types EditorOpen.app owns IN THE APP ITSELF — not
            # just via duti. This is load-bearing: `duti -s <ext>` can only bind an
            # extension whose UTI some installed app already declares; for a type
            # nothing else on the machine declares (rs, go, kdl, lua, fish, …) duti
            # hits a FATAL LaunchServices -50 and silently no-ops, so those files
            # keep opening in nothing/Terminal. Declaring the extension here
            # materializes its UTI and registers this app as the owner, and
            # `lsregister -f` makes it the default — even beating an existing owner
            # (a bare .py that would otherwise open in Xcode). Delete-first keeps
            # the block idempotent across re-activations.
            $DRY_RUN_CMD ${plistBuddy} -c "Delete :CFBundleDocumentTypes" "$PL" 2>/dev/null || true
            $DRY_RUN_CMD ${plistBuddy} -c "Add :CFBundleDocumentTypes array" "$PL"
            $DRY_RUN_CMD ${plistBuddy} -c "Add :CFBundleDocumentTypes:0 dict" "$PL"
            $DRY_RUN_CMD ${plistBuddy} -c "Add :CFBundleDocumentTypes:0:CFBundleTypeName string Source" "$PL"
            $DRY_RUN_CMD ${plistBuddy} -c "Add :CFBundleDocumentTypes:0:CFBundleTypeRole string Editor" "$PL"
            $DRY_RUN_CMD ${plistBuddy} -c "Add :CFBundleDocumentTypes:0:LSHandlerRank string Owner" "$PL"
            $DRY_RUN_CMD ${plistBuddy} -c "Add :CFBundleDocumentTypes:0:CFBundleTypeExtensions array" "$PL"
            ${declareExts}

            # Register the freshly-declared bundle so LaunchServices sees the new
            # types before we pin defaults against them.
            $DRY_RUN_CMD ${lsregister} -f "$appDir/EditorOpen.app" 2>/dev/null || true

            # Belt-and-suspenders: pin us as the *user default* for every type
            # where the UTI is bindable. duti prints (and this swallows) a benign
            # -50 on the pure-dynamic types the declaration above already handled;
            # a real failure isn't worth aborting activation over.
            if [ -x "${pkgs.duti}/bin/duti" ]; then
            ${dutiPins}
            fi
          ''
        )
      );

      # Claude Code — seed a couple of defaults into settings.json:
      #   permissions.defaultMode = "auto"  — pin the permission mode here
      #     instead of passing --dangerously-skip-permissions on the command
      #     line (the zellij binds above no longer do). "auto" runs agents
      #     unattended but keeps the background safety checks that block
      #     dangerous escalations, so it's safe on the host — unlike
      #     bypassPermissions, which is the flag's exact, check-free behaviour
      #     and wants a container.
      #   tui = "fullscreen"  — render Claude Code in the alt-screen (fullscreen)
      #     TUI rather than inline. `/tui fullscreen` sets this per-session and
      #     relaunches; seeding it makes fullscreen the default on every new
      #     machine. Highlight-to-copy through zellij still works, so there's no
      #     tradeoff to the classic inline renderer.
      #   disableAgentView = true  — turn off the built-in agent-manager view
      #     (`claude agents`, `--bg`, /background, its on-demand daemon) and the
      #     "← for agents" toolbar hint that advertises it. Undocumented key,
      #     equivalent to CLAUDE_CODE_DISABLE_AGENT_VIEW=1. Parallel Claude
      #     sessions here go through `holt` + zellij panes (den/hearth), not the
      #     in-app view, so the hint is pure noise — kill it at the rice level.
      #   statusLine  — point Claude Code's status bar at `claude-statusline`
      #     (den ships it on PATH). It renders THIS session's `holt` worktree +
      #     the sister worktrees in flight across every repo — the agent-worktree
      #     HUD the built-in bar can't give. refreshInterval keeps the sister
      #     list current while the main session sits idle watching other panes.
      #     It is also the ONLY feed behind sill's `claudeUsage` pill — Claude
      #     Code hands the statusline its rate-limit percentages and nothing
      #     else on this machine sees them — so unsetting this key freezes that
      #     pill (it greys itself out after 30 minutes rather than lying).
      #   spinnerTipsEnabled = false  — drop the rotating "Tip:" line under the
      #     spinner; the status bar already carries the context that matters.
      #     (The built-in mode/`esc to interrupt` footer badge has no such knob
      #     in Claude Code — statusLine renders above it and can't replace it.)
      #   footerLinksRegexes  — CC scans conversation output for these patterns
      #     and renders a native, clickable badge in the footer for each hit. We
      #     match GitHub `owner/repo#N` shorthand → the PR's github.com page, so
      #     a family PR reference anywhere in the transcript is one click away.
      #     This is the maintained clickable-PR path: CC 2.1.3+ STRIPS the OSC 8
      #     hyperlinks the statusline (den/statusline.sh) emits for its "#N" PR
      #     pills — colored but no longer ⌘-clickable (upstream regression,
      #     anthropics/claude-code#21586). footerLinksRegexes needs no OSC 8, so
      #     it survives that. Note it's a DIFFERENT surface (the footer, keyed
      #     off conversation text) — it doesn't restore clickability to the
      #     statusline pills themselves; those relight if/when CC stops filtering.
      #     Pattern uses char classes ([0-9], not \d) on purpose: a backslash
      #     would have to survive the nix'' → sh"" → jq"" escaping layers below.
      # Claude owns settings.json (it rewrites the file as plugins/statusline/
      # permission grants change), so we merge our keys in at activation and
      # never own it — every other key it holds must survive. jq is pinned from
      # the store because activation runs with a bare PATH.
      #
      # The two WorktreeCreate/WorktreeRemove hooks are set here, and that is a
      # change from how they used to live: hand-written, once, and hoped for.
      # The risk was never a rebuild clobbering them — this merge only touches
      # the keys it names — it was the sentence above. Claude REWRITES this file
      # on its own schedule, and a hand-edited hook it doesn't know about can go
      # with it; you would find out at pane-close, by losing a worktree's
      # parking. Declaring them makes them self-healing: every rebuild
      # re-asserts them, so the worst case is one `haus rebuild` rather than
      # silent data loss.
      #
      # Set as whole arrays, not merged into: these two events are rice plumbing
      # pointing at a rice-controlled /run/current-system path, and there is no
      # sensible second handler for "make me a worktree". Every OTHER hook event
      # in the file is untouched — including the four agent-state hooks, which
      # stay yours (see modules/sill/options.nix).
      # Claude Code settings/hooks/statusline are agent tooling; a machine that
      # runs no agents should not have its ~/.claude/settings.json rewritten.
      home.activation.claudeCodeSettings = lib.mkIf devCfg.agents.enable (
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run sh -c '
          settings="$0"
          mkdir -p "''${settings%/*}"
          tmp="$settings.hm-seed"
          if [ -s "$settings" ]; then base="$settings"; else base="$tmp.base"; printf "{}" > "$base"; fi
          ${pkgs.jq}/bin/jq ".hooks.WorktreeCreate = [{hooks: [{type: \"command\", command: \"/run/current-system/sw/bin/holt hook create\"}]}]
            | .hooks.WorktreeRemove = [{hooks: [{type: \"command\", command: \"/run/current-system/sw/bin/holt hook remove\"}]}]
            | .permissions.defaultMode = \"auto\"
            | .tui = \"fullscreen\"
            | .disableAgentView = true
            | .spinnerTipsEnabled = false
            | .statusLine = {type: \"command\", command: \"/run/current-system/sw/bin/claude-statusline\", refreshInterval: 12}
            | .footerLinksRegexes = [{type: \"regex\", pattern: \"(?<owner>[A-Za-z0-9_.-]+)/(?<repo>[A-Za-z0-9_.-]+)#(?<pr>[0-9]+)\", url: \"https://github.com/{owner}/{repo}/pull/{pr}\", label: \"{repo}#{pr}\"}]" \
            "$base" > "$tmp"
          mv "$tmp" "$settings"
          rm -f "$tmp.base"
        ' "$HOME/.claude/settings.json"
      ''
      );

      # Codex — the same agent-pane status wiring, in Codex's own hook file, so a
      # Codex pane lights the `agents` paw and the zellij tab badge exactly like a
      # Claude or Opencode one. Three of its ten events carry the states we draw:
      #
      #   UserPromptSubmit  → working
      #   PermissionRequest → waiting    ← the urgent one; the pill goes amber
      #   Stop              → idle
      #
      # There is deliberately no fourth: Codex has no session-END event (its list
      # stops at Stop), so nothing can report `remove`. agents.sh closes that by
      # asking zellij which panes still exist and dropping the rows of those that
      # don't — which also cleans up after any client that dies without saying
      # goodbye. Schema verified against codex-cli 0.145.0 by running a real turn
      # with `--dangerously-bypass-hook-trust` and watching the hooks fire: it is
      # Claude-shaped (PascalCase event → matcher groups → `{type, command}`
      # handlers), the command runs under `$SHELL -lc` with the session's cwd, and
      # it inherits $ZELLIJ_PANE_ID / $ZELLIJ_SESSION_NAME — which is the whole
      # addressing scheme.
      #
      # First launch after this lands, Codex will ask you to REVIEW the hooks
      # ("Hooks need review") and won't run them until you trust them. That gate
      # is Codex's, it is a good one, and the rice does not try to defeat it —
      # `--dangerously-bypass-hook-trust` exists but appears nowhere here.
      #
      # Merged with jq rather than owned outright: hooks.json is a user-editable
      # file and may hold hooks of your own, which must survive a rebuild.
      # Only written when Codex is actually installed (`agents.clients`).
      home.activation.codexAgentHooks =
        lib.mkIf (devCfg.agents.enable && lib.elem "codex" agentClients)
          (
            lib.hm.dag.entryAfter [ "writeBoundary" ] ''
              run sh -c '
                hooks="$0"
                bin="$1"
                mkdir -p "''${hooks%/*}"
                tmp="$hooks.hm-seed"
                if [ -s "$hooks" ]; then base="$hooks"; else base="$tmp.base"; printf "{}" > "$base"; fi
                ${pkgs.jq}/bin/jq --arg bin "$bin" ".hooks.UserPromptSubmit = [{hooks:[{type:\"command\",command:(\$bin + \" working codex\")}]}]
                  | .hooks.PermissionRequest = [{hooks:[{type:\"command\",command:(\$bin + \" waiting codex\")}]}]
                  | .hooks.Stop = [{hooks:[{type:\"command\",command:(\$bin + \" idle codex\")}]}]" \
                  "$base" > "$tmp"
                mv "$tmp" "$hooks"
                rm -f "$tmp.base"
              ' "$HOME/.codex/hooks.json" "/run/current-system/sw/bin/agent-state"
            ''
          );
    };
}
