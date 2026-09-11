#!/usr/bin/env bats
# Hermetic tests for the weekly SUB-limits in the aiUsage pill
# (modules/bar/sketchybar/plugins/ai_usage.sh).
#
# Why a suite. A Max plan caps some model families INSIDE the weekly allowance
# rather than beside it — Fable may take up to half the week, and nothing is
# given back for it — so a family can be spent for the week while the weekly
# gauge it lives in still reads 50%. That is a number the bar shows WRONG rather
# than not at all, which is the one failure a glance never catches: the pill is
# lit, confident, and describing the half of the week you were not about to run
# out of. Everything below is aimed at that.
#
# The other half is freshness. Two feeds write here on very different clocks —
# the nine-column usage row is PUSHED by every render of every open pane, the
# sub-limits are only PULLED — so a row seconds old sitting beside numbers an
# hour old is the NORMAL state, not the broken one. A sub-limit that reached the
# pill's label on the strength of its neighbour's stamp would be the first bug
# back.
#
# Harness as barlib.bats's: $HOME redirected, the three sourced files faked, and
# $SB a recorder that appends one line of argv per call, so a test asserts on
# sketchybar TRAFFIC rather than on pixels.

bats_require_minimum_version 1.5.0

setup() {
  PILL="$BATS_TEST_DIRNAME/../modules/bar/sketchybar/plugins/ai_usage.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  export TZ=UTC                       # the reset notes are local time
  BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$HOME/.config/sketchybar/plugins" "$BIN" "$BATS_TEST_TMPDIR/cache"
  export CLAUDE_STATUSLINE_CACHE="$BATS_TEST_TMPDIR/cache"

  export SB_LOG="$BATS_TEST_TMPDIR/sb.log"
  cat >"$BIN/sb" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$SB_LOG"
EOF
  # popup_toggle asks the bar whether the dropdown is up, through jq. An empty
  # answer is the "no answer" case, which a toggle treats as closed-and-open —
  # so every click below builds rows. The pill itself never calls jq.
  cat >"$BIN/jq" <<'EOF'
#!/bin/bash
printf '\n'
EOF
  # `date -r <epoch>` is BSD. The pill is macOS-only and spells it that way on
  # purpose; the RUNNER may be GNU, where -r means "reference file" and every
  # reset note would come out empty — green, and testing nothing. Answer both
  # the same, and pin the real binary before $BIN goes on PATH.
  local real_date; real_date=$(command -v date)
  cat >"$BIN/date" <<EOF
#!/bin/bash
if [ "\${1:-}" = "-r" ] && [ -n "\${2:-}" ] && [ -z "\${2//[0-9]/}" ]; then
  if "$real_date" --version >/dev/null 2>&1; then "$real_date" -d "@\$2" "\${3:-+%s}"
  else "$real_date" -r "\$2" "\${3:-+%s}"; fi
  exit 0
fi
exec "$real_date" "\$@"
EOF
  chmod +x "$BIN/sb" "$BIN/jq" "$BIN/date"
  export PATH="$BIN:$PATH"

  # The three files barlib sources. The colors.sh stub is the SAME block
  # test/barlib.bats writes, in the same bare `export TONE_…=` shape, because
  # `bar-tones` reads both files with one regex and diffs them against
  # modules/bar/tones.nix — a rung added to the ladder and forgotten in either
  # stub paints grey in every test here, silently, and the assertions below name
  # these hexes by rung.
  cat >"$HOME/.config/sketchybar/colors.sh" <<'EOF'
export FLAMINGO=0xffeebbcc
export TONE_MUTE=0xff111111
export TONE_DIM=0xff1a1a1a
export TONE_TEXT=0xff777777
export TONE_OK=0xff222222
export TONE_BUSY=0xff333333
export TONE_WATCH=0xff3a3a3a
export TONE_WARN=0xff444444
export TONE_BAD=0xff555555
export TONE_ACTION=0xff5a5a5a
export TONE_ACCENT=0xff666666
export MARK_WARM=0xff7a0001
export MARK_RUST=0xff7a0005
export MARK_PINK=0xff7a0006
export MARK_VIOLET=0xff7a0003
export MARK_BLUE=0xff7a0007
export MARK_TEAL=0xff7a0002
export MARK_PLUM=0xff7a0004
export TEXT=0xff777777
export SUBTEXT0=0xff888888
export OVERLAY0=0xff999999
export OVERLAY1=0xffaaaaaa
export SURFACE1=0xffbbbbbb
export SURFACE0=0xffcccccc
export BASE=0xff000000
EOF
  cat "$BATS_TEST_DIRNAME/colors-fns.sh" >>"$HOME/.config/sketchybar/colors.sh"
  cat >"$HOME/.config/sketchybar/sizes.sh" <<'EOF'
export BAR_FONT="Test Font"
export FS_ICON=14
export FS_LABEL=13
export FS_SMALL=12
export FS_TINY=10
export FS_APP_ICON=14
export BAR_SCALE=1
export PAD_ICON_L=8
export PAD_ICON_R=4
export PAD_ICON_SOLO=10
EOF
  cat >"$HOME/.config/sketchybar/bar.sh" <<EOF
BAR_TOP="$BIN/sb"
BAR_BOTTOM=""
SB="\$BAR_TOP"
EOF
  cp "$BATS_TEST_DIRNAME/../modules/bar/sketchybar/barlib.sh" "$HOME/.config/sketchybar/"
  cp "$BATS_TEST_DIRNAME/../modules/bar/sketchybar/plugins/ai-provider.sh" \
     "$HOME/.config/sketchybar/plugins/"

  NOW=$(date +%s)
  R5=$((NOW + 3600))        # session resets in an hour
  RW=$((NOW + 80000))       # weekly resets tomorrow
  usage 35 89
}

