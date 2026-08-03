#!/bin/bash
# find.sh — ⌘F / ⌘/ (this pane) and ⌘⇧/ (every pane): full-text search across
# the zellij session, in a floating overlay, live as you type.
#
# WHY THIS ISN'T JUST `SwitchToMode "EnterSearch"`
#
# zellij's native search is excellent — for a shell pane. It is useless for the
# panes you most want to search: hearth seeds Claude Code with `tui =
# "fullscreen"` (modules/hearth/default.nix), so an agent pane renders in the
# ALT-SCREEN, which by definition has no scrollback. Native search there sees
# exactly the one screenful in front of you, and `dump-screen --full` returns
# the same. For those panes the session TRANSCRIPT is the only real corpus —
# and it's a better one anyway: complete, not truncated at scroll_buffer_size,
# and it still holds what was inside collapsed tool output.
#
# zellij also has no cross-pane search of any kind, so ⌘⇧/ has nothing native
# to sit on regardless.
#
# So: one overlay, both keys, both pane kinds. Native search stays reachable on
# its own path (Ctrl g → scroll → `/`, see config.kdl) for in-place n/N
# highlighting, which the overlay deliberately does not try to replace.
#
# WHERE THE TEXT COMES FROM, per pane
#   agent pane → its Claude Code transcript, via claude-statusline's pane →
#     transcript map (modules/den/statusline.sh writes pane-transcripts.tsv on
#     every render — it's the one process that knows both $ZELLIJ_PANE_ID and
#     the transcript path). Same join the Links picker uses.
#   any other pane → `zellij action dump-screen --full -p <id>`, the pane's
#     whole scrollback.
#
# THE FOCUS DANCE (the non-obvious part)
#
# A zellij keybind can only `Run` something, and running it opens a PANE, which
# takes focus — so by the time this script starts, "the focused pane" is this
# script's own launcher and the pane the user actually meant is unreachable.
# `list-clients` reports only the floating pane when one is focused
# (zellij-org/zellij#4067), so there is nothing to read underneath it either.
#
# The Links bind dodges this by accident: it Runs `pounce`, an NSPanel that
# never touches zellij focus, from a throwaway 1% float that has already closed
# by the time the command runs. We do the same on purpose, explicitly:
#
#   `launch`  runs in the 1% corner float. It detaches `open` and exits
#             immediately, so the float closes and focus snaps back.
#   `open`    (detached, no pane) polls list-clients until the focused pane is
#             something OTHER than the launcher we were spawned from, and that
#             is the target. Then it builds the corpus and opens the overlay.
#   `ui`      runs inside the overlay pane: fzf, driven by rg on every keystroke.
#
# The corpus is ALWAYS every pane, even for pane scope — scope is just which
# subdirectory rg is pointed at. That makes the in-overlay scope toggle
# (Ctrl-s) instant instead of a rebuild, which is the whole reason it's worth
# having a toggle at all.
#
# Gotchas encoded here:
#   - Commands spawned from a zellij bind inherit a thin PATH; resolve
#     zellij/jq/rg/fzf/bat off an explicit one (same prelude as links.sh).
#   - `zellij action` from a detached process must not see an inherited
#     $ZELLIJ from the pane that spawned it — `env -u ZELLIJ` + explicit -s.
#   - list-clients prints pane ids as "terminal_88"; $ZELLIJ_PANE_ID inside a
#     pane is bare "88". Strip the prefix before joining against anything.
#   - list-clients' RUNNING_COMMAND is the pane's DEEPEST FOREGROUND process,
#     not what you launched — a Claude pane routinely reports node, rg or
#     sourcekit-lsp. Never gate the transcript lookup on it; presence in the
#     map is the only reliable "this is an agent pane" signal.
#   - dump-screen takes `--path FILE` or prints to stdout; it has NO positional
#     file argument (passing one makes zellij 0.44 exit with a usage error and
#     leave an empty dump, i.e. a silent "no results").

