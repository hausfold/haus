#!/bin/bash
# float-term.sh — the ONE way the hacker desktop throws up a floating, centered
# Ghostty window. Consolidates logic that used to be copy-pasted (and to drift)
# across the Rebuild System pounce command, the Super-y yazi peek panel, and
# the agent-peek popup.
#
# Three subcommands:
#
#   geom [--tiled | --pct N | --w PX --h PX | --match-frontmost]
#       Print "X Y W H": a window of the requested size, centered on the
#       VISIBLE frame (menubar/dock excluded) of whichever display the cursor
#       is on right now. Multi-monitor aware; coords are Ghostty/AppKit
#       top-left origin. --pct sizes the window to N% of the visible frame.
#       --match-frontmost instead returns the frame of the window that is on
#       top RIGHT NOW — the one whose keystroke summoned us — so the popup
#       covers its summoner exactly instead of landing at some fraction of the
#       screen (this is what ⌘F's this-window search wants). Falls back to a
#       centered 80% if that frame can't be read.
#       --tiled is the "cover the whole desktop" size, and it is NOT the same
#       as --pct 100: the visible frame is everything macOS leaves us, whereas
#       the TILED area is that frame inset by AeroSpace's outer gaps — the
#       rectangle the tiled windows themselves occupy, bar room and edge
#       padding excluded. A --pct 100 popup therefore overhangs every window it
#       is covering by exactly the gap, which reads as "too big" rather than as
#       "the desktop, replaced". The four insets are baked in from
#       ../lib/gaps.nix (GAP_* below) — the SAME arithmetic modules/windows
#       writes into aerospace.toml's [gaps] block, per monitor class, so the
#       popup cannot drift from the layout it is covering.
#       Every caller reaches this through spawn/place rather than directly;
#       the subcommand stays public because it is the one way to ASK what a
#       geometry resolves to without opening anything (the peek panel used to
#       consume it that way, back when it teleported a parked window instead of
#       spawning a fresh one per summon).
#
#   spawn --title T [--tiled | --pct N | --w PX --h PX | --match-frontmost]
#         [--cols N --rows N] [--pin]
#         --command CMD [-- EXTRA ghostty args…]
#       Spawn a fresh Ghostty INSTANCE running CMD, centered at that geometry,
#       and print its pid. macOS forces this exact shape:
#         - `ghostty -e …` / `+new-window` are unsupported from the CLI, so we
#           must `open -na Ghostty.app` to get a fresh instance;
#         - that instance's --window-position/-width flags are silently ignored
#           on macOS (it inherits a saved-state frame), so we PID-diff to find
#           the new instance and drive System Events to set the real frame once
#           AX first exposes the window.
#       Aerospace's "every runtime ghostty floats" rule (windows/aerospace.toml)
#       keeps it from tiling; --pin also yanks it back onto the workspace you
#       spawned from and force-floats it, in case any on-window-detected rule
#       grabbed it first. Finally it CLAIMS FOCUS (see raise below) — these
#       windows are summoned, and one that opens behind its summoner is a
#       message nobody reads. It also draws the OUTLINE (see ring below) around
#       the new window, so every popup that comes through here is edged the same.
#
#   place PID {--tiled | --pct N | --w PX --h PX | --frame "X Y W H"}
#       Re-plant an EXISTING window at that geometry — geom + the same AX drive
#       spawn uses, and nothing else (no focus claim, no aerospace, no ring; the
#       window already has all three). For a popup whose SCOPE changes while it
#       is open, which is ⌘F's ^s toggle and so far only that: the overlay is
#       sized to the summoning window while it searches that window's
#       scrollback, and to the tiled desktop the moment ^s widens it to every
#       session. Without this the rule would hold only on the entry path, and
#       ⌘F→^s would land you in exactly the half-width cross-session list ⌘⇧F
#       exists to avoid.
#       --frame is why place takes an explicit rectangle at all, and it is the
#       ^s toggle read backwards: --match-frontmost is useless once the popup
#       IS the frontmost window, so shrinking back to pane scope has to replay a
#       frame captured before the popup existed. The caller stashes it at spawn
#       time (find.sh writes "$dir/frame") and hands it back here.
#       PID is the GHOSTTY process, not the caller — a script running inside the
#       popup wants the ancestor it is hosted by (find.sh's `host_ghostty_pid`).
#
#   ring PID [COLOR [WIDTH_PT]]
#       Draw a rounded outline just outside PID's window and follow it until that
#       process exits — the thin edge that separates a popup from whatever it
#       landed on. Baked defaults come from haus.terminal.floatBorder (rendered
#       into RING_* below), so spawn() needs no flag; the arguments exist to
#       PREVIEW a colour on any window without a rebuild, e.g.
#           float-term.sh ring "$(pgrep -x ghostty | head -1)" '#cba6f7' 2
#       A no-op when the option is "off" (RING_COLOR renders empty).
#       Implementation, and why it isn't Ghostty/aerospace/JankyBorders doing it:
#       modules/terminal/floatring.swift.

