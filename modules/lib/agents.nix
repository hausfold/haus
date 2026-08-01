# The coding-agent clients the rice knows about. Imported the same way as
# gui-wait.nix / keys.nix / nebelung.nix — a plain value, no module system
# involved.
#
#   agentClients = import ../lib/agents.nix;
#
# It lives here because the list had started to fan out. `agents.clients` and
# `agents.default` (modules/options.nix) already shared one `let`-bound copy,
# but sill's `aiUsage.provider` enum was a second, hand-typed one in another
# room's option file — and the two are the same question asked twice, so a
# fourth client would have to be added in both or the bar would refuse to
# display a client the palette could happily spawn.
#
# `agent_known()` in modules/den/wt.sh is the one copy that CANNOT be folded in:
# it's the same set on the shell side, and a shell script can't read Nix. Adding
# a client means editing there too.
[
  "claude"
  "codex"
  "opencode"
]
