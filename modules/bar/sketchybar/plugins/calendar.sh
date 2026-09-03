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
# pointer is on the pill.
#
# How wide the settled form is comes from `haus.bar.calendar.width`, applied as
# the item's label.max_chars in the Nix style — SketchyBar owns the clip, so
# nothing here has to know the number.
#
# ── the framework ─────────────────────────────────────────────────────────────
# A barlib widget (hausfold.co/docs/haus/rooms/bar-widgets). The header below is
# the pill's whole wiring; the runtime owns the $SB routing, the diffed repaint,
# the click dispatch, and the whole popup dance — the per-row items, the one
# batched --add, the close-on-click and the barpop arm this file used to spell
# out by hand. The dropdown's rows are the runtime's six kinds now: a heading
# per band, a two-column row per event (the when column on the left, the title
# on the value column), and a second two-column row hanging the duration and
# the who under it with the Join affordance trailing in the value slot.
# widget: popup      = true
# widget: mark = plum
# widget: subscribes = mouse.entered, mouse.exited, mouse.exited.global
set -u
export USER="${USER:-$(id -un)}"
export PATH="/opt/homebrew/bin:/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:$PATH"

BAR_ITEM=calendar
source "$HOME/.config/sketchybar/barlib.sh"
# GENERATED from haus.bar.calendar.* — absent on a desktop that predates it, hence
# the defaults below rather than a hard `source`.
[ -f "$HOME/.config/sketchybar/calendar_config.sh" ] &&
  source "$HOME/.config/sketchybar/calendar_config.sh"

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

# A dropdown row's click: the link that row was built with. A CLI mode rather
# than a handler because a click_script is a fresh process, and it exits here
# without ever reaching barlib_main — the runtime already appended the popup
# close to the row.
if [ "${1:-}" = "open" ]; then
  open_join "${2:-}"
  exit 0
fi

