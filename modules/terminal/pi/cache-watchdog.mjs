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
// Alert condition: STALE_MIN consecutive turns whose read did not grow by
// more than READ_GROWTH_TOKENS over the previous turn's read, while the
// session's cumulative cache writes cross the threshold. Fires at the
// threshold, then once more at 4x, then never again — two banners is the
// ceiling per session. Both banners go through haus-notify, the same one door
// onto the screen as the compact and auth banners, with their own --source so
// rules.json can tune them independently.
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

// Consecutive non-growing read turns before the frozen head counts as real.
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

const WATCHDOG = (process.env.HAUS_PI_CACHE_WATCHDOG ?? "1") !== "0";

export function wasteThreshold() {
	const raw = Number(process.env.HAUS_PI_CACHE_WASTE_TOKENS);
	return Number.isFinite(raw) && raw > 0 ? raw : 5_000_000;
}

// The pure half. `state` is carried by the caller (the extension keeps one per
// session id); `usage` is one turn's message.usage. Returns the state to carry
// forward and, when a tier fires, the numbers a banner should name. Never
// throws on a shape it does not recognize — a turn without usage is a turn
// without data, not a crash.
export function observe(state, usage, threshold) {
	const cw = Number(usage?.cacheWrite ?? usage?.cache_write);
	const cr = Number(usage?.cacheRead ?? usage?.cache_read);
	const cost = Number(usage?.cost?.total);

	const next = {
		write: (state?.write ?? 0) + (Number.isFinite(cw) ? cw : 0),
		// Stale-ness is measured against the PREVIOUS turn's read, not a
		// cumulative peak: post-compaction reads restart lower and grow again,
		// and each restart is the reset the false-positive work depends on.
		read: Number.isFinite(cr) && cr >= 0 ? cr : (state?.read ?? 0),
		cost: (state?.cost ?? 0) + (Number.isFinite(cost) ? cost : 0),
		stale: state?.stale ?? 0,
		tiers: state?.tiers ?? 0,
		turns: (state?.turns ?? 0) + (Number.isFinite(cw) && cw > 0 ? 1 : 0),
	};
	if (Number.isFinite(cr) && cr >= 0) {
		// This turn read back more than the last one did, by real growth: the
		// cache prefix moved. A frozen head is the exact absence of this.
		if (cr > (state?.read ?? 0) + READ_GROWTH_TOKENS) next.stale = 0;
		else if (Number.isFinite(cw) && cw > 0) next.stale += 1;
	} else if (Number.isFinite(cw) && cw > 0) {
		next.stale += 1;
	}
	if (!Number.isFinite(cw) || cw <= 0) return { state: next, alert: null };

	// Parens matter: without them, a stale clock under STALE_MIN yields the
	// `&&` chain's own `false`, and `tier === 0` never matches it.
	const tier = next.stale >= STALE_MIN ? (next.tiers === 0 && next.write >= threshold ? 1
		: next.tiers === 1 && next.write >= threshold * ESCALATION ? 2
		: 0) : 0;
	if (tier === 0) return { state: next, alert: null };
	return {
		state: { ...next, tiers: tier },
		alert: {
			tier,
			write: next.write,
			stale: next.stale,
			cost: next.cost,
			turns: next.turns,
		},
	};
}

export default function (pi) {
	if (!WATCHDOG) return;

	// One window per session id — /new, /resume and a fork each fire
	// session_start and each start at zero, because a fresh pi session is a
	// fresh bill and the old one was reported (or was never degenerate) already.
	let state;

	pi.on("session_start", (_event, _ctx) => {
		state = undefined;
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
			const usage = event?.message?.usage;
			if (!usage) return;
			const { state: next, alert } = observe(state, usage, wasteThreshold());
			state = next;
			if (!alert) return;
			notify(
				"haus.ai.pi.cache",
				"cache burn",
				`prompt cache reads have been frozen for ${alert.stale} turns while writing ` +
					`${(alert.write / 1e6).toFixed(1)}M tokens (~$${alert.cost.toFixed(0)} this session) — ` +
					"stop this lane; its resumed replay is only hitting the head",
			);
		} catch {
			/* never break a turn over a banner */
		}
	});
}
