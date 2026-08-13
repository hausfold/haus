# The coding-agent clients the rice knows about. Imported the same way as
# gui-wait.nix / keys.nix / nebelung.nix — a plain value, no module system
# involved.
#
#   agentClients = import ../lib/agents.nix;
#
# It lives here because the list had started to fan out. `ai.clients` and
# `ai.default` (modules/ai/options.nix) already shared one `let`-bound copy,
# but sill's `aiUsage.provider` enum was a second, hand-typed one in another
# room's option file — and the two are the same question asked twice, so a
# fourth client would have to be added in both or the bar would refuse to
# display a client the palette could happily spawn.
#
# `specFor()` in holt (hausfold/holt, internal/commands/agent.go) is the one
# copy that CANNOT be folded in: it's the same set on the Go side, and a Go
# binary can't read Nix. Adding a client means editing there too.
#
# And two tables in hearth are keyed BY these ids rather than derived from them,
# because their values are per-client facts this list can't hold: `agentHomes`
# (where that client keeps its instructions file and its skills dir) and
# `clientScopeNote` (which of its own files the rice does NOT own). A client
# added here and not there fails the eval with `attribute '<id>' missing`, which
# names neither file — so add all four in one go.
[
  "claude"
  "codex"
  "opencode"
]
