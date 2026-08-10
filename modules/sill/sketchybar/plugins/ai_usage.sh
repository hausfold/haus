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
#
# ── how the dropdown is drawn ─────────────────────────────────────────────────
# Everything below obeys two rules, and the whole look falls out of them.
#
# **A hue on a mark means identity; a hue on a number means state.** The header
# glyph carries the client's brand accent (provider_style's P_COLOR, picked from
# the half of the palette the ladder never touches), and the ladder —
# GREEN → YELLOW → PEACH → RED — appears only on values, on the same thresholds
# the pill paints ITSELF with, via the pct_color() both paths now share. Before
# this, 92% and 0% were the same grey in the dropdown while the pill outside it
# was red: the one number worth opening the popup for was the one it hid.
#
# **Three weights of type, and nothing carries importance by position alone.**
#   header  Bold  FS_LABEL, TEXT, brand icon, taller row  → which client
#   value   Bold  FS_SMALL, ladder colour                 → the answer
#   descr   Regular FS_SMALL, OVERLAY1, left column       → what the answer is of
#   meta    Italic  FS_TINY, OVERLAY0, short row          → staleness, footnotes
# A stale provider drops its values to OVERLAY0 too, so a block whose feed died
# greys out as a whole exactly like the pill does — no row is left claiming a
# number it can no longer stand behind.
#
# The descriptor sits in the item's ICON and the value in its LABEL, because
# that is the only way to give one row two colours. They line up in a column
# because the gap is a PIXEL count derived from the monospace advance
# (desc_pad), not trailing spaces — sketchybar trims a label's whitespace when
# it sizes the item and then draws the untrimmed string, so padding with spaces
# buys a clipped row (the same trap TOKEN_INDENT documents below).
set -u
export USER="${USER:-$(id -un)}"
export PATH="/opt/homebrew/bin:/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:$PATH"
source "$HOME/.config/sketchybar/colors.sh"
# $SB — which bar this pill lives on (haus.sill.bottom.items can move it to
# the bottom bar, a separate SketchyBar instance addressed by its own
# binary). SILL_ITEM is the fallback bar.sh needs on the HOOK path: invoked
# from outside SketchyBar there is no $BAR_NAME to route on, and not every
# caller sets $NAME either.
SILL_ITEM=ai_usage
source "$HOME/.config/sketchybar/bar.sh"

source "$HOME/.config/sketchybar/sizes.sh"
# provider_style() — the shared icon/font/name table, so the agents pill draws
# the same mark for a client that this pill draws for its usage.
# shellcheck source=./ai-provider.sh
source "$HOME/.config/sketchybar/plugins/ai-provider.sh"

CACHE_DIR="${CLAUDE_STATUSLINE_CACHE:-$HOME/.cache/claude-statusline}"
ITEM_NAME="${NAME:-ai_usage}"

pct_color() { # pct_color <pct> — the one ladder, so the pill and the row it
  # explains can never disagree about whether 76% is worth worrying over.
  if   [ "${1:-0}" -ge 90 ]; then printf '%s' "$RED"
  elif [ "${1:-0}" -ge 75 ]; then printf '%s' "$PEACH"
  elif [ "${1:-0}" -ge 50 ]; then printf '%s' "$YELLOW"
  else                            printf '%s' "$GREEN"
  fi
}

GAUGE_CELLS=10
GAUGE_FILL="█"                   # full block — the bar
GAUGE_TRACK="▁"                  # lower eighth block — the rail it sits on
gauge() { # gauge <pct> — a meter in block elements, sharing the row's colour
  # A percentage is a quantity, and a number alone makes you do the comparing.
  # Ten cells is the most that fits beside the value and the reset time without
  # pushing the popup wider than the pill it hangs off; at that width one cell
  # is 10 points, which is finer than the decision the meter is there to serve.
  #
  # One item draws one colour, so the track can't be a second, dimmer one — it
  # has to differ in INK instead: a full block against a one-eighth rail, both
  # sitting on the same baseline. Two glyphs were tried and rejected on the live
  # bar — ░ fills an untouched limit with texture, so 0% reads as busy from
  # across the room, and ▄ renders with gaps between cells in JetBrains Mono, so
  # a solid 45% reads as five separate things. A rail reads as empty, because it
  # is; a full block reads as one bar, because it is.
  awk -v p="${1:-0}" -v n="$GAUGE_CELLS" -v f="$GAUGE_FILL" -v t="$GAUGE_TRACK" 'BEGIN {
    if (p + 0 < 0) p = 0; if (p + 0 > 100) p = 100
    k = int(p * n / 100 + 0.5)
    for (i = 0; i < n; i++) printf "%s", (i < k ? f : t)
  }'
}

