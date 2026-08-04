#!/bin/bash
# find.sh — ⌘F (this pane) and ⌘⇧F (every pane): full-text search across
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
# zellij also has no cross-pane search of any kind, so ⌘⇧F has nothing native
# to sit on regardless.
#
# So: one overlay, both keys, both pane kinds. Native search stays reachable on
# its own path (Ctrl g → scroll → `/`, see config.kdl) for in-place n/N
# highlighting, which the overlay deliberately does not try to replace.
#
# WHERE THE TEXT COMES FROM, per pane
#   Claude pane   → its Claude Code transcript, via claude-statusline's pane →
#     transcript map (modules/den/statusline.sh writes pane-transcripts.tsv on
#     every render — it's the one process that knows both $ZELLIJ_PANE_ID and
#     the transcript path). Same join the Links picker uses.
#   Opencode pane → that conversation's rows in opencode's SQLite history, via
#     the `.session` file agent-state writes (its plugin runs inside the
#     opencode server process, so it inherits $ZELLIJ_PANE_ID the same way),
#     falling back to a match on the session's recorded directory. See
#     opencode_session / render_opencode.
#   any other pane → `zellij action dump-screen --full -p <id>`, the pane's
#     whole scrollback. That includes CODEX panes: it reports pane state through
#     agent-state like the others, but passes no conversation id and this repo
#     knows no on-disk history path for it, so there is nothing to join to.
#
# WHICH PANE DID THE USER MEAN (the non-obvious part)
#
# A zellij keybind can only `Run` something, and running it opens a PANE, which
# takes focus — so by the time this script starts, the *client's* focused pane
# is this script's own launcher float. `list-clients` reports only that float
# (zellij-org/zellij#4067), so it can't name the pane underneath.
#
# `list-panes --json` can: it reports THIS TAB's panes with their own is_focused
# flag, and the focused tiled pane keeps that flag while a floating pane is up.
# So the launcher just reads it, synchronously, and never has to wait for focus
# to come back:
#
#   `launch`  runs in the 1% corner float: read the focused tiled pane, then
#             open the overlay pane and exit (which closes the float).
#   `ui`      runs inside the overlay pane: build the corpus, then fzf, driven
#             by rg on every keystroke.
#
# NOTHING MAY BE DETACHED FROM THE LAUNCHER. This used to `nohup` a stage-2
# helper and exit immediately, which never ran at all: when a `close_on_exit`
# pane's command exits, zellij tears down its whole process group, and nohup
# only blocks SIGHUP. The helper was killed before its first line — ⌘F opened a
# 1% float for a few milliseconds and then, visibly, nothing. Anything that must
# outlive the launcher has to be a zellij PANE (as the overlay is), not a
# background child of it.
#
# The corpus is ALWAYS every pane, even for pane scope — scope is just which
# subdirectory rg is pointed at. That makes the in-overlay scope toggle
# (Ctrl-s) instant instead of a rebuild, which is the whole reason it's worth
# having a toggle at all.
#
# Gotchas encoded here:
#   - Commands spawned from a zellij bind inherit a thin PATH; resolve
#     zellij/jq/rg/fzf/bat off an explicit one (same prelude as links.sh).
#     That PATH sees ONLY the nix profiles, so every one of those has to be a
#     real installed binary — a shell alias or a bare store path that happens to
#     work in an interactive shell is invisible here. `rg` shipped missing
#     exactly this way once (modules/den declares it in the toolbelt now); the
#     preflight in cmd_ui is what stops that from ever looking like "no hits".
#   - `zellij action` run from inside a pane must not see that pane's inherited
#     $ZELLIJ — `env -u ZELLIJ` + an explicit `-s <session>`, or the action is
#     routed at the pane rather than the session we resolved.
#   - list-panes ids are bare integers; list-clients prints them as
#     "terminal_88". Strip the prefix before joining against anything.
#   - A pane's RUNNING_COMMAND is its DEEPEST FOREGROUND process, not what you
#     launched — a Claude pane routinely reports node, rg or sourcekit-lsp.
#     Never gate the transcript lookup on it; presence in the map is the only
#     reliable "this is an agent pane" signal.
#   - dump-screen takes `--path FILE` or prints to stdout; it has NO positional
#     file argument (passing one makes zellij 0.44 exit with a usage error and
#     leave an empty dump, i.e. a silent "no results").

set -u

# Same prelude as links.sh, but $USER is defaulted: this runs under `set -u`,
# and a detached process spawned off a zellij bind is not guaranteed to have it.
export PATH="/run/current-system/sw/bin:/etc/profiles/per-user/${USER:-$(id -un)}/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin"

