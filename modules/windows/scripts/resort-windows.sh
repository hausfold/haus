#!/bin/bash
# Re-apply workspace assignments to every existing window.
# Mirrors the on-window-detected rules in aerospace.toml, which only fire on
# first detection — after macOS wake events windows often pile up on the
# current workspace and need re-sorting.
#
# ── it puts the LAYOUT back too, not only the page ───────────────────────────
# Sorting alone left half the job undone, and the visible half at that. Every
# runtime Ghostty window is detected as `layout floating` on purpose
# (aerospace.toml says why: a title rule races detection, and a popup tiled for
# a beat reflows the whole workspace), so the ONLY thing that ever makes one a
# tile again is the self-tile inside terminal's launch.sh / lanes/lane-open.sh.
# When one of those misses — the window was born on the wrong page, or the
# window it aimed at was not the one it was in — you get exactly what this
# script is reached for: a window on the right page after a re-sort, still
# floating at whatever size the last one happened to have. So each window this
# script claims is put back to `tiling` as well.
#
# Apps that are MEANT to float are exempt, and they are the same list
# aerospace.toml's generated float rules are built from (haus.roster.*.float) —
# passed in below rather than re-derived, so the two cannot drift. A `float`
# entry scoped by titleRegex exempts the whole app here: leaving one of its
# windows as it is costs nothing, un-floating one that asked to float is the
# thing this must never do.

set -u

focused=$(aerospace list-workspaces --focused 2>/dev/null || true)

# Space-delimited app-bundle-ids that must keep whatever layout they have —
# generated from haus._apps, same source as aerospace.toml's @FLOAT_RULES@.
floaters=" @RESORT_FLOATERS@ "

# Snapshot the window list first — piping into the loop would let the
# `aerospace move-node-to-workspace` calls inside consume stdin and starve
# the read.
windows=$(aerospace list-windows --all --format '%{window-id}|%{app-bundle-id}|%{window-title}' 2>/dev/null)

# Window ids that a zmx session has claimed with a `window=` label. Ghostty's
# `--title` is INSTANCE-WIDE, so a plain ⌘N window opened into a lane's Ghostty
# process is born wearing `scruff.<repo>.<lane>` — and moving one of those to
# T/<repo> is precisely "a window you did not touch leaving the page you were
# reading it on". A plain window always has that label and a real lane never
# does (its session is made by `zmx attach` inside the window, not by
# launch.sh), so a claimed id is the impostor. Empty, and the lane branch below
# behaves exactly as it did, on a machine with no zmx at all included.
claimed=""
command -v zmx >/dev/null 2>&1 &&
    claimed=$(zmx ls 2>/dev/null | tr '\t' '\n' | sed -n 's/^window=//p')

while IFS='|' read -r id bundle title; do
    id=$(echo "$id" | tr -d ' ')
    bundle=$(echo "$bundle" | sed 's/^ *//;s/ *$//')
    title=$(echo "$title" | sed 's/^ *//;s/ *$//')

    [ -z "$id" ] && continue

    target=""
    case "$bundle" in
        com.mitchellh.ghostty)
            case "$title" in
                # Every float-term.sh popup — peek, find, github, rebuild,
                # the palette's installers — and the dropdown itself. Placed at
                # a pixel frame, floated on purpose, wearing a floatring: a
                # re-sort must neither move one nor (since it restores layout
                # too) tile one. The prefix is float-term.sh's own rule; its
                # header says so, which is where a new popup will read it.
                quick-terminal*) continue ;;
                # A zmx lane window: its page is derivable from the forced
                # title (scruff.<repo>.<lane> → T/<repo>, the same join
                # lane-open.sh tiles by), so a re-sort HEALS a lane that a wake
                # event dumped on the wrong workspace instead of collapsing
                # every page back onto bare T. Strip the LAST segment, not the
                # first: the repo basename may itself carry dots (hausfold.co),
                # the lane name never does.
                # Both prefixes: a window born before scruff 1.2.0 renamed
                # the join wears the old FORCED title for its whole life, and
                # a re-sort that skipped it would strand it on bare T.
                scruff.*.*)
                    if [ -n "$claimed" ] && printf '%s\n' "$claimed" | grep -qFx "$id"; then
                        # Wearing a lane's name, but some session holds it by
                        # id: an ordinary terminal window, so an ordinary page.
                        target="T"
                    else
                        repo="${title#scruff.}"
                        target="T/${repo%.*}"
                    fi
                    ;;
                *) target="T" ;;
            esac
            ;;
        # Generated from haus._roster (appId -> workspace) so this stays
        # in lockstep with aerospace.toml's on-window-detected rules.
@RESORT_CASES@
        *) continue ;;
    esac

    # </dev/null is critical: aerospace reads stdin and would otherwise
    # drain the herestring, ending the loop after one iteration.
    aerospace move-node-to-workspace --window-id "$id" "$target" </dev/null >/dev/null 2>&1 || true

    case "$floaters" in
        *" $bundle "*) continue ;;
    esac
    aerospace layout --window-id "$id" tiling </dev/null >/dev/null 2>&1 || true
done <<< "$windows"

if [ -n "$focused" ]; then
    aerospace workspace "$focused" >/dev/null 2>&1 || true
fi

# This script CREATES pages — every lane window it claims lands on `T/<repo>` —
# and it ends on the workspace it started on, so `exec-on-workspace-change` never
# fires and nothing else recomputes what the palette reads. Without this line the
# sequence "wake piles the windows onto T · you switch workspace once, which
# records no pages · caps ` or a relogin sorts them back onto their pages" leaves
# `any-page` saying 0 while three pages are open, and the Pages row stays hidden
# until you happen to switch workspace again.
#
# `push` and not a second implementation: it takes the workspace as $2 and
# re-prepending the entry already at the head of the MRU is a no-op, so the only
# effect here is the verdict beside it. Same reason it runs from
# after-startup-command's copy of this script — that is the other moment pages
# exist before any workspace has changed.
[ -x "$HOME/.config/aerospace/workspace-mru.sh" ] &&
    "$HOME/.config/aerospace/workspace-mru.sh" push "$focused" >/dev/null 2>&1 || true
