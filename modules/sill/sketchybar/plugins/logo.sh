#!/bin/bash
# The far-left haus.logo pill: its colour, its hover sweep, and all four of its
# click gestures. Defined in sketchybarrc, configured by haus.sill.logo.*.
#
# One script for all of it because every branch here reads the same two facts —
# what the machine's health is, and whether the leader is armed — and a pill
# whose hover and whose state tick disagree about either is a pill that flickers
# between two colours. See `paint` for the one place that resolves them.
#
# PATH: a SketchyBar plugin inherits launchd's bare PATH (/usr/bin:/bin:…), so
# `git`, `jq`, `pgrep` and the nix profile have to be named. Same prelude
# reload-bar.sh carries, for the same reason.
export PATH="/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

source "$HOME/.config/sketchybar/colors.sh"
# SILL_LOGO_* — GENERATED from haus.sill.logo.*. Sourced AFTER colors.sh on
# purpose: SILL_LOGO_COLOR and SILL_LOGO_SWEEP_COLORS are written as `$MAUVE`,
# `$TEAL`, … so a palette change reaches this pill without anything here
# knowing a hex. Sourced first they would expand to empty and the pill would
# draw in SketchyBar's default white.
source "$HOME/.config/sketchybar/logo_config.sh"

ITEM=haus.logo
# A bare `sketchybar` (not bar.sh's $SB routing): this pill is hand-written into
# sketchybarrc's left side and is not in `haus.sill.items`, so unlike the movable
# pills it can only ever be on the menu bar. $SKETCHYBAR_BIN — the same override
# sillpop already takes — is honoured so this can be exercised against a
# stand-in: the PATH line above prepends the real binary's directory, so a test
# shim earlier on PATH loses and the run repaints the live bar instead.
SB="${SKETCHYBAR_BIN:-sketchybar}"

STATE_FILE=/tmp/sketchybar_logo_state        # ok | update | alert
UPSTREAM_CACHE=/tmp/sketchybar_logo_upstream # 1 == a newer haus is pinned upstream
SWEEP_PID=/tmp/sketchybar_logo_sweep.pid
SWEEP_RUN=/tmp/sketchybar_logo_sweep.run  # exists == the sweep may draw
# Written by launch_mode.sh while the leader is armed; its presence is the one
# signal that the pill is not ours to paint right now.
LAUNCH_SNAP=/tmp/sketchybar_launch_logo.json

armed() { [ -f "$LAUNCH_SNAP" ]; }

# ── state ────────────────────────────────────────────────────────────────────
# Three values, worst-first, because the pill has one colour and has to spend it
# on the worst thing that is true:
#
#   alert   something haus runs is enabled but not running
#   update  a newer haus is pinned upstream (haus.sill.logo.updateCheck)
#   ok      neither
#
# `alert` is the one that earns the feature. A wedged GUI agent is otherwise
# invisible by construction: AeroSpace stops tiling but leaves every window
# where it was, and a dead `sill-bottom` leaves its bar on screen drawing the
# last frame it painted — a bar that has stopped and a bar with nothing to say
# look identical. This is the same check `haus doctor` opens with, kept to the
# part that costs nothing so it can run on a five-minute tick.
#
# `org.nixos.sketchybar` is deliberately NOT in the list: this script only runs
# because SketchyBar is running, so checking it could never fail.
health() {
    pgrep -qx nix-daemon || return 1
    local pair label name
    for pair in "org.nixos.aerospace:AeroSpace" \
        "org.nixos.sill-bottom:sill-bottom" \
        "com.hausfold.pounce:pounce"; do
        label="${pair%%:*}"
        name="${pair##*:}"
        # Only the jobs whose plist exists — an absent one means that room is
        # off, which is a configuration, not a fault.
        launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1 || continue
        pgrep -qx "$name" || return 1
    done
    return 0
}

