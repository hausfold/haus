#!/bin/bash
# calendar.sh — the `calendar` pill: the one meeting you have to be at next, how
# long you have, and one gesture to join it.
#
#   left click    the timeline dropdown (done · now · next)
#   right click   join — opens the conferencing link of the event the pill shows
#   hover         sweep the full title past, and re-read the calendar on the spot
#
# ── what the pill says ────────────────────────────────────────────────────────
# The countdown LEADS, and that is load-bearing: SketchyBar clips a label to
# label.max_chars from the END, so whatever is last is what a long meeting name
# eats. "<title> in 12m" would put the one number the pill exists for in exactly
# that spot. Countdown first pins it; the title is the part that can run long.
#
# Below `haus.bar.calendar.preciseUnder` hours the countdown carries minutes
# ("in 3h20m"); above it they are noise on a number you're reading as "not yet"
# ("in 14h", and "in 2d" once `horizon` reaches that far — at the default 24 the
# day form is out of range by construction). While an event is running the pill
# says "now · <title>" rather than going blank, which is what it used to do — a
# pill with nothing to say during the only half hour it matters is a pill you
# learn to ignore.
#
# For `haus.bar.calendar.imminent` minutes either side of the start the pill
# FILLS: the accent moves from the glyph to the whole background and the type
# goes dark. That is the one state worth catching from the corner of an eye, and
# it is a shape change, not a colour change, so it survives being glanced at.
#
# ── the sweep ─────────────────────────────────────────────────────────────────
# HOVER ONLY. The title used to also sweep for eight seconds whenever the next
# event changed, on the theory that that's when you'd want to read it; in
# practice the bar just moved on its own several times a day, which is the one
# thing a status bar must never do. Nothing here starts a marquee unless the
# pointer is on the pill. That also removed the whole hover-flag/settle timer
# apparatus this file used to carry, and with it the stranded-flag failure mode
# the bar's init had to clean up after.
#
# How wide the settled form is comes from `haus.bar.calendar.width`, applied as
# the item's label.max_chars at add time (modules/bar/default.nix) — SketchyBar
# owns the clip, so nothing here has to know the number.
set -u
export USER="${USER:-$(id -un)}"
export PATH="/opt/homebrew/bin:/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:$PATH"
source "$HOME/.config/sketchybar/colors.sh"
# $SB — which bar this pill lives on (haus.bar.bottom.items can move it to the
# bottom bar, a separate SketchyBar instance addressed by its own binary).
BAR_ITEM=calendar
source "$HOME/.config/sketchybar/bar.sh"
source "$HOME/.config/sketchybar/sizes.sh"
# GENERATED from haus.bar.calendar.* — absent on a rice that predates it, hence
# the defaults below rather than a hard `source`.
[ -f "$HOME/.config/sketchybar/calendar_config.sh" ] &&
  source "$HOME/.config/sketchybar/calendar_config.sh"

ITEM_NAME="${NAME:-calendar}"
# This file, by the path SketchyBar knows it as — a dropdown row's click_script
# is a string SketchyBar runs later, so it can't inherit anything from here.
SELF="${BASH_SOURCE[0]:-$HOME/.config/sketchybar/plugins/calendar.sh}"
HORIZON=${BAR_CALENDAR_HORIZON:-24}       # hours ahead the pill counts down
PRECISE_UNDER=${BAR_CALENDAR_PRECISE_UNDER:-12}  # hours below which minutes show
IMMINENT=${BAR_CALENDAR_IMMINENT:-5}      # minutes either side of the start
PAST=${BAR_CALENDAR_PAST:-24}             # hours of "done" the dropdown keeps
UPCOMING=${BAR_CALENDAR_UPCOMING:-5}      # how many "next" rows the dropdown draws
ME_EXTRA=${BAR_CALENDAR_ME:-}             # comma-joined: addresses that are me
JOIN_EXTRA=${BAR_CALENDAR_JOIN_HOSTS:-}   # comma-joined: extra conferencing hosts

# Homebrew's path FIRST, not `command -v`'s answer: a CLI's Calendar grant in
# TCC is keyed by PATH, so the copy the user already approved is the copy that
# can read anything (see also the note about brew upgrades orphaning that grant).
ICALBUDDY=/opt/homebrew/bin/icalBuddy
[ -x "$ICALBUDDY" ] || ICALBUDDY="$(command -v icalBuddy 2>/dev/null || echo "$ICALBUDDY")"