# ── reading the calendar ──────────────────────────────────────────────────────
# ONE icalBuddy call serves whichever half asked (~50 ms, measured), covering
# `past` hours back to a week ahead — the pill applies its own horizon to what
# comes out. Every field is LABELLED (`-npn` deliberately not passed):
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
#
# Sets EVENTS (one US-separated row per event, oldest first:
# startMin endMin sdate stime etime title who join), NOW_MIN and the day
# anchors. startMin/endMin are NAIVE local minutes (a Julian day number × 1440
# plus the clock), which is all the ordering, the section split and the
# durations need and costs no `date` fork per event. The one number that must
# survive a DST boundary — the countdown the pill prints — is computed from a
# real epoch in pick_focus, for the one event it's about.
read_calendar() {
  NOW_YMD=$(date +%Y-%m-%d)
  NOW_HM=$(date +%H:%M)
  TODAY=$NOW_YMD
  TOMORROW=$(date -v+1d +%F 2>/dev/null || echo "")
  YESTERDAY=$(date -v-1d +%F 2>/dev/null || echo "")

  local from ahead to raw
  from=$(date -v-"${PAST}"H +%F 2>/dev/null || date +%F)
  ahead=$(((HORIZON + 23) / 24))
  [ "$ahead" -lt 7 ] && ahead=7
  to=$(date -v+"${ahead}"d +%F 2>/dev/null || date +%F)
  raw=$("$ICALBUDDY" -nc -nrd -ea \
    -nnr " ⏎ " -b "@@E@@" -ps "|@@F@@|" \
    -df "%Y-%m-%d" -tf "%H:%M" \
    -iep "datetime,title,attendees,location,url,notes" \
    eventsFrom:"$from" to:"$to" 2>/dev/null)

  # Both lists reach awk COMMA-joined, never newline-joined: a `-v` assignment
  # is parsed by awk's own lexer, which will not take a literal newline inside
  # the value and dies with "newline in string" — silently, from the pill's
  # point of view, since stderr goes nowhere.
  EVENTS=$(printf '%s\n' "$raw" | awk \
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
    # -po for these two and a desktop that reorders them would otherwise file every
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

  NOW_MIN=$(awk -v d="$NOW_YMD" -v t="$NOW_HM" '
BEGIN {
  y = substr(d,1,4)+0; m = substr(d,6,2)+0; dd = substr(d,9,2)+0
  a = int((14-m)/12); yy = y+4800-a; mm = m+12*a-3
  j = dd + int((153*mm+2)/5) + 365*yy + int(yy/4) - int(yy/100) + int(yy/400) - 32045
  print j*1440 + substr(t,1,2)*60 + substr(t,4,2)
}')
}

# ── which event the pill is about ─────────────────────────────────────────────
# The one running right now, else the next one to start. An in-progress meeting
# outranks the one after it: during the half hour you are actually in it, "in 4h
# · Standup" is the pill telling you about the wrong thing.
#
# Sets FOCUS (the picked row, or empty), the F_* fields it splits into, and the
# three facts the pill paints from: LABEL, FILL and JOIN_URL.
pick_focus() {
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
  F_SMIN=""
  F_TITLE=""
  if [ -n "$FOCUS" ]; then
    IFS="$US" read -r F_STATE F_SMIN _F_EMIN F_SDATE F_STIME _F_ETIME F_TITLE _F_WHO F_JOIN \
      <<<"$FOCUS"
    # The one place a real epoch is worth two forks: everything else here is
    # naive local minutes, which is exact for ordering and off by an hour for a
    # duration that straddles a daylight-saving change. This number is a
    # countdown someone walks into a meeting on.
    local start_epoch now_epoch diff
    start_epoch=$(date -j -f "%Y-%m-%d %H:%M" "$F_SDATE $F_STIME" +%s 2>/dev/null || echo "")
    now_epoch=$(date +%s)
    diff=$((${start_epoch:-$now_epoch} - now_epoch))

    if [ "$F_STATE" = "now" ]; then
      LABEL="now · $F_TITLE"
      JOIN_URL="$F_JOIN"
    elif [ "$diff" -le $((HORIZON * 3600)) ]; then
      local mins hours time_str
      mins=$(((diff + 59) / 60))   # round UP: "in 0m" for a meeting that hasn't started
      [ "$mins" -lt 0 ] && mins=0
      hours=$((mins / 60))
      if [ "$mins" -lt 60 ]; then
        time_str="${mins}m"
      elif [ "$hours" -lt "$PRECISE_UNDER" ] && [ $((mins % 60)) -gt 0 ]; then
        time_str="${hours}h$((mins % 60))m"
      elif [ "$hours" -lt 24 ]; then
        time_str="${hours}h"
      elif [ $((hours % 24)) -eq 0 ]; then
        time_str="$((hours / 24))d"
      else
        time_str="$((hours / 24))d$((hours % 24))h"
      fi
      LABEL="in $time_str · $F_TITLE"
      JOIN_URL="$F_JOIN"
    else
      FOCUS=""   # something exists, but past the horizon: the pill has nothing to say
    fi

    # The fill window, measured from the START in both directions — five minutes
    # before is "go now" and five after is "you are late", and they are the same
    # fact. It deliberately does NOT last the whole meeting: a pill that stays
    # filled for an hour is just a pill that is a different colour.
    if [ -n "$FOCUS" ] && [ "$diff" -le $((IMMINENT * 60)) ] &&
      [ "$diff" -ge $((-IMMINENT * 60)) ]; then
      FILL=1
    fi
  fi
}

fetch() {
  read_calendar
  pick_focus
  # Via a tmp file and a rename: a plain `>` truncates first, so a right-click
  # landing inside a tick's write window would read an empty file and open
  # nothing. The rename is atomic, so the reader sees the old link or the new
  # one.
  printf '%s' "$JOIN_URL" >"$JOIN_CACHE.tmp" && mv -f "$JOIN_CACHE.tmp" "$JOIN_CACHE"
  emit label="$LABEL" fill="$FILL"
}

# Filled: the accent moves off the glyph and onto the whole pill, and the type
# goes to BASE so it reads on it. Unfilled is the bar's ordinary SURFACE0 pill.
# Palette keys through sb_set rather than tones, deliberately: the mauve is
# this pill's IDENTITY (the ladder has no rung for a pill's own hue — the same
# reason clock's pink and cpu's peach live in the Nix style), and the fill is
# that identity swapping between the glyph and the background at runtime,
# which a style written at --add time cannot do. Same escape media.sh uses for
# its artwork tint.
render() {
  if [ "$fill" = 1 ]; then
    pill --label "$label"
    sb_set background.color="$MAUVE" icon.color="$BASE" label.color="$BASE"
  else
    pill --label "$label"
    sb_set background.color="$SURFACE0" icon.color="$MAUVE" label.color="$TEXT"
  fi
}

# ── the dropdown ──────────────────────────────────────────────────────────────
# A timeline, top to bottom: what's DONE (the last `past` hours), what's on NOW,
# and what's NEXT. Two rows per event, and the split is the point:
#
#   spine  the when in the NAME column ("Today 12:45" — five-char day label +
#          clock, so the times stack; the column is monospace), the title on
#          the value column. The band picks the tones: a done row is mute/dim,
#          the now band warns from its when column, everything later is dim.
#   meta   duration + who in the name column, dim, with the join affordance
#          trailing it on the value slot in the action sapphire. Clicking
#          either row opens the link.
#
# Exactly ONE row gets a filled box: the event the PILL is about. Highlighting
# by background rather than by colour alone is what makes it findable at a
# glance; popup_set on the row the runtime just added is how the box lands on
# exactly one.

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

# One event is one list item: the title, and under it when, how long and with
# whom. A `focus` event — the one the pill is counting down to — is the one
# whose Join is a BUTTON rather than a badge on its caption: the thing you
# opened this dropdown to press, drawn as a thing you press. Every other
# joinable event keeps the badge, so the panel has one button, and the button
# says which meeting is next.
event_rows() { # event_rows <smin> <emin> <sdate> <stime> <title> <who> <join> <band> <focus>
  local smin="$1" emin="$2" sdate="$3" stime="$4" title="$5" who="$6" join="$7"
  local band="$8" focus="$9"
  local when ttone stone meta

  when="$(daylabel "$sdate")"
  when="${when%"${when##*[![:space:]]}"} $stime"
  # The band picks the two tones: the title and the caption. A done row is
  # over — its title goes dim and its caption mute; the now band's caption is
  # the same peach the section rule wears; the focus row — the one the pill
  # counts down to — brightens its caption to full text; everything else is
  # the quiet default, a title in the text colour over a dim caption.
  case "$band" in
  done) ttone=dim; stone=mute ;;
  now) ttone=text; stone=warn ;;
  focus) ttone=text; stone=text ;;
  *) ttone=text; stone=dim ;;
  esac

  meta="$when · $(duration $((emin - smin)))"
  [ -n "$who" ] && meta="$meta · $(withwho "$who")"
  if [ -n "$join" ] && [ "$focus" != 1 ]; then
    popup_item --title "$title" --title-tone "$ttone" --subtitle "$meta" --subtitle-tone "$stone" \
      --badge "Join" --badge-tone action --run "$SELF open $(popup_quote "$join")"
  elif [ -n "$join" ]; then
    popup_item --title "$title" --title-tone "$ttone" --subtitle "$meta" --subtitle-tone "$stone" \
      --run "$SELF open $(popup_quote "$join")"
    popup_button --icon "󰕧" --label "Join" --run "$SELF open $(popup_quote "$join")"
  elif [ "$focus" = 1 ]; then
    # The one the pill counts down to, with nothing to join: the button
    # would have said which one it was, so a badge says it instead.
    popup_item --title "$title" --title-tone "$ttone" --subtitle "$meta" --subtitle-tone "$stone" \
      --badge "up next" --badge-tone text
  else
    popup_item --title "$title" --title-tone "$ttone" --subtitle "$meta" --subtitle-tone "$stone"
  fi
}