set -u
# open/osascript live in /usr/bin; aerospace in the nix/brew profiles. Callers
# range from a login shell to launchd's minimal PATH (pounce command), so be
# explicit rather than trust the inherited environment.
export PATH="/opt/homebrew/bin:/run/current-system/sw/bin:/usr/bin:/bin:$PATH"

# Baked by modules/terminal from haus.terminal.floatBorder — the outline's binary,
# colour and thickness. RING_COLOR is empty when the option is "off", which is
# the single check every ring path makes. The binary is referenced by store path
# rather than by name so a launchd-spawned pounce command (bare PATH) finds it.
RING_BIN="@floatring@"
RING_COLOR="@ring_color@"
RING_WIDTH="@ring_width@"

# Baked by modules/terminal from ../lib/gaps.nix — AeroSpace's OUTER gaps, in
# points, per monitor class. These are the same numbers modules/windows writes
# into aerospace.toml's [gaps] block; imported from the shared file rather than
# re-derived here so a --tiled popup and the windows it covers can never
# disagree about where the desktop ends. Only `geom --tiled` reads them.
GAP_TOP_BUILTIN="@gap_top_builtin@"
GAP_TOP_EXTERNAL="@gap_top_external@"
GAP_BOTTOM_BUILTIN="@gap_bottom_builtin@"
GAP_BOTTOM_EXTERNAL="@gap_bottom_external@"
GAP_SIDE_BUILTIN="@gap_side_builtin@"
GAP_SIDE_EXTERNAL="@gap_side_external@"

# ── frame of the window that's on top right now ─────────────────────────────
# Emits "X Y W H" for the frontmost window of the frontmost application — the
# window whose keystroke summoned us — in the SAME top-left-origin coord system
# geom() emits and spawn()'s AppleScript consumes, so the two are drop-in
# interchangeable. Silent (empty) on any failure — no frontmost app, a process
# with no windows, a nonsense frame — which is the caller's cue to fall back to
# centered geometry rather than place a window at 0×0.
frontmost_frame() {
  local out x y w h
  out=$(osascript 2>/dev/null <<'APPLESCRIPT'
tell application "System Events"
  set fronts to (every application process whose frontmost is true)
  if (count of fronts) is 0 then return ""
  tell item 1 of fronts
    if (count of windows) is 0 then return ""
    set {px, py} to position of window 1
    set {pw, ph} to size of window 1
    set out to ((px as integer) as text) & " " & ((py as integer) as text)
    set out to out & " " & ((pw as integer) as text)
    set out to out & " " & ((ph as integer) as text)
    return out
  end tell
end tell
APPLESCRIPT
)
  read -r x y w h <<< "${out:-}"
  # Sanity gate: a real terminal window, not a menubar extra or a zero-size
  # stub. Only w/h are checked — x/y are legitimately negative on a display
  # sitting left of / above the primary one.
  case "${w:-x}${h:-x}" in *[!0-9]*) return 0 ;; esac
  [ "$w" -ge 200 ] && [ "$h" -ge 200 ] && echo "$x $y $w $h"
  return 0
}

