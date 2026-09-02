#!/usr/bin/env bash
# awake — a durable controller for macOS's built-in caffeinate assertion.
#
# The assertion itself runs under a declarative per-user launchd job (wired by
# modules/core/default.nix), so it is independent of the shell or SketchyBar
# process that started it. State is deliberately tiny and durable: a timed
# assertion resumes with only its remaining time after login/rebuild, while an
# indefinite assertion resumes until explicitly stopped.
set -euo pipefail

STATE_DIR="${AWAKE_STATE_DIR:-$HOME/.local/state/haus/awake}"
STATE_FILE="$STATE_DIR/state"
LABEL="${AWAKE_LAUNCHD_LABEL:-com.hausfold.awake}"
LAUNCHCTL="${AWAKE_LAUNCHCTL_BIN:-/bin/launchctl}"
CAFFEINATE="${AWAKE_CAFFEINATE_BIN:-/usr/bin/caffeinate}"
# Overridable for the same reason the three above are — and here it is not only
# a stub hook. `date -r <seconds>` is BSD's "format this epoch time"; GNU
# coreutils spells `-r` as `--reference=FILE` and answers `No such file or
# directory` on a number. That is fine on the Mac this ships to and fatal in a
# suite running on a Linux CI runner, where the `(until …)` half of the timed
# sentence would come back empty and the assertion would fail describing a bug
# that does not exist on any machine haus runs on.
DATE="${AWAKE_DATE_BIN:-/bin/date}"
# @sketchybar@ is substituted from haus.roster.sketchybar.binPath by
# ../core/default.nix, and is empty on a machine with no bar — every use below
# is behind an `[ -x ]` guard, which is also what makes the env override work.
SKETCHYBAR="${AWAKE_SKETCHYBAR_BIN:-@sketchybar@}"
# bar's optional SECOND bar (haus.bar.bottom.enable) — the same binary under a
# second name, hence a second client to poke. Absent on a machine without it.
BAR_BOTTOM="${AWAKE_BAR_BOTTOM_BIN:-/run/current-system/sw/bin/bar-bottom}"

# ---- snug's bash painter, loaded only where this draws for a person ---------
# `awake` is its own binary and inherits nobody's environment — a launchd agent,
# the bar's coffee pill and a person at a prompt all exec it directly — so
# `HAUS_UI_SH` is PREPENDED by the derivation (modules/core/default.nix), the
# way `github-signal` takes it, rather than substituted into a `@uiSh@` hole.
# Both shapes are legal; this one is right here because this file is already a
# `replaceStrings` template for `@sketchybar@` and a second hole buys nothing.
# The variable still wins when a caller sets it, so a working copy of ui.sh is
# one export away.
#
# LAZY, and a function rather than a source at the top, for the reason `focus`
# is: the hot path through this script is `awake status --raw`, which the bar's
# caffeinate plugin runs on every tick, and reading a thousand lines of bash to
# print three tab-separated fields is a cost paid forever for nothing. `_run`,
# the launchd controller, never reaches it either. Only the prose paths call it.
UI_READY=""
ui_load() {
    [ -n "${UI_LOADED:-}" ] && return 0
    UI_LOADED=1
    # ui.sh is bash 4+ — `${role^^}` inside ui_paint_role alone rules 3.2 out —
    # and this script's shebang is `env bash` for exactly that reason. `env`
    # still finds macOS's /bin/bash 3.2 on a launchd or sketchybar PATH, where
    # sourcing would half-load with three `bad substitution` errors and leave a
    # painter that answers `type` and then draws nothing. So the version is
    # checked, not assumed, and 3.2 keeps the plain sentence.
    [ "${BASH_VERSINFO[0]:-0}" -ge 4 ] || return 0
    if [ -r "${HAUS_UI_SH:-}" ]; then
        # `|| true` is load-bearing under `set -euo pipefail`: a sourced file's
        # exit status is the body of this `if`, not its condition, so a ui.sh
        # that returns non-zero at load would abort `awake 3h` AFTER `launchctl
        # kickstart` started the assertion. That is the same failure the `type`
        # probe below exists to prevent, arriving on the other axis — a Mac held
        # awake with an error where its confirmation should be.
        # shellcheck source=/dev/null
        source "$HAUS_UI_SH" || true
    fi
    # Every verb this script calls, not a sample of them: a pin whose ui.sh
    # predates one of them is a `command not found`, and under `set -euo
    # pipefail` that aborts `awake 3h` AFTER the assertion started and BEFORE
    # anything says so — a Mac held awake with an error where the confirmation
    # should be. The plain sentence is still there for exactly that machine.
    type ui_fail ui_hint ui_paint_role ui_glyph >/dev/null 2>&1 && UI_READY=1
    return 0
}