set -u

# Same prelude as links.sh, but $USER is defaulted: this runs under `set -u`,
# and a detached process spawned off a zellij bind is not guaranteed to have it.
export PATH="/run/current-system/sw/bin:/etc/profiles/per-user/${USER:-$(id -un)}/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin"

SELF="$HOME/.config/zellij/find.sh"
CACHE_DIR="${CLAUDE_STATUSLINE_CACHE:-$HOME/.cache/claude-statusline}"
MAP="$CACHE_DIR/pane-transcripts.tsv"
# Rendered transcripts are cached by (size, mtime) so a repeat search on a
# multi-megabyte conversation is instant instead of another full jq pass.
RENDER_CACHE="$HOME/.cache/nebelhaus/find/transcripts"
# How long to wait for zellij focus to snap back off the launcher float.
FOCUS_TICKS=40 # ×0.05s

zj() { env -u ZELLIJ zellij -s "$SESSION" "$@"; }

# ── stage 1: the 1% launcher float ──────────────────────────────────────────
# Nothing happens here. Detach and die, so the float closes and the user's real
# pane gets focus back before `open` looks for it.
cmd_launch() {
    local scope="${1:-pane}"
    nohup "$SELF" open "$scope" "${ZELLIJ_PANE_ID:-}" "${ZELLIJ_SESSION_NAME:-}" \
        >/dev/null 2>&1 &
    exit 0
}

