#!/bin/zsh

# Open a file OR a directory in the rice editor, in a new zellij tab. @editor@
# is baked from haus.terminal.editor at build time (the one editor the whole
# rice uses — same value as $EDITOR). Called by the EditorOpen.app
# file-association handler (a file), by nix-config-open.sh (a file plus a
# cwd override, so the pane sits at the flake root rather than the file's own
# directory), and by the zellij link-handler plugin when a clicked path
# carried a line number (a file, an empty cwd override, and the line).
FILE_PATH="${1:A}"
CWD_OVERRIDE="${2:+${2:A}}"
LINE="${3:-}"

# 1. Ensure Ghostty is running
if ! pgrep -x "Ghostty" > /dev/null; then
    open -a "Ghostty"
    # Wait for Ghostty and Zellij to bootstrap
    sleep 2.0
fi

# 2. Check if the "main" zellij session is active
if ! zellij list-sessions 2>/dev/null | grep -q "main"; then
    # Wait up to 5 seconds for the session to appear
    for i in {1..10}; do
        sleep 0.5
        if zellij list-sessions 2>/dev/null | grep -q "main"; then
            break
        fi
    done
fi

# A directory opens as `<editor> .` cwd'd into it; a file opens cwd'd at its
# nearest git repo root (so the tab name and the editor's workspace match the
# project it lives in), falling back to the file's own parent dir outside a repo.
# An explicit cwd passed as $2 (nix-config-open.sh) always wins.
if [ -d "$FILE_PATH" ]; then
    DIR_PATH="$FILE_PATH"
    TARGET="."
else
    PARENT="${FILE_PATH:h}"
    DIR_PATH="${CWD_OVERRIDE:-$(git -C "$PARENT" rev-parse --show-toplevel 2>/dev/null || echo "$PARENT")}"
    TARGET="$FILE_PATH"
fi

# A line number, when the caller had one (a clicked `foo.rs:26`), is spelled
# differently by every editor and there is no portable flag: helix takes it
# glued to the path, VS Code wants --goto, and everything vi-shaped (vim,
# nvim, nano, emacs) takes `+N` BEFORE the file. Unknown editors get the `+N`
# form, which is the widest convention; a directory target never gets one.
EDITOR_CMD=(@editor@)
PRE_ARGS=()
if [ -n "$LINE" ] && [ "$TARGET" != "." ]; then
    case "${EDITOR_CMD[1]:t}" in
        hx|helix) TARGET="$TARGET:$LINE" ;;
        code|codium|cursor) PRE_ARGS=(--goto); TARGET="$TARGET:$LINE" ;;
        *) PRE_ARGS=("+$LINE") ;;
    esac
fi

# 3. Open in a new tab with zsh and the editor
if zellij list-sessions 2>/dev/null | grep -q "main"; then
    # Focus Ghostty to bring it to front
    osascript -e 'tell application "Ghostty" to activate'

    # Open in a new tab running zsh, cd to the dir, run the editor, and exec zsh
    # on exit. After the two shifts "$@" is the line-number prefix, which is
    # usually empty and then expands to nothing at all.
    zellij -s main action new-tab -- zsh -c 'if cd "$1"; then shift; target="$1"; shift; @editor@ "$@" "$target"; fi; exec zsh' "editor-launcher" "$DIR_PATH" "$TARGET" "${PRE_ARGS[@]}"
else
    # Fallback: Open a fresh Ghostty window running the editor on the target.
    # cd first, because a directory target is spelled "." above and would
    # otherwise open the editor on Ghostty's own cwd.
    open -na "Ghostty" --args -e "cd \"$DIR_PATH\" && @editor@ ${PRE_ARGS[*]} \"$TARGET\""
fi
