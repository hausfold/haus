#!/bin/bash
# pounce: name = Peek Files (Stay)
# pounce: description = Peek without hopping out of an agent worktree
# pounce: icon = folder.fill

# ⌘⇧Y's target. A hotkey target is a bare `cmd:<id>` with no arguments, so the
# stay flag needs a file of its own; everything real lives in peek.sh.
exec "$HOME/.config/haus/term/peek.sh" --stay