# The overlay pane re-enters this same script, so it needs an absolute path to
# it. Derive it from $0 rather than hardcoding the installed location, so a
# worktree copy can be exercised end to end (launcher float → overlay pane)
# without a rebuild; the installed path is the fallback.
case "$0" in
    /*) SELF="$0" ;;
    *) SELF="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")" ;;
esac
[ -x "$SELF" ] || SELF="$HOME/.config/zellij/find.sh"
CACHE_DIR="${CLAUDE_STATUSLINE_CACHE:-$HOME/.cache/claude-statusline}"
MAP="$CACHE_DIR/pane-transcripts.tsv"
# Rendered transcripts are cached by (size, mtime) so a repeat search on a
# multi-megabyte conversation is instant instead of another full jq pass.
RENDER_CACHE="$HOME/.cache/nebelhaus/find/transcripts"
# Opencode's history db. The filename moved between releases (`opencode.db` →
# `opencode-stable.db`), so take whichever exists rather than pinning one and
# silently degrading every opencode pane to scrollback after an upgrade.
# Empty when opencode isn't installed, or when sqlite3 isn't around to read it.
OPENCODE_DB=""
if command -v sqlite3 >/dev/null 2>&1; then
    for _db in "$HOME/.local/share/opencode/opencode-stable.db" \
        "$HOME/.local/share/opencode/opencode.db"; do
        [ -f "$_db" ] && OPENCODE_DB="$_db" && break
    done
fi
zj() { env -u ZELLIJ zellij -s "$SESSION" "$@"; }

# ── stage 1: the 1% launcher float ──────────────────────────────────────────
# Runs inside the throwaway float the keybind opens. Resolves the pane the user
# was actually on, opens the overlay pane, and exits — which closes the float
# and hands focus to the overlay.
#
# Everything here is synchronous ON PURPOSE: see the "nothing may be detached"
# note in the header.
cmd_launch() {
    local scope="${1:-pane}"
    SESSION="${ZELLIJ_SESSION_NAME:-}"
    [ -n "$SESSION" ] ||
        SESSION=$(env -u ZELLIJ zellij list-sessions -n 2>/dev/null |
            grep -v EXITED | head -1 | awk '{print $1}')
    [ -n "$SESSION" ] || exit 0

    # The pane the user meant = this tab's focused TILED pane. `list-panes`
    # (without --all, so: this tab) keeps reporting it as focused even while
    # this launcher float sits on top of it, which is precisely the read
    # `list-clients` cannot give — that one only ever names the float
    # (zellij-org/zellij#4067). No polling, no waiting for focus to snap back.
    local target
    target=$(zj action list-panes --json 2>/dev/null |
        jq -r 'first(.[] | select(.is_focused and (.is_floating | not)
                                  and (.is_plugin | not)) | .id) // empty' 2>/dev/null)

    local dir
    dir=$(mktemp -d -t zellij-find) || exit 0
    mkdir -p "$dir/src"
    printf '%s\n' "$target" >"$dir/target"
    printf '%s\n' "$SESSION" >"$dir/session"

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
               | [(.id|tostring), (.tab_name // ""), (.title // ""), (.pane_cwd // "")] | @tsv' \
            >"$dir/panes.raw" 2>/dev/null

    [ -s "$dir/panes.raw" ] || return 0

    : >"$dir/panes.tsv"
    local id tab title cwd transcript ocsid kind label
    while IFS=$'\t' read -r id tab title cwd; do
        [ -n "$id" ] || continue
        # Our own two panes are not worth searching. The launcher is usually
        # gone by now and the overlay doesn't exist yet, but a Ctrl-s rebuild or
        # a second ⌘F over an open overlay would otherwise index them.
        case "$title" in find | find-launch) continue ;; esac

        transcript=""
        [ -f "$MAP" ] &&
            transcript=$(awk -F'\t' -v i="$id" '$1==i{t=$2} END{print t}' "$MAP")

        if [ -n "$transcript" ] && [ -f "$transcript" ]; then
            kind="claude"
            render_transcript "$transcript" "$dir/src/$id.txt" &
        elif ocsid=$(opencode_session "$id" "$cwd") && [ -n "$ocsid" ]; then
            kind="opencode"
            render_opencode "$ocsid" "$dir/src/$id.txt" &
        else
            kind="shell"
            zj action dump-screen --full -p "$id" >"$dir/src/$id.txt" 2>/dev/null &
        fi

        label="${tab:-?}/${title:-pane $id}"
        printf '%s\t%s\t%s\n' "$id" "$label" "$kind" >>"$dir/panes.tsv"
    done <"$dir/panes.raw"
    wait
}

# Which opencode conversation, if any, is this pane showing?
#
# Two routes, most-precise first:
#   1. The `.session` file agent-state writes (modules/sill/sketchybar/plugins/
#      agents-hook.sh). The opencode plugin runs inside the opencode server
#      process, which is a child of the pane, so it inherits $ZELLIJ_PANE_ID and
#      can report the id `chat.message` hands it. Exact, and correct even with
#      two opencode panes on the same checkout.
#   2. Failing that, the newest non-archived session whose recorded `directory`
#      IS this pane's cwd. Covers the pane that was already open before any of
#      this shipped, and the one that hasn't sent a first message yet — both of
#      which have no `.session` file and would otherwise fall to scrollback.
#      Ambiguous if two opencode panes share a checkout; newest wins, which is
#      the better half of a bad guess.
#
# Empty output (and non-zero) means "not an opencode pane", which is also what a
# machine with no opencode at all returns on the very first test.
opencode_session() {
    local id="$1" cwd="$2" sf sid
    [ -n "$OPENCODE_DB" ] || return 1

    sf="/tmp/nebelhaus-agents/${SESSION}__terminal_${id}.session"
    if [ -f "$sf" ]; then
        sid=$(cat "$sf" 2>/dev/null)
        [ -n "$sid" ] && printf '%s' "$sid" && return 0
    fi

    [ -n "$cwd" ] || return 1
    sid=$(sqlite3 "$OPENCODE_DB" \
        "SELECT id FROM session
          WHERE directory = '$(printf '%s' "$cwd" | sed "s/'/''/g")'
            AND time_archived IS NULL
          ORDER BY time_updated DESC LIMIT 1;" 2>/dev/null)
    [ -n "$sid" ] && printf '%s' "$sid" && return 0
    return 1
}

# One opencode conversation → readable lines, newest last.
#
# The text lives in a JSON `data` blob per row, whose shape is opencode's
# business and changes between versions (there are two generations of it in the
# schema right now — the v1 `part` table and the newer `session_message`). So
# don't parse the shape: walk it with `json_tree` and take every string leaf,
# minus the key names that are ids and type tags. That's the same call the
# Claude renderer makes, for the same reason, and it means an opencode release
# that reshapes a part still searches fine.
#
# No cache here, unlike render_transcript: the query is indexed on session_id
# and returns one conversation, where the Claude side re-reads a whole
# append-only file that can run to tens of megabytes.
#
# `sqlite3 "$db" "..."` with no read-only flag matches statusline-refresh.sh,
# which has been reading this same db on a timer for a while — worth staying
# identical to the call that's known to work here rather than being cleverer
# unverified. It's a WAL db; concurrent reads while opencode writes are fine.
render_opencode() {
    local sid="$1" out="$2" tables sql t
    : >"$out"
    tables=$(sqlite3 "$OPENCODE_DB" \
        "SELECT name FROM sqlite_master WHERE type='table';" 2>/dev/null) || return 0

    # Ids and discriminators, never prose. json_tree gives array indices as
    # integer keys, which are not in this list and so pass through.
    local skip="'type','id','messageID','sessionID','callID','partID','tool','status','state','mime','filename','path','url','source','providerID','modelID','agent','role','snapshot','time'"

    for t in part session_message; do
        grep -qx "$t" <<<"$tables" || continue
        sql="SELECT tr.value FROM $t r, json_tree(r.data) tr
              WHERE r.session_id = '$(printf '%s' "$sid" | sed "s/'/''/g")'
                AND tr.type = 'text'
                AND (tr.key IS NULL OR tr.key NOT IN ($skip))
              ORDER BY r.time_created, r.id;"
        sqlite3 "$OPENCODE_DB" "$sql" 2>/dev/null >>"$out"
    done
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
    SESSION="$session" # what zj() routes at, for build_corpus below

    trap 'rm -rf "$dir"' EXIT

    # A missing tool here is otherwise INVISIBLE: fzf runs its reload bind in a
    # subshell whose stderr goes nowhere, so no `rg` means an overlay that opens,
    # accepts typing, and simply never matches anything — indistinguishable from
    # "your search has no hits". Say so instead, and hold the pane open (it's
    # --close-on-exit, so an unheld message would flash past).
    # A plain string, not an array: the shebang is /bin/bash, which on macOS is
    # still 3.2, where `${#arr[@]}` on an EMPTY array trips `set -u`.
    local missing="" tool
    for tool in rg fzf bat; do
        command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
    done
    if [ -n "$missing" ]; then
        printf '\n  find is missing:%s\n\n' "$missing"
        printf '  These resolve off this script'\''s own PATH, not your shell'\''s,\n'
        printf '  so a shell alias will not do. Install via the rice:\n'
        printf '    nebelhaus.developer.toolbelt.enable = true;  (then haus rebuild)\n\n'
        printf '  press any key to close '
        { read -r -n 1 -s </dev/tty; } 2>/dev/null || sleep 10
        exit 0
    fi

    # The corpus is built HERE, in the overlay pane, not by the launcher: the
    # launcher's process group dies with its float, and dumping a session's
    # worth of panes is exactly the kind of work that would get killed halfway.
    # It also means the overlay is on screen while it happens, so a multi-second
    # index reads as "working" instead of as a keypress that did nothing.
    printf '\n  indexing panes…\n'
    build_corpus "$dir"

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
    ui) shift; cmd_ui "$@" ;;
    _rg) shift; cmd_rg "$@" ;;
    _preview) shift; cmd_preview "$@" ;;
    *) printf 'usage: find.sh launch [pane|session]\n' >&2; exit 2 ;;
esac
