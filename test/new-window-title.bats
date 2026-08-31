#!/usr/bin/env bats
# Hermetic tests for the half of modules/terminal/scripts/new-window.sh that
# decides whether the Apple Event may be used at all.
#
# ── the bug this suite pins ──────────────────────────────────────────────────
# `tell application "Ghostty"` is addressed by BUNDLE ID, and this desktop runs
# several Ghostty processes at once: every agent lane is one of its own
# (lanes/lane-open.sh) and so is every float popup (scripts/float-term.sh),
# each launched `--title=<name>`. Ghostty's `title` is INSTANCE-WIDE
# configuration — "if it is set, the title will update for all windows", its own
# docs — so a window opened by Apple Event into a lane's process is BORN wearing
# `scruff.<repo>.<lane>` and can never take the name back, a forced title being
# precisely one that ignores the OSC 2 the shell inside would send. ⌘T, ⌘N and
# ⌘⇧N all handed out windows named after the lane they were pressed in.
#
# Neither half is observable by eye from inside the script — a mistitled window
# opens perfectly, and the only symptom is a name — so both are tested here:
#
#   * the SET of forced titles is read off `ps`, not matched as a pattern, so
#     nothing has to know a lane is spelled `scruff.*` (scruff's prefix to
#     change, not ours). The traps are a `--title=` inside an
#     `--initial-command=` payload, a plain instance with no `--title` at all,
#     and a non-Ghostty process whose argv carries the flag.
#   * the REFUSAL comes before the spawn in the generated AppleScript. Reversed,
#     the window opens and then has to be closed again, which is a flash rather
#     than a fix.
#
# ⚠️ Both subjects are extracted by `sed`: new-window.sh cannot be sourced — it
# is a top-to-bottom script that opens a window. So `osa_str() {` and its
# closing `}`, the `forced=""` opening with its `FORCED` heredoc terminator, and
# the `verdict="$(osascript` opening with its closing `)"` must all keep column
# 1. If any moves, the eval yields nothing and every case fails on an empty
# result — the loud failure, and the reason this is acceptable.

bats_require_minimum_version 1.5.0

SUBJECT() { printf '%s' "$BATS_TEST_DIRNAME/../modules/terminal/scripts/new-window.sh"; }

setup() {
  STUB="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUB"

  # osascript never runs here — the stub prints the script it was handed, which
  # is the only thing these cases are about.
  cat >"$STUB/osascript" <<'OSA'
#!/usr/bin/env bash
cat
OSA
  chmod +x "$STUB/osascript"
}

# `ps -axww -o command=` for a given desk. Verbatim in the format the real tool
# emits — one command line per process, no header — because a stub that
# paraphrases its subject is how a suite starts passing for the wrong reason.
forced_for() { # PS-OUTPUT
  printf '%s' "$1" >"$BATS_TEST_TMPDIR/ps"
  cat >"$STUB/ps" <<EOF
#!/usr/bin/env bash
cat "$BATS_TEST_TMPDIR/ps"
EOF
  chmod +x "$STUB/ps"
  PATH="$STUB:$PATH" eval "$(sed -n '/^osa_str() {/,/^}/p' "$(SUBJECT)")
$(sed -n '/^forced=""/,/^FORCED$/p' "$(SUBJECT)")"
  printf '%s' "$forced"
}

# The AppleScript the script would send, given a set of forced titles.
applescript_for() { # FORCED-LIST
  forced="$1"
  cwd=/Users/me
  cmd="'/Users/me/.config/haus/term/launch.sh' "
  env_list=', environment variables:{"HAUS_STAY=1"}'
  PATH="$STUB:$PATH" eval "$(sed -n '/^osa_str() {/,/^}/p' "$(SUBJECT)")
$(sed -n '/^verdict="\$(osascript/,/^)"$/p' "$(SUBJECT)")"
  printf '%s' "$verdict"
}

