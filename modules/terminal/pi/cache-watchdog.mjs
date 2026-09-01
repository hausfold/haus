// cache-watchdog.mjs — pi's alarm on prompt-cache burn.
//
// Rendered by terminal to ~/.pi/agent/extensions/haus-cache-watchdog.ts (a .ts
// name, because that is the extension glob pi auto-discovers — the bytes are
// plain JS, which is a TS subset, and the bats suite imports THIS source file
// directly so the tested bytes and the rendered bytes cannot drift).
//
// The prompt-cache room (agent-state.ts's `x-session-affinity` header) has a
// degenerate mode: a resumed lane whose SDK replay only ever HITS a frozen
// head of the conversation. The reads stop growing — every turn reads back
// the same ~42k tokens while the context keeps climbing — so every turn also
// re-writes everything past that head as a fresh 1-hour-TTL cache write: 2x
// base input price, at whatever size the context has reached, hundreds of
// times a session. Measured on one 417-turn lane: 22.2M cache-write tokens
// against 20.4M reads, reads FROZEN at exactly 42,319 tokens from turn ~30 to
// the end — $221.78 of a $233.45 session, and from the outside it looked
// identical to a lane that was working.
//
// Nothing pi can set (breakpoints, headers, models) moves that number: the
// replay's request shaping happens inside meridian's SDK session. So the fix
// here is not to repair the cache but to refuse to burn SILENTLY. The
// signature this watches is the one that cannot mean anything else — READS
// THAT STOP GROWING while the writes continue. A healthy lane's reads grow
// every turn (each turn re-reads the whole prior context plus the new
// messages); a post-compaction lane's reads restart lower but grow again at
// once; an idle gap drops reads to zero for exactly ONE turn, then the next
// turn re-reads everything. Only a frozen head holds reads flat for turn
// after turn after turn.
//
// Alert condition: STALE_MIN consecutive BILLED turns whose read did not grow
// by more than READ_GROWTH_TOKENS over the previous billed turn's read, while
// the session's cumulative cache writes cross the threshold. Fires at the
// threshold, then once more at 4x, then never again — two banners is the
// ceiling per session. Both banners go through haus-notify, the same one door
// onto the screen as the compact and auth banners, with their own --source so
// rules.json can tune them independently.
//
// ⚠️ "BILLED" is load-bearing, and it is the one thing this file got wrong the
// first time. pi fires `turn_end` for turns that spent NOTHING: every aborted
// run and every failed one goes through `handleRunFailure`, which builds an
// assistant message carrying `EMPTY_USAGE` — every field, `cacheRead`
// included, a literal 0 (pi 0.84.3, @earendil-works/pi-agent-core's agent.js).
// Read as data, that zero says "the cache prefix collapsed to nothing", so the
// NEXT real turn's 42,319-token read looks like growth and zeroes the stale
// clock. One Esc is enough. On an interactive lane — where interrupting is
// routine — the clock could never reach STALE_MIN and the alarm would never
// fire at all, silently, which is the exact failure this file exists to
// prevent. A turn that billed nothing is a turn with no evidence in it: it
// moves no counter and resets no clock.
//
// Deliberately NOT gated on ctx.mode === "tui": a cost alarm belongs to a
// `pi -p` loop more than to a pane, and unlike the pill it repaints nothing —
// it is a banner with a source string. Fire-and-forget like everything else
// in this room: a missing binary or a non-haus machine must never surface as
// a failed hook.
//
// HAUS_PI_CACHE_WATCHDOG=0 turns the whole file off.
// HAUS_PI_CACHE_WASTE_TOKENS overrides the alert threshold (default 5M —
// roughly $50 of 1-hour-TTL writes at opus rates, $15 at sonnet's).

import { spawn } from "node:child_process";

const HAUS_NOTIFY = "@HAUS_NOTIFY@";

// Consecutive non-growing BILLED turns before the frozen head counts as real.
// A TTL expiry after an idle gap is stale for exactly one turn; the write
// threshold is the second half of the condition and does the rest of the
// false-positive work.
const STALE_MIN = 10;

// What "reads grew" means, in tokens, turn over turn. A working lane's read
// grows by at least the turn's own delta (~1k); a frozen head grows by
// exactly zero. A hundred tokens of slack separates those worlds by an order
// of magnitude on both sides.
const READ_GROWTH_TOKENS = 100;

// Alert at this much cumulative cache write, then once more at 4x, then never
// again. 2x would re-fire on a session that brushed the line.
const ESCALATION = 4;

const DEFAULT_WASTE_TOKENS = 5_000_000;

export function watchdogEnabled(env = process.env) {
	return (env.HAUS_PI_CACHE_WATCHDOG ?? "1") !== "0";
}

export function wasteThreshold(env = process.env) {
	const raw = Number(env.HAUS_PI_CACHE_WASTE_TOKENS);
	return Number.isFinite(raw) && raw > 0 ? raw : DEFAULT_WASTE_TOKENS;
}

// A usage field, coerced. Anything that is not a non-negative finite number —
// absent, null, NaN, a string pi never sends — reads as zero, because every
// caller below wants "how much did this cost" and no shape answers that with
// a negative.
function tokens(value) {
	const n = Number(value);
	return Number.isFinite(n) && n > 0 ? n : 0;
}

