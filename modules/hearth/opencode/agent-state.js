// agent-state.js — Opencode's half of the rice's agent-pane status.
//
// Installed by hearth as ~/.config/opencode/plugin/nebelhaus-agent-state.js,
// with BIN below rendered to den's `agent-state` by absolute path (a plugin gets
// no PATH guarantees). It is the Opencode equivalent of the four Claude Code
// hooks a nebelhaus host wires into ~/.claude/settings.json, mapping this
// client's lifecycle onto the same four words agent-state understands:
//
//     chat.message    → working    a turn just started
//     permission.ask  → waiting    the agent is blocked on you  ← the urgent one
//     session.idle    → idle       the turn finished
//     dispose         → remove     the client is going away
//
// Both readers (sill's `agents` paw pill, hearth's zellij tab-bar badge) then
// treat an Opencode pane exactly like a Claude one.
//
// Why this works at all: the plugin runs inside the Opencode server process,
// which is a child of the `opencode` you started in a zellij pane, so it
// inherits $ZELLIJ_SESSION_NAME + $ZELLIJ_PANE_ID — which is the whole
// addressing scheme (agent-state exits silently when they're absent, so a
// bare-terminal Opencode stays invisible, as intended).
//
// Caveat, deliberate: `opencode attach <url>` talks to a server started
// somewhere else, so its state is filed under THAT server's pane, not the pane
// you attached from. Rare enough not to warp the design for.

export const NebelhausAgentState = async ({ directory }) => {
  const BIN = "@AGENT_STATE@"

  // Fire and forget. The bar is a nicety; a missing binary, a busy disk, or no
  // zellij at all must never surface as a failed hook in someone's chat.
  const report = (state, wait = false) => {
    try {
      const opts = {
        cmd: [BIN, state, "opencode"],
        cwd: directory,
        stdout: "ignore",
        stderr: "ignore",
      }
      // `remove` is the one report that must land before we're gone: dispose is
      // the last thing that runs, and an async child would be orphaned (or
      // killed) mid-write, leaving a dead pane on the bar until the 12h reaper.
      if (wait) Bun.spawnSync(opts)
      else Bun.spawn(opts)
    } catch {
      /* never break a turn over a menu-bar pill */
    }
  }

  return {
    "chat.message": async () => report("working"),
    "permission.ask": async () => report("waiting"),
    event: async ({ event }) => {
      if (event?.type === "session.idle") report("idle")
    },
    dispose: async () => report("remove", true),
  }
}
