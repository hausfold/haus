#!/usr/bin/env bash
# desktop-guard.sh — haus's PreToolUse hook for Claude Code (`agent-desktop-guard`).
#
# The problem it solves: `permissions.defaultMode` is "auto" (terminal's
# claudeCodeSettings sets it), so an agent that decides to foreground an app,
# move a window or click something just DOES it — while you are typing into
# something else. With N lanes running that lands as random focus theft, and no
# amount of prompt wording makes it never happen.
#
# What it is NOT: a blocklist. Nothing here is ever refused. The only verdict
# this hook ever returns is "ask" — it re-opens the permission prompt for one
# thin slice of tool calls and leaves auto-mode alone everywhere else. Automating
# a demo recording, driving a GUI you asked for, rebuilding when you said to:
# all still available, one keypress away.
#
# The line it draws is NOT "is this dangerous" — it is:
#
#     does this change what is in front of my eyes, within about two seconds?
#
# That test is why `screencapture -x` and a screenshot-only computer_batch pass
# silently (looking is free) while `open -a` and a click do not, and why
# `defaults write` is absent (invisible until something restarts) but
# `killall Dock` is present (instantly visible).
#
# Deliberately NOT gated: every mcp__claude-in-chrome__* tool. That browser is
# not the one on screen, so an agent driving it costs the user nothing. Same
# reasoning, same answer, for anything run over `ssh` on another machine — a
# lane's own headless macOS VM above all (see the Bash section). The one thing
# that changes is which screen the command lands on.
#
# Escape hatch: HAUS_DESKTOP_OK=1 in a pane's environment turns the whole guard
# off for that pane — for a long unattended run where 40 prompts is the problem.
# Mirrors bench's BENCH_AGENT_SWITCH=1: a reminder, not a jail.
#
# Wired by modules/terminal (home.activation.claudeCodeSettings) as a PreToolUse
# hook matching "Bash|mcp__computer-use__.*". Contract:
# stdin is the hook JSON ({tool_name, tool_input, …}); stdout is either nothing
# (no opinion — normal permission flow) or a hookSpecificOutput verdict; exit 0
# always, because a nonzero exit from a PreToolUse hook means something else.
#
# TWO clients speak that contract. pi's `haus-desktop-guard.ts` extension
# (modules/terminal/pi/desktop-guard.ts) runs this same binary from `tool_call`
# with a synthesised {tool_name:"Bash"} payload, and blocks the call when the
# verdict comes back "ask" and the human says Deny. So the contract above is a
# real interface with a second implementation behind it, not a private detail of
# the Claude hook — the extension parses `permissionDecision` and
# `permissionDecisionReason` by name, and both move together.
PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/etc/profiles/per-user/$(id -un 2>/dev/null)/bin:/opt/homebrew/bin:/usr/bin:/bin:${PATH:-}"

set -u

# Never let the guard itself break a turn: any failure below exits 0 with no
# verdict, which is exactly "no opinion".
in=$(cat 2>/dev/null) || exit 0
[ -n "${HAUS_DESKTOP_OK:-}" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

ask() { # $1 = the reason the user reads in the prompt
  jq -n --arg r "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: $r
    }
  }' 2>/dev/null
  exit 0
}

j() { printf '%s' "$in" | jq -r "$1 // empty" 2>/dev/null; }

tool=$(j '.tool_name')

