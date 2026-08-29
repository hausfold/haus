#!/usr/bin/env bats
# Hermetic tests for modules/bar/sketchybar/barlib.sh — the bar widget runtime
# (docs/bar-framework.md).
#
# Why a suite. Every promise barlib makes fails SILENTLY on the machine that
# breaks it: a diff that never settles repaints a quiet pill forever (invisible
# — the bar just works harder), a diff that over-matches freezes a pill on
# stale data, a --hide without updates=on is a pill no event can ever bring
# back, and a batch that splits into N spawns costs the exact latency the
# framework exists to remove. None of those show in a build or an eval.
#
# The harness fakes the three files barlib sources ($HOME redirected into
# BATS_TEST_TMPDIR) and replaces $SB with a recorder that appends one line of
# argv per invocation — so a test can assert on sketchybar TRAFFIC: how many
# calls, and exactly what rode each one.

bats_require_minimum_version 1.5.0

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.config/sketchybar" "$BATS_TEST_TMPDIR/bin"

  export SB_LOG="$BATS_TEST_TMPDIR/sb.log"
  cat >"$BATS_TEST_TMPDIR/bin/sb" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$SB_LOG"
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/sb"

  # The three files barlib sources, minimal but shaped like the real ones:
  # colors.sh carries the TONE_* ladder the generated file exports, bar.sh
  # sets $SB / $BAR_TOP / $BAR_BOTTOM the way the generated router does.
  cat >"$HOME/.config/sketchybar/colors.sh" <<EOF
export FLAMINGO=0xffeebbcc
export TONE_MUTE=0xff111111
export TONE_OK=0xff222222
export TONE_BUSY=0xff333333
export TONE_WARN=0xff444444
export TONE_BAD=0xff555555
export TONE_ACCENT=0xff666666
EOF
  cat >"$HOME/.config/sketchybar/sizes.sh" <<'EOF'
export BAR_FONT="Test Font"
EOF
  cat >"$HOME/.config/sketchybar/bar.sh" <<EOF
BAR_TOP="$BATS_TEST_TMPDIR/bin/sb"
BAR_BOTTOM=""
SB="\$BAR_TOP"
EOF

  BARLIB="${BARLIB_UNDER_TEST:-$BATS_TEST_DIRNAME/../modules/bar/sketchybar/barlib.sh}"
}

# widget <body> — write a widget script around the given fetch/render/on_*
# definitions and run it the way sketchybar would (env NAME/SENDER/BUTTON
# come from the caller's exports).
widget() {
  local f="$BATS_TEST_TMPDIR/widget.sh"
  {
    printf '#!/bin/bash\nsource "%s"\n' "$BARLIB"
    printf '%s\n' "$1"
    printf 'barlib_main "$@"\n'
  } >"$f"
  chmod +x "$f"
  bash "$f"
}

calls() { [ -f "$SB_LOG" ] && wc -l <"$SB_LOG" | tr -d ' ' || echo 0; }

@test "first tick renders and batches into one sketchybar call" {
  NAME=w SENDER=routine widget '
    fetch() { emit label=hello tone=ok; }
    render() { pill --icon X --label "$label" --tone "$tone"; }
  '
  [ "$(calls)" = 1 ]
  grep -q -- '--set w drawing=on --set w label=hello --set w icon=X icon.drawing=on --set w icon.color=0xff222222' "$SB_LOG"
}

@test "unchanged state costs zero sketchybar traffic" {
  for _ in 1 2; do
    NAME=w SENDER=routine widget '
      fetch() { emit label=hello; }
      render() { pill --label "$label"; }
    '
  done
  [ "$(calls)" = 1 ]
}

@test "changed state renders again" {
  NAME=w SENDER=routine widget 'fetch() { emit n=1; }; render() { pill --label "$n"; }'
  NAME=w SENDER=routine widget 'fetch() { emit n=2; }; render() { pill --label "$n"; }'
  [ "$(calls)" = 2 ]
}

@test "SENDER=forced repaints through an unchanged cache" {
  NAME=w SENDER=routine widget 'fetch() { emit n=1; }; render() { pill --label "$n"; }'
  NAME=w SENDER=forced widget 'fetch() { emit n=1; }; render() { pill --label "$n"; }'
  [ "$(calls)" = 2 ]
}

@test "state with spaces round-trips into render variables" {
  NAME=w SENDER=routine widget '
    fetch() { emit label="3 PRs waiting"; }
    render() { pill --label "$label"; }
  '
  grep -q 'label=3 PRs waiting' "$SB_LOG"
}

@test "pill --hide pairs drawing=off with updates=on" {
  NAME=w SENDER=routine widget 'fetch() { emit x=1; }; render() { pill --hide; }'
  grep -q -- '--set w drawing=off updates=on' "$SB_LOG"
}

@test "empty --icon turns the icon off rather than drawing a blank" {
  NAME=w SENDER=routine widget 'fetch() { emit x=1; }; render() { pill --icon "" --label L; }'
  grep -q 'icon.drawing=off' "$SB_LOG"
  ! grep -q 'icon= ' "$SB_LOG"
}

@test "mouse.clicked routes to on_click and never runs fetch" {
  NAME=w SENDER=mouse.clicked widget '
    fetch() { echo FETCHED >"$BATS_TEST_TMPDIR/fetched"; }
    on_click() { sb_set label=clicked; }
  '
  [ ! -f "$BATS_TEST_TMPDIR/fetched" ]
  grep -q -- '--set w label=clicked' "$SB_LOG"
}

@test "modifier click routes to its handler, falls back to on_click" {
  NAME=w SENDER=mouse.clicked BUTTON=left MODIFIER=cmd widget '
    on_click() { sb_set label=plain; }
    on_cmd_click() { sb_set label=cmd; }
  '
  grep -q 'label=cmd' "$SB_LOG"
  : >"$SB_LOG"
  NAME=w SENDER=mouse.clicked BUTTON=left MODIFIER=alt widget '
    on_click() { sb_set label=plain; }
  '
  grep -q 'label=plain' "$SB_LOG"
}

@test "unknown tone warns and paints mute instead of failing the pill" {
  NAME=w SENDER=routine widget 'fetch() { emit x=1; }; render() { pill --icon X --tone banana; }' 2>"$BATS_TEST_TMPDIR/err"
  grep -q 'icon.color=0xff111111' "$SB_LOG"
  grep -q 'unknown tone' "$BATS_TEST_TMPDIR/err"
}

@test "emit refuses a non-identifier key and a newline value, loudly" {
  NAME=w SENDER=routine widget '
    fetch() {
      emit "bad-key=1" "good=1" "multi=a
b"
    }
    render() { pill --label "ran $good ${bad_key:-}${multi:-}"; }
  ' 2>"$BATS_TEST_TMPDIR/err"
  grep -q 'label=ran 1 $' "$SB_LOG" || grep -q 'label=ran 1' "$SB_LOG"
  grep -q "not identifier=value" "$BATS_TEST_TMPDIR/err"
  grep -q "has a newline" "$BATS_TEST_TMPDIR/err"
}

@test "a widget with handlers only makes no call on a routine tick" {
  NAME=w SENDER=routine widget 'on_click() { sb_set label=x; }'
  [ "$(calls)" = 0 ]
}

@test "widgets cache per item name, not per file" {
  NAME=a SENDER=routine widget 'fetch() { emit n=1; }; render() { pill --label "$n"; }'
  NAME=b SENDER=routine widget 'fetch() { emit n=1; }; render() { pill --label "$n"; }'
  [ "$(calls)" = 2 ]
}