# The field separator between this file's two halves (the awk parser and the
# shell that draws from it). ASCII unit separator, and deliberately NOT a tab:
# tab is an IFS *whitespace* character, so bash's `read` collapses a run of them
# into one delimiter — an event with no attendees would hand its join URL to the
# `who` variable and draw "with https://acme.zoom.us/j/1234". A control byte is
# also the one thing a meeting name cannot contain.
US=$'\037'
STATE_DIR="$HOME/.local/state/haus/calendar"
JOIN_CACHE="$STATE_DIR/join-url"   # the shown event's link, so right-click is instant
ME_CACHE="$STATE_DIR/me"           # which addresses are this machine's own
mkdir -p "$STATE_DIR" 2>/dev/null

# ── who is "me" ───────────────────────────────────────────────────────────────
# An attendee list that includes you is a list that tells you nothing: every
# meeting is "with julien@…". icalBuddy has no is-current-user flag, but a
# CalDAV account's calendar is NAMED for the address it syncs, so the set of
# calendar names that look like email addresses is a good enough answer with no
# configuration at all — which is the point, since the one machine that could
# state it (yours) is the one that shouldn't have to.
#
# Cached for six hours: an account is added about as often as a machine is, and
# this is a second icalBuddy spawn on a path that already pays for one.
me_addresses() {
  local age=0 stamp
  stamp=$(stat -f %m "$ME_CACHE" 2>/dev/null || echo 0)
  case "$stamp" in '' | *[!0-9]*) stamp=0 ;; esac
  age=$(($(date +%s) - stamp))
  # `-f`, NOT `-s`: an EMPTY answer is a real answer. A stock iCloud machine's
  # calendars are called Home and Work, so the sed below matches nothing and the
  # file lands at zero bytes — and a `-s` test reads that as "never cached" and
  # re-spawns icalBuddy on every single tick, forever, doubling the cost of the
  # pill on exactly the machines that get nothing back for it.
  if [ ! -f "$ME_CACHE" ] || [ "$age" -ge 21600 ]; then
    "$ICALBUDDY" -nrd calendars 2>/dev/null |
      sed -n 's/^• \(.*@.*\..*\)$/\1/p' >"$ME_CACHE.tmp" 2>/dev/null
    mv -f "$ME_CACHE.tmp" "$ME_CACHE" 2>/dev/null || : >"$ME_CACHE"
  fi
  cat "$ME_CACHE" 2>/dev/null
}

# ── join ──────────────────────────────────────────────────────────────────────
# Right-clicking the pill, or clicking a dropdown row, opens the conferencing
# link. Nothing happens when there isn't one: a pill that opened Calendar.app
# instead would be a different gesture wearing this one's clothes.
open_join() {
  local url="${1:-}"
  [ -n "$url" ] || return 0
  case "$url" in http://* | https://* | msteams:* | zoommtg:* | zoomus:*) ;; *) return 0 ;; esac
  /usr/bin/open "$url" >/dev/null 2>&1 &
}

case "${1:-}" in
join)                       # right-click, and the pill's own gesture: the shown event
  open_join "$(cat "$JOIN_CACHE" 2>/dev/null)"
  exit 0
  ;;
open)                       # a dropdown row: the link that row was built with
  open_join "${2:-}"
  exit 0
  ;;
esac

# Hover is answered without touching icalBuddy for the marquee half — the
# pointer crossing the bar fires this script and re-reading the calendar for a
# mouse twitch would spawn a binary per pixel. Entering DOES fall through to a
# repaint though: looking at the pill is the moment its number has to be right,
# and it is also the cheapest possible cache-invalidation signal there is.
# mouse.exited.global is the belt-and-braces twin — the per-item exit is missed
# when the pointer is flicked straight off the bar, and a stranded marquee is
# the exact failure this pill's whole sweep design exists to prevent.
case "${SENDER:-}" in
mouse.entered)
  "$SB" --set "$ITEM_NAME" scroll_texts=on
  ;;
mouse.exited | mouse.exited.global)
  "$SB" --set "$ITEM_NAME" scroll_texts=off
  exit 0
  ;;
esac

WANT_POPUP=0
if [ "${1:-}" = "click" ]; then
  case "${BUTTON:-left}" in
  right)
    open_join "$(cat "$JOIN_CACHE" 2>/dev/null)"
    exit 0
    ;;
  *)
    # Closing is just hiding. Rebuilding a dozen rows first would re-lay-out a
    # popup the user can see, which is the shrink/regrow flash the AI-usage pill
    # documents; the rows are rebuilt on the way back IN, where nothing shows.
    if [ "$("$SB" --query "$ITEM_NAME" 2>/dev/null | jq -r '.popup.drawing')" = "on" ]; then
      "$SB" --set "$ITEM_NAME" popup.drawing=off
      exit 0
    fi
    WANT_POPUP=1
    ;;
  esac