case "$tool" in
  # ---- computer use -------------------------------------------------------
  # computer_batch is the ONLY interaction tool in this session's toolkit, so
  # its action list is where the whole read/write distinction lives. A batch of
  # nothing but screenshot/zoom/cursor_position/wait is a look — it moves no
  # pointer and steals no focus, and it is precisely what an agent should reach
  # for instead of clicking around. Anything else in the list, ask.
  mcp__computer-use__computer_batch)
    if printf '%s' "$in" | jq -e '
        [.tool_input.actions[]?.action] as $a
        | ($a | length) > 0
          and (($a - ["screenshot", "zoom", "cursor_position", "wait"]) | length) == 0
      ' >/dev/null 2>&1; then
      exit 0
    fi
    ask "This moves the pointer / types / scrolls on the Mac you are using. Prefer a screenshot-only batch, or hand the step back to the user."
    ;;

  # Launching an app is background-safe in one of the tool's two modes and
  # front-and-center in the other, and the hook cannot tell which from here — so
  # it asks. Approving is one keypress; guessing wrong costs the user their
  # window.
  mcp__computer-use__open_application)
    ask "Launching '$(j '.tool_input.app')' may bring it to the front of the screen the user is working on."
    ;;

  mcp__computer-use__write_clipboard)
    ask "Overwrites the user's clipboard, which they may be mid-way through using."
    ;;

  mcp__computer-use__teach_step | mcp__computer-use__teach_batch)
    ask "Teach mode drives the user's screen directly."
    ;;

  # Looking and asking: silent. ENUMERATED, with everything else under the
  # prefix falling through to ask — the settings matcher is the broad
  # `mcp__computer-use__.*`, so a tool this list has never heard of is exactly
  # the case that must not fail open. The sibling browser server already exposes
  # a singular `computer` tool, so a new interaction verb here is one server
  # release away.
  mcp__computer-use__screenshot | mcp__computer-use__zoom \
    | mcp__computer-use__read_clipboard | mcp__computer-use__list_granted_applications \
    | mcp__computer-use__request_access | mcp__computer-use__request_teach_access \
    | mcp__computer-use__switch_display) exit 0 ;;

  mcp__computer-use__*)
    ask "Unrecognised computer-use tool '$tool' — it may drive the screen the user is working on."
    ;;

  Bash) ;;
  *) exit 0 ;;
esac

# ---- Bash ------------------------------------------------------------------
# Nine patterns, each one passing the two-second test above. Kept short on
# purpose: a long list stops being read and starts being clicked through.
cmd=$(j '.tool_input.command')
[ -n "$cmd" ] || exit 0

