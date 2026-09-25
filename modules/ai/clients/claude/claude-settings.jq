# ~/.claude/settings.json, as haus re-asserts it on every rebuild.
#
# Read by the `claudeCodeSettings` activation in ./default.nix, which hands it
# the file Claude Code already had (`$base`) and two arguments:
#
#   $auto[0]  the `autoMode` sections haus DECLARES this generation, already
#             carrying the `"$defaults"` marker wherever `keepDefaults` asked
#             for one. `{}` when the host names none.
#   $prev[0]  the section names haus WROTE last generation, read back from
#             ~/.local/state/haus/claude-auto-mode-sections. `[]` on a machine
#             that has never had one.
#
# A program in a file rather than a filter argument, which is not tidying. The
# activation is one single-quoted `sh -c` argument, so everything in it used to
# arrive through a nix'' → sh'' → jq"" escaping stack: every string doubled its
# quotes, `$auto` had to be written `\$auto` to survive the shell, and a lone
# apostrophe ANYWHERE — a comment included — ended the argument early and
# re-parsed the rest of the script (see the warning in ./default.nix, which is
# what that cost on 2026-08-27). Out here the quotes are jq's own, and a comment
# can say "the machine's" without breaking an activation.
#
# It also makes the thing testable off the shelf: `test/claude-auto-mode.bats`
# runs THIS file with the real jq against fixtures, on a Linux runner with no
# Nix and no Mac. That is the whole reason the program is static — nothing below
# is interpolated, and nothing below should become interpolated. A value that
# has to come from Nix arrives as a `--slurpfile`, the way both of these do.
#
# Merged, never assigned: Claude Code rewrites this file on its own schedule and
# the user writes to it by hand and through `claude auto-mode`, so every clause
# here either sets one key haus owns outright or folds haus's entry into a list
# that may already hold theirs.

  .hooks.WorktreeCreate = [{hooks: [{type: "command", command: "/run/current-system/sw/bin/scruff hook create"}]}]
| .hooks.WorktreeRemove = [{hooks: [{type: "command", command: "/run/current-system/sw/bin/scruff hook remove"}]}]
| .hooks.PreToolUse = (((.hooks.PreToolUse // []) | map(select([.hooks[]?.command] | any(. == "/run/current-system/sw/bin/agent-desktop-guard" or . == "/run/current-system/sw/bin/agent-desktop-ask") | not))) + [{matcher: "Bash|mcp__computer-use__.*", hooks: [{type: "command", command: "/run/current-system/sw/bin/agent-desktop-guard"}]}])
| .hooks.Notification = (((.hooks.Notification // []) | map(select([.hooks[]?.command] | index("/run/current-system/sw/bin/scruff hook notify") | not))) + [{hooks: [{type: "command", command: "/run/current-system/sw/bin/scruff hook notify"}]}])
| .hooks.Stop = (((.hooks.Stop // []) | map(select([.hooks[]?.command] | index("/run/current-system/sw/bin/scruff hook notify") | not))) + [{hooks: [{type: "command", command: "/run/current-system/sw/bin/scruff hook notify"}]}])
| .hooks.UserPromptSubmit = (((.hooks.UserPromptSubmit // []) | map(select([.hooks[]?.command] | index("/run/current-system/sw/bin/scruff hook notify") | not))) + [{hooks: [{type: "command", command: "/run/current-system/sw/bin/scruff hook notify"}]}])
| .hooks.PostToolUse = (((.hooks.PostToolUse // []) | map(select([.hooks[]?.command] | index("/run/current-system/sw/bin/scruff hook notify") | not))) + [{hooks: [{type: "command", command: "/run/current-system/sw/bin/scruff hook notify"}]}])
| .permissions.defaultMode = "auto"
| .tui = "fullscreen"
| .disableAgentView = true
| .spinnerTipsEnabled = false
| .statusLine = {type: "command", command: "/run/current-system/sw/bin/claude-statusline", refreshInterval: 12}
| .footerLinksRegexes = [{type: "regex", pattern: "(?<owner>[A-Za-z0-9_.-]+)/(?<repo>[A-Za-z0-9_.-]+)#(?<pr>[0-9]+)", url: "https://github.com/{owner}/{repo}/pull/{pr}", label: "{repo}#{pr}"}]

# ---- the auto-mode classifier's picture of this machine ---------------------
#
# `.autoMode` is ONE object holding four independent lists, and `claude
# auto-mode` writes into the same object. So haus owns the sections it NAMES
# and leaves the rest alone: a host that declares only `allow` must never cost
# someone the `hard_deny` they wrote with the CLI, and taking a refusal away as
# a side effect of adding a permission is the kind of thing nobody reads a diff
# to discover.
#
# Undeclaring a section is a DELETE, and $prev is the only reason it can be.
# Without a record of what haus wrote last time, "haus has no opinion about
# this section" and "haus has never had one" look identical from in here — so
# the safe reading was to leave everything, and an `allow` rule went on lifting
# refusals for a machine whose config had stopped asking for it. A section
# haus is listed as having written and no longer declares goes; a section it
# never wrote stays, whatever is in it.
#
# What that costs, and it is the right cost: a `claude auto-mode` edit INSIDE a
# section haus declared is haus's to overwrite, and to remove with the section.
# The last rebuild that named a section owns its contents.
#
# Both empty is the machine that has never named one, and it must come out
# byte-identical to the file that arrived — a malformed `.autoMode` included,
# since there is nothing here to be right about yet.
#
# The `type == "object"` guard is there because `+` against a string or null is
# a jq ERROR, and what a jq error costs here is worse than a crash: the `&& mv`
# in ./default.nix short-circuits, but that block ends in `rm -f`, so the step
# still exits 0 and the rebuild carries on with the whole file unmerged — no
# hooks, no statusline, no `permissions.defaultMode`, and nothing on either
# stream to say so. A malformed `.autoMode` costs its own contents, never the
# rest of the program. $prev gets the same treatment for the same reason, and
# it is the second of two: the activation drops a record jq cannot PARSE before
# it gets here, and this is what catches one that parses into the wrong thing.

| (
    ($prev[0] | if type == "array" then map(select(type == "string")) else [] end) as $wrote
    | if ($auto[0] | length) == 0 and ($wrote | length) == 0 then
        .
      else
        .autoMode = (
          (.autoMode | if type == "object" then . else {} end)
          | delpaths([$wrote - ($auto[0] | keys) | .[] | [.]])
          | . + $auto[0]
        )
        # Nothing left of it: drop the key rather than leave `"autoMode": {}`
        # behind, so a machine that has been reset reads as one that was never
        # set. Claude Code treats the two the same; a person reading the file
        # does not.
        | if (.autoMode | length) == 0 then del(.autoMode) else . end
      end
  )