fi

# ── reading the calendar ──────────────────────────────────────────────────────
# ONE icalBuddy call serves both the pill and the dropdown (~50 ms, measured),
# covering `past` hours back to a week ahead — the pill applies its own horizon
# to what comes out. Every field is LABELLED (`-npn` deliberately not passed):
# icalBuddy omits a property an event doesn't have rather than emitting an empty
# one, so a positional parse silently files the notes under the location the
# first time somebody's meeting has no attendees. `-nnr` folds a note's newlines
# so an event is one line; the parser still glues continuation lines back on,
# because `-nnr` covers notes only and a two-line LOCATION would otherwise split
# an event in half.
#
# The window FOLLOWS the options rather than being a fixed week: `past` back,
# and forward the larger of a week and whatever `horizon` asks for. A hardcoded
# +7d silently caps the option — set `horizon = 720` for a sparse calendar and
# the pill says "No events" about a month it can see nothing of, with nothing
# anywhere to explain why. A week is the FLOOR, not the reach, because the
# dropdown's Next band is documented as being allowed to outrun the horizon.
FROM=$(date -v-"${PAST}"H +%F 2>/dev/null || date +%F)
AHEAD=$(((HORIZON + 23) / 24))
[ "$AHEAD" -lt 7 ] && AHEAD=7
TO=$(date -v+"${AHEAD}"d +%F 2>/dev/null || date +%F)
RAW=$("$ICALBUDDY" -nc -nrd -ea \
  -nnr " ⏎ " -b "@@E@@" -ps "|@@F@@|" \
  -df "%Y-%m-%d" -tf "%H:%M" \
  -iep "datetime,title,attendees,location,url,notes" \
  eventsFrom:"$FROM" to:"$TO" 2>/dev/null)

NOW_YMD=$(date +%Y-%m-%d)
NOW_HM=$(date +%H:%M)
TODAY=$NOW_YMD
TOMORROW=$(date -v+1d +%F 2>/dev/null || echo "")
YESTERDAY=$(date -v-1d +%F 2>/dev/null || echo "")

