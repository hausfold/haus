#!/usr/bin/env bats
# Hermetic tests for modules/bar/sketchybar/barlib.sh — the bar widget runtime
# (hausfold.co/docs/haus/rooms/bar-widgets).
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
  # mark added there and not here paints grey in every test), then tone() and
  # mark() themselves, appended from test/colors-fns.sh exactly as the
  # generated colors.sh carries them (`bar-tones` byte-diffs that file
  # against the emitter, modules/bar/colors-fns.nix), so the suite resolves
  # colours through the very code a real bar does. bar.sh sets $SB /
  # $BAR_TOP / $BAR_BOTTOM the way the generated router does.
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
export BAR_SCALE=1
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

@test "a colors.sh too old to carry tone()/mark() paints mute and plum, not a crash" {
  # The generation-skew window barlib's own guard exists for: colors.sh and
  # barlib.sh are separate home.file entries landing in either order, so a
  # widget can source a colors.sh from before the functions moved there. It
  # must degrade to the grey the leniency doctrine promises — never die on
  # `command not found` mid-render, which would take the whole batched --add
  # with it. Heals at the activation-end bar reload.
  #
  # Plain assignments, not `export`: everything here is read in-shell, and
  # `bar-tones` / `bar-marks` extract setup()'s stub from this file by the
  # `export TONE_*` shape — an exported line here would ride into that diff.
  cat >"$HOME/.config/sketchybar/colors.sh" <<'EOF'
FLAMINGO=0xffeebbcc
TONE_MUTE=0xff111111
MARK_PLUM=0xff7a0004
EOF
  NAME=w SENDER=routine widget 'fetch() { emit x=1; }
render() { pill --icon X --tone ok --label y --label-tone text; }'
  grep -q 'icon.color=0xff111111' "$SB_LOG"
  grep -q 'label.color=0xff111111' "$SB_LOG"
  rm -f "$SB_LOG"
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() { popup_heading --icon C --label Claude --mark warm; }
    on_click() { popup_open; }
  '
  grep -q 'icon=C icon.color=0xff7a0004' "$SB_LOG"
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
  [[ "$batch" == *"background.height=34"* ]]
  [[ "$batch" == *"background.height=26"* ]]
  [[ "$batch" == *"background.height=18"* ]]
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

@test "popup_row --value puts the name left and the value flush right" {
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() { popup_row --label user --value "12%"; }
    on_click() { popup_open; }
  '
  grep -q 'icon=user' "$SB_LOG"
  grep -q 'label=12%' "$SB_LOG"
  # The value slot is a fixed width sized from the value, right-aligned in
  # it: that is what lands every value on the gutter whatever the name did.
  # Never trailing spaces — sketchybar sizes an item from its TRIMMED label
  # and then draws the untrimmed string.
  grep -qE 'label\.width=[0-9]+ label\.align=right' "$SB_LOG"
  # The name is the bare string in a slot that takes the rest of the row.
  grep -q 'icon=user icon\.color=' "$SB_LOG"
  grep -qE 'icon\.width=[0-9]+ icon\.align=left' "$SB_LOG"
}

@test "a value row tones the number, not the name" {
  # The name is the question and the value is the answer; a row whose name
  # climbed to `bad` with it would be one row shouting twice.
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() { popup_row --label Safari --value "91%" --tone bad; }
    on_click() { popup_open; }
  '
  grep -qE 'label=91% label\.font=[^ ]+( [^ ]+)* label\.color=0xff555555' "$SB_LOG"
  grep -q 'icon=Safari icon.color=0xff1a1a1a' "$SB_LOG"
}

@test "a value row with no tone is a live readout, not an absence" {
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() { popup_row --label load --value "2.1"; }
    on_click() { popup_open; }
  '
  grep -qE 'label=2.1 label\.font=[^ ]+( [^ ]+)* label\.color=0xff777777' "$SB_LOG"
}

@test "a name longer than its slot is cut with an ellipsis, never spilled" {
  # SketchyBar's max_chars cuts and says nothing; the runtime cuts by
  # character and spends one column on saying so.
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() { popup_row --label "a-very-long-process-name-indeed-and-then-some-more-words" --value "4%"; }
    on_click() { popup_open; }
  '
  grep -q 'icon=a-very-long-process-name-indeed' "$SB_LOG"
  grep -q '…' "$SB_LOG"
  ! grep -q 'some-more-words' "$SB_LOG"
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

@test "a heading naming no font draws its glyph at the label size" {
  # The default is spelled out rather than inherited so there is one code
  # path: the glyph sits in a 20pt well, and the bar's own 17pt icon face
  # would overflow it.
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() { popup_heading --icon C --label CPU; }
    on_click() { popup_open; }
  '
  grep -q 'icon.font=Test Font:Bold:13' "$SB_LOG"
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

@test "leading blanks in a value are dropped — the slot right-aligns instead" {
  # A label is sized TRIMMED and drawn untrimmed, so ` 7%` would lose exactly
  # its own indent off the right edge. A widget that wrote `%3s` to line its
  # numbers up gets the same column from the slot's own alignment.
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() {
      popup_row --label session --value "  7%"
      popup_row --label weekly  --value " 46%"
    }
    on_click() { popup_open; }
  '
  grep -q 'label=7% ' "$SB_LOG"
  grep -q 'label=46% ' "$SB_LOG"
  ! grep -q 'label=  7%' "$SB_LOG"
  [ "$(grep -o 'label.align=right' "$SB_LOG" | wc -l)" -ge 2 ]
}

@test "an empty --label is a continuation row under the one above it" {
  # The second line of a token block: no name, and the value still lands on
  # the column. It needs no branch of its own — an empty icon still holds its
  # slot — but a widget has to be able to rely on that.
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() {
      popup_row --label tokens --value "220Md"
      popup_row --label "" --value "590Mm"
    }
    on_click() { popup_open; }
  '
  grep -q 'label=220Md ' "$SB_LOG"
  grep -q 'label=590Mm ' "$SB_LOG"
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

@test "a heading's title wears its hue, glyph and title together" {
  # The colour a converted dropdown lost: a section title in the same hue as
  # its glyph, which is what every hand-written popup drew and the first
  # framework cut of this file painted TEXT.
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() { popup_heading --icon C --label CPU --tone warn; }
    on_click() { popup_open; }
  '
  grep -q 'icon=C icon.color=0xff444444' "$SB_LOG"
  grep -q 'label=CPU label.color=0xff444444' "$SB_LOG"
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
  [[ "$batch" == *"--set w.popup.1 width=dynamic background.image.padding_left=140"* ]]
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
  grep -q -- '--set agents.pill popup.height=1 popup.drawing=on' "$SB_LOG"
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

# ---- the segment list has to survive a DIRECT invocation --------------------
# The pill's primary update path is not sketchybar's. agents-hook.sh runs the
# reader itself (`SENDER=refresh NAME=agents "$reader"`) on every agent state
# change, so anything carried on `script=`'s command line is absent exactly
# where the pill learns the most. These pin the file-read that replaced it.

@test "a direct invocation still finds segments, from the widget's own header" {
  # No BARLIB_SEGMENTS in the environment — the hook's shape.
  NAME=agents SENDER=refresh widget '
# widget: segments = ready, working, done
    fetch() { emit n=1; }
    render() { pill --icon B --tone ok; segment ready --icon "?" --label "$n" --tone bad; }
  '
  grep -q -- '--set agents.pill drawing=on' "$SB_LOG"
  grep -q -- '--set agents.ready drawing=on' "$SB_LOG"
  grep -q -- '--set agents.ready label=1' "$SB_LOG"
}

@test "a direct invocation reaches the bracket's popup too" {
  NAME=agents SENDER=mouse.clicked widget '
# widget: segments = ready, working, done
    popup_rows() { popup_heading --label Agents; }
    on_click() { popup_open; }
  '
  grep -q -- '--add item agents.pill.popup.0 popup.agents.pill' "$SB_LOG"
}

@test "the hide path takes the bracket down on a direct invocation" {
  # The failure this pins: head hidden, bracket and its stale counts left
  # drawn — an empty capsule with numbers in it and no bot.
  NAME=agents SENDER=refresh widget '
# widget: segments = ready, working, done
    fetch() { emit n=0; }
    render() { pill --hide; segment ready --hide; }
  '
  grep -q -- '--set agents drawing=off updates=on' "$SB_LOG"
  grep -q -- '--set agents.pill drawing=off' "$SB_LOG"
  grep -q -- '--set agents.ready drawing=off' "$SB_LOG"
}

@test "a header with no segments key leaves the pill unsegmented" {
  NAME=w SENDER=routine widget '
# widget: interval = 10
    fetch() { emit n=1; }
    render() { pill --hide; }
  '
  ! grep -q 'w.pill' "$SB_LOG"
}

@test "an explicit BARLIB_SEGMENTS still overrides the file" {
  NAME=agents BARLIB_SEGMENTS="ready" SENDER=refresh widget '
# widget: segments = ready, working, done
    fetch() { emit n=1; }
    render() { segment working --icon x --label 1 --tone ok; }
  ' 2>"$BATS_TEST_TMPDIR/err"
  grep -q "is not in segments" "$BATS_TEST_TMPDIR/err"
}

@test "--name-tone without a --value warns instead of doing nothing" {
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() { popup_row --label plain --name-tone busy; }
    on_click() { popup_open; }
  ' 2>"$BATS_TEST_TMPDIR/err"
  grep -q -- "--name-tone needs a --value" "$BATS_TEST_TMPDIR/err"
}

# ---- bar_emit ---------------------------------------------------------------
# The pubsub half, which had no cases at all while it had no producer. It is a
# wrapper over `haus-bar-poke` now (modules/core/haus-bar-poke.sh, and
# test/bar-poke.bats is where the both-bars behaviour itself is pinned), so what
# a widget owes it is narrower: the argv it was given, unmangled, and the two
# failure modes that would otherwise be silent.

# The poke stands in for the binary at its absolute path, which a test cannot
# write to — hence the `_BARLIB_`-prefixed override. That name is deliberately
# inside the reject list's `_BARLIB*` arm: a plain `BARLIB_BAR_POKE` would be a
# name a widget could `emit` over, silently redirecting every bar_emit it makes.
poke_stub() { # poke_stub [exit-status]
  export POKE_LOG="$BATS_TEST_TMPDIR/poke.log"
  cat >"$BATS_TEST_TMPDIR/bin/poke" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >>"$BATS_TEST_TMPDIR/poke.log"
exit ${1:-0}
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/poke"
  export _BARLIB_BAR_POKE="$BATS_TEST_TMPDIR/bin/poke"
}

@test "bar_emit hands the event and its key=value pairs through unchanged" {
  poke_stub
  NAME=w SENDER=routine widget '
    fetch() { emit n=1; }
    render() { bar_emit haus.w.change kind="a b" n=2; }
  '
  [ "$(cat "$BATS_TEST_TMPDIR/poke.log")" = "haus.w.change kind=a b n=2" ]
}

# A widget must never be able to `emit` its way onto the binary this calls.
# `_BARLIB_BAR_POKE` is caught by the reject list's `_BARLIB*` arm, which is
# exactly why the variable wears that prefix rather than a bare BARLIB_ one.
@test "a widget cannot emit over the poke's own variable" {
  poke_stub
  NAME=w SENDER=routine widget '
    fetch() { emit _BARLIB_BAR_POKE=/tmp/hijacked; emit n=1; }
    render() { bar_emit haus.w.change; }
  ' 2>"$BATS_TEST_TMPDIR/err"
  grep -q "is a runtime name — dropped" "$BATS_TEST_TMPDIR/err"
  [ "$(cat "$BATS_TEST_TMPDIR/poke.log")" = "haus.w.change" ]
}

# The poke sends the bars' own noise to /dev/null itself, so the only thing it
# ever writes to stderr is its usage error — a widget calling bar_emit with no
# event. That has to reach sketchybar's log: swallowed, the bug is found later
# by a pill that never repaints.
@test "bar_emit with no event lets the usage error through" {
  # The REAL script here, not the recorder: the usage error is its behaviour,
  # and a stub asserting it would be asserting itself. Copied because the file
  # in the tree is not executable — nix installs it through
  # `writeShellScriptBin`, which is also what supplies the `@sketchybar@` value.
  install -m 755 "$BATS_TEST_DIRNAME/../modules/core/haus-bar-poke.sh" \
    "$BATS_TEST_TMPDIR/bin/real-poke"
  export _BARLIB_BAR_POKE="$BATS_TEST_TMPDIR/bin/real-poke"
  NAME=w SENDER=routine widget '
    fetch() { emit n=1; }
    render() { bar_emit; }
  ' 2>"$BATS_TEST_TMPDIR/err"
  grep -q "usage: haus-bar-poke <event>" "$BATS_TEST_TMPDIR/err"
}

# ...and it still must not take the widget down with it. Every producer calls
# this as a side effect on something else's success path.
@test "a poke that fails does not fail the render" {
  poke_stub 3
  NAME=w SENDER=routine widget '
    fetch() { emit n=1; }
    render() { bar_emit haus.w.change; pill --icon x --label ok; }
  '
  grep -q -- '--set w ' "$SB_LOG"
}

# ---- the grid ----------------------------------------------------------------
# SketchyBar lays a popup out as a stack of content-width, left-aligned items
# with no alignment property. Every promise below is about the ONE decision
# that turns that into a panel: every row is a fixed-width item, and the two
# text slots are placed inside it. Each fails silently on a real bar — a row
# that lost its width is a ragged edge, a badge without its slot is a capsule
# as wide as the column, a 30pt cell floor is a note twice its height.

# row_args <n> — every --set argument aimed at popup row n on the batched
# add, joined. A row's close is a `--set w popup.drawing=off` INSIDE its
# click_script, so the batch is split only at the runtime's own verbs and at
# a `--set w.popup.<id>`, never at a bare `--set`.
row_args() {
  grep -- '--add' "$SB_LOG" |
    awk '{ gsub(/ --(add|subscribe|push) /, "\n&"); gsub(/ --set w\.popup\.[a-z0-9]+ /, "\n&"); print }' |
    grep -E "^ --set w\.popup\.$1 " | sed -E "s/^ --set w\.popup\.$1 //" | tr '\n' ' '
}

@test "every row is the panel's width, inset from the frame" {
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() {
      popup_heading --icon H --label "Head"
      popup_row --label "row"
      popup_action --label "act"
      popup_note --label "note"
    }
    on_click() { popup_open; }
  '
  local n
  for n in 0 1 2 3; do
    [[ "$(row_args $n)" == *"width=340 padding_left=6 padding_right=6"* ]]
  done
}

@test "popup_width widens the panel for the widget that asks, before the first row" {
  NAME=w SENDER=mouse.clicked widget '
    popup_width 420
    popup_rows() { popup_row --label "a sentence of a title"; }
    on_click() { popup_open; }
  '
  [[ "$(row_args 0)" == *"width=420 "* ]]
}

@test "the grid scales with the type" {
  # haus.ui.scale reaches the type through BAR_SCALE; a panel that did not
  # follow it would be the same panel with bigger words falling off it.
  # In the body rather than the environment: the stub sizes.sh exports its
  # own BAR_SCALE, and the grid is laid lazily at the first row.
  NAME=w SENDER=mouse.clicked widget '
    BAR_SCALE=1.25
    popup_rows() { popup_row --label "r"; }
    on_click() { popup_open; }
  '
  [[ "$(row_args 0)" == *"width=425 "* ]]
  [[ "$(row_args 0)" == *"background.height=33"* ]]
}

@test "every row carries a transparent background of its own height" {
  # A background counts toward an item's height ONLY while it is drawn, so a
  # row with drawing=off is as tall as its text and the popup's cell floor
  # wins. Transparent-and-drawn is what makes the heights real.
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() { popup_note --label "n"; }
    on_click() { popup_open; }
  '
  [[ "$(row_args 0)" == *"background.drawing=on background.color=0x00000000 background.height=18"* ]]
}

@test "opening sets the cell floor to 1 and pads the panel top and bottom" {
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() { popup_row --label "r"; }
    on_click() { popup_open; }
  '
  grep -q -- '--set w popup.height=1 popup.drawing=on' "$SB_LOG"
  grep -q -- '--add item w.popup.top popup.w' "$SB_LOG"
  grep -q -- '--add item w.popup.bottom popup.w' "$SB_LOG"
  # The pads are numbered apart, so the widget's first row is still .popup.0.
  grep -q -- '--add item w.popup.0 popup.w' "$SB_LOG"
  ! grep -q -- 'w.popup.1 ' "$SB_LOG"
  grep -qE -- '--set w\.popup\.(top|bottom) [^-]*background\.height=8' "$SB_LOG"
}

# ---- the widget's own hue ----------------------------------------------------

@test "a heading with no tone wears the mark the widget's header declares" {
  # The colour a converted pill's dropdown lost: the ladder has no rung for
  # "this pill's own colour", so `mark =` in the header is where it lives,
  # read from the file exactly as `segments =` is.
  NAME=w SENDER=mouse.clicked widget '
# widget: mark = teal
    popup_rows() { popup_heading --icon C --label CPU; }
    on_click() { popup_open; }
  '
  grep -q 'icon=C icon.color=0xff7a0002' "$SB_LOG"
  grep -q 'label=CPU label.color=0xff7a0002' "$SB_LOG"
}

@test "a heading's own --tone still beats the header's mark" {
  NAME=w SENDER=mouse.clicked widget '
# widget: mark = teal
    popup_rows() { popup_heading --icon C --label Dead --tone warn; }
    on_click() { popup_open; }
  '
  grep -q 'icon=C icon.color=0xff444444' "$SB_LOG"
}

@test "the header read leaves the widget's own argv alone" {
  # barlib is SOURCED, and its header read word-splits inside a function on
  # purpose: a `set --` at file level would eat the CLI mode github's
  # `refresh` dispatches on after the source.
  NAME=w SENDER=mouse.clicked widget_raw '
# widget: mark = teal
# widget: segments = a, b
    case "${1:-}" in
      refresh) sb_set label=refreshed; barlib_flush; exit 0 ;;
    esac
    barlib_main "$@"
  ' refresh
  grep -q -- '--set w label=refreshed' "$SB_LOG"
}

@test "a glyph on a heading sits in a well of the heading's tint" {
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() { popup_heading --icon C --label CPU --mark teal; }
    on_click() { popup_open; }
  '
  local r
  r=$(row_args 0)
  [[ "$r" == *"icon.background.drawing=on icon.background.color=0x307a0002 icon.background.height=20 icon.background.corner_radius=10"* ]]
  [[ "$r" == *"icon.width=20 icon.align=center"* ]]
}

@test "a heading with no glyph draws no well" {
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() { popup_heading --label "What is using it"; }
    on_click() { popup_open; }
  '
  ! grep -q 'icon.background.drawing=on' "$SB_LOG"
}

# ---- the right column: badge and hint ----------------------------------------

@test "a badge is a capsule in the tone's tint with the tone's words in it" {
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() { popup_row --label pressure --badge critical --badge-tone bad; }
    on_click() { popup_open; }
  '
  local r
  r=$(row_args 0)
  [[ "$r" == *"label=critical label.font=Test Font:Bold:10 label.color=0xff555555"* ]]
  [[ "$r" == *"label.background.drawing=on label.background.color=0x30555555 label.background.height=18 label.background.corner_radius=9"* ]]
  # The capsule HUGS its words: a fixed label.width would make it as wide as
  # the whole column, so the slot is cut from the name side instead.
  [[ "$r" == *"label.width=dynamic"* ]]
  # 8 columns × 7pt (the tiny face), 8pt of padding each side, 4 of slack,
  # and the gutter, taken from the 340 the row has.
  [[ "$r" == *"icon.width=254 icon.align=left"* ]]
}

@test "a heading badge is the heading's own hue unless told otherwise" {
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() {
      popup_heading --icon C --label CPU --mark teal --badge "41%"
      popup_heading --icon M --label Memory --mark teal --badge "6 GB" --badge-tone warn
    }
    on_click() { popup_open; }
  '
  [[ "$(row_args 0)" == *"label=41% label.font=Test Font:Bold:10 label.color=0xff7a0002"* ]]
  [[ "$(row_args 1)" == *"label=6 GB label.font=Test Font:Bold:10 label.color=0xff444444"* ]]
  # A badge takes the label slot, so glyph and title share the icon slot and
  # the well is not drawn — the price of a third thing on a two-slot row.
  [[ "$(row_args 0)" == *"icon=C CPU icon.color=0xff7a0002"* ]]
  ! grep -q 'icon.background.drawing=on' "$SB_LOG"
}

@test "a hint is a tiny dim caption flush right" {
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() { popup_action --icon R --label Refresh --hint "2m ago" --run "true"; }
    on_click() { popup_open; }
  '
  local r
  r=$(row_args 0)
  [[ "$r" == *"label=2m ago label.font=Test Font:Regular:10 label.color=0xff999999"* ]]
  [[ "$r" == *"label.align=right"* ]]
  [[ "$r" == *"icon=R Refresh icon.color=0xff5a5a5a"* ]]
}

# ---- hover -------------------------------------------------------------------

@test "a row that does something lights up under the pointer, one that does not never does" {
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() {
      popup_row --label "go" --run "true"
      popup_row --label "inert"
      popup_heading --label "Lane" --run "true"
      popup_note --label "aside"
    }
    on_click() { popup_open; }
  '
  grep -q -- '--subscribe w.popup.0 mouse.entered mouse.exited' "$SB_LOG"
  grep -q -- '--subscribe w.popup.2 mouse.entered mouse.exited' "$SB_LOG"
  ! grep -q -- '--subscribe w.popup.1 ' "$SB_LOG"
  ! grep -q -- '--subscribe w.popup.3 ' "$SB_LOG"
  # The script swaps the row grey and back, addressed by the $NAME sketchybar
  # exports for the row — no id baked in, so a rebuilt popup keeps it right.
  grep -q 'mouse.entered) .* --set "$NAME" background.color=0xffcccccc' "$SB_LOG"
  grep -q 'mouse.exited) .* --set "$NAME" background.color=0x00000000' "$SB_LOG"
}

# ---- the button --------------------------------------------------------------

@test "a button is a tinted, centred capsule the width of the panel" {
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() { popup_button --icon A --label "Activity Monitor" --run "am"; }
    on_click() { popup_open; }
  '
  local r
  r=$(row_args 0)
  [[ "$r" == *"width=320 align=center padding_left=16 padding_right=16"* ]]
  [[ "$r" == *"label=Activity Monitor label.color=0xff5a5a5a"* ]]
  [[ "$r" == *"background.color=0x305a5a5a background.corner_radius=8"* ]]
  [[ "$r" == *"background.height=28"* ]]
  [[ "$r" == *"click_script=am; "* ]]
  # Hover brightens the tint one step rather than greying the row.
  grep -q 'mouse.entered) .* background.color=0x505a5a5a' "$SB_LOG"
}

@test "a --solid button is the hue itself with the base colour for its words" {
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() { popup_button --label "Allow sleep" --tone bad --solid --run "off"; }
    on_click() { popup_open; }
  '
  local r
  r=$(row_args 0)
  [[ "$r" == *"label=Allow sleep label.color=0xff000000"* ]]
  [[ "$r" == *"background.color=0xff555555"* ]]
  ! grep -q -- '--subscribe w.popup.0 mouse.entered' "$SB_LOG"
}

# ---- the bar and the sparkline -----------------------------------------------

@test "popup_bar is a name line over a track: a slider with no knob and no gesture" {
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() { popup_bar --label "session · resets 14:20" --percentage 38 --value "38%" --tone watch; }
    on_click() { popup_open; }
  '
  # Row 0 is the name and the number, a plain item; row 1 is the track.
  grep -q -- '--add item w.popup.0 popup.w' "$SB_LOG"
  grep -qE -- '--add slider w\.popup\.1 popup\.w [0-9]+' "$SB_LOG"
  local n t
  n=$(row_args 0)
  t=$(row_args 1)
  # The name has the whole line: nothing cut, the number flush right in the tone.
  [[ "$n" == *"icon=session · resets 14:20 "* ]]
  [[ "$n" == *"label=38% label.font=Test Font:Bold:12 label.color=0xff3a3a3a"* ]]
  [[ "$n" == *"label.align=right"* ]]
  [[ "$t" == *"slider.percentage=38"* ]]
  [[ "$t" == *"slider.highlight_color=0xff3a3a3a"* ]]
  [[ "$t" == *"slider.background.color=0xffbbbbbb"* ]]
  [[ "$t" == *"slider.knob= slider.knob.drawing=off"* ]]
  [[ "$t" == *"icon.drawing=off label.drawing=off"* ]]
  [[ "$t" == *"background.height=12"* ]]
  # A readout closes like a row and never subscribes: the one thing that
  # separates it from popup_slider.
  ! grep -q -- '--subscribe w.popup.1 mouse.clicked' "$SB_LOG"
  [[ "$t" == *"click_script="*"popup.drawing=off"* ]]
}

@test "every bar's track runs from the text column to the gutter, so bars align for free" {
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() {
      popup_bar --label "session" --percentage 38 --value "38%"
      popup_bar --label "weekly · resets Thu 09:00" --percentage 91 --value "91%"
    }
    on_click() { popup_open; }
  '
  local a b
  a=$(grep -oE -- '--add slider w\.popup\.1 popup\.w [0-9]+' "$SB_LOG" | awk '{print $NF}')
  b=$(grep -oE -- '--add slider w\.popup\.3 popup\.w [0-9]+' "$SB_LOG" | awk '{print $NF}')
  [ "$a" = "$b" ]
  # 340 − 38 (text column) − 10 (gutter); inset by the text column on the left.
  [ "$a" = 292 ]
  [[ "$(row_args 1)" == *"width=292 padding_left=44 padding_right=16"* ]]
}

@test "popup_graph is an --add graph, its readings stretched over its width, oldest first" {
  NAME=w SENDER=mouse.clicked widget '
# widget: mark = teal
    popup_rows() { popup_graph --points "10 40 140 -3"; }
    on_click() { popup_open; }
  '
  grep -q -- '--add graph w.popup.0 popup.w 320' "$SB_LOG"
  [[ "$(row_args 0)" == *"graph.color=0xff7a0002 graph.fill_color=0x307a0002"* ]]
  # A graph is one sample per point of width: four readings pushed as four
  # would draw in four points of 320. They are resampled to the width with a
  # straight line between neighbours — the first push is the first reading,
  # the last push the last (clamped, like `graph`), and every push is on the
  # same batch as the --add.
  local batch pushes
  batch=$(grep -- '--add graph' "$SB_LOG")
  pushes=$(printf '%s' "$batch" | grep -o -- '--push w.popup.0 [0-9.]*' | wc -l | tr -d ' ')
  [ "$pushes" = 320 ]
  [[ "$batch" == *"--push w.popup.0 0.10 --push w.popup.0 0.10 "* ]]
  [[ "$batch" == *"--push w.popup.0 0.01 --push w.popup.0 0.00 "* ]]
  # Halfway between the second and third reading is halfway up.
  [[ "$batch" == *"--push w.popup.0 0.70 "* ]]
}

@test "popup_graph with one reading is a flat line at its level" {
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() { popup_graph --points "55"; }
    on_click() { popup_open; }
  '
  local batch
  batch=$(grep -- '--add graph' "$SB_LOG")
  [[ "$batch" == *"--push w.popup.0 0.55 --push w.popup.0 0.55 "* ]]
  [[ "$batch" != *"--push w.popup.0 0.54"* ]]
}

# ---- separator and space -----------------------------------------------------

@test "a separator is a one-point line from gutter to gutter, on a twelve-point row" {
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() { popup_separator; }
    on_click() { popup_open; }
  '
  local r
  r=$(row_args 0)
  [[ "$r" == *"width=320 padding_left=16 padding_right=16"* ]]
  # The row is the transparent background every row carries, at the
  # separator's own height; the LINE is the icon slot's background.
  [[ "$r" == *"background.drawing=on background.color=0x00000000 background.height=12"* ]]
  [[ "$r" == *"icon.width=320 icon.align=left"* ]]
  [[ "$r" == *"icon.background.drawing=on icon.background.height=1 icon.background.corner_radius=0 icon.background.color=0xffbbbbbb"* ]]
  ! grep -q -- '--subscribe w.popup.0' "$SB_LOG"
}

# ---- the list item -----------------------------------------------------------

@test "popup_item is two lines that are one row: title with the glyph, caption with the reading" {
  NAME=w SENDER=mouse.clicked widget '
    BARLIB_MARK=teal
    popup_rows() {
      popup_item --icon C --icon-font "Other Font:Regular:14" --title "launch-mission-1" \
        --subtitle "ready · 32m · workshop" --subtitle-tone bad \
        --value "⎇ +2 unshipped" --value-tone warn --run "go"
    }
    on_click() { popup_open; }
  '
  local t s
  t=$(row_args 0)
  s=$(row_args 1)
  # The title line: glyph in the widget'"'"'s mark on the glyph column, in its own
  # face; the title bold, in the text colour, on the text column.
  [[ "$t" == *"background.height=22"* ]]
  [[ "$t" == *"icon=C icon.color=0xff7a0002 icon.font=Other Font:Regular:14"* ]]
  [[ "$t" == *"label=launch-mission-1 label.color=0xff777777"* ]]
  [[ "$t" == *"label.font=Test Font:Bold:12"* ]]
  # The caption line: the caption in its tone from the text column, the
  # reading bold and flush right in ITS tone — three hues, nothing merged.
  [[ "$s" == *"background.height=18"* ]]
  [[ "$s" == *"icon=ready · 32m · workshop icon.color=0xff555555 icon.font=Test Font:Regular:10 icon.padding_left=38"* ]]
  [[ "$s" == *"label=⎇ +2 unshipped label.font=Test Font:Bold:10 label.color=0xff444444"* ]]
  [[ "$s" == *"label.align=right"* ]]
  # Both lines run the action, and both close.
  [[ "$t" == *"click_script=go; "*"popup.drawing=off"* ]]
  [[ "$s" == *"click_script=go; "*"popup.drawing=off"* ]]
}

@test "popup_item lights both lines as one under the pointer" {
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() {
      popup_item --title "a" --subtitle "b" --run "go"
      popup_item --title "inert" --subtitle "still"
    }
    on_click() { popup_open; }
  '
  grep -q -- '--subscribe w.popup.0 mouse.entered mouse.exited' "$SB_LOG"
  grep -q -- '--subscribe w.popup.1 mouse.entered mouse.exited' "$SB_LOG"
  ! grep -q -- '--subscribe w.popup.2 ' "$SB_LOG"
  ! grep -q -- '--subscribe w.popup.3 ' "$SB_LOG"
  # Each line'"'"'s script names BOTH ids, so the pair is one highlight from
  # whichever line the pointer is on.
  # (On the raw log: row_args splits on the very `--set w.popup.N` the
  # script carries.)
  local on off
  on='mouse.entered) "'"$BATS_TEST_TMPDIR"'/bin/sb" --set w.popup.0 background.color=0xffcccccc --set w.popup.1 background.color=0xffcccccc ;;'
  off='mouse.exited) "'"$BATS_TEST_TMPDIR"'/bin/sb" --set w.popup.0 background.color=0x00000000 --set w.popup.1 background.color=0x00000000 ;;'
  grep -qF -- "--set w.popup.0 script=case \"\$SENDER\" in $on $off esac" "$SB_LOG"
  grep -qF -- "--set w.popup.1 script=case \"\$SENDER\" in $on $off esac" "$SB_LOG"
}

@test "popup_item with a badge puts a capsule on the caption line; with nothing under the title, one line" {
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() {
      popup_item --title "Standup" --subtitle "Today 14:00 · 30m" --badge "Join" --badge-tone action --run "j"
      popup_item --title "alone"
    }
    on_click() { popup_open; }
  '
  local s
  s=$(row_args 1)
  [[ "$s" == *"label=Join label.font=Test Font:Bold:10 label.color=0xff5a5a5a"* ]]
  [[ "$s" == *"label.background.drawing=on label.background.color=0x305a5a5a label.background.height=16 label.background.corner_radius=8"* ]]
  # The one-line item is row 2, and there is no row 3.
  [[ "$(row_args 2)" == *"label=alone"* ]]
  ! grep -q -- '--add item w.popup.3 ' "$SB_LOG"
}

# ---- the right slot is fair -------------------------------------------------

@test "a long name gives way to the value rather than cutting it to four columns" {
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() {
      popup_row --label "working · 12m · a-repo-with-a-long-name · and more" --value "⎇ +2 unshipped" --tone warn
    }
    on_click() { popup_open; }
  '
  local r
  r=$(row_args 0)
  # The value is whole; the name wears the ellipsis.
  [[ "$r" == *"label=⎇ +2 unshipped label.font"* ]]
  [[ "$r" == *"icon=working · 12m · a"*"… icon.color"* ]]
}

@test "a value longer than its share is still the one cut" {
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() {
      popup_row --label "when" --value "a title so long it would take the whole row and then the name too"
    }
    on_click() { popup_open; }
  '
  [[ "$(row_args 0)" == *"icon=when icon.color"* ]]
  [[ "$(row_args 0)" == *"label=a title so long"*"… label.font"* ]]
}

# ---- a button stands off ----------------------------------------------------

@test "a button after a row gets the panel's pad above it; first, or after a space or button, none" {
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() {
      popup_button --label "first" --run "a"
      popup_row --label "r"
      popup_button --label "second" --run "b"
      popup_button --label "third" --run "c"
    }
    on_click() { popup_open; }
  '
  [[ "$(row_args 0)" == *"label=first"* ]]
  [[ "$(row_args 1)" == *"label=r"* ]]
  [[ "$(row_args 2)" == *"icon.drawing=off label.drawing=off"* ]]
  [[ "$(row_args 2)" == *"background.height=8"* ]]
  [[ "$(row_args 3)" == *"label=second"* ]]
  [[ "$(row_args 4)" == *"label=third"* ]]
}

@test "popup_heading --hint is a tiny dim caption flush right on the title line" {
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() { popup_heading --icon A --label "Agents" --hint "3 ready · 1 working"; }
    on_click() { popup_open; }
  '
  local r
  r=$(row_args 0)
  [[ "$r" == *"icon=A Agents icon.color=0xff1a1a1a"* ]]
  [[ "$r" == *"label=3 ready · 1 working label.font=Test Font:Regular:10 label.color=0xff999999"* ]]
  [[ "$r" == *"label.align=right"* ]]
}

@test "popup_space is nothing, that tall, and scales" {
  NAME=w SENDER=mouse.clicked widget '
    BAR_SCALE=1.25
    popup_rows() { popup_space 8; }
    on_click() { popup_open; }
  '
  [[ "$(row_args 0)" == *"background.height=10"* ]]
  [[ "$(row_args 0)" == *"icon.drawing=off label.drawing=off"* ]]
}

# ---- what a slot may hold -----------------------------------------------------

@test "a value longer than the row leaves the name its room and is cut itself" {
  # calendar's event title is a VALUE. Uncapped, a long one sized a slot wider
  # than the row and the name slot went negative — a row spilling out of the
  # panel on the right.
  NAME=w SENDER=mouse.clicked widget '
    popup_rows() { popup_row --label "Thu 14:00" --value "a meeting whose title runs on and on and on and on and on"; }
    on_click() { popup_open; }
  '
  local r
  r=$(row_args 0)
  [[ "$r" == *"icon=Thu 14:00 "* ]]
  [[ "$r" == *"…"* ]]
  ! grep -qE 'icon\.width=-' "$SB_LOG"
  ! grep -q 'and on and on and on and on' "$SB_LOG"
}

@test "a cut never lands inside a glyph, under the bash macOS ships" {
  # ${#s} and ${s%?} count what the locale says; the runtime sets it per
  # function and relies on bash putting it back. Run under /bin/bash (3.2)
  # on purpose, with a string that ENDS in a three-byte glyph: a byte-wise
  # cut would leave two bytes of it on the row.
  [ -x /bin/bash ] || skip "no /bin/bash"
  NAME=w SENDER=mouse.clicked run /bin/bash -c '
    source "'"$BARLIB"'"
    _barlib_fit "abcdefghijklmnopqrstuvwxyz 󰃰󰃰󰃰󰃰󰃰" 20
    printf "%s\n" "$_BARLIB_FIT"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"…" ]]
  # Every glyph that survived is whole: the output is valid UTF-8.
  printf '%s' "$output" | iconv -f UTF-8 -t UTF-8 >/dev/null
}
