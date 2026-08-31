#!/usr/bin/env bats
# Hermetic tests for modules/terminal/pi/cache-watchdog.mjs — pi's alarm on
# prompt-cache burn through meridian.
#
# Why a suite. The watchdog's whole value is its trigger, and BOTH sides of
# that line fail silently. Too quiet and a degenerate lane burns the plan the
# way the one that cost $221.78 of $233.45 did — reads frozen at 42,319 tokens
# for 380 turns, the whole growing tail re-written at 1-hour-TTL prices, and
# no signal. Too loud and it fires on a healthy lane's ordinary turns, a
# post-compaction re-baseline, or the single stale turn after an idle gap —
# and the next real burn gets swiped away as notification spam.
#
# The subject is a pure function — cumulative state + one turn's usage in,
# state + optional alert out — so every case here is data, and the suite needs
# no pi, no proxy and no API call.

bats_require_minimum_version 1.5.0

setup() {
  WD="${CACHE_WATCHDOG_UNDER_TEST:-$BATS_TEST_DIRNAME/../modules/terminal/pi/cache-watchdog.mjs}"
}

# lane <script> <threshold> — runs the given turn script through observe(),
# one JSON line per alert. The script is a JS expression array of usage
# objects; a number n in it expands to `n` turns of the PREVIOUS usage
# (the incident lane's writes grow, which is the shape repetition models).
lane() {
  node -e '
    import(process.argv[1]).then((m) => {
      const threshold = Number(process.argv[3]);
      let script;
      eval("script = " + process.argv[2]);
      let state = null, last = null;
      for (let item of script.flat()) {
        const n = typeof item === "number" ? item : 1;
        const usage = typeof item === "number" ? last : item;
        for (let i = 0; i < n; i++) {
          const { state: next, alert } = m.observe(state, usage, threshold);
          state = next;
          if (alert) console.log(JSON.stringify(alert));
        }
        if (typeof item !== "number") last = item;
      }
    });
  ' "$WD" "$1" "$2"
}

# The incident, at 1/100 scale: reads frozen at 423 from turn 2 on, writes
# growing ~63 tokens a turn as the tail climbs. Threshold 10k ≈ the real
# lane's cumulative-write curve compressed.
FREEZE='[{"cacheWrite":430,"cacheRead":0},{"cacheWrite":63,"cacheRead":423},63,{"cacheWrite":126,"cacheRead":423},200]'

# ---- the line between quiet and loud ----------------------------------------

@test "a healthy resumed lane never alerts: reads grow every turn" {
  # 60 turns of a working cache — reads grow by the turn's delta, writes are
  # small and constant. Cumulative writes pass any small threshold; the
  # frozen-read condition is never satisfied for even one turn.
  local script='['
  for i in $(seq 1 60); do script+="{cacheWrite:2000,cacheRead:5000+$i*1000},"; done
  script+='0]'
  run lane "$script" 10000
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a first turn never alerts: all writes, no reads, is not burn" {
  run lane '[{"cacheWrite":43000,"cacheRead":0}]' 10000
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "turns without usage are skipped, not crashed on" {
  run node -e '
    import(process.argv[1]).then((m) => {
      let state = null;
      for (const usage of [null, {output: 100}, {}]) {
        state = m.observe(state, usage, 20000).state;
      }
      if (state.write !== 0 || state.turns !== 0) process.exit(1);
    });
  ' "$WD"
  [ "$?" -eq 0 ]
}

@test "one stale turn after an idle gap is not burn" {
  # TTL expiry: reads drop to zero for exactly ONE turn (the whole context is
  # re-written), then the next turn re-reads everything. Ten consecutive
  # stale turns is the bar; this clears it by nine.
  run lane '[{"cacheWrite":2000,"cacheRead":5000},{"cacheWrite":6000,"cacheRead":0},{"cacheWrite":2000,"cacheRead":7000}]' 10000
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a post-compaction re-baseline is not burn: reads restart low but grow" {
  # Reads drop to 2k (compacted context) then climb every turn. The absolute
  # level is below the session's earlier peak; the growth is what matters.
  local script='[{"cacheWrite":50000,"cacheRead":40000},{"cacheWrite":30000,"cacheRead":2000}'
  for i in $(seq 1 20); do script+=",{cacheWrite:2000,cacheRead:2000+$i*1500}"; done
  script+=']'
  run lane "$script" 100000
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---- the degenerate mode, which is the reason this file exists ---------------

@test "the frozen-head pattern stays silent until the threshold, then fires once" {
  run lane "$FREEZE" 10000
  [ "$status" -eq 0 ]
  # 14 turns of frozen reads before cumulative writes cross 10k — quiet the
  # whole way, then exactly ONE tier-1 banner.
  [ "${#lines[@]}" -eq 1 ]
  [ "$(echo "${lines[0]}" | jq -r '.tier')" = "1" ]
  [ "$(echo "${lines[0]}" | jq -r '.stale')" -ge 10 ]
}

@test "a frozen head below the write threshold does not fire" {
  # Same frozen reads, but the session ends before the write bill is big
  # enough to shout about. 9 turns: stale clock hits 10 only at the end.
  run lane '[{"cacheWrite":430,"cacheRead":0},{"cacheWrite":63,"cacheRead":423},[63]]' 10000
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "it escalates once at 4x, then holds its fire" {
  run lane "$FREEZE" 2500
  [ "$status" -eq 0 ]
  # Threshold 2.5k crossed early (tier 1), 4x = 10k crossed late (tier 2),
  # then silence while the lane keeps freezing.
  [ "${#lines[@]}" -eq 2 ]
  [ "$(echo "${lines[0]}" | jq -r '.tier')" = "1" ]
  [ "$(echo "${lines[1]}" | jq -r '.tier')" = "2" ]
}

# ---- configuration -----------------------------------------------------------

@test "HAUS_PI_CACHE_WASTE_TOKENS moves the threshold" {
  # The incident lane at the 5M default needs ~650 growing turns to cross;
  # at 10k it fires inside the first twenty — same shape, same verdict, one
  # API call of test data instead of six hundred.
  out="$(HAUS_PI_CACHE_WASTE_TOKENS=10000 node -e '
    import(process.argv[1]).then((m) => {
      let state = null, alert = null, turns = 0;
      while (!alert && turns < 1000) {
        turns++;
        const usage = turns === 1
          ? { cacheWrite: 430, cacheRead: 0 }
          : { cacheWrite: 430 + turns * 63, cacheRead: 423 };
        alert = m.observe(state, usage, m.wasteThreshold()).alert;
        state = m.observe(state, usage, m.wasteThreshold()).state;
      }
      console.log(JSON.stringify({ alert, turns }));
    });
  ' "$WD")"
  [ "$(echo "$out" | jq -r '.alert.tier')" = "1" ]
  [ "$(echo "$out" | jq -r '.turns')" -lt 100 ]
}

@test "an unset threshold is 5M" {
  env -u HAUS_PI_CACHE_WASTE_TOKENS node -e '
    import(process.argv[1]).then((m) => {
      if (m.wasteThreshold() !== 5000000) process.exit(1);
    });
  ' "$WD"
  [ "$?" -eq 0 ]
}
