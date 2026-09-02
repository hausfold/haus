#!/bin/bash
# find.sh — ⌘F (this window) and ⌘⇧F (every window): full-text search across
# every zmx session, in a floating overlay, live as you type.
#
# WHY THIS EXISTS AT ALL
#
# Ghostty has no find. It also has no way to be ASKED for one: its AppleScript
# API can create and focus a surface but cannot read a single character back —
# no dump-screen, no scrollback, no text property. The corpus therefore comes
# from zmx, which is exactly why every window runs inside a session
# (scripts/launch.sh). This overlay is the reason that design decision was made,
# not a consumer that happened to find it useful.
#
# It also has to exist for the windows you most want to search: terminal seeds
# Claude Code with `tui = "fullscreen"` (modules/terminal/default.nix), so an
# agent renders in the ALT-SCREEN, which by definition has no scrollback. For
# those the session TRANSCRIPT is the only real corpus — and it is a better one
# anyway: complete, and it still holds what was inside collapsed tool output.
#
# WHERE THE TEXT COMES FROM, per session
#   Claude window   → its Claude Code transcript, via claude-statusline's
#     session → transcript map (modules/ai/statusline.sh writes
#     pane-transcripts.tsv on every render — it's the one process that knows
#     both $ZMX_SESSION and the transcript path). Same join the Links picker uses.
#   Opencode window → that conversation's rows in opencode's SQLite history, via
#     the `convo` LABEL agents-hook.sh sets on the session (its plugin runs
#     inside the opencode server process, so it inherits $ZMX_SESSION the same
#     way), falling back to a match on the session's recorded directory. See
#     opencode_session / render_opencode.
#   any other       → `zmx history <session>`, the whole scrollback. That is
#     MORE than the old zellij path gave: `dump-screen --full` was capped at
#     scroll_buffer_size. It includes CODEX windows: Codex reports state through
#     agent-state like the others, but passes no conversation id and this repo
#     knows no on-disk history path for it, so there is nothing to join to.
#
# WHICH WINDOW DID THE USER MEAN
#
# The one that has focus. pounce's Ghostty-scoped tap fires this from the
# daemon, and the palette panel never appears, so nothing has taken focus away
# from the terminal by the time we run. scripts/focused-session.sh turns that
# window into a session name — by window id, which is the `lwindow=` label
# lanes/lane-open.sh stamps for a lane and the `window=` one scripts/launch.sh
# stamps for everything else, and only then by a lane's forced title.
#
# This is a two-stage script and it stays two-stage, though the reason changed.
# Under zellij, stage 1 ran inside a throwaway 1% pane and could not detach
# anything (a `close_on_exit` pane's command exiting tears down its whole
# process group, so a `nohup`ed helper was killed before its first line). Now
# stage 1 runs in the pounce daemon, and the split is simply that the overlay is
# a different process in a different window:
#
#   `launch`  resolve the focused session, then spawn the overlay window.
#   `ui`      runs inside the overlay: build the corpus, then fzf, driven by rg
#             on every keystroke.
#
# The corpus is ALWAYS every session, even for `this window` scope — scope is
# just which subdirectory rg is pointed at. That makes the in-overlay scope
# toggle (Ctrl-s) instant instead of a rebuild, which is the whole reason it is
# worth having a toggle at all.
#
# Gotchas encoded here:
#   - The pounce daemon spawns commands on launchd's bare PATH; resolve
#     zmx/jq/rg/fzf off an explicit one (same prelude as links.sh). That PATH
#     sees ONLY the nix profiles, so every one of those has to be a real
#     installed binary — a shell alias or a bare store path that happens to work
#     in an interactive shell is invisible here. `rg` shipped missing exactly
#     this way once (modules/core declares it in the toolbelt now); the preflight
#     in cmd_ui is what stops that from ever looking like "no hits".
#   - A session's RUNNING command is not what you launched — a Claude window
#     routinely has node, rg or sourcekit-lsp in front. Never gate the
#     transcript lookup on it; presence in the map is the only reliable "this is
#     an agent" signal.
#   - macOS's awk is BWK awk: no `\x` escapes (so `-F'\x01'` is the literal FS
#     "x01"), no `length()` in characters, and byte-counting %-*s padding. Octal
#     escapes, and pad-without-truncating, or a multi-byte label gets sliced.
#   - VERSION FLOOR, and it fails invisibly. The overlay needs fzf ≳0.65
#     (--footer, --footer-border, --ghost, --gutter, --highlight-line,
#     --info=inline-right, --border-label-pos). fzf rejects an unknown option and
#     exits at once, and the overlay window closes when its command does, so on
#     an older pin ⌘F flashes a window and does nothing — the same silent shape
#     the cmd_ui preflight exists to prevent, which only checks that the binaries
#     EXIST, never which flags they take. Bump the floor here when you reach for
#     a newer flag.

