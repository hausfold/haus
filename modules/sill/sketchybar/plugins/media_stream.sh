#!/bin/bash

# The living half of the media pill.
#
# SketchyBar's own `media_change` event has been dead since macOS 15.4: Apple
# made mediaremoted check the CALLER's entitlement and the bar doesn't have one,
# so the event simply never fires and the pill stayed dark forever. See
# modules/sill/media-control.nix for the whole story and for why the replacement
# has to run inside /usr/bin/perl.
#
# This is that replacement: one long-running `media-control stream` whose JSON
# lines become the pill. The pill stays event-driven — a track change or a
# play/pause repaints it in the same instant it happens — rather than dropping to
# a poll, which is what the old event bought us and what a `get` on an
# update_freq would have quietly given up.
#
# It lives in its own script rather than inside media.sh because sketchybar reaps
# its `script=` runs: a stream started from one would be killed by the next tick.
# sketchybarrc launches it detached, and media.sh restarts it if it ever dies.
#
# Rendering itself is in media_lib.sh, not here, because the TICK repaints too: a
# long-form countdown has to keep moving while the stream is silent. This file's
# own job is narrower — turn each payload into the `now` record, notice when the
# TRACK (not the state) changed, and paint.

export PATH="/opt/homebrew/bin:/run/current-system/sw/bin:/usr/bin:/bin:$PATH"

source "$HOME/.config/sketchybar/colors.sh"
source "$HOME/.config/sketchybar/media_config.sh"
source "$HOME/.config/sketchybar/plugins/media_lib.sh"
SILL_ITEM=media
source "$HOME/.config/sketchybar/bar.sh"

# Both of these are keyed on the plugin DIRECTORY — not per bar (see the takeover
# below for why that would be wrong), and not one name for the whole machine.
# The key is what stops a COPY of these plugins run from anywhere else — a
# scratchpad, a second checkout, whatever an agent or a bisect leaves lying
# around — from becoming this bar's streamer of record. It is not hypothetical
# and it fails silently: with one shared name, a stray copy's pid sat in the
# pidfile, media.sh's watchdog matched it (a stranger's command line carries the
# script's name too), certified the stream as healthy, and so never restarted the
# real one — for as long as the stranger lived. The uid buys the same separation
# between two users' rices on one machine.
#
# The directory is this script's own as INVOKED, deliberately NOT resolved.
# ~/.config/sketchybar/plugins is a symlink into the store, so `pwd -P` would
# mint a new name on every generation — and a rebuild's reload, which is the
# moment the takeover below exists for, would then never find the streamer it
# came to replace.
SILL_PLUGIN_DIR="$(dirname "${BASH_SOURCE[0]}")"
SILL_STREAM_KEY="$(id -u).$(printf '%s' "$SILL_PLUGIN_DIR" | shasum -a 256 | cut -c1-12)"
PIDFILE="/tmp/sketchybar_media_stream.$SILL_STREAM_KEY.pid"
LOCKDIR="/tmp/sketchybar_media_stream.$SILL_STREAM_KEY.lock"

