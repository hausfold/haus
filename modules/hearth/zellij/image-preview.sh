#!/bin/bash
# image-preview.sh — terminal-native image preview for the zellij link-handler.
#
# Spawned by the link-handler plugin in a floating pane when an image path is
# clicked (a bare click, in a pane no application is tracking the mouse in). Renders with chafa in `symbols` mode (truecolor half-block
# art) — the ONLY mode that survives this pipeline: zellij's VTE parser drops
# kitty-graphics APC sequences outright, and it only forwards sixel when the
# host terminal advertises it in its DA1 response, which Ghostty (kitty
# protocol only, no sixel) does not. Don't "upgrade" this to --format=kitty
# or sixels; you'll get a blank pane.

set -u

# The plugin spawns this directly, not through a login shell — make sure the
# nix profile bins (chafa, zellij) are reachable regardless.
export PATH="$PATH:/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin"

BOLD=$'\e[1m'
DIM=$'\e[2m'
RESET=$'\e[0m'
KEY=$'\e[1;35m'   # bold magenta — hotkey letters
OK=$'\e[1;32m'    # bold green — confirmation flashes
ERR=$'\e[1;31m'   # bold red — errors

path="${1:-}"
if [ -z "$path" ] || [ ! -f "$path" ]; then
    printf '\n  %serror:%s no such image: %s\n\n  press any key to close\n' "$ERR" "$RESET" "${path:-<none>}"
    read -rsn1
    exit 1
fi

name=$(basename "$path")

# Static facts for the header (sips can't read every format; omit when empty).
dims=$(sips -g pixelWidth -g pixelHeight "$path" 2>/dev/null \
    | awk '/pixelWidth:/ {w=$2} /pixelHeight:/ {h=$2} END {if (w && h) printf "%s×%s", w, h}')
bytes=$(stat -f%z "$path" 2>/dev/null || echo 0)
size=$(awk -v b="$bytes" 'BEGIN {
    split("B KB MB GB", u); i = 1
    while (b >= 1024 && i < 4) { b /= 1024; i++ }
    printf (i == 1 ? "%d %s" : "%.1f %s"), b, u[i]
}')

# Name the floating pane after the image instead of the raw command line.
zellij action rename-pane "🖼  $name" 2>/dev/null

rows=0
cols=0

draw_hints() {
    tput cup $((rows - 1)) 0
    tput el
    printf '  %sq%s%s close  %s·%s  %sp%s%s copy path  %s·%s  %sc%s%s copy image  %s·%s  %so%s%s open in Preview  %s·%s  %sf%s%s reveal in Finder%s' \
        "$KEY" "$RESET" "$DIM" "$DIM" "$RESET" \
        "$KEY" "$RESET" "$DIM" "$DIM" "$RESET" \
        "$KEY" "$RESET" "$DIM" "$DIM" "$RESET" \
        "$KEY" "$RESET" "$DIM" "$DIM" "$RESET" \
        "$KEY" "$RESET" "$DIM" "$RESET"
}

flash() {
    tput cup $((rows - 1)) 0
    tput el
    printf '  %s✓ %s%s' "$OK" "$1" "$RESET"
    sleep 1
    draw_hints
}

draw() {
    cols=$(tput cols)
    rows=$(tput lines)
    # Row 0: header. Last row: hints. One blank row of breathing room each side.
    local body_rows=$((rows - 4))
    ((body_rows < 1)) && body_rows=1

    local fmt="symbols"
    if [ -z "${ZELLIJ:-}" ] && [ "${TERM_PROGRAM:-}" = "Ghostty" -o -n "${GHOSTTY_RESOURCES_DIR:-}" ]; then
        fmt="kitty"
    fi

    if [ "$fmt" = "symbols" ]; then
        local art
        if ! art=$(chafa -f symbols -c full --center=on --size="${cols}x${body_rows}" "$path" 2>&1); then
            clear
            printf '\n  %schafa failed to render %s:%s\n\n%s\n' "$ERR" "$name" "$RESET" "$art"
            draw_hints
            return
        fi

        local art_rows pad
        art_rows=$(printf '%s\n' "$art" | wc -l | tr -d ' ')
        pad=$(( (body_rows - art_rows) / 2 ))
        ((pad < 0)) && pad=0

        clear
        printf '  %s%s%s' "$BOLD" "$name" "$RESET"
        [ -n "$dims" ] && printf '  %s%s px%s' "$DIM" "$dims" "$RESET"
        printf '  %s%s%s' "$DIM" "$size" "$RESET"

        tput cup $((2 + pad)) 0
        printf '%s\n' "$art"
        draw_hints
    else
        clear
        printf '  %s%s%s' "$BOLD" "$name" "$RESET"
        [ -n "$dims" ] && printf '  %s%s px%s' "$DIM" "$dims" "$RESET"
        printf '  %s%s%s' "$DIM" "$size" "$RESET"

        tput cup 2 0
        chafa -f kitty --center=on --size="${cols}x${body_rows}" "$path"
        draw_hints
    fi
}

quit() {
    printf '\e[?25h' # show cursor
    # A zellij command pane lingers after its command exits ("press Enter to
    # re-run") — close the pane explicitly so q/Esc dismisses in one press.
    zellij action close-pane 2>/dev/null
    exit 0
}

printf '\e[?25l' # hide cursor
trap draw SIGWINCH
trap quit INT TERM

draw

while true; do
    key=""
    read -rsn1 key
    status=$?
    if [ $status -ne 0 ]; then
        # >128 = read interrupted by a trapped signal (WINCH redraw);
        # anything else means stdin is gone — close instead of spinning.
        [ $status -gt 128 ] && continue
        quit
    fi

    if [ "$key" = $'\e' ]; then
        # Swallow any escape-sequence tail (arrow keys etc.); bare Esc quits.
        read -rsn2 -t 0.05 seq || true
        [ -z "${seq:-}" ] && quit
        continue
    fi

    case "$key" in
        q|Q) quit ;;
        p|P)
            printf '%s' "$path" | pbcopy
            flash "copied path"
            ;;
        c|C)
            # Copy as a file reference — pastes as the image into Finder,
            # Slack, Discord, mail, etc.
            osascript -e "set the clipboard to (POSIX file \"$path\")" >/dev/null 2>&1
            flash "copied image"
            ;;
        o|O)
            /usr/bin/open "$path"
            flash "opened in Preview"
            ;;
        f|F)
            /usr/bin/open -R "$path"
            flash "revealed in Finder"
            ;;
    esac
done
