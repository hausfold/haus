#!/usr/bin/env bats
# Hermetic tests for modules/ai/desktop-guard.sh — the PreToolUse hook that
# re-opens the permission prompt before a tool call that would move the pointer,
# take focus or redraw the desktop.
#
# Why a suite. The guard's whole value is the line it draws, and BOTH sides of
# that line fail silently. Too loud and it trains click-through, which is worse
# than no guard at all — that is exactly what a lane's headless VM used to hit,
# where `ssh admin@<guest> 'haus rebuild'` prompted for something the user
# cannot see. Too quiet and the first anyone knows is a window jumping in front
# of them mid-sentence. Neither shows up in a build, a lint or a rebuild.
#
# The subject is a pure function — hook JSON in, verdict JSON out — so every
# case here is one string, and the suite needs no Mac, no VM and no ssh.
#
# HAUS_DESKTOP_OK is unset per test on purpose: it is the whole-guard escape
# hatch, and a pane that has it exported would otherwise pass this suite by
# doing nothing at all.

bats_require_minimum_version 1.5.0

setup() {
  GUARD="${DESKTOP_GUARD_UNDER_TEST:-$BATS_TEST_DIRNAME/../modules/ai/desktop-guard.sh}"
  unset HAUS_DESKTOP_OK
}

# verdict <json> → the reason string, or "" for "no opinion" (silence)
verdict() {
  printf '%s' "$1" | bash "$GUARD" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty'
}

# The command goes in through jq's STDIN, never `--arg`: one case here is a
# 200 KB command (the size cap), and Linux caps a single argv element at 128 KB
# — `jq: Argument list too long`, which fails as an empty verdict and therefore
# reads as "the guard stayed silent". macOS has no such cap, so this is a trap
# that only springs in CI. `-Rs` takes the whole of stdin as one raw string,
# newlines and all, and `printf` is a builtin, so nothing crosses an exec.
bash_json() { printf '%s' "$1" | jq -Rs '{tool_name: "Bash", tool_input: {command: .}}'; }

# asks <command> / silent <command> — the two assertions this file is made of.
asks() {
  local r
  r="$(verdict "$(bash_json "$1")")"
  [ -n "$r" ] || { printf 'expected a prompt, got silence: %s\n' "$1" >&2; return 1; }
}
silent() {
  local r
  r="$(verdict "$(bash_json "$1")")"
  [ -z "$r" ] || { printf 'expected silence, got a prompt: %s\n  → %s\n' "$1" "$r" >&2; return 1; }
}

# ---- the host's own screen: unchanged ---------------------------------------

@test "foregrounding, focus and redraw on this Mac still ask" {
  asks 'open -a Ghostty'
  asks 'osascript -e "tell application \"Ghostty\" to activate"'
  asks 'aerospace focus left'
  asks 'killall Dock'
  asks 'sketchybar --reload ~/.config/sketchybar/sketchybarrc'
  asks 'launchctl kickstart -k gui/501/org.nixos.pounce'
  asks 'screencapture /tmp/shot.png'
  asks 'haus rebuild'
}

@test "the backgrounded and silent forms stay silent" {
  # `-g` is silent because it takes no FOCUS, which is all this guard polices.
  # It is not an endorsement: a backgrounded app need not open a window at all
  # (Ghostty, measured 2026-08-23, opens none), which is why the guard's own
  # message and modules/ai's instructions both say what `-g` is and is not for.
  silent 'open -g -a Ghostty'
  silent 'screencapture -x /tmp/shot.png'
  silent 'git commit -m "open the door, killall the noise"'
}

@test "an indented line is still a command boundary" {
  # Anchors are `^`-based and grep is line-based, so a heredoc body or a
  # continued script indents its way out of the guard unless ` *` follows `^`.
  asks 'cd /tmp
  killall Dock'
}

# ---- another machine's screen -----------------------------------------------

@test "a lane's VM over ssh is not this screen" {
  silent 'ssh admin@192.168.64.5 "haus rebuild"'
  silent 'ssh admin@192.168.64.5 "sudo darwin-rebuild switch --flake /Volumes/work#vm"'
  silent 'ssh admin@192.168.64.5 "sketchybar --reload ~/.config/sketchybar/sketchybarrc"'
  silent 'ssh admin@192.168.64.5 "launchctl kickstart -k gui/501/org.nixos.pounce"'
  silent 'ssh admin@192.168.64.5 "screencapture /tmp/s.png"'
  silent "ssh admin@192.168.64.5 'osascript -e \"tell application \\\"Pounce\\\" to activate\"'"
}