set -u

# Same prelude as links.sh, but $USER is defaulted: this runs under `set -u`,
# and a process spawned by the pounce daemon is not guaranteed to have it.
export PATH="/run/current-system/sw/bin:/etc/profiles/per-user/${USER:-$(id -un)}/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin"

# The overlay window re-enters this same script, so it needs an absolute path to
# it. Derive it from $0 rather than hardcoding the installed location, so a
# worktree copy can be exercised end to end (launch → overlay) without a
# rebuild; the installed path is the fallback.
case "$0" in
    /*) SELF="$0" ;;
    *) SELF="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")" ;;
esac
[ -x "$SELF" ] || SELF="$HOME/.config/haus/term/find.sh"
CACHE_DIR="${CLAUDE_STATUSLINE_CACHE:-$HOME/.cache/claude-statusline}"
MAP="$CACHE_DIR/pane-transcripts.tsv"
# Rendered transcripts are cached by (size, mtime) so a repeat search on a
# multi-megabyte conversation is instant instead of another full jq pass.
RENDER_CACHE="$HOME/.cache/haus/find/transcripts"
# Opencode's history db. The filename moved between releases (`opencode.db` →
# `opencode-stable.db`), so take whichever exists rather than pinning one and
# silently degrading every opencode window to scrollback after an upgrade.
# Empty when opencode isn't installed, or when sqlite3 isn't around to read it.
OPENCODE_DB=""
if command -v sqlite3 >/dev/null 2>&1; then
    for _db in "$HOME/.local/share/opencode/opencode-stable.db" \
        "$HOME/.local/share/opencode/opencode.db"; do
        [ -f "$_db" ] && OPENCODE_DB="$_db" && break
    done
fi
# Every live zmx session, one per line: "<name>\t<dir>". The directory is under
# either of the two names zmx has used for it — 0.7.0 prints `start_dir=<plain
# path>` and no `cwd`; a newer one prints `cwd=file://Mac/Users/…` — so take
# whichever is there and strip the URL scheme, which is a no-op on a plain path.
zmx_sessions() {
    zmx ls 2>/dev/null | awk -F'\t' '
        {
            name = ""; c = ""; sd = ""
            for (i = 1; i <= NF; i++) {
                p = index($i, "=")
                if (p == 0) continue
                k = substr($i, 1, p - 1); gsub(/^[ \t]+|[ \t]+$/, "", k)
                # zmx marks the row you are ATTACHED to in its first field
                # ("-> ** name=..."), gluing the marker onto that key. Strip
                # anything before the key proper or the session you are
                # sitting in is the one row that never matches.
                sub(/^[^A-Za-z_]*/, "", k)
                if (k == "name")      name = substr($i, p + 1)
                if (k == "cwd")       c    = substr($i, p + 1)
                if (k == "start_dir") sd   = substr($i, p + 1)
            }
            if (name == "") next
            if (c == "") c = sd
            sub(/^file:\/\/[^\/]*/, "", c)
            printf "%s\t%s\n", name, c
        }'
}

# One session's labels as "k=v" lines. agents-hook.sh sets `convo` here; nothing
# else in this script reads a label, so this stays a one-liner rather than
# growing a parser.
zmx_label() { # zmx_label <session> <key>
    zmx get "$1" 2>/dev/null | tr '\t' '\n' |
        sed -n "s/^ *$2=//p" | head -1
}

