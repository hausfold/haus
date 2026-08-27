#!/bin/bash
# lane-cwd.sh — "which directory should a chord pressed here work in?"
#
# The shared half of every window-layer chord. A zellij bind inherited the
# focused pane's directory for free; a chord bound outside the terminal (⌘↵'s
# lane-spawn.sh, ⌘N/⌘⇧N's shell-here, ⌘Y's peek, ⌘B) has no directory at
# all, so it has to ask.
#
# Usage: lane-cwd.sh [--page]
#
# The answer is one hop past scripts/focused-session.sh, which does the hard
# half — window → zmx session, by window id (the `lwindow=` label for a lane,
# `window=` for everything else) and only then by a lane's forced title.
# `zmx ls` then reports that session's directory.
#
# A window with no session — a browser, Finder, the quick terminal — prints
# NOTHING; the caller picks its own fallback, because "from anywhere" beats a
# refusal and what "anywhere" should mean differs per chord.
#
# ── --page: the PAGE you are standing on outranks the window ─────────────────
# WITHOUT the flag this is exactly "the focused window's directory", which is
# what ⌘Y's peek and ⌘B's lane build want: both act ON that window.
#
# WITH it, the focused WORKSPACE gets the last word about which REPO the answer
# belongs to. A page is `<base>/<repo>` (lanes/lane-open.sh tiles every lane of
# one repo onto `T/<repo>`), so standing on one is an unambiguous statement of
# which repo you are working in — and the two chords that CREATE something new
# in a repo, ⌘↵'s lane and ⌘N's shell window, should obey it. The window under
# the keystroke is a weaker signal than it looks: a plain shell dragged onto a
# page, a session whose live cwd could not be read and fell back to where it was
# BORN, or focus that has not caught up with a page you just walked to, all
# answer with some other repo entirely — and then ⌘↵ opens a lane in it.
#
# It is a CORRECTION, not a replacement: the window's own directory is kept
# whenever it already belongs to the page's repo, so ⌘N in a subdirectory still
# opens there and ⌘↵ inside a lane's worktree still spawns a sibling lane. Only
# a directory whose repo DISAGREES with the page is overridden, and then with
# that repo's main checkout — holt's own `main` for the lanes it knows about,
# which is where the page's name came from in the first place (lane-open.sh
# names it `basename $HOLT_MAIN`).
#
# With no page under you, no holt registry, or no repo answer either side, this
# flag changes nothing at all.
#
# stdout: the directory, or empty. Exit 0 either way.
set -u

export PATH="/etc/profiles/per-user/${USER:-$(id -un)}/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin${PATH:+:$PATH}"

want_page=0
[ "${1:-}" = "--page" ] && want_page=1

# ── which repo does a directory belong to ────────────────────────────────────
# The MAIN checkout's basename, which is exactly the string a page is named
# after: lanes/lane-open.sh builds `T/<repo>` from `basename $HOLT_MAIN`. So
# this is the same question asked from the other end, and the two answers are
# comparable by string equality.
#
# `--git-common-dir` rather than `--show-toplevel`, because a lane IS a worktree
# and its toplevel is the worktree — the common dir is the one thing every
# worktree of a repo shares. It comes back relative to the cwd when you are
# standing in the toplevel (a bare `.git`), so it is resolved by cd'ing into it
# rather than by string-joining.
repo_of() {
  local d="$1" common
  [ -n "$d" ] && [ -d "$d" ] || return 0
  common="$(git -C "$d" rev-parse --git-common-dir 2>/dev/null)" || return 0
  [ -n "$common" ] || return 0
  case "$common" in
    /*) ;;
    *) common="$(cd "$d" && cd "$common" 2>/dev/null && pwd)" || return 0 ;;
  esac
  basename "$(dirname "$common")"
}

# ── the page under you, as a repo name ───────────────────────────────────────
# `list-workspaces --focused`, NOT the focused window's workspace: the page you
# are LOOKING at is the question, and the two differ exactly in the case this
# whole flag exists for — focus lagging a page walk.
page_repo=""
if [ "$want_page" = 1 ] && command -v aerospace >/dev/null 2>&1; then
  ws="$(aerospace list-workspaces --focused 2>/dev/null)"
  case "$ws" in
    */*) page_repo="${ws##*/}" ;;
  esac
fi