# ---- the one sentence awake ever says about this Mac ------------------------
# Every prose verb ends here. `status` prints it having changed nothing; `awake
# 3h` and `awake off` print it having just made it true. One painter and not
# three, because the confirmation IS the status — the person who typed `awake
# off` and the person who typed `awake status` are owed the same line.
#
# fd 1, and `UI_OUT_` with it: this is a report, painted for the stream it is
# written to — the stream rule is snug's AGENTS.md, **Streams**. It
# is fd 1 for every verb including the two that change the machine, which is
# the one place this departs from `haus.sh`'s report/narrator split — awake has
# no narration to separate a report from, and the bar's popup rows have always
# run `awake 1h >/dev/null`, so moving the confirmation to fd 2 would put a
# line in sketchybar's log on every click. `die` stays on fd 2, where an error
# belongs whichever command raised it.
#
# The GLYPH carries the state and the colour only reinforces it, which is this
# family's rule rather than a preference here: `awake status` under `NO_COLOR`
# still has to say at a glance whether anything is holding this Mac awake, and
# a role resolves to the empty string there. Text is otherwise byte-identical
# to the plain branch, so a machine with no painter loses the mark and nothing
# else.
say_state() { # say_state <glyph> <role> <lead> [strong] [tail]
    local glyph=$1 role=$2 lead=$3 strong=${4:-} tail=${5:-}
    local mark plead pstrong ptail
    ui_load
    if [ -n "$UI_READY" ]; then
        ui_glyph mark "$glyph"
        ui_paint_role mark "$role" "$mark" UI_OUT_
        # `body` rather than no call at all: it always resolves to the empty
        # string, and naming it is how a caller says "deliberately unpainted"
        # out loud — ui.sh keeps it in the public nine for exactly that. A
        # future simplifier dropping it would leave the reader unable to tell
        # this from an oversight.
        ui_paint_role plead body "$lead" UI_OUT_
        # The duration is what the person came for, so it is the SUBJECT of the
        # line; "more", the parenthetical and "idle sleep is allowed" are all
        # scaffolding around it. Both are empty on the states that have no
        # number to point at — and an EMPTY segment is left unpainted rather
        # than handed to `ui_paint_role`, which would wrap nothing in a
        # set-then-reset pair and leave two escapes on a line with no text
        # between them for them to mean anything about.
        pstrong=""; [ -n "$strong" ] && ui_paint_role pstrong subject "$strong" UI_OUT_
        ptail=""; [ -n "$tail" ] && ui_paint_role ptail muted "$tail" UI_OUT_
        printf '%s%s%s%s\n' "$mark" "$plead" "$pstrong" "$ptail"
    else
        printf '%s%s%s\n' "$lead" "$strong" "$tail"
    fi
}

usage() {
    cat <<'EOF'
awake — keep this Mac from idle-sleeping.

  awake 3h              stay awake for three hours
  awake 90m             stay awake for 90 minutes
  awake indefinitely    stay awake until explicitly stopped
  awake off             allow idle sleep again
  awake status          show the current assertion

A bare number is hours (`awake 3` = three hours). The display may still turn
off, and closing a MacBook lid still sleeps it.
EOF
}

# The name stays in the message where `haus.sh`'s own `die` drops it and lets
# the glyph speak. This binary's stderr is a LOG as often as it is a terminal —
# the bar's popup rows run `awake 1h >/dev/null` with fd 2 left alone, so a
# refusal lands in sketchybar's — and in a log nothing else says who refused.
die() {
    ui_load
    if [ -n "$UI_READY" ]; then ui_fail "awake: $*"
    else printf 'awake: %s\n' "$*" >&2; fi
    exit 64
}