# ── stage 1: resolve the window, open the overlay ───────────────────────────
# Runs in the pounce daemon (the ⌘F / ⌘⇧F appHotkeys target). Resolves the
# session the user was looking at, drops it in a temp dir the overlay reads, and
# spawns the overlay window.
cmd_launch() {
    local scope="${1:-pane}"

    # The focused window's session. Nothing has stolen focus — pounce's panel is
    # never shown for an appHotkeys chord — so this is the window the chord was
    # pressed in. See scripts/focused-session.sh for the two joins.
    local target
    target="$("$(dirname "$SELF")/focused-session.sh" 2>/dev/null)"

    local dir
    dir=$(mktemp -d -t haus-find) || exit 0
    mkdir -p "$dir/src"
    printf '%s\n' "$target" >"$dir/target"

    # Scope falls back to every-session when we never pinned a target — an empty
    # "this window" search would just look broken.
    [ -n "$target" ] || scope="session"

    # A FLOATING window, and its SIZE follows its SCOPE — the one place in
    # haus where two chords of the same script want different geometry:
    #
    #   ⌘F  (pane)     matched to the frame of the window that summoned it, so
    #                  find reads as that terminal switching into a search. The
    #                  corpus is that window's scrollback and nothing else, so a
    #                  result you click is already on screen behind the overlay
    #                  — covering exactly the window it belongs to is the honest
    #                  shape, not a compromise.
    #   ⌘⇧F (session)  the whole tiled desktop. This corpus is EVERY session, so
    #                  there is no one window the overlay belongs to; sizing it
    #                  to whichever pane happened to be focused made a
    #                  cross-session result list draw in a half-width column and
    #                  implied a scope it doesn't have.
    #
    # ^s flips scope mid-search, so the rule can't live on this path alone:
    # `replant` below re-sizes the open window on every toggle, both ways.
    #
    # Under zellij both were a 100%/100% borderless floating PANE; --pin lands it
    # on the current workspace and force-floats it, since windows/aerospace.toml
    # floats every runtime-spawned Ghostty window anyway.
    #
    # The overlay's own window has no zmx session (float-term runs the command
    # directly, not through scripts/launch.sh), which is also why it never shows
    # up in its own corpus — there is nothing to enumerate.
    # Stash the summoning window's frame for ^s. Once the overlay is up it IS
    # the focused window, so --match-focused can no longer find the terminal
    # that summoned us — a toggle back to pane scope has to replay a rectangle
    # captured here, before the popup exists. `geom` always answers something —
    # a frame it can't read, or that describes a window on no screen, degrades
    # to a centred 80% of this screen — so the shrink-back below lands
    # somewhere sane even then; place --frame's no-op guard is for the file
    # being missing or truncated, not for that.
    local ft="$HOME/.config/haus/term/float-term.sh" frame
    frame="$("$ft" geom --match-focused 2>/dev/null)"
    printf '%s\n' "$frame" >"$dir/frame"

    # ONE resolve, used twice: pane scope hands that same rectangle to spawn
    # rather than asking for it again. Two asks cost a second AX round trip on
    # a keystroke, and they can disagree — focus moves while a window is being
    # opened — which would size the overlay to one window and shrink it back
    # onto another.
    local -a geom_args=(--frame "$frame")
    [ "$scope" = "session" ] && geom_args=(--tiled)

    "$ft" spawn \
        --title "quick-terminal-find" \
        "${geom_args[@]}" \
        --pin \
        --command "/bin/bash $SELF ui $dir $scope" >/dev/null
}