# The parser. Emits one US-separated row per event, oldest first:
#
#   startMin  endMin  sdate  stime  etime  title  who  join
#
# startMin/endMin are NAIVE local minutes (a Julian day number × 1440 plus the
# clock), which is all the ordering, the section split and the durations need
# and costs no `date` fork per event. The one number that must survive a DST
# boundary — the countdown the pill prints — is computed from a real epoch
# below, for the one event it's about.
#
# Both lists reach awk COMMA-joined, never newline-joined: a `-v` assignment is
# parsed by awk's own lexer, which will not take a literal newline inside the
# value and dies with "newline in string" — silently, from the pill's point of
# view, since stderr goes nowhere.
EVENTS=$(printf '%s\n' "$RAW" | awk \
  -v me="$(printf '%s\n%s\n' "$(me_addresses)" "$ME_EXTRA" | tr '\n' ',')" \
  -v extrahosts="$(printf '%s\n' "$JOIN_EXTRA" | tr '\n' ',')" \
  -v nowymd="$NOW_YMD" -v nowhm="$NOW_HM" '
function jdn(y, m, d,   a, yy, mm) {
  a = int((14 - m) / 12); yy = y + 4800 - a; mm = m + 12 * a - 3
  return d + int((153 * mm + 2) / 5) + 365 * yy + int(yy / 4) \
         - int(yy / 100) + int(yy / 400) - 32045
}
function minutes(ymd, hm) {
  return jdn(substr(ymd, 1, 4) + 0, substr(ymd, 6, 2) + 0, substr(ymd, 9, 2) + 0) * 1440 \
         + substr(hm, 1, 2) * 60 + substr(hm, 4, 2)
}
function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
function titlecase(s,   n, i, w, out) {
  n = split(s, w, " "); out = ""
  for (i = 1; i <= n; i++) {
    if (w[i] == "") continue
    out = out (out == "" ? "" : " ") toupper(substr(w[i], 1, 1)) substr(w[i], 2)
  }
  return out
}
# An address is a machine detail; a name is what you would say out loud. So an
# email becomes its local part, title-cased with the dots opened out
# (chalo@monogram.io -> Chalo, first.last@x -> First Last), and anything that
# already IS a display name is left exactly as the organiser typed it.
function person(s,   local) {
  s = trim(s)
  if (s !~ /@/) return s
  local = s; sub(/@.*/, "", local); gsub(/[._+-]+/, " ", local)
  return titlecase(local)
}
function isme(s,   i) {
  s = tolower(trim(s))
  for (i = 1; i <= nme; i++) if (s == melist[i]) return 1
  return 0
}
function hostof(u,   h) {
  sub(/^[a-zA-Z]+:\/\//, "", u)
  h = u; sub(/[\/?#].*$/, "", h); sub(/^.*@/, "", h); sub(/:[0-9]+$/, "", h)
  return tolower(h)
}
# A bare registrable name also covers its subdomains — `zoom.us` catches
# us02web.zoom.us. The dots are escaped on the way into the regex: unescaped,
# `zoom.us` is a pattern that any of `zoomxus` matches, so a lookalike host in a
# spam invite would be offered as a one-click join.
function reQuote(s) { gsub(/[][(){}.*+?^$|\\\\]/, "\\\\&", s); return s }
function isjoinhost(h,   i) {
  for (i = 1; i <= nhost; i++)
    if (h == hosts[i] || h ~ ("\\." reQuote(hosts[i]) "$")) return 1
  return 0
}
# The first URL in the text whose HOST is a conferencing service. Host-matched,
# not substring-matched, because every Google Meet invite also carries
# https://tel.meet/… (the dial-in) and https://support.google.com/… (the
# footer), and a naive search for "meet" opens the phone-number page.
function findjoin(text,   n, i, tok, h) {
  n = split(text, tok, /[ \t<>",]+/)
  for (i = 1; i <= n; i++) {
    if (tok[i] !~ /^https?:\/\//) continue
    gsub(/[).;:]+$/, "", tok[i])
    h = hostof(tok[i])
    if (isjoinhost(h)) return tok[i]
  }
  return ""
}
BEGIN {
  FS = "@@F@@"
  US = sprintf("%c", 31)   # the same unit separator the shell half reads back
  nme = 0
  n = split(me, tmp, ",")
  for (i = 1; i <= n; i++) if (trim(tmp[i]) != "") melist[++nme] = tolower(trim(tmp[i]))
  # The built-in roster. `zoom.us` also covers us02web.zoom.us and friends via
  # the suffix rule in isjoinhost, which is why these are bare registrable names
  # rather than the hostnames anybody actually clicks.
  n = split("meet.google.com zoom.us zoom.com teams.microsoft.com teams.live.com " \
            "webex.com meet.jit.si whereby.com chime.aws bluejeans.com " \
            "gotomeeting.com gotomeet.me meet.goto.com around.co discord.gg", h, " ")
  for (i = 1; i <= n; i++) hosts[++nhost] = h[i]
  n = split(extrahosts, h, ",")
  for (i = 1; i <= n; i++) if (trim(h[i]) != "") hosts[++nhost] = tolower(trim(h[i]))
  nowmin = minutes(nowymd, nowhm)
  rec = ""
}
# One record per @@E@@; anything else continues the one before it.
{
  if (substr($0, 1, 5) == "@@E@@") { if (rec != "") emit(rec); rec = substr($0, 6) }
  else if (rec != "")              { rec = rec " " $0 }
}
END { if (rec != "") emit(rec); }
function emit(line,   n, f, i, v, dt, title, att, loc, url, notes, rest, r,
                     sdate, stime, edate, etime, who, nwho, seen, p, join, smin, emin) {
  n = split(line, f, FS)
  dt = ""; title = ""; att = ""; loc = ""; url = ""; notes = ""
  for (i = 1; i <= n; i++) {
    v = f[i]
    if      (v ~ /^attendees: /) att   = substr(v, 12)
    else if (v ~ /^location: /)  loc   = substr(v, 11)
    else if (v ~ /^url: /)       url   = substr(v, 6)
    else if (v ~ /^notes: /)     notes = substr(v, 8)
    # Unnamed: the datetime is the one with a datetime SHAPE, the other is the
    # title. Shape-tested rather than position-tested because icalBuddy honours
    # -po for these two and a rice that reorders them would otherwise file every
    # meeting name as a date and print an empty bar.
    else if (v ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] at [0-9][0-9]:[0-9][0-9]/) dt = v
    else if (title == "") title = trim(v)
  }
  # An event with no datetime has nothing to place on a timeline. An event with
  # no NAME still has a slot in your day, so it gets drawn rather than silently
  # vanishing from both the pill and the dropdown.
  if (dt == "") return
  if (title == "") title = "(no title)"
  sdate = substr(dt, 1, 10); stime = substr(dt, 15, 5)
  edate = sdate; etime = stime
  rest = substr(dt, 20)
  if (substr(rest, 1, 3) == " - ") {
    r = substr(rest, 4)
    # " - 08:55" (same day) or " - 2026-08-11 at 01:00" (over midnight).
    if (substr(r, 11, 4) == " at ") { edate = substr(r, 1, 10); etime = substr(r, 15, 5) }
    else                            { etime = substr(r, 1, 5) }
  }
  smin = minutes(sdate, stime); emin = minutes(edate, etime)
  if (emin < smin) emin = smin

  who = ""; nwho = 0
  if (att != "") {
    n = split(att, a, ", ")
    for (i = 1; i <= n; i++) {
      if (trim(a[i]) == "" || isme(a[i])) continue
      p = person(a[i])
      if (p == "" || (p in seen)) continue
      seen[p] = 1
      who = who (who == "" ? "" : ", ") p
      nwho++
    }
  }
  # An app SCHEME counts as a join too. The url property of a Teams invite is
  # `msteams:/l/meetup-join/…`, which has no `//` and therefore no host for
  # isjoinhost to judge. Only the url property is read this way: a bare scheme
  # buried in the notes of an invite is not a link anybody clicked on purpose.
  # (No apostrophes anywhere in this awk program — the whole thing is one
  # single-quoted shell string, and one would end it mid-parser.)
  join = ""
  if (url != "") {
    if (tolower(url) ~ /^(msteams|zoommtg|zoomus):/) join = url
    else if (isjoinhost(hostof(url)))               join = url
  }
  if (join == "") join = findjoin(loc)
  if (join == "") join = findjoin(notes)

  printf "%d%s%d%s%s%s%s%s%s%s%s%s%s%s%s\n", smin, US, emin, US, sdate, US, stime, US, etime,
         US, title, US, who, US, join
}
')

# ── which event the pill is about ─────────────────────────────────────────────
# The one running right now, else the next one to start. An in-progress meeting
# outranks the one after it: during the half hour you are actually in it, "in 4h
# · Standup" is the pill telling you about the wrong thing.
NOW_MIN=$(awk -v d="$NOW_YMD" -v t="$NOW_HM" '
BEGIN {
  y = substr(d,1,4)+0; m = substr(d,6,2)+0; dd = substr(d,9,2)+0
  a = int((14-m)/12); yy = y+4800-a; mm = m+12*a-3
  j = dd + int((153*mm+2)/5) + 365*yy + int(yy/4) - int(yy/100) + int(yy/400) - 32045
  print j*1440 + substr(t,1,2)*60 + substr(t,4,2)
}')

FOCUS=$(printf '%s\n' "$EVENTS" | awk -F"$US" -v now="$NOW_MIN" -v us="$US" '
  NF >= 6 && $1 <= now && $2 > now { print "now" us $0; found = 1; exit }
  END { if (!found) exit 1 }
' 2>/dev/null)
if [ -z "$FOCUS" ]; then
  FOCUS=$(printf '%s\n' "$EVENTS" | awk -F"$US" -v now="$NOW_MIN" -v us="$US" '
    NF >= 6 && $1 > now { print "next" us $0; exit }
  ')
fi

FILL=0
LABEL="No events"
JOIN_URL=""
if [ -n "$FOCUS" ]; then
  IFS="$US" read -r F_STATE F_SMIN _F_EMIN F_SDATE F_STIME _F_ETIME F_TITLE _F_WHO F_JOIN \
    <<<"$FOCUS"
  # The one place a real epoch is worth two forks: everything else here is naive
  # local minutes, which is exact for ordering and off by an hour for a duration
  # that straddles a daylight-saving change. This number is a countdown someone
  # walks into a meeting on.
  START_EPOCH=$(date -j -f "%Y-%m-%d %H:%M" "$F_SDATE $F_STIME" +%s 2>/dev/null || echo "")
  NOW_EPOCH=$(date +%s)
  DIFF=$((${START_EPOCH:-$NOW_EPOCH} - NOW_EPOCH))

  if [ "$F_STATE" = "now" ]; then
    LABEL="now · $F_TITLE"
    JOIN_URL="$F_JOIN"
  elif [ "$DIFF" -le $((HORIZON * 3600)) ]; then
    MINS=$(((DIFF + 59) / 60))   # round UP: "in 0m" for a meeting that hasn't started
    [ "$MINS" -lt 0 ] && MINS=0
    HOURS=$((MINS / 60))
    if [ "$MINS" -lt 60 ]; then
      TIME_STR="${MINS}m"
    elif [ "$HOURS" -lt "$PRECISE_UNDER" ] && [ $((MINS % 60)) -gt 0 ]; then
      TIME_STR="${HOURS}h$((MINS % 60))m"
    elif [ "$HOURS" -lt 24 ]; then
      TIME_STR="${HOURS}h"
    elif [ $((HOURS % 24)) -eq 0 ]; then
      TIME_STR="$((HOURS / 24))d"
    else
      TIME_STR="$((HOURS / 24))d$((HOURS % 24))h"
    fi
    LABEL="in $TIME_STR · $F_TITLE"
    JOIN_URL="$F_JOIN"
  else
    FOCUS=""   # something exists, but past the horizon: the pill has nothing to say
  fi

  # The fill window, measured from the START in both directions — five minutes
  # before is "go now" and five after is "you are late", and they are the same
  # fact. It deliberately does NOT last the whole meeting: a pill that stays
  # filled for an hour is just a pill that is a different colour.
  if [ -n "$FOCUS" ] && [ "$DIFF" -le $((IMMINENT * 60)) ] &&
    [ "$DIFF" -ge $((-IMMINENT * 60)) ]; then
    FILL=1
  fi
fi

# Via a tmp file and a rename: a plain `>` truncates first, so a right-click
# landing inside a tick's write window would read an empty file and open
# nothing. The rename is atomic, so the reader sees the old link or the new one.
printf '%s' "$JOIN_URL" >"$JOIN_CACHE.tmp" && mv -f "$JOIN_CACHE.tmp" "$JOIN_CACHE"

# Filled: the accent moves off the glyph and onto the whole pill, and the type
# goes to BASE so it reads on it. Unfilled is the bar's ordinary SURFACE0 pill.
if [ "$FILL" = 1 ]; then
  "$SB" --set "$ITEM_NAME" label="$LABEL" \
    background.color="$MAUVE" icon.color="$BASE" label.color="$BASE"
else
  "$SB" --set "$ITEM_NAME" label="$LABEL" \
    background.color="$SURFACE0" icon.color="$MAUVE" label.color="$TEXT"
fi

[ "$WANT_POPUP" = 1 ] || exit 0

# ── the dropdown ──────────────────────────────────────────────────────────────
# A timeline, top to bottom: what's DONE (the last `past` hours), what's on NOW,
# and what's NEXT. The old popup was five undated "09:00 Some meeting" rows,
# which answered the one question you already knew the answer to and none of the
# ones you opened it for — which day, who with, and how do I get in.
#
# Two rows per event, and the split is the point:
#   spine  `Today 12:45` in the ICON, the title in the LABEL — one item draws one
#          colour, so the when and the what can only differ if they sit in
#          different fields. The when column is fixed-width so the times stack.
#   meta   duration + who, dim, hanging under the TITLE rather than under the
#          clock — the when column is a column, and nothing else belongs in it —
#          with the join affordance trailing it in SAPPHIRE. Clicking either row
#          opens the link.
#
# Exactly ONE row gets a filled box: the event the PILL is about. Highlighting
# by background rather than by colour alone is what makes it findable at a
# glance, and keeping it to a single row means no two rounded boxes ever meet at
# a seam. Everything else is separated by weight and hue only.
#
# Every row is accumulated into ARGS and handed to ONE sketchybar call, so the
# popup appears fully formed instead of growing a row at a time.
#
# Horizontal measures are PIXEL counts derived from the monospace advance, never
# leading spaces: SketchyBar sizes an item from its label with the whitespace
# trimmed and then draws the untrimmed string, so an indent written as spaces
# buys nothing but a row clipped by exactly the width of its own indent. (The
# AI-usage pill's grid documents the same trap, including that a no-break space
# is trimmed too.) The advance is ~0.602em, which holds for JetBrains Mono and
# Fira Code alike — name a proportional family in haus.fonts.mono and the meta
# lines drift a few points, which is a wobble in one popup, not a broken bar.
ROW_ICON_PAD=10                       # the popup's own left margin
WHEN_COLS=11                          # "Today 12:45" — every when is this wide
WHEN_GAP=12                           # when column -> title gutter
ADV_M=$(awk -v s="${FS_SMALL:-13}" 'BEGIN { printf "%.0f", s * 602 }')
px() { printf '%s' $((($1 + 500) / 1000)); }
# The meta line hangs under the TITLE, not under the clock: the when column
# holds one kind of thing and a duration is not it.
META_INDENT=$(px $((ROW_ICON_PAD * 1000 + WHEN_COLS * ADV_M + WHEN_GAP * 1000)))
META_GAP=$(px $((2 * ADV_M)))         # meta text -> the trailing `Join`
H_SECTION=28
H_SPINE=26
H_META=20
TITLE_MAX=46

"$SB" --remove "/${ITEM_NAME}\.row\..*/" 2>/dev/null
ARGS=()
i=0

pop_add() {
  ARGS+=(--add item "${ITEM_NAME}.row.$i" "popup.${ITEM_NAME}"
    --set "${ITEM_NAME}.row.$i"
    icon="" icon.padding_left=0 icon.padding_right=0
    label="" label.padding_left=0 label.padding_right=14
    background.drawing=off background.height="$H_SPINE"
    click_script="$SB --set ${ITEM_NAME} popup.drawing=off"
    "$@")
  i=$((i + 1))
}

# A section rule: the smallest, dimmest thing in the popup. It names the band
# rather than decorating it — "Next" above three rows is what tells you the two
# above the fold are already over.
section() { # section <glyph> <colour> <name>
  pop_add icon="$1" icon.color="$2" icon.font="${BAR_FONT}:Bold:${FS_SMALL}" \
    icon.padding_left=10 icon.padding_right=8 \
    label="$3" label.color="$2" label.font="${BAR_FONT}:Bold:${FS_TINY}" \
    background.height="$H_SECTION"
}

# `Today`, `Tmrw`, `Ystdy` or a weekday, padded to a common width so the clock
# column underneath it stacks. Five characters is the longest of them, and the
# bar is monospace, so this is alignment rather than luck.
daylabel() { # daylabel <yyyy-mm-dd>
  case "$1" in
  "$TODAY") printf 'Today' ;;
  "$TOMORROW") printf 'Tmrw ' ;;
  "$YESTERDAY") printf 'Ystdy' ;;
  *) printf '%-5s' "$(date -j -f "%Y-%m-%d" "$1" +%a 2>/dev/null || echo "$1")" ;;
  esac
}

# "with X", "with X & Y", "with X +12" — the third form on purpose: past two
# names the list stops being who you're meeting and starts being a roster, and
# the count is the part that still means something.
withwho() { # withwho <comma-separated names>
  local names="$1" first second rest count
  [ -n "$names" ] || return 0
  count=$(printf '%s' "$names" | awk -F', ' '{ print NF }')
  first=${names%%, *}
  case "$count" in
  1) printf 'with %s' "$first" ;;
  2)
    second=${names#*, }
    printf 'with %s & %s' "$first" "$second"
    ;;
  *) printf 'with %s +%d' "$first" "$((count - 1))" ;;
  esac
}

# minutes -> "25m" / "1h" / "1h30m", the same shape the pill's countdown uses.
duration() { # duration <minutes>
  local m="$1"
  if [ "$m" -lt 60 ]; then printf '%dm' "$m"
  elif [ $((m % 60)) -eq 0 ]; then printf '%dh' $((m / 60))
  else printf '%dh%dm' $((m / 60)) $((m % 60)); fi
}

# One event: the spine, then the meta line under it. `focus` boxes the spine,
# which is the only background in the whole popup.
event_rows() { # event_rows <smin> <emin> <sdate> <stime> <title> <who> <join> <tone> <focus>
  local smin="$1" emin="$2" sdate="$3" stime="$4" title="$5" who="$6" join="$7"
  local tone="$8" focus="$9"
  local when icol tcol tweight meta click
  local box
  # `box=()` then an unguarded "${box[@]}" is an unbound-variable error under
  # `set -u` on the bash this shebang gets (macOS ships 3.2), which is why the
  # expansion at the bottom carries the +alternate guard rather than being bare.
  box=()

  when="$(daylabel "$sdate") $stime"
  case "$tone" in
  done) icol="$OVERLAY0"; tcol="$OVERLAY1"; tweight="Regular" ;;
  now) icol="$PEACH"; tcol="$TEXT"; tweight="Bold" ;;
  focus) icol="$MAUVE"; tcol="$TEXT"; tweight="Bold" ;;
  *) icol="$SUBTEXT0"; tcol="$SUBTEXT1"; tweight="Regular" ;;
  esac

  # A row with a link is a button; one without just closes the popup. Both are
  # click_scripts, so the popup never stays open under a browser it just raised.
  click="$SB --set ${ITEM_NAME} popup.drawing=off"
  [ -n "$join" ] &&
    click="$click; $(printf '%q' "$SELF") open $(printf '%q' "$join")"

  if [ "$focus" = 1 ]; then
    box=(background.drawing=on background.color="$SURFACE1"
      background.corner_radius=8 background.height=30)
  fi

  pop_add icon="$when" icon.color="$icol" \
    icon.font="${BAR_FONT}:Bold:${FS_SMALL}" \
    icon.padding_left="$ROW_ICON_PAD" icon.padding_right="$WHEN_GAP" \
    label="$title" label.color="$tcol" \
    label.font="${BAR_FONT}:${tweight}:${FS_SMALL}" \
    label.max_chars="$TITLE_MAX" \
    click_script="$click" ${box[@]+"${box[@]}"}

  meta="$(duration $((emin - smin)))"
  [ -n "$who" ] && meta="$meta · $(withwho "$who")"
  pop_add icon="$meta" icon.color="$OVERLAY1" \
    icon.font="${BAR_FONT}:Regular:${FS_TINY}" \
    icon.padding_left="$META_INDENT" icon.padding_right="$META_GAP" \
    label="${join:+󰕧 Join}" label.color="$SAPPHIRE" \
    label.font="${BAR_FONT}:Bold:${FS_TINY}" \
    background.height="$H_META" click_script="$click"
}