# ── that repo name, as a directory ───────────────────────────────────────────
# holt's registry is the only thing on the machine that knows where a repo named
# `<repo>` actually lives, and `main` is the field the page name was derived
# from. Read through holt-cache (modules/ai) rather than `holt --json`, whose
# lsof sweep costs seconds — and with a WEEK of slack, because the one field
# read here is a path that does not move while a lane's state does. A cold cache
# gets one bounded foreground sync; anything longer belongs nowhere near a
# keystroke, and no answer simply means no correction.
page_dir=""
if [ -n "$page_repo" ] && command -v jq >/dev/null 2>&1 && command -v holt-cache >/dev/null 2>&1; then
  json="$(holt-cache read 604800 2>/dev/null)"
  [ -n "$json" ] || json="$(holt-cache sync 2 2>/dev/null)"
  if [ -n "$json" ]; then
    page_dir="$(
      printf '%s' "$json" |
        jq -r --arg repo "$page_repo" '
          [ (.lanes // [])[] | .main // empty | select((. | split("/") | last) == $repo) ][0] // ""
        ' 2>/dev/null
    )"
  fi
  [ -n "$page_dir" ] && [ -d "$page_dir" ] || page_dir=""
fi

# What the caller gets when the window has nothing to say — empty without
# --page, and the page's repo with it.
give_up() {
  [ -n "$page_dir" ] && printf '%s\n' "$page_dir"
  exit 0
}

command -v zmx >/dev/null 2>&1 || give_up

sess="$("$HOME/.config/haus/term/focused-session.sh" 2>/dev/null)"
[ -n "$sess" ] || give_up

# `zmx ls` is tab-separated k=v. The first two traps below are every copy of
# this parse's to handle (scripts/focused-session.sh, scripts/find.sh,
# scripts/launch.sh, the bar's agents.sh, the palette's lanes.sh); the third
# binds only a reader that wants a LIVE directory, which today is this file
# alone — find.sh's opencode lookup reads the same stale field and is content
# to, because it falls back to a label join.
#
#   · The directory field is `start_dir` in zmx 0.7.0; older zmx called it `cwd`
#     and wrapped it in a file:// URL with the host in it. Both spellings are
#     accepted and the URL prefix is stripped when present. Reading only `cwd`
#     is what silently broke ⌘↵ once: no directory came back, the chord fell
#     through to $HOME, and $HOME isn't a git repo.
#   · zmx marks rows in the FIRST field ("→ ** name=…" for the session you are
#     attached to), so that row's first key arrives with the marker glued to it.
#     Strip everything before the key proper, or the session you pressed the
#     chord IN is the one row that fails to resolve.
#   · **`start_dir` is where the session was BORN, not where it is now.** It is
#     stamped once at `zmx attach` and never moves again, so a window opened in
#     $HOME still reports $HOME after you `cd` into a repo — which is the whole
#     of "⌘↵ says ~ isn't a git repo" while you are plainly standing in one.
#     zmx has no live-cwd field to ask for (0.7.0's `ls` emits exactly
#     name/pid/clients/created/start_dir/window), so the live answer has to come
#     from the kernel: `pid` is the session's own login shell, and a shell's cwd
#     IS the thing that tracks `cd`. That makes start_dir the FALLBACK — right
#     for a session whose shell has died or that we can't read — and the pid's
#     real cwd the answer.
row="$(
  zmx ls 2>/dev/null | awk -F'\t' -v want="$sess" '
    {
      name = ""; c = ""; pid = ""
      for (i = 1; i <= NF; i++) {
        eq = index($i, "=")
        if (eq == 0) continue
        k = substr($i, 1, eq - 1); gsub(/^[ \t]+|[ \t]+$/, "", k)
        sub(/^[^A-Za-z_]*/, "", k)
        if (k == "name") name = substr($i, eq + 1)
        else if (k == "pid") pid = substr($i, eq + 1)
        else if (k == "start_dir") c = substr($i, eq + 1)
        else if (k == "cwd" && c == "") c = substr($i, eq + 1)
      }
      if (name == want && (c != "" || pid != "")) {
        sub(/^file:\/\/[^\/]*/, "", c)
        print pid "\t" c
        exit
      }
    }
  '
)"

pid="${row%%$'\t'*}"
cwd="${row#*$'\t'}"

# macOS has no /proc, so a process's cwd is lsof's to give — one pid, one fd,
# ~30 ms, paid only when a chord is pressed rather than on every `cd`. It lives
# in /usr/sbin, which is why the PATH prelude above carries that dir.
if [ -n "$pid" ]; then
  live="$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)"
  [ -n "$live" ] && [ -d "$live" ] && cwd="$live"
fi

[ -n "$cwd" ] && [ -d "$cwd" ] || give_up

# ── the correction ───────────────────────────────────────────────────────────
# Only when the page names a repo we could place AND the window's directory
# belongs to a different one. A window in no repo at all counts as different:
# standing on `T/<repo>` with a shell in $HOME, the page is the only thing in
# the room that knows what you meant.
if [ -n "$page_dir" ]; then
  cwd_repo="$(repo_of "$cwd")"
  [ "$cwd_repo" = "$page_repo" ] || cwd="$page_dir"
fi

printf '%s\n' "$cwd"
exit 0
