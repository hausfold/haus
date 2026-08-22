#!/bin/bash
# tour.sh init|start|click|skip|dismiss|reset|status|event <launch|workspace|navigate|resize|palette>
#
# The haus tour — the first-run tutor. One quiet pill at the FAR RIGHT of the
# bar (tour_item.sh --move's it next to the clock, so a notch can never cover
# it) walks the four moves (launch / navigate / resize / palette): no focus
# steal, no key logging, and no window of its own — except the "haus tour"
# buddy Finder window steps 2-3 spawn when the workspace is too empty to
# demonstrate on (see buddy_open). Completion is detected from signals the rice
# already fires — the leader-mode scripts and aerospace-notify.sh call
# `tour.sh event <name>`, each guarded by a single `[ -f $STATE ]`, so an idle
# machine pays one stat per mode change and nothing else. We verify the
# RESULTING state (mode entered, workspace changed), never the keystroke.
#
# With haus.tour.steps = null, the built-in steps are strictly sequential:
#   1a  tap the leader (launch mode armed)    <- launch_mode.sh on
#   1b  press a letter (an app launches)      <- aerospace-notify.sh (workspace
#                                                changed). The named key is
#                                                picked to point AWAY from the
#                                                focused workspace (launch_key),
#                                                so pressing it always moves you
#                                                and fires the event — otherwise
#                                                a key that lands on the CURRENT
#                                                workspace never fires and the
#                                                step hangs (click the pill to
#                                                skip if it somehow still can't).
#   2   leader + arrow (navigate mode)        <- navigate_mode.sh on
#   3   leader + -/=   (resize mode)          <- resize_mode.sh on
#   4   palette hotkey, type tour             <- the pounce "Haus Tour" command
#                                                (skipped when pounce is off)
#
# Setting haus.tour.steps replaces that lap with community-authored
# { hint, detect } rows. tour_config.sh contains those rows as shell-safe case
# functions; the state becomes c1, c2, ... and the same event funnel advances
# them. No executable code crosses the data-only rice boundary.
#
# The leader and palette GLYPHS come from tour_config.sh, generated from
# haus.keys.* — the built-in prompts have to name the key this machine
# actually has, or the tutor teaches a chord that does nothing.
#
# Left-click skips the current step (dormant: starts), right-click dismisses
# for good. Entry points: the dormant "new here?" hint on a fresh machine,
# `haus tour`, and the pounce command — which doubles as step 4's detection,
# so the palette finishes its own tutorial.
#
# State: $STATE holds the current step; $DONE present == completed or
# dismissed — it's what keeps the dormant hint from ever coming back. `reset`
# clears both and re-arms the hint. $MUTED lists the right-side pills hidden
# while a tour runs (see mute/unmute).
#
# Concurrency: leader->letter can fire `launch` and `workspace` back to back as
# fire-and-forget processes, so every mutation runs under the same mkdir-lock
# trick launch_mode.sh uses. The "nice" flash sleeps WHILE holding the lock on
# purpose: a queued event blocks until the flash lands, then reads the settled
# step. The steal window (~5s) stays above the longest flash (4s).

export PATH="/run/current-system/sw/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"

STATE_DIR="$HOME/.local/state/haus"
STATE="$STATE_DIR/tour"        # built-in: 1a|1b|2|3|4; custom: c1|c2|...
DONE="$STATE_DIR/tour-done"    # present == completed or dismissed
MUTED="$STATE_DIR/tour-muted"  # right-side pills hidden while a tour runs
FINISHING="$STATE_DIR/tour-finishing" # present only while the completion flash is visible
LOCK="/tmp/sketchybar_tour.lock"

source "$HOME/.config/sketchybar/colors.sh"
source "$HOME/.config/sketchybar/workspaces.sh"
# Not for $SB — the tour pill itself never moves off the menu bar and addresses
# it directly. This is for the TABLE bar.sh generates (BAR_BOTTOM_ITEMS and the
# two client paths): mute() hides pills that CAN have moved, and it has to know
# which instance owns each one. See bar_of().
source "$HOME/.config/sketchybar/bar.sh"

