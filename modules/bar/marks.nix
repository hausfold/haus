# THE MARK SET — the bar's IDENTITY colours, the axis beside the tone ladder.
#
# A tone answers "how is it going" (`modules/bar/tones.nix`). A mark answers
# "which one is this", for a subject the bar cannot know until it runs: which
# AI client wrote this usage row, which app is playing, which agent owns this
# pane. `docs/bar-framework.md` — "Marks, for what a tone cannot say".
#
# ── why this is not the ladder with four more rungs ───────────────────────────
# The ladder's rule is that a rung names a JOB (`warn` = wants a human here),
# and the reason a widget may name one is that the job is the same wherever it
# appears. Identity has no job. Two providers drawn side by side need to be
# TELLABLE APART and need to be unmistakable for a verdict, and that is the
# whole specification — there is nothing for a name to mean.
#
# So the names below are hue families on purpose, and that is the one place in
# this repo where naming a colour after its colour is right: a mark carries no
# claim, which is exactly what makes it safe on a mark. Putting `claude` and
# `openai` in the bar's colour vocabulary was the other candidate and is worse
# in both directions — it drags vendor knowledge into the bar, and media's app
# marks would follow it with `spotify`, `safari`, `zen`.
#
# ── the invariant this file exists to hold ───────────────────────────────────
# **Identity and status never share a hue.** ai-provider.sh has said so in
# prose since it was written ("a hue on a mark means identity, a hue on a
# number means state — paint a header icon YELLOW and the popup silently
# starts claiming a provider is at 60% of something"), and prose is what it
# stayed: nothing stopped the next mark from being added on `yellow`. It is
# mechanical now — `bar-marks` in flake.nix fails on a mark whose key is also
# a tone's, so the two vocabularies cannot converge by hand-edit.
#
# `accent` is the deliberate non-collision: it has no fixed key, it follows
# haus.theme.accent, and its enum contains `mauve`, `flamingo`, `teal` and
# `lavender` — so on some machines the logo pill and a mark DO wear the same
# hue. That is a coincidence between two IDENTITY colours, which lies about
# nothing; the check pins the fixed-key tones, which are the verdicts.
#
# ── what earns a mark ────────────────────────────────────────────────────────
# The same bar the ladder sets: a colour the bar ALREADY spends, in more than
# one pill, on one job. All four below are spent by `ai-provider.sh`, which
# `ai_usage.sh` and `agents.sh` both draw from — the aiUsage pill's dropdown
# headings and the agents pill's section headers are the same mark for the
# same client, which is why that table exists at all. A fifth mark waits for a
# second consumer, exactly as `badge` waits for a first.
#
# Fields mirror tones.nix so the two read as one system: `name` is what a
# widget says, `key` is the nebelung palette entry it resolves to, `stub` is
# the fake hex test/barlib.bats writes, `meaning` is what the doc table says.
#
# A plain value, imported the way tones.nix is: no module system, so flake.nix
# can read it without evaluating a configuration.
[
  {
    name = "warm";
    key = "flamingo";
    stub = "0xff7a0001";
    meaning = "Anthropic's clay — Claude, and Claude behind another harness";
    # The palette's warm clay, and the nearest neighbour to Anthropic's orange
    # that is NOT `peach` — peach is `warn`, and a Claude header wearing it
    # would read as a provider in trouble.
  }
  {
    name = "teal";
    key = "teal";
    stub = "0xff7a0002";
    meaning = "OpenAI's green-teal — Codex, and GPT behind another harness";
    # `green` is `ok` and `sky` is `busy`, so this is the one green-family
    # hue on the palette that carries no verdict.
  }
  {
    name = "violet";
    key = "lavender";
    stub = "0xff7a0003";
    meaning = "Gemini's blue-violet";
  }
  {
    name = "plum";
    key = "mauve";
    stub = "0xff7a0004";
    meaning = "a subject with no mark of its own — the catch-all";
    # What an unknown client gets, and what `mark()` falls back to. It is a
    # real mark rather than "no colour" for a reason the dropdown shows: a
    # block whose heading is grey reads as STALE, because grey is what a dead
    # feed is painted. An unrecognised provider is reporting perfectly well.
  }
]
