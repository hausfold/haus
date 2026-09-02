# THE MARK SET — the bar's IDENTITY colours, the axis beside the tone ladder.
#
# A tone answers "how is it going" (`modules/bar/tones.nix`). A mark answers
# "which one is this", for a subject the bar cannot know until it runs: which
# AI client wrote this usage row, which app is playing, which agent owns this
# pane. The framework doc, hausfold.co/docs/haus/rooms/bar-widgets — the mark
# table sits under "Tones, not colours", beside the ladder's, because the page
# is about naming a colour rather than about either axis.
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
# one pill, on one job. Four are spent by `ai-provider.sh`, which `ai_usage.sh`
# and `agents.sh` both draw from — the aiUsage pill's dropdown headings and the
# agents pill's section headers are the same mark for the same client, which is
# why that table exists at all.
#
# The other three arrived with the SECOND consumer this axis was waiting for.
# `media.sh` paints its glyph, its dropdown title and its scrubber by what is
# playing — a music note, a podcast, a video in a browser tab — and it had been
# spending seven raw palette keys on that since it was written. Four of them
# were `green`, `peach`, `red` and `sapphire`, which is the invariant below
# stated as a bug rather than a rule: a Spotify pill was painted `ok`, VLC was
# painted `warn`, and a YouTube tab was painted `bad`, for the whole time each
# one was playing perfectly. The conversion re-hued those four onto marks and
# left the two that were already off the ladder (`mauve`, `lavender`) where
# they were — which is the check doing the work the prose could not.
#
# So an eighth mark waits for a THIRD consumer, exactly as `badge` waits for a
# first. Media wanting a hue is not on its own an argument for a rung: what
# earned these three is that the pill's kind vocabulary already spent them.
#
# Fields mirror tones.nix so the two read as one system: `name` is what a
# widget says, `key` is the nebelung palette entry it resolves to, `stub` is
# the fake hex test/barlib.bats writes, `meaning` is the set's own wording —
# published as `docs/site-data/bar-marks.json` and held against the page's
# table by hausfold.co, exactly as the ladder's is. See tones.nix for the
# split: the names and their order are pinned to the page, the wording is
# snapshotted.
#
# A plain value, imported the way tones.nix is: no module system, so flake.nix
# can read it without evaluating a configuration.
[
  {
    name = "warm";
    key = "flamingo";
    stub = "0xff7a0001";
    meaning = "Anthropic's clay — Claude, Claude elsewhere, and VLC";
    # The palette's warm clay, and the nearest neighbour to Anthropic's orange
    # that is NOT `peach` — peach is `warn`, and a Claude header wearing it
    # would read as a provider in trouble. VLC's cone is the same orange with
    # the same problem, and lands on the same answer: two subjects sharing one
    # mark is what a hue family is FOR, and they are never on screen together.
  }
  {
    name = "rust";
    key = "maroon";
    stub = "0xff7a0005";
    meaning = "a muted red — video in a browser tab";
    # `red` is `bad`, so the pill spent the alarm hue on a YouTube tab for as
    # long as one was open. Maroon is the palette's other red and carries no
    # verdict, which is the whole of why it is here rather than a rung.
  }
  {
    name = "pink";
    key = "pink";
    stub = "0xff7a0006";
    meaning = "music with no app of its own — and media's catch-all kind";
    # The one media hue that never collided: pink is on no rung of the ladder,
    # so the music note the pill draws for Apple Music (and for a source it
    # cannot place) kept its colour through the conversion.
  }
  {
    name = "violet";
    key = "lavender";
    stub = "0xff7a0003";
    meaning = "Gemini's blue-violet — and a video file playing locally";
  }
  {
    name = "blue";
    key = "blue";
    stub = "0xff7a0007";
    meaning = "music in a browser tab";
    # `sapphire` is `action` and `sky` is `busy`. Blue is the third of the
    # palette's blues and the only one a row can wear without claiming either
    # to be a button or to be working on something.
  }
  {
    name = "teal";
    key = "teal";
    stub = "0xff7a0002";
    meaning = "OpenAI's green-teal — Codex, GPT elsewhere, and Spotify";
    # `green` is `ok` and `sky` is `busy`, so this is the one green-family
    # hue on the palette that carries no verdict. Spotify's own green is
    # `green`, i.e. the ok rung — the nearest hue that says nothing is this.
  }
  {
    name = "plum";
    key = "mauve";
    stub = "0xff7a0004";
    meaning = "a subject with no mark of its own — the catch-all, and podcasts";
    # What an unknown client gets, and what `mark()` falls back to. It is a
    # real mark rather than "no colour" for a reason the dropdown shows: a
    # block whose heading is grey reads as STALE, because grey is what a dead
    # feed is painted. An unrecognised provider is reporting perfectly well.
  }
]
