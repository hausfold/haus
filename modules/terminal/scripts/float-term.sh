#!/bin/bash
# float-term.sh — the ONE way the hacker desktop throws up a floating, centered
# Ghostty window. Consolidates logic that used to be copy-pasted (and to drift)
# across the Rebuild System pounce command, the Super-y yazi peek panel, and
# the agent-peek popup.
#
# Three subcommands:
#
#   geom [--tiled | --pct N | --w PX --h PX | --match-focused]
#       Print "X Y W H": a window of the requested size, centered on the
#       VISIBLE frame (menubar/dock excluded) of whichever display the cursor
#       is on right now. Multi-monitor aware; coords are Ghostty/AppKit
#       top-left origin. --pct sizes the window to N% of the visible frame.
#       --match-focused instead returns the frame of the FOCUSED window right
#       NOW — the one whose keystroke summoned us — so the popup covers its
#       summoner exactly instead of landing at some fraction of the screen. It
#       is what every per-window chord wants: ⌘F searches that one window's
#       scrollback, ⌘Y roots yazi at that one window's cwd, and a popup that
#       lands over a DIFFERENT window than the one it is about reads as a bug
#       even when its contents are right. Which window has focus comes from the
#       TILER, not from macOS's frontmost-process flag — see focused_frame()
#       for the measurement that forced that. Falls back to a centered 80% when
#       the frame can't be read, or describes a window that is on no screen.
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
# ── every popup's title starts `quick-terminal-` ─────────────────────────────
# A forced --title is how anything outside a window finds it, and for these
# windows the only question anyone asks from outside is "leave it alone": a
# float-term popup is placed at a pixel frame, floated on purpose and wearing a
# floatring outline, so windows' re-sort (windows/scripts/resort-windows.sh)
# must neither move it to a workspace nor pull it into the tiling tree, and
# terminal's launch.sh must not wrap it in a zmx session. Both ask by prefix.
# `find` and `github` were the two that did not carry it, which cost nothing
# until the re-sort learned to restore layout as well as page and started
# tiling them; they carry it now, and a NEW popup that forgets is the same bug
# again. So: whatever you call it, prefix it. A --tiled popup covers the whole
# tiled desktop and is the one that would be most visibly wrong as a tile.
#
#   spawn --title T [--tiled | --pct N | --w PX --h PX | --match-focused]
#         [--cols N --rows N] [--pin]
#         --command CMD [-- EXTRA ghostty args…]
#       Spawn a fresh Ghostty INSTANCE running CMD, centered at that geometry,
#       and print its pid. ⚠️ With `--cols/--rows`, the GRID decides the size and
#       `--w/--h` decide only which rectangle gets centered — Ghostty rounds to
#       whole cells and refuses to shrink below its grid, so the two disagree and
#       the window is re-centred on its real size afterwards (`recenter`). Pass
#       both only when you mean "this many columns, roughly this big".
#       macOS forces this exact shape:
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
#       ^s toggle read backwards: --match-focused is useless once the popup
#       IS the focused window, so shrinking back to pane scope has to replay a
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