# Dump every session once. Agent sessions render from their transcript,
# everything else from `zmx history`. Sessions are dumped in parallel — a
# history read is a cheap socket round-trip, but a jq pass over a tens-of-MB
# transcript is not.
build_corpus() {
    local dir="$1"
    mkdir -p "$RENDER_CACHE"

    zmx_sessions >"$dir/panes.raw"
    [ -s "$dir/panes.raw" ] || return 0

    # The LABEL is the session name, shortened.
    #
    # A lane is `scruff.<repo>.<lane>`, and the prefix is on every single
    # one — pure width spent on nothing, in a column whose whole job is telling
    # rows apart. `<repo>.<lane>` is what you would navigate by, and it is
    # exactly the key the bar's popup joins scruff on. A plain window keeps its
    # `term.<n>` as-is: it is already short, and the number is the only thing
    # distinguishing one shell from another.
    #
    # No de-duplication pass here, unlike the zellij version, which had to
    # number `workshop.1`, `workshop.2` because several panes could share one
    # tab name. A zmx session name is unique by construction.
    # This column was live-broken for a release: the `sub` was flipped to
    # `scruff\.` during the rename while lane-open.sh was still writing the old
    # prefix, so every lane row carried its full prefix in the one column whose
    # job is telling rows apart. Keep the two spellings in step.
    awk -F'\t' '{ n = $1; sub(/^scruff\./, "", n); printf "%s\t%s\n", $1, n }' \
        "$dir/panes.raw" >"$dir/labels.tsv"

    : >"$dir/panes.tsv"
    local id cwd transcript ocsid kind label
    while IFS=$'\t' read -r id cwd; do
        [ -n "$id" ] || continue

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
            zmx history "$id" >"$dir/src/$id.txt" 2>/dev/null &
        fi

        label=$(awk -F'\t' -v i="$id" '$1==i{l=$2} END{print l}' "$dir/labels.tsv")
        printf '%s\t%s\t%s\n' "$id" "${label:-$id}" "$kind" >>"$dir/panes.tsv"
    done <"$dir/panes.raw"
    wait
}

# Which opencode conversation, if any, is this session showing?
#
# Two routes, most-precise first:
#   1. The `convo` LABEL agents-hook.sh sets (modules/bar/sketchybar/plugins/
#      agents-hook.sh). The opencode plugin runs inside the opencode server
#      process, which is a child of the session, so it inherits $ZMX_SESSION and
#      can report the id `chat.message` hands it. Exact, and correct even with
#      two opencode windows on the same checkout.
#   2. Failing that, the newest non-archived session whose recorded `directory`
#      IS this session's cwd. Covers the window that was already open before any
#      of this shipped, and the one that hasn't sent a first message yet — both
#      of which have no label and would otherwise fall to scrollback. Ambiguous
#      if two opencode windows share a checkout; newest wins, which is the
#      better half of a bad guess.
#
# Empty output (and non-zero) means "not an opencode window", which is also what
# a machine with no opencode at all returns on the very first test.
opencode_session() {
    local id="$1" cwd="$2" sid
    [ -n "$OPENCODE_DB" ] || return 1

    sid=$(zmx_label "$id" convo)
    [ -n "$sid" ] && printf '%s' "$sid" && return 0

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

# ── resize this overlay to match a changed scope ────────────────────────────
# Runs INSIDE the popup, so the pid float-term needs is the Ghostty process
# hosting us — not $$, which is this bash. Walk up until a `ghostty` shows: the
# chain is ghostty → bash (float-term's --command) → us, but nothing here
# depends on its length.
host_ghostty_pid() {
    local p=$$ comm
    while [ "${p:-0}" -gt 1 ]; do
        comm=$(ps -o comm= -p "$p" 2>/dev/null)
        case "${comm##*/}" in ghostty) echo "$p"; return 0 ;; esac
        p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
    done
    return 0
}

# replant <dir> <scope> — grow to the tiled desktop for an every-session search,
# shrink back to the summoning window's stashed frame for a this-window one.
# Silent and best-effort throughout: a search in a mis-sized window still works.
replant() {
    local dir="$1" scope="$2" pid
    pid=$(host_ghostty_pid)
    [ -n "$pid" ] || return 0
    local ft="$HOME/.config/haus/term/float-term.sh"
    [ -x "$ft" ] || return 0
    if [ "$scope" = "session" ]; then
        "$ft" place "$pid" --tiled >/dev/null 2>&1
    else
        "$ft" place "$pid" --frame "$(cat "$dir/frame" 2>/dev/null)" >/dev/null 2>&1
    fi
}