# ── centered geometry on the cursor's screen ────────────────────────────────
# Emits "X Y W H" for a WIN_W×WIN_H window centered on the visible frame of the
# display under the cursor. Pass either an explicit pixel size or a percentage.
geom() {
  local mode="pct" arg="85"
  while [ $# -gt 0 ]; do
    case "$1" in
      --pct) mode="pct"; arg="$2"; shift 2 ;;
      --w)   mode="px";  W_PX="$2"; shift 2 ;;
      --h)             H_PX="$2"; shift 2 ;;
      --match-frontmost) mode="match"; shift ;;
      --tiled) mode="tiled"; shift ;;
      *) shift ;;
    esac
  done

  # Cover-the-summoner mode short-circuits the centering math entirely; if the
  # frame comes back unreadable, degrade to the old centered default.
  if [ "$mode" = "match" ]; then
    local matched
    matched=$(frontmost_frame)
    if [ -n "$matched" ]; then
      echo "$matched"
      return 0
    fi
    mode="pct"; arg="80"
  fi

  # WHICH display. The cursor's, normally — it is the only "where am I" a popup
  # summoned from launchd can read for free. But --tiled is covering the WINDOWS,
  # and haus.windows.mouseFollowsFocus defaults to false, so on a two-display
  # desk the pointer is routinely parked on a screen the chord wasn't pressed on.
  # Probe from the summoning window's own centre when its frame is readable, and
  # fall back to the cursor when it isn't — which is also every non-tiled mode,
  # where the popup is centred on a screen rather than fitted to a layout and the
  # cursor is the better guess anyway.
  if [ "$mode" = "tiled" ]; then
    local fx fy fw fh probe
    probe=$(frontmost_frame)
    if [ -n "$probe" ]; then
      read -r fx fy fw fh <<< "$probe"
      export HAUS_PROBE_X=$(( fx + fw / 2 )) HAUS_PROBE_Y=$(( fy + fh / 2 ))
    fi
  fi

  # Frame of that display in Ghostty's top-origin coord system. `frame` would
  # include the menu bar / dock; `visibleFrame` excludes them so a centered
  # window never gets clipped.
  local frame
  frame=$(osascript -l JavaScript -e '
    ObjC.import("AppKit");
    ObjC.import("CoreGraphics");
    // HAUS_PROBE_X/Y: an explicit point to resolve instead of the pointer, set
    // by the tiled branch above. Both coordinate systems are top-left origin
    // (CGEventGetLocation is global display space), so they are interchangeable.
    var env = $.NSProcessInfo.processInfo.environment;
    var ex = env.objectForKey("HAUS_PROBE_X"), ey = env.objectForKey("HAUS_PROBE_Y");
    var loc = (ex && ey)
      ? { x: parseFloat(ObjC.unwrap(ex)), y: parseFloat(ObjC.unwrap(ey)) }
      : $.CGEventGetLocation($.CGEventCreate($()));
    var screens = $.NSScreen.screens;
    if (screens.count === 0) {
      "0 0 1920 1080 0";
    } else {
      var primaryH = screens.objectAtIndex(0).frame.size.height;
      var pick = screens.objectAtIndex(0);
      for (var i = 0; i < screens.count; i++) {
        var s = screens.objectAtIndex(i);
        var fr = s.frame;
        var topY = primaryH - (fr.origin.y + fr.size.height);
        if (loc.x >= fr.origin.x && loc.x < fr.origin.x + fr.size.width &&
            loc.y >= topY      && loc.y < topY      + fr.size.height) {
          pick = s; break;
        }
      }
      var vf = pick.visibleFrame;
      var vTopY = primaryH - (vf.origin.y + vf.size.height);
      // Fifth field: which gap column of aerospace.toml this display is in.
      // AeroSpace keys its per-monitor gaps off the display NAME, so match on
      // the same string it does rather than on index or on `screens[0]` — the
      // built-in is not always the primary, and a laptop docked shut has none.
      // Not a perfect mirror: AeroSpace treats its monitor key as a REGEX, so a
      // display whose name merely CONTAINS "Built-in Retina Display" would get
      // the built-in gaps from AeroSpace and the external ones from this ===.
      // No such display is known to exist; the cost if one turns up is a popup
      // inset by 20/36 instead of 10/10, not a broken one.
      var name = "";
      try { name = ObjC.unwrap(pick.localizedName) || ""; } catch (e) {}
      Math.round(vf.origin.x) + " " + Math.round(vTopY) + " " +
      Math.round(vf.size.width) + " " + Math.round(vf.size.height) + " " +
      (name === "Built-in Retina Display" ? "1" : "0");
    }
  ' 2>/dev/null)
  [ -z "$frame" ] && frame="0 0 1920 1080 0"

  local sx sy sw sh builtin win_w win_h
  read -r sx sy sw sh builtin <<< "$frame"

  # The tiled desktop: the visible frame minus AeroSpace's outer gaps, which is
  # the rectangle the windows underneath actually occupy. Returned directly —
  # there is nothing to centre, the answer IS a frame.
  if [ "$mode" = "tiled" ]; then
    local g_top g_bottom g_side
    if [ "${builtin:-0}" = "1" ]; then
      g_top="$GAP_TOP_BUILTIN"; g_bottom="$GAP_BOTTOM_BUILTIN"; g_side="$GAP_SIDE_BUILTIN"
    else
      g_top="$GAP_TOP_EXTERNAL"; g_bottom="$GAP_BOTTOM_EXTERNAL"; g_side="$GAP_SIDE_EXTERNAL"
    fi
    echo "$(( sx + g_side )) $(( sy + g_top ))" \
         "$(( sw - 2 * g_side )) $(( sh - g_top - g_bottom ))"
    return 0
  fi

  if [ "$mode" = "pct" ]; then
    win_w=$(( sw * arg / 100 ))
    win_h=$(( sh * arg / 100 ))
  else
    win_w="${W_PX:?--w required}"
    win_h="${H_PX:?--h required}"
  fi
  echo "$(( sx + (sw - win_w) / 2 )) $(( sy + (sh - win_h) / 2 )) $win_w $win_h"
}

