#!/bin/bash
# widget: interval = 600
# widget: popup = true
# widget: mark = blue
#
# weather.sh — the weather pill: the temperature now, and a dropdown that is
# the forecast. A framework widget (hausfold.co/docs/haus/rooms/bar-widgets):
# the header above is the whole of its wiring, and barlib owns the bar
# instance, the batching, the tones and the dropdown. Open-Meteo, no key
# (https://open-meteo.com/); the location is the machine's public IP, asked
# once a day.
#
# The tick FETCHES and the click READS. fetch pulls the forecast onto disk
# and emits the two things the pill shows; popup_rows renders the dropdown
# from that file, three jq reads and no network, so the panel opens in the
# time it takes to lay out rather than the time it takes a request to come
# back. Both fetches are bounded: Wi-Fi off fails fast on DNS, but a captive
# portal or a half-up VPN accepts the connection and never answers, and a
# SketchyBar plugin is synchronous, so an unbounded curl there wedges this
# pill's update slot rather than falling through.
#
# A fetch that fails KEEPS the last forecast — a reading ten minutes old is
# a better pill than "--°" — and the dropdown says how old it is once that
# matters. Only a machine with no forecast at all draws the placeholder.
set -u
export USER="${USER:-$(id -un)}"
export PATH="/opt/homebrew/bin:/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:/usr/bin:/bin:$PATH"

# BAR_ITEM is the fallback for a run with no $BAR_NAME of its own; barlib
# sources colors/sizes/bar.sh and resolves $SB from it. The pill is movable
# via haus.bar.bottom.items, so a bare `sketchybar` here would keep updating
# a top-bar item that no longer exists.
BAR_ITEM=weather
source "$HOME/.config/sketchybar/barlib.sh"

# In the session's own $TMPDIR (0700) rather than world-writable /tmp: a
# predictable name in a shared directory is a symlink away from writing
# somewhere else. `.json` is the forecast (with the city and the fetch time
# folded in), `.loc` the geolocated position.
STATE="${TMPDIR:-/tmp}/bar-weather"
LOC_MAX_AGE=86400
STALE_AFTER=1800

# Literal glyphs, not printf '\uXXXX' — macOS ships bash 3.2, whose printf
# has no \u escapes and emits the escape text verbatim into the bar.
G_CLOUD="󰖐"

# ── WMO weather codes ─────────────────────────────────────────────────────────
glyph() { # glyph <wmo-code>
  case "${1:-}" in
  0) printf '󰖙' ;;                          # clear
  1 | 2 | 3) printf '󰖐' ;;                  # partly cloudy … overcast
  45 | 48) printf '󰖑' ;;                    # fog
  51 | 53 | 55 | 56 | 57) printf '󰖗' ;;     # drizzle
  61 | 63 | 65 | 66 | 67) printf '󰖗' ;;     # rain
  71 | 73 | 75 | 77) printf '󰖘' ;;          # snow
  80 | 81 | 82) printf '󰖗' ;;               # showers
  85 | 86) printf '󰖘' ;;                    # snow showers
  95 | 96 | 99) printf '󰖓' ;;               # thunderstorm
  *) printf '%s' "$G_CLOUD" ;;
  esac
}

condition() { # condition <wmo-code>
  case "${1:-}" in
  0) printf 'Clear' ;;
  1) printf 'Mostly clear' ;;
  2) printf 'Partly cloudy' ;;
  3) printf 'Overcast' ;;
  45) printf 'Fog' ;;
  48) printf 'Icy fog' ;;
  51) printf 'Light drizzle' ;;
  53) printf 'Drizzle' ;;
  55) printf 'Heavy drizzle' ;;
  56 | 57) printf 'Freezing drizzle' ;;
  61) printf 'Light rain' ;;
  63) printf 'Rain' ;;
  65) printf 'Heavy rain' ;;
  66 | 67) printf 'Freezing rain' ;;
  71) printf 'Light snow' ;;
  73) printf 'Snow' ;;
  75) printf 'Heavy snow' ;;
  77) printf 'Snow grains' ;;
  80) printf 'Light showers' ;;
  81) printf 'Showers' ;;
  82) printf 'Heavy showers' ;;
  85) printf 'Light snow showers' ;;
  86) printf 'Snow showers' ;;
  95) printf 'Thunderstorm' ;;
  96 | 99) printf 'Thunderstorm, hail' ;;
  *) printf 'Unknown' ;;
  esac
}