# GENERATED gates, authored steps + glyphs (modules/bar/default.nix).
# TOUR_CUSTOM=1 replaces the built-in lap. Otherwise TOUR_HAS_PALETTE=0 when
# pounce is off, which drops step 4 and makes it a three-step tour. Defaults here
# preserve the old tour when tour_config.sh is stale or absent.
TOUR_CUSTOM=0
TOUR_CUSTOM_COUNT=0
TOUR_HAS_PALETTE=1
TOUR_LEADER="⇪"
TOUR_LEADER_NAME="Caps Lock"
TOUR_PALETTE="⌘ Space"
tour_custom_hint() { return 1; }
tour_custom_detect() { return 1; }
[ -f "$HOME/.config/sketchybar/tour_config.sh" ] && source "$HOME/.config/sketchybar/tour_config.sh"
if [ "$TOUR_CUSTOM" = 1 ]; then
    TOTAL=$TOUR_CUSTOM_COUNT
else
    TOTAL=3
    [ "$TOUR_HAS_PALETTE" = 1 ] && TOTAL=4
fi

# fa-paw (U+F1B0) as raw UTF-8 bytes — /bin/bash is 3.2, whose printf has no
# \u/\U; \xHH works (same trick as launch_mode.sh).
PAW=$(printf '\xEF\x86\xB0')

# Step 1b's letter. Detection (see the `workspace` event below) fires on ANY
# workspace change, so what matters is that the key we name actually MOVES you:
# pressing the launcher for the workspace you're already on switches nothing, no
# aerospace-notify fires, and the step dead-ends — the #1 way the tour stalls
# (start it from the terminal, whose key `t` leads the roster, and "press t"
# does nothing). So pick, in roster order, the first APP key (skip the numbered
# workspaces' digits) bound to a workspace that ISN'T the focused one. Recomputed at
# render time, not cached, so it stays right if the user drifts workspaces mid-
# step. Fall back to the roster's first app key when every app sits on the
# focused workspace or aerospace is mute — the click-to-skip escape still covers
# that corner. LAUNCHERS ("<key>:<ws>" pairs) and LAUNCHER_KEYS come from the
# roster in workspaces.sh, the same source launch_mode.sh's picker reads.
launch_key() {
    local focused entry key ws
    focused=$(aerospace list-workspaces --focused 2>/dev/null)
    for entry in $LAUNCHERS; do
        key=${entry%%:*}; ws=${entry#*:}
        # Numbered-workspace digits focus a space, not an app. Membership in
        # NUMBERED_KEYS rather than "is it a digit": how many digits there are
        # follows haus.windows.numberedWorkspaces, and a roster app is allowed to
        # claim one the numbered workspaces didn't take.
        case " ${NUMBERED_KEYS[*]} " in *" $key "*) continue ;; esac
        [ -n "$ws" ] || continue                        # null-workspace app: no guaranteed move
        [ "$ws" = "$focused" ] && continue              # already here → pressing it moves nothing
        printf '%s\n' "$key"; return
    done
    # The first APP key, which is whatever follows the numbered digits in
    # LAUNCHER_KEYS — an index rather than the literal 4 it was, since the count
    # of digits is an option now.
    printf '%s\n' "${LAUNCHER_KEYS[${#NUMBERED_KEYS[@]}]:-t}"
}

acquire_lock() {
    local n=0
    until mkdir "$LOCK" 2>/dev/null; do
        sleep 0.05
        n=$((n + 1))
        [ $n -ge 100 ] && rmdir "$LOCK" 2>/dev/null   # ~5s: steal a crashed lock
    done
    trap 'rmdir "$LOCK" 2>/dev/null' EXIT
}

step() { cat "$STATE" 2>/dev/null; }

# Changing from the built-in lap to authored steps (or shortening an authored
# list) can leave yesterday's state file naming a step the new tour does not
# have. Treat that as a fresh dormant tour rather than rendering a blank or,
# worse, resuming a built-in instruction the rice no longer declares.
state_is_valid() {
    local current index
    current=$(step)
    if [ "$TOUR_CUSTOM" = 1 ]; then
        case "$current" in
            c*)
                index=${current#c}
                [[ "$index" =~ ^[0-9]+$ ]] \
                    && [ "$index" -ge 1 ] \
                    && [ "$index" -le "$TOUR_CUSTOM_COUNT" ]
                ;;
            *) return 1 ;;
        esac
    else
        case "$current" in 1a|1b|2|3|4) return 0 ;; *) return 1 ;; esac
    fi
}

