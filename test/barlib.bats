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
  # colors.sh carries the TONE_* ladder AND the MARK_* set the generated file
  # exports (the real ones are modules/bar/tones.nix and modules/bar/marks.nix,
  # and `bar-tones` / `bar-marks` diff these names against them — a rung or a
  # mark added there and not here paints grey in every test), bar.sh sets
  # $SB / $BAR_TOP / $BAR_BOTTOM the way the generated router does.
  cat >"$HOME/.config/sketchybar/colors.sh" <<EOF
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
EOF
  cat >"$HOME/.config/sketchybar/sizes.sh" <<'EOF'
export BAR_FONT="Test Font"
export FS_ICON=14
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

# widget_raw <body> — the same, but the body is the WHOLE script: no
# barlib_main is appended. For the CLI-mode shape, where a widget dispatches on
# its own argv and must never fall through to the runtime's SENDER routing.
widget_raw() {
  local f="$BATS_TEST_TMPDIR/widget.sh"
  {
    printf '#!/bin/bash\nsource "%s"\n' "$BARLIB"
    printf '%s\n' "$1"
  } >"$f"
  chmod +x "$f"
  bash "$f" "${@:2}"
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

@test "the two dim steps are two colours — mute is off, dim is quiet" {
  export NAME=w SENDER=routine
  run widget 'fetch() { emit n=1; }
render() { pill --icon "" --tone dim --label "3" --label-tone mute; }'
  [ "$status" -eq 0 ]
  grep -q 'icon.color=0xff1a1a1a' "$SB_LOG"
  grep -q 'label.color=0xff111111' "$SB_LOG"
}

@test "watch is its own rung between ok and warn, not either of them" {
  export NAME=w SENDER=routine
  # Deliberately NOT `run`: bats folds the command's stderr into $output, so a
  # `2>file` on the `run` line captures nothing and every assertion against
  # that file passes vacuously. The unknown-tone test above calls `widget`
  # bare for the same reason — copy that shape, not this one's absence.
  widget 'fetch() { emit n=1; }
render() { pill --icon "" --tone watch; }' 2>"$BATS_TEST_TMPDIR/err"
  grep -q 'icon.color=0xff3a3a3a' "$SB_LOG"
  # Its own colour, and not reached through the unknown-tone fallback — which
  # paints mute, and is the silent failure this whole check exists to prevent.
  ! grep -q 'unknown tone' "$BATS_TEST_TMPDIR/err"
}

# The regression the `action` rung exists for. `accent` follows
# haus.theme.accent, whose enum contains red/peach/yellow/green/sky — so a verb
# row defaulting there was the alarm colour on those machines and nowhere else,
# which is a bug nobody who did not own one of them could ever see.
@test "a verb row is action, not the theme accent" {
  export NAME=w SENDER=mouse.clicked BUTTON=left
  run widget 'popup_rows() { popup_action --icon "" --label "Refresh" --run "true"; }
on_click() { popup_toggle; }'
  [ "$status" -eq 0 ]
  grep -q 'icon.color=0xff5a5a5a' "$SB_LOG"
  ! grep -q 'icon.color=0xff666666' "$SB_LOG"
}

# A section title with no verdict is still a title. Every hand-written popup in
# the bar draws one overlay1 and reserves overlay0 for the meta row under it.
@test "a heading with no tone is dim, not mute" {
  export NAME=w SENDER=mouse.clicked BUTTON=left
  run widget 'popup_rows() { popup_heading --icon "" --label "Open PRs"; }
on_click() { popup_toggle; }'
  [ "$status" -eq 0 ]
  grep -q 'icon.color=0xff1a1a1a' "$SB_LOG"
  ! grep -q 'icon.color=0xff111111' "$SB_LOG"
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

@test "barlib_tick sends its batch without barlib_main" {
  # A CLI mode calls it and exits; a batch nobody flushes is a pill that
  # silently did not repaint.
  export NAME=w
  run widget_raw 'fetch() { emit n=1; }
render() { pill --icon "X" --label "cli"; }
barlib_tick
exit 0'
  [ "$status" -eq 0 ]
  [ "$(calls)" -eq 1 ]
  grep -q 'label=cli' "$SB_LOG"
}

@test "a CLI mode does not route on an inherited SENDER" {
  # The fork-loop shape: a widget detaches a copy of itself from a click, so
  # the child inherits SENDER=mouse.clicked BUTTON=right. A child that reached
  # barlib_main would land back in the handler that spawned it and spawn
  # again — unbounded, and past every lock the parent already released.
  export NAME=w SENDER=mouse.clicked BUTTON=right
  run widget_raw 'fetch() { emit n=1; }
render() { pill --icon "X" --label "did the work"; }
on_right_click() { echo LOOPED >&2; }
barlib_tick
exit 0'
  [ "$status" -eq 0 ]
  [[ "$output" != *LOOPED* ]]
  grep -q 'label=did the work' "$SB_LOG"
}

# ---- the graph --------------------------------------------------------------
# Every one of these pins a promise whose breach is invisible on the machine:
# a graph that stops advancing looks exactly like a quiet one, and a graph the
# pointer advances looks like history.

@test "graph pushes a clamped fraction on the same batch as the pill" {
  NAME=w SENDER=routine widget '
    fetch() { graph 41.2; emit pct=41; }
    render() { pill --icon C --label "${pct}%"; }
  '
  [ "$(calls)" = 1 ]
  grep -q -- '--push w 0.41' "$SB_LOG"
  grep -q 'label=41%' "$SB_LOG"
}

@test "a graph point still goes out on a tick the diff threw away" {
  # THE reason graph belongs in fetch. A machine sitting at one number emits
  # identical state tick after tick and render never runs — but the rolling
  # window has to keep advancing, or a quiet stretch and a stalled pill draw
  # the same flat line.
  for _ in 1 2 3; do
    NAME=w SENDER=routine widget '
      fetch() { graph 3; emit pct=3; }
      render() { pill --label "${pct}%"; }
    '
  done
  [ "$(calls)" = 3 ]
  [ "$(grep -c -- '--push w 0.03' "$SB_LOG")" = 3 ]
  # ...and the label was painted exactly once, on the first tick.
  [ "$(grep -c 'label=3%' "$SB_LOG")" = 1 ]
}

@test "a click pushes no graph point" {
  # The graph has no time axis of its own — it is the last N values, evenly
  # spaced — so a point pushed by the POINTER shoves the history sideways at
  # the speed of a mouse. A mouse event never reaches fetch, which is what
  # makes that unreachable rather than merely discouraged.
  NAME=w SENDER=mouse.clicked widget '
    fetch() { graph 50; emit pct=50; }
    render() { pill --label "${pct}%"; }
    on_click() { sb_set label=clicked; }
  '
  ! grep -q -- '--push' "$SB_LOG"
}

@test "graph clamps out of range values instead of drawing off the pill" {
  # sketchybar scales a pushed value against the item height and nothing else,
  # so >1 is drawn off the top and <0 vanishes — neither of which reads as an
  # error.
  NAME=w SENDER=routine widget 'fetch() { graph 250; emit n=1; }; render() { :; }'
  NAME=w SENDER=routine widget 'fetch() { graph -12; emit n=2; }; render() { :; }'
  grep -q -- '--push w 1.00' "$SB_LOG"
  grep -q -- '--push w 0.00' "$SB_LOG"
}

# ---- the value column -------------------------------------------------------

@test "popup_row --value puts the name left of a value on its own column" {
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() { popup_row --label user --value "12%"; }
    on_click() { popup_open; }
  '
  grep -q 'icon=user' "$SB_LOG"
  grep -q 'label=12%' "$SB_LOG"
  # A pixel padding, never trailing spaces: sketchybar sizes an item from its
  # TRIMMED label and then draws the untrimmed string, so a space-padded row
  # is clipped by exactly the width of its own padding.
  grep -qE 'icon\.padding_right=[0-9]+' "$SB_LOG"
  # The name is the bare string — the column is bought with that padding and
  # not by padding the name out, which sketchybar would trim and then clip.
  grep -q 'icon=user icon\.color=' "$SB_LOG"
}

@test "a value row tones the number, not the name" {
  # The name is the question and the value is the answer; a row whose name
  # climbed to `bad` with it would be one row shouting twice.
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() { popup_row --label Safari --value "91%" --tone bad; }
    on_click() { popup_open; }
  '
  grep -q 'label=91% label.color=0xff555555' "$SB_LOG"
  grep -q 'icon=Safari icon.color=0xff1a1a1a' "$SB_LOG"
}

@test "a value row with no tone is a live readout, not an absence" {
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() { popup_row --label load --value "2.1"; }
    on_click() { popup_open; }
  '
  grep -q 'label=2.1 label.color=0xff777777' "$SB_LOG"
}

@test "a name longer than the column keeps a gap rather than a negative pad" {
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() { popup_row --label "a-very-long-process-name-indeed" --value "4%"; }
    on_click() { popup_open; }
  '
  ! grep -qE 'icon\.padding_right=-' "$SB_LOG"
  grep -qE 'icon\.padding_right=[0-9]+' "$SB_LOG"
}

@test "popup_heading --value carries glyph and title in one hue" {
  # They are the same mark; splitting them across the row's two colourable
  # halves would spend the value's colour on a word.
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() { popup_heading --icon C --label CPU --value "41%"; }
    on_click() { popup_open; }
  '
  grep -q 'icon=C CPU' "$SB_LOG"
  grep -q 'label=41%' "$SB_LOG"
}

@test "popup_heading without a value is unchanged" {
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() { popup_heading --icon C --label CPU --count 3; }
    on_click() { popup_open; }
  '
  grep -q 'icon=C ' "$SB_LOG"
  grep -q 'label=CPU · 3' "$SB_LOG"
}

# ---- marks: the identity axis ------------------------------------------------

@test "a mark is not a tone — identity resolves off its own set" {
  # modules/bar/marks.nix, and `bar-marks` pins these names against it the way
  # `bar-tones` pins the ladder. The point of the separate resolver is that a
  # widget CANNOT reach a verdict colour by naming a subject.
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() { popup_heading --icon C --label Claude --mark warm; }
    on_click() { popup_open; }
  '
  grep -q 'icon=C icon.color=0xff7a0001' "$SB_LOG"
}

@test "an unknown mark is plum, not grey — grey means stale" {
  # Same leniency as tone(), one direction different: an unrecognised subject
  # is reporting perfectly well, and grey is what a DEAD feed is painted.
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() { popup_heading --icon C --label Nobody --mark chartreuse; }
    on_click() { popup_open; }
  ' 2>/dev/null
  grep -q 'icon=C icon.color=0xff7a0004' "$SB_LOG"
}

@test "mark and tone are last-wins, so a dead feed keeps its heading grey" {
  # `--mark warm --tone dim` is a widget saying "this is Claude, and its feed
  # is dead" — one heading with two things to say and an order to say them in.
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() {
      popup_heading --icon C --label Claude --mark warm --tone dim
      popup_heading --icon O --label Codex --tone dim --mark teal
    }
    on_click() { popup_open; }
  '
  grep -q 'icon=C icon.color=0xff1a1a1a' "$SB_LOG"
  grep -q 'icon=O icon.color=0xff7a0002' "$SB_LOG"
}

@test "--icon-font draws a glyph in a face the bar does not have" {
  # sketchybar-app-font's :claude: is the shipped case: without this the mark
  # is tofu. It is not a typography flag — the runtime still owns the weight
  # and size of everything else the heading draws.
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() { popup_heading --icon ":claude:" --icon-font "app-font:Regular:16" --label Claude; }
    on_click() { popup_open; }
  '
  grep -q 'icon.font=app-font:Regular:16' "$SB_LOG"
}

@test "a heading naming no font draws exactly as it did before the flag" {
  # The default is spelled out rather than inherited so there is one code path;
  # it has to be byte-identical to sketchybarrc's --default icon.font, or every
  # existing framework heading changes size the day this flag lands.
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() { popup_heading --icon C --label CPU; }
    on_click() { popup_open; }
  '
  grep -q 'icon.font=Test Font:Bold:14' "$SB_LOG"
}

@test "--icon-font is refused rather than ignored on a two-column heading" {
  # Glyph and title share ONE item there, so a glyph-only face would draw the
  # title as tofu. Warned and the glyph kept: a mark in the wrong face gets
  # reported, a missing mark does not.
  NAME=w SENDER=mouse.clicked run widget '
    popup_rows() { popup_heading --icon C --label CPU --icon-font "app-font:Regular:16" --value "41%"; }
    on_click() { popup_open; }
  '
  [[ "$output" == *"--icon-font is ignored with --value"* ]]
  ! grep -q 'icon.font=app-font:Regular:16' "$SB_LOG"
}

# ---- alignment inside the value column ---------------------------------------

# pad_for <value> — the icon.padding_right of the row whose VALUE is <value>.
# Anchored on the value rather than the name because the row chrome carries an
# `icon.padding_right=8 label=` of its own, and the fonts have spaces in them.
pad_for() {
  grep -oE "icon\.padding_right=[0-9]+ label=$1 " "$SB_LOG" |
    head -1 | cut -d= -f2 | cut -d' ' -f1
}

@test "leading blanks in a value right-align it instead of clipping the row" {
  # A label is sized TRIMMED and drawn untrimmed, so ` 7%` loses exactly its
  # own indent off the right edge. The runtime pays for the alignment in the
  # name's right padding instead — the same mechanism the column already is.
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() {
      popup_row --label session --value "  7%"
      popup_row --label weekly  --value " 46%"
      popup_row --label weekly  --value "46%"
    }
    on_click() { popup_open; }
  '
  # The blanks are gone from the label…
  grep -q 'label=7% ' "$SB_LOG"
  grep -q 'label=46% ' "$SB_LOG"
  ! grep -q 'label=  7%' "$SB_LOG"
  # …and what they bought is that the two numbers land on ONE column: two
  # leading blanks on a 7-character name and one on a 6-character name are the
  # same x, which is the whole reason a widget writes `%3s` at all.
  [ "$(pad_for '7%')" -eq "$(pad_for '46%')" ]
  # The same value without them sits further left, so the padding is real and
  # not a constant that happens to match.
  narrow=$(grep -oE 'icon\.padding_right=[0-9]+ label=46% ' "$SB_LOG" | tail -1 | cut -d= -f2 | cut -d' ' -f1)
  [ "$(pad_for '46%')" -gt "$narrow" ]
}

@test "an empty --label is a continuation row under the one above it" {
  # The second line of a token block: no name, and the value still lands on
  # the column. It needs no branch of its own — an empty icon still reserves
  # its padding — but a widget has to be able to rely on that.
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() {
      popup_row --label tokens --value "220Md"
      popup_row --label "" --value "590Mm"
    }
    on_click() { popup_open; }
  '
  grep -q 'label=220Md ' "$SB_LOG"
  grep -q 'label=590Mm ' "$SB_LOG"
  # The nameless row buys back exactly the width the name would have taken, so
  # its value starts where the value above it does rather than at the indent.
  [ "$(pad_for '590Mm')" -gt "$(pad_for '220Md')" ]
  grep -q 'icon= icon.color=0xff1a1a1a' "$SB_LOG"
}

@test "a heading greys as a BLOCK, mark and title together" {
  # `--tone dim` alone reaches only the glyph, because the title is a separate
  # colourable half. A dim mark under a full-brightness name reads as a
  # rendering bug rather than as a feed that stopped reporting — which is what
  # ai_usage's hand-written header took a fifth argument for.
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() { popup_heading --icon O --label Codex --tone dim --label-tone dim; }
    on_click() { popup_open; }
  '
  grep -q 'icon=O icon.color=0xff1a1a1a' "$SB_LOG"
  grep -q 'label=Codex label.color=0xff1a1a1a' "$SB_LOG"
}

@test "a heading that names no label tone is the ordinary foreground" {
  # The default has to stay TEXT, or every heading github/cpu/memory already
  # draw changes colour the day the flag lands.
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() { popup_heading --icon C --label CPU --tone warn; }
    on_click() { popup_open; }
  '
  grep -q 'icon=C icon.color=0xff444444' "$SB_LOG"
  grep -q 'label=CPU label.color=0xff777777' "$SB_LOG"
}

# ---- the scrubber -----------------------------------------------------------
# The one row kind that is a CONTROL. Everything here is about the two ways it
# differs from a menu item, both of which fail silently: an `--add item` slider
# is an ordinary row with no track in it, and a slider that closes the popup is
# a scrubber you can only aim once.

@test "a slider is an --add slider with a width, not an --add item" {
  export NAME=w SENDER=mouse.clicked BUTTON=left
  run widget 'popup_rows() { popup_slider --percentage 40 --width 150; }
on_click() { popup_open; }'
  [ "$status" -eq 0 ]
  grep -q -- '--add slider w.popup.0 popup.w 150' "$SB_LOG"
  ! grep -q -- '--add item w.popup.0' "$SB_LOG"
}

@test "a slider does NOT close the popup, and every other row still does" {
  export NAME=w SENDER=mouse.clicked BUTTON=left
  run widget 'popup_rows() {
  popup_slider --percentage 10 --run "/bin/echo seek"
  popup_row --label "R" --run "/bin/echo row"
}
on_click() { popup_open; }'
  [ "$status" -eq 0 ]
  local batch
  batch=$(grep -- '--add slider' "$SB_LOG")
  # Scrubbing is something you do twice. The slider carries its action ALONE.
  [[ "$batch" == *"click_script=/bin/echo seek "* ]]
  [[ "$batch" != *"click_script=/bin/echo seek; "* ]]
  # The ordinary row beside it is unchanged — the exception is the kind's, not
  # a flag any row can reach for.
  [[ "$batch" == *"click_script=/bin/echo row; "*"popup.drawing=off"* ]]
}

@test "a slider subscribes to mouse.clicked, which is what makes PERCENTAGE" {
  export NAME=w SENDER=mouse.clicked BUTTON=left
  run widget 'popup_rows() { popup_slider --percentage 50; }
on_click() { popup_open; }'
  [ "$status" -eq 0 ]
  grep -q -- '--subscribe w.popup.0 mouse.clicked' "$SB_LOG"
}

@test "a slider percentage is 0-100, clamped, and never a fraction" {
  export NAME=w SENDER=mouse.clicked BUTTON=left
  run widget 'popup_rows() {
  popup_slider --percentage 140
  popup_slider --percentage ""
}
on_click() { popup_open; }'
  [ "$status" -eq 0 ]
  local batch
  batch=$(grep -- '--add slider' "$SB_LOG")
  [[ "$batch" == *"slider.percentage=100"* ]]
  [[ "$batch" == *"slider.percentage=0"* ]]
  # graph's 0…1 fraction next door is the trap this pins: 100, not 1.00.
  [[ "$batch" != *"slider.percentage=1.00"* ]]
}