# ── stage 2: the overlay ────────────────────────────────────────────────────
cmd_ui() {
    local dir="$1" scope="${2:-pane}"
    local target
    target=$(cat "$dir/target" 2>/dev/null)

    trap 'rm -rf "$dir"' EXIT

    # A missing tool here is otherwise INVISIBLE: fzf runs its reload bind in a
    # subshell whose stderr goes nowhere, so no `rg` means an overlay that opens,
    # accepts typing, and simply never matches anything — indistinguishable from
    # "your search has no hits". Say so instead, and hold the window open (Ghostty
    # closes it when the command exits, so an unheld message would flash past).
    # A plain string, not an array: the shebang is /bin/bash, which on macOS is
    # still 3.2, where `${#arr[@]}` on an EMPTY array trips `set -u`.
    # bat is deliberately NOT in this list any more — cmd_preview renders the
    # context window with awk now. This list is the tools whose ABSENCE would be
    # invisible rather than loud, which is why it isn't every binary the script
    # touches: awk, jq, zmx and sqlite3 also resolve off the PATH above, but awk
    # is in every base system and the other three fail where you can see it.
    local missing="" tool
    for tool in rg fzf; do
        command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
    done
    if [ -n "$missing" ]; then
        printf '\n  find is missing:%s\n\n' "$missing"
        printf '  These resolve off this script'\''s own PATH, not your shell'\''s,\n'
        printf '  so a shell alias will not do. Install via haus:\n'
        printf '    haus.developer.toolbelt.enable = true;  (then haus rebuild)\n\n'
        printf '  press any key to close '
        { read -r -n 1 -s </dev/tty; } 2>/dev/null || sleep 10
        exit 0
    fi

    # The corpus is built HERE, in the overlay, not in stage 1: stage 1 runs in
    # the pounce daemon, and holding a keystroke handler open for a multi-second
    # index is how a chord comes to feel broken. It also means the overlay is on
    # screen while it happens, so the wait reads as "working" rather than as a
    # keypress that did nothing.
    printf '\n  indexing windows…\n'
    build_corpus "$dir"

    # Ctrl-s toggles scope by EXITING fzf and reopening it, not by fzf's
    # `become`: become execs over the fzf process, which inherits this shell's
    # stdout, so the re-entered UI's result would land in the outer command
    # substitution and get acted on twice — the selection focused, and the line
    # copied, once per toggle. A plain loop is boring and correct, and
    # --print-query lets the typed query survive the switch, which become
    # couldn't have done anyway.
    #
    # The toggle is instant because the corpus already holds every session in
    # both scopes; scope is only which path rg is aimed at.
    #
    # `start:reload` matters BECAUSE of that loop: --query restores the text you
    # had typed, but restoring a query is not a `change`, so the re-entered fzf
    # would sit there showing 0/0 under a query that plainly has hits until you
    # touched a key. Running the search once at start is what makes ^s read as a
    # toggle rather than a reset.
    #
    # ── the chrome ──────────────────────────────────────────────────────────
    # ONE border, ours, drawn by fzf — the window has none of its own
    # (macos-titlebar-style = hidden). Everything the eye doesn't need is off:
    #
    #   - The only title is the border's top-LEFT label, `find · this window`.
    #     It used to be centred while zellij's floating-pane frame said "find" in
    #     its own corner, so the word appeared twice; now the scope rides along
    #     with it in the one place a title belongs.
    #   - No --header. It sat above the list, so it was clipped to the list's
    #     width and the last hints were simply never readable. The same keys
    #     live in --footer, which is drawn against the bottom of the overlay and
    #     is short enough to survive a narrow window.
    #   - `2>/dev/null` on BOTH helper binds. rg is Rust, and Rust ignores
    #     SIGPIPE — so when fzf tears down an in-flight reload (every keystroke
    #     does), it hits EPIPE and aborts with a "fatal runtime error: assertion
    #     failed: output.write(...)" on stderr. fzf doesn't own stderr, so that
    #     lands on the PANE, over the overlay. Seen for real on the ^s toggle,
    #     where the message survived the redraw. The preview bind is awk now and
    #     dies quietly, but it keeps the redirect — the next tool put behind it
    #     shouldn't have to rediscover this.
    #   - `--gutter=' '`. fzf ≥0.53 paints a ▌ rail down the left of EVERY row,
    #     which read as a second pointer under the real one. It is a CHARACTER
    #     option, not a colour one — `--color=gutter:…` only restyles it, so
    #     blanking the glyph is the only way off. The current row is already
    #     marked twice over (--pointer plus --highlight-line's bg+).
    #   - COLOURS ARE ANSI INDICES, NOT HEX, on purpose: 0-15 resolve against
    #     the terminal's own palette, which ghostty themes from nebelung. So the
    #     overlay follows a flavour change for free, and no colour literal has to
    #     be smuggled into haus (they belong in the nebelung repo). 8 is the
    #     grey the border/footer want; 5 is the mauve accent.
    #   - `${scoped_label}…`, braced. Ghostty execs this command directly rather
    #     than through a login shell, so LANG can be unset — and in the C locale
    #     bash reads the following ellipsis's UTF-8 bytes as MORE variable name
    #     and then dies under `set -u` on a name that doesn't exist. Brace every
    #     expansion here that a non-ASCII character follows.
    #
    # Nothing here relies on FZF_DEFAULT_OPTS either, for that same reason:
    # home-manager's fzf colours live in the shell environment this pane never
    # had. Every colour that matters is passed explicitly.
    # 60/40, in the LIST's favour — not the even split it looks like it wants.
    #
    # The two halves are not doing the same job. The preview is read one line at
    # a time, so what it needs is enough column to be prose (~60 chars is a book);
    # past that, extra width is spent on the ragged right of a paragraph. The
    # list is SCANNED, and a scan fails in a specific way: 26 hits from the same
    # shell pane all render `Shell cwd was reset to /Users/julienmartel/.cache/cl…`
    # because the cut lands just BEFORE the part that tells them apart. Width
    # there buys distinguishability, which is the whole job of that column, and
    # it went further once the pane/line-number columns came off the row.
    #
    # No `<SIZE(ALTERNATIVE_LAYOUT)` clause here, and don't add one hoping to
    # stack the preview under the list on a narrow window: fzf compares that
    # threshold against the terminal's HEIGHT even when the preview is on the
    # `right`. Measured — at 145x14, `<13` keeps it beside and `<100` moves it
    # below, i.e. it tracked the 14, not the 145. So the clause says "stack when
    # SHORT", which is precisely backwards (stacking is what a short terminal
    # can least afford), and there is no width-keyed form to say the real thing.
    local preview_win='right,40%,border-left'

    local out query key sel id line
    local fzf_color='fg:-1,bg:-1,fg+:-1,bg+:8,gutter:-1,border:8,label:5'
    fzf_color="$fzf_color,preview-border:8,prompt:5,pointer:5,query:-1"
    fzf_color="$fzf_color,info:8,spinner:5,footer:8,scrollbar:8"

    while :; do
        local scoped_label="this window" other="session"
        [ "$scope" = "session" ] && scoped_label="every window" other="pane"

        out=$(fzf \
            --ansi --disabled --no-sort --layout=reverse \
            --info=inline-right --highlight-line \
            --border=rounded --border-label="  find · $scoped_label " \
            --border-label-pos=3 \
            --color="$fzf_color" \
            --prompt='  ' --pointer='▍' --marker='▍' --gutter=' ' \
            --ghost="search ${scoped_label}…" \
            --query="${query:-}" \
            --delimiter='\t' --with-nth=3 \
            --preview="$SELF _preview $dir {1} {2} 2>/dev/null" \
            --preview-window="$preview_win" \
            --bind="change:reload:$SELF _rg $dir $scope {q} 2>/dev/null" \
            --bind="start:reload:$SELF _rg $dir $scope {q} 2>/dev/null" \
            --footer="⏎ focus · ^y copy · ^s $other · esc" --footer-border=none \
            --print-query --expect=ctrl-y,ctrl-s </dev/null)

        query=$(sed -n 1p <<<"$out")
        key=$(sed -n 2p <<<"$out")
        sel=$(sed -n 3p <<<"$out")

        [ "$key" = "ctrl-s" ] || break
        scope="$other"
        # Resize to match the new scope, same rule the entry path applies:
        # this window's scrollback gets this window's frame, every session gets
        # the whole tiled desktop. Growing is computed fresh; shrinking replays
        # the frame cmd_launch stashed, since the summoner is no longer
        # frontmost. Best-effort — a failed re-plant leaves a correct search in
        # a wrongly-sized window, which is the pre-2026-08-20 behaviour.
        replant "$dir" "$scope"
    done

    [ -n "$sel" ] || exit 0
    id=$(cut -f1 <<<"$sel")
    # Field 4 — the uncoloured, unpadded copy. Field 3 carries escape codes and
    # (in `every window` scope) a label column, neither of which belongs on a
    # clipboard. See the field map above cmd_rg.
    line=$(cut -f4- <<<"$sel")

    # The matched line goes to the clipboard on BOTH exits. ^y is the explicit
    # "I only wanted the text" key; on ⏎ it's a free consolation prize if the
    # focus call below turns out to be a no-op (see next comment).
    printf '%s' "$line" | pbcopy
    [ "$key" = "ctrl-y" ] && exit 0

    # ⏎ — go to the window the hit came from. scripts/raise-session.sh owns the
    # joins (and knows whether this machine has a tiler); the bar's popup calls
    # exactly the same script for exactly the same reason. A detached session
    # raises nothing, and there is deliberately no branch reopening a window for
    # it — you asked to go to a hit, not to resurrect a terminal. The line is on
    # the clipboard either way, which is the floor this key has always had.
    if [ -n "$id" ]; then
        "$HOME/.config/haus/term/raise-session.sh" "$id" >/dev/null 2>&1
    fi
    exit 0
}

