#!/bin/bash
# ai_usage.sh — the reader half of the `aiUsage` pill (opt-in via
# haus.sill.items). Puts rate-limit gauges for AI providers (Claude Code,
# Codex, etc.) or token API costs (Opencode, etc.) in the menu bar.
#
# Subscription TSV lines:
#     <5h %>\t<7d %>\t<5h resets epoch>\t<7d resets epoch>\t<written epoch>\t<provider>
# Cost TSV lines (e.g. usage-opencode.tsv):
#     <today $>\t<mtd $>\t0\t0\t<written epoch>\topencode\t<model>\t<provider_id>
# Token TSV lines (tokens-<provider>.tsv, optional, dropdown only):
#     <today tokens>\t<all-time tokens>\t<written epoch>
#
# Two entry paths:
#   • periodic / system_woke / refresh  → repaint main pill icon+label
#   • mouse.clicked                     → open dropdown showing all reporting providers
set -u
export USER="${USER:-$(id -un)}"
export PATH="/opt/homebrew/bin:/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:$PATH"
source "$HOME/.config/sketchybar/colors.sh"
source "$HOME/.config/sketchybar/sizes.sh"
# provider_style() — the shared icon/font/name table, so the agents pill draws
# the same mark for a client that this pill draws for its usage.
# shellcheck source=./ai-provider.sh
source "$HOME/.config/sketchybar/plugins/ai-provider.sh"

CACHE_DIR="${CLAUDE_STATUSLINE_CACHE:-$HOME/.cache/claude-statusline}"
ITEM_NAME="${NAME:-ai_usage}"

tokens_label() { # tokens_label <d> <w> <m> <all> — the token score, TWO periods
  # per line, printed as one line per output line:
  #
  #    220M d  ·  2.02B w
  #    590M m  ·  7.65B total
  #
  # Four periods on one line runs the dropdown off the side of a laptop screen,
  # so they wrap into a 2×2 block. Cells are padded to a common width — number
  # right-aligned, period left — which in the bar's monospace font is what makes
  # the second line sit under the first instead of beside it.
  #
  # Numbers are three significant figures with the trailing zeros filed off, so a
  # cell stays the same handful of characters whether it reads 950K or 7.65B and
  # never pads a number with digits it hasn't earned. Empty periods are dropped
  # rather than printed as 0 — the block just gets smaller, which is its own
  # signal that today (or this month) hasn't started yet. Nothing at all is
  # printed when the all-time total is zero; that provider gets no row.
  awk -v d="${1:-0}" -v w="${2:-0}" -v m="${3:-0}" -v a="${4:-0}" 'BEGIN {
    split("K M B T", u, " ")
    if (a + 0 <= 0) exit
    n = split("d w m total", tag, " ")
    v[1] = d; v[2] = w; v[3] = m; v[4] = a
    for (i = 1; i <= n; i++) {
      if (v[i] + 0 <= 0) continue
      k++
      num[k] = si(v[i]); per[k] = tag[i]
    }
    # Widths are per COLUMN, and the period is padded only where something has to
    # line up after it — the left column of a line that has a right column. Pad
    # every period to the widest and "220M d" grows five dead spaces to keep pace
    # with "7.65B total", which is not alignment, just a hole.
    for (i = 1; i <= k; i++) {
      c = (i % 2) ? 1 : 2
      if (length(num[i]) > nw[c]) nw[c] = length(num[i])
      if (c == 1 && i < k && length(per[i]) > pw) pw = length(per[i])
    }
    for (i = 1; i <= k; i++) {
      c = (i % 2) ? 1 : 2
      cell = sprintf("%*s %-*s", nw[c], num[i], (c == 1 ? pw : 0), per[i])
      line = (c == 1) ? cell : line "  ·  " cell
      if (c == 2 || i == k) { sub(/ +$/, "", line); print line }
    }
  }
  function si(x,   j, s, scale, unit) {
    scale = 1; unit = ""
    for (j = 4; j >= 1; j--) if (x >= 1000 ^ j) { scale = 1000 ^ j; unit = u[j]; break }
    x = x / scale
    s = (x >= 100) ? sprintf("%.0f", x) : (x >= 10 ? sprintf("%.1f", x) : sprintf("%.2f", x))
    if (s ~ /\./) { sub(/0+$/, "", s); sub(/\.$/, "", s) }
    return s unit
  }'
}

