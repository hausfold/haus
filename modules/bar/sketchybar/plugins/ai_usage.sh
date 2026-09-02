#!/bin/bash
# widget: interval = 15
# widget: popup = true
#
# ai_usage.sh — the reader half of the `aiUsage` pill (opt-in via
# haus.bar.items). Puts rate-limit gauges for AI providers (Claude Code,
# Codex, etc.) or token API costs (Opencode, etc.) in the menu bar.
#
# A framework widget (docs/bar-framework.md): the header above is the whole of
# its wiring, and barlib owns the bar instance, the batching, the state diff,
# the dropdown and every colour. What is left here is the FEEDS — how a
# provider reports, which one the pill speaks for, and what a percentage means
# — which is the pill's actual subject.
#
# Subscription TSV lines:
#     <5h %>\t<7d %>\t<5h resets epoch>\t<7d resets epoch>\t<written epoch>\t<provider>\t<model>\t<provider_id>\t<used epoch>
# Cost TSV lines (e.g. usage-opencode.tsv):
#     <today $>\t<mtd $>\t0\t0\t<written epoch>\topencode\t<model>\t<provider_id>\t<used epoch>
# No column here is ever EMPTY, including the two a subscription feed has no
# real use for: tab is IFS whitespace, so `read` collapses a run of empty middle
# fields into one delimiter and shifts every later column left.
# Token TSV lines (tokens-<provider>.tsv, optional, dropdown only):
#     <day>\t<week>\t<month>\t<all time>\t<written epoch>
# Five columns, and `read_tokens` takes all five or none: the four buckets are
# computed INDEPENDENTLY rather than nested (statusline-refresh.sh), so a week
# that started before the 1st holds tokens the month does not, and a file left
# by an older haus has a different shape that would file the week under the day.
#
# ── written vs used, and why they are two columns ─────────────────────────────
# Column 5 answers "how old are these NUMBERS" and column 9 answers "when did
# you last actually burn quota here". They were one field, and the pill read it
# as both, which is exactly as wrong as it sounds the moment a feed is PULLED
# rather than pushed: the Codex block re-asks OpenAI every two minutes whether
# you have touched Codex or not, so its stamp was always `now` and `latest`
# handed the pill to the one client that had been idle for days. Opencode had
# the mirror-image fault — it stamped its row with the last SESSION time, so a
# feed refreshed 30 seconds ago greyed itself out as stale.
#
# So: staleness (the grey, the `as of N ago` footnote) reads column 5, and the
# `latest` provider selection reads column 9. A row with no column 9 — an older
# haus, or a client whose writer this repo doesn't own — falls back to column 5,
# which for a PUSHED feed is what it always meant.
#
# ── how the dropdown says what it says ────────────────────────────────────────
# Two rules, and the whole look still falls out of them — but both are the
# framework's vocabulary now rather than this file's hexes.
#
# **A hue on a MARK means identity, a hue on a NUMBER means state.** The
# heading wears the client's mark (`--mark`, from ai-provider.sh's shared
# table, which the agents pill draws from too), and the severity ladder
# appears only on values, on the same thresholds the pill paints ITSELF with
# via the `pct_tone` both paths share. Before that split, 92% and 0% were the
# same grey in the dropdown while the pill outside it was red: the one number
# worth opening the popup for was the one it hid.
#
# **Type says rank, and nothing carries importance by position alone.** Which
# is barlib's: `popup_heading` is which client, `popup_row --value` is a
# question on the left and its answer on the right, `popup_note` is a
# footnote. This file no longer owns a font, a height or a pixel of the value
# column — the six row kinds do, once, for every pill on the bar.
#
# A stale provider drops its heading to `dim` and its values to `mute`, so a
# block whose feed died greys out as a whole exactly like the pill does — no
# row is left claiming a number it can no longer stand behind. That two-tier
# grey is the `dim`/`mute` pair, which this pill's own `descr`/`meta` rule is
# one of the two that earned (modules/bar/tones.nix).
#
# ── what the conversion gave up, deliberately ─────────────────────────────────
# Money was SAPPHIRE and is `text`; the ∑ block's mark was PINK and is the
# heading default. Both were one pill's hex, and the ladder does not take a
# rung for a colour one widget wants — the argument is in tones.nix under
# `action`. The brand hues survived because two pills spend them, which is the
# same rule pointing the other way.
set -u
export USER="${USER:-$(id -un)}"
export PATH="/opt/homebrew/bin:/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:$PATH"