# An authored hint is a literal string in someone else's rice, so it cannot name
# the keys THIS machine resolved — the rice importing it may have moved
# `keys.palette` or `keys.leader`. The built-in lap interpolates them; a shared
# tour gets the same thing through placeholders, expanded here from the very
# values tour_config.sh already carries. Without this, the only way to author
# "press ⌘ Space" is to hardcode a chord that a consumer may not have bound.
expand_keys() {
    local s=$1
    s=${s//\{palette\}/$TOUR_PALETTE}
    s=${s//\{leader\}/$TOUR_LEADER}
    s=${s//\{leaderName\}/$TOUR_LEADER_NAME}
    printf '%s' "$s"
}

render() {
    local current index lbl
    current=$(step)
    case "$current" in
        c*)
            index=${current#c}
            lbl="$index/$TOTAL · $(expand_keys "$(tour_custom_hint "$index")")"
            ;;
    esac
    case "$(step)" in
        1a) lbl="1/$TOTAL · tap $TOUR_LEADER ($TOUR_LEADER_NAME)" ;;
        1b) lbl="1/$TOTAL · now press $(launch_key) — the letters are in the bar" ;;
        2)  lbl="2/$TOTAL · tap $TOUR_LEADER, then an arrow — ⎋ ends" ;;
        3)  lbl="3/$TOTAL · tap $TOUR_LEADER, then - or = — ⎋ ends" ;;
        4)  lbl="4/$TOTAL · press $TOUR_PALETTE, type tour, hit ↵" ;;
        c*) ;;
        *)  return ;;
    esac
    sketchybar --set tour drawing=on \
        background.color=$SURFACE0 icon="$PAW" icon.color=$PINK \
        label.color=$TEXT label="$lbl"
}

dormant() {
    sketchybar --set tour drawing=on \
        background.color=$MANTLE icon="$PAW" icon.color=$PINK \
        label.color=$SUBTEXT0 label="new here? click for a tour"
}

hide() { sketchybar --set tour drawing=off; }

# While a tour runs, the other right-side pills get out of the way — the step
# labels need room, and a notch'd laptop has none to spare mid-bar. Only the
# clock stays. $MUTED records exactly which pills WE hid, so unmute restores
# those and nothing else (agents & co. manage their own drawing and must not
# be forced on). A pill's own script can still redraw it mid-tour (media
# change, agent event) — accepted clutter; the instruction itself sits
# notch-safe next to the clock.
#
# mute MERGES into an existing $MUTED rather than truncating it: a re-mute
# while pills are already hidden (start over a mid-flight tour, init after a
# partial repaint) would otherwise record nothing and orphan every hidden
# pill — the restore list must survive until unmute actually runs.
#
# Every pill in the list is MOVABLE (haus.bar.bottom.items), so none of them can
# be addressed with a bare `sketchybar`: that name is the menu bar's instance
# alone, and a --set aimed at the wrong one is silent — the pill just stays
# visible through the whole lap, over the step labels, with nothing in any log.
# bar_of() routes per item off the same BAR_BOTTOM_ITEMS table bar.sh generates,
# which is the one place that knows where each pill ended up. The tour pill
# itself never moves and keeps talking to the top bar directly.
#
# On the id's FIRST DOT-SEGMENT: a pill drawn as several items names them
# `<pill>.<part>` (the agents pill is a robot, three count segments and the
# bracket behind them), and only the base id is ever in the placement table.
# Routing the parts by their full name would send them to the top bar while
# the pill they belong to lives on the bottom one — a silent miss, since a
# `--set` for an item the instance doesn't have is not an error.
bar_of() { # bar_of <item> — the SketchyBar client that owns this pill
    case " ${BAR_BOTTOM_ITEMS:-} " in
        *" ${1%%.*} "*) printf '%s' "${BAR_BOTTOM:-sketchybar}" ;;
        *) printf '%s' "${BAR_TOP:-sketchybar}" ;;
    esac
}