# ── frame of the window that has the keyboard right now ─────────────────────
# Emits "X Y W H" for the FOCUSED window — the one whose keystroke summoned us
# — in the SAME top-left-origin coord system geom() emits and spawn()'s
# AppleScript consumes, so the two are drop-in interchangeable. Silent (empty)
# on any failure — nothing focused, a process with no windows, a nonsense frame
# — which is the caller's cue to fall back to centered geometry rather than
# place a window at 0×0.
#
# ASK THE TILER WHICH WINDOW, not macOS which PROCESS, and that is the whole
# correctness of this function. It used to read the frontmost APPLICATION
# PROCESS's window, and that question has no reliable answer on this desktop:
# every lane and every popup is its own `open -na` Ghostty INSTANCE, so
# "Ghostty" is five or six processes, and macOS's per-process `frontmost` flag
# routinely names one that does not hold the keyboard. Measured 2026-08-21 with
# focus sitting still in a lane window: System Events named a Ghostty process
# whose only window was parked on a HIDDEN workspace, for a minute at a time,
# while `aerospace list-windows --focused` named the right one on every sample.
#
# That is why ⌘F and ⌘Y still landed wrong after AXFocusedWindow replaced
# `window 1` (the same file, 2026-08-20): reading the right window of the WRONG
# process is just as wrong, and it fails worse — AeroSpace parks the windows of
# a workspace you can't see just off the bottom-right corner at their full tile
# size, so the frame that came back was a full-desktop rectangle at 1511×950.
# AppKit then clamps a window that big back onto the screen, which is exactly
# the reported bug: an overlay that is desktop-sized "no matter what" and lands
# nowhere near the pane you pressed the chord in.
#
# scripts/focused-session.sh already asks AeroSpace the same question for the
# SESSION half of these chords (~4 ms, and its header has the two-backend
# story). Sharing the source is the point: the frame a popup wears and the
# scrollback it reads can no longer disagree about which window you meant.
# AeroSpace gives us pid + title; the frame itself is still AX, matched inside
# that pid by title — Ghostty forces the title of a lane and of a popup, and
# `first process whose unix id is` with the pid written into the script text is
# the one process lookup System Events gets right (a `whose` clause fed a
# VARIABLE hands back a different process entirely; measured the same day).
# With no tiler installed there is no parking either, so the old
# frontmost-process probe stays as the fallback.
#
# The retry loop is the palette's half of the same question, and it belongs to
# the FALLBACK alone. ⌘Y is a chord AND a palette row (Peek Files), and a pounce
# command commits with the palette still fading — `.linger`, ~0.4 s, focus
# handed back to the captured window only after the client has been spawned.
# Pounce's own window clears the sanity gate below, so a frontmost-process probe
# run in that window would size the popup to the palette; ask again until pounce
# is no longer what has focus, then fall through to the centered default if it
# never yields. AeroSpace never sees the palette at all (it is in no workspace
# and in no `list-windows --all`), so on that path the answer is already the
# window underneath — retrying a failed AX read there would just burn a spawn
# pair and 50 ms per turn on a keystroke, so it doesn't. The Pounce arm stays
# as the belt: `%{app-name}` is `Pounce` (CFBundleName) where System Events'
# process name is `pounce` (CFBundleExecutable), which is why the two branches
# spell it differently.
#
# `--nowait` is for the one caller that only wants a POINT — the tiled branch's
# display probe — where a missed answer costs a guess at which screen you are on
# (and the palette is on that screen anyway), not a misplaced window. It would
# otherwise pay the whole 0.6 s on every palette-spawned --tiled popup.
#
# HAUS_WINDOW_BACKEND picks the backend by hand, the same two spellings
# focused-session.sh takes, so either path can be feel-tested anywhere. Same
# question, NOT the same fallback though: with no tiler that file asks GHOSTTY
# over Apple Events, which needs no Accessibility grant, while this one still
# needs AX to read a frame at all — Ghostty's dictionary can name the front
# window but not measure it.

# ax_frame PID TITLE — "X Y W H" for that process's window named TITLE, falling
# back to its AXFocusedWindow when no title matches (a ⌘N window shares its
# parent's pid and wears whatever title the program inside it last emitted).
ax_frame() {
  local pid="${1:-}" title="${2:-}"
  case "$pid" in '' | *[!0-9]*) return 0 ;; esac
  osascript - "$title" 2>/dev/null <<APPLESCRIPT
on run argv
  set wantTitle to item 1 of argv
  tell application "System Events"
    tell (first process whose unix id is $pid)
      if (count of windows) is 0 then return ""
      set w to missing value
      if wantTitle is not "" then
        repeat with ww in windows
          try
            if (name of ww) is wantTitle then
              set w to ww
              exit repeat
            end if
          end try
        end repeat
      end if
      if w is missing value then
        set w to window 1
        try
          set fw to value of attribute "AXFocusedWindow"
          if fw is not missing value then set w to fw
        end try
      end if
      set {px, py} to position of w
      set {pw, ph} to size of w
      set out to ((px as integer) as text) & " " & ((py as integer) as text)
      set out to out & " " & ((pw as integer) as text)
      set out to out & " " & ((ph as integer) as text)
      return out
    end tell
  end tell
end run
APPLESCRIPT
}