now() {
    if [ -n "${AWAKE_NOW:-}" ]; then
        printf '%s\n' "$AWAKE_NOW"
    else
        "$DATE" +%s
    fi
}

# Poke BOTH bars: the coffee pill can be on either one (haus.bar.bottom.items
# moves it to bar's second bar, a separate SketchyBar instance with its own mach
# service and so its own client binary). A --trigger for an event a bar never
# registered is a no-op, and the second binary only exists on a machine that
# turned that bar on — so poking both beats teaching this script which bar won.
poke_bar() {
    local bar
    for bar in "$SKETCHYBAR" "$BAR_BOTTOM"; do
        if [ -x "$bar" ]; then
            "$bar" --trigger caffeinate_change >/dev/null 2>&1 || true
        fi
    done
}

domain() {
    printf 'gui/%s/%s\n' "$(/usr/bin/id -u)" "$LABEL"
}

# Prints: token<TAB>mode<TAB>until. Invalid/truncated state is treated as off.
read_state() {
    local token mode until extra
    [ -r "$STATE_FILE" ] || return 1
    IFS="$(printf '\t')" read -r token mode until extra <"$STATE_FILE" || return 1
    [ -n "$token" ] && [ -z "${extra:-}" ] || return 1
    case "$mode" in
        indefinite)
            [ "$until" = 0 ] || return 1
            ;;
        timed)
            case "$until" in
                '' | *[!0-9]*) return 1 ;;
            esac
            ;;
        *) return 1 ;;
    esac
    printf '%s\t%s\t%s\n' "$token" "$mode" "$until"
}

write_state() {
    local mode=$1 until=$2 token tmp
    token="$(now)-$$-${RANDOM:-0}"
    /bin/mkdir -p "$STATE_DIR"
    /bin/chmod 700 "$STATE_DIR"
    tmp=$(/usr/bin/mktemp "$STATE_DIR/.state.XXXXXX")
    /bin/chmod 600 "$tmp"
    printf '%s\t%s\t%s\n' "$token" "$mode" "$until" >"$tmp"
    /bin/mv -f "$tmp" "$STATE_FILE"
}

remove_if_token() {
    local expected=$1 state token
    state=$(read_state 2>/dev/null) || return 0
    IFS="$(printf '\t')" read -r token _ _ <<EOF
$state
EOF
    if [ "$token" = "$expected" ]; then
        /bin/rm -f "$STATE_FILE"
        poke_bar
    fi
}

parse_duration() {
    local value=$1 amount unit seconds
    case "$value" in
        *minutes) amount=${value%minutes}; unit=m ;;
        *minute) amount=${value%minute}; unit=m ;;
        *mins) amount=${value%mins}; unit=m ;;
        *min) amount=${value%min}; unit=m ;;
        *hours) amount=${value%hours}; unit=h ;;
        *hour) amount=${value%hour}; unit=h ;;
        *hrs) amount=${value%hrs}; unit=h ;;
        *hr) amount=${value%hr}; unit=h ;;
        *m) amount=${value%m}; unit=m ;;
        *h) amount=${value%h}; unit=h ;;
        *) amount=$value; unit=h ;;
    esac
    case "$amount" in
        '' | *[!0-9]*) return 1 ;;
    esac
    amount=$((10#$amount))
    [ "$amount" -gt 0 ] || return 1
    if [ "$unit" = h ]; then
        [ "$amount" -le 8760 ] || return 1
        seconds=$((amount * 3600))
    else
        [ "$amount" -le 525600 ] || return 1
        seconds=$((amount * 60))
    fi
    printf '%s\n' "$seconds"
}

format_duration() {
    local seconds=$1 hours minutes
    # Round up to the next minute: "1m" is more useful than "0m" in the pill
    # and human status during the final minute.
    minutes=$(((seconds + 59) / 60))
    hours=$((minutes / 60))
    minutes=$((minutes % 60))
    if [ "$hours" -gt 0 ]; then
        printf '%dh %02dm\n' "$hours" "$minutes"
    else
        printf '%dm\n' "$minutes"
    fi
}

raw_status() {
    local state token mode until remaining current
    state=$(read_state 2>/dev/null) || {
        # Self-heal malformed state instead of leaving a lying active pill.
        [ ! -e "$STATE_FILE" ] || /bin/rm -f "$STATE_FILE"
        printf 'off\t0\t0\n'
        return
    }
    IFS="$(printf '\t')" read -r token mode until <<EOF
$state
EOF
    if [ "$mode" = indefinite ]; then
        printf 'indefinite\t0\t0\n'
        return
    fi
    current=$(now)
    remaining=$((until - current))
    if [ "$remaining" -le 0 ]; then
        remove_if_token "$token"
        printf 'off\t0\t0\n'
    else
        printf 'timed\t%s\t%s\n' "$remaining" "$until"
    fi
}

show_status() {
    local raw mode remaining until
    raw=$(raw_status)
    IFS="$(printf '\t')" read -r mode remaining until <<EOF
$raw
EOF
    case "$mode" in
        off) say_state bullet muted "idle sleep is allowed" ;;
        indefinite) say_state ok accent "awake " "indefinitely" ;;
        timed) say_state ok accent "awake for " "$(format_duration "$remaining")" \
            " more (until $("$DATE" -r "$until" '+%l:%M %p' | /usr/bin/sed 's/^ //'))" ;;
    esac
}