usage() { # usage <5h %> <7d %> — the nine-column row, written just now
  printf '%s\t%s\t%s\t%s\t%s\tclaude\tclaude\tanthropic\t%s\n' \
    "$1" "$2" "$R5" "$RW" "$NOW" "$NOW" >"$CLAUDE_STATUSLINE_CACHE/usage-claude.tsv"
}

scoped() { # scoped <family> <%> [resets] [written] — one sub-limit row, appended
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "${3:-$RW}" "${4:-$NOW}" \
    >>"$CLAUDE_STATUSLINE_CACHE/scoped-claude.tsv"
}

fail() { printf '%s\n' "$1" >&2; return 1; }

# The runtime BATCHES a whole dropdown into one sketchybar call, so the log is a
# handful of very long lines and nothing about a row is per-LINE. Order and tone
# are read off the argv stream a token at a time instead.
tok() { # tok <exact token> — its 1-based position in the traffic, empty if absent
  traffic | tr ' ' '\n' | grep -n -m1 -x -- "$1" | cut -d: -f1
}

# Through the plugin's OWN shebang (`#!/bin/bash`), never `bash "$PILL"`: on this
# machine that is 3.2.57, which is the shell sketchybar runs it with and the one
# a `local -A` or a `mapfile` would only fail in. `bash` on PATH here is 5.
tick()  { : >"$SB_LOG"; NAME=ai_usage SENDER=routine "$PILL"; }
click() { : >"$SB_LOG"; NAME=ai_usage SENDER=mouse.clicked BUTTON=left "$PILL"; }
traffic() { cat "$SB_LOG"; }

@test "a sub-limit never reaches the pill's own label, however high it reads" {
  # The pill's number answers "how close am I to being stopped", and a spent
  # ceiling does not stop you: every other model is still there. It rode the
  # label for a day, wearing the family's initial, and the highest number on the
  # machine turned out to be the one that changed nothing about what you could
  # do next. The gauge lives in the dropdown, read against the weekly it comes
  # out of; this is the case that keeps it there.
  scoped Fable 100
  tick
  traffic | grep -q 'label=89% ' || fail "the weekly no longer stands: $(traffic | tr '\n' ' ')"
  traffic | grep -qE 'label=100%|label=[0-9]+% [A-Z]' \
    && fail "the sub-limit reached the label"
  return 0
}

@test "a sub-limit under the weekly changes nothing either" {
  scoped Fable 40
  tick
  traffic | grep -q 'label=89% ' || fail "weekly no longer stands: $(traffic | tr '\n' ' ')"
}

