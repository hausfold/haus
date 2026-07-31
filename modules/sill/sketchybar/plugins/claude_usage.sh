#!/bin/bash
# claude_usage.sh — the reader half of the `claudeUsage` pill (opt-in via
# nebelhaus.sill.items). Puts Claude Code's own rate-limit gauges in the menu
# bar — the 5-hour session window and the 7-day weekly one — so you can see a
# limit coming instead of discovering it mid-task.
#
# The numbers are NOT scraped and NOT fetched: Claude Code hands its statusline
# `.rate_limits.{five_hour,seven_day}.{used_percentage,resets_at}` on every
# render, and modules/den/statusline.sh stashes them as one TSV line:
#     <5h %>\t<7d %>\t<5h resets epoch>\t<7d resets epoch>\t<written epoch>\t<provider>
# So there is no OAuth token to read out of the keychain, no /api/oauth/usage
# call, and nothing polling on a timer — the pill costs one `cut` per tick.
#
# Two entry paths:
#   • periodic / system_woke / refresh  → repaint icon+label from the stash
#   • mouse.clicked                     → (re)build + toggle the two-row popup
set -u
# Work whether we're run by the bar (rich env) or from a bare env (statusline.sh
# nudging us after a percentage moved): guarantee the nix profile + Homebrew on
# PATH, and $USER (sketchybar-msg resolves its socket via it). USER before PATH,
# since PATH interpolates it.
export USER="${USER:-$(id -un)}"
export PATH="/opt/homebrew/bin:/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:$PATH"
source "$HOME/.config/sketchybar/colors.sh"

STASH="${CLAUDE_STATUSLINE_CACHE:-$HOME/.cache/claude-statusline}/usage.tsv"
STALE=1800                       # 30 min with no render → say "last known", don't lie

# No AI session has ever rendered here → nothing true to show, stay invisible.
# (The item is created with drawing=off and only ever turned on below, so this is
# also the boot state: the pill appears the first time a pane reports.)
[ -s "$STASH" ] || exit 0
provider="claude"
IFS=$'\t' read -r p5 pw r5 rw stamp provider < "$STASH"
p5=${p5:-0}; pw=${pw:-0}; r5=${r5:-0}; rw=${rw:-0}; stamp=${stamp:-0}
provider=${provider:-claude}
now=$(date +%s)

case "$provider" in
  codex|openai) ICON="󱚦" ;;
  *)            ICON="󰏫" ;;
esac

# A window past its reset is empty again no matter what the last render said, so
# fold it to 0% here. That's what lets the pill stay honest for hours with no
# Claude pane open — the common "closed the laptop over the weekend" case heals
# on the next tick instead of showing Friday's 90%.
[ "$r5" -gt 0 ] && [ "$now" -ge "$r5" ] && p5=0
[ "$rw" -gt 0 ] && [ "$now" -ge "$rw" ] && pw=0

age=$((now - stamp))
stale=0; [ "$stamp" -gt 0 ] && [ "$age" -gt "$STALE" ] && stale=1

# Colour by the window that's closest to biting — a comfortable 5h window is no
# comfort at all if the weekly one is at 95%.
worst=$p5; [ "$pw" -gt "$worst" ] && worst=$pw
if   [ "$worst" -ge 90 ]; then COL=$RED
elif [ "$worst" -ge 75 ]; then COL=$PEACH
elif [ "$worst" -ge 50 ]; then COL=$YELLOW
else                           COL=$GREEN
fi
# Stale numbers get greyed rather than hidden: a hidden item's update_freq never
# ticks, so a pill that hides itself could never come back without another
# render to nudge it (the same trap agents.sh documents).
[ "$stale" = 1 ] && COL=$OVERLAY1

# ── click: two rows — one per window, each with its reset clock ───────────────
if [ "${SENDER:-}" = "mouse.clicked" ]; then
  sketchybar --remove '/claude_usage.popup\..*/' 2>/dev/null
  i=0
  row() { # row <title> <pct> <resets-epoch>
    local when=""
    if [ "$3" -gt "$now" ]; then
      # Same-day resets read better as a bare clock; the weekly one needs its day.
      if [ $(($3 - now)) -lt 86400 ]; then when="resets $(date -r "$3" '+%H:%M')"
      else                                  when="resets $(date -r "$3" '+%a %H:%M')"; fi
    fi
    sketchybar --add item "claude_usage.popup.$i" popup.claude_usage 2>/dev/null \
      --set "claude_usage.popup.$i" \
        icon="$1" icon.color="$SUBTEXT0" icon.font="Hack Nerd Font:Regular:13.0" \
        icon.padding_left=10 icon.padding_right=10 \
        label="$2%${when:+  ·  $when}" label.color="$TEXT" \
        label.font="Hack Nerd Font:Regular:13.0" label.padding_right=10 \
        background.drawing=off \
        click_script="sketchybar --set claude_usage popup.drawing=off"
    i=$((i + 1))
  }
  row "session" "$p5" "$r5"
  row "weekly " "$pw" "$rw"
  [ "$stale" = 1 ] && row "as of  " "$((age / 60))m ago" 0
  sketchybar --set claude_usage popup.drawing=toggle
  exit 0
fi

# ── update: one pill, session percentage, worst-case colour ───────────────────
sketchybar --set claude_usage drawing=on icon="$ICON" icon.color="$COL" \
  label="${p5}%" label.color="$COL"