@test "a slider's fill takes a mark, and the track stays the runtime's groove" {
  export NAME=w SENDER=mouse.clicked BUTTON=left
  run widget 'popup_rows() { popup_slider --percentage 50 --mark teal; }
on_click() { popup_open; }'
  [ "$status" -eq 0 ]
  local batch
  batch=$(grep -- '--add slider' "$SB_LOG")
  [[ "$batch" == *"slider.highlight_color=0xff7a0002"* ]]
  [[ "$batch" == *"slider.knob.color=0xff7a0002"* ]]
  [[ "$batch" == *"slider.background.color=0xffbbbbbb"* ]]
}

@test "a slider with no colour is action — a thing you reach for" {
  export NAME=w SENDER=mouse.clicked BUTTON=left
  run widget 'popup_rows() { popup_slider --percentage 50; }
on_click() { popup_open; }'
  [ "$status" -eq 0 ]
  grep -q 'slider.highlight_color=0xff5a5a5a' "$SB_LOG"
}

# ---- a picture --------------------------------------------------------------

@test "popup_image sizes a well and offsets a corner mark, never both" {
  export NAME=w SENDER=mouse.clicked BUTTON=left
  run widget 'popup_rows() {
  popup_image --source /tmp/cover.png --box 84 --scale 0.16
  popup_image --source app.Zen --box 28 --scale 0.9 --pad-left 140
}
on_click() { popup_open; }'
  [ "$status" -eq 0 ]
  local batch
  batch=$(grep -- '--add item' "$SB_LOG")
  [[ "$batch" == *"--set w.popup.0 width=84"* ]]
  [[ "$batch" != *"--set w.popup.0 background.image.padding_left"* ]]
  [[ "$batch" == *"--set w.popup.1 background.image.padding_left=140"* ]]
  [[ "$batch" != *"--set w.popup.1 width="* ]]
  [[ "$batch" == *"background.image=/tmp/cover.png"* ]]
  [[ "$batch" == *"background.image=app.Zen"* ]]
}