# ── stage 2: detached — resolve the target pane, build the corpus, open the UI ─
cmd_open() {
    local scope="$1" launcher="$2"
    SESSION="$3"
    [ -n "$SESSION" ] ||
        SESSION=$(env -u ZELLIJ zellij list-sessions -n 2>/dev/null |
            grep -v EXITED | head -1 | awk '{print $1}')
    [ -n "$SESSION" ] || exit 0

    launcher=${launcher#terminal_}

    # Wait for focus to come off the launcher. Bounded: if the float somehow
    # outlives us we still search *something* rather than hanging on a keypress.
    local target="" i pane
    for ((i = 0; i < FOCUS_TICKS; i++)); do
        pane=$(zj action list-clients 2>/dev/null | awk 'NR==2{print $2}')
        pane=${pane#terminal_}
        if [ -n "$pane" ] && [ "$pane" != "$launcher" ]; then
            target="$pane"
            break
        fi
        sleep 0.05
    done

    local dir
    dir=$(mktemp -d -t zellij-find) || exit 0
    mkdir -p "$dir/src"
    printf '%s\n' "$target" >"$dir/target"
    printf '%s\n' "$SESSION" >"$dir/session"

    build_corpus "$dir"

    # Scope falls back to session when we never pinned a target pane — an empty
    # "this pane" search would just look broken.
    [ -n "$target" ] || scope="session"

    # Overlay geometry mirrors the yazi-jump float (Super Shift y): big enough
    # to read a preview beside the hit list, still obviously an overlay.
    zj action new-pane --floating --close-on-exit \
        --name find --x 5% --y 5% --width 90% --height 90% \
        -- "$SELF" ui "$dir" "$scope" >/dev/null 2>&1
}

# Dump every pane once. Agent panes render from their transcript, everything
# else from full scrollback. Panes are dumped in parallel — dump-screen is a
# cheap IPC round-trip, but a jq pass over a tens-of-MB transcript is not.
build_corpus() {
    local dir="$1"
    mkdir -p "$RENDER_CACHE"

    zj action list-panes --all --json 2>/dev/null |
        jq -r '.[] | select(.is_plugin == false)
               | [(.id|tostring), (.tab_name // ""), (.title // "")] | @tsv' \
            >"$dir/panes.raw" 2>/dev/null

    [ -s "$dir/panes.raw" ] || return 0

    : >"$dir/panes.tsv"
    local id tab title transcript kind label
    while IFS=$'\t' read -r id tab title; do
        [ -n "$id" ] || continue
        # Our own two panes are not worth searching. The launcher is usually
        # gone by now and the overlay doesn't exist yet, but a Ctrl-s rebuild or
        # a second ⌘F over an open overlay would otherwise index them.
        case "$title" in find | find-launch) continue ;; esac

        transcript=""
        [ -f "$MAP" ] &&
            transcript=$(awk -F'\t' -v i="$id" '$1==i{t=$2} END{print t}' "$MAP")

        if [ -n "$transcript" ] && [ -f "$transcript" ]; then
            kind="agent"
            render_transcript "$transcript" "$dir/src/$id.txt" &
        else
            kind="shell"
            zj action dump-screen --full -p "$id" >"$dir/src/$id.txt" 2>/dev/null &
        fi

        label="${tab:-?}/${title:-pane $id}"
        printf '%s\t%s\t%s\n' "$id" "$label" "$kind" >>"$dir/panes.tsv"
    done <"$dir/panes.raw"
    wait
}

# Transcript JSONL → readable lines. Every string inside a user/assistant
# record, which covers message text AND the tool_result content nested in user
# records — the same shape links.sh mines for URLs, minus the JSON scaffolding.
#
# links.sh can take every string leaf because it only ever greps the result for
# URLs. A search corpus can't: `.. | strings` also yields the DISCRIMINATOR
# values, so a plain walk emits a junk line reading "text", "tool_use" or
# "tool_result" before every real one — matching "tool" in the overlay would
# have returned one hit per tool call, all of them the literal word. Hence the
# key-name filter; the excluded keys are ids and type tags, never prose.
#
# `fromjson?` keeps a torn mid-write final line (Claude is probably appending to
# this file right now) from aborting the whole stream.
render_transcript() {
    local src="$1" out="$2" stamp key cached
    stamp=$(stat -f '%z-%m' "$src" 2>/dev/null || echo 0)
    key="$RENDER_CACHE/$(printf '%s' "$src" | shasum | cut -c1-16).$stamp"

    if [ -f "$key" ]; then
        cp "$key" "$out" 2>/dev/null && return 0
    fi
    # Drop stale renders of this transcript (same hash, older stamp).
    for cached in "${key%.*}".*; do
        [ -e "$cached" ] && rm -f "$cached"
    done

    jq -Rr 'fromjson?
            | select(.type=="user" or .type=="assistant")
            | .message.content
            | [paths(strings) as $p
               | select(($p[-1]|tostring)
                        | IN("type","id","name","tool_use_id","cache_control","signature")
                        | not)
               | getpath($p)]
            | .[]' \
        "$src" 2>/dev/null >"$key"
    cp "$key" "$out" 2>/dev/null
}

# ── stage 3: the overlay ────────────────────────────────────────────────────
cmd_ui() {
    local dir="$1" scope="${2:-pane}"
    local target session
    target=$(cat "$dir/target" 2>/dev/null)
    session=$(cat "$dir/session" 2>/dev/null)

    trap 'rm -rf "$dir"' EXIT

    # Ctrl-s toggles scope by EXITING fzf and reopening it, not by fzf's
    # `become`: become execs over the fzf process, which inherits this shell's
    # stdout, so the re-entered UI's result would land in the outer command
    # substitution and get acted on twice — the selection focused, and the line
    # copied, once per toggle. A plain loop is boring and correct, and
    # --print-query lets the typed query survive the switch, which become
    # couldn't have done anyway.
    #
    # The toggle is instant because the corpus already holds every pane in both
    # scopes; scope is only which path rg is aimed at.
    local out query key sel id line
    while :; do
        local scoped_label="this pane" other="session"
        [ "$scope" = "session" ] && scoped_label="every pane" other="pane"

        out=$(fzf \
            --ansi --disabled --no-sort --layout=reverse --info=inline \
            --border --border-label=" find · $scoped_label " \
            --prompt='  ' --pointer='▍' --marker='▍' \
            --query="${query:-}" \
            --delimiter='\t' --with-nth='2..' \
            --preview="$SELF _preview $dir {1} {3}" \
            --preview-window='right,55%,border-left' \
            --bind="change:reload:$SELF _rg $dir $scope {q}" \
            --header="⏎ focus pane · ^y copy line · ^s search $other · esc close" \
            --print-query --expect=ctrl-y,ctrl-s </dev/null)

        query=$(sed -n 1p <<<"$out")
        key=$(sed -n 2p <<<"$out")
        sel=$(sed -n 3p <<<"$out")

        [ "$key" = "ctrl-s" ] || break
        scope="$other"
    done

    [ -n "$sel" ] || exit 0
    id=$(cut -f1 <<<"$sel")
    line=$(cut -f4- <<<"$sel")

    # The matched line goes to the clipboard on BOTH exits. ^y is the explicit
    # "I only wanted the text" key; on ⏎ it's a free consolation prize if the
    # focus call below turns out to be a no-op (see next comment).
    printf '%s' "$line" | pbcopy
    [ "$key" = "ctrl-y" ] && exit 0

    # ⏎ — go to the pane the hit came from. focus-pane-with-id landed in zellij
    # 0.44.1; on anything older it exits non-zero and the overlay simply closes,
    # which is a fine floor for a key whose text you already have.
    [ -n "$id" ] &&
        env -u ZELLIJ zellij -s "$session" action focus-pane-with-id "$id" \
            >/dev/null 2>&1
    exit 0
}

# ── fzf helpers ─────────────────────────────────────────────────────────────
# Emit: <pane id> \t <label> \t <line no> \t <text>. fzf shows fields 2.. and
# keeps the id for the ⏎ action.
cmd_rg() {
    local dir="$1" scope="$2" q="${3:-}"
    [ -n "$q" ] || exit 0

    local root="$dir/src" target
    if [ "$scope" = "pane" ]; then
        target=$(cat "$dir/target" 2>/dev/null)
        [ -n "$target" ] && root="$dir/src/$target.txt"
    fi
    [ -e "$root" ] || exit 0

    rg --line-number --no-heading --with-filename --color=never \
        --smart-case --max-columns=400 --max-columns-preview \
        -e "$q" "$root" 2>/dev/null |
        awk -F: -v panes="$dir/panes.tsv" '
            BEGIN {
                while ((getline l < panes) > 0) {
                    split(l, f, "\t"); label[f[1]] = f[2]; kind[f[1]] = f[3]
                }
            }
            {
                path = $1; lineno = $2
                text = $0
                sub(/^[^:]*:[0-9]+:/, "", text)
                n = split(path, p, "/"); id = p[n]; sub(/\.txt$/, "", id)
                tag = label[id]; if (tag == "") tag = "pane " id
                # dim label + line number, so the matched text carries the eye
                printf "%s\t\033[2m%s\033[0m\t%s\t%s\n", id, tag, lineno, text
            }' |
        head -2000
}

cmd_preview() {
    local dir="$1" id="${2:-}" lineno="${3:-}"
    local file="$dir/src/$id.txt"
    [ -f "$file" ] && [ -n "$lineno" ] || exit 0
    local from=$((lineno - 12))
    [ "$from" -lt 1 ] && from=1
    bat --color=always --style=numbers --paging=never \
        --highlight-line "$lineno" --line-range "$from:$((lineno + 12))" \
        "$file" 2>/dev/null ||
        sed -n "$from,$((lineno + 12))p" "$file"
}

case "${1:-}" in
    launch) shift; cmd_launch "$@" ;;
    open) shift; cmd_open "$@" ;;
    ui) shift; cmd_ui "$@" ;;
    _rg) shift; cmd_rg "$@" ;;
    _preview) shift; cmd_preview "$@" ;;
    *) printf 'usage: find.sh launch [pane|session]\n' >&2; exit 2 ;;
esac