# BAR_ITEM is the fallback bar.sh and barlib need on the PUSH path: the
# statusline invokes this file directly (`SENDER=refresh NAME=ai_usage`) from
# outside SketchyBar, where there is no $BAR_NAME to route on. The pill is
# movable via haus.bar.bottom.items, so a bare `sketchybar` would keep talking
# to a top-bar item that is no longer there.
BAR_ITEM=ai_usage
source "$HOME/.config/sketchybar/barlib.sh"
# provider_style() — the shared icon/mark/name table, so the agents pill draws
# the same mark for a client that this pill draws for its usage.
# shellcheck source=./ai-provider.sh
source "$HOME/.config/sketchybar/plugins/ai-provider.sh"

CACHE_DIR="${CLAUDE_STATUSLINE_CACHE:-$HOME/.cache/claude-statusline}"
STALE=300                        # 5 min with no WRITE → mark the feed stale
FEED_TTL=180                     # how often we re-pull the Codex/Opencode feeds

# BAR_AI_USAGE_PROVIDER — which client the pill speaks for, or `latest`.
# shellcheck source=/dev/null
[ -f "$HOME/.config/sketchybar/ai_usage_config.sh" ] && source "$HOME/.config/sketchybar/ai_usage_config.sh"
PREFERRED="${BAR_AI_USAGE_PROVIDER:-latest}"

