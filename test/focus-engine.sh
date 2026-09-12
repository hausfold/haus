#!/usr/bin/env bash
# The ONE place a focus suite turns modules/focus/focus.sh into the script the
# module actually builds. Sourced, never run.
#
# It exists because the sed table below MIRRORS modules/focus/default.nix's
# `--subst-var-by` names, and a hand-copied mirror is the thing this family
# keeps getting caught by: a new placeholder there would otherwise reach the
# engine unsubstituted and a suite would keep passing, testing a script the
# module never builds. So the mirror is checked rather than trusted — anything
# left in @placeholder@ form fails the build, naming itself — and there is one
# copy of it rather than one per suite, because two tables drift the same way
# one table and a module do.
#
# Comment lines are stripped before the check: the script's own header explains
# the @var@ convention in prose, and every real substitution is on the
# right-hand side of an assignment.

# focus_build_engine <source focus.sh> <scenes.json> <ui.sh path> <out>
focus_build_engine() {
    local src=$1 scenes=$2 uish=$3 out=$4 left
    sed -e "s|@jq@|/usr/bin/jq|" \
        -e "s|@keyCode@|105|" \
        -e "s|@timerLabel@|'com.hausfold.focus-timer'|" \
        -e "s|@pounceBin@|''|" \
        -e "s|@slackEnabled@|0|" \
        -e "s|@slackTokenCommand@|''|" \
        -e "s|@slackTokenHint@|'run: haus-secret --check'|" \
        -e "s|@slackStatusText@|'heads down'|" \
        -e "s|@slackStatusEmoji@|':no_bell:'|" \
        -e "s|@slackSnooze@|0|" \
        -e "s|@hooks@||" \
        -e "s|@scenes@|$scenes|" \
        -e "s|@switchAudio@||" \
        -e "s|@uiSh@|$uish|" \
        "$src" >"$out"
    chmod +x "$out"
    left=$(/usr/bin/grep -v '^[[:space:]]*#' "$out" \
        | /usr/bin/grep -oE '@[a-zA-Z][a-zA-Z0-9]*@' | sort -u || true)
    if [ -n "$left" ]; then
        printf 'not ok - a placeholder survived (%s) — test/focus-engine.sh has drifted from modules/focus/default.nix\n' \
            "$(printf '%s' "$left" | /usr/bin/tr '\n' ' ')" >&2
        return 1
    fi
    return 0
}
