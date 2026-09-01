#!/bin/zsh

# Open a file OR a directory in haus's editor, in a new tiled Ghostty window.
# @editor@ is baked from haus.terminal.editor at build time (the one editor the
# whole of haus uses — same value as $EDITOR). Called by the EditorOpen.app
# file-association handler (a file), and by nix-config-open.sh (a file plus a
# cwd override, so the window sits at the flake root rather than the file's own
# directory). The third argument — a line number — was the zellij link-handler
# plugin's caller, which is gone; the parameter stays because the line-number
# spelling table below is the only place that knowledge lives, and a future
# clicked-path opener will want it.
#
# The name says "pane" for the same reason ~/.cache/claude-worktrees does: it
# is the path every caller already spells, and renaming it buys nothing.
FILE_PATH="${1:A}"
CWD_OVERRIDE="${2:+${2:A}}"
LINE="${3:-}"

# A directory opens as `<editor> .` cwd'd into it; a file opens cwd'd at its
# nearest git repo root (so the window name and the editor's workspace match the
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

# `exec zsh` after the editor so quitting it leaves a shell rather than closing
# the window out from under you — the one thing the old zellij tab gave for
# free.
# `zsh -c SCRIPT name args…` binds `name` to $0, not $1 — hence the throwaway
# first word. After the shift "$@" is the line-number prefix, usually empty.
exec "$HOME/.config/haus/term/new-window.sh" --cwd "$DIR_PATH" -- \
    zsh -c 'target="$1"; shift; @editor@ "$@" "$target"; exec zsh' \
    editor-launcher "$TARGET" "${PRE_ARGS[@]}"