compass() { # compass <degrees>
  local d=${1%%.*}
  case "$d" in '' | *[!0-9]*) return 0 ;; esac
  local -a dirs=(N NE E SE S SW W NW)
  printf '%s' "${dirs[$((((d + 22) % 360) / 45))]}"
}

# The UV index as a word and a tone, WHO's bands: the number alone means
# nothing to most people, and the tone is the one verdict in this dropdown.
uv_word() { # uv_word <index> → UV_WORD UV_TONE
  local u=${1%%.*}
  case "$u" in '' | *[!0-9]*) u=0 ;; esac
  if [ "$u" -le 2 ]; then UV_WORD=low; UV_TONE=text
  elif [ "$u" -le 5 ]; then UV_WORD=moderate; UV_TONE=text
  elif [ "$u" -le 7 ]; then UV_WORD=high; UV_TONE=warn
  elif [ "$u" -le 10 ]; then UV_WORD="very high"; UV_TONE=bad
  else UV_WORD=extreme; UV_TONE=bad; fi
}

# "how long ago", the shape the other dropdowns use for staleness.
ago() { # ago <seconds>
  local s=${1:-0}
  if [ "$s" -lt 3600 ]; then printf '%dm' $((s / 60))
  elif [ "$s" -lt 86400 ]; then printf '%dh' $((s / 3600))
  else printf '%dd' $((s / 86400)); fi
}

# ── the fetch ─────────────────────────────────────────────────────────────────
location() { # → LAT LON CITY, from the day's cache or ip-api.com
  local f="$STATE.loc" age now
  if [ -s "$f" ]; then
    now=$(date +%s)
    age=$(stat -f %m "$f" 2>/dev/null || echo 0)
    if [ $((now - age)) -gt "$LOC_MAX_AGE" ]; then
      curl -sf --max-time 6 -o "$f.tmp" "http://ip-api.com/json/?fields=lat,lon,city" 2>/dev/null &&
        jq -e '.lat' "$f.tmp" >/dev/null 2>&1 && mv "$f.tmp" "$f"
      rm -f "$f.tmp"
    fi
  else
    curl -sf --max-time 6 -o "$f.tmp" "http://ip-api.com/json/?fields=lat,lon,city" 2>/dev/null &&
      jq -e '.lat' "$f.tmp" >/dev/null 2>&1 && mv "$f.tmp" "$f"
    rm -f "$f.tmp"
  fi
  [ -s "$f" ] || return 1
  IFS=$'\t' read -r LAT LON CITY < <(jq -r '[.lat, .lon, (.city // "Here")] | @tsv' "$f" 2>/dev/null)
  [ -n "${LAT:-}" ]
}

