# Codex. The record modules/ai/clients/default.nix describes; the AI room
# renders it.
{
  package = pkgs: pkgs.codex;

  # Verified with `codex debug prompt-input`: ~/.codex/AGENTS.md and
  # ~/.codex/skills/* appear in the model-visible prompt.
  home = {
    instructions = ".codex/AGENTS.md";
    skills = ".codex/skills";
  };

  # `exec` is codex's non-interactive verb. The long flag turns off BOTH
  # halves of its gate — the approval prompt and the seatbelt sandbox — and
  # the sandbox half matters as much as the prompt: `nix eval` and `git
  # commit` both write outside the workspace codex would otherwise confine
  # them to. clap takes `--` as end-of-options.
  #
  # 🚨 UNVERIFIED — codex was on no machine when this was written
  # (2026-08-31). This is the documented full-bypass shape for `codex exec`;
  # the first machine to set `haus.ai.default = "codex"` and press Fix it is
  # the test.
  oneshot = [
    "codex"
    "exec"
    "--dangerously-bypass-approvals-and-sandbox"
    "--"
  ];

  scopeNote = "`config.toml` and `hooks.json` are Codex's own, and a host may wire individual skills as out-of-store symlinks";

  # Codex — the same agent status wiring, in Codex's own hook file, so a
  # Codex window lights the `agents` pill exactly like a Claude or Opencode
  # one. Three of its ten events carry the states we draw:
  #
  #   UserPromptSubmit  → working
  #   PermissionRequest → waiting    ← the urgent one; the pill goes red
  #   Stop              → idle
  #
  # There is deliberately no fourth: Codex has no session-END event (its list
  # stops at Stop), so nothing can report `remove`. A zmx session closes that
  # by construction: its labels live in the session and die with it, so a
  # window that goes away takes its row with it — which also cleans up after
  # any client that dies without saying goodbye. Schema verified against codex-cli 0.145.0 by running a real turn
  # with `--dangerously-bypass-hook-trust` and watching the hooks fire: it is
  # Claude-shaped (PascalCase event → matcher groups → `{type, command}`
  # handlers), the command runs under `$SHELL -lc` with the session's cwd, and
  # it inherits $ZMX_SESSION — which is the whole addressing scheme.
  #
  # First launch after this lands, Codex will ask you to REVIEW the hooks
  # ("Hooks need review") and won't run them until you trust them. That gate
  # is Codex's, it is a good one, and haus does not try to defeat it —
  # `--dangerously-bypass-hook-trust` exists but appears nowhere here.
  #
  # Merged with jq rather than owned outright: hooks.json is a user-editable
  # file and may hold hooks of your own, which must survive a rebuild.
  # Only written when Codex is actually installed (`ai.clients`).
  settings = {
    name = "codexAgentHooks";
    onlyWhenInstalled = true;
    activation =
      {
        pkgs,
        lib,
        cfg,
      }:
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run sh -c '
          hooks="$0"
          bin="$1"
          mkdir -p "''${hooks%/*}"
          tmp="$hooks.hm-seed"
          if [ -s "$hooks" ]; then base="$hooks"; else base="$tmp.base"; printf "{}" > "$base"; fi
          ${pkgs.jq}/bin/jq --arg bin "$bin" ".hooks.UserPromptSubmit = [{hooks:[{type:\"command\",command:(\$bin + \" working codex\")}]}]
            | .hooks.PermissionRequest = [{hooks:[{type:\"command\",command:(\$bin + \" waiting codex\")}]}]
            | .hooks.Stop = [{hooks:[{type:\"command\",command:(\$bin + \" idle codex\")}]}]" \
            "$base" > "$tmp"
          mv "$tmp" "$hooks"
          rm -f "$tmp.base"
        ' "$HOME/.codex/hooks.json" "/run/current-system/sw/bin/agent-state"
      '';
  };
}