@test "popup_image with no box draws nothing rather than a zero-height row" {
  # A box is the row's HEIGHT too, so a missing one is not a small picture —
  # it is an invisible row that reads as "the cover didn't load".
  export NAME=w SENDER=mouse.clicked BUTTON=left
  run widget 'popup_rows() { popup_image --source /tmp/cover.png; }
on_click() { popup_open; }'
  [ "$status" -eq 0 ]
  [[ "$output" == *"--box <points> is required"* ]]
  ! grep -q -- '--add item w.popup.0' "$SB_LOG"
}

@test "popup_image with no source draws nothing rather than an empty box" {
  export NAME=w SENDER=mouse.clicked BUTTON=left
  run widget 'popup_rows() { popup_image --box 84; }
on_click() { popup_open; }'
  [ "$status" -eq 0 ]
  [[ "$output" == *"no --source"* ]]
  ! grep -q -- '--add item w.popup.0' "$SB_LOG"
}

# ---- reaching a row again ---------------------------------------------------

@test "POPUP_ID names the row just added, and popup_set reaches it" {
  export NAME=w SENDER=mouse.clicked BUTTON=left
  run widget 'popup_rows() {
  popup_row --label "first"
  popup_row --label "second"
  MINE="$POPUP_ID"
}
on_click() { popup_open; popup_set "$MINE" background.image.padding_left=99; }'
  [ "$status" -eq 0 ]
  grep -q -- '--set w.popup.1 background.image.padding_left=99' "$SB_LOG"
}

