# THE TONE LADDER — the bar's whole colour vocabulary, in one place.
#
# A barlib widget names a TONE and never a hex or a palette key (the framework
# doc, hausfold.co/docs/haus/rooms/bar-widgets, "Tones, not colours"). This file
# is the one definition of what the names are and which nebelung key each
# resolves to; everything else is generated from it or checked against it:
#
#   modules/bar/default.nix    generates the `TONE_*` exports in colors.sh
#   modules/bar/colors-fns.nix emits `tone()` itself into the same file, one
#                              arm per rung, right after the exports it reads
#   test/barlib.bats           the colors.sh stub its setup() writes, plus
#                              test/colors-fns.sh — the committed copy of the
#                              emitted functions the suite runs against
#
# The first two are generated from this list, so they cannot drift. The test
# pair is not, and neither errors when stale — `tone()` warns to stderr,
# which goes to sketchybar's log where nobody looks, and the pill paints
# grey. So `bar-tones` in flake.nix pins both against this list: the stub's
# exports as PAIRS in file order (each rung by what it resolves to — swapping
# two lines inverts the severity ladder while leaving the names
# byte-identical, and order is the ladder's own, quietest first), and the
# fixture byte-exact against what colors-fns.nix emits, so its failure
# output IS the new file when the ladder moves.
#
# `meaning` has a consumer again, one repo out. The third copy used to be the
# doc's own table and that arm went when the doc moved to a private repo this
# flake cannot read — which left the table on
# hausfold.co/docs/haus/rooms/bar-widgets a hand copy nothing checked. So the
# list is PUBLISHED instead: `nix build .#site-data` writes it to
# `docs/site-data/bar-tones.json` (committed, pinned by `site-data-current`),
# and hausfold.co's `scripts/check-bar-tables.mjs` reads that file. It holds
# the page's rung NAMES and their ORDER to this list exactly, and snapshots
# `meaning` so a rewording here surfaces as a docs task rather than as a page
# that quietly disagrees. The page's own wording stays the page's: it is
# shorter than these lines on purpose, since "Claude elsewhere" is a client
# name to us and a typo to a reader.
#
# `stub` is the fake hex `test/barlib.bats`'s `setup()` writes for that rung —
# here so the fixture is single-sourced with the ladder rather than being ten
# magic numbers a test asserts against by hand. It ascends with the ladder so
# a failing assertion reads as a position, not a colour.
#
# `fallback` is the colors.sh VARIABLE the emitted arm falls back to when the
# rung's own TONE_* is unset — `TONE_WATCH:-$TONE_WARN` — which is the
# rung this one was carved out of, and so also what the pill looked like one
# generation ago. It guards a shell still carrying an OLDER generation's
# exports: within colors.sh the function rides the same file as the exports
# it reads, so those two cannot skew, but a by-hand shell that sourced last
# generation's file keeps its variables (barlib's source guard honours them)
# while knowing nothing newer. null means the rung was in the founding
# ladder and reads its variable bare; a NEW rung always names one — `TONE_`
# + another rung, or an UPPER-cased nebelung palette key (`text` falls back
# to $TEXT, the palette's own foreground). `bar-tones` refuses a fallback
# nothing could resolve.
#
# `key = null` means the tone does NOT resolve to a fixed palette key.
# `accent` is the only one, and that is the whole reason it is dangerous —
# see its row.
#
# A plain value, imported the way modules/lib/accents.nix is: no module
# system, so flake.nix can read it without evaluating a configuration.
#
# ── What earns a rung ────────────────────────────────────────────────────────
# A colour the bar ALREADY spends, in more than one pill, on one job. A rung
# only one widget wants is that widget's hex being laundered through the
# framework; the mapping onto an existing rung was already right. Every rung
# below names the pills that earned it, so the next person can check the claim
# rather than take it. (Most of those pills are not framework widgets yet —
# they convert on touch, and the ladder has to be ready for them when they do,
# or the first conversion of `cpu.sh` has nothing to call 50%.)
[
  {
    name = "mute";
    key = "overlay0";
    stub = "0xff111111";
    fallback = null;
    meaning = "nothing there — inactive, stale, no verdict";
    # harvest's idle pill, trill's, elgato's unreachable third state,
    # ai_usage's doubly-stale values, calendar's done glyphs, and both
    # label colours barlib itself lays a popup out with.
  }
  {
    name = "dim";
    key = "overlay1";
    stub = "0xff1a1a1a";
    fallback = "TONE_MUTE";
    meaning = "present but subordinate — a heading, a row's name, a descriptor";
    # The second dim step, and the bar has had it all along: agents paints a
    # popup SECTION icon overlay1 and its META row overlay0, as vitals_lib
    # and ai_usage did before the runtime took their rows — ai_usage wrote
    # the same two-tier rule down as `descr` vs `meta`, and both halves are
    # `popup_row` and `popup_note` now; memory/cpu's "everything else",
    # calendar's meta glyph and empty-state label, page's counter and
    # media_lib's inactive source are all the brighter one. `mute` cannot do
    # this job — it is the OFF step, so a heading painted with it reads as
    # absent rather than quiet, and a widget with only one dim rung can only
    # ever get greyer.
  }
  {
    name = "text";
    key = "text";
    stub = "0xff777777";
    fallback = "TEXT";
    meaning = "a live readout carrying no alarm — the ordinary foreground";
    # The rung that is deliberately not a verdict. github's `info` sources:
    # a count that is news without being bad news.
  }
  {
    name = "ok";
    key = "green";
    stub = "0xff222222";
    fallback = null;
    meaning = "green, nothing needed";
  }
  {
    name = "busy";
    key = "sky";
    stub = "0xff333333";
    fallback = null;
    meaning = "the machine has it, not you";
  }
  {
    name = "watch";
    key = "yellow";
    stub = "0xff3a3a3a";
    fallback = "TONE_WARN";
    meaning = "worth knowing, nothing to do yet";
    # The missing MIDDLE of the severity ladder. Two pills wrote the four
    # steps out in a comment and then in code — `GREEN → YELLOW → PEACH →
    # RED`, on identical thresholds, in vitals_lib.sh's `vitals_color` and
    # ai_usage.sh's `pct_color`. Both are gone now: all three pills are
    # converted, and `vitals_tone` and `pct_tone` say the same ladder in
    # tone names. battery.sh is the one left, spending yellow across its
    # whole 20-80% band.
    #
    # The ladder had three severity rungs against their four, so neither
    # function could be written in tones at all: the first pill to convert
    # would have had to keep a hardcoded hex, which is the exact thing the
    # framework exists to delete. 50% CPU is not "wants a human here".
    #
    # It is NOT github's `auth` — see the `auth` case in github.sh's
    # render(). That one wants a human right now, and the popup heading
    # under it has said `warn` since the pill was written.
  }
  {
    name = "warn";
    key = "peach";
    stub = "0xff444444";
    fallback = null;
    meaning = "wants a human here";
  }
  {
    name = "bad";
    key = "red";
    stub = "0xff555555";
    fallback = null;
    meaning = "the load-bearing thing is broken";
  }
  {
    name = "action";
    key = "sapphire";
    stub = "0xff5a5a5a";
    fallback = "TONE_ACCENT";
    meaning = "a thing you press — an affordance, not a status";
    # Three pills reached for sapphire for this independently: calendar's
    # trailing "Join" on a meeting row, caffeinate's active/stop rows, and
    # github's Refresh. It is the bar's settled colour for "this row does
    # something", and it needed a name for one reason above taste — see the
    # `accent` row directly below, which is what an affordance falls back to
    # without it.
    #
    # ai_usage spent sapphire on MONEY too (a figure that must not be
    # green-as-in-safe), and that was a different job this rung never
    # claimed. ai_usage has converted, and the answer was NO: a spend is
    # `text`. It failed the bar at the top of this file — one pill, one
    # place — and the two things its own comment asked sapphire for ("a
    # quantity, no verdict" and "not mistakable for a client's brand hue")
    # are both true of `text`, which is the rung that already means a live
    # readout carrying no alarm. The colour lost is real; the rung it would
    # have cost was that pill's hex laundered through the framework.
  }
  {
    name = "accent";
    key = null; # follows haus.theme.accent
    stub = "0xff666666";
    fallback = null;
    meaning = "haus's own mark — identity, never status";
    # 🚨 The one rung that is not a fixed palette key, and the one nothing
    # carrying MEANING may name. `haus.theme.accent` is an enum of fourteen
    # names (modules/lib/accents.nix) and it contains `red`, `peach`,
    # `yellow`, `green` and `sky` — so on somebody's machine this tone IS
    # every verdict rung above, and a row that names it is indistinguishable
    # from the alarm. It fails in the direction nobody tests: fine on mauve,
    # wrong on red, and the person it is wrong for never filed it because
    # they never saw the other machine.
    #
    # It is also a promise: `haus.theme.accent`'s own option doc says "a
    # machine that changes its accent sees exactly one pill change hue" —
    # the logo — and `accent-reach` pins that. `popup_action` defaulting
    # here would have quietly enrolled every verb row in every framework
    # popup as the second.
  }
]
