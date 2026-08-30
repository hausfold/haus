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
export TONE_TEXT=0xff777777
export TEXT=0xff777777
export SUBTEXT0=0xff888888
export OVERLAY0=0xff999999
EOF
  cat >"$HOME/.config/sketchybar/sizes.sh" <<'EOF'
export BAR_FONT="Test Font"
export FS_LABEL=13
export FS_SMALL=12
export FS_TINY=10
export PAD_ICON_L=8
export PAD_ICON_R=4
export PAD_ICON_SOLO=10
EOF
  cat >"$HOME/.config/sketchybar/bar.sh" <<EOF
BAR_TOP="$BATS_TEST_TMPDIR/bin/sb"
BAR_BOTTOM=""
SB="\$BAR_TOP"
EOF

  # popup_toggle asks the bar whether the dropdown is up, through jq. The
  # recorder above answers nothing, so the query comes back empty — which is
  # the "no answer" case, and the one a toggle must treat as closed-and-open
  # rather than as open-and-close. A test that wants the other branch exports
  # SB_POPUP_DRAWING and the stub jq echoes it.
  cat >"$BATS_TEST_TMPDIR/bin/jq" <<'EOF'
#!/bin/bash
printf '%s\n' "${SB_POPUP_DRAWING:-}"
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/jq"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"

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
  grep -q -- '--set w drawing=on --set w label=hello label.drawing=on --set w icon=X icon.drawing=on --set w icon.padding_left=8 icon.padding_right=4 --set w icon.color=0xff222222' "$SB_LOG"
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

@test "a state key named like a runtime local cannot poison the diff" {
  # The reviewer's repro: `emit state=busy` once landed the VALUE in the
  # cache file (the eval clobbered the runtime's own `state` between diff
  # and write), so the diff never settled and the pill repainted forever.
  for _ in 1 2 3; do
    NAME=w SENDER=routine widget '
      fetch() { emit state=busy label=x; }
      render() { pill --label "$label $state"; }
    '
  done
  [ "$(calls)" = 1 ]
  grep -q 'label=x busy' "$SB_LOG"
}

@test "emit refuses runtime names loudly" {
  NAME=w SENDER=routine widget '
    fetch() { emit NAME=evil good=1; }
    render() { pill --label "$good"; }
  ' 2>"$BATS_TEST_TMPDIR/err"
  grep -q 'runtime name' "$BATS_TEST_TMPDIR/err"
  grep -q -- '--set w' "$SB_LOG"
  ! grep -q -- '--set evil' "$SB_LOG"
}

@test "the button outranks the modifier on a click" {
  NAME=w SENDER=mouse.clicked BUTTON=right MODIFIER=cmd widget '
    on_right_click() { sb_set label=right; }
    on_cmd_click() { sb_set label=cmd; }
  '
  grep -q 'label=right' "$SB_LOG"
}

@test "widgets cache per item name, not per file" {
  NAME=a SENDER=routine widget 'fetch() { emit n=1; }; render() { pill --label "$n"; }'
  NAME=b SENDER=routine widget 'fetch() { emit n=1; }; render() { pill --label "$n"; }'
  [ "$(calls)" = 2 ]
}

# ---- the dropdown -----------------------------------------------------------

@test "an empty label hides it and re-centres the icon" {
  export NAME=w SENDER=routine
  run widget 'fetch() { emit n=0; }
render() { pill --icon "X" --label ""; }'
  [ "$status" -eq 0 ]
  grep -q 'label.drawing=off' "$SB_LOG"
  grep -q "icon.padding_left=10 icon.padding_right=10" "$SB_LOG"
}

@test "a label that comes back takes the default padding with it" {
  export NAME=w SENDER=routine
  run widget 'fetch() { emit n=1; }
render() { pill --icon "X" --label "3"; }'
  [ "$status" -eq 0 ]
  grep -q 'label=3 label.drawing=on' "$SB_LOG"
  grep -q "icon.padding_left=8 icon.padding_right=4" "$SB_LOG"
}

@test "the text tone is the ordinary foreground, not the mute grey" {
  export NAME=w SENDER=routine
  run widget 'fetch() { emit n=1; }
render() { pill --icon "" --tone text --label "3" --label-tone mute; }'
  [ "$status" -eq 0 ]
  grep -q 'icon.color=0xff777777' "$SB_LOG"
  grep -q 'label.color=0xff111111' "$SB_LOG"
}