start_assertion() {
    local mode=$1 seconds=${2:-0} until=0
    if [ "$mode" = timed ]; then
        until=$(($(now) + seconds))
    fi
    write_state "$mode" "$until"
    if ! "$LAUNCHCTL" kickstart -k "$(domain)" >/dev/null 2>&1; then
        /bin/rm -f "$STATE_FILE"
        poke_bar
        ui_load
        if [ -n "$UI_READY" ]; then
            ui_fail "awake: could not start $LABEL"
            ui_hint "rebuild once so its launchd job is loaded"
        else
            printf 'awake: could not start %s; rebuild once so its launchd job is loaded\n' "$LABEL" >&2
        fi
        exit 1
    fi
    poke_bar
    if [ "$mode" = indefinite ]; then
        say_state ok accent "awake " "indefinitely"
    else
        say_state ok accent "awake for " "$(format_duration "$seconds")"
    fi
}

stop_assertion() {
    /bin/rm -f "$STATE_FILE"
    "$LAUNCHCTL" kill TERM "$(domain)" >/dev/null 2>&1 || true
    poke_bar
    say_state bullet muted "idle sleep is allowed"
}

# launchd-only entry point. It owns the child and only clears state if nobody
# replaced our token in the meantime (`awake 4h` racing `awake indefinitely`).
run_assertion() {
    local state token mode until remaining child=0
    state=$(read_state 2>/dev/null) || exit 0
    IFS="$(printf '\t')" read -r token mode until <<EOF
$state
EOF
    if [ "$mode" = timed ]; then
        remaining=$((until - $(now)))
        if [ "$remaining" -le 0 ]; then
            remove_if_token "$token"
            exit 0
        fi
        "$CAFFEINATE" -i -t "$remaining" &
    else
        "$CAFFEINATE" -i &
    fi
    child=$!
    trap 'if [ "$child" -gt 0 ]; then /bin/kill "$child" 2>/dev/null || true; wait "$child" 2>/dev/null || true; fi; remove_if_token "$token"; exit 0' TERM INT HUP
    wait "$child" || true
    child=0
    remove_if_token "$token"
}

command=${1:-status}
case "$command" in
    -h | --help | help)
        usage
        ;;
    status)
        if [ "${2:-}" = "--raw" ]; then raw_status; else show_status; fi
        ;;
    off | stop)
        stop_assertion
        ;;
    indefinitely | indefinite | forever | on)
        start_assertion indefinite
        ;;
    for)
        [ "$#" -ge 2 ] || die "missing duration (try: awake for 3h)"
        seconds=$(parse_duration "$2") || die "duration must be 1m–525600m or 1h–8760h"
        start_assertion timed "$seconds"
        ;;
    _run)
        run_assertion
        ;;
    *)
        seconds=$(parse_duration "$command") || die "unknown duration '$command' (try: awake 3h)"
        start_assertion timed "$seconds"
        ;;
esac
