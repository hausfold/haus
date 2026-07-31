#!/bin/bash
# ai_usage.sh — the reader half of the `aiUsage` pill (opt-in via
# nebelhaus.sill.items). Puts rate-limit gauges for AI providers (Claude Code,
# Codex, etc.) or token API costs (Opencode, etc.) in the menu bar.
#
# Subscription TSV lines:
#     <5h %>\t<7d %>\t<5h resets epoch>\t<7d resets epoch>\t<written epoch>\t<provider>
# Cost TSV lines (e.g. usage-opencode.tsv):
#     <today $>\t<mtd $>\t0\t0\t<written epoch>\topencode\t<model>\t<provider_id>
#
# Two entry paths:
#   • periodic / system_woke / refresh  → repaint main pill icon+label
#   • mouse.clicked                     → open dropdown showing all reporting providers
set -u
export USER="${USER:-$(id -un)}"
export PATH="/opt/homebrew/bin:/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:$PATH"
source "$HOME/.config/sketchybar/colors.sh"

CACHE_DIR="${CLAUDE_STATUSLINE_CACHE:-$HOME/.cache/claude-statusline}"
ITEM_NAME="${NAME:-ai_usage}"
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
main_val5="0"
main_valw="0"
main_provider="claude"
main_model=""
main_provider_id=""
is_cost=0

for f in "${files[@]}"; do
  val5=0; valw=0; r5=0; rw=0; stamp=0; prov="claude"; model=""; prov_id=""
  IFS=$'\t' read -r val5 valw r5 rw stamp prov model prov_id < "$f" || true
  val5=${val5:-0}; valw=${valw:-0}; r5=${r5:-0}; rw=${rw:-0}; stamp=${stamp:-0}; prov=${prov:-claude}

  f_is_cost=0
  if [ "$prov" = "opencode" ] || [[ "$val5" =~ \. ]]; then
    f_is_cost=1
  else
    [ "$r5" -gt 0 ] && [ "$now" -ge "$r5" ] && val5=0
    [ "$rw" -gt 0 ] && [ "$now" -ge "$rw" ] && valw=0
  fi

  if [ "$PREFERRED" != "latest" ] && [ "$prov" = "$PREFERRED" ]; then
    main_val5=$val5
    main_valw=$valw
    main_provider=$prov
    main_model=${model:-}
    main_provider_id=${prov_id:-}
    is_cost=$f_is_cost
    latest_stamp=$stamp
    break
  elif [ "$stamp" -gt "$latest_stamp" ]; then
    latest_stamp=$stamp
    main_val5=$val5
    main_valw=$valw
    main_provider=$prov
    main_model=${model:-}
    main_provider_id=${prov_id:-}
    is_cost=$f_is_cost
  fi
done

# Evaluate worst percentage across subscription providers for status color
worst_all=0
for f in "${files[@]}"; do
  val5=0; valw=0; r5=0; rw=0; stamp=0; prov="claude"
  IFS=$'\t' read -r val5 valw r5 rw stamp prov < "$f" || true
  val5=${val5:-0}; valw=${valw:-0}; r5=${r5:-0}; rw=${rw:-0}; stamp=${stamp:-0}
  if [ "$prov" != "opencode" ] && ! [[ "$val5" =~ \. ]]; then
    [ "$r5" -gt 0 ] && [ "$now" -ge "$r5" ] && val5=0
    [ "$rw" -gt 0 ] && [ "$now" -ge "$rw" ] && valw=0
    [ "$val5" -gt "$worst_all" ] 2>/dev/null && worst_all=$val5
    [ "$valw" -gt "$worst_all" ] 2>/dev/null && worst_all=$valw
  fi
done

if [ "$is_cost" = 1 ]; then
  COL=$GREEN
else
  if   [ "$worst_all" -ge 90 ]; then COL=$RED
  elif [ "$worst_all" -ge 75 ]; then COL=$PEACH
  elif [ "$worst_all" -ge 50 ]; then COL=$YELLOW
  else                            COL=$GREEN
  fi
fi

age=$((now - latest_stamp))
stale=0; [ "$latest_stamp" -gt 0 ] && [ "$age" -gt "$STALE" ] && stale=1
[ "$stale" = 1 ] && COL=$OVERLAY1

case "$main_provider" in
  codex|openai) ICON=":openai:"; IFONT="sketchybar-app-font:Regular:16.0" ;;
  claude)       ICON=":claude:"; IFONT="sketchybar-app-font:Regular:16.0" ;;
  opencode)
    case "${main_provider_id:-$main_model}" in
      google*|gemini*)    ICON="✦"; IFONT="Hack Nerd Font:Bold:14.0" ;;
      anthropic*|claude*) ICON=":claude:"; IFONT="sketchybar-app-font:Regular:16.0" ;;
      openai*|gpt*)       ICON=":openai:"; IFONT="sketchybar-app-font:Regular:16.0" ;;
      *)                  ICON="󰏫"; IFONT="Hack Nerd Font:Bold:14.0" ;;
    esac
    ;;
  *)            ICON="󰏫";       IFONT="Hack Nerd Font:Bold:14.0" ;;
esac

if [ "$is_cost" = 1 ]; then
  MAIN_LABEL="\$$main_val5"
else
  MAIN_LABEL="${main_val5}%"
fi