# Is the haus revision this machine pins behind its upstream? The same question, and the
# same answer, as `haus status`'s last block: read the pinned rev out of the
# consumer's lock and ask GitHub for the ref's head.
#
# Cached and refreshed at most every 30 minutes, because unlike everything else
# here it leaves the machine. The low-speed guards are the offline case: with no
# network `git ls-remote` will otherwise sit on a connect timeout, and a plugin
# that blocks holds nothing up but does pile up processes on a laptop that spends
# an afternoon on a train. An unreachable remote yields no answer, and no answer
# is treated as "up to date" — a pill that turns yellow when the wifi drops is
# worse than one that says nothing.
upstream_behind() {
    [ "$SILL_LOGO_UPDATE_CHECK" = "1" ] || return 1

    if [ -f "$UPSTREAM_CACHE" ] && [ -z "$(find "$UPSTREAM_CACHE" -mmin +30 2>/dev/null)" ]; then
        [ "$(cat "$UPSTREAM_CACHE" 2>/dev/null)" = "1" ]
        return
    fi

    local consumer lock rev owner repo ref remote
    consumer="${HAUS_CONSUMER:-$HOME/.config/nix}"
    lock="$consumer/flake.lock"
    [ -f "$lock" ] || return 1
    rev="$(jq -r '.nodes.nebelhaus.locked.rev // ""' "$lock" 2>/dev/null)"
    [ -n "$rev" ] || return 1
    owner="$(jq -r '.nodes.nebelhaus.original.owner // "hausfold"' "$lock" 2>/dev/null)"
    repo="$(jq -r '.nodes.nebelhaus.original.repo // "hausfold"' "$lock" 2>/dev/null)"
    ref="$(jq -r '.nodes.nebelhaus.original.ref // "HEAD"' "$lock" 2>/dev/null)"

    remote="$(GIT_TERMINAL_PROMPT=0 \
        git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=8 \
        ls-remote "https://github.com/$owner/$repo.git" "$ref" 2>/dev/null |
        awk 'NR==1{print $1}')"

    if [ -n "$remote" ] && [ "$remote" != "$rev" ]; then
        echo 1 >"$UPSTREAM_CACHE"
        return 0
    fi
    # Only cache a definite answer. An empty $remote means the question wasn't
    # asked (offline, rate-limited), and caching that would hold the pill quiet
    # for half an hour after the network came back.
    [ -n "$remote" ] && echo 0 >"$UPSTREAM_CACHE"
    return 1
}

resolve_state() {
    if [ "$SILL_LOGO_STATUS" != "1" ]; then
        echo ok
    elif ! health; then
        echo alert
    elif upstream_behind; then
        echo update
    else
        echo ok
    fi
}

state_color() {
    case "$1" in
    alert) printf '%s' "$RED" ;;
    update) printf '%s' "$YELLOW" ;;
    *) printf '%s' "$SILL_LOGO_COLOR" ;;
    esac
}

# ── the sweep ────────────────────────────────────────────────────────────────
# The bar's copy of the mark on hausfold.co: hovering it turns a conic gradient
# of the six family accents through the glyph. SketchyBar cannot put a gradient
# inside a glyph — the only colour a text item has is one flat `icon.color` — so
# the sweep IS the gradient, one colour at a time, `--animate`d between so it
# reads as a turn rather than six steps.
#
# A background loop with a pidfile rather than a fixed-length run, because the
# thing that ends it is the pointer leaving, and that arrives as a separate
# event in a separate process. Same shape as media.sh's marquee.
# Stopping it is belt AND braces, and the braces are the load-bearing half.
#
#   * $SWEEP_RUN's existence is the loop's own permission to draw another frame,
#     re-read before every one. Removing it ends the sweep within one frame no
#     matter what happens to the signal.
#   * the TERM is only there to make it immediate.
#
# The signal alone was not enough: bash defers a signal until the foreground
# command it is running returns, so a subshell parked in `sleep 0.75` takes the
# TERM late and gets one more `--set` out first — and that frame lands AFTER the
# settle that mouse.exited just did, leaving the pill on a sweep colour with
# nothing left running to move it off. The guard file is what makes the frame
# that wins the last one written by whoever is still allowed to draw.
sweep_stop() {
    rm -f "$SWEEP_RUN"
    local old
    [ -f "$SWEEP_PID" ] || return 0
    old="$(cat "$SWEEP_PID" 2>/dev/null)"
    # The subshell only — deliberately NOT `pkill -P` for the `sleep` under it.
    # Killing the sleep makes its own shell report `Terminated: 15  sleep 0.75`
    # on stderr, which for a bar plugin means a line in /tmp/sketchybar.err.log
    # every single time the pointer leaves the pill — enough noise to bury a
    # real error. Left alone, the sleep finishes on its own and the pending TERM
    # lands a fraction of a second later, which the guard file above has already
    # made harmless.
    if [ -n "$old" ] && [ "$old" != "$$" ] && kill -0 "$old" 2>/dev/null; then
        kill "$old" 2>/dev/null
    fi
    rm -f "$SWEEP_PID"
}

sweep_start() {
    sweep_stop
    : >"$SWEEP_RUN"
    (
        while [ -f "$SWEEP_RUN" ]; do
            for c in $SILL_LOGO_SWEEP_COLORS; do
                [ -f "$SWEEP_RUN" ] || exit 0
                "$SB" --animate sin 45 --set "$ITEM" icon.color="$c"
                sleep 0.75
            done
        done
    ) &
    # The PARENT records the pid, from `$!`. The subshell cannot record its own:
    # /bin/bash here is 3.2, where $BASHPID does not exist — it expands to
    # nothing, and the pidfile lands empty.
    echo $! >"$SWEEP_PID"
}

