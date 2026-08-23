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
SKETCHYBAR="${AWAKE_SKETCHYBAR_BIN:-/run/current-system/sw/bin/sketchybar}"
# bar's optional SECOND bar (haus.bar.bottom.enable) — the same binary under a
# second name, hence a second client to poke. Absent on a machine without it.
BAR_BOTTOM="${AWAKE_BAR_BOTTOM_BIN:-/run/current-system/sw/bin/bar-bottom}"

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

die() {
    printf 'awake: %s\n' "$*" >&2
    exit 64
}

now() {
    if [ -n "${AWAKE_NOW:-}" ]; then
        printf '%s\n' "$AWAKE_NOW"
    else
        /bin/date +%s
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
        off) echo "idle sleep is allowed" ;;
        indefinite) echo "awake indefinitely" ;;
        timed) printf 'awake for %s more (until %s)\n' \
            "$(format_duration "$remaining")" \
            "$(/bin/date -r "$until" '+%l:%M %p' | /usr/bin/sed 's/^ //')" ;;
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
        printf 'awake: could not start %s; rebuild once so its launchd job is loaded\n' "$LABEL" >&2
        exit 1
    fi
    poke_bar
    if [ "$mode" = indefinite ]; then
        echo "awake indefinitely"
    else
        printf 'awake for %s\n' "$(format_duration "$seconds")"
    fi
}

stop_assertion() {
    /bin/rm -f "$STATE_FILE"
    "$LAUNCHCTL" kill TERM "$(domain)" >/dev/null 2>&1 || true
    poke_bar
    echo "idle sleep is allowed"
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