mute() {
    touch "$MUTED"
    local it bar
    # The agents pill is five ids, not one: hiding `agents` alone would leave
    # its counts and the bracket behind them on the bar with the robot missing.
    # Each is gated on its own drawing state below, so the ones already hidden
    # (a state with nothing in it) are skipped and stay hidden on unmute.
    for it in weather media battery wifi focus \
              agents agents.ready agents.working agents.done agents.pill \
              elgato harvest github; do
        bar="$(bar_of "$it")"
        [ "$("$bar" --query "$it" 2>/dev/null | jq -r '.geometry.drawing')" = on ] || continue
        grep -qxF "$it" "$MUTED" || echo "$it" >> "$MUTED"
        "$bar" --set "$it" drawing=off
    done
}

unmute() {
    [ -f "$MUTED" ] || return 0
    local it
    while IFS= read -r it; do
        "$(bar_of "$it")" --set "$it" drawing=on
    done < "$MUTED"
    rm -f "$MUTED"
}

# Steps 2-3 demonstrate nothing on a lone window: `focus left` has nowhere to
# go, `resize smart` just re-fills the workspace — the tour would "pass" while
# the user sees nothing move. So entering either step guarantees a sparring
# partner: if the focused workspace holds fewer than two windows, spawn a
# Finder window on an empty folder literally named "haus tour" — the title
# explains the apparition. AppleScript, not `open`: `make new Finder window`
# sidesteps the open-folders-in-tabs pref (which would tab into an existing
# window on some other workspace) and doesn't activate Finder, so focus stays
# where the user left it. buddy_close reaps every such window, however the
# tour ends — no state to track, the window name IS the marker.
buddy_open() {
    [ "$(aerospace list-windows --workspace focused | wc -l)" -ge 2 ] && return
    mkdir -p "$STATE_DIR/haus tour"
    osascript -e "tell application \"Finder\" to make new Finder window to (POSIX file \"$STATE_DIR/haus tour\")" >/dev/null 2>&1
}

buddy_close() {
    osascript -e 'tell application "Finder"
        repeat while (exists Finder window "haus tour")
            close Finder window "haus tour"
        end repeat
    end tell' >/dev/null 2>&1
}

# A short colored beat between steps ("tap ⇪ then t… nice"). Sleeping while
# holding the lock is deliberate — see the concurrency note up top.
flash() { # flash <bg-color> <seconds> <label>
    sketchybar --set tour drawing=on \
        background.color=$1 icon="$PAW" icon.color=$BASE \
        label.color=$BASE label="$3"
    sleep "$2"
}

finish() {
    # Mark the four-second completion flash separately from normal progress so
    # a click on “the house is yours” dismisses it instead of starting a new lap.
    touch "$FINISHING"
    if [ "$TOUR_CUSTOM" = 1 ]; then
        flash "$MAUVE" 4 "the house is yours $PAW"
    else
        flash "$MAUVE" 4 "the house is yours $PAW — ⇪ / opens the cheatsheet"
    fi
    rm -f "$FINISHING"
    touch "$DONE"; rm -f "$STATE"
    buddy_close
    unmute
    hide
}

# Move past the current step. $1 = a "nice" line to flash; empty (a click-skip)
# flashes nothing — no praise for a move that didn't happen.
advance() {
    local current index
    current=$(step)
    case "$current" in
        1a|1b) [ -n "$1" ] && flash "$GREEN" 2 "$1"; echo 2 > "$STATE"; buddy_open ;;
        2)     [ -n "$1" ] && flash "$GREEN" 2 "$1"; echo 3 > "$STATE"; buddy_open ;;
        3)     [ -n "$1" ] && flash "$GREEN" 2 "$1"
               if [ "$TOUR_HAS_PALETTE" = 1 ]; then echo 4 > "$STATE"; else finish; return; fi ;;
        4)     finish; return ;;
        c*)
            index=${current#c}
            if [ "$index" -lt "$TOUR_CUSTOM_COUNT" ]; then
                echo "c$((index + 1))" > "$STATE"
            else
                finish
                return
            fi
            ;;
        *)     return ;;
    esac
    render
}