ago() { # ago <seconds> — "90m", "5h 12m", "4d". The old row said `6962m ago`,
  # which is a true number nobody can read as "this feed died on Tuesday".
  awk -v s="${1:-0}" 'BEGIN {
    m = int(s / 60); h = int(m / 60); d = int(h / 24)
    if      (d >= 1) printf "%dd %dh", d, h % 24
    else if (h >= 1) printf "%dh %dm", h, m % 60
    else             printf "%dm", m
  }'
}

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

# ── the column grid ───────────────────────────────────────────────────────────
# Rows never indent with spaces in the text: sketchybar sizes an item from its
# label with the leading whitespace trimmed and then draws the untrimmed string,
# so a leading run of spaces buys nothing but a label clipped by exactly the
# width of its own indent. (A no-break space is trimmed just the same — that was
# the obvious fix and it does not work.) The same trimming is why the descriptor
# column can't be right-padded to a common width either.
#
# So every horizontal measure here is a pixel count, DERIVED rather than written
# down, from a MONOSPACE advance of ~0.602em at whatever size ui.scale settled
# on. (Measured by hand against Hack, when the bar had a font of its own;
# JetBrains Mono and Fira Code are 0.6em, so the number survived the switch to
# haus.fonts.mono.name.) It is the one place in the bar that assumes a fixed
# advance — name a proportional family there and the columns drift, which is an
# alignment wobble in one popup rather than a broken bar.
ROW_INDENT=22                    # left margin of a value row, under its header
DESC_COLS=7                      # widest descriptor: `session` / `monthly`
DESC_GAP=12                      # descriptor → value gutter
ADVANCE=$(awk -v s="${FS_SMALL:-13}" 'BEGIN { printf "%.4f", s * 0.602 }')
# Where the value column starts, in points from the popup's left edge. A
# continuation row (the second line of the token block) has no descriptor of its
# own and pads its LABEL to exactly here, which is what puts it under the line
# above instead of beside it.
TOKEN_INDENT=$(awk -v a="$ADVANCE" -v i="$ROW_INDENT" -v c="$DESC_COLS" -v g="$DESC_GAP" \
  'BEGIN { printf "%.0f", i + c * a + g }')
desc_pad() { # desc_pad <descriptor> [extra columns] — the icon's right padding
  # that lands the value on the column, whatever this row happened to call
  # itself, plus any leading blanks the value wanted and can't have (see unpad).
  awk -v n="${#1}" -v a="$ADVANCE" -v c="$DESC_COLS" -v g="$DESC_GAP" -v x="${2:-0}" \
    'BEGIN { printf "%.0f", (c - n + x) * a + g }'
}