@test "popup_set with no row id warns instead of setting the whole bar" {
  export NAME=w SENDER=mouse.clicked BUTTON=left
  run widget 'on_click() { popup_set "" label=nope; }'
  [ "$status" -eq 0 ]
  [[ "$output" == *"no row id"* ]]
  [ "$(calls)" = 0 ]
}

@test "a click from a popup row leaves its id in POPUP_CLICKED" {
  # The seek's whole mechanism: a click_script is a SPAWN, so the fresh process
  # knows which slider it belongs to only from the NAME the runtime strips.
  export NAME=w.popup.3 SENDER=mouse.clicked BUTTON=left PERCENTAGE=64
  run widget 'on_click() { popup_set "$POPUP_CLICKED" slider.percentage="$PERCENTAGE"; }'
  [ "$status" -eq 0 ]
  grep -q -- '--set w.popup.3 slider.percentage=64' "$SB_LOG"
}

# ---- a long label -----------------------------------------------------------

@test "--max-chars caps a row and --marquee is what makes it sweep" {
  export NAME=w SENDER=mouse.clicked BUTTON=left
  run widget 'popup_rows() {
  popup_heading --label "a very long title indeed" --max-chars 30 --marquee
  popup_row --label "artist — album" --max-chars 30
}
on_click() { popup_open; }'
  [ "$status" -eq 0 ]
  local batch
  batch=$(grep -- '--add item' "$SB_LOG")
  [[ "$batch" == *"--set w.popup.0 label.max_chars=30 --set w.popup.0 scroll_texts=on"* ]]
  # The cap without the motion: reduceMotion turns the sweep off and the row
  # clips, which it can only do if the two are separate properties.
  [[ "$batch" == *"--set w.popup.1 label.max_chars=30"* ]]
  [[ "$batch" != *"--set w.popup.1 scroll_texts"* ]]
}