# ── fzf helpers ─────────────────────────────────────────────────────────────
# Emit four tab-separated fields, of which fzf DISPLAYS exactly one:
#
#   1 session    the ⏎ action's target, and the corpus filename
#   2 line no    where the preview scrolls to. Deliberately NOT on the row: it
#                indexes a rendered transcript, so it means nothing anywhere
#                outside this overlay, and it cost a column on all 2000 rows.
#   3 display    what the row shows (--with-nth=3, so ONLY this).
#   4 raw text   the same line, unpadded and uncoloured — what ⏎/^y put on the
#                clipboard. It has to come AFTER the display field, since
#                --with-nth can only take a single field or a contiguous tail.
#
# The label column is drawn in `every window` scope only. In `this window` scope
# it would be the same string on every row (see the labeller in build_corpus).
#
# rg colours the MATCH itself (--color=always) rather than fzf doing it: fzf is
# --disabled here, so it matches nothing and therefore highlights nothing, and
# without this you cannot see WHICH part of a long line you hit.
#
# That forces the prefix parsing to change. `--colors path:none` does NOT mean
# "emit no escapes for the path" — rg still wraps every field in a reset, so
# `rg:12.txt<esc>[0m:<esc>[0m3<esc>[0m:` no longer matches a `^[^:]*:[0-9]+:`
# strip, and the whole line came through as one uncut blob with the id parsed as
# "12.txt<esc>[0m". So: --field-match-separator makes the two prefix fields
# splittable on a byte that cannot occur in the text (\x01), and the escapes are
# scrubbed from those two fields only — the text keeps its match colours.
cmd_rg() {
    local dir="$1" scope="$2" q="${3:-}"
    [ -n "$q" ] || exit 0

    local root="$dir/src" target
    if [ "$scope" = "pane" ]; then
        target=$(cat "$dir/target" 2>/dev/null)
        [ -n "$target" ] && root="$dir/src/$target.txt"
    fi
    [ -e "$root" ] || exit 0

    local wide=0
    [ "$scope" = "session" ] && wide=1

    # $'\001' both sides: macOS's awk is BWK awk, which does NOT understand \x
    # escapes — `-F'\x01'` silently becomes the three-character FS "x01" and
    # every line collapses into one field. Octal is the portable spelling.
    rg --line-number --no-heading --with-filename --color=always \
        --field-match-separator=$'\001' \
        --colors 'match:none' --colors 'match:fg:magenta' \
        --colors 'match:style:bold' \
        --smart-case --max-columns=400 --max-columns-preview \
        -e "$q" "$root" 2>/dev/null |
        awk -F'\001' -v panes="$dir/panes.tsv" -v wide="$wide" '
            BEGIN {
                esc = sprintf("%c", 27) "\\[[0-9;]*m"
                while ((getline l < panes) > 0) {
                    split(l, f, "\t"); label[f[1]] = f[2]; kind[f[1]] = f[3]
                }
            }
            {
                path = $1; lineno = $2
                gsub(esc, "", path); gsub(esc, "", lineno)
                if (lineno !~ /^[0-9]+$/) next

                # $3.. rather than $3: a \x01 in the corpus is vanishingly
                # unlikely, but rejoining is free and losing the tail is not.
                text = $3
                for (i = 4; i <= NF; i++) text = text FS $i
                # A tab would open a field of its own downstream and shove the
                # clipboard column into the visible one.
                gsub(/\t/, "    ", text)
                raw = text
                gsub(esc, "", raw)

                n = split(path, p, "/"); id = p[n]; sub(/\.txt$/, "", id)
                tag = label[id]; if (tag == "") tag = "pane " id
                # %-14s pads without truncating: awk counts BYTES, so cutting
                # here could slice a multi-byte tab name in half.
                disp = (wide ? sprintf("%c[2m%-14s%c[0m %s", 27, tag, 27, text) : text)
                printf "%s\t%s\t%s\t%s\n", id, lineno, disp, raw
            }' |
        head -2000
}