# A value that right-aligns its number — ` 7%` under `46%`, ` 733M` under
# `6.14B` — asks for leading blanks, which is the one thing a label may not
# have: they are trimmed when the item is sized and then drawn anyway, so the
# row loses exactly its own indent off the right edge. unpad turns them back
# into what everything else here already is, a column count the caller pays for
# in padding.
#
# It sets two globals rather than printing, because `$(unpad …)` is a subshell
# and the count would never come back out of one.
LEAD=0
UNPADDED=""
unpad() { # unpad <value> → sets UNPADDED (blanks stripped) and LEAD (how many)
  UNPADDED="${1#"${1%%[! ]*}"}"
  LEAD=$(( ${#1} - ${#UNPADDED} ))
}

# ── row rhythm ────────────────────────────────────────────────────────────────
# Height is the other half of the hierarchy, and it costs nothing to read: a
# header that stands 8 points taller than its rows separates two providers
# without a rule between them, and a footnote that sits 4 shorter stops
# pretending to be data. background.drawing stays off — this is layout, not a
# box.
H_HEADER=32
H_ROW=25
H_META=20

# ── row builders ──────────────────────────────────────────────────────────────
# All four append to ARGS and bump $i; nothing here talks to sketchybar, so the
# whole popup is still one message (see the click path). Each takes the common
# chrome first and the caller's overrides last, because --set applies left to
# right and the last write of a property wins.
pop_add() { # pop_add <property=value…>
  ARGS+=(--add item "${ITEM_NAME}.popup.$i" "popup.${ITEM_NAME}"
    --set "${ITEM_NAME}.popup.$i"
      icon="" icon.padding_left=0 icon.padding_right=0
      label="" label.padding_left=0 label.padding_right=14
      background.drawing=off background.height="$H_ROW"
      click_script="$SB --set ${ITEM_NAME} popup.drawing=off"
    "$@")
  i=$((i + 1))
}

header() { # header <icon> <font> <color> <name> [name-color] — which client the
  # block is about. The name defaults to TEXT and only moves when the whole
  # block is greyed: a dim mark under a bright name looks like a rendering bug
  # rather than like a feed that stopped reporting.
  pop_add icon="$1" icon.font="$2" icon.color="$3" \
    icon.padding_left=10 icon.padding_right=8 \
    label="$4" label.color="${5:-$TEXT}" label.font="${BAR_FONT}:Bold:${FS_LABEL}" \
    background.height="$H_HEADER"
}

row() { # row <descriptor> <value> <color> [weight] — dim left column, coloured
  # value. Weight is the third axis after size and hue: Bold is for a number
  # that is a fraction of something you can run out of, Regular for one that
  # just counts up.
  unpad "$2"
  pop_add icon="$1" icon.color="$OVERLAY1" \
    icon.font="${BAR_FONT}:Regular:${FS_SMALL}" \
    icon.padding_left="$ROW_INDENT" icon.padding_right="$(desc_pad "$1" "$LEAD")" \
    label="$UNPADDED" label.color="$3" label.font="${BAR_FONT}:${4:-Bold}:${FS_SMALL}"
}

row_cont() { # row_cont <value> <color> [weight] — a value row whose descriptor is
  # the one above it. No icon at all: an empty icon still reserves its padding,
  # and the label carries the whole indent instead.
  local indent; unpad "$1"
  indent=$(awk -v t="$TOKEN_INDENT" -v a="$ADVANCE" -v x="$LEAD" 'BEGIN { printf "%.0f", t + x * a }')
  pop_add label="$UNPADDED" label.color="$2" \
    label.font="${BAR_FONT}:${3:-Bold}:${FS_SMALL}" \
    label.padding_left="$indent"
}

meta() { # meta <text> — a footnote. Smallest, dimmest, shortest row there is.
  pop_add label="$1" label.color="$OVERLAY0" \
    label.font="${BAR_FONT}:Italic:${FS_TINY}" \
    label.padding_left="$ROW_INDENT" background.height="$H_META"
}

token_block() { # token_block <d> <w> <m> <all> <color> [weight] — the score,
  # labelled then indented under its own label.
  local blk line first=1
  blk=$(tokens_label "$1" "$2" "$3" "$4")
  [ -n "$blk" ] || return 0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if [ "$first" = 1 ]; then row "tokens" "$line" "$5" "${6:-Regular}"; first=0
    else                      row_cont "$line" "$5" "${6:-Regular}"
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
  COL=$TEAL
else
  COL=$(pct_color "$main_pct")
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
  if [ "$("$SB" --query "$ITEM_NAME" 2>/dev/null | jq -r '.popup.drawing')" = "on" ]; then
    "$SB" --set "$ITEM_NAME" popup.drawing=off
    exit 0
  fi

  "$SB" --remove "/${ITEM_NAME}\.popup\..*/" 2>/dev/null
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
    p_icon="$P_ICON"; p_font="$P_FONT"; p_name="$P_NAME"; p_color="$P_COLOR"

    # A dead feed greys out as a BLOCK — mark, name and all — the same way the
    # pill greys itself. Half a stale block still painted in confident red would
    # be the popup asserting a number it stopped being able to check hours ago.
    p_name_color="$TEXT"
    [ "$f_stale" = 1 ] && { p_color="$OVERLAY1"; p_name_color="$OVERLAY1"; }

    header "$p_icon" "$p_font" "$p_color" "$p_name" "$p_name_color"

    if [ "$f_is_cost" = 1 ]; then
      # Money is off the ladder by construction: there is no ceiling to be 90%
      # of, so a spend can never be GREEN-as-in-safe without lying. TEAL says
      # "a quantity, no verdict" — and a period that hasn't started yet stays
      # grey rather than shouting $0.00 in colour.
      c5="$TEAL"; cw="$TEAL"
      awk -v v="$val5" 'BEGIN { exit !(v + 0 > 0) }' || c5="$OVERLAY1"
      awk -v v="$valw" 'BEGIN { exit !(v + 0 > 0) }' || cw="$OVERLAY1"
      [ "$f_stale" = 1 ] && { c5="$OVERLAY0"; cw="$OVERLAY0"; }
      row "today"   "\$$val5" "$c5"
      row "monthly" "\$$valw" "$cw"
    else
      # `resets …` rides in the same label as the value it belongs to (one item
      # draws one colour), separated by a `·` so the eye still reads it as the
      # quieter half. The gauge is what makes 92% and 38% differ before you've
      # read either number.
      when=""
      if [ "$r5" -gt "$now" ]; then
        if [ $(($r5 - now)) -lt 86400 ]; then when="resets $(date -r "$r5" '+%H:%M')"
        else                                  when="resets $(date -r "$r5" '+%a %H:%M')"; fi
      fi
      c5="$(pct_color "$val5")"; [ "$f_stale" = 1 ] && c5="$OVERLAY0"
      row "session" "$(printf '%3s%%  %s' "$val5" "$(gauge "$val5")")${when:+  ·  $when}" "$c5"

      when_w=""
      if [ "$rw" -gt "$now" ]; then
        if [ $(($rw - now)) -lt 86400 ]; then when_w="resets $(date -r "$rw" '+%H:%M')"
        else                                  when_w="resets $(date -r "$rw" '+%a %H:%M')"; fi
      fi
      cw="$(pct_color "$valw")"; [ "$f_stale" = 1 ] && cw="$OVERLAY0"
      row "weekly" "$(printf '%3s%%  %s' "$valw" "$(gauge "$valw")")${when_w:+  ·  $when_w}" "$cw"
    fi

    # Tokens: the score row. Every number above is a fraction of something you
    # are allowed; this is the raw count of tokens actually moved, which no
    # client shows anywhere and which nothing here throttles or warns on. Only
    # providers whose token feed exists get the row (see statusline-refresh.sh).
    # It is drawn Regular in SUBTEXT1, deliberately quieter than the gauges: a
    # count with no ceiling can't be urgent, and colouring it would make the
    # ladder above it mean less.
    if read_tokens "$CACHE_DIR/tokens-$prov.tsv"; then
      t_col="$SUBTEXT1"; [ "$f_stale" = 1 ] && t_col="$OVERLAY0"
      token_block "$T_D" "$T_W" "$T_M" "$T_ALL" "$t_col"
    fi

    [ "$f_stale" = 1 ] && meta "as of $(ago "$f_age") ago"
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
    # PINK on the ∑ and Bold on the numbers: this block is a summary of the ones
    # above it, so it is set apart by WEIGHT rather than by a fourth hue. The
    # sizes come from sizes.sh like every other row — they were hardcoded 14/13
    # here, which pinned one block of the popup at ui.scale=1 while the rest of
    # it grew.
    header "∑" "${BAR_FONT}:Bold:${FS_LABEL}" "$PINK" "Everything"
    token_block "$g_d" "$g_w" "$g_m" "$g_all" "$TEXT" "Bold"
  fi

  # One message: every row, then reveal. Not `toggle` — the state was already
  # settled above, and toggling off a popup whose rows we just rebuilt is exactly
  # the double-open the flash came from if a stray click arrives mid-build.
  [ ${#ARGS[@]} -gt 0 ] && "$SB" "${ARGS[@]}" 2>/dev/null
  "$SB" --set "$ITEM_NAME" popup.drawing=on
  # Then hand it to sillpop so it also closes on the first click anywhere else —
  # the dismissal sketchybar can't do, since it only hears clicks on its own
  # items. Backgrounded and after the reveal, so opening costs what it did above.
  # SKETCHYBAR_BIN is what sillpop resolves its own client from: unset, it
  # queries the TOP bar, finds no such item on a pill that moved to the
  # bottom one, and exits before it ever arms — leaving a dropdown nothing
  # closes but a second click on the pill.
  SKETCHYBAR_BIN="$SB" /run/current-system/sw/bin/sillpop arm "$ITEM_NAME" 2>/dev/null &
  exit 0
fi

# ── update: main pill icon + label + colour ───────────────────────────────────
"$SB" --set ${ITEM_NAME} drawing=on icon="$ICON" icon.font="$IFONT" icon.color="$COL" \
  label="$MAIN_LABEL" label.color="$COL"