@test "a row that names neither is untouched, not capped at zero" {
  export NAME=w SENDER=mouse.clicked BUTTON=left
  run widget 'popup_rows() { popup_row --label "R"; }
on_click() { popup_open; }'
  [ "$status" -eq 0 ]
  ! grep -q 'label.max_chars' "$SB_LOG"
  ! grep -q 'scroll_texts' "$SB_LOG"
}

# ---- the pill's own identity ------------------------------------------------

@test "pill --mark paints the glyph off the identity axis, not the ladder" {
  NAME=w SENDER=routine widget '
    fetch() { emit m=violet; }
    render() { pill --icon P --label x --mark "$m"; }
  '
  grep -q 'icon.color=0xff7a0003' "$SB_LOG"
}

@test "pill --mark and --tone are last-wins, so a paused pill greys" {
  NAME=w SENDER=routine widget '
    fetch() { emit n=1; }
    render() { pill --icon P --label x --mark plum --tone dim; }
  '
  grep -q 'icon.color=0xff1a1a1a' "$SB_LOG"
  ! grep -q 'icon.color=0xff7a0004' "$SB_LOG"
}

# ---- the detached half ------------------------------------------------------

@test "sb_now sends immediately, where sb_set would ride a batch nobody flushes" {
  export NAME=w SENDER=mouse.entered
  run widget 'on_hover() { ( sb_now scroll_texts=off ) & wait; }'
  [ "$status" -eq 0 ]
  grep -q -- '--set w scroll_texts=off' "$SB_LOG"
}

