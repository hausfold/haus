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
# provider_style() — the shared icon/font/name table, so the agents pill draws
# the same mark for a client that this pill draws for its usage.
# shellcheck source=./ai-provider.sh
source "$HOME/.config/sketchybar/plugins/ai-provider.sh"

CACHE_DIR="${CLAUDE_STATUSLINE_CACHE:-$HOME/.cache/claude-statusline}"
ITEM_NAME="${NAME:-ai_usage}"
STALE=300                        # 5 min with no render → mark stale
FEED_TTL=180                     # how often we re-pull the Codex/Opencode feeds
now=$(date +%s)

# ── keep the PULLED feeds alive with no Claude session anywhere ───────────────
# Claude's row is pushed here for free by its statusline on every render. Codex
# (an account API call) and Opencode (a sqlite read) have no such client-side
# writer — the refresher pulls them — and the refresher only ever ran because a
# Claude statusline kicked it. So on a machine whose default agent is Codex or
# Opencode the pill used to grey out and stay grey. Kick it here instead, on its
# own TTL: --usage-only skips the panel and the `gh` traffic, and the refresher's
# own mkdir-lock means a concurrent full pass just makes this one exit.
kick="$CACHE_DIR/.usage-kick"
kick_at=$(stat -f %m "$kick" 2>/dev/null || echo 0)
case "$kick_at" in '' | *[!0-9]*) kick_at=0 ;; esac
if [ $((now - kick_at)) -ge "$FEED_TTL" ] && command -v claude-statusline-refresh >/dev/null 2>&1; then
  mkdir -p "$CACHE_DIR" && touch "$kick"
  (claude-statusline-refresh --usage-only >/dev/null 2>&1 &)
fi

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

main_pct=0
if [ "$is_cost" = 0 ]; then
  main_pct=${main_val5:-0}
  if [ "${main_valw:-0}" -gt "$main_pct" ] 2>/dev/null; then
    main_pct=$main_valw
  fi
fi

if [ "$is_cost" = 1 ]; then
  COL=$GREEN
else
  if   [ "$main_pct" -ge 90 ]; then COL=$RED
  elif [ "$main_pct" -ge 75 ]; then COL=$PEACH
  elif [ "$main_pct" -ge 50 ]; then COL=$YELLOW
  else                            COL=$GREEN
  fi
fi

age=$((now - latest_stamp))
stale=0; [ "$latest_stamp" -gt 0 ] && [ "$age" -gt "$STALE" ] && stale=1
[ "$stale" = 1 ] && COL=$OVERLAY1

provider_style "$main_provider" "${main_provider_id:-$main_model}" 14.0
ICON="$P_ICON"; IFONT="$P_FONT"

if [ "$is_cost" = 1 ]; then
  MAIN_LABEL="\$$main_val5"
else
  MAIN_LABEL="${main_pct}%"
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

    provider_style "$prov" "${prov_id:-$model}" 13.0
    p_icon="$P_ICON"; p_font="$P_FONT"; p_name="$P_NAME"

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