// A fresh window. `read` starts at -1 rather than 0 so the FIRST billed turn
// is never mistaken for growth over a zero baseline — it has nothing to grow
// over, and `firstTurn` below is the state that says so.
export function empty() {
	return { write: 0, read: -1, cost: 0, stale: 0, tiers: 0, turns: 0 };
}

function carry(state) {
	const base = empty();
	if (!state || typeof state !== "object") return base;
	return {
		write: tokens(state.write),
		read: Number.isFinite(Number(state.read)) ? Number(state.read) : -1,
		cost: tokens(state.cost),
		stale: tokens(state.stale),
		tiers: tokens(state.tiers),
		turns: tokens(state.turns),
	};
}

// The pure half. `state` is carried by the caller (the extension keeps one per
// pi session); `usage` is one turn's `message.usage` — pi-ai's `Usage`, whose
// fields are camelCase and whose `cost.total` is that message's own dollars
// (node_modules/@earendil-works/pi-ai/dist/types.d.ts). Returns the state to
// carry forward and, when a tier fires, the numbers a banner should name.
// Never throws on a shape it does not recognize — a turn without usage is a
// turn without data, not a crash.
export function observe(state, usage, threshold) {
	const prev = carry(state);
	if (!usage || typeof usage !== "object") return { state: prev, alert: null };

	const write = tokens(usage.cacheWrite);
	const read = tokens(usage.cacheRead);

	// The billed gate — see the ⚠️ in the header. `input`/`output` are in the
	// sum so a turn that spent real money with the cache entirely cold still
	// counts; only a turn that spent NOTHING is discarded, and that is exactly
	// the shape pi's aborted and failed runs carry.
	if (write + read + tokens(usage.input) + tokens(usage.output) <= 0) {
		return { state: prev, alert: null };
	}

	const firstTurn = prev.read < 0;
	const next = {
		write: prev.write + write,
		// Stale-ness is measured against the PREVIOUS billed turn's read, not a
		// cumulative peak: post-compaction reads restart lower and grow again,
		// and each restart is the reset the false-positive work depends on.
		read,
		cost: prev.cost + tokens(usage.cost?.total),
		// A first turn is neither stale nor fresh — it is the baseline, and it
		// is all writes by construction (nothing is cached yet).
		stale: firstTurn || read > prev.read + READ_GROWTH_TOKENS ? 0 : prev.stale + 1,
		tiers: prev.tiers,
		turns: prev.turns + 1,
	};

	// A turn that read back more than the last one did, by real growth: the
	// cache prefix moved. A frozen head is the exact absence of this.
	if (next.stale < STALE_MIN) return { state: next, alert: null };

	let tier = 0;
	if (next.tiers === 0 && next.write >= threshold) tier = 1;
	else if (next.tiers === 1 && next.write >= threshold * ESCALATION) tier = 2;
	if (tier === 0) return { state: next, alert: null };

	next.tiers = tier;
	return {
		state: next,
		alert: { tier, write: next.write, stale: next.stale, cost: next.cost, turns: next.turns },
	};
}

// What a banner says, kept out of the handler so the suite can read it. The
// dollars are pi's own `cost.total`, summed — and they are OMITTED when that
// sum is zero rather than printed as "~$0", because a model this pi has no
// price for (a proxied id its catalogue does not know) would otherwise turn
// the one number that makes the alarm land into an argument against it.
export function bannerBody(alert) {
	const money = alert.cost > 0 ? ` (~$${alert.cost.toFixed(0)} this session)` : "";
	return (
		`prompt cache reads have been frozen for ${alert.stale} of ${alert.turns} turns ` +
		`while writing ${(alert.write / 1e6).toFixed(1)}M tokens${money} — ` +
		"stop this lane; its resumed replay is only hitting the head"
	);
}

export default function (pi) {
	if (!watchdogEnabled()) return;

	// The threshold is read ONCE, like the off switch above it, so a session's
	// bar cannot move under it half way through — an alarm whose line drifts
	// mid-session is one whose two banners stop meaning "this much" and start
	// meaning "this much, when we looked".
	const threshold = wasteThreshold();

	// One window per pi session — /new, /resume and a fork each fire
	// session_start and each start at zero, because a fresh pi session is a
	// fresh bill and the old one was reported (or was never degenerate)
	// already. One variable and not a map: an extension instance belongs to
	// one session, and pi-subagents get a `pi` PROCESS each (agent-state.ts's
	// header has the measurement).
	let state = empty();

	pi.on("session_start", () => {
		state = empty();
	});

	// The spawn goes through the same shape as agent-state's `launch`: the
	// `error` listener is what keeps a missing binary from killing pi's
	// process, because a failed spawn arrives asynchronously.
	const notify = (source, title, body) => {
		try {
			const child = spawn(
				HAUS_NOTIFY,
				["--source", source, "--kind", "fault", "--title", title, "--body", body, "--symbol", "exclamationmark.triangle"],
				{ stdio: ["ignore", "ignore", "ignore"], detached: true },
			);
			child.on("error", () => {});
			child.unref();
		} catch {
			/* never break a turn over a banner */
		}
	};

	pi.on("turn_end", (event) => {
		try {
			const { state: next, alert } = observe(state, event?.message?.usage, threshold);
			state = next;
			if (alert) notify("haus.ai.pi.cache", "cache burn", bannerBody(alert));
		} catch {
			/* never break a turn over a banner */
		}
	});
}