start() {
    # The item only exists when the tour is wired in (haus.tour.enable +
    # windows + bar) — refuse cleanly instead of scribbling state nothing reads.
    if ! sketchybar --query tour >/dev/null 2>&1; then
        echo "tour: the bar has no tour item — it needs haus.tour.enable with windows + bar on." >&2
        exit 1
    fi
    mkdir -p "$STATE_DIR"
    rm -f "$DONE" "$FINISHING"
    if [ "$TOUR_CUSTOM" = 1 ]; then echo c1 > "$STATE"; else echo 1a > "$STATE"; fi
    mute
    render
}

case "$1" in
    init)
        # Called by the generated tour_item.sh right after adding the item —
        # last in sketchybarrc, so every right-side pill already exists:
        # repaint whatever the last session left — a mid-tour step (re-muting
        # the freshly-added pills), done (hidden), or the dormant hint.
        acquire_lock
        if [ -f "$FINISHING" ]; then
            # A restart can interrupt the visual completion beat. Completion
            # already happened, so settle it as done instead of reviving a
            # stale final step that still intercepts clicks.
            rm -f "$FINISHING" "$STATE"; touch "$DONE"; buddy_close; unmute; hide
        elif [ -f "$STATE" ] && state_is_valid; then mute; render
        elif [ -f "$STATE" ]; then rm -f "$STATE"; buddy_close; unmute; dormant
        elif [ -f "$DONE" ]; then hide
        else dormant; fi
        ;;
    start)   acquire_lock; start ;;
    reset)   acquire_lock; rm -f "$STATE" "$DONE" "$FINISHING"; buddy_close; unmute; dormant ;;
    skip)    acquire_lock; advance "" ;;
    dismiss) acquire_lock; touch "$DONE"; rm -f "$STATE" "$FINISHING"; buddy_close; unmute; hide ;;
    click)
        # $BUTTON is exported by sketchybar for click_scripts.
        # finish() deliberately holds LOCK during its visible flash, so handle
        # this outside the lock: the completion pill must disappear immediately
        # rather than queue a click that starts another tour when the flash ends.
        if [ -f "$FINISHING" ]; then
            touch "$DONE"; rm -f "$STATE" "$FINISHING"; buddy_close; unmute; hide
            exit 0
        fi
        acquire_lock
        if [ "${BUTTON:-left}" = "right" ]; then touch "$DONE"; rm -f "$STATE" "$FINISHING"; buddy_close; unmute; hide
        elif [ -f "$DONE" ]; then hide
        elif [ -f "$STATE" ]; then advance ""
        else start; fi
        ;;
    status)  step; [ -f "$STATE" ] || echo "idle$([ -f "$DONE" ] && echo ' (done)')" ;;
    event)
        # The live-detection funnel. Callers guard with [ -f $STATE ] — except
        # `palette`, which is also the tour's re-entry point (⌘Space → tour).
        case "$2" in
            launch|workspace|navigate|resize|palette) ;;
            *) echo "usage: $0 event launch|workspace|navigate|resize|palette" >&2; exit 1 ;;
        esac
        acquire_lock
        current=$(step)
        if [[ "$current" == c* ]]; then
            index=${current#c}
            [ "$(tour_custom_detect "$index")" = "$2" ] && advance ""
            exit 0
        fi
        case "$2" in
            launch)    [ "$(step)" = 1a ] && { echo 1b > "$STATE"; render; } ;;
            workspace) [ "$(step)" = 1b ] && advance "nice — that's the launcher" ;;
            navigate)  [ "$(step)" = 2 ] && advance "nice — ⇧+arrow drags the window along" ;;
            resize)    [ "$(step)" = 3 ] && advance "nice — it repeats till ⎋" ;;
            palette)
                case "$(step)" in
                    4)  advance "" ;;   # advancing past 4 IS the finale
                    "") start ;;        # no tour running — (re)start one
                    *)  render ;;       # mid-tour: just repaint
                esac
                ;;
        esac
        ;;
    *) echo "usage: $0 init|start|click|skip|dismiss|reset|status|event <name>" >&2; exit 1 ;;
esac
