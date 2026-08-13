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
  # read by ai.clients, ai.default, and sill's aiUsage.provider, so none
  # of the three can drift apart. modules/lib/agents.nix says why it lives there
  # rather than here, and names the one copy that can't be folded in.
  agentClients = import ../lib/agents.nix;
in
{
  options.haus = {
    ai.enable = lib.mkOption {
      type = lib.types.bool;
      # Unchanged behaviour, deliberately: this option was
      # `haus.developer.agents.enable`, whose default was the developer pack's
      # switch, and step 2 of the rooms plan moves ownership without moving
      # values. A room defaulting to another room's switch is exactly the
      # "rooms do not silently enable each other" rule that the desktop carve-out
      # (step 4) exists to fix — the neutral default and the nebelhaus value that
      # replaces it have to land together or an install silently loses the room.
      default = config.haus.developer.enable;
      defaultText = lib.literalExpression "config.haus.developer.enable";
      description = ''
        The AI room: coding-agent *tooling*. `holt` (agent worktrees),
        `agent-state` (the pane-status writer behind the `agents` bar pill and
        the zellij tab badge), the agent-worktree statusline, and the client
        config hearth writes (Claude Code's settings.json keys, opencode's
        agent-state plugin). Which clients get installed is `ai.clients`.

        On, this room brings its clients, `holt` and the lifecycle wiring on its
        own. What it adds to OTHER rooms it adds only when they are present: the
        ⌘A terminal binds and the `c` alias arrive with the terminal, the
        `agents` pill with the bar, the agent commands with the launcher. None
        of those rooms is switched on by turning this one on.

        Off is right for any machine not running coding agents — it's a large
        surface a non-developer never sees. It also empties `ai.clients`,
        since a client with no `holt` to park it is not the deal on offer.

        Was `haus.developer.agents.enable`, and the rest of this namespace was
        `haus.agents.*`, until 2026-08-13. Neither spelling is aliased — see
        modules/moved.nix for why.
      '';
    };

    ai.clients = lib.mkOption {
      type = lib.types.listOf (lib.types.enum agentClients);
      default = lib.optionals config.haus.ai.enable [
        "claude"
        "opencode"
      ];
      # Prose, so literalMD — see developer.languages for why that matters.
      defaultText = lib.literalMD ''[ "claude" "opencode" ] when ai.enable is true, else [ ]'';
      example = [
        "claude"
        "codex"
      ];
      description = ''
        Which coding-agent clients to install. `claude` is Claude Code, `codex`
        is OpenAI Codex, `opencode` is OpenCode. The ⌘A terminal binding starts
        whichever one `ai.default` names — Claude Code through its own
        `--worktree` hook, the others through `holt new`.

        A list rather than one bool per client, matching `developer.languages`
        — a fourth client later doesn't change this option's shape.

        This is the option that makes `ai.default` honest. Naming a client
        you have not installed used to fail *at spawn time*, inside the pane,
        after the worktree already existed: a flash of
        `codex is unavailable`, and litter to reap. `ai.default` must now
        be a member of this list, so the same mistake fails the rebuild
        instead, with both values named.

        Override the package for a client the usual Nix way — an overlay on
        `claude-code`, `codex` or `opencode` — rather than dropping the client
        here and installing your own copy alongside; two derivations shipping
        the same `bin/` name collide in one profile.
      '';
    };

    ai.default = lib.mkOption {
      type = lib.types.enum agentClients;
      default = "claude";
      example = "codex";
      description = ''
        The coding agent started by Pounce's **Spawn Agent** command, by the
        ⌘A / Super-a zellij binds and the `c` shell alias, and used to reopen
        worktrees with no client recorded yet. Each spawned worktree records its
        own client, so changing this affects new work but never reopens an
        existing Codex or OpenCode task in Claude.

        Must be one of `ai.clients` — see there.

        Only `claude` can make its own worktree (its native `--worktree` flag,
        which fires `holt hook create`); for `codex` and `opencode` ⌘A runs
        `holt new` instead, producing the same checkout, branch and registry
        entry from the outside. Resuming follows the client too: `codex` reopens
        its cwd-filtered `codex resume` picker, `opencode` continues its latest
        session for that cwd. All three share one `holt` branch/parking/reap
        lifecycle, and all three light up the `agents` bar pill and the zellij
        tab-bar badge — the opencode plugin and the codex hooks are written for
        you; only Claude Code's stay yours to wire, because Claude owns its own
        settings.json (see `haus.sill.items.agents`).
      '';
    };

    # The two files the rice ships into an agent's home, one option each. Both
    # were `haus.claude.*` until 2026-08-11 and wrote only Claude Code's copy —
    # which made `ai.default = "codex"` a half-truth: the client spawned,
    # with none of the operating context or the option knowledge the same
    # machine hands Claude. They are named for the ROOM, not the client, and
    # hearth writes one copy per entry in `ai.clients` (renamed.nix keeps
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
        to the other two. When set, the rice prepends two short sections of its
        own — a note that the file is generated and where to actually edit it
        (with THAT client's path), and the `holt` worktree etiquette, since the
        rice ships `holt` and that rule is what keeps it working — then your
        text.

        Empty (the default) writes nothing at all, for any client, so a
        hand-managed instructions file is never clobbered just to inject the
        rice's note. If you set it and one of those paths already holds a file
        you wrote by hand, home-manager moves yours aside as `<file>.backup`
        rather than refusing — quiet, so check for one before the first rebuild
        after setting this.

        With `ai.clients` empty (a machine the rice installs no client on)
        every known client's path is written instead of none: the list being
        empty means the rice installs none, not that no agent runs here.
      '';
    };

    ai.skill = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Install the `haus` skill for every client in `ai.clients`, so an
        agent asked to "install Slack" or "make everything bigger" edits your
        host file and runs `haus rebuild` instead of guessing at dotfiles and
        `brew install`.

        One copy per client, in the directory that client scans:
        `~/.claude/skills/haus`, `~/.codex/skills/haus`,
        `~/.config/opencode/skills/haus`. OpenCode also scans `~/.claude/skills`
        for Claude Code compatibility, and prefers its own copy when both
        exist — so a machine running both clients sees the skill once, not
        twice.

        The skill's option reference is GENERATED from the rice revision this
        machine is pinned to, so it can only ever describe options that
        actually exist here — and it is regenerated by `haus update`. It also
        carries this host's current state (which rooms are on, where the host
        file is) and a starter AGENTS.md + CLAUDE.md pair for your config repo —
        the rules in the first, a one-line import in the second, so a session
        opened there is oriented whichever client it runs.

        Unrelated to the clients' own settings, which follow
        `haus.ai.enable`. This is a plain file drop: with
        `ai.clients` empty — a machine the rice installs no client on, which
        can still have one from npm or Homebrew — every known client's directory
        gets a copy rather than none. Set false to leave every client's skills
        directory alone.
      '';
    };
  };
}
