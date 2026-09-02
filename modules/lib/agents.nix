# The coding-agent clients haus knows about. Imported the same way as
# gui-wait.nix / keys.nix / nebelung.nix — a plain value, no module system
# involved.
#
#   agentClients = import ../lib/agents.nix;
#
# It lives here because the list had started to fan out. `ai.clients` and
# `ai.default` (modules/ai/options.nix) already shared one `let`-bound copy,
# but bar's `aiUsage.provider` enum was a second, hand-typed one in another
# room's option file — and the two are the same question asked twice, so a
# new client would have to be added in both or the bar would refuse to
# display a client the palette could happily spawn.
#
# `specFor()` in scruff (hausfold/scruff, internal/commands/agent.go) is the one
# copy that CANNOT be folded in: it's the same set on the Go side, and a Go
# binary can't read Nix. Adding a client means editing there too — and scruff is a
# flake input, so the id has to land THERE first and ripple down, or every lane
# spawned with the new client dies on `unknown agent`.
#
# Every client here is installed from nixpkgs, so it also needs a derivation in
# modules/lib/agent-packages.nix. And what a client id must have in every case
# is a `scruff` spec: the id is what `ai.default` is typed against, and a default
# scruff can't spawn is the dead-pane failure `ai.clients` exists to end.
#
# And three more tables are keyed BY these ids rather than derived from them,
# because their values are per-client facts this list can't hold. Two are in the
# AI room (modules/ai/default.nix): `agentHomes` (where that client keeps its
# instructions file and its skills dir) and `clientScopeNote` (which of its own
# files haus does NOT own). The third is modules/lib/agent-oneshot.nix — how
# to run that client for ONE headless turn, which is what `haus fix` needs.
#
# The oneshot table CHECKS ITSELF against this file and throws by name; the two
# in the AI room fail the eval with `attribute '<id>' missing`, which names
# neither file. So a new client is five edits in one go: here, agent-packages,
# agent-oneshot, and the AI room's two.
[
  "claude"
  "codex"
  "opencode"
  "pi"
]