# A hairline between two bands, and none above the first: the bands are three
# sections of one timeline, and a rule is what says where one ends.
band_break() { # band_break <rows-drawn-so-far>
  [ "${1:-0}" -gt 0 ] && popup_separator
  return 0
}

popup_rows() {
  read_calendar
  pick_focus

  # The focus event's identity, so the loop below can box exactly one row.
  # Start minute plus title, and `boxed` makes it exactly one even then: two
  # calendars invited to the same meeting is one event listed twice with the
  # same key, and two boxes is no highlight at all.
  local focus_key="" drawn_done=0 drawn_now=0 drawn_next=0 next_count=0 boxed=0
  local rows=0 past_min focus
  [ -n "$FOCUS" ] && focus_key="$F_SMIN|$F_TITLE"
  past_min=$((NOW_MIN - PAST * 60))

  local smin emin sdate stime _etime title who join
  while IFS="$US" read -r smin emin sdate stime _etime title who join; do
    [ -n "${title:-}" ] || continue
    focus=0
    if [ "$boxed" = 0 ] && [ "$smin|$title" = "$focus_key" ]; then
      focus=1
      boxed=1
    fi
    if [ "$emin" -le "$NOW_MIN" ]; then
      # Keyed on when it ENDED, not when it began: an all-day-long workshop
      # that finished an hour ago is the most relevant thing in the band, and a
      # start-keyed window is exactly the filter that would drop it.
      [ "$emin" -ge "$past_min" ] || continue
      [ "$drawn_done" = 1 ] || { band_break "$rows"; popup_heading --icon "󰄬" --tone mute --label "Done"; drawn_done=1; }
      event_rows "$smin" "$emin" "$sdate" "$stime" "$title" "$who" "$join" "done" 0
    elif [ "$smin" -le "$NOW_MIN" ]; then
      [ "$drawn_now" = 1 ] || { band_break "$rows"; popup_heading --icon "󰔟" --tone warn --label "Now"; drawn_now=1; }
      event_rows "$smin" "$emin" "$sdate" "$stime" "$title" "$who" "$join" now "$focus"
    else
      [ "$next_count" -lt "$UPCOMING" ] || continue
      next_count=$((next_count + 1))
      # `--mark plum` is the pill's own mauve on the identity axis — the Next
      # band is the one the pill itself speaks for, so its rule wears the hue
      # the glyph in the bar does.
      [ "$drawn_next" = 1 ] || { band_break "$rows"; popup_heading --icon "󰃰" --mark plum --label "Next"; drawn_next=1; }
      if [ "$focus" = 1 ]; then
        event_rows "$smin" "$emin" "$sdate" "$stime" "$title" "$who" "$join" focus 1
      else
        event_rows "$smin" "$emin" "$sdate" "$stime" "$title" "$who" "$join" later 0
      fi
    fi
    rows=$((rows + 1))
  done <<<"$EVENTS"

  if [ "$rows" = 0 ]; then
    popup_note --label "Nothing on the calendar"
  fi
}

# ── gestures ──────────────────────────────────────────────────────────────────
on_click() { popup_toggle; }

# Right-click joins the event the pill is showing, off the cache the last fetch
# wrote — so the gesture is instant, never behind an icalBuddy spawn.
on_right_click() { open_join "$(cat "$JOIN_CACHE" 2>/dev/null)"; }

# Hover starts the sweep (haus.bar.calendar.marquee, which
# haus.appearance.reduceMotion sets off) and re-reads the calendar on the spot:
# looking at the pill is the moment its number has to be right, and it is also
# the cheapest possible cache-invalidation signal there is. barlib_tick is
# DIFFED, so a calendar that hasn't moved costs no repaint.
on_hover() {
  [ "${BAR_CALENDAR_MARQUEE:-1}" = "1" ] && sb_set scroll_texts=on
  barlib_tick
}

# The runtime routes mouse.exited AND its .global twin here — the per-item exit
# is missed when the pointer is flicked straight off the bar, and a stranded
# marquee is the exact failure the hover-only sweep design exists to prevent.
on_unhover() { sb_set scroll_texts=off; }

barlib_main
