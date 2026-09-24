#!/bin/bash
# space.sh — a workspace pill's CLICKS, and the dropdown that lists what is on
# it. Defined per workspace in sketchybarrc (`space.<ws>`).
#
# It does not paint the pill. It used to — once per pill on every workspace
# change, each run asking AeroSpace the same two questions the watcher asks
# every two seconds — and the painting lives in one place now,
# plugins/aerospace_watcher.sh over plugins/workspace_lib.sh. What is left here
# is what only the pill you touched can know: which one it was.
#
# A barlib widget with NO emitted block, the logo's shape: hand-written into
# sketchybarrc's left group (a workspace pill is not a `haus.bar.widgets`
# entry and can only ever sit on the menu bar), so there is no `# widget:`
# header — the runtime buys the click routing and the popup grid.
#
#   click           go there — or, on the pill you are already on, open the
#                   list: clicking where you stand asks "what is here?"
#   right click     the list, for any pill
#   the list        every window on the workspace and its pages, each one a
#                   row that focuses it — the Mission Control you had to open
#                   to find a floating window that sank behind the tiles
#
# "Go there" resolves a workspace that has pages the way the leader does: `T`
# goes to the page you were last on (windows/scripts/workspace-mru.sh
# resolve), because the pill stands for `T` and everything under it. A bare
# `aerospace workspace T` — what the click_script said until now — dropped you
# on an EMPTY `T` whenever your lanes lived on their pages, which is most of
# the time.
export PATH="/opt/homebrew/bin:/run/current-system/sw/bin:/usr/bin:/bin"

# shellcheck disable=SC2034 # read by bar.sh, which barlib sources
BAR_ITEM="${NAME:-}"
source "$HOME/.config/sketchybar/barlib.sh"
source "$HOME/.config/sketchybar/workspaces.sh"
source "$HOME/.config/sketchybar/plugins/workspace_lib.sh"

WS="${NAME#space.}"
# Before any row, which is where barlib wants it: popup_open lays the panel's
# top pad before it calls popup_rows, and the grid is fixed from then on.
popup_width 360
MRU="$HOME/.config/aerospace/workspace-mru.sh"

go() {
    local target="$WS"
    [ -x "$MRU" ] && target=$("$MRU" resolve "$WS" 2>/dev/null)
    "$WS_AEROSPACE" workspace "${target:-$WS}"
}

on_click() {
    local here
    here=$("$WS_AEROSPACE" list-workspaces --focused 2>/dev/null)
    if ws_is_under "$WS" "$here"; then
        popup_toggle
    else
        popup_close
        go
    fi
}

on_right_click() { popup_toggle; }

# One window as a list row. The badge is the one fact about it most likely to
# be why you opened the list, worst first: behind > fullscreen > minimised /
# hidden > floating. The focused window gets a caption rather than a badge — it
# is where you are, not a state.
row() {
    local id=$1 layout=$2 app=$3 title=$4 badge='' tone=''
    case "$layout" in
        floating) badge=floating tone=dim ;;
        *minimized*) badge=minimised tone=mute ;;
        *hidden*) badge=hidden tone=mute ;;
        *fullscreen*) badge=fullscreen tone=warn ;;
    esac
    [ "$id" = "$WS_FOCUSED_WIN" ] && [ "$WS_FULLSCREEN" = 1 ] && badge=fullscreen tone=warn
    case $'\n'"$WS_BURIED"$'\n' in
        *$'\n'"$id$WS_US"*) badge=behind tone=watch ;;
    esac
    ws_app_glyph "$app"
    local -a extra=()
    if [ -n "$badge" ]; then
        extra=(--badge "$badge" --badge-tone "$tone")
    elif [ "$id" = "$WS_FOCUSED_WIN" ]; then
        extra=(--hint focused)
    fi
    # The caption is the window's title — the thing that tells two windows of
    # one app apart. A title that is empty, or only the app's name again
    # (Calculator's is "Calculator"), says nothing the line above has not;
    # the badge already carries the window's state, so the caption just says
    # there is no title rather than repeating either.
    if [ -z "$title" ] || [ "$title" = "$app" ]; then title="no title"; fi
    popup_item --icon "$WS_GLYPH" \
        --icon-font "sketchybar-app-font:Regular:${FS_APP_ICON:-16.0}" \
        --tone text --title "$app" --subtitle "$title" \
        "${extra[@]}" \
        --run "$WS_AEROSPACE focus --window-id $id"
}

popup_rows() {
    ws_snapshot
    ws_is_under "$WS" "$WS_FOCUSED" && ws_buried
    ws_count "$WS"
    local total=$((WS_N_TILED + WS_N_LOOSE))

    # The places this pill stands for, in the order the page pill counts them:
    # the workspace itself when anything is on it, then its pages as AeroSpace
    # lists them.
    local places="" w rest
    while IFS="$WS_US" read -r w rest; do
        [ "$w" = "$WS" ] && { places="$WS"$'\n'; break; }
    done <<<"$WS_WINDOWS"
    while IFS="$WS_US" read -r w rest; do
        [ "$w" != "$WS" ] || continue
        ws_is_under "$WS" "$w" || continue
        case $'\n'"$places" in *$'\n'"$w"$'\n'*) continue ;; esac
        places="${places}${w}"$'\n'
    done <<<"$WS_WINDOWS"

    ws_icon "$WS"
    popup_heading --icon "$ICON" --icon-font "$IFONT" \
        --label "Workspace $WS" --count "$total" --tone dim

    if [ "$total" = 0 ]; then
        popup_note --label "Nothing here yet."
        return 0
    fi

    local multi=0 place id layout app title
    [ "$(printf '%s' "$places" | grep -c .)" -gt 1 ] && multi=1
    while IFS= read -r place; do
        [ -n "$place" ] || continue
        if [ "$multi" = 1 ]; then
            popup_separator
            if [ "$place" = "$WS" ]; then
                popup_note --label "$WS"
            else
                popup_note --label "$place"
            fi
        fi
        while IFS="$WS_US" read -r w id layout app title; do
            [ "$w" = "$place" ] || continue
            row "$id" "$layout" "$app" "$title"
        done <<<"$WS_WINDOWS"
    done <<<"$places"
}

barlib_main
