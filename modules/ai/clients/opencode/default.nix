# OpenCode. The record modules/ai/clients/default.nix describes; the AI room
# renders it. Its theme (tui.json, the nebelung port) is modules/terminal's,
# with every other theme drop.
{
  package = pkgs: pkgs.opencode;

  # Verified with `opencode debug skill`, which lists ~/.config/opencode/skills/*.
  #
  # OpenCode also scans `~/.claude/skills` for Claude Code compatibility, so a
  # machine running both clients has two copies of each haus skill in its
  # reach. That is safe on purpose: the same probe shows opencode deduplicating
  # by frontmatter `name` and preferring its OWN directory, so the skill is
  # offered once. (Its docs only say "ensure skill names are unique", which is
  # why this was probed.)
  home = {
    instructions = ".config/opencode/AGENTS.md";
    skills = ".config/opencode/skills";
  };

  # `run` takes the message as positionals. `--auto` is opencode's own word
  # for the bypass ("auto-approve permissions that are not explicitly
  # denied"), and its own `--help` calls it dangerous — which it is, and is
  # the point. yargs has `populate--` off by default, so operands after `--`
  # land in `_`. Verified against opencode 1.x's `--help`, 2026-08-31.
  oneshot = [
    "opencode"
    "run"
    "--auto"
    "--"
  ];

  scopeNote = "`opencode.json` is OpenCode's own, and a host may wire individual skills or plugins as out-of-store symlinks";

  files = {
    # Opencode's half of the agent status the bar's `agents` pill draws.
    # Claude Code's equivalent is four hooks in ~/.claude/settings.json,
    # which the USER wires (Claude owns that file and rewrites it, so haus
    # never has); opencode instead auto-loads every file under this directory,
    # so haus can own the whole wiring and a fresh machine gets a working
    # pill for opencode panes with nothing to configure.
    # @AGENT_STATE@ → core's `agent-state` by absolute path: a plugin runs
    # inside opencode's server process, which is given no PATH guarantees.
    ".config/opencode/plugin/haus-agent-state.js".text =
      builtins.replaceStrings [ "@AGENT_STATE@" ] [ "/run/current-system/sw/bin/agent-state" ]
        (builtins.readFile ./agent-state.js);
  };
}