# ── the whole script, end to end ─────────────────────────────────────────────
# The cases above pin the two pieces; these pin the WIRING, which is the half
# that can be inverted without any of them noticing — a `verdict` compared the
# wrong way opens no window at all and still generates a perfect AppleScript.
#
# ⚠️ The subject is COPIED with two things rewritten, because neither can be
# reached from PATH:
#
#   `^export PATH=`  the prelude puts `/usr/bin:/bin` ahead of anything a test
#                    can prepend, and `osascript`, `open`, `ps` and `pgrep` all
#                    live there. If that line ever stops starting the way it
#                    does, the copy runs against the REAL tools and opens
#                    windows — which is why the sed is anchored.
#   the absolute     the failure banner is addressed
#   `haus-notify`    `/run/current-system/sw/bin/haus-notify` on purpose (launchd
#                    PATHs name nothing of ours). Left alone, running this suite
#                    on a real Mac puts a banner on someone's screen.
#
# Both rewrites are anchored on text the subject must keep; a miss shows up as a
# case that opens something rather than one that quietly passes.
spawn() { # OSASCRIPT-REPLY PS-OUTPUT ARGS…
  local reply="$1" desk="$2"
  shift 2
  local dir="$BATS_TEST_TMPDIR/e2e"
  rm -rf "$dir"
  mkdir -p "$dir/bin"
  sed -e 's|^export PATH=.*|export PATH="$PATH"|' \
      -e 's|/run/current-system/sw/bin/haus-notify|haus-notify|' \
      "$(SUBJECT)" >"$dir/new-window.sh"
  grep -q '^export PATH="\$PATH"$' "$dir/new-window.sh"
  ! grep -q '/run/current-system/sw/bin' "$dir/new-window.sh"
  chmod +x "$dir/new-window.sh"

  printf '%s\n' "$desk" >"$dir/ps.txt"
  cat >"$dir/bin/ps" <<EOF
#!/usr/bin/env bash
cat "$dir/ps.txt"
EOF
  # Ghostty is already running, so the cold-start branch stays out of the way.
  printf '#!/usr/bin/env bash\nexit 0\n' >"$dir/bin/pgrep"
  cat >"$dir/bin/osascript" <<EOF
#!/usr/bin/env bash
cat >/dev/null
printf '%s' "$reply"
EOF
  # A window id that CHANGES on the second call, so the tile poll resolves at
  # once instead of spending its full second timing out.
  cat >"$dir/bin/aerospace" <<EOF
#!/usr/bin/env bash
printf 'aerospace %s\n' "\$*" >>"$dir/calls"
case "\$*" in
  *list-windows*--focused*)
    if [ -e "$dir/seen" ]; then printf '200\n'; else : >"$dir/seen"; printf '100\n'; fi
    ;;
esac
EOF
  for stub in open haus-notify; do
    cat >"$dir/bin/$stub" <<EOF