# ── click: show expanded info for all reporting providers ─────────────────────
if [ "${SENDER:-}" = "mouse.clicked" ]; then
  sketchybar --remove "/${ITEM_NAME}\.popup\..*/" 2>/dev/null
  i=0
  for f in "${files[@]}"; do
    val5=0; valw=0; r5=0; rw=0; stamp=0; prov="claude"; model=""; prov_id=""
    IFS=$'\t' read -r val5 valw r5 rw stamp prov model prov_id < "$f" || true
    val5=${val5:-0}; valw=${valw:-0}; r5=${r5:-0}; rw=${rw:-0}; stamp=${stamp:-0}; prov=${prov:-claude}

    f_is_cost=0
    if [ "$prov" = "opencode" ] || [[ "$val5" =~ \. ]]; then
      f_is_cost=1
    else
      [ "$r5" -gt 0 ] && [ "$now" -ge "$r5" ] && val5=0
      [ "$rw" -gt 0 ] && [ "$now" -ge "$rw" ] && valw=0
    fi
    f_age=$((now - stamp))
    f_stale=0; [ "$stamp" -gt 0 ] && [ "$f_age" -gt "$STALE" ] && f_stale=1

    case "$prov" in
      codex|openai) p_icon=":openai:"; p_font="sketchybar-app-font:Regular:16.0"; p_name="Codex" ;;
      claude)       p_icon=":claude:"; p_font="sketchybar-app-font:Regular:16.0"; p_name="Claude" ;;
      opencode)
        case "${prov_id:-$model}" in
          google*|gemini*)    p_icon="✦"; p_font="Hack Nerd Font:Bold:13.0"; p_name="Opencode (${model:-gemini})" ;;
          anthropic*|claude*) p_icon=":claude:"; p_font="sketchybar-app-font:Regular:16.0"; p_name="Opencode (${model:-claude})" ;;
          openai*|gpt*)       p_icon=":openai:"; p_font="sketchybar-app-font:Regular:16.0"; p_name="Opencode (${model:-gpt})" ;;
          *)                  p_icon="󰏫"; p_font="Hack Nerd Font:Bold:13.0"; p_name="Opencode (${model:-api})" ;;
        esac
        ;;
      *)            p_icon="󰏫";       p_font="Hack Nerd Font:Bold:13.0";       p_name="$prov" ;;
    esac

    # Provider header row
    sketchybar --add item "${ITEM_NAME}.popup.$i" popup.${ITEM_NAME} 2>/dev/null \
      --set "${ITEM_NAME}.popup.$i" \
        icon="$p_icon" icon.color="$PINK" icon.font="$p_font" \
        icon.padding_left=10 icon.padding_right=6 \
        label="$p_name" label.color="$TEXT" label.font="Hack Nerd Font:Bold:13.0" \
        background.drawing=off \
        click_script="sketchybar --set ${ITEM_NAME} popup.drawing=off"
    i=$((i + 1))

    # Usage rows helper
    row() { # row <label> <val_str>
      sketchybar --add item "${ITEM_NAME}.popup.$i" popup.${ITEM_NAME} 2>/dev/null \
        --set "${ITEM_NAME}.popup.$i" \
          icon="" icon.padding_left=0 icon.padding_right=0 \
          label="$1  $2" label.color="$SUBTEXT0" \
          label.font="Hack Nerd Font:Regular:13.0" label.padding_left=22 label.padding_right=10 \
          background.drawing=off \
          click_script="sketchybar --set ${ITEM_NAME} popup.drawing=off"
      i=$((i + 1))
    }

    if [ "$f_is_cost" = 1 ]; then
      row "today " "\$$val5"
      row "monthly" "\$$valw"
    else
      when=""
      if [ "$r5" -gt "$now" ]; then
        if [ $(($r5 - now)) -lt 86400 ]; then when="resets $(date -r "$r5" '+%H:%M')"
        else                                  when="resets $(date -r "$r5" '+%a %H:%M')"; fi
      fi
      row "session" "${val5}%${when:+  ·  $when}"

      when_w=""
      if [ "$rw" -gt "$now" ]; then
        if [ $(($rw - now)) -lt 86400 ]; then when_w="resets $(date -r "$rw" '+%H:%M')"
        else                                  when_w="resets $(date -r "$rw" '+%a %H:%M')"; fi
      fi
      row "weekly " "${valw}%${when_w:+  ·  $when_w}"
    fi

    if [ "$f_stale" = 1 ]; then
      sketchybar --add item "${ITEM_NAME}.popup.$i" popup.${ITEM_NAME} 2>/dev/null \
        --set "${ITEM_NAME}.popup.$i" \
          icon="" icon.padding_left=0 icon.padding_right=0 \
          label="as of $((f_age / 60))m ago" label.color="$OVERLAY1" \
          label.font="Hack Nerd Font:Italic:12.0" label.padding_left=22 label.padding_right=10 \
          background.drawing=off \
          click_script="sketchybar --set ${ITEM_NAME} popup.drawing=off"
      i=$((i + 1))
    fi
  done
  sketchybar --set ${ITEM_NAME} popup.drawing=toggle
  exit 0
fi

# ── update: main pill icon + label + colour ───────────────────────────────────
sketchybar --set ${ITEM_NAME} drawing=on icon="$ICON" icon.font="$IFONT" icon.color="$COL" \
  label="$MAIN_LABEL" label.color="$COL"