[ -n "$SILL_MEDIA_CONTROL" ] && [ -x "$SILL_MEDIA_CONTROL" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

mkdir -p "$SILL_MEDIA_STATE_DIR" 2>/dev/null

# ── one streamer per installed rice ───────────────────────────────────────────
# A reload runs the bar's config again without killing what the last one spawned,
# so the previous stream (and the perl adapter under it) has to go first, or every
# track change repaints once per stream that survived.
#
# ONE pidfile, not one per bar, even though there are two bars: the pill lives on
# exactly one of them (a pill named in haus.sill.bottom.items MOVES rather than
# duplicating, so only that bar's items file carries the launch), and a single
# file is what makes moving the pill from one bar to the other kill the streamer
# the OTHER bar started. Keyed per bar, that one would stream on forever. The
# plugin-directory key above does not reintroduce that: both bars run out of the
# same plugins dir, so they still share one record, exactly as they must.
#
# The shape below is two bugs deep, and both of them ended the same way — a live
# stream nobody owns, repainting the pill a second time on every track change,
# until they stack up into a pill that flickers and a perl adapter per orphan:
#
#   * THE EXIT TRAP MAY ONLY DROP A PIDFILE THAT IS STILL OURS. It used to
#     `rm -f` unconditionally, so the instance we had just killed deleted the
#     record its killer had already written — and the NEXT reload then read an
#     empty pidfile, killed nothing, and left that stream running beside its
#     replacement. Half of all reloads leaked one, which a day of rebuilds turned
#     into fourteen processes — seven live streams — on a real machine, all of them
#     painting. A pidfile left BEHIND is harmless by comparison,
#     because every reader matches the pid against the process's command line.
#   * READ, KILL AND RECORD ARE ONE CRITICAL SECTION. Two instances can start in
#     the same second — media.sh's watchdog spawns from a `script=` run, and two
#     subscribed events in one tick means two of those — and interleaved, they
#     both read the same old pid, both kill it, and then both stream. mkdir is the
#     only atomic primitive a shell has, so it is the mutex, and the takeover runs
#     inside it. Serialising is better here than letting a loser bail out: every
#     instance's takeover is then real, so the newest code always ends up being
#     the code that streams, which is what a reload after a rebuild is FOR.
#   * THE RECORD IS NOT THE WHOLE TRUTH. Both bugs above left streams the pidfile
#     never named, and a takeover that only reads the record cannot reclaim one —
#     so the takeover also sweeps for streams nothing recorded, which is what
#     makes the count converge on a machine that already leaked some.
#
# A pid is validated the way media.sh's watchdog validates it — against the
# process's own command line, not with a bare kill -0 — because pids get reused,
# and TERMing whatever inherited one is far worse than skipping a takeover. The
# pattern is anchored on a bash running THIS script, not on the name appearing
# anywhere in the line, because the sweep below asks about pids nothing recorded:
# `vim …/plugins/media_stream.sh` matches a loose grep, and a bar reload has no
# business TERMing somebody's editor.
is_streamer() {
    [ -n "$1" ] && ps -p "$1" -o command= 2>/dev/null |
        grep -qE '^[^ ]*bash .*media_stream\.sh$'
}

# Signal a streamer AND everything under it — the perl adapter and the `while
# read` subshell of its pipeline. Children first, so the read at the end of that
# pipeline sees EOF, and RE-ENUMERATED on every pass rather than captured once:
# an instance signalled during the moment it takes to fork its own pipeline has
# children that appear after the first pgrep, and once its parent is gone they
# are nobody's `pkill -P` any more. That is not theoretical — a burst of four
# starts reproduced it, leaving a perl adapter and a reader with ppid 1 happily
# painting the pill as a second stream.
signal_tree() {
    local sig="$1" pid="$2"
    local kids
    kids=($(pgrep -P "$pid" 2>/dev/null))
    [ ${#kids[@]} -gt 0 ] && kill "-$sig" "${kids[@]}" 2>/dev/null
    kill "-$sig" "$pid" 2>/dev/null
}

# TERM every stream in the list, wait a bounded moment, then stop asking nicely.
# TERM alone is not proof of anything: bash can only act on a signal between
# commands, and a streamer spends its entire life inside one pipeline, so one
# whose children outlive the signal would sit there with it pending forever. The
# TERM is repeated each pass because a stream signalled mid-fork only shows the
# pipeline it was forking as a child on a later pass. One shared wait for the
# whole list, so a pile of orphans still costs one bounded second, not one each.
terminate_streamers() {
    local p alive
    for p in "$@"; do
        is_streamer "$p" && signal_tree TERM "$p"
    done
    for _ in $(seq 1 20); do
        alive=""
        for p in "$@"; do
            if is_streamer "$p"; then
                alive=1
                signal_tree TERM "$p"
            fi
        done
        [ -n "$alive" ] || break
        sleep 0.05
    done
    for p in "$@"; do
        is_streamer "$p" && signal_tree KILL "$p"
    done
}

# Take the mutex. About three seconds, which is far longer than the section can
# honestly take — a ps, a kill, and at worst one bounded second spent watching a
# stream die — so failing to get it means the holder was SIGKILLed inside it.
# Break it and go: a pill that stays dark until the next login is worse than two
# takeovers overlapping, and the sweep below is what makes an overlap survivable
# rather than permanent.
LOCK_HELD=""
for _ in $(seq 1 60); do
    if mkdir "$LOCKDIR" 2>/dev/null; then
        LOCK_HELD=1
        break
    fi
    sleep 0.05
done
if [ -z "$LOCK_HELD" ]; then
    rmdir "$LOCKDIR" 2>/dev/null
    mkdir "$LOCKDIR" 2>/dev/null && LOCK_HELD=1
fi
# Installed here, not after the section: everything in it is idempotent, and a
# streamer that dies mid-takeover would otherwise strand the mutex and cost the
# next one the full spin above before it broke in.
trap 'pkill -P $$ 2>/dev/null
      [ -n "$LOCK_HELD" ] && rmdir "$LOCKDIR" 2>/dev/null
      [ "$(cat "$PIDFILE" 2>/dev/null)" = "$$" ] && rm -f "$PIDFILE"' EXIT

# The pid the record names, AND any stream the record lost track of. The second
# half is not belt-and-braces: the bug above minted streams that were never in
# the pidfile, and a guard that trusts only the record can never reclaim those —
# no number of reloads brings the count back down, so the machine that grew to
# seven of them would keep all seven after the fix. Inside the mutex this is safe.
# A sibling instance still spinning for the lock hasn't started a stream yet, and
# one that already held it is the pid we just read.
VICTIMS=""
OLD="$(cat "$PIDFILE" 2>/dev/null)"
[ -n "$OLD" ] && [ "$OLD" != "$$" ] && VICTIMS="$OLD"
for p in $(pgrep -f media_stream.sh 2>/dev/null); do
    case " $VICTIMS $$ " in
        *" $p "*) continue ;;
    esac
    VICTIMS="$VICTIMS $p"
done
terminate_streamers $VICTIMS

# Ours now. A dead instance's own trap can still fire after this write, which is
# exactly why that trap checks the pid first: the record it finds is no longer its
# own, so it leaves it alone.
echo $$ >"$PIDFILE"
[ -n "$LOCK_HELD" ] && {
    rmdir "$LOCKDIR" 2>/dev/null
    LOCK_HELD=""
}

# Now that the stream we replaced is gone, start from a clean slate — the LAST
# one may not have got to run its trap. bash does not run an EXIT trap on
# SIGKILL, and a bar reload signals the whole process group — so an artwork
# fetch, a scroll-seek or a marquee sweep caught mid-flight leaves its lock
# directory behind, and a lock nothing ever releases is a feature switched off
# forever, silently, across reboots. The hover flag gets the same treatment: it's
# cleared by an event a pointer flicked off the bar can miss, and shouldn't
# outlive the stream that set it.
#
# This has to run AFTER the takeover above, not before: the locks most likely to
# be stranded mid-flight are the ones belonging to the stream we just killed.
rmdir "$SILL_MEDIA_STATE_DIR/art.lock" "$SILL_MEDIA_STATE_DIR/scroll.lock" \
    "$SILL_MEDIA_STATE_DIR/marquee.lock" 2>/dev/null
rm -f "$SILL_MEDIA_STATE_DIR/hover" 2>/dev/null
$SB --set media scroll_texts=off 2>/dev/null

# The marquee is entirely hover-driven now (media.sh's mouse.entered) — a track
# change does not, on its own, scroll anything. scroll_texts used to be on
# forever, which meant a title longer than the pill scrolled for as long as the
# track played — permanent motion in the corner of your eye, on a bar you are
# not looking at; arming it off a track change instead just moved the same
# problem to "for a few seconds after every change", so nothing here fires it
# on its own any more. See media.sh for the hover-triggered one-shot sweep.

# ── the stream ───────────────────────────────────────────────────────────────
# --no-artwork keeps several hundred KB of base64 per update out of a pipe that
# only ever renders text (media_art.sh fetches the cover separately, once per
# track); --no-diff means every line is a complete payload, so there is no state
# to merge here and a missed line can't leave the pill stale.
#
# Three things the record format does on purpose:
#
#   * `timestamp` is folded to epoch seconds by jq rather than by a `date -j` per
#     payload — it is what media_elapsed_now advances a countdown from, and
#     spawning date(1) in a stream's hot path is how a track change earns a
#     visible stutter. The sub() strips a fractional part first: v0.7.6 never
#     emits one, but fromdateiso8601 rejects "...:05.123Z" outright, jq's error
#     is swallowed by the 2>/dev/null, and the pill would go dark for good on a
#     media-control bump nobody would think to connect to it.
#   * control characters in the VALUES are flattened to spaces before joining
#     rather than escaped by @tsv. @tsv also escapes backslashes, and nothing
#     downstream un-escapes them, so a track called `AC\DC` reached the bar as
#     `AC\\DC`. A title has no business carrying a newline anyway.
#   * the join is US (0x1f), not tab — see SILL_MEDIA_FS in media_lib.sh.
PREV_KEY=""
media_read_now && PREV_KEY="$(media_change_key)"

"$SILL_MEDIA_CONTROL" stream --no-diff --no-artwork --debounce=200 2>/dev/null |
    while IFS= read -r line; do
        parsed="$(printf '%s' "$line" | jq -r '
            select(.type == "data")
            | .payload
            | [ (.playing // false | tostring),
                (.title // ""),
                (.artist // ""),
                (.album // ""),
                (.bundleIdentifier // ""),
                (.duration // 0 | tostring),
                (.elapsedTime // 0 | tostring),
                (if (.timestamp // "") == "" then ""
                 else (.timestamp | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601 | tostring) end),
                (.playbackRate // 1 | tostring),
                (.processIdentifier // 0 | tostring),
                (.contentItemIdentifier // "") ]
            | map(gsub("[\u0001-\u001f]"; " "))
            | join("\u001f")' 2>/dev/null)"
        [ -n "$parsed" ] || continue

        printf '%s\n' "$parsed" >"$SILL_MEDIA_NOW"
        media_read_now
        # media_read_now returns non-zero on an empty title, which is a real
        # state (nothing is playing) and not a read failure — MEDIA_* is still
        # populated either way, and media_render hides the pill on it.

        key="$(media_change_key)"
        if [ "$key" != "$PREV_KEY" ]; then
            PREV_KEY="$key"
            if [ -n "$MEDIA_TITLE" ]; then
                ("$HOME/.config/sketchybar/plugins/media_art.sh" "$MEDIA_ID" >/dev/null 2>&1 &)
            else
                rm -f "$SILL_MEDIA_ART".* "$SILL_MEDIA_ART_SCALE" "$SILL_MEDIA_TINT" 2>/dev/null
            fi
        fi

        media_render
    done