read_tokens() { # read_tokens <file> — T_D/T_W/T_M/T_ALL, false if there's no row
  T_D=0; T_W=0; T_M=0; T_ALL=0
  [ -s "$1" ] || return 1
  local at=""
  IFS=$'\t' read -r T_D T_W T_M T_ALL at <"$1" || true
  # All five columns or none: a file left by an older rice has a different shape,
  # and reading it anyway would file the week's tokens under the day.
  [ -n "$at" ] || return 1
  T_D=${T_D:-0}; T_W=${T_W:-0}; T_M=${T_M:-0}; T_ALL=${T_ALL:-0}
}

# Continuation rows are indented with PADDING, never with spaces in the label:
# sketchybar sizes an item from its label with the leading whitespace trimmed and
# then draws the untrimmed string, so a leading run of spaces buys nothing but a
# label clipped by exactly the width of its own indent. (A no-break space is
# trimmed just the same — that was the obvious fix and it does not work.)
#
# So the indent is a pixel count, which means it has to be DERIVED, not written
# down: the row's usual 22, plus the nine columns of `tokens ` and the two spaces
# after it, at a MONOSPACE advance of ~0.602em in whatever size ui.scale settled
# on. At the default FS_SMALL=13 that is 92, which is what measuring it by hand
# gave (against Hack, when the bar had a font of its own; JetBrains Mono and
# Fira Code are 0.6em, so the number survived the switch to
# haus.fonts.mono.name). It is the one place in the bar that assumes a
# fixed advance — name a proportional family there and this indent drifts,
# which is an alignment wobble in one popup rather than a broken bar.
TOKEN_INDENT=$(awk -v s="${FS_SMALL:-13}" 'BEGIN { printf "%.0f", 22 + 9 * s * 0.602 }')

token_block() { # token_block <d> <w> <m> <all> — the score, labelled then indented
  local blk line first=1
  blk=$(tokens_label "$1" "$2" "$3" "$4")
  [ -n "$blk" ] || return 0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    # Only the first line carries the `tokens` label; the rest sit under it.
    if [ "$first" = 1 ]; then row "tokens " "$line"; first=0
    else                      row "" "$line" "$TOKEN_INDENT"
    fi
  done <<<"$blk"
}
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

provider_style "$main_provider" "${main_provider_id:-$main_model}" "$FS_LABEL"
ICON="$P_ICON"; IFONT="$P_FONT"

if [ "$is_cost" = 1 ]; then
  MAIN_LABEL="\$$main_val5"
else
  MAIN_LABEL="${main_pct}%"
fi