@test "the dropdown draws one gauge per family, under the weekly" {
  scoped Fable 100
  scoped Cowork 12
  click
  traffic | grep -q 'icon=session' || fail "no session gauge"
  traffic | grep -q 'icon=weekly'  || fail "no weekly gauge"
  traffic | grep -q 'icon=fable'   || fail "no fable gauge: $(traffic | tr '\n' ' ')"
  traffic | grep -q 'icon=cowork'  || fail "no cowork gauge"
  # Under it, not above it: a ceiling is read against the window it is carved
  # out of, and a reader who has to scroll back up to find that window is
  # reading two unrelated numbers.
  [ "$(tok icon=weekly)" -lt "$(tok icon=fable)" ] || fail "fable drawn above weekly"
}

@test "a family inheriting the weekly's reset does not repeat it" {
  # Which, for a ceiling inside that window, is always. The row would otherwise
  # restate the line directly above it word for word.
  scoped Fable 100
  click
  traffic | grep -q 'icon=fable · resets' && fail "repeated the weekly's reset time"
  return 0
}

@test "a family with a reset of its own keeps it" {
  scoped Fable 100 $((RW + 200000))
  click
  traffic | grep -q 'icon=fable · resets' || fail "dropped a reset the weekly never gave"
}

@test "a window that already rolled over draws zero, not last week's number" {
  # What makes the hour-long horizon safe. Without it a gauge would keep last
  # week's 100% until the next successful poll.
  scoped Fable 100 $((NOW - 10)) "$NOW"
  click
  traffic | grep -q 'icon=fable' || fail "the gauge should still be drawn, at zero"
  traffic | tr ' ' '\n' | grep -qx 'label=0%' || fail "a rolled window is not 0%"
}

@test "ten minutes of silence is not stale here, and five is not either" {
  # These numbers are a fraction of a SEVEN-DAY window and are only ever pulled.
  # Greying them on the pushed row's five-minute horizon had the dropdown fading
  # a gauge in and out on a feed that merely stuttered.
  scoped Fable 100 "$RW" $((NOW - 600))
  click
  [ -z "$(tok label.color=0xff111111)" ] || fail "greyed a ten-minute-old ceiling"
  [ -n "$(tok label.color=0xff555555)" ] || fail "a live 100% is not on the bad rung"
}

@test "a stale family greys, and takes none of the gauges above it with it" {
  # The pill's own grey is all-or-nothing because one feed backs the whole row.
  # Here it cannot be: the session and weekly numbers are still being pushed,
  # and greying them for a pull that died would be a lie about live data.
  scoped Fable 100 "$RW" $((NOW - 4000))
  click
  [ -n "$(tok label.color=0xff111111)" ] || fail "a stale family did not grey (mute)"
  [ -n "$(tok label.color=0xff444444)" ] \
    || fail "the weekly lost its warn rung to a dead pull"
  [ -n "$(tok label.color=0xff222222)" ] || fail "the session lost its ok rung too"
}

@test "no sub-limit file at all leaves the pill exactly as it was" {
  # Most accounts have no scoped ceiling, and every machine had none before this
  # feed existed. Neither may pay a line of traffic for it.
  tick
  traffic | grep -q 'label=89% ' || fail "pill changed with no sub-limit to show"
  click
  traffic | grep -q 'icon=fable' && fail "drew a gauge for a family nobody reported"
  # And it costs no noise either. `done <"$missing" 2>/dev/null` suppresses
  # nothing: the redirections are applied left to right, so the shell has
  # already shouted into the bar's log by the time the second one lands.
  run bash -c 'NAME=ai_usage SENDER=mouse.clicked BUTTON=left "$0" 2>&1 >/dev/null' "$PILL"
  [ -z "$output" ] || fail "wrote to the bar's log with no sub-limit file: $output"
}

@test "a row the feed garbled is skipped, not drawn as a number" {
  # `[ "$x" -ge 90 ]` on a non-number prints `integer expression expected` into
  # the bar's log once per row, per open, forever.
  printf 'Fable\tn/a\t%s\t%s\n' "$RW" "$NOW" >"$CLAUDE_STATUSLINE_CACHE/scoped-claude.tsv"
  scoped Cowork 12
  click
  traffic | grep -q 'icon=cowork' || fail "one bad row took the good one with it"
  traffic | grep -q 'icon=fable' && fail "drew a gauge for a percent that is not one"
  run bash -c 'NAME=ai_usage SENDER=routine "$0" 2>&1' "$PILL"
  [[ "$output" != *"integer expression"* ]] || fail "shouted at the bar's log: $output"
}