fetch() {
  local url tmp="$STATE.json.tmp"
  if ! location; then
    # No forecast at all is the placeholder; an old one stays up.
    [ -s "$STATE.json" ] && return 1
    emit ok=0
    return 0
  fi
  url="https://api.open-meteo.com/v1/forecast?latitude=${LAT}&longitude=${LON}"
  url="${url}&current=temperature_2m,apparent_temperature,weather_code,relative_humidity_2m,wind_speed_10m,wind_direction_10m,uv_index"
  url="${url}&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_sum,precipitation_probability_max"
  url="${url}&hourly=temperature_2m,weather_code,precipitation_probability&timezone=auto&forecast_days=4"
  if ! curl -sf --max-time 8 -o "$tmp" "$url" 2>/dev/null ||
    ! jq -e '.current.temperature_2m' "$tmp" >/dev/null 2>&1; then
    rm -f "$tmp"
    [ -s "$STATE.json" ] && return 1
    emit ok=0
    return 0
  fi
  # Merged into a second temp and moved into place: a `>` onto the live
  # file truncates it before jq has said a word, and the last-good forecast
  # is the thing this file promises to keep.
  if ! jq -c --arg city "$CITY" --argjson fetched "$(date +%s)" '. + {city: $city, fetched: $fetched}' "$tmp" >"$tmp.2" 2>/dev/null; then
    rm -f "$tmp" "$tmp.2"
    [ -s "$STATE.json" ] && return 1
    emit ok=0
    return 0
  fi
  mv "$tmp.2" "$STATE.json"
  rm -f "$tmp"
  IFS=$'\t' read -r temp code < <(jq -r '[(.current.temperature_2m | round), .current.weather_code] | @tsv' "$STATE.json")
  emit ok=1 temp="$temp" code="$code"
}

# The icon says the sky and the label the temperature; the icon's colour is
# identity, painted once in the item's Nix style, and never a verdict.
render() {
  if [ "${ok:-0}" = 1 ]; then
    pill --icon "$(glyph "$code")" --label "${temp}°"
  else
    pill --icon "$G_CLOUD" --label "--°" --label-tone mute
  fi
}