# ---- the pointer leaving --------------------------------------------------

@test "mouse.exited.global lands on on_unhover too" {
  # The per-item event is MISSED when the pointer is flicked straight off the
  # bar, and a widget whose hover state is a latch is then stuck in it.
  export NAME=w SENDER=mouse.exited.global
  run widget 'on_unhover() { sb_set label.drawing=off; }'
  [ "$status" -eq 0 ]
  grep -q -- '--set w label.drawing=off' "$SB_LOG"
}

# ---- segmented pills --------------------------------------------------------
# A `segments =` header makes the pill a BRACKET over a head item and N
# segments (modules/bar/manifest.nix). $BARLIB_SEGMENTS is how the emitter
# tells the running script, and everything below is what changes when it is
# set. Each of these fails silently on a real bar: a --set at an item that
# does not exist is accepted without a word, and a popup on the wrong item
# opens hanging off the side of its own pill.

@test "segment paints icon and label on <name>.<seg> in ONE tone" {
  NAME=agents BARLIB_SEGMENTS="ready working done" SENDER=routine widget '
    fetch() { emit n=2; }
    render() { segment ready --icon "?" --label "$n" --tone bad; }
  '
  grep -q -- '--set agents.ready drawing=on' "$SB_LOG"
  grep -q -- '--set agents.ready icon=?' "$SB_LOG"
  grep -q -- '--set agents.ready label=2' "$SB_LOG"
  # One tone, both halves: the glyph and the count are the same answer.
  grep -q -- '--set agents.ready icon.color=0xff555555 label.color=0xff555555' "$SB_LOG"
}

