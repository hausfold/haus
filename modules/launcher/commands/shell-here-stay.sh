#!/bin/bash
# pounce: name = New Shell Window (Stay)
# pounce: description = Shell window staying in an agent worktree's directory
# pounce: icon = terminal.fill

# ⌘⇧P's target. A hotkey target is a bare `cmd:<id>` with no arguments, so the
# stay flag needs a file of its own; everything real lives in shell-here.sh.
exec "$(dirname "$0")/shell-here.sh" --stay