#!/usr/bin/env bash
printf '$stub %s\n' "\$*" >>"$dir/calls"
exit "\${${stub%%-*}_RC:-0}"
EOF
  done
  chmod +x "$dir"/bin/*
  : >"$dir/calls"
  local rc=0
  PATH="$dir/bin:$PATH" "$dir/new-window.sh" "$@" || rc=$?
  cat "$dir/calls"
  # The subject's status, not `cat`'s — without this every case is a `run -0`
  # that passes on any exit code at all.
  return "$rc"
}

@test "a refused spawn falls through to a fresh instance with no --title" {
  run -0 spawn forced '/Applications/Ghostty.app/Contents/MacOS/ghostty --title=scruff.haus.lane' \
    --cwd / --no-tile -- /bin/zsh
  [[ "$output" == *"open -na Ghostty --args --working-directory=/ --initial-command="* ]]
  [[ "$output" != *"--title"* ]]
}

@test "an accepted spawn opens nothing a second time" {
  run -0 spawn ok '/Applications/Ghostty.app/Contents/MacOS/ghostty' --cwd / --no-tile -- /bin/zsh
  [[ "$output" != *"open "* ]]
}

@test "an env rides the fallback as an env prefix, since open has no flag for it" {
  run -0 spawn forced '/Applications/Ghostty.app/Contents/MacOS/ghostty --title=scruff.haus.lane' \
    --cwd / --no-tile --env HAUS_STAY=1 -- /bin/zsh
  [[ "$output" == *"--initial-command=/usr/bin/env 'HAUS_STAY=1' '/bin/zsh'"* ]]
}

@test "--no-tile leaves the window floating, and without it the window is tiled" {
  run -0 spawn ok '/Applications/Ghostty.app/Contents/MacOS/ghostty' --cwd / --no-tile -- /bin/zsh
  [[ "$output" != *"aerospace layout"* ]]

  run -0 spawn ok '/Applications/Ghostty.app/Contents/MacOS/ghostty' --cwd / -- /bin/zsh
  [[ "$output" == *"aerospace layout --window-id 200 tiling"* ]]
}

# Failing silently is the one sin a chord can't afford, and the refusal added a
# second way to reach this: a machine where the Apple Event is refused AND the
# launch fails now ends here rather than at an osascript error.
@test "both spawns gone is the one failure that says so on screen" {
  # exported, not a `run` prefix: the stub is another process, and a plain shell
  # variable never reaches it.
  export open_RC=1
  run -1 spawn forced '/Applications/Ghostty.app/Contents/MacOS/ghostty --title=scruff.haus.lane' \
    --cwd / --no-tile -- /bin/zsh
  [[ "$output" == *"open -na"* ]]
  [[ "$output" == *"haus-notify"*"is Ghostty installed?"* ]]
}

# The desk the bug was found on: three lanes and a float popup, each its own
# process with its own forced title, and NO plain instance anywhere — which is
# why every ⌘T that day landed in a lane. The `zmx attach` rows are the real
# ones that sit beside each Ghostty.
BUSY_DESK='/Applications/Ghostty.app/Contents/MacOS/ghostty --title=scruff.haus.shell-window-titles --initial-command=/tmp/lane.sh
/Applications/Ghostty.app/Contents/MacOS/ghostty --title=scruff.workshop.test-producer-desktop --initial-command=/tmp/lane.sh
/Applications/Ghostty.app/Contents/MacOS/ghostty --title=scruff.haus.remove-iina-integration --initial-command=/tmp/lane.sh
/Applications/Ghostty.app/Contents/MacOS/ghostty --title=quick-terminal-peek --initial-command=/tmp/peek.sh
zmx attach scruff.haus.shell-window-titles bash -lc claude
/usr/bin/some-daemon --title=not-a-terminal'

@test "every forced title on the desk, quoted and sorted" {
  run -0 forced_for "$BUSY_DESK"
  [ "$output" = '"quick-terminal-peek", "scruff.haus.remove-iina-integration", "scruff.haus.shell-window-titles", "scruff.workshop.test-producer-desktop"' ]
}

@test "a process that is not Ghostty never contributes a title" {
  run -0 forced_for 'zmx attach x --title=stolen
/usr/bin/some-daemon --title=not-a-terminal'
  [ "$output" = "" ]
}

@test "a plain instance contributes nothing, so the fast path survives" {
  run -0 forced_for '/Applications/Ghostty.app/Contents/MacOS/ghostty'
  [ "$output" = "" ]
}

# The payload of --initial-command is an arbitrary script — a lane's is a whole
# agent prompt — so it can contain the flag's own spelling. Ghostty's real
# --title is always written first by this room's spawns, and taking the first is
# what makes that reliable.
@test "a --title inside the initial-command payload does not win" {
  run -0 forced_for '/Applications/Ghostty.app/Contents/MacOS/ghostty --title=scruff.haus.lane --initial-command=echo --title=decoy'
  [ "$output" = '"scruff.haus.lane"' ]
}

@test "one instance listed twice yields one entry" {
  run -0 forced_for '/Applications/Ghostty.app/Contents/MacOS/ghostty --title=scruff.haus.lane
/Applications/Ghostty.app/Contents/MacOS/ghostty --title=scruff.haus.lane'
  [ "$output" = '"scruff.haus.lane"' ]
}

@test "the refusal is asked BEFORE the window is created" {
  run -0 applescript_for '"scruff.haus.lane"'
  [[ "$output" == *'if t is in {"scruff.haus.lane"} then return "forced"'* ]]
  guard=$(printf '%s\n' "$output" | grep -n 'return "forced"' | cut -d: -f1)
  spawn=$(printf '%s\n' "$output" | grep -n 'new window with configuration' | cut -d: -f1)
  [ "$guard" -lt "$spawn" ]
}

# A machine with no lane and no popup is the common case, and an empty
# AppleScript list is legal — `is in {}` is false, so it takes the fast path
# with no branch in the shell.
@test "an empty desk still produces a legal script" {
  run -0 applescript_for ''
  [[ "$output" == *'if t is in {} then return "forced"'* ]]
  [[ "$output" == *'new window with configuration'* ]]
}

@test "the front window is read defensively, since an instance may have none" {
  run -0 applescript_for ''
  [[ "$output" == *'try'*'set t to name of front window'*'end try'* ]]
}
