#!/bin/bash
# pounce: name = Copy Text from Screen
# pounce: description = Drag an area; the text in it lands on the clipboard
# pounce: icon = text.viewfinder
# pounce: cheat = copy screen text
#
# The screenshot gesture, but the crop's TEXT is the product: macOS's own
# interactive capture (`screencapture -i`, the same call spawn-agent's ⌘↵
# makes — no second crosshair to keep in sync with the OS) into a temp file,
# `hausocr` (Vision, offline — see ../hausocr.swift) over it, result onto the
# clipboard. The image is deleted either way; nothing is ever saved.
#
# ⌘⇧2 by default — beside macOS's own ⌘⇧3/4/5 capture family, the key the
# established OCR-capture tools train. The binding is a launcher item like any
# other: rebind or null it with haus.launcher.items."cmd:copy-text".hotkey.
set -u

say() { /run/current-system/sw/bin/haus-notify --source haus.launcher.copytext "$@" >/dev/null 2>&1; }

# BSD mktemp wants the Xs at the END of the template, and screencapture wants
# an extension it recognizes — so make the anchor file, then capture beside it.
base="$(mktemp -t haus-copy-text)" || exit 0
shot="$base.png"
trap 'rm -f "$base" "$shot"' EXIT

# -x: no shutter sound — nothing is being saved. -t png: pin the format so
# hausocr's input doesn't follow haus.screenshots.format around. Esc during the
# drag exits non-zero with an empty file: a change of mind, not an error.
if ! /usr/sbin/screencapture -i -x -t png "$shot" || [ ! -s "$shot" ]; then
  exit 0
fi

text="$(@hausocr@ "$shot")"
rc=$?
if [ "$rc" -eq 3 ] || { [ "$rc" -eq 0 ] && [ -z "$text" ]; }; then
  say --title "No text found" --body "Nothing legible in that area" \
    --symbol text.viewfinder
  exit 0
elif [ "$rc" -ne 0 ]; then
  say --kind fault --symbol exclamationmark.triangle \
    --title "Copy Text failed" --body "hausocr exited $rc"
  exit 0
fi

printf '%s' "$text" | /usr/bin/pbcopy

# Confirmation carries proof, not just a count: the first line is how you know
# at a glance the recognition read the thing you meant. Truncation is bash's
# substring under an explicit UTF-8 locale, not `cut -c` — the daemon spawns
# this with no locale, where BSD cut counts bytes and would split a curly
# quote or a CJK character mid-sequence at the preview's tail.
export LC_ALL=en_US.UTF-8
count="$(printf '%s\n' "$text" | wc -l | tr -d ' ')"
preview="${text%%$'\n'*}"
preview="${preview:0:80}"
if [ "$count" -eq 1 ]; then
  say --title "Copied to clipboard" --body "$preview" --symbol text.viewfinder
else
  say --title "Copied $count lines" --body "$preview" --symbol text.viewfinder
fi