# ── drive a window to an exact frame over AX ─────────────────────────────────
# set_frame PID X Y W H [TRIES] — poll until AX exposes the process's window,
# then plant it at the requested frame. Size is set, then position, then size
# AGAIN: AppKit clamps a resize that would run past a screen edge, so a window
# moved after being sized can come out short. The second set, now that the
# origin is right, is what makes "cover it perfectly" actually perfect.
set_frame() {
  local pid="$1" x="$2" y="$3" w="$4" h="$5" tries="${6:-100}"
  osascript >/dev/null 2>&1 <<APPLESCRIPT
tell application "System Events"
  tell (first process whose unix id is $pid)
    repeat $tries times
      try
        if (count windows) > 0 then
          set size of window 1 to {$w, $h}
          set position of window 1 to {$x, $y}
          set size of window 1 to {$w, $h}
          exit repeat
        end if
      end try
      delay 0.02
    end repeat
  end tell
end tell
APPLESCRIPT
}

# ── bring the new window to the front ───────────────────────────────────────
# raise PID WID — claim focus for the window we just spawned, retrying briefly.
#
# A summoned popup that lands BEHIND its summoner is worse than no popup: the
# rebuild / Install App terminal is where a failure gets REPORTED, and one that
# opens unfocused reports it to nobody (found exactly that way — an install
# whose rebuild failed on a leader-key collision, discovered minutes later).
# `open -na` does activate the new instance, but the focus is routinely handed
# straight back: a pounce command runs while the picker window is still tearing
# down, and macOS restores whatever was frontmost before it. So claim focus
# explicitly once the window exists, and re-claim it over the next fraction of a
# second in case that teardown lands after us. `aerospace focus` is the rice's
# own path (what bar's agents plugin uses); System Events is the fallback for a
# machine where aerospace isn't running.
raise() {
  local pid="$1" wid="$2" i
  for i in 1 2 3; do
    if [ -n "$wid" ]; then
      aerospace focus --window-id "$wid" >/dev/null 2>&1
      [ "$(aerospace list-windows --focused --format '%{window-id}' 2>/dev/null)" = "$wid" ] && return 0
    fi
    [ -n "$pid" ] && osascript >/dev/null 2>&1 \
      -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $pid) to true"
    sleep 0.1
  done
}