# ── click: show expanded info for all reporting providers ─────────────────────
if [ "${SENDER:-}" = "mouse.clicked" ]; then
  # Closing is just hiding: a click while the popup is UP must not rebuild the
  # rows first. This pill draws ~16 of them, and the old code spent one
  # sketchybar invocation per row — each one a re-layout of a popup the user can
  # see — so closing it flashed through a shrink/regrow before finally toggling
  # off. Query the current state and take the cheap path out; the rows are
  # rebuilt on the way back IN, where the popup is hidden and nothing shows.
  if [ "$(sketchybar --query "$ITEM_NAME" 2>/dev/null | jq -r '.popup.drawing')" = "on" ]; then
    sketchybar --set "$ITEM_NAME" popup.drawing=off
    exit 0
  fi

  sketchybar --remove "/${ITEM_NAME}\.popup\..*/" 2>/dev/null
  # Every row below is accumulated into ARGS and handed to ONE sketchybar call at
  # the end, so the popup appears fully formed in a single repaint instead of
  # growing a row at a time.
  ARGS=()
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

    provider_style "$prov" "${prov_id:-$model}" "$FS_SMALL"
    p_icon="$P_ICON"; p_font="$P_FONT"; p_name="$P_NAME"

    # Provider header row
    ARGS+=(--add item "${ITEM_NAME}.popup.$i" "popup.${ITEM_NAME}"
      --set "${ITEM_NAME}.popup.$i"
        icon="$p_icon" icon.color="$PINK" icon.font="$p_font"
        icon.padding_left=10 icon.padding_right=6
        label="$p_name" label.color="$TEXT" label.font="${BAR_FONT}:Bold:$FS_SMALL"
        background.drawing=off
        click_script="sketchybar --set ${ITEM_NAME} popup.drawing=off")
    i=$((i + 1))

    # Usage rows helper
    row() { # row <label> <val_str> [label.padding_left] — an empty label draws the
      # value alone, with no gap in front of it to be clipped (see TOKEN_INDENT)
      ARGS+=(--add item "${ITEM_NAME}.popup.$i" "popup.${ITEM_NAME}"
        --set "${ITEM_NAME}.popup.$i"
          icon="" icon.padding_left=0 icon.padding_right=0
          label="${1:+$1  }$2" label.color="$SUBTEXT0"
          label.font="${BAR_FONT}:Regular:$FS_SMALL"
          label.padding_left="${3:-22}" label.padding_right=10
          background.drawing=off
          click_script="sketchybar --set ${ITEM_NAME} popup.drawing=off")
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

    # Tokens: the score row. Every number above is a fraction of something you
    # are allowed; this is the raw count of tokens actually moved, which no
    # client shows anywhere and which nothing here throttles or warns on. Only
    # providers whose token feed exists get the row (see statusline-refresh.sh).
    if read_tokens "$CACHE_DIR/tokens-$prov.tsv"; then
      token_block "$T_D" "$T_W" "$T_M" "$T_ALL"
    fi

    if [ "$f_stale" = 1 ]; then
      ARGS+=(--add item "${ITEM_NAME}.popup.$i" "popup.${ITEM_NAME}"
        --set "${ITEM_NAME}.popup.$i"
          icon="" icon.padding_left=0 icon.padding_right=0
          label="as of $((f_age / 60))m ago" label.color="$OVERLAY1"
          label.font="${BAR_FONT}:Italic:$FS_TINY" label.padding_left=22 label.padding_right=10
          background.drawing=off
          click_script="sketchybar --set ${ITEM_NAME} popup.drawing=off")
      i=$((i + 1))
    fi
  done

  # ── grand total ─────────────────────────────────────────────────────────────
  # Every token feed on the machine added up, because the interesting number when
  # you drive three clients is what YOU spent, not what any one of them did. Only
  # drawn when more than one provider reports: with a single feed this row would
  # be the row above it, restated.
  g_d=0; g_w=0; g_m=0; g_all=0; g_n=0
  for tf in "$CACHE_DIR"/tokens-*.tsv; do
    read_tokens "$tf" || continue
    g_d=$(( g_d + T_D )); g_w=$(( g_w + T_W ))
    g_m=$(( g_m + T_M )); g_all=$(( g_all + T_ALL ))
    g_n=$(( g_n + 1 ))
  done
  if [ "$g_n" -gt 1 ] && [ "$g_all" -gt 0 ]; then
    ARGS+=(--add item "${ITEM_NAME}.popup.$i" "popup.${ITEM_NAME}"
      --set "${ITEM_NAME}.popup.$i"
        icon="∑" icon.color="$PINK" icon.font="${BAR_FONT}:Bold:14.0"
        icon.padding_left=10 icon.padding_right=6
        label="Everything" label.color="$TEXT" label.font="${BAR_FONT}:Bold:13.0"
        background.drawing=off
        click_script="sketchybar --set ${ITEM_NAME} popup.drawing=off")
    i=$((i + 1))
    token_block "$g_d" "$g_w" "$g_m" "$g_all"
  fi

  # One message: every row, then reveal. Not `toggle` — the state was already
  # settled above, and toggling off a popup whose rows we just rebuilt is exactly
  # the double-open the flash came from if a stray click arrives mid-build.
  [ ${#ARGS[@]} -gt 0 ] && sketchybar "${ARGS[@]}" 2>/dev/null
  sketchybar --set "$ITEM_NAME" popup.drawing=on
  # Then hand it to sillpop so it also closes on the first click anywhere else —
  # the dismissal sketchybar can't do, since it only hears clicks on its own
  # items. Backgrounded and after the reveal, so opening costs what it did above.
  /run/current-system/sw/bin/sillpop arm "$ITEM_NAME" 2>/dev/null &
  exit 0
fi

# ── update: main pill icon + label + colour ───────────────────────────────────
sketchybar --set ${ITEM_NAME} drawing=on icon="$ICON" icon.font="$IFONT" icon.color="$COL" \
  label="$MAIN_LABEL" label.color="$COL"