# The context window around a hit, with the hit line the ONLY one at full
# strength and everything around it dimmed.
#
# That inversion is why bat isn't here any more. bat can mark a line exactly one
# way — `--highlight-line` paints a background BAR across it — which is the loud
# half of the pair: a slab of colour on the line you're reading, and the twelve
# lines of context beside it rendered exactly as bright. Reading position should
# come from the context RECEDING, not from the answer being boxed. bat has no
# "dim everything except" mode, and its number gutter indexed a rendered
# transcript anyway — offsets into nothing you could open.
#
# So: SGR 2 (dim) on the context, nothing at all on the hit line. Dim is a
# relative attribute, not a colour, so it fades whatever the terminal's
# foreground already is and follows a nebelung flavour change for free — the
# same reason the pane column in cmd_rg uses it. Cheaper than bat, too, and it
# drops the last user of it from this script.
#
# No wrapping, deliberately: every corpus line is exactly one row, so the hit
# always lands mid-window at a predictable spot instead of being pushed off the
# bottom by a long paragraph above it. (bat didn't wrap here either — fzf hands
# the preview command a pipe, so bat's `--wrap=auto` resolved to no width and
# truncated. This keeps that, on purpose rather than by accident.)
cmd_preview() {
    local dir="$1" id="${2:-}" lineno="${3:-}"
    local file="$dir/src/$id.txt"
    [ -f "$file" ] && [ -n "$lineno" ] || exit 0
    local from=$((lineno - 12))
    [ "$from" -lt 1 ] && from=1

    # Escapes are stripped from the corpus FIRST, and that is load-bearing, not
    # tidiness. The corpus is not guaranteed plain: render_transcript pulls
    # string leaves out of tool_result content, and a Bash tool result routinely
    # carries colour — including its own \033[0m. Wrapping such a line in
    # `\033[2m … \033[0m` dims only up to the FIRST embedded reset, after which
    # the rest of that context line renders at full strength: exactly the signal
    # this design reserves for the hit line, on a row that isn't it. bat's
    # background bar couldn't be broken this way; a relative attribute can.
    #
    # %c/27 rather than a \033 literal: BWK awk (macOS) is the floor here.
    awk -v from="$from" -v to="$((lineno + 12))" -v hit="$lineno" '
        BEGIN { esc = sprintf("%c", 27) "\\[[0-9;]*m" }
        NR < from { next }
        NR > to { exit }
        { gsub(esc, ""); gsub(/\t/, "    ")
          if (NR == hit) print; else printf "%c[2m%s%c[0m\n", 27, $0, 27 }
    ' "$file"
}

case "${1:-}" in
    launch) shift; cmd_launch "$@" ;;
    ui) shift; cmd_ui "$@" ;;
    _rg) shift; cmd_rg "$@" ;;
    _preview) shift; cmd_preview "$@" ;;
    *) printf 'usage: find.sh launch [pane|session]\n' >&2; exit 2 ;;
esac