# ── painting ─────────────────────────────────────────────────────────────────
# Put the pill back to whatever the last computed state says, without computing
# it again — the callers here are the two that end a sweep, and both want the
# cached answer rather than another round of `pgrep`.
#
# `snap` skips the animation, and exists for exactly one caller: launch_mode.sh
# snapshots this colour on the way into leader mode, and a value read mid-tween
# is the one it would restore on the way out.
settle() {
    armed && return 0
    local col
    col="$(state_color "$(cat "$STATE_FILE" 2>/dev/null || echo ok)")"
    if [ "${1:-animate}" = "snap" ]; then
        "$SB" --set "$ITEM" icon.color="$col"
    else
        "$SB" --animate sin 30 --set "$ITEM" icon.color="$col"
    fi
}

# The single place the two facts meet. Leader mode owns the pill outright while
# armed (launch_mode.sh has filled it), so nothing here touches it then — the
# state is still computed and written down, and the next tick after disarm puts
# the right colour back.
paint() {
    local state
    state="$(resolve_state)"
    echo "$state" >"$STATE_FILE"
    armed && return 0
    "$SB" --animate sin 20 --set "$ITEM" icon.color="$(state_color "$state")"
}

# ── gestures ─────────────────────────────────────────────────────────────────
# All three detached with nohup: a click_script runs inside SketchyBar's own
# event loop, so anything here that waits on a GUI app stalls the whole bar.
# Same reason launch_palette.sh — the old bare-click target, deleted with this,
# since the palette is now one branch of a click rather than all of it — did it.
menu() { nohup "$HOME/.config/sketchybar/plugins/haus_menu.sh" >/dev/null 2>&1 & }
palette() { nohup pounce-palette >/dev/null 2>&1 & }
rebuild() {
    # The palette's own Rebuild System command by path, so ⌘-click and
    # ⌘Space → "Rebuild System" are one implementation of the floating-terminal
    # rebuild rather than two. $SILL_LOGO_COMMANDS is empty when pounce is off,
    # in which case there is nothing to run and nothing to report.
    [ -x "$SILL_LOGO_COMMANDS/rebuild.sh" ] || return 0
    nohup "$SILL_LOGO_COMMANDS/rebuild.sh" >/dev/null 2>&1 &
}

# A hand call, not an event. launch_mode.sh runs it on the way into leader mode:
# the pointer can be sitting on the pill when caps is tapped, and a sweep loop
# left running would keep writing icon.color over the inverted pill once every
# 0.75s. It settles the colour too, synchronously and un-animated, because the
# very next thing that caller does is snapshot this pill — so this is what makes
# the snapshot a state colour rather than whatever the sweep was mid-way to.
# Here rather than in launch_mode.sh so the pidfile has exactly one owner.
if [ "${1:-}" = "sweep-stop" ]; then
    sweep_stop
    settle snap
    exit 0
fi

case "${SENDER:-}" in
mouse.clicked)
    # Every gesture opens something pounce draws, so all of them are off
    # together — see haus.sill.logo.gestures, which folds in haus.pounce.enable.
    [ "$SILL_LOGO_GESTURES" = "1" ] || exit 0
    # A plain click sends MODIFIER=none (not empty), so test against "none".
    case "${BUTTON:-left}" in
    right) palette ;;
    *)
        case "${MODIFIER:-none}" in
        *cmd*) rebuild ;;
        *) menu ;;
        esac
        ;;
    esac
    ;;
mouse.entered)
    # Hover says "show me the family colours" — and only that. A pill sitting at
    # yellow or red is already saying something, and a rainbow running over the
    # top of it is a pill saying two things at once, so the sweep is gated on a
    # clear state (and on the leader not owning the pill).
    [ "$SILL_LOGO_SWEEP" = "1" ] || exit 0
    armed && exit 0
    [ "$(cat "$STATE_FILE" 2>/dev/null || echo ok)" = "ok" ] || exit 0
    sweep_start
    ;;
mouse.exited | mouse.exited.global)
    # The .global twin is belt and braces, exactly as the media and calendar
    # pills use it: a per-item mouse.exited is missable when the pointer leaves
    # fast or a window comes up under it, and a sweep nothing stops is permanent
    # motion in the corner of your eye.
    sweep_stop
    settle
    ;;
*)
    # The update_freq tick, system_woke, and the first run at bar start.
    paint
    ;;
esac
