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

    # The two files the rice ships into an agent's home, one option each. Both
    # were `haus.claude.*` until 2026-08-11 and wrote only Claude Code's copy —
    # which made `ai.default = "codex"` a half-truth: the client spawned,
    # with none of the operating context or the option knowledge the same
    # machine hands Claude. They are named for the ROOM, not the client, and
    # terminal writes one copy per entry in `ai.clients` (renamed.nix keeps
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