@test "segment --hide is drawing=off ALONE — the updates door is the head's" {
  NAME=agents BARLIB_SEGMENTS="ready working done" SENDER=routine widget '
    fetch() { emit n=0; }
    render() { segment working --hide; }
  '
  grep -q -- '--set agents.working drawing=off' "$SB_LOG"
  ! grep -q -- '--set agents.working drawing=off updates=on' "$SB_LOG"
}

@test "a segment name not in the header is dropped, not sent" {
  NAME=agents BARLIB_SEGMENTS="ready working done" SENDER=routine widget '
    fetch() { emit n=1; }
    render() { segment redy --icon x --label 1 --tone ok; }
  ' 2>"$BATS_TEST_TMPDIR/err"
  ! grep -q 'agents.redy' "$SB_LOG"
  grep -q "is not in segments" "$BATS_TEST_TMPDIR/err"
}

@test "pill takes the bracket up and down with the head" {
  NAME=agents BARLIB_SEGMENTS="ready working done" SENDER=routine widget '
    fetch() { emit n=1; }
    render() { pill --hide; }
  '
  # An all-hidden bracket still paints its own background, so hiding the
  # members is not enough — the pill behind them has to go too.
  grep -q -- '--set agents drawing=off updates=on' "$SB_LOG"
  grep -q -- '--set agents.pill drawing=off' "$SB_LOG"
}

@test "a shown pill shows its bracket" {
  NAME=agents BARLIB_SEGMENTS="ready working done" SENDER=routine widget '
    fetch() { emit n=1; }
    render() { pill --icon B --tone ok; }
  '
  grep -q -- '--set agents drawing=on' "$SB_LOG"
  grep -q -- '--set agents.pill drawing=on' "$SB_LOG"
}

