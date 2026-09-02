#!/bin/bash
# GENERATED — tone() and mark() exactly as the generated colors.sh carries
# them, emitted by modules/bar/colors-fns.nix from modules/bar/tones.nix
# and modules/bar/marks.nix. Committed so `bats test/barlib.bats` (which
# runs without Nix, in CI and by hand) exercises the very functions a real
# bar resolves colours through: setup() appends this file to the colors.sh
# stub it writes. Do not edit — `bar-tones` in flake.nix byte-diffs it
# against the emitter, and when the ladder moves its failure output names
# the regenerated file to copy over this one.

# tone(): the ladder as the function widgets resolve it through, generated
# beside the exports it reads (modules/bar/colors-fns.nix, from tones.nix)
# so the two cannot skew. Each arm's `:-` is that rung's own `fallback`
# field — what a shell still carrying an older generation's exports
# answers. An unknown tone is mute, not an error: a typo must cost a grey
# pill, never a pill that stops painting; the warning goes to sketchybar's
# log, and `bar-tones` in flake.nix is what actually catches drift.
tone() {
    case "$1" in
        mute)   printf '%s' "$TONE_MUTE" ;;
        dim)    printf '%s' "${TONE_DIM:-$TONE_MUTE}" ;;
        text)   printf '%s' "${TONE_TEXT:-$TEXT}" ;;
        ok)     printf '%s' "$TONE_OK" ;;
        busy)   printf '%s' "$TONE_BUSY" ;;
        watch)  printf '%s' "${TONE_WATCH:-$TONE_WARN}" ;;
        warn)   printf '%s' "$TONE_WARN" ;;
        bad)    printf '%s' "$TONE_BAD" ;;
        action) printf '%s' "${TONE_ACTION:-$TONE_ACCENT}" ;;
        accent) printf '%s' "$TONE_ACCENT" ;;
        *)
            echo "barlib: unknown tone '$1' (mute|dim|text|ok|busy|watch|warn|bad|action|accent) — using mute" >&2
            printf '%s' "$TONE_MUTE"
            ;;
    esac
}

# mark(): the identity axis (marks.nix) as its resolver, generated the
# same way. The catch-all is plum — the set's own catch-all mark — and
# never grey: grey is what a dead feed is painted, and an unrecognised
# subject is reporting perfectly well.
mark() {
    case "$1" in
        warm)   printf '%s' "${MARK_WARM:-$TONE_MUTE}" ;;
        rust)   printf '%s' "${MARK_RUST:-$TONE_MUTE}" ;;
        pink)   printf '%s' "${MARK_PINK:-$TONE_MUTE}" ;;
        violet) printf '%s' "${MARK_VIOLET:-$TONE_MUTE}" ;;
        blue)   printf '%s' "${MARK_BLUE:-$TONE_MUTE}" ;;
        teal)   printf '%s' "${MARK_TEAL:-$TONE_MUTE}" ;;
        plum)   printf '%s' "${MARK_PLUM:-$TONE_MUTE}" ;;
        *)
            echo "barlib: unknown mark '$1' (warm|rust|pink|violet|blue|teal|plum) — using plum" >&2
            printf '%s' "${MARK_PLUM:-$TONE_MUTE}"
            ;;
    esac
}