# ── outline the window ──────────────────────────────────────────────────────
# ring PID [COLOR [WIDTH_PT]] — hand PID to floatring, which draws a rounded
# outline just outside that window and follows it until the process exits.
#
# Detached on purpose: the ring must outlive this script (a pounce command exits
# the moment it has spawned its terminal), so it's backgrounded with its stdio
# detached. It reaps ITSELF when the popup goes away — nothing here has to track
# it, which is why there's no pidfile and no cleanup path.
#
# ${1:-} rather than $1: this subcommand is user-facing (the option description
# hands out a preview command), and `set -u` would turn a bare `ring` into an
# unbound-variable trace instead of a quiet no-op.
ring() {
  local pid="${1:-}" color="${2:-$RING_COLOR}" width="${3:-$RING_WIDTH}"
  [ -n "$pid" ] || return 0
  [ -n "$color" ] || return 0     # haus.terminal.floatBorder = "off"
  [ -x "${RING_BIN:-}" ] || return 0 # …which also renders RING_BIN empty
  "$RING_BIN" --pid "$pid" --color "$color" --width "$width" </dev/null >/dev/null 2>&1 &
}

# ── spawn a fresh centered instance ─────────────────────────────────────────
spawn() {
  local title="" command="" pin=0 cols="" rows="" exact=0
  local -a size_args=() extra=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --title)   title="$2"; shift 2 ;;
      --command) command="$2"; shift 2 ;;
      --pin)     pin=1; shift ;;
      --cols)    cols="$2"; shift 2 ;;
      --rows)    rows="$2"; shift 2 ;;
      --pct)     size_args=(--pct "$2"); shift 2 ;;
      --w)       size_args+=(--w "$2"); shift 2 ;;
      --h)       size_args+=(--h "$2"); shift 2 ;;
      --match-frontmost) size_args=(--match-frontmost); exact=1; shift ;;
      --tiled)   size_args=(--tiled); exact=1; shift ;;
      --)        shift; extra=("$@"); break ;;
      *) shift ;;
    esac
  done
  : "${title:?--title required}" "${command:?--command required}"

  # ${arr[@]+"${arr[@]}"}: expand safely even when empty — macOS /bin/bash is
  # 3.2, where a bare "${arr[@]}" on an empty array trips `set -u`.
  local pos_x pos_y win_w win_h
  read -r pos_x pos_y win_w win_h <<< "$(geom ${size_args[@]+"${size_args[@]}"})"

  # Snapshot before spawn: existing ghostty pids so we can pick out the NEW
  # instance, and the focused workspace so --pin can put the window there.
  local before source_ws=""
  before=$(pgrep -x ghostty 2>/dev/null | sort -u)
  [ "$pin" = 1 ] && source_ws=$(aerospace list-workspaces --focused 2>/dev/null)

  local -a open_args=(--title="$title")
  [ -n "$cols" ] && open_args+=(--window-width="$cols")
  [ -n "$rows" ] && open_args+=(--window-height="$rows")
  open_args+=(--window-position-x="$pos_x" --window-position-y="$pos_y")
  open_args+=(${extra[@]+"${extra[@]}"} --command="$command")
  open -na Ghostty.app --args "${open_args[@]}"

  # Find the new instance (poll fast — detection dominates perceived latency).
  local new_pid="" after
  local i
  for i in $(seq 1 100); do
    after=$(pgrep -x ghostty 2>/dev/null | sort -u)
    new_pid=$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | head -1)
    [ -n "$new_pid" ] && break
    sleep 0.02
  done

  # Set the real frame the moment AX exposes the window (CLI flags don't stick).
  [ -n "$new_pid" ] && set_frame "$new_pid" "$pos_x" "$pos_y" "$win_w" "$win_h"

  # Aerospace cleanup: pull the window back to the source workspace (if asked)
  # and force-float it. Runs after positioning so we don't fight our own AS.
  local wid=""
  for i in $(seq 1 30); do
    wid=$(aerospace list-windows --all --format '%{window-id}|%{app-name}|%{window-title}' 2>/dev/null \
          | awk -F'|' -v t="$title" '$2 == "Ghostty" && $3 == t {print $1; exit}')
    if [ -n "$wid" ]; then
      [ -n "$source_ws" ] && aerospace move-node-to-workspace --window-id "$wid" "$source_ws" 2>/dev/null
      aerospace layout --window-id "$wid" floating 2>/dev/null
      break
    fi
    sleep 0.03
  done

  # Flipping a window to floating makes aerospace restore its REMEMBERED
  # floating frame, which would undo the placement above. Harmless when we only
  # wanted "roughly centered", fatal in the two modes whose whole point is a
  # frame that lines up with something — covering the summoning window
  # (--match-frontmost) or the tiled desktop (--tiled) — so there, let aerospace
  # have its say and then plant the frame again, last word ours.
  if [ "$exact" = 1 ] && [ -n "$new_pid" ]; then
    sleep 0.05
    set_frame "$new_pid" "$pos_x" "$pos_y" "$win_w" "$win_h" 1
  fi

  # Last word: the window is placed, floated and pinned — now make sure it's the
  # one you're typing into.
  raise "$new_pid" "$wid"

  # The outline goes on last, after every frame-setting pass above: floatring
  # follows the window from here on, so it can't be desynced by a late re-plant.
  ring "$new_pid"

  echo "$new_pid"
}