focused_frame() {
  local out="" x y w h i tries=12 backend focused pid title
  [ "${1:-}" = "--nowait" ] && tries=1

  backend="${HAUS_WINDOW_BACKEND:-}"
  if [ -z "$backend" ]; then
    if command -v aerospace >/dev/null 2>&1; then backend=aerospace; else backend=ghostty; fi
  fi

  for i in $(seq 1 $tries); do
    if [ "$backend" = "aerospace" ]; then
      # pid, app, title — the title is last so a title containing "|" is safe.
      focused=$(aerospace list-windows --focused --format '%{app-pid}|%{app-name}|%{window-title}' 2>/dev/null)
      case "$focused" in
        '' | *'|Pounce|'*) out="" ;;
        *)
          pid="${focused%%|*}"
          title="${focused#*|}"
          title="${title#*|}"
          # The tiler already answered about a window that is NOT the palette,
          # so an empty frame here is AX refusing (a denied Automation prompt,
          # a window that vanished) — a thing no amount of waiting fixes.
          out=$(ax_frame "$pid" "$title")
          break
          ;;
      esac
    else
      out=$(osascript 2>/dev/null <<'APPLESCRIPT'
tell application "System Events"
  set p to (first application process whose frontmost is true)
  if name of p is "pounce" then return ""
  tell p
    if (count of windows) is 0 then return ""
    set w to window 1
    try
      set fw to value of attribute "AXFocusedWindow"
      if fw is not missing value then set w to fw
    end try
    set {px, py} to position of w
    set {pw, ph} to size of w
    set out to ((px as integer) as text) & " " & ((py as integer) as text)
    set out to out & " " & ((pw as integer) as text)
    set out to out & " " & ((ph as integer) as text)
    return out
  end tell
end tell
APPLESCRIPT
)
    fi
    [ -n "$out" ] && break
    sleep 0.05
  done
  read -r x y w h <<< "${out:-}"
  # Sanity gate: a real terminal window, not a menubar extra or a zero-size
  # stub. Only w/h are checked — x/y are legitimately negative on a display
  # sitting left of / above the primary one.
  case "${w:-x}${h:-x}" in *[!0-9]*) return 0 ;; esac
  [ "$w" -ge 200 ] && [ "$h" -ge 200 ] && echo "$x $y $w $h"
  return 0
}