@test "an unsegmented pill never mentions a bracket" {
  NAME=w SENDER=routine widget 'fetch() { emit n=1; }; render() { pill --hide; }'
  ! grep -q 'w.pill' "$SB_LOG"
}

@test "popup rows hang off the BRACKET, not the head" {
  NAME=agents BARLIB_SEGMENTS="ready working done" SENDER=mouse.clicked widget '
    popup_rows() { popup_heading --label Agents; }
    on_click() { popup_open; }
  '
  grep -q -- '--add item agents.pill.popup.0 popup.agents.pill' "$SB_LOG"
  grep -q -- '--set agents.pill popup.drawing=on' "$SB_LOG"
  ! grep -q -- 'popup.agents ' "$SB_LOG"
}

@test "a row's close targets the bracket too" {
  NAME=agents BARLIB_SEGMENTS="ready working done" SENDER=mouse.clicked widget '
    popup_rows() { popup_row --label go --run "true"; }
    on_click() { popup_open; }
  '
  grep -q 'click_script=true; .* --set agents.pill popup.drawing=off' "$SB_LOG"
}

@test "a segment's click arrives as the HEAD, not as the segment" {
  # sketchybar exports the item that was touched, and the emitter gives each
  # segment a click_script. Every --set after that would land on a segment.
  NAME=agents.ready BARLIB_SEGMENTS="ready working done" SENDER=mouse.clicked widget '
    on_click() { sb_set label=clicked; }
  '
  grep -q -- '--set agents label=clicked' "$SB_LOG"
  ! grep -q -- '--set agents.ready label=clicked' "$SB_LOG"
}

@test "a popup row on a segmented pill strips back past the bracket" {
  NAME=agents.pill.popup.3 BARLIB_SEGMENTS="ready working done" SENDER=mouse.clicked widget '
    on_click() { sb_set label=row; }
  '
  grep -q -- '--set agents label=row' "$SB_LOG"
}

@test "the head's own id survives a segment-shaped suffix it does not own" {
  # Stripped by NAME, not at the first dot: a blind %%.* would eat a head id
  # that legitimately carries one.
  NAME=media_lib.foo BARLIB_SEGMENTS="ready working done" SENDER=mouse.clicked widget '
    on_click() { sb_set label=x; }
  '
  grep -q -- '--set media_lib.foo label=x' "$SB_LOG"
}

@test "popup_toggle asks the bracket whether the dropdown is up" {
  SB_POPUP_DRAWING=on NAME=agents BARLIB_SEGMENTS="ready working done" \
    SENDER=mouse.clicked widget '
    popup_rows() { popup_heading --label Agents; }
    on_click() { popup_toggle; }
  '
  # Open → it must CLOSE, and never rebuild the rows on the way out.
  grep -q -- '--set agents.pill popup.drawing=off' "$SB_LOG"
  ! grep -q 'agents.pill.popup.0' "$SB_LOG"
}

# ---- the two-answer row and the clickable heading ---------------------------

@test "popup_row --name-tone colours the name half" {
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() { popup_row --label "working · 12m" --name-tone busy --value "+2" --tone warn; }
    on_click() { popup_open; }
  '
  # name in busy, value in warn — two answers, not a question and an answer.
  grep -q 'icon.color=0xff333333' "$SB_LOG"
  grep -q 'label.color=0xff444444' "$SB_LOG"
}

@test "a --value row still dims its name by default" {
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() { popup_row --label user --value 42 --tone ok; }
    on_click() { popup_open; }
  '
  grep -q 'icon.color=0xff1a1a1a' "$SB_LOG"
}

@test "popup_heading --run makes the heading a click target" {
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() { popup_heading --label Lane --run "do-thing"; }
    on_click() { popup_open; }
  '
  grep -q 'click_script=do-thing; ' "$SB_LOG"
}

@test "a heading with no --run still just closes" {
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() { popup_heading --label Lane; }
    on_click() { popup_open; }
  '
  ! grep -q 'click_script=; ' "$SB_LOG"
  grep -q 'click_script=.* --set w popup.drawing=off' "$SB_LOG"
}
