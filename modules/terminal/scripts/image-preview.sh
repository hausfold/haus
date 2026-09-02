#!/usr/bin/env bash
# image-preview.sh — terminal-native image preview. yazi's Enter opener for an
# image (yazi/… `run` in modules/terminal), and a reader in its own right.
#
# Renders with `chafa -f kitty`: REAL PIXELS, at the terminal's own resolution.
# It used to render truecolor half-block art (`-f symbols`) and carried a long
# comment explaining that this was the only mode that could survive the
# pipeline — zellij's VTE parser drops kitty-graphics APC outright, and forwards
# sixel only when the host terminal advertises it in DA1, which Ghostty (kitty
# protocol, no sixel) does not. That parser is gone. This is the escape hatch
# that file's own header described, taken.

set -u

# yazi spawns this directly, not through a login shell — make sure the nix
# profile bins (chafa) are reachable regardless.
export PATH="$PATH:/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin"

# ---- snug's bash painter ----------------------------------------------------
# Role names, not colours. This file is a `home.file` symlink into the store
# with nothing substituted into it, so nothing injects `HAUS_UI_SH` for it the
# way the `haus` wrapper does — ui_resolve finds the painter beside `snug`,
# which the PATH export above makes findable at all (yazi spawns this without
# a login shell), and a caller's own variable still wins.

# ── ui_resolve — the painter's PATH, and nothing else ────────────────────────
# The ONE copy of this block is modules/lib/ui-load.nix; `nix flake check`
# (ui-load-sync) diffs this file against it, so edit it THERE and re-copy.
# Honour a caller's HAUS_UI_SH — the `haus` wrapper and the injecting
# derivations set an absolute store path — else take the copy that ships
# beside `bin/snug` in snug's own derivation, which can never be a version
# apart from the binary; the carrier's own PATH setup is what makes `snug`
# findable at all. Never the name `UI_SH`: that exact name is ui.sh's own
# source-twice sentinel, and a caller holding the path in it makes the file
# return before defining anything — no error, no colour, and a green suite,
# because every role is legitimately empty when the painter is absent. Ends
# readable-or-empty, so `[ -n "$HAUS_UI_SH" ]` is the whole downstream test.
# No source, no bash-version check: resolving must stay safe in a shell that
# could never LOAD the painter — that is ui_load's job, where one exists.
ui_resolve() {
    if [ -z "${HAUS_UI_SH:-}" ]; then
        local _snug
        _snug="$(command -v snug 2>/dev/null)" \
            && HAUS_UI_SH="$(dirname "$(dirname "$(readlink -f "$_snug")")")/share/ui.sh"
    fi
    [ -r "${HAUS_UI_SH:-}" ] || HAUS_UI_SH=""
    return 0
}

# ── ui_load — source the painter once, and answer whether it can draw ────────
# The ONE copy of this block is modules/lib/ui-load.nix; `nix flake check`
# (ui-load-sync) diffs this file against it, so edit it THERE and re-copy.
# UI_READY=1 only when every verb named in UI_WANT arrived: the carrier sets
# UI_WANT to every ui_* verb it CALLS, not a sample, because a pin whose ui.sh
# predates one of them is a `command not found` halfway down a report — under
# `set -e` an abort AFTER the machine changed and before anything said so —
# and UI_READY would have licensed it. Idempotent, so calling it lazily from
# each draw path and calling it once at load are the same verb; a path that
# never draws never calls it and pays nothing. Three traps, each silent, each
# paid for before this block existed:
#
#   * ui.sh is bash 4+ (`declare -gA`, `${v^^}`). macOS's /bin/bash 3.2 does
#     not fail it quietly: three `bad substitution` errors and a half-loaded
#     painter that answers `type` and then draws nothing — so the version is
#     checked, never assumed, and 3.2 keeps the plain output.
#   * `|| true` is load-bearing under `set -euo pipefail`: a sourced file's
#     non-zero exit is the caller's to survive, and a ui.sh that failed at
#     load would otherwise abort the verb mid-flight — for `awake 3h`, AFTER
#     the assertion started.
#   * The path stays in `HAUS_UI_SH`, never `UI_SH` — that exact name is
#     ui.sh's own source-twice sentinel, and holding the path in it makes the
#     file return before defining anything, with no error and no colour.
UI_READY=""
ui_load() {
    [ -n "${UI_LOADED:-}" ] && return 0
    UI_LOADED=1
    [ "${BASH_VERSINFO[0]:-0}" -ge 4 ] || return 0
    if [ -r "${HAUS_UI_SH:-}" ]; then
        # shellcheck source=/dev/null
        source "$HAUS_UI_SH" || true
    fi
    [ -n "${UI_WANT:-}" ] || return 0
    # shellcheck disable=SC2086
    type $UI_WANT >/dev/null 2>&1 && UI_READY=1
    return 0
}
# Probed by the two verbs the palette below calls.
UI_WANT="ui__detect_profile ui__resolve_palette"
ui_resolve
ui_load

# The five slots this reader has, each an alias onto a generated role — so the
# hexes come from snug's script/gen-palette.sh resolved against nebelung, not
# from the bold-ANSI-basic set that used to sit here. Two deliberate losses in
# the move, both of which the standard calls correct:
#
#   * The header's filename was `\e[1m` bold and is now `subject`, the role for
#     "the thing under discussion" — which is exactly what it is. The nine roles
#     carry colour only; a bold attribute is not a role and had no way to be one.
#   * The hotkeys, the flash and the error were bold-magenta/green/red. Bold is
#     gone with them; the letters and the ✓ carry the meaning, which is this
#     standard's own rule that the glyph is load-bearing and the colour is not.
#
# Everything degrades to empty on a terminal that cannot colour, and the whole
# reader still draws — every escape below lives OUTSIDE the printf widths.
BOLD=; DIM=; RESET=; KEY=; OK=; ERR=
if [ -n "$UI_READY" ]; then
    RESET="${UI_OFF:-}"
    BOLD="${UI_SUBJECT:-}"   # the image being read
    DIM="${UI_MUTED:-}"      # dimensions, size, the separators between hotkeys
    KEY="${UI_ACCENT:-}"     # hotkey letters — the tool speaking
    OK="${UI_OK:-}"          # confirmation flashes
    ERR="${UI_ERR:-}"        # errors
fi

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

# Name the WINDOW after the image instead of the raw command line. OSC 2 rather
# than a rename action: the window is the surface now, and its title is whatever
# the program inside last set.
printf '\033]2;🖼  %s\007' "$name"

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

    clear
    printf '  %s%s%s' "$BOLD" "$name" "$RESET"
    [ -n "$dims" ] && printf '  %s%s px%s' "$DIM" "$dims" "$RESET"
    printf '  %s%s%s' "$DIM" "$size" "$RESET"

    tput cup 2 0
    chafa -f kitty --center=on --size="${cols}x${body_rows}" "$path"
    draw_hints
}

# The only two raw escapes left, and both are legal: DECTCEM is cursor
# visibility, not colour, and there is no role for it — snug owns the cursor
# inside a live region, and this reader owns its whole screen instead.
quit() {
    printf '\e[?25h' # show cursor
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
