# `.agents/` — the harness-neutral layer

Every coding agent invents its own dotfile. This directory is the answer to
that: **the content lives here (or in `AGENTS.md`), and each client's own
directory holds nothing but wiring** — a pointer, a symlink, or a hook
registration. Switch harness, keep the flows.

> **One body, many pointers.** A rule, a flow, or a script is written *once*. If
> a file under `.claude/`, `.codex/`, `.opencode/` or `.github/` carries a
> project rule rather than a reference to one, it's a bug — the next agent, on a
> different client, runs without it.

Corollary: never "fix" a stale pointer by copying the current text into it.

The family-wide rationale — the four kinds of agent config, how to add a new
harness — is written once, in the workshop:
[`hausfold/workshop` → `.agents/README.md`](https://github.com/hausfold/workshop/blob/main/.agents/README.md).
The table below is only what's wired in *this* repo.

**This layer is for hacking on the rice.** Don't confuse it with the agent
config the rice *ships*: `haus.agents.instructions`, `haus.agents.skill`,
`modules/hearth/agents/`, and the per-client agent-state hooks. Those write into
a **user's** home directory and are a product feature; these files configure the
agent working on this repo. They follow the same rule the table below does —
one body, one copy per client, at the path that client actually reads.

| Path | Read by | What it actually is |
|---|---|---|
| `AGENTS.md` | Codex, OpenCode, Cursor, Zed, Amp, Copilot-in-editor, and anything else that speaks [agents.md](https://agents.md) | **The source of truth.** Every project rule, starting with the routing rule that keeps palette and app changes in their own repos. |
| `CLAUDE.md` | Claude Code (CLI, desktop, web) | `@AGENTS.md` import + a table of Claude-only wiring. Claude Code reads only `CLAUDE.md`, so the import is how it gets the real file. |
| `GEMINI.md` | Gemini CLI | Symlink → `AGENTS.md`. |
| `opencode.json` | OpenCode | Names `AGENTS.md` explicitly. Belt and braces — OpenCode finds it anyway. |
| `.github/copilot-instructions.md` | GitHub Copilot coding agent + code review | A **real file**, not a symlink: Copilot reads through the GitHub API, where a symlink is just a path string. Short pointer + the few facts a drive-by reviewer needs. |
| `.agents/setup.sh` | all of them, via the hooks below | Installs Determinate Nix in a bare cloud container, persists `PATH` + `NIX_SSL_CERT_FILE`. No-ops on macOS and where Nix already exists. Replaces the old Claude-only `.claude/hooks/session-start.sh`. |
| `.claude/settings.json` | Claude Code | `SessionStart` → `.agents/setup.sh`. |
| `.codex/hooks.json` + `.codex/config.toml` | Codex CLI | `SessionStart` → `.agents/setup.sh`, plus the flag that enables hooks. |
| `.opencode/plugins/nix-bootstrap.js` | OpenCode | Plugin load *is* session start; runs the same script, swallowing every error. |

No repo-local flows live here yet: the cross-repo ones (`/ship`, `/docs-sync`)
belong to the workshop. When the rice grows one of its own it goes in
`.agents/skills/<name>/SKILL.md`, symlinked into `.claude/skills/<name>/` and
`.opencode/skills/`, never copied.

## Caveats

- **A cloud session can evaluate but not activate.** `nix eval
  .#darwinConfigurations.example.system.drvPath` is the check that works
  anywhere; `darwin-rebuild` / `bench try switch` are macOS-only and always the
  local machine's job.
- **Codex repo-local hooks** have historically not fired in every interactive
  session ([openai/codex#17532](https://github.com/openai/codex/issues/17532)),
  and some builds want an absolute path for `hooks`. If `/hooks` doesn't list
  ours, point your own `~/.codex/config.toml` at this repo's `.codex/hooks.json`.
- **Codex cloud takes its setup script from the web UI**, not from a file here;
  set it to `bash .agents/setup.sh`.
- **The OpenCode plugin is best-effort** and deliberately silent: it runs the
  bootstrap on plugin load and swallows failures. A bootstrap that breaks the
  client would be worse than none.
- **Whatever the harness, the fallback is the same:** `./.agents/setup.sh` is
  idempotent and safe to run by hand. If a flake command says Nix is missing,
  that's the fix.