# ── which display, and how much of it we may use ────────────────────────────
# Emits "SX SY SW SH BUILTIN HIT" for the display under the cursor, or under
# HAUS_PROBE_X/Y when those are set: the VISIBLE frame (menu bar / dock
# excluded) in Ghostty's top-origin coord system, which gap column of
# aerospace.toml the display is in, and whether the probed point actually
# landed ON a screen. HIT is 0 when it didn't — the answer then describes the
# primary display, which is a fine default to centre on and a lie to trust as
# "this point is visible", so on_screen() below is the only reader that cares.
screen_probe() {
  local frame
  frame=$(osascript -l JavaScript -e '
    ObjC.import("AppKit");
    ObjC.import("CoreGraphics");
    // HAUS_PROBE_X/Y: an explicit point to resolve instead of the pointer, set
    // by geom()'"'"'s tiled branch and by on_screen(). Both coordinate systems are
    // top-left origin (CGEventGetLocation is global display space), so they are
    // interchangeable.
    //
    // ObjC.unwrap FIRST, and then test. An NSDictionary lookup that MISSES
    // comes back as an ObjC nil wrapper whose `typeof` is "function" — truthy
    // in JS — so `ex && ey` on the raw values is true even with nothing in the
    // environment, and the cursor branch below was dead code from the day it
    // was written: every unset-env probe parsed NaN, compared false against
    // every screen and silently answered "the primary display". Invisible on a
    // one-screen Mac and wrong on every other, since it is the ONLY thing that
    // decides which display a centred popup opens on.
    var env = $.NSProcessInfo.processInfo.environment;
    var ex = ObjC.unwrap(env.objectForKey("HAUS_PROBE_X"));
    var ey = ObjC.unwrap(env.objectForKey("HAUS_PROBE_Y"));
    var loc = (ex && ey)
      ? { x: parseFloat(ex), y: parseFloat(ey) }
      : $.CGEventGetLocation($.CGEventCreate($()));
    var screens = $.NSScreen.screens;
    if (screens.count === 0) {
      "0 0 1920 1080 0 0";
    } else {
      var primaryH = screens.objectAtIndex(0).frame.size.height;
      var pick = screens.objectAtIndex(0);
      var hit = 0;
      for (var i = 0; i < screens.count; i++) {
        var s = screens.objectAtIndex(i);
        var fr = s.frame;
        var topY = primaryH - (fr.origin.y + fr.size.height);
        if (loc.x >= fr.origin.x && loc.x < fr.origin.x + fr.size.width &&
            loc.y >= topY      && loc.y < topY      + fr.size.height) {
          pick = s; hit = 1; break;
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
      (name === "Built-in Retina Display" ? "1" : "0") + " " + hit;
    }
  ' 2>/dev/null)
  [ -z "$frame" ] && frame="0 0 1920 1080 0 0"
  printf '%s\n' "$frame"
}

# on_screen X Y — true when that point is on some display. The guard for a
# frame that came back from AX but describes a window nobody can see: AeroSpace
# parks the windows of a hidden workspace just off the bottom-right corner, so
# "unreadable" is not the only way the summoner's frame can be useless.
on_screen() {
  local probe
  probe=$(HAUS_PROBE_X="$1" HAUS_PROBE_Y="$2" screen_probe)
  [ "$(printf '%s\n' "$probe" | awk '{print $6}')" = "1" ]
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
      --match-focused) mode="match"; shift ;;
      --tiled) mode="tiled"; shift ;;
      *) shift ;;
    esac
  done

  # Cover-the-summoner mode short-circuits the centering math entirely; if the
  # frame comes back unreadable — or readable but off every screen, which is
  # what a window parked on a hidden workspace looks like — degrade to the old
  # centered default. Placing a popup at an invisible frame is the worse
  # failure of the two: AppKit clamps it back into view at whatever size the
  # parked window had, so it lands looking deliberate and wrong.
  if [ "$mode" = "match" ]; then
    local matched fx fy fw fh
    matched=$(focused_frame)
    if [ -n "$matched" ]; then
      read -r fx fy fw fh <<< "$matched"
      if on_screen "$(( fx + fw / 2 ))" "$(( fy + fh / 2 ))"; then
        echo "$matched"
        return 0
      fi
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
    probe=$(focused_frame --nowait)
    if [ -n "$probe" ]; then
      read -r fx fy fw fh <<< "$probe"
      export HAUS_PROBE_X=$(( fx + fw / 2 )) HAUS_PROBE_Y=$(( fy + fh / 2 ))
    fi
  fi

  # Frame of that display, from the one probe both modes share.
  local sx sy sw sh builtin hit win_w win_h
  read -r sx sy sw sh builtin hit <<< "$(screen_probe)"

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

# ── centre a window on the size it actually IS ──────────────────────────────
# window_size PID — the real size of the window over AX, as "W H", or nothing.
#
# Needed because a Ghostty window does NOT become the size we ask for. `spawn`
# takes a pixel size AND a cell grid (`--cols 80 --rows 20`), and the grid wins:
# Ghostty rounds to whole cells and will not go below the grid it was launched
# with, so `set_frame`'s size half is quietly refused while its position half
# sticks. Measured 2026-08-23 on a 2560×1440 external: rebuild's popup asks for
# 750×400 and is 942×554, planted at the origin that would have centred 750×400
# — off by (942−750)/2 = 96pt right and (554−400)/2 = 77pt down. The centring
# was correct for a box the window never was.
window_size() {
  local pid="$1" i out
  [ -n "$pid" ] || return 0
  for i in $(seq 1 25); do
    out=$(osascript 2>/dev/null <<APPLESCRIPT
tell application "System Events"
  tell (first process whose unix id is $pid)
    if (count windows) > 0 then
      set {w, h} to size of window 1
      return (w as text) & " " & (h as text)
    end if
  end tell
end tell
APPLESCRIPT
)
    case "$out" in ''|*[!0-9\ ]*) ;; *) printf '%s\n' "$out"; return 0 ;; esac
    sleep 0.02
  done
}