@test "a quoted remote payload is ONE segment, separators and all" {
  # The mask is what makes this true: split naively on `;` and the tail of the
  # payload reads as a local command that was never going to run here.
  silent "ssh admin@192.168.64.5 'killall Dock; open -a Pounce; aerospace focus left'"
}

@test "the capture round trip in the workshop's notes/agent-vm.md is silent end to end" {
  silent 'ssh admin@$(tart ip holt-lane) "/usr/sbin/screencapture -x /tmp/s.png" && scp admin@$(tart ip holt-lane):/tmp/s.png ./shot.png'
}

@test "a local command beside a remote one is still gated" {
  # The failure this pins: dropping the whole line once it starts with `ssh`.
  asks 'ssh admin@192.168.64.5 "true" && killall Dock'
  asks 'ssh admin@192.168.64.5 "true"; aerospace focus left'
  asks 'ssh admin@192.168.64.5 "true" | open -f'
  asks 'for h in a b; do ssh $h "true"; done; haus rebuild'
}

@test "ssh that really does draw here keeps asking" {
  asks 'ssh localhost "haus rebuild"'
  asks 'ssh admin@127.0.0.1 "sketchybar --reload x"'
  asks 'ssh -X admin@192.168.64.5 "sketchybar --reload x"'
  asks 'ssh -Y admin@192.168.64.5 "sketchybar --reload x"'
  asks 'ssh mbp.local "haus rebuild"'      # a .local name is a Mac on somebody's desk
}

@test "an ssh to this host's own name is an ssh to this Mac" {
  # $HOSTNAME, not a resolver: the three literal loopback spellings miss the
  # way anyone actually types it. Substituted here so the suite does not depend
  # on what the machine running it is called — and passed as a real command
  # environment, since a `VAR=x fn` prefix on a bats helper never reaches the
  # guard's own bash, which would then set HOSTNAME itself and pass for the
  # wrong reason.
  as_host() {
    printf '%s' "$(bash_json "$2")" | env HOSTNAME="$1" bash "$GUARD" \
      | jq -r '.hookSpecificOutput.permissionDecisionReason // empty'
  }
  [ -n "$(as_host fixturehost 'ssh fixturehost "haus rebuild"')" ]
  [ -n "$(as_host fixturehost 'ssh julien@fixturehost.example.com "sketchybar --reload x"')" ]
  [ -z "$(as_host fixturehost 'ssh admin@192.168.64.5 "haus rebuild"')" ]
}

@test "a flag on one segment does not exempt the next" {
  # The bug this pins: `m` asked "anywhere in the command", so the first call's
  # exempting flag covered the second call's bare one.
  asks 'open -g -a Preview; open -a Ghostty'
  asks 'screencapture -x /tmp/a.png && screencapture /tmp/b.png'
  asks 'tart run vm --no-graphics; tart run other'
}

@test "the guard stays cheap, and a command too big to parse is gated not exempted" {
  # The filter is O(n²) in one line's length, and this hook runs before EVERY
  # Bash call in every lane. Two gates keep that invisible: it is skipped
  # entirely for a command with no ssh-family word in it, and skipped past
  # 32 KB — where skipping means the desktop patterns see the WHOLE command,
  # so a huge remote one asks rather than slipping through.
  local big start
  big="$(head -c 200000 /dev/zero | tr '\0' 'x')"
  start=$SECONDS
  silent "echo $big"
  [ $((SECONDS - start)) -lt 5 ] || { printf 'guard took %ss on a 200 KB command\n' "$((SECONDS - start))" >&2; return 1; }

  asks "ssh admin@192.168.64.5 'haus rebuild' # $big"
}

# ---- tart itself -------------------------------------------------------------

@test "a headless VM boots silently, a windowed one asks" {
  silent 'tart run holt-lane --no-graphics --dir=work:/lane &'
  silent 'tart clone tahoe-base holt-lane; tart ip holt-lane --wait 60'
  silent 'holt runtime up my-lane --backend tart'
  asks 'tart run holt-lane'
  asks 'tart run holt-lane --dir=work:/lane'
}

# ---- the contract ------------------------------------------------------------

@test "every verdict is ask, on exit 0, and unknown tools are left alone" {
  run bash -c "printf '%s' '$(bash_json 'open -a Ghostty')' | bash '$GUARD'"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')" = "ask" ]

  run bash -c "printf '%s' '$(jq -nc '{tool_name: "Read", tool_input: {file_path: "/x"}}')' | bash '$GUARD'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "HAUS_DESKTOP_OK turns the whole guard off" {
  run bash -c "printf '%s' '$(bash_json 'open -a Ghostty')' | HAUS_DESKTOP_OK=1 bash '$GUARD'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