# ── re-plant a window that already exists ───────────────────────────────────
place() {
  local pid="${1:-}"
  shift || true
  [ -n "$pid" ] || return 0
  local pos_x pos_y win_w win_h
  if [ "${1:-}" = "--frame" ]; then
    read -r pos_x pos_y win_w win_h <<< "${2:-}"
    # A frame the caller couldn't capture comes through as empty fields; do
    # nothing rather than collapse the window onto 0×0.
    case "${pos_x:-x}${pos_y:-x}${win_w:-x}${win_h:-x}" in *[!0-9-]*) return 0 ;; esac
    [ "${win_w:-0}" -ge 200 ] && [ "${win_h:-0}" -ge 200 ] || return 0
  else
    read -r pos_x pos_y win_w win_h <<< "$(geom "$@")"
  fi
  # A low try count on purpose: the window is already on screen, so AX exposes
  # it on the first pass. The 100 spawn uses is for a process that may not have
  # drawn yet, and waiting that long here would just stall a keypress.
  set_frame "$pid" "$pos_x" "$pos_y" "$win_w" "$win_h" 10
}

case "${1:-}" in
  geom)  shift; geom "$@" ;;
  spawn) shift; spawn "$@" ;;
  place) shift; place "$@" ;;
  ring)  shift; ring "$@" ;;
  *) echo "usage: float-term.sh {geom|spawn|place|ring} …" >&2; exit 2 ;;
esac
