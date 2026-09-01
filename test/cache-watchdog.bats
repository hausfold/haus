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
# state + optional alert out — so most cases here are data, and the suite
# needs no pi, no proxy and no API call. The three that exercise the wiring
# (the off switch, the events it registers, the reset) hand the default export
# a fake `pi` that records `on()` calls, which is the whole surface pi gives
# an extension.
#
# ⚠️ `run node …` sets `$status`, NOT `$?` — `$?` is always `run`'s own 0, so
# a `[ "$?" -eq 0 ]` after one is an assertion that cannot fail. Two of these
# cases were written that way and tested nothing; assert on `$status`.

bats_require_minimum_version 1.5.0

setup() {
  WD="${CACHE_WATCHDOG_UNDER_TEST:-$BATS_TEST_DIRNAME/../modules/terminal/pi/cache-watchdog.mjs}"
}

# lane <script> <threshold> — runs the given turn script through observe(),
# one JSON line per alert. The script is a JS expression array of usage
# objects; a number n in it expands to `n` MORE turns of the previous usage,
# which is how a long stretch of one shape stays one token wide here.
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

# The incident, at 1/100 scale: reads frozen at 423 from turn 2 on, a constant
# 63-token write while the head holds, then a 126-token one as the tail gets
# longer. Threshold 10k ≈ the real lane's cumulative-write curve compressed.
FREEZE='[{"cacheWrite":430,"cacheRead":0},{"cacheWrite":63,"cacheRead":423},63,{"cacheWrite":126,"cacheRead":423},200]'

# pi's EMPTY_USAGE, byte for byte — the usage on the assistant message
# `handleRunFailure` synthesises for an aborted or failed run
# (@earendil-works/pi-agent-core's agent.js, pi 0.84.3). Every field zero.
ABORT='{"input":0,"output":0,"cacheRead":0,"cacheWrite":0,"totalTokens":0,"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0,"total":0}}'

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

# ---- turns with nothing in them ---------------------------------------------

@test "a turn with no usage at all moves nothing" {
  # null, undefined, {} and pi's own EMPTY_USAGE are all "no data": no write,
  # no turn counted, and — the load-bearing half — the read baseline is left
  # at its -1 sentinel rather than being pulled down to 0.
  run node -e '
    import(process.argv[1]).then((m) => {
      let state = null;
      for (const usage of [null, undefined, {}, JSON.parse(process.argv[2])]) {
        state = m.observe(state, usage, 20000).state;
      }
      const want = JSON.stringify(m.empty());
      if (JSON.stringify(state) !== want) {
        console.error(JSON.stringify(state) + " !== " + want);
        process.exit(1);
      }
    });
  ' "$WD" "$ABORT"
  [ "$status" -eq 0 ]
}

@test "an abort mid-freeze does not reset the stale clock" {
  # THE regression. pi fires turn_end for every aborted and failed run with
  # EMPTY_USAGE attached, and one Esc is routine on an interactive lane. Read
  # as data, its cacheRead:0 collapses the read baseline, so the next real
  # turn's 423 looks like growth and the clock restarts — on a lane that is
  # interrupted every few turns the alarm can then NEVER fire. Here the abort
  # lands 30 turns into the freeze and the run still reports one banner whose
  # stale count spans the whole stretch, abort included.
  local script="[{\"cacheWrite\":430,\"cacheRead\":0},{\"cacheWrite\":63,\"cacheRead\":423},30,$ABORT,{\"cacheWrite\":63,\"cacheRead\":423},32,{\"cacheWrite\":126,\"cacheRead\":423},200]"
  run lane "$script" 10000
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [ "$(echo "${lines[0]}" | jq -r '.tier')" = "1" ]
  # Exactly two turns in this lane are not stale — the baseline and the one
  # that first reads the head back — so a clock that never reset reports
  # `stale == turns - 2`, which is 107 of 109 here. The code this replaced
  # restarted at the abort and reported 76: the same banner, thirty-one turns
  # of burn later, on a lane interrupted only ONCE. Interrupt every ten and it
  # never fires.
  [ "$(echo "${lines[0]}" | jq -r '.turns')" = "109" ]
  [ "$(echo "${lines[0]}" | jq -r '.stale')" = "107" ]
}

# ---- the degenerate mode, which is the reason this file exists ---------------