# The focus event's identity, so the loop below can box exactly one row. Start
# minute plus title, and `boxed` makes it exactly one even then: two calendars
# invited to the same meeting is one event listed twice with the same key, and
# two boxes is no highlight at all.
FOCUS_KEY=""
[ -n "$FOCUS" ] && FOCUS_KEY="$F_SMIN|$F_TITLE"

drawn_done=0
drawn_now=0
drawn_next=0
next_count=0
boxed=0
PAST_MIN=$((NOW_MIN - PAST * 60))

while IFS="$US" read -r smin emin sdate stime _etime title who join; do
  [ -n "${title:-}" ] || continue
  focus=0
  if [ "$boxed" = 0 ] && [ "$smin|$title" = "$FOCUS_KEY" ]; then
    focus=1
    boxed=1
  fi
  if [ "$emin" -le "$NOW_MIN" ]; then
    # Keyed on when it ENDED, not when it began: an all-day-long workshop that
    # finished an hour ago is the most relevant thing in the band, and a
    # start-keyed window is exactly the filter that would drop it.
    [ "$emin" -ge "$PAST_MIN" ] || continue
    [ "$drawn_done" = 1 ] || { section "󰄬" "$OVERLAY0" "Done"; drawn_done=1; }
    event_rows "$smin" "$emin" "$sdate" "$stime" "$title" "$who" "$join" "done" 0
  elif [ "$smin" -le "$NOW_MIN" ]; then
    [ "$drawn_now" = 1 ] || { section "󰔟" "$PEACH" "Now"; drawn_now=1; }
    event_rows "$smin" "$emin" "$sdate" "$stime" "$title" "$who" "$join" now "$focus"
  else
    [ "$next_count" -lt "$UPCOMING" ] || continue
    next_count=$((next_count + 1))
    [ "$drawn_next" = 1 ] || { section "󰃰" "$MAUVE" "Next"; drawn_next=1; }
    if [ "$focus" = 1 ]; then
      event_rows "$smin" "$emin" "$sdate" "$stime" "$title" "$who" "$join" focus 1
    else
      event_rows "$smin" "$emin" "$sdate" "$stime" "$title" "$who" "$join" later 0
    fi
  fi
