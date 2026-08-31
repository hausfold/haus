# One coding-agent client id → the argv that runs it ONCE, headless, with its
# permission gate open. The prompt is appended as the final argument.
#
#   agentOneshot = import ../lib/agent-oneshot.nix;
#   argv = agentOneshot.claude ++ [ prompt ];
#
# It is the third table keyed by modules/lib/agents.nix's client ids, beside
# modules/lib/agent-packages.nix (what installs a client) and the AI room's
# `agentHomes` (where a client keeps its files). This one answers the question
# neither of those can: how do you hand this client one prompt, get one answer,
# and never draw a TUI — which is what `haus-fix` needs and what nothing in the
# rice needed before it. scruff's own specs are the INTERACTIVE shape (a lane,
# a window, a person), so they are not this and cannot be reused for it.
#
# Unlike its two siblings, this table CHECKS ITSELF: it reads agents.nix and
# throws on any id it has no entry for. A missing spec here would otherwise
# only surface on the machine whose `ai.default` happened to name it.
#
# ── the three things every entry has to get right ────────────────────────────
#
# 1. NON-INTERACTIVE. A TUI in a process with no terminal is a hang, and this
#    is called from a trill pill and from a detached holder — neither has one.
#    claude `-p`, codex `exec`, opencode `run`, pi `--print`.
#
# 2. PERMISSIONS BYPASSED. `haus-fix` runs the agent to EDIT the config that
#    just failed to build, in a checkout it was handed; a client that stops to
#    ask about its first `Edit` is a one-shot that never finishes and nobody is
#    watching it. The boundary is the cwd plus the git commit it makes, and the
#    undo is `git -C ~/.config/nix revert HEAD` — see modules/ai/fix.sh's
#    header for why that is the boundary rather than a permission prompt.
#    pi carries no flag here because pi has no permission gate to bypass; its
#    tools run (which is why the rice wires a desktop guard extension into it),
#    and `haus-fix` sets HAUS_DESKTOP_OK=1 for every client instead.
#
# 3. `--` LAST. End-of-options, so a prompt that ever begins with a dash is a
#    prompt rather than a flag. pi is the one where this has already bitten —
#    modules/lib/agent-packages.nix pins pi ≥0.84.3 for exactly this, and its
#    `--help` lists `--` as an option. claude (commander), codex (clap) and
#    opencode (yargs, `populate--` off by default, so operands land in `_`)
#    all take it the same way.
#
# Verified against the clients installed on a haus machine, 2026-08-31:
# claude 2.x, opencode 1.x and pi 0.84.3 all list these flags in `--help`.
# 🚨 `codex` is UNVERIFIED — it was on no machine when this was written. Its
# entry is the documented full-bypass shape for `codex exec`; the first
# machine to set `haus.ai.default = "codex"` and press Fix it is the test.
let
  clients = import ./agents.nix;

  specs = {
    # `-p` is print mode. `--dangerously-skip-permissions` is the bypass that
    # needs no `--allow-dangerously-skip-permissions` beside it: that second
    # flag only ENABLES the first as an option, and passing the first alone
    # already turns it on.
    claude = [
      "claude"
      "-p"
      "--dangerously-skip-permissions"
      "--"
    ];

    # `exec` is codex's non-interactive verb. The long flag turns off BOTH
    # halves of its gate — the approval prompt and the seatbelt sandbox — and
    # the sandbox half matters as much as the prompt: `nix eval` and `git
    # commit` both write outside the workspace codex would otherwise confine
    # them to.
    codex = [
      "codex"
      "exec"
      "--dangerously-bypass-approvals-and-sandbox"
      "--"
    ];

    # `run` takes the message as positionals. `--auto` is opencode's own word
    # for the bypass ("auto-approve permissions that are not explicitly
    # denied"), and its own `--help` calls it dangerous — which it is, and is
    # the point.
    opencode = [
      "opencode"
      "run"
      "--auto"
      "--"
    ];

    # No bypass flag: pi's built-in tools carry no permission gate at all, so
    # there is nothing here to open. See note 2 above.
    pi = [
      "pi"
      "--print"
      "--"
    ];
  };

  missing = builtins.filter (c: !(specs ? ${c})) clients;
in
if missing == [ ] then
  specs
else
  throw (
    "modules/lib/agent-oneshot.nix: no one-shot spec for "
    + builtins.concatStringsSep ", " missing
    + " — every client id in modules/lib/agents.nix needs one, or `haus fix` "
    + "has no way to run the client this machine defaults to."
  )
