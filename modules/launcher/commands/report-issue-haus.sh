#!/bin/bash
# pounce: name = Report haus Issue
# pounce: description = Open a pre-filled bug report for haus
# pounce: icon = ladybug

# The haus counterpart to pounce's built-in "Report Pounce Issue": opens
# github.com/hausfold/haus with a new-issue form pre-filled from a
# template. Shipped by haus (modules/launcher/commands, layered in via
# extraCommandDirs), so it only appears when pounce is used with haus.
# Same URL-query approach as the pounce built-in — nothing hosted needed.

repo="hausfold/haus"

# Environment footer, best-effort.
macos=$(sw_vers -productVersion 2>/dev/null)
[ -z "$macos" ] && macos="unknown"
host=$(scutil --get LocalHostName 2>/dev/null || hostname -s 2>/dev/null)
[ -z "$host" ] && host="unknown"

body="**What happened?**


**What did you expect?**


**Steps to reproduce**
1.
2.
3.

---
- host: ${host}
- macOS: ${macos}"

# Pure-bash percent-encoding — no python/jq dependency (the daemon inherits
# launchd's bare PATH, so we can't assume either is on it).
urlencode() {
    local s="$1" out="" c i
    for (( i = 0; i < ${#s}; i++ )); do
        c="${s:i:1}"
        case "$c" in
            [a-zA-Z0-9.~_-]) out+="$c" ;;
            *) printf -v c '%%%02X' "'$c" ; out+="$c" ;;
        esac
    done
    printf '%s' "$out"
}

url="https://github.com/${repo}/issues/new"
url+="?labels=bug"
url+="&title=$(urlencode '[bug] ')"
url+="&body=$(urlencode "$body")"

open "$url"