@test "popup rows ride ONE call with the popup.drawing that shows them" {
  export NAME=w SENDER=mouse.clicked BUTTON=left
  run widget 'popup_rows() {
  popup_heading --label "Open PRs" --count 12 --tone warn
  popup_row --label "fix the thing" --tone ok --open "https://example.com/1"
  popup_note --label "+4 more"
}
on_click() { popup_toggle; }'
  [ "$status" -eq 0 ]
  # Three rows, ONE --add call. (The other two lines are the toggle's --query
  # and the --remove that clears the previous rows, both of which have to be
  # their own call — the query because its answer decides what happens next,
  # the remove because the adds below reuse the ids it is clearing.)
  [ "$(grep -c -- '--add item' "$SB_LOG")" -eq 1 ]
  grep -q -- '--remove' "$SB_LOG"
  local batch
  batch=$(grep -- '--add item' "$SB_LOG")
  [[ "$batch" == *"--add item w.popup.0 popup.w"* ]]
  [[ "$batch" == *"--add item w.popup.1 popup.w"* ]]
  [[ "$batch" == *"--add item w.popup.2 popup.w"* ]]
  [[ "$batch" == *"popup.drawing=on"* ]]
}

@test "each row kind carries its own font and height, not the widget's" {
  export NAME=w SENDER=mouse.clicked BUTTON=left
  run widget 'popup_rows() {
  popup_heading --label "H"
  popup_row --label "R"
  popup_action --label "A"
  popup_note --label "N"
}
on_click() { popup_open; }'
  [ "$status" -eq 0 ]
  local batch
  batch=$(grep -- '--add item' "$SB_LOG")
  [[ "$batch" == *"Test Font:Bold:13"* ]]     # heading
  [[ "$batch" == *"Test Font:Regular:12"* ]]  # row
  [[ "$batch" == *"Test Font:Bold:12"* ]]     # action
  [[ "$batch" == *"Test Font:Italic:10"* ]]   # note
  [[ "$batch" == *"background.height=32"* ]]
  [[ "$batch" == *"background.height=25"* ]]
  [[ "$batch" == *"background.height=20"* ]]
}

@test "every row closes the popup, and an action runs BEFORE that close" {
  export NAME=w SENDER=mouse.clicked BUTTON=left
  run widget 'popup_rows() {
  popup_note --label "just an aside"
  popup_action --label "Refresh" --run "/bin/echo hi"
}
on_click() { popup_open; }'
  [ "$status" -eq 0 ]
  local batch
  batch=$(grep -- '--add item' "$SB_LOG")
  [[ "$batch" == *"click_script=/bin/echo hi; "*"popup.drawing=off"* ]]
  # The note has no action of its own, so its click_script is the close alone.
  [[ "$batch" == *"click_script="*"--set w popup.drawing=off"* ]]
}

@test "a quote in a row's data cannot escape into the click_script" {
  export NAME=w SENDER=mouse.clicked BUTTON=left
  run widget 'popup_rows() { popup_row --label "x" --open "https://e.com/a'"'"'; touch /tmp/pwned; #"; }
on_click() { popup_open; }'
  [ "$status" -eq 0 ]
  [ ! -e /tmp/pwned ]
  grep -q "open 'https://e.com/a'\\\\''; touch /tmp/pwned; #'" "$SB_LOG"
}

@test "a heading with no count says its title alone" {
  export NAME=w SENDER=mouse.clicked BUTTON=left
  run widget 'popup_rows() { popup_heading --label "Open PRs" --count 0; }
on_click() { popup_open; }'
  [ "$status" -eq 0 ]
  grep -q 'label=Open PRs ' "$SB_LOG"
  ! grep -q 'Open PRs · ' "$SB_LOG"
}

@test "closing does not rebuild the rows" {
  export NAME=w SENDER=mouse.clicked BUTTON=left SB_POPUP_DRAWING=on
  run widget 'popup_rows() { popup_row --label "should not be built"; }
on_click() { popup_toggle; }'
  [ "$status" -eq 0 ]
  ! grep -q -- '--add item' "$SB_LOG"
  ! grep -q -- '--remove' "$SB_LOG"
  grep -q 'popup.drawing=off' "$SB_LOG"
}

@test "an unanswered query opens rather than closing" {
  # SB_POPUP_DRAWING unset: the stub jq prints an empty line, which is what a
  # busy bar returns. Treating that as `on` would swallow the click.
  export NAME=w SENDER=mouse.clicked BUTTON=left
  run widget 'popup_rows() { popup_row --label "built"; }
on_click() { popup_toggle; }'
  [ "$status" -eq 0 ]
  grep -q -- '--add item w.popup.0' "$SB_LOG"
}

@test "a popup row re-entering the widget lands on the pill, not the row" {
  # sketchybar exports NAME as the CLICKED item, which for the Refresh row is
  # w.popup.7 — every --set after that would hit a 25pt row.
  export NAME=w.popup.7 SENDER=routine
  run widget 'fetch() { emit n=1; }
render() { pill --icon "" --label "3"; }'
  [ "$status" -eq 0 ]
  grep -q -- '--set w ' "$SB_LOG"
  ! grep -q -- '--set w.popup.7' "$SB_LOG"
}

@test "barlib_tick repaints from a handler that changed the world" {
  export NAME=w SENDER=mouse.clicked BUTTON=right
  run widget 'fetch() { emit n=1; }
render() { pill --icon "" --label "fresh"; }
on_right_click() { barlib_tick; }'
  [ "$status" -eq 0 ]
  grep -q 'label=fresh' "$SB_LOG"
}
