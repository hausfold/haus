#!/bin/bash
# ai_usage.sh — the reader half of the `aiUsage` pill (opt-in via
# nebelhaus.sill.items). Puts rate-limit gauges for AI providers (Claude Code,
# Codex, etc.) in the menu bar — 5-hour session window and 7-day weekly window.
#
# Numbers are stashed as TSV lines per provider (`usage-<provider>.tsv` or `usage.tsv`):
#     <5h %>\t<7d %>\t<5h resets epoch>\t<7d resets epoch>\t<written epoch>\t<provider>
#
# Two entry paths:
#   • periodic / system_woke / refresh  → repaint main pill icon+label
#   • mouse.clicked                     → open dropdown showing all reporting providers
set -u
export USER="${USER:-$(id -un)}"
export PATH="/opt/homebrew/bin:/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:$PATH"
source "$HOME/.config/sketchybar/colors.sh"

CACHE_DIR="${CLAUDE_STATUSLINE_CACHE:-$HOME/.cache/claude-statusline}"
STALE=300                        # 5 min with no render → mark stale
now=$(date +%s)

# Collect provider files: prefer usage-*.tsv over usage.tsv to avoid duplicates
files=()
if [ -d "$CACHE_DIR" ]; then
  for f in "$CACHE_DIR"/usage-*.tsv; do
    [ -s "$f" ] && files+=("$f")
  done
  if [ ${#files[@]} -eq 0 ] && [ -s "$CACHE_DIR/usage.tsv" ]; then
    files+=("$CACHE_DIR/usage.tsv")
  fi
fi

[ ${#files[@]} -gt 0 ] || exit 0

[ -f "$HOME/.config/sketchybar/ai_usage_config.sh" ] && source "$HOME/.config/sketchybar/ai_usage_config.sh"
PREFERRED="${SILL_AI_USAGE_PROVIDER:-latest}"

# Determine active/preferred provider for the main pill
latest_stamp=-1
main_p5=0
main_pw=0
main_provider="claude"

for f in "${files[@]}"; do
  p5=0; pw=0; r5=0; rw=0; stamp=0; prov="claude"
  IFS=$'\t' read -r p5 pw r5 rw stamp prov < "$f"
  p5=${p5:-0}; pw=${pw:-0}; r5=${r5:-0}; rw=${rw:-0}; stamp=${stamp:-0}; prov=${prov:-claude}
  [ "$r5" -gt 0 ] && [ "$now" -ge "$r5" ] && p5=0
  [ "$rw" -gt 0 ] && [ "$now" -ge "$rw" ] && pw=0
  if [ "$PREFERRED" != "latest" ] && [ "$prov" = "$PREFERRED" ]; then
    main_p5=$p5
    main_pw=$pw
    main_provider=$prov
    latest_stamp=$stamp
    break
  elif [ "$stamp" -gt "$latest_stamp" ]; then
    latest_stamp=$stamp
    main_p5=$p5
    main_pw=$pw
    main_provider=$prov
  fi
done

# Evaluate worst percentage across all providers for status color
worst_all=0
for f in "${files[@]}"; do
  p5=0; pw=0; r5=0; rw=0; stamp=0; prov="claude"
  IFS=$'\t' read -r p5 pw r5 rw stamp prov < "$f"
  p5=${p5:-0}; pw=${pw:-0}; r5=${r5:-0}; rw=${rw:-0}; stamp=${stamp:-0}
  [ "$r5" -gt 0 ] && [ "$now" -ge "$r5" ] && p5=0
  [ "$rw" -gt 0 ] && [ "$now" -ge "$rw" ] && pw=0
  [ "$p5" -gt "$worst_all" ] && worst_all=$p5
  [ "$pw" -gt "$worst_all" ] && worst_all=$pw
done

# Colour by worst usage across all windows
if   [ "$worst_all" -ge 90 ]; then COL=$RED
elif [ "$worst_all" -ge 75 ]; then COL=$PEACH
elif [ "$worst_all" -ge 50 ]; then COL=$YELLOW
else                            COL=$GREEN
fi

age=$((now - latest_stamp))
stale=0; [ "$latest_stamp" -gt 0 ] && [ "$age" -gt "$STALE" ] && stale=1
[ "$stale" = 1 ] && COL=$OVERLAY1

case "$main_provider" in
  codex|openai) ICON=":openai:"; IFONT="sketchybar-app-font:Regular:16.0" ;;
  claude)       ICON=":claude:"; IFONT="sketchybar-app-font:Regular:16.0" ;;
  *)            ICON="󰏫";       IFONT="Hack Nerd Font:Bold:14.0" ;;
esac

# ── click: show expanded info for all reporting providers ─────────────────────
if [ "${SENDER:-}" = "mouse.clicked" ]; then
  sketchybar --remove '/ai_usage.popup\..*/' 2>/dev/null
  i=0
  for f in "${files[@]}"; do
    p5=0; pw=0; r5=0; rw=0; stamp=0; prov="claude"
    IFS=$'\t' read -r p5 pw r5 rw stamp prov < "$f"
    p5=${p5:-0}; pw=${pw:-0}; r5=${r5:-0}; rw=${rw:-0}; stamp=${stamp:-0}; prov=${prov:-claude}
    [ "$r5" -gt 0 ] && [ "$now" -ge "$r5" ] && p5=0
    [ "$rw" -gt 0 ] && [ "$now" -ge "$rw" ] && pw=0
    f_age=$((now - stamp))
    f_stale=0; [ "$stamp" -gt 0 ] && [ "$f_age" -gt "$STALE" ] && f_stale=1

    case "$prov" in
      codex|openai) p_icon=":openai:"; p_font="sketchybar-app-font:Regular:16.0"; p_name="Codex" ;;
      claude)       p_icon=":claude:"; p_font="sketchybar-app-font:Regular:16.0"; p_name="Claude" ;;
      *)            p_icon="󰏫";       p_font="Hack Nerd Font:Bold:13.0";       p_name="$prov" ;;
    esac

    # Provider header row
    sketchybar --add item "ai_usage.popup.$i" popup.ai_usage 2>/dev/null \
      --set "ai_usage.popup.$i" \
        icon="$p_icon" icon.color="$PINK" icon.font="$p_font" \
        icon.padding_left=10 icon.padding_right=6 \
        label="$p_name" label.color="$TEXT" label.font="Hack Nerd Font:Bold:13.0" \
        background.drawing=off \
        click_script="sketchybar --set ai_usage popup.drawing=off"
    i=$((i + 1))

    # Usage rows helper
    row() { # row <label> <pct> <resets-epoch>
      local when=""
      if [ "$3" -gt "$now" ]; then
        if [ $(($3 - now)) -lt 86400 ]; then when="resets $(date -r "$3" '+%H:%M')"
        else                                  when="resets $(date -r "$3" '+%a %H:%M')"; fi
      fi
      sketchybar --add item "ai_usage.popup.$i" popup.ai_usage 2>/dev/null \
        --set "ai_usage.popup.$i" \
          icon="" icon.padding_left=0 icon.padding_right=0 \
          label="$1  $2%${when:+  ·  $when}" label.color="$SUBTEXT0" \
          label.font="Hack Nerd Font:Regular:13.0" label.padding_left=22 label.padding_right=10 \
          background.drawing=off \
          click_script="sketchybar --set ai_usage popup.drawing=off"
      i=$((i + 1))
    }
    row "session" "$p5" "$r5"
    row "weekly " "$pw" "$rw"
    if [ "$f_stale" = 1 ]; then
      sketchybar --add item "ai_usage.popup.$i" popup.ai_usage 2>/dev/null \
        --set "ai_usage.popup.$i" \
          icon="" icon.padding_left=0 icon.padding_right=0 \
          label="as of $((f_age / 60))m ago" label.color="$OVERLAY1" \
          label.font="Hack Nerd Font:Italic:12.0" label.padding_left=22 label.padding_right=10 \
          background.drawing=off \
          click_script="sketchybar --set ai_usage popup.drawing=off"
      i=$((i + 1))
    fi
  done
  sketchybar --set ai_usage popup.drawing=toggle
  exit 0
fi

# ── update: main pill icon + session percentage + worst-case colour ──────────
sketchybar --set ai_usage drawing=on icon="$ICON" icon.font="$IFONT" icon.color="$COL" \
  label="${main_p5}%" label.color="$COL"