# recenter PID IX IY IW IH — re-centre a spawned window on its REAL size.
#
# The intended rect (IX IY IW IH) is only used to find the display: its centre
# is on the target screen by construction, which is steadier than re-reading the
# cursor — by the time this runs the pointer may have moved off the screen the
# popup was resolved against, and a popup that jumps to another display because
# the mouse did is worse than one that is off-centre.
#
# The size passed back to `set_frame` is the size the window already has, so the
# half that Ghostty refuses is a no-op and only the position moves. That is also
# why this cannot fight the grid: it never asks for a size at all.
recenter() {
  local pid="$1" ix="$2" iy="$3" iw="$4" ih="$5"
  local aw ah sx sy sw sh nx ny
  [ -n "$pid" ] || return 0
  read -r aw ah <<< "$(window_size "$pid")"
  case "${aw:-x}${ah:-x}" in *[!0-9]*|'') return 0 ;; esac
  # Nothing to do when the window really is the size we asked for.
  [ "$aw" = "$iw" ] && [ "$ah" = "$ih" ] && return 0
  # Fields 5 and 6 (the gap column, and whether the probe hit a screen) belong
  # to the tiled branch; centring needs the frame alone.
  read -r sx sy sw sh _ _ <<< \
    "$(HAUS_PROBE_X=$(( ix + iw / 2 )) HAUS_PROBE_Y=$(( iy + ih / 2 )) screen_probe)"
  nx=$(( sx + (sw - aw) / 2 ))
  ny=$(( sy + (sh - ah) / 2 ))
  # A window wider or taller than the display centres to a negative origin,
  # which puts its top-left off-screen and its title bar out of reach. Clamp to
  # the visible frame's origin: overflowing off the RIGHT is recoverable, off
  # the top-left is not.
  [ "$nx" -lt "$sx" ] && nx="$sx"
  [ "$ny" -lt "$sy" ] && ny="$sy"
  set_frame "$pid" "$nx" "$ny" "$aw" "$ah" 10
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
  local title="" command="" pin=0 cols="" rows="" exact=0 frame=""
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
      --match-focused) size_args=(--match-focused); exact=1; shift ;;
      --tiled)   size_args=(--tiled); exact=1; shift ;;
      --frame)   frame="$2"; exact=1; shift 2 ;;
      --)        shift; extra=("$@"); break ;;
      *) shift ;;
    esac
  done
  : "${title:?--title required}" "${command:?--command required}"

  # --frame is a geometry the caller ALREADY resolved, the same rectangle place
  # takes: it skips geom entirely. find.sh is why it exists — ⌘F has to stash
  # the summoner's frame for the ^s toggle anyway, and asking twice cost a
  # second AX round trip AND let the two answers disagree if focus moved in
  # between, which would size the overlay to one window and shrink it back onto
  # another. Resolve once, use it for both.
  #
  # ${arr[@]+"${arr[@]}"}: expand safely even when empty — macOS /bin/bash is
  # 3.2, where a bare "${arr[@]}" on an empty array trips `set -u`.
  local pos_x pos_y win_w win_h
  read -r pos_x pos_y win_w win_h <<< "${frame:-$(geom ${size_args[@]+"${size_args[@]}"})}"
  # A frame the caller couldn't capture (empty, truncated, nonsense) must not
  # become a window at 0×0 — resolve it the ordinary way instead.
  case "${pos_x:-x}${pos_y:-x}${win_w:-x}${win_h:-x}" in
    *[!0-9-]* | '')
      read -r pos_x pos_y win_w win_h <<< "$(geom ${size_args[@]+"${size_args[@]}"})" ;;
  esac

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
  # floating frame, which would undo the placement above — fatal in the two
  # modes whose whole point is a frame that lines up with something: covering
  # the summoning window (--match-focused) or the tiled desktop (--tiled). So
  # there, let aerospace have its say and then plant the frame again, last word
  # ours.
  #
  # ⚠️ This used to read "harmless when we only wanted roughly centered", and
  # that clause was the bug: the centred modes are the ONLY ones where nothing
  # gets the last word, so they are the only ones that can drift. They drifted
  # for a different reason than aerospace's memory — see `recenter` — but the
  # branch that would have corrected either was the one skipping them.
  if [ "$exact" = 1 ] && [ -n "$new_pid" ]; then
    sleep 0.05
    set_frame "$new_pid" "$pos_x" "$pos_y" "$win_w" "$win_h" 1
  fi

  # Centred modes: the window is whatever size the cell grid made it, so centre
  # THAT rather than the size we asked for. After the float flip, so aerospace
  # doesn't undo it; before raise/ring, so the outline follows the final frame.
  if [ "$exact" != 1 ] && [ -n "$new_pid" ]; then
    recenter "$new_pid" "$pos_x" "$pos_y" "$win_w" "$win_h"
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