done <<<"$EVENTS"

if [ "$i" = 0 ]; then
  pop_add icon="󰃭" icon.color="$OVERLAY1" icon.padding_left=10 icon.padding_right=10 \
    label="Nothing on the calendar" label.color="$OVERLAY1" \
    label.font="${BAR_FONT}:Regular:${FS_SMALL}" background.height="$H_SECTION"
fi

# Guarded, though the fallback row above means it can't currently be empty:
# `"${ARGS[@]}"` on an empty array is an unbound-variable error under `set -u`
# on bash 3.2, so an early `continue` added to the loop later would turn this
# into a dropdown that never opens, with nothing printed anywhere.
[ ${#ARGS[@]} -gt 0 ] && "$SB" "${ARGS[@]}" 2>/dev/null
"$SB" --set "$ITEM_NAME" popup.drawing=on
# Then hand it to barpop so it also closes on the first click anywhere else —
# the dismissal SketchyBar can't do, since it only hears clicks on its own
# items. SKETCHYBAR_BIN is how barpop learns WHICH bar to guard: unset, it
# queries the top bar, finds no such item on a pill that moved to the bottom
# one, and exits before it ever arms.
SKETCHYBAR_BIN="$SB" /run/current-system/sw/bin/barpop arm "$ITEM_NAME" 2>/dev/null &
exit 0