# ---- prose is not a command ------------------------------------------------
# Every rule below wants a COMMAND, and an agent's Bash call is mostly not
# commands: a `python3 - <<'PY'` that edits a file, a `cat > README.md <<EOF`,
# a commit body, a docs paragraph that happens to say `haus rebuild`. Two weeks
# of transcripts (2026-08-23 → 09-06) put 357 prompts on this guard, and ~300
# of them were text like that — 249 of the 259 `haus rebuild` prompts were the
# words in a heredoc, not the verb on a line of its own. A prompt on prose is
# the one that teaches click-through on the prompts that matter.
#
# So, before anything looks for a command: drop heredoc bodies (the lines
# between `<<WORD` and the line that is WORD, `<<-` tabs allowed, `<<<` is a
# here-string and not this) and comment lines. Whole-line and in memory,
# because a body with no terminator is left exactly as it came — a `<<` inside
# a quoted string must not eat the rest of the command. Failing this pass is
# harmless in the right direction: `cmd` stays raw and prose asks as it did.
if stripped=$(printf '%s\n' "$cmd" | awk '
    { L[NR] = $0 }
    END {
      n = NR; i = 1
      while (i <= n) {
        line = L[i]; i++
        if (line ~ /^[[:space:]]*#/) continue
        scan = line; gsub(/<<</, "   ", scan)
        nd = 0
        while (match(scan, /<<-?[[:space:]]*["'"'"']?[A-Za-z_][A-Za-z0-9_]*["'"'"']?/)) {
          tok = substr(scan, RSTART, RLENGTH)
          S[++nd] = (tok ~ /^<<-/)
          sub(/^<<-?[[:space:]]*["'"'"']?/, "", tok); sub(/["'"'"']$/, "", tok)
          D[nd] = tok
          scan = substr(scan, RSTART + RLENGTH)
        }
        print line
        for (k = 1; k <= nd; k++) {
          found = 0
          for (j = i; j <= n; j++) {
            t = L[j]; if (S[k]) sub(/^\t+/, "", t)
            if (t == D[k]) { found = j; break }
          }
          if (found) i = found + 1
        }
      }
    }
  ' 2>/dev/null); then
  cmd=$stripped
fi

# ---- one command per line, and another machine's screen is not this screen --
# A lane feel-tests the desktop in its OWN headless macOS VM (`scruff runtime up
# --backend tart`, written up in the workshop's `docs/agent-vm.md` — not a
# file in this repo), driven entirely over ssh: `ssh
# admin@<guest> 'haus rebuild'`, `… 'sketchybar --reload …'`, `… 'killall
# Dock'`. Not one of those is visible to the person at this Mac — the guest
# renders to nothing at all — and the guard used to prompt for three of them,
# because it matched the TEXT of a command rather than the machine it lands on.
# A prompt there is worse than useless: it is the thing that teaches
# click-through on the prompts that matter.
#
# So: split the command at unquoted `;`, `&&`, `||`, `|` and newlines, drop the
# segments that run somewhere else, and hand the patterns below ONE SEGMENT PER
# LINE — every rule anchors to the start of a line, so a command word inside a
# quoted argument (`git commit -m "…; haus rebuild …"`, `grep "open -a\|…"`,
# a multi-line `printf '…'`) can never start one. Quote-aware on purpose, so
# `ssh h 'a; b'` is ONE remote segment rather than a remote one and a local
# `b`, and length-preserving, so a segment that IS kept is re-emitted as its
# own original text, quotes and all, never a masked copy — with one exception:
# a quote that spans lines is joined onto one, because the segment is one
# command however many lines its argument takes.
#
# Two ssh shapes stay gated, because both really do draw here:
#   ssh -X / -Y   forwarded windows render on this display
#   this Mac      `localhost`, `127.0.0.1`, `::1`, any `.local` name, or this
#                 host's own $HOSTNAME — an ssh home is not a trip. Those are
#                 spellings, not a resolver: a host that IS this Mac under some
#                 fourth name is exempted, and no cheap check catches it. The
#                 lane flow never has that shape — `tart ip` hands back a
#                 192.168.64.x literal.
# A kept ssh segment is followed by its quoted payload on a line of its own,
# so `ssh localhost "haus rebuild"` still puts `haus rebuild` where a rule
# anchored to a line start can see it.
#
# Whatever the mask cannot classify stays local — a `$(…)`, an ssh whose host
# is a variable — so the failure mode is one extra prompt, never a missed one.
# Same if awk is somehow missing: `cmd` is left exactly as it came.
#
# One gate in front of it, because this hook runs before EVERY Bash call in
# every lane and its own cost has to stay invisible. The char loop is O(n²) in
# one line's length — seconds at a few hundred KB, which an agent writing a
# file through a single-line heredoc reaches — so past 32 KB it is skipped
# rather than trusted: the patterns then see the whole raw command, unanchored,
# which gates a huge remote command instead of exempting it. The failure
# direction stays "one extra prompt". Under the cap it runs for every command
# (~0.14 s at the cap, invisible at the sizes real calls have), because the
# per-line anchoring above is what keeps the rules off prose.
segmented=
# bash sets HOSTNAME itself, so the this-Mac test below costs no fork in the
# normal case; the fallback is only reached in a shell that unset it.
self=${HOSTNAME:-$(hostname -s 2>/dev/null)}
if [ "${#cmd}" -le 32768 ] && filtered=$(printf '%s\n' "$cmd" | awk -v self="${self%%.*}" '
    function flush(   m, p) {
      if (seg == "") { mseg = ""; return }
      m = mseg
      sub(/^[[:space:]]+/, "", m)
      while (m ~ /^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+/)
        sub(/^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+/, "", m)
      sub(/^(exec|command|nohup)[[:space:]]+/, "", m)
      if (m ~ /^([^[:space:]]*\/)?(ssh|scp|sftp|rsync)[[:space:]]/) {
        if (m !~ /[[:space:]]-[A-Za-z]*[XY]([[:space:]]|$)/ &&
            m !~ /(localhost|127\.0\.0\.1|::1|\.local([[:space:]]|:|$))/ &&
            (self == "" || index(m, self) == 0)) { seg = ""; mseg = ""; return }
        p = seg
        if (match(p, /["'"'"']/)) { p = substr(p, RSTART + 1); gsub(/\n/, " ", p); payload = p }
      }
      sub(/^[[:space:]]+/, "", seg)   # a kept segment starts the line: `^` anchors below want no indent
      gsub(/\n/, " ", seg)            # a quote spanning lines is still one command
      print seg
      if (payload != "") { print payload; payload = "" }
      seg = ""; mseg = ""
    }
    {
      n = length($0)
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1)
        if (q != "") {                                    # inside a quote
          if (q == "\"" && c == "\\" && i < n) { seg = seg c substr($0, i + 1, 1); mseg = mseg "__"; i++ }
          else if (c == q)                     { seg = seg c; mseg = mseg c; q = "" }
          else                                 { seg = seg c; mseg = mseg "_" }
          continue
        }
        if (c == "\"" || c == "'"'"'") { q = c; seg = seg c; mseg = mseg c; continue }
        if (c == "\\") {                                  # escaped: never a separator
          seg = seg c; mseg = mseg "_"
          if (i < n) { i++; seg = seg substr($0, i, 1); mseg = mseg "_" }
          continue
        }
        if (c == ";" || c == "&" || c == "|") { flush(); continue }
        seg = seg c; mseg = mseg c
      }
      if (q != "") { seg = seg "\n"; mseg = mseg "\n" }   # a quote spanning lines
      else flush()
    }
    END { flush() }
  ' 2>/dev/null); then
  cmd=$filtered
  segmented=1
fi
# Every segment ran elsewhere: there is nothing here to have an opinion about.
[ -n "$cmd" ] || exit 0

# ---- a wrapper is not a hiding place ---------------------------------------
# The rules below anchor to the start of a line, deliberately: an unanchored
# `open` fires on `open the door` in a commit message, and a guard that nags on
# prose is one that gets clicked through. But an anchor is only as good as its
# idea of where a command STARTS, and a wrapper moves it — `bash -c 'killall
# Dock'`, `sudo killall WindowServer`, `nohup open -a Ghostty &`, `if …; then
# open -a Ghostty`. Not one of those matched. #579 found the shape the hard
# way: handed a refusal that named HAUS_DESKTOP_OK, pi re-issued the call as
# `HAUS_DESKTOP_OK=1 bash -c '<the same command>'` — and the wrapper half of
# that would have worked on its own.
#
# So: peel the wrappers off each segment and APPEND what was hiding under them.
# Appending rather than rewriting is what makes this safe to reason about — a
# peel that guesses wrong can only add a prompt, never take one away, and one
# pattern below (`BENCH_AGENT_SWITCH=… try … switch`) is a shape whose env
# prefix IS the match. It is prefix-shaped and stops at the first token it
# cannot name, so a wrapper flag carrying a VALUE (`sudo -u admin killall …`)
# ends the walk and stays exactly as quiet as it is today. `command` and
# `builtin` are deliberately NOT in the list: they prefix nothing an agent
# could not have typed bare, and `command -v screencapture && …` — the
# is-it-here idiom this repo is built out of — would have started prompting.
#
# The split here is naive where the segmenter above is quote-aware, and that
# is the right trade in this direction: once a piece of a line has been peeled,
# every piece after it is appended too, so the second statement of a
# `bash -c 'a; killall Dock'` payload is seen — a separator inside a quoted
# argument can only ever ADD a line, and a line that matches no rule costs
# nothing. The segmenter had to DROP text, where a wrong split is a gate that
# silently stopped firing.
if unwrapped=$(printf '%s\n' "$cmd" | awk '
    function unwrap(s,   before, k) {
      # BOUNDED, and the bound is the point: every sub() below rescans what is
      # left, so an unbounded walk is O(n²) in the number of prefixes and BWK
      # awk — the one a Mac ships, and the one this runs under — takes 38 s
      # over `sudo ` twenty thousand times.
      # A PreToolUse hook holds the tool call while it thinks, so that is a
      # dead turn. Nothing real stacks two dozen wrappers; past the bound the
      # rest stays wrapped, which is the same direction as stopping at a token
      # it cannot name.
      for (k = 0; k < 24; k++) {
        before = s
        sub(/^[[:space:]]+/, "", s)
        sub(/^[({][[:space:]]*/, "", s)                     # a subshell is not a hiding place either
        sub(/^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+/, "", s)
        sub(/^([^[:space:]]*\/)?(sudo|doas|env|nohup|exec|time|nice|arch|xargs|caffeinate|if|then|else|elif|do|while|until)([[:space:]]+-[-A-Za-z0-9]+)*[[:space:]]+/, "", s)
        # Long flags and short ones are separate alternatives because the short
        # class has to exclude `c` (so `-lc` is left for the terminator below),
        # and one class for both would exclude `--norc` with it.
        if (sub(/^([^[:space:]]*\/)?(ba|da|k|z|a|c|tc|fi)?sh([[:space:]]+(--[-A-Za-z0-9]+|-[-A-Za-bd-z0-9]+))*[[:space:]]+-[A-Za-z]*c[[:space:]]+/, "", s) ||
            sub(/^eval[[:space:]]+/, "", s))
          sub(/^["'"'"']/, "", s)   # the payload of a `-c` starts inside a quote
        if (s == before) break
      }
      return s
    }
    {
      n = split($0, seg, /[;&|]/)
      peeled = 0
      for (i = 1; i <= n; i++) {
        s = seg[i]
        sub(/^[[:space:]]+/, "", s)
        u = unwrap(s)
        if (u != "" && u != s) { print u; peeled = 1 }
        else if (peeled && s != "") print s
      }
    }
  ' 2>/dev/null) && [ -n "$unwrapped" ]; then
  cmd="$cmd
$unwrapped"
fi

# Every rule is anchored to the start of a line, which is the start of a
# segment once the segmenter has run. When it has not — a command past the
# size cap, or no awk — there are no segments to anchor to, and the rules see
# the whole raw command instead: unanchored, as the guard always did before it
# learned to segment, which asks more rather than less.
A='^ *'
[ -n "$segmented" ] || A=''
m() { printf '%s' "$cmd" | grep -Eq "$1"; }

# Three of the rules below are PAIRS — a shape that asks, and a flag that
# exempts it (`open -g`, `screencapture -x`, `tart run --no-graphics`) — and
# `m` is the wrong question for those: it asks "anywhere in the command", so
# one segment's flag silently exempted another segment's bare call. `open -g a;
# open b` was silent, and so was `tart run vm --no-graphics; tart run other`.
# `unpaired` asks what those rules actually mean: is there a SEGMENT matching
# $1 that does not carry $2? A segmented command already has one per line;
# the raw fallback splits on the separator characters, which is enough there —
# one inside a quoted argument splits a segment that then matches neither half,
# which asks, and asking is the safe direction.
lines() { if [ -n "$segmented" ]; then printf '%s' "$cmd"; else printf '%s' "$cmd" | tr ';&|' '\n\n\n'; fi; }
unpaired() { lines | grep -E "$1" | grep -Eqv "$2"; }

# `open` foregrounds by default; only the explicitly-backgrounded form passes.
#
# Two shapes this deliberately does NOT match, both found by review:
#   - prose. grep is line-based, so a bare `^open ` would fire on any line of a
#     heredoc that happens to start with the word — `open the door` in a commit
#     message. Requiring a flag, a path-shaped argument or a URL keeps English
#     out. Nagging on prose is worse than not nagging: it trains click-through.
#   - `open -ga Ghostty`. The flag cluster is combined far more often than not,
#     so the background exemption looks for a `g` ANYWHERE in a whitespace-led
#     cluster rather than a standalone `-g`. The leading whitespace matters:
#     without it `open ./my-great-file` exempts itself on the `-g` of "great".
if unpaired '^ *open +(-[a-zA-Z]|[~./$"'"'"']|[a-z][a-z0-9+.-]*://)' 'open.*[[:space:]]-([a-zA-Z]*g|-background)'; then
  ask "\`open\` brings an app or file to the front. \`open -g\` launches without activating, but it does not promise a window — Ghostty under it opens none, and \`open\` exits 0 either way. Use it to RUN something, a VM to SEE something, or ask the user to open it."
fi

m "$A"'([^[:space:]]*/)?osascript[^;&|]*activate' &&
  ask "This AppleScript activates an app — it will take the user's focus."

# `--help` on a verb that would move a window moves nothing — and an agent
# reading a CLI's help is exactly the agent to leave alone.
if unpaired '^ *([^[:space:]]*/)?aerospace +(focus|move|workspace|layout|fullscreen|flatten)([[:space:]]|$)' 'aerospace.*(--help|[[:space:]]-h([[:space:]]|$))'; then
  ask "This moves or refocuses the user's windows."
fi

m "$A"'([^[:space:]]*/)?sketchybar[^;&|]*--reload' &&
  ask "Reloading the bar redraws the user's menu bar."

m "$A"'([^[:space:]]*/)?launchctl +kickstart' &&
  ask "Restarting this agent kills whatever the user has open from it (the Pounce palette, the Perch shelf)."

m "$A"'([^[:space:]]*/)?killall +(Dock|Finder|SystemUIServer|sketchybar|WindowServer)' &&
  ask "Restarting this process visibly redraws the user's desktop."

# screencapture's default plays the shutter and flashes the screen; -x is silent
# and is the form an agent should be reaching for.
# The -x test needs the leading whitespace for the same reason `open -g` does:
# without it `screencapture ~/shot-x.png` exempts itself on its own filename.
if unpaired '^ *([^[:space:]]*/)?screencapture[[:space:]]' 'screencapture.*[[:space:]]-[a-zA-Z]*x'; then
  ask "\`screencapture\` without \`-x\` plays the shutter sound and flashes the screen. Add \`-x\` to take it silently."
fi

# The VM exemption above holds only while the VM is headless. `tart run`
# without --no-graphics opens the guest's window, full size, on this display —
# the one command in the whole tart flow that IS screen theft. `scruff runtime up
# --backend tart` already boots headless; this is for a hand-run one.
if unpaired '^ *([^[:space:]]*/)?tart +run([[:space:]]|$)' 'tart +run.*(--no-graphics|--help)'; then
  ask "\`tart run\` without \`--no-graphics\` opens the VM's window on the user's display. Boot it headless — that is what \`scruff runtime up --backend tart\` does."
fi

# `haus report` ends by opening the bug form in a browser — a window on the
# user's display, from a pane that runs in permission mode `auto`. `--print`
# stops before that and prints the block and the link instead, which is also the
# only form of it any agent wants: hand over the link, don't take the screen.
if unpaired '^ *([^[:space:]]*/)?haus +report([[:space:]]|$)' 'haus +report.*--print'; then
  ask "\`haus report\` opens the bug form in the user's browser. \`haus report --print\` prints the same block and the same link and opens nothing — hand them the link."
fi

m "$A"'(([^[:space:]]*/)?darwin-rebuild +switch|([^[:space:]]*/)?haus +rebuild|BENCH_AGENT_SWITCH=[^ ]* +.*try +.*switch)' &&
  ask "Activation is machine-wide and serial — with several lanes running, the last one to switch silently wins."

exit 0
