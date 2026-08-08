# Copilot instructions

**Read [`AGENTS.md`](../AGENTS.md) at the repo root first — it is the full,
authoritative instruction set for every agent working here, and this file is
only a pointer to it.** (Copilot doesn't follow file imports, hence the
duplication below; if the two ever disagree, `AGENTS.md` wins.)

The short version:

- nebelhaus is an opinionated **macOS rice as composable nix-darwin modules** —
  the "distro". A personal machine consumes it via `mkNebelhaus` and adds only
  its own host.
- **Never hardcode identity.** Anything personal — git name/email, signing keys,
  a signing cert — is a `haus.*` option the host sets. A literal name or
  email in this repo is a bug, not a convenience.
- **This repo owns the rice and nothing else.** Colors live in `nebelung`, the
  palette app in `pounce`, the notch file shelf in `perch`, one machine's config
  in that machine's own repo. A change that would "work here" but belongs
  elsewhere is still wrong.
- **Docs live downstream:** user-facing guides are the Astro site in the
  `workshop` repo, served at nebelhaus.com. A change to user-facing behavior
  needs the matching guide updated there, or it silently drifts.
- **Verify by evaluating:** `nix eval
  .#darwinConfigurations.example.system.drvPath`. `nixfmt` formats `.nix`.
- Two traps worth knowing at review time: the **launchd GUI race**
  (`modules/lib/gui-wait.nix` is load-bearing — don't simplify it away, and don't
  drop its 60 s deadline: unbounded, it wedges the agent forever), and
  **pounce self-signing** in `modules/pounce`, which is what keeps a TCC grant
  alive across rebuilds. `AGENTS.md` has the rest.

For review comments, the same bar applies as anywhere in the family:
correctness and boundaries (does this change belong in *this* repo?) over style.
