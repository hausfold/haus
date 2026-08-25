# The AI room's option surface: `haus.ai.*`.
#
# These declarations lived in modules/options.nix — the file for what no single
# room owns — because the AI capability had no room to live in. It has one now
# (modules/ai), and the whole namespace moved with it: `haus.agents.*` became
# `haus.ai.*`, and the switch that sat outside it altogether
# (`haus.developer.agents.enable`) became `haus.ai.enable`. One room, one
# namespace, one on/off. No aliases — modules/moved.nix says why.
#
# The room is the first proof of the cross-room contract in
# notes/rooms-desktops.md: AI OWNS the capability, and the rooms that present it
# (Development's terminal binds, the Bar's pill, the Launcher's commands) own
# the extension points it writes to. See modules/ai/default.nix.
{ lib, config, ... }:

let
  # Every coding-agent client the rice knows how to install, spawn and resume —
  # read by ai.clients, ai.default, and bar's aiUsage.provider, so none
  # of the three can drift apart. modules/lib/agents.nix says why it lives there
  # rather than here, and names the one copy that can't be folded in.
  agentClients = import ../lib/agents.nix;
in
{
  options.haus = {
    ai.enable = lib.mkOption {
      type = lib.types.bool;
      # Rooms are independent. hacker selects AI in its desktop; the neutral
      # room catalogue leaves it off until a desktop or host asks for it.
      default = false;
      defaultText = lib.literalExpression "false";
      description = ''
        The AI room: coding-agent *tooling*. `holt` (agent worktrees),
        `agent-state` (the status writer behind the `agents` bar pill),
        the agent-worktree statusline, `tart` and the adapter that drives it
        (SPEC.md §5.5 — `holt runtime up|enter|down --backend tart` stands a
        lane up in its own headless macOS, so an agent can feel-test a desktop
        change without touching the screen its user is sitting at; pulling a
        base image is still a manual, one-time step), and the client
        config the Terminal room writes (Claude Code's settings.json keys, opencode's
        agent-state plugin). Which clients get installed is `ai.clients`.

        On, this room brings its clients, `holt` and the lifecycle wiring on its
        own. What it adds to OTHER rooms it adds only when they are present: the
        `c` alias arrives with the terminal, the
        `agents` pill with the bar, the agent commands with the launcher. None
        of those rooms is switched on by turning this one on.

        Off is right for any machine not running coding agents — it's a large
        surface a non-developer never sees. The neutral default installs no
        clients; a desktop that selects this room names both `ai.clients` and
        `ai.default`.

        Was `haus.developer.agents.enable`, and the rest of this namespace was
        `haus.agents.*`, until 2026-08-13. Neither spelling is aliased — see
        modules/moved.nix for why.
      '';
    };

    ai.clients = lib.mkOption {
      type = lib.types.listOf (lib.types.enum agentClients);
      default = [ ];
      defaultText = lib.literalExpression "[ ]";
      example = [
        "claude"
        "codex"
      ];
      description = ''
        Which coding-agent clients to install. `claude` is Claude Code, `codex`
        is OpenAI Codex, `opencode` is OpenCode. The ⌘↵ lane chord starts
        whichever one `ai.default` names, all of them through `holt new`.

        A list rather than one bool per client, matching `developer.languages`
        — a client added later doesn't change this option's shape.

        This is the option that makes `ai.default` honest. Naming a client
        you have not installed used to fail *at spawn time*, inside the pane,
        after the worktree already existed: a flash of
        `codex is unavailable`, and litter to reap. `ai.default` must now
        be a member of this list, so the same mistake fails the rebuild
        instead, with both values named.

        Override a client's package the usual Nix way — an overlay on
        `claude-code`, `codex` or `opencode` — rather than dropping the client
        here and installing your own copy alongside; two derivations shipping
        the same `bin/` name collide in one profile.

        Ignored entirely when `ai.enable` is off — see `haus._ai.clients`, the
        resolved list every room actually installs from. Before step 4 this was
        an assertion instead ("clients are set but the room is off"), which was
        right while the list defaulted from the room's own switch and wrong
        afterwards: a desktop names the clients, so a host turning the room off
        would have had to blank the desktop's list as well to get a rebuild at
        all. One switch now removes the room, which is what "clean removal when
        disabled" means.
      '';
    };

    # The list as the rest of the rice must read it. `ai.clients` is what
    # somebody WROTE; this is what this machine actually installs, which is the
    # same thing gated on the room being on at all. Internal, because it is a
    # resolution rather than a setting — see modules/lib/contrib.nix for the
    # same reasoning applied to cross-room wiring.
    _ai.clients = lib.mkOption {
      internal = true;
      readOnly = true;
      type = lib.types.listOf (lib.types.enum agentClients);
      default = lib.optionals config.haus.ai.enable config.haus.ai.clients;
      description = "Resolved coding-agent clients: `ai.clients` when the AI room is on, else none.";
    };

    ai.default = lib.mkOption {
      type = lib.types.enum agentClients;
      default = "claude";
      example = "codex";
      description = ''
        The coding agent started by the ⌘↵ lane chord, by the palette's
        **Spawn Agent** command and by the `c` shell
        alias, and used to reopen worktrees with no client recorded yet. Each spawned worktree records its
        own client, so changing this affects new work but never reopens an
        existing Codex or OpenCode task in Claude.

        Must be one of `ai.clients` — see there.

        This option chooses the client and nothing else about how a lane opens.
        `claude` can make its own worktree (its native `--worktree` flag, which
        fires `holt hook create`), but haus does not use it: that flag runs the
        client in the pane it was launched from and never asks holt's `[hooks]
        open`, which is the seam a lane's own window arrives through. So every
        client goes through `holt new`, producing the same checkout, branch and
        registry entry from the outside — and the lane stays resumable, because
        Claude keys a transcript to the directory it started in.
        Resuming follows the client too: `codex` reopens
        its cwd-filtered `codex resume` picker, `opencode` continues its latest
        session for that cwd. They share one `holt` branch/parking/reap
        lifecycle, and they all light up the `agents` bar pill — the opencode
        plugin and the codex hooks are written for
        you; only Claude Code's stay yours to wire, because Claude owns its own
        settings.json (see `haus.bar.items.agents`).
      '';
    };

    # What NAMES a lane that arrives with a task but no name. holt's own key,
    # spelled verbatim: it runs one argv from
    # `~/.config/holt/adapters/namer/<id>.toml` and reads a word off stdout, so
    # haus only has to carry the id — the adapter file names the program, and
    # holt never holds a key or knows a vendor.
    ai.namer = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "api";
      description = ''
        The holt namer adapter that turns a lane's first-turn brief into the
        lane's name — `mobile-nav-jitter` instead of `cozy-otter`. Empty, the
        default, means no namer: an unnamed lane keeps taking a random word
        pair, which is what every install had before the key existed.

        `claude` is holt's one built-in, and it costs 8-12s per lane — almost
        all of it the client's own start-up rather than the model. Any other id
        is a file you write: `~/.config/holt/adapters/namer/<id>.toml`, naming
        a program that takes the brief on argv and prints one name. That file
        is the HOST's, not the layer's, because it is where the model, the key
        and its location get decided; haus deliberately carries only the id, so
        a machine that hasn't written the adapter degrades to random names
        rather than failing to build.

        It cannot cost you a lane. Every failure — no adapter file, a missing
        program, a timeout at holt's 30s ceiling, prose instead of a name — is
        a warning and a fall back to the random pair.

        **The offline floor is the adapter's to honour.** The palette's Spawn
        Agent has always named the lane itself, from a stopword slug of your
        prompt, and it stops doing that when this is set — so it hands the slug
        down as `HOLT_NAMER_FALLBACK` and expects an adapter that cannot reach
        its model to print that instead of failing. holt neither sets nor reads
        that variable; it only passes the environment through. An adapter that
        ignores it makes an offline spawn fall to the random pair, which is
        worse than the slug the palette would have used.

        `claude` is excluded from the palette path for exactly that reason: its
        argv is fixed and reads no environment, so it cannot meet the contract —
        and at 8-12s it would outlive the palette's own 8-second chain fade.
        Set it and hand-run `holt spawn` still asks it; Spawn Agent keeps its
        slug.
      '';
    };

    # Where the palette looks for something to spawn ON. It is an AI-room fact
    # rather than a launcher one — the same list would answer "which repos can
    # I lane into" for any surface that asked — so it lives here and reaches
    # the palette through `_contrib.launcher.agents`, which is also the only
    # way it can reach the pounce DAEMON at all: a launchd GUI agent inherits
    # nothing from your shell, so the `$HAUS_REPO_ROOTS` this used to be was
    # unsettable in the one process that reads it.
    # ---- keeping the Mac awake while agents work ----------------------------
    # A PROFILE, in the sense modules/appearance/default.nix uses the word: the
    # AI room owns the intent ("let my agents finish"), the power room owns the
    # machinery, and this option answers the first by writing the second at
    # `mkDefault`. The room boundary is what makes that the right shape --
    # `disablesleep` is nothing to do with coding agents, and `haus.ai` has no
    # business knowing what a pmset key is.
    ai.keepAwake = lib.mkOption {
      type = lib.types.enum [
        "off"
        "idle"
        "lid"
      ];
      default = "off";
      example = "idle";
      description = ''
        Let agents hold this Mac awake while they are mid-turn.

        Three stops, each one deeper than the last:

        `off` (the default) -- agents get no say. macOS sleeps on its own
        schedule and a run that was still going is simply over.

        `idle` -- a `caffeinate` assertion for exactly as long as an agent is
        working. This is the gap most people actually hit: with the lid OPEN
        and nobody at the keyboard, `haus.power.displaySleep` and
        `haus.power.computerSleep` end an overnight run without anything having
        closed. Needs no privilege, and works on battery, because closing the
        lid still sleeps the Mac, so the closed-laptop-cooking-in-a-bag case
        this stop cannot cause.

        `lid` -- the above, plus turning on `haus.power.lidAwake`, whose root
        daemon holds macOS's `disablesleep`. That is the only lever that
        crosses a lid close, and shutting the lid is the one gesture everybody
        reads as "stop", so it is the stop you have to name deliberately.

        The signal is the one the bar's agents pill already draws, reported by
        every client haus knows, and an agent parked at a permission prompt
        does NOT hold: it is blocked on a human who is not there.

        What this sets rather than owns: `lid` writes
        `haus.power.lidAwake.enable` at `mkDefault`, so a host that names that
        option itself always wins and is told, in a warning, that it did. How
        long a hold lingers past the last turn and how long one may last stay
        where the machinery is (`haus.power.lidAwake.linger` and `.maxHold`),
        and both stops read them -- this is a switch, not a second copy of the
        dial.

        Two knobs there do NOT reach this option. `requirePower` guards the
        **lid** hold only: its argument is that nothing can stop a closed
        laptop cooking in a bag, and at the `idle` stop the lid still sleeps
        the Mac, so an unplugged laptop sitting open on a desk is exactly the
        case worth protecting. And `while = "always"` -- plain closed-display
        mode -- shapes the lid daemon alone; this option means "while my agents
        work" at both stops and never turns into an unconditional hold.

        Host-only, so a shared desktop may not set it: `lid` reaches into
        `haus.power.*`, which is a namespace about one machine's hardware, and
        starts a root daemon there.

        Needs `ai.enable`: the hold signal is written by the agent hooks this
        room installs, so with the room off nothing would ever report a turn.
      '';
    };

    ai.repoRoots = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "~/code"
        "~/src"
        "~/Developer"
        "~/Projects"
        "~/.config/nix"
      ];
      # Spelled on ONE line for ../host-template.jq — the same escape hatch
      # `haus.wallpaper.debug.inputs` uses, and for the same reason: the
      # annotated host file comments each default with `  # `, and its "is this
      # still legal once uncommented" check un-comments only the line the option
      # NAME is on. A default rendered across several lines leaves the rest
      # commented, and the template stops parsing at the NEXT option — which is
      # how this one first showed up, as `haus.ai.skill = true;` failing to parse.
      defaultText = lib.literalExpression ''[ "~/code" "~/src" "~/Developer" "~/Projects" "~/.config/nix" ]'';
      example = [
        "~/code"
        "~/work/clients"
        "~/.config/nix"
      ];
      description = ''
        Where the palette's **Spawn Agent** finds repositories, most recently
        touched first. A leading `~/` is expanded; a path that does not exist is
        skipped in silence, so the default list can name four conventions and
        cost nothing for the three you don't use.

        Each entry is read TWO ways, and which one applies is decided by the
        path itself:

        - **a repo** (it has a `.git` directory) is offered as itself, and is
          not descended into — that is how `~/.config/nix`, the config flake
          this Mac is built from, is in the default list without `~/.config`
          being scanned.
        - **anything else** is scanned two levels deep for main checkouts, so
          both `~/code/thing` and a parent directory full of repos
          (`~/code/workshop/thing`) resolve.

        Repos `holt` already knows are always offered too, whether or not they
        are under a root here — so a one-off repo you have agent'd before stays
        reachable, and this list is about the ones you have not.
      '';
    };

    # The two files the rice ships into an agent's home, one option each. Both
    # were `haus.claude.*` until 2026-08-11 and wrote only Claude Code's copy —
    # which made `ai.default = "codex"` a half-truth: the client spawned,
    # with none of the operating context or the option knowledge the same
    # machine hands Claude. They are named for the ROOM, not the client, and
    # terminal writes one copy per entry in `ai.clients` (moved.nix keeps
    # the old names working, with a warning).
    ai.instructions = lib.mkOption {
      type = lib.types.lines;
      default = "";
      example = ''
        # How I work
        Ship small, verified changes; ask before anything hard to reverse…
      '';
      description = ''
        Your always-on, cross-project operating context — the "instructions"
        slot every client has under a different name. Written once per client
        in `ai.clients`, to the path that client actually reads:
        `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`,
        `~/.config/opencode/AGENTS.md`.

        Write it client-neutrally: the same text reaches whichever agent the ⌘A
        pane spawns, so a line about a Claude-only skill or file path is noise
        to the others. When set, haus prepends three short sections of its
        own — a note that the file is generated and where to actually edit it
        (with THAT client's path), the `holt` worktree etiquette, since haus
        ships `holt` and that rule is what keeps it working, and the screen
        etiquette that pairs with `agent-desktop-guard` — then your text.

        Empty (the default) writes nothing at all, for any client, so a
        hand-managed instructions file is never clobbered just to inject
        haus's note. If you set it and one of those paths already holds a file
        you wrote by hand, home-manager moves yours aside as `<file>.backup`
        rather than refusing — quiet, so check for one before the first rebuild
        after setting this.

        With `ai.clients` empty (a machine haus installs no client on)
        every known client's path is written instead of none: the list being
        empty means haus installs none, not that no agent runs here.
      '';
    };

    ai.skill = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Install every hausfold tool's agent skill for each client in
        `ai.clients`, so an agent asked to "install Slack" or "make everything
        bigger" edits your host file and runs `haus rebuild` instead of guessing
        at dotfiles and `brew install` — and an agent asked "what worktrees do I
        have open?" or "hand this off to a fresh session" reaches for `holt`
        rather than `git worktree`.

        Three skills today: `haus` (this machine's setup), and holt's own two —
        `holt` (the lane lifecycle) and `handoff` (turning work into a brief a
        cold session can act on, ending on the clipboard or in a new lane). Each
        tool names its own skills; haus only decides that they are installed.

        One copy per client, in the directory that client scans:
        `~/.claude/skills/haus`, `~/.codex/skills/haus`,
        `~/.config/opencode/skills/haus`, and the same three directories again
        per skill. OpenCode also
        scans `~/.claude/skills`
        for Claude Code compatibility, and prefers its own copy when both
        exist — so a machine running both clients sees each skill once, not
        twice.

        The skill's option reference is GENERATED from the haus revision this
        machine is pinned to, so it can only ever describe options that
        actually exist here — and it is regenerated by `haus update`. It also
        carries this host's current state (which rooms are on, where the host
        file is) and a starter AGENTS.md + CLAUDE.md pair for your config repo —
        the rules in the first, a one-line import in the second, so a session
        opened there is oriented whichever client it runs.

        Unrelated to the clients' own settings, which follow
        `haus.ai.enable`. This is a plain file drop: with
        `ai.clients` empty — a machine haus installs no client on, which
        can still have one from npm or Homebrew — every known client's directory
        gets a copy rather than none. Set false to leave every client's skills
        directory alone.
      '';
    };
  };
}
