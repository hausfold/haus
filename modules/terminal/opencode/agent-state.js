// agent-state.js — Opencode's half of the rice's agent status.
//
// Installed by terminal as ~/.config/opencode/plugin/haus-agent-state.js,
// with BIN below rendered to core's `agent-state` by absolute path (a plugin gets
// no PATH guarantees). It is the Opencode equivalent of the four Claude Code
// hooks a haus host wires into ~/.claude/settings.json, mapping this
// client's lifecycle onto the same four words agent-state understands:
//
//     chat.message    → working    a turn just started
//     permission.ask  → waiting    the agent is blocked on you  ← the urgent one
//     session.idle    → idle       the turn finished
//     dispose         → remove     the client is going away
//
// The reader (bar's `agents` pill) then treats an Opencode window exactly
// like a Claude one.
//
// Why this works at all: the plugin runs inside the Opencode server process,
// which is a child of the `opencode` you started in a terminal window, so it
// inherits $ZMX_SESSION — which is the whole addressing scheme (agent-state
// exits silently when it's absent, so a bare-terminal Opencode stays invisible,
// as intended).
//
// Caveat, deliberate: `opencode attach <url>` talks to a server started
// somewhere else, so its state is filed under THAT server's session, not the
// window you attached from. Rare enough not to warp the design for.

export const HausAgentState = async ({ directory }) => {
  const BIN = "@AGENT_STATE@"

  // The conversation this window is showing. `chat.message` is the only hook that
  // carries it (`input.sessionID`, verified against the plugin Hooks interface),
  // so latch it on the first turn and pass it on every later report — the states
  // that fire without it (waiting/idle) would otherwise have nothing to send,
  // and agent-state refuses to blank an id it already holds.
  //
  // This is what lets terminal's ⌘F find overlay search an Opencode window's
  // whole conversation instead of its scrollback. The TUI is alt-screen, so
  // scrollback is a single screenful; the history lives in opencode's SQLite db,
  // keyed by exactly this id. agent-state records it as a `convo` label on the
  // zmx session. Claude Code gets the same reach from claude-statusline's
  // session → transcript map — this is Opencode's equivalent, and the only piece
  // it was missing, because the plugin already runs inside the opencode server
  // process and so inherits $ZMX_SESSION.
  let sessionID = ""

  // Fire and forget. The bar is a nicety; a missing binary, a busy disk, or not
  // being on a haus machine at all must never surface as a failed hook in
  // someone's chat.
  const report = (state, wait = false) => {
    try {
      const opts = {
        cmd: [BIN, state, "opencode", sessionID],
        cwd: directory,
        stdout: "ignore",
        stderr: "ignore",
      }
      // `remove` is the one report that must land before we're gone: dispose is
      // the last thing that runs, and an async child would be orphaned (or
      // killed) mid-write, leaving a stale row on the bar for as long as the
      // session outlives the client.
      if (wait) Bun.spawnSync(opts)
      else Bun.spawn(opts)
    } catch {
      /* never break a turn over a menu-bar pill */
    }
  }

  return {
    "chat.message": async (input) => {
      if (input?.sessionID) sessionID = input.sessionID
      report("working")
    },
    "permission.ask": async () => report("waiting"),
    event: async ({ event }) => {
      if (event?.type === "session.idle") report("idle")
    },
    dispose: async () => report("remove", true),
  }
}