# ── the ladder ────────────────────────────────────────────────────────────────
# One function, so the pill and the row explaining it can never disagree about
# whether 76% is worth worrying over. It is the same four steps the vitals
# pills climb (`vitals_tone`), on the same thresholds — said in TONE NAMES,
# because a framework widget names a tone and never a hex.
#
# The stderr redirects are the same guard the old `pct_color` carried: a TSV
# field that isn't a number would otherwise print "integer expression expected"
# into sketchybar's log once per row, per open.
pct_tone() { # pct_tone <pct>
  if   [ "${1:-0}" -ge 90 ] 2>/dev/null; then printf '%s' bad
  elif [ "${1:-0}" -ge 75 ] 2>/dev/null; then printf '%s' warn
  elif [ "${1:-0}" -ge 50 ] 2>/dev/null; then printf '%s' watch
  else                                        printf '%s' ok
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
  #
  # Bash, not awk, because this runs twice per provider on the click path and an
  # awk fork costs ~2.4 ms on this machine. Everything the meter needs is
  # integer arithmetic the shell can already do.
  local p="${1:-0}" k i out=""
  [[ "$p" =~ ^[0-9]+$ ]] || p=0
  ((p > 100)) && p=100
  k=$(((p * GAUGE_CELLS + 50) / 100))
  for ((i = 0; i < GAUGE_CELLS; i++)); do
    if ((i < k)); then out+="$GAUGE_FILL"; else out+="$GAUGE_TRACK"; fi
  done
  printf '%s' "$out"
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

resets_at() { # resets_at <epoch> <now> — "resets 14:20" / "resets Thu 09:00"
  # Rides in the same label as the value it belongs to, because one item draws
  # one colour and the reset time is the quieter half of the same fact.
  [ "${1:-0}" -gt "${2:-0}" ] 2>/dev/null || return 0
  if [ $(($1 - $2)) -lt 86400 ]; then
    printf 'resets %s' "$(date -r "$1" '+%H:%M')"
  else
    printf 'resets %s' "$(date -r "$1" '+%a %H:%M')"
  fi
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
  # The LEADING blanks that right-alignment produces are barlib's problem now,
  # not this file's: `popup_row --value` turns them back into padding, since a
  # label is sized trimmed and drawn untrimmed. That used to be `unpad`/`LEAD`
  # here, and it was the same arithmetic the value column already does.
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

T_D=0; T_W=0; T_M=0; T_ALL=0
read_tokens() { # read_tokens <file> — T_D/T_W/T_M/T_ALL, false if there's no row
  T_D=0; T_W=0; T_M=0; T_ALL=0
  [ -s "$1" ] || return 1
  local at=""
  IFS=$'\t' read -r T_D T_W T_M T_ALL at <"$1" || true
  # All five columns or none: a file left by an older haus has a different shape,
  # and reading it anyway would file the week's tokens under the day.
  [ -n "$at" ] || return 1
  T_D=${T_D:-0}; T_W=${T_W:-0}; T_M=${T_M:-0}; T_ALL=${T_ALL:-0}
  return 0
}

# ── the feeds ─────────────────────────────────────────────────────────────────
# Collect provider files: prefer usage-*.tsv over usage.tsv to avoid duplicates.
# Sets FILES, and every caller checks ${#FILES[@]} before expanding it —
# `"${FILES[@]}"` on an empty array is an unbound-variable abort under bash 3.2
# and `set -u`, which is the shell the bar actually runs these with.
FILES=()
usage_files() {
  local f
  FILES=()
  [ -d "$CACHE_DIR" ] || return 0
  for f in "$CACHE_DIR"/usage-*.tsv; do
    [ -s "$f" ] && FILES+=("$f")
  done
  if [ ${#FILES[@]} -eq 0 ] && [ -s "$CACHE_DIR/usage.tsv" ]; then
    FILES+=("$CACHE_DIR/usage.tsv")
  fi
  return 0
}

# One row, parsed and judged. Sets ROW_*; nothing here draws.
ROW_V5=0; ROW_VW=0; ROW_R5=0; ROW_RW=0; ROW_STAMP=0; ROW_USED=0
ROW_PROV=claude; ROW_MODEL=""; ROW_PID=""
ROW_IS_COST=0; ROW_AGE=0; ROW_STALE=0
read_row() { # read_row <now> <file>
  local now=$1
  ROW_V5=0; ROW_VW=0; ROW_R5=0; ROW_RW=0; ROW_STAMP=0
  ROW_PROV=claude; ROW_MODEL=""; ROW_PID=""; ROW_USED=""
  # Column 9 is read even where the dropdown never shows it: without a variable
  # to land in, `read` folds it into prov_id — the field provider_style picks a
  # mark from — and every row draws the wrong client.
  IFS=$'\t' read -r ROW_V5 ROW_VW ROW_R5 ROW_RW ROW_STAMP ROW_PROV ROW_MODEL ROW_PID ROW_USED <"$2" || true
  ROW_V5=${ROW_V5:-0}; ROW_VW=${ROW_VW:-0}; ROW_R5=${ROW_R5:-0}; ROW_RW=${ROW_RW:-0}
  ROW_STAMP=${ROW_STAMP:-0}; ROW_PROV=${ROW_PROV:-claude}
  # No column 9 (or a non-numeric one) → the row predates the split, where the
  # written stamp WAS the used stamp for every pushed feed. Validated twice, and
  # the second one is not redundant: the fallback is ROW_STAMP, which is only
  # defaulted and never checked, so a garbled row would otherwise reach `-gt`
  # and print "integer expression expected" into the bar's log every tick.
  case "${ROW_USED:-}" in '' | *[!0-9]*) ROW_USED=$ROW_STAMP ;; esac
  case "${ROW_USED:-}" in '' | *[!0-9]*) ROW_USED=0 ;; esac

  ROW_IS_COST=0
  if [ "$ROW_PROV" = "opencode" ] || [[ "$ROW_V5" =~ \. ]]; then
    ROW_IS_COST=1
  else
    [ "$ROW_R5" -gt 0 ] && [ "$now" -ge "$ROW_R5" ] && ROW_V5=0
    [ "$ROW_RW" -gt 0 ] && [ "$now" -ge "$ROW_RW" ] && ROW_VW=0
  fi
  ROW_AGE=$((now - ROW_STAMP))
  ROW_STALE=0
  [ "$ROW_STAMP" -gt 0 ] && [ "$ROW_AGE" -gt "$STALE" ] && ROW_STALE=1
  return 0
}

# ── keep the PULLED feeds alive with no Claude session anywhere ───────────────
# Claude's row is pushed here for free by its statusline on every render. Codex
# (an account API call) and Opencode (a sqlite read) have no such client-side
# writer — the refresher pulls them — and the refresher only ever ran because a
# Claude statusline kicked it. So on a machine whose default agent is Codex or
# Opencode the pill used to grey out and stay grey. Kick it here instead, on its
# own TTL: --usage-only skips the panel and the `gh` traffic, and the refresher's
# own mkdir-lock means a concurrent full pass just makes this one exit.
#
# ⚠️ `env -u SENDER …` on the detach, even though the child is another program:
# the refresher invokes THIS FILE back when a row moves, and a $SENDER inherited
# across that round trip is the runtime re-entering a handler it already left.
# It is the rule in barlib.sh's header, and the cost of honouring it is nothing.
kick_feeds() { # kick_feeds <now>
  local kick="$CACHE_DIR/.usage-kick" kick_at
  command -v claude-statusline-refresh >/dev/null 2>&1 || return 0
  kick_at=$(stat -f %m "$kick" 2>/dev/null || echo 0)
  case "$kick_at" in '' | *[!0-9]*) kick_at=0 ;; esac
  [ $(($1 - kick_at)) -ge "$FEED_TTL" ] || return 0
  mkdir -p "$CACHE_DIR" && touch "$kick"
  (env -u SENDER -u BUTTON -u MODIFIER claude-statusline-refresh --usage-only >/dev/null 2>&1 &)
  return 0
}

# ── the tick ──────────────────────────────────────────────────────────────────
# `latest` orders on USED (column 9), not on written — see the header. The
# chosen row's WRITTEN stamp is carried separately, because that is still what
# greys the pill.
fetch() {
  local now f best_used=-1
  local main_stamp=0 main_v5=0 main_vw=0 main_cost=0
  local main_prov=claude main_model="" main_pid=""
  now=$(date +%s)
  kick_feeds "$now"
  usage_files

  # No feed at all — hide, rather than leave the last number anyone reported
  # sitting in the bar forever. The pill ships `drawing=off updates=on`, so a
  # hidden one keeps ticking and reveals itself the moment a row lands; that
  # pairing is what `pill --hide` writes, and it is why this widget needs no
  # kick at bar start any more.
  if [ ${#FILES[@]} -eq 0 ]; then
    emit hidden=1
    return 0
  fi

  for f in "${FILES[@]}"; do
    read_row "$now" "$f"
    if [ "$PREFERRED" != "latest" ] && [ "$ROW_PROV" = "$PREFERRED" ]; then
      main_v5=$ROW_V5; main_vw=$ROW_VW; main_stamp=$ROW_STAMP
      main_prov=$ROW_PROV; main_model=$ROW_MODEL; main_pid=$ROW_PID
      main_cost=$ROW_IS_COST
      break
    elif [ "$ROW_USED" -gt "$best_used" ]; then
      best_used=$ROW_USED
      main_v5=$ROW_V5; main_vw=$ROW_VW; main_stamp=$ROW_STAMP
      main_prov=$ROW_PROV; main_model=$ROW_MODEL; main_pid=$ROW_PID
      main_cost=$ROW_IS_COST
    fi
  done

  local label tone pct=0
  if [ "$main_cost" = 1 ]; then
    # Money is off the ladder by construction: there is no ceiling to be 90% of,
    # so a spend can never be ok-as-in-safe without lying. `text` is the rung
    # for a live readout carrying no alarm, which is exactly what a spend is.
    label="\$$main_v5"
    tone=text
  else
    pct=$main_v5
    if [ "${main_vw:-0}" -gt "$pct" ] 2>/dev/null; then pct=$main_vw; fi
    label="${pct}%"
    tone=$(pct_tone "$pct")
  fi
  # A feed nobody has written to in five minutes: the pill goes quiet rather
  # than keeping a confident colour on a number it can no longer check.
  if [ "$main_stamp" -gt 0 ] && [ $((now - main_stamp)) -gt "$STALE" ]; then
    tone=dim
  fi

  provider_style "$main_prov" "${main_pid:-$main_model}" "$FS_LABEL"
  emit hidden=0 label="$label" tone="$tone" icon="$P_ICON" ifont="$P_FONT"
}

# The mark and the number wear the SAME tone here, unlike the vitals pills:
# this pill's glyph is not its identity, it is which client the number is
# about, and a Claude mark beside a red 94% has to be as urgent as the number
# — they are one sentence. The client is still identified by the glyph itself.
#
# icon.font is an sb_set rather than a component flag because the FACE is
# per-provider and chosen at runtime (`:claude:` lives in sketchybar-app-font,
# ✦ and π in the bar's own), which is exactly the odd raw property the escape
# is for.
render() {
  if [ "$hidden" = 1 ]; then
    pill --hide
    return 0
  fi
  pill --icon "$icon" --label "$label" --tone "$tone" --label-tone "$tone"
  sb_set icon.font="$ifont"
}

# ── the dropdown ──────────────────────────────────────────────────────────────
# Read again here rather than from the tick's state: popup_rows runs on a
# CLICK, where fetch never ran and the framework's emitted variables do not
# exist. One pass over the feeds serves every row, so no two are describing
# different moments.

# A stale block loses its mark, and that is the one place the two colour axes
# meet: `--mark` and `--tone` are last-wins in barlib, so naming the tone
# second is how a widget says "this is Claude, and its feed is dead". Grey is
# what a dead feed looks like everywhere in this bar, and a heading that kept
# its brand hue while its numbers greyed would be half a block still asserting.
provider_heading() { # provider_heading <stale>
  if [ "$1" = 1 ]; then
    # Both halves, not just the mark: a dim glyph under a full-brightness name
    # reads as a rendering bug rather than as a feed that stopped reporting.
    popup_heading --icon "$P_ICON" --icon-font "$P_FONT" --label "$P_NAME" \
      --tone dim --label-tone dim
  else
    popup_heading --icon "$P_ICON" --icon-font "$P_FONT" --label "$P_NAME" --mark "$P_MARK"
  fi
}

# The score, labelled and then indented under its own label. A continuation
# row is `--label ""`: the name column is left blank and the value still lands
# on it, which is what puts the second line under the first instead of beside
# it.
token_block() { # token_block <d> <w> <m> <all> <tone>
  local blk line first=1
  blk=$(tokens_label "$1" "$2" "$3" "$4")
  [ -n "$blk" ] || return 0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if [ "$first" = 1 ]; then
      popup_row --label "tokens" --value "$line" --tone "$5"
      first=0
    else
      popup_row --label "" --value "$line" --tone "$5"
    fi
  done <<<"$blk"
  return 0
}

popup_rows() {
  local now f when c5 cw t_tone
  local g_d=0 g_w=0 g_m=0 g_all=0 g_n=0 tf
  now=$(date +%s)
  usage_files

  if [ ${#FILES[@]} -eq 0 ]; then
    popup_heading --label "AI usage"
    popup_note --label "no provider is reporting"
    return 0
  fi

  for f in "${FILES[@]}"; do
    read_row "$now" "$f"
    # FS_LABEL, not FS_SMALL: a heading's name is drawn one step up from its
    # rows, and the size passed here is what a NERD-FONT mark (Opencode's 󰏫,
    # Gemini's ✦) is drawn at. Ask for the row size and those clients get a
    # glyph smaller than their own name, while :claude:/:openai: — sized from
    # FS_APP_ICON — look right, so the mismatch shows on some providers only.
    provider_style "$ROW_PROV" "${ROW_PID:-$ROW_MODEL}" "$FS_LABEL"
    provider_heading "$ROW_STALE"

    if [ "$ROW_IS_COST" = 1 ]; then
      # A period that hasn't started yet stays dim rather than shouting $0.00
      # in the foreground colour.
      c5=text; cw=text
      [[ "$ROW_V5" =~ ^[0.]*$ ]] && c5=dim
      [[ "$ROW_VW" =~ ^[0.]*$ ]] && cw=dim
      if [ "$ROW_STALE" = 1 ]; then c5=mute; cw=mute; fi
      popup_row --label "today" --value "\$$ROW_V5" --tone "$c5"
      popup_row --label "monthly" --value "\$$ROW_VW" --tone "$cw"
    else
      # `%3s%%` right-aligns the number so every gauge starts on one column;
      # the leading blanks that produces are turned back into padding by
      # `popup_row --value`, because a label is sized trimmed and drawn
      # untrimmed. The gauge is what makes 92% and 38% differ before you have
      # read either number.
      when=$(resets_at "$ROW_R5" "$now")
      c5=$(pct_tone "$ROW_V5"); [ "$ROW_STALE" = 1 ] && c5=mute
      popup_row --label "session" --tone "$c5" \
        --value "$(printf '%3s%%  %s' "$ROW_V5" "$(gauge "$ROW_V5")")${when:+  ·  $when}"

      when=$(resets_at "$ROW_RW" "$now")
      cw=$(pct_tone "$ROW_VW"); [ "$ROW_STALE" = 1 ] && cw=mute
      popup_row --label "weekly" --tone "$cw" \
        --value "$(printf '%3s%%  %s' "$ROW_VW" "$(gauge "$ROW_VW")")${when:+  ·  $when}"
    fi

    # Tokens: the score row. Every number above is a fraction of something you
    # are allowed; this is the raw count of tokens actually moved, which no
    # client shows anywhere and which nothing here throttles or warns on. Only
    # providers whose token feed exists get the row (see statusline-refresh.sh).
    # `dim` deliberately: a count with no ceiling can't be urgent, and putting
    # it on the ladder would make the gauges above it mean less.
    if read_tokens "$CACHE_DIR/tokens-$ROW_PROV.tsv"; then
      t_tone=dim; [ "$ROW_STALE" = 1 ] && t_tone=mute
      token_block "$T_D" "$T_W" "$T_M" "$T_ALL" "$t_tone"
    fi

    [ "$ROW_STALE" = 1 ] && popup_note --label "as of $(ago "$ROW_AGE") ago"
  done

  # ── grand total ─────────────────────────────────────────────────────────────
  # Every token feed on the machine added up, because the interesting number when
  # you drive three clients is what YOU spent, not what any one of them did. Only
  # drawn when more than one provider reports: with a single feed this row would
  # be the row above it, restated.
  #
  # No mark: the sum is not a client, and the ladder has no rung for "this block
  # is a summary" — it is set apart by being last and by its values being `text`
  # where every provider's are `dim`.
  for tf in "$CACHE_DIR"/tokens-*.tsv; do
    read_tokens "$tf" || continue
    g_d=$((g_d + T_D)); g_w=$((g_w + T_W))
    g_m=$((g_m + T_M)); g_all=$((g_all + T_ALL))
    g_n=$((g_n + 1))
  done
  if [ "$g_n" -gt 1 ] && [ "$g_all" -gt 0 ]; then
    popup_heading --icon "∑" --label "Everything"
    token_block "$g_d" "$g_w" "$g_m" "$g_all" text
  fi
  return 0
}

on_click() { popup_toggle; }

barlib_main "$@"