# ── the dropdown ──────────────────────────────────────────────────────────────
# Everything below reads the tick's file. Three jq calls: the scalars, the
# next twelve hours, the next three days.
popup_rows() {
  local f="$STATE.json"
  if [ ! -s "$f" ]; then
    popup_heading --icon "$G_CLOUD" --label "Weather"
    popup_note --label "no forecast yet — asking every ten minutes"
    popup_button --label "Open Weather" --run "open -a Weather"
    return 0
  fi

  local city fetched temp feels code hum wind wdir uv tmax tmin sunrise sunset pchance psum
  IFS=$'\t' read -r city fetched temp feels code hum wind wdir uv tmax tmin sunrise sunset pchance psum < <(
    jq -r '[
      .city, .fetched,
      (.current.temperature_2m | round), (.current.apparent_temperature | round),
      .current.weather_code, (.current.relative_humidity_2m | round),
      (.current.wind_speed_10m | round), .current.wind_direction_10m,
      (.current.uv_index // 0 | round),
      (.daily.temperature_2m_max[0] | round), (.daily.temperature_2m_min[0] | round),
      (.daily.sunrise[0] | .[11:16]), (.daily.sunset[0] | .[11:16]),
      (.daily.precipitation_probability_max[0] // 0), ((.daily.precipitation_sum[0] // 0) * 10 | round / 10)
    ] | @tsv' "$f" 2>/dev/null
  )
  [ -n "${temp:-}" ] || { popup_heading --label "Weather"; popup_note --label "the forecast on disk did not parse"; return 0; }

  # The city is the heading and the sky is its badge, in the pill's own hue.
  popup_heading --icon "$(glyph "$code")" --label "$city" --badge "$(condition "$code")"
  popup_row --label "now" --value "${temp}°  ·  feels ${feels}°"
  popup_row --label "today" --value "↑ ${tmax}°   ↓ ${tmin}°"
  if [ "${pchance%%.*}" -gt 0 ] 2>/dev/null; then
    local rain="${pchance%%.*}%"
    [ "${psum%%.*}" -gt 0 ] 2>/dev/null && rain="$rain  ·  ${psum} mm"
    popup_row --label "rain" --value "$rain"
  fi

  # ── the next hours: a temperature curve, then four horizons ─────────────
  # The first hour AFTER now, found by comparing Open-Meteo's local-time
  # strings against the machine's own — no index arithmetic on the hour of
  # day, which is what used to hand the 23:00 forecast tomorrow's midnight
  # from TODAY's array.
  local now_local
  now_local=$(date '+%Y-%m-%dT%H:%M')
  local -a h_time=() h_code=() h_temp=()
  local t c d
  while IFS=$'\t' read -r t c d; do
    [ -n "$t" ] || continue
    h_time+=("$t"); h_code+=("$c"); h_temp+=("$d")
  done < <(
    jq -r --arg now "$now_local" '
      .hourly as $h
      | ([$h.time[] | select(. > $now)] | length) as $left
      | (($h.time | length) - $left) as $i
      | [range($i; ([$i + 12, ($h.time | length)] | min))]
      | map("\($h.time[.][11:16])\t\($h.weather_code[.])\t\($h.temperature_2m[.] | round)")
      | .[]' "$f" 2>/dev/null
  )
  if [ ${#h_temp[@]} -gt 1 ]; then
    # Temperatures spread over the middle of the sparkline's height — a
    # curve pinned to the edges reads as a percentage, and this isn't one.
    local lo hi span pts=""
    lo=${h_temp[0]}; hi=${h_temp[0]}
    for t in "${h_temp[@]}"; do
      [ "$t" -lt "$lo" ] && lo=$t
      [ "$t" -gt "$hi" ] && hi=$t
    done
    span=$((hi - lo))
    for t in "${h_temp[@]}"; do
      if [ "$span" -gt 0 ]; then
        pts="${pts:+$pts }$((15 + (t - lo) * 70 / span))"
      else
        pts="${pts:+$pts }50"
      fi
    done
    popup_graph --points "$pts"
    local i
    for i in 0 2 5 8; do
      [ "$i" -lt ${#h_time[@]} ] || break
      popup_row --icon "$(glyph "${h_code[$i]}")" --label "${h_time[$i]}" --value "${h_temp[$i]}°"
    done
  fi

  # ── the next days ───────────────────────────────────────────────────────
  local -a rows=()
  local day dc dmax dmin dchance name
  while IFS=$'\t' read -r day dc dmax dmin dchance; do
    [ -n "$day" ] || continue
    rows+=("$day	$dc	$dmax	$dmin	$dchance")
  done < <(
    jq -r '
      .daily as $d
      | [range(1; ([4, ($d.time | length)] | min))]
      | map("\($d.time[.])\t\($d.weather_code[.])\t\($d.temperature_2m_max[.] | round)\t\($d.temperature_2m_min[.] | round)\t\($d.precipitation_probability_max[.] // 0)")
      | .[]' "$f" 2>/dev/null
  )
  if [ ${#rows[@]} -gt 0 ]; then
    popup_separator
    for t in "${rows[@]}"; do
      IFS=$'\t' read -r day dc dmax dmin dchance <<<"$t"
      name=$(date -j -f "%Y-%m-%d" "$day" "+%a" 2>/dev/null || printf '%s' "$day")
      local v="↑ ${dmax}°   ↓ ${dmin}°"
      [ "${dchance%%.*}" -ge 30 ] 2>/dev/null && v="󰖗 ${dchance%%.*}%   $v"
      popup_row --icon "$(glyph "$dc")" --label "$name" --value "$v"
    done
  fi

  # ── the rest of the picture ─────────────────────────────────────────────
  popup_separator
  popup_row --label "wind" --value "${wind} km/h $(compass "$wdir")"
  popup_row --label "humidity" --value "${hum}%"
  uv_word "$uv"
  popup_row --label "UV" --value "${uv} · ${UV_WORD}" --tone "$UV_TONE"
  popup_row --label "sun" --value "↑ ${sunrise}   ↓ ${sunset}"

  local age=$(($(date +%s) - ${fetched:-0}))
  [ "$age" -gt "$STALE_AFTER" ] && popup_note --label "as of $(ago "$age") ago"

  popup_button --icon "$G_CLOUD" --label "Open Weather" --run "open -a Weather"
}

# ── gestures ──────────────────────────────────────────────────────────────────
on_click() { popup_toggle; }
# The native app: right-click rather than a modifier because the dropdown is
# the answer nine times in ten and this is where you go when it isn't.
on_right_click() { open -a Weather; }

barlib_main "$@"
