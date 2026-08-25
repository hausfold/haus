#!/bin/sh
# `haus-notify` — one way for anything the desktop ships to put a line on
# screen, drawn by trill when trill is there and by macOS when it isn't.
#
# WHY THIS EXISTS
#
# Seventeen scripts in this repo each carried their own `osascript -e 'display
# notification …'`. That worked, and it is also the one notification surface
# the desktop cannot theme, cannot group, cannot route and cannot silence: it
# is Apple's, drawn by Notification Center, subject to Apple's per-app settings
# and nothing of ours. trill is the compositor that fixes all four, and the
# only thing standing between the two was that every call site named Apple's
# path literally. This is that name, moved to one place.
#
# WHAT DECIDES
#
# Nothing declarative — deliberately. There is no `haus.notify.*` option, and
# adding one would put a second dial in front of a mechanism that already has a
# better one: `~/.config/trill/rules.json` routes, batches, quiets and DROPS by
# `source`, is hot-reloaded on save, and is a file the user can already read.
# Every send from here carries a `--source`, so "stop telling me about the bar
# reloading" is a rule, not a rebuild. The nix-time gate arrives with the trill
# flake input (route B); until then the gate is "does the daemon answer".
#
# So: trill if the daemon takes it, Apple otherwise. `HAUS_NOTIFY` overrides —
# `apple` never tries trill, `trill` never falls back (for a caller that wants
# to know), `off` draws nothing at all.
#
# ALWAYS EXITS 0 on anything but its own misuse. A notification is a courtesy;
# a script that failed because the courtesy failed is a worse outcome than a
# missed banner, and every one of these call sites already ended in
# `>/dev/null 2>&1` for exactly that reason.

set -u

TRILL="@trill@"

usage() {
    cat >&2 <<'MESSAGE'
usage: haus-notify --title TEXT [--body TEXT] [--source NAME] [--kind KIND]
                   [--urgency low|normal|critical] [--symbol SFSYMBOL]
                   [--action "Label=https://…"]…

  --source defaults to "haus". It is what rules.json matches on, so give a
  room its own (haus.bar, haus.lane, …) rather than sharing one.
  --kind/--urgency/--symbol/--action reach trill only; macOS has nowhere to
  put them and they are dropped rather than faked.

  HAUS_NOTIFY=apple|trill|off overrides the choice of renderer.
MESSAGE
    exit 64
}

title=""
body=""
source_name="haus"
kind=""
urgency=""
symbol=""
# Actions are repeatable and there is no array in POSIX sh, so they accumulate
# into a newline-delimited list and are split back into argv below.
actions_count=0
trill_extra=""

while [ $# -gt 0 ]; do
    case "$1" in
        --title)   title="${2:-}"; shift 2 || usage ;;
        --body)    body="${2:-}"; shift 2 || usage ;;
        --source)  source_name="${2:-}"; shift 2 || usage ;;
        --kind)    kind="${2:-}"; shift 2 || usage ;;
        --urgency) urgency="${2:-}"; shift 2 || usage ;;
        --symbol)  symbol="${2:-}"; shift 2 || usage ;;
        --action)
            # Held as a newline-delimited list; `set --` rebuilds the argv from
            # it below, with IFS set to newline so a label with spaces survives.
            trill_extra="${trill_extra}--action
${2:-}
"
            actions_count=$((actions_count + 1))
            shift 2 || usage
            ;;
        -h|--help) usage ;;
        *) printf 'haus-notify: unknown argument: %s\n' "$1" >&2; usage ;;
    esac
done

[ -n "$title" ] || { printf 'haus-notify: --title is required\n' >&2; usage; }

mode="${HAUS_NOTIFY:-auto}"
[ "$mode" = "off" ] && exit 0

# --- Apple's own banner, the fallback ----------------------------------------
#
# `argv` rather than interpolation: a title or body carrying a double quote,
# a backslash or a newline would otherwise end the AppleScript string early —
# at best a mangled banner, at worst a syntax error and no banner at all. Two
# of the call sites this replaces interpolated `$1` straight in.
apple() {
    /usr/bin/osascript \
        -e 'on run argv
              display notification (item 1 of argv) with title (item 2 of argv)
            end run' \
        -- "$body" "$title" >/dev/null 2>&1
    exit 0
}

[ "$mode" = "apple" ] && apple

# --- trill --------------------------------------------------------------------

set -- send --title "$title" --source "$source_name"
[ -n "$body" ]    && set -- "$@" --body "$body"
[ -n "$kind" ]    && set -- "$@" --kind "$kind"
[ -n "$urgency" ] && set -- "$@" --urgency "$urgency"
[ -n "$symbol" ]  && set -- "$@" --symbol "$symbol"
if [ "$actions_count" -gt 0 ]; then
    old_ifs="$IFS"
    IFS='
'
    # Unquoted on purpose — this is the word split the newline IFS exists for.
    # shellcheck disable=SC2086
    set -- "$@" $trill_extra
    IFS="$old_ifs"
fi

"$TRILL" "$@" >/dev/null 2>&1
status=$?

case "$status" in
    0)
        # Accepted by the daemon — which is NOT the same as drawn: a rule,
        # quiet hours, coalescing or a digest can route it elsewhere. That is
        # the user's call and the whole reason to prefer trill, so there is
        # nothing to fall back to here.
        exit 0
        ;;
    2|127)
        # 2 = daemon unreachable, 127 = no Trill.app (this desktop's wrapper).
        # Both mean "trill could not draw it", and a machine without trill is
        # the normal case, not an error — so Apple draws it and nobody hears
        # about it.
        [ "$mode" = "trill" ] && exit "$status"
        apple
        ;;
    *)
        # 1 (bad usage) or 3 (daemon refused the request) means WE built the
        # call wrong — a haus bug, not a user's machine. Say so once on stderr
        # so it is findable, then still put the message on screen: the caller
        # had something to tell the user and that hasn't stopped being true.
        printf 'haus-notify: trill rejected this send (exit %s) — this is a haus bug\n' \
            "$status" >&2
        [ "$mode" = "trill" ] && exit "$status"
        apple
        ;;
esac