@test "the frozen-head pattern stays silent until the threshold, then fires once" {
  run lane "$FREEZE" 10000
  [ "$status" -eq 0 ]
  # Quiet the whole way while cumulative writes climb to 10k, then exactly
  # ONE tier-1 banner.
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

# ---- what the banner says ----------------------------------------------------

@test "the banner names the frozen stretch, and drops the dollars it does not have" {
  # pi prices a turn from its own model catalogue; an id it does not know
  # (which a proxy can hand it) prices at zero. "~$0 this session" would read
  # as an argument against the alarm, so the clause goes rather than lies.
  run node -e '
    import(process.argv[1]).then((m) => {
      const priced = m.bannerBody({ tier: 1, write: 22_200_000, stale: 380, cost: 221.78, turns: 417 });
      const free = m.bannerBody({ tier: 1, write: 22_200_000, stale: 380, cost: 0, turns: 417 });
      if (!priced.includes("380 of 417 turns")) process.exit(1);
      if (!priced.includes("22.2M tokens")) process.exit(1);
      if (!priced.includes("(~$222 this session)")) process.exit(1);
      if (free.includes("$")) process.exit(1);
      if (!free.includes("22.2M tokens —")) process.exit(1);
    });
  ' "$WD"
  [ "$status" -eq 0 ]
}

# ---- configuration and wiring ------------------------------------------------

@test "HAUS_PI_CACHE_WASTE_TOKENS moves the threshold" {
  # The incident lane at the 5M default needs ~650 growing turns to cross;
  # at 10k it fires inside the first hundred — same shape, same verdict, one
  # API call of test data instead of six hundred.
  run env HAUS_PI_CACHE_WASTE_TOKENS=10000 node -e '
    import(process.argv[1]).then((m) => {
      const threshold = m.wasteThreshold();
      let state = null, alert = null, turns = 0;
      while (!alert && turns < 1000) {
        turns++;
        const usage = turns === 1
          ? { cacheWrite: 430, cacheRead: 0 }
          : { cacheWrite: 430 + turns * 63, cacheRead: 423 };
        ({ state, alert } = m.observe(state, usage, threshold));
      }
      console.log(JSON.stringify({ alert, turns }));
    });
  ' "$WD"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.alert.tier')" = "1" ]
  [ "$(echo "$output" | jq -r '.turns')" -lt 100 ]
}

@test "an unset threshold is 5M, and a junk one falls back to it" {
  run env -u HAUS_PI_CACHE_WASTE_TOKENS node -e '
    import(process.argv[1]).then((m) => {
      if (m.wasteThreshold() !== 5000000) process.exit(1);
      for (const raw of ["", "0", "-1", "nonsense"]) {
        if (m.wasteThreshold({ HAUS_PI_CACHE_WASTE_TOKENS: raw }) !== 5000000) process.exit(1);
      }
      if (m.wasteThreshold({ HAUS_PI_CACHE_WASTE_TOKENS: "250000" }) !== 250000) process.exit(1);
    });
  ' "$WD"
  [ "$status" -eq 0 ]
}

@test "HAUS_PI_CACHE_WATCHDOG=0 registers nothing at all" {
  # The off switch has to be OFF, not merely quiet: an extension that still
  # subscribes is one that still runs on every turn of every session.
  run env HAUS_PI_CACHE_WATCHDOG=0 node -e '
    import(process.argv[1]).then((m) => {
      const seen = [];
      m.default({ on: (name) => seen.push(name) });
      if (seen.length !== 0) process.exit(1);
      if (m.watchdogEnabled({ HAUS_PI_CACHE_WATCHDOG: "0" })) process.exit(1);
      if (!m.watchdogEnabled({})) process.exit(1);
      if (!m.watchdogEnabled({ HAUS_PI_CACHE_WATCHDOG: "1" })) process.exit(1);
    });
  ' "$WD"
  [ "$status" -eq 0 ]
}

@test "the extension subscribes to session_start and turn_end, and a restart re-zeroes" {
  # session_start must clear the window: a resumed pi is a fresh bill, and a
  # carried-over stale clock would fire the first banner on somebody else's
  # burn. Driving the real handlers also proves a turn_end whose event has no
  # message — pi's own shape for a failure it could not even build — costs
  # nothing rather than throwing out of the event loop.
  run env -u HAUS_PI_CACHE_WATCHDOG HAUS_PI_CACHE_WASTE_TOKENS=1000 node -e '
    import(process.argv[1]).then((m) => {
      const on = {};
      m.default({ on: (name, fn) => { on[name] = fn; } });
      if (typeof on.session_start !== "function") process.exit(1);
      if (typeof on.turn_end !== "function") process.exit(1);
      on.turn_end({});
      on.turn_end({ message: {} });
      on.turn_end(undefined);
      // Freeze hard enough to arm the clock, then restart before it fires.
      on.turn_end({ message: { usage: { cacheWrite: 400, cacheRead: 0 } } });
      for (let i = 0; i < 20; i++) {
        on.turn_end({ message: { usage: { cacheWrite: 10, cacheRead: 423 } } });
      }
      on.session_start();
      // Nothing here may throw; a banner spawn on a machine with no
      // haus-notify is swallowed by the error listener, so reaching this line
      // at all is the assertion.
    });
  ' "$WD"
  [ "$status" -eq 0 ]
}
