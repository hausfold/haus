/**
 * agent-state.ts — pi's half of the rice's agent status AND its lane banners.
 *
 * Installed by terminal as ~/.pi/agent/extensions/haus-agent-state.ts (pi's
 * global auto-discovery dir), with the three @PLACEHOLDER@ paths below rendered
 * to absolute /run/current-system/sw/bin names: an extension runs inside pi's
 * own process, which is given no PATH guarantees.
 *
 * It is the pi equivalent of what haus wires for the other three clients, and
 * it carries BOTH halves at once, because pi has one seam where they have two:
 *
 *   the bar pill      `agent-state <working|waiting|idle|remove> pi <session>`
 *                     — the same four words Claude Code's four hooks, Codex's
 *                     three and the OpenCode plugin's four report.
 *   the lane banners  `scruff hook notify` with a Claude-SHAPED payload on
 *                     stdin, so a pi lane's trill fin is keyed, replaced,
 *                     focused and resolved by exactly the code path a Claude
 *                     lane's is. Nothing about that hook is Claude-specific
 *                     except the four event NAMES it switches on, which is why
 *                     synthesising them here is reuse rather than pretence.
 *
 * ── the event map ───────────────────────────────────────────────────────────
 *
 *   input (interactive)   → working   + UserPromptSubmit  (you answered: fin down)
 *   agent_start           → working   — the backstop: a loop that starts
 *                                       without passing through `input` (rpc,
 *                                       a queued continuation) still turns the
 *                                       pill green. A ⌘↵ lane's held prompt is
 *                                       NOT one of those — it arrives as pi's
 *                                       initialMessage through `session.prompt`,
 *                                       whose source defaults to "interactive"
 *                                       — so turn one is the dedupe's job.
 *   tool_execution_start  → waiting   + Notification      (ask fin up)
 *     …for an ask tool      ← the urgent one; the pill goes red
 *   tool_execution_end    → working   + PostToolUse       (answered: fin down)
 *     …for an ask tool
 *   agent_settled         → idle      + Stop              (done banner)
 *   session_shutdown      → remove                        (quit only)
 *
 * ── what pi has that Claude Code's hooks do not ─────────────────────────────
 * Two events with no CC counterpart earn a banner of their own. Neither is a
 * lane fin — they are not questions and nothing resolves them — so they go
 * through `haus-notify` (the one door onto the screen, AGENTS.md) rather than
 * through scruff, each with its OWN --source so rules.json can silence the
 * chatty one without silencing the one that means your lanes are all dead:
 *
 *   session_compact_failed  haus.ai.pi.compact — a fault. Compaction failing
 *                           is not cosmetic: the
 *                           turn that triggered it is usually dead, and in a
 *                           lane nobody is watching that reads as "it just
 *                           stopped".
 *   after_provider_response haus.ai.pi.auth — an auth/billing refusal
 *                           (401/402/403), ONCE per
 *                           session. pi reaches Anthropic through meridian's
 *                           loopback proxy, which authenticates by reading
 *                           Claude Code's OAuth token out of the login
 *                           keychain; when that goes stale every pi lane on the
 *                           machine is dead and says so nowhere. Transient
 *                           statuses (429, 5xx) are deliberately NOT here —
 *                           pi retries them, and a banner per retry is noise.
 *
 * ── why "waiting" needs a tool name at all ──────────────────────────────────
 * pi has no permission modes and so no permission prompt — the event Claude
 * Code calls Notification and Codex calls PermissionRequest does not exist
 * here. The honest analogue is a tool whose whole execution IS a question:
 * `ask_user_question` (@juicesharp/rpiv-ask-user-question, one of the four
 * packages haus.ai.pi.packages installs by default) blocks in ctx.ui until you
 * answer it. HAUS_PI_ASK_TOOLS overrides the list for anything else that does
 * the same.
 *
 * ── why `project_trust` is NOT wired, though it looks like the best fit ─────
 * "pi is holding at its trust dialog" is exactly the thing a background lane
 * needs a banner for, and the event exists. It cannot be used: pi emits it
 * BEFORE it consults its own trust store (`resolveProjectTrusted` asks the
 * extensions first and reads `trust.json` only if none of them decided), and
 * it emits it for any directory with a `.pi/` resource or a `.agents/skills`
 * ANYWHERE up the tree — which is every repo under ~/code/workshop. So a
 * handler cannot tell "about to prompt" from "answered months ago" without
 * re-implementing pi's nearest-ancestor trust lookup and its
 * `defaultProjectTrust` setting, and getting that wrong means an ask fin on
 * every pi start forever. The case it would have covered is already closed
 * from the other end: `scruff` copies the yes you already gave the repo onto
 * each lane it makes (its `~/.pi/agent/trust.json` propagation), so a haus
 * lane does not sit at that dialog in the first place.
 *
 * ── why the fin resolves on the ask tool and not on every tool ──────────────
 * Claude Code's wiring resolves on PostToolUse — every tool call in every pane
 * — because a permission prompt being approved shows up as "a tool ran" and
 * nothing finer. pi's ask is a tool of its own, so the resolve fires on that
 * tool ending and on you typing, and an ordinary read/grep/edit costs nothing
 * at all. scruff's marker-file gate still backs it up.
 *
 * ── TUI only ────────────────────────────────────────────────────────────────
 * Everything here is gated on ctx.mode === "tui". A `pi -p` is a command
 * somebody ran, not an agent pane: it inherits the $ZMX_SESSION of whatever
 * window it was run from, so reporting would repaint THAT lane's pill (a Claude
 * lane's, routinely) and banner a "finished its turn" nobody asked for.
 *
 * Fire-and-forget throughout, exactly like the OpenCode plugin: a missing
 * binary, a busy disk, a machine with no trill, or not being on a haus machine
 * at all must never surface as a failed hook in somebody's session.
 */

import { spawn, spawnSync } from "node:child_process";

const AGENT_STATE = "@AGENT_STATE@";
const SCRUFF = "@SCRUFF@";
const HAUS_NOTIFY = "@HAUS_NOTIFY@";

// What names this pane's trill fin when it is NOT inside a scruff lane. scruff
// keys a lane's fin by the lane (a lane answered from a resumed session is the
// same lane and the same question) and falls back to the payload's session id
// for anything else — so what this needs to be is stable for as long as the
// PANE is, which pi's own session id is not: `/new`, `/resume` and a fork each
// mint a new one, and a fin raised under the old id could then never be
// resolved. The pid is exactly pane-lived.
const SESSION_KEY = `pi-${process.pid}`;

// The tools whose execution IS a question to the user. Comma-separated
// override so a pi package that ships its own asker can join without a rebuild.
const ASK_TOOLS = new Set(
	(process.env.HAUS_PI_ASK_TOOLS ?? "ask_user_question,ask_user")
		.split(",")
		.map((s) => s.trim())
		.filter((s) => s.length > 0),
);

export default function (pi: any) {
	let cwd = process.cwd();
	// Set at session_start, and the gate on every path below: an extension is
	// loaded in every mode, and only one of them is a pane.
	let live = false;
	// Last state actually reported. pi fires `input` and `agent_start` back to
	// back for one prompt, and each report is a process spawn.
	let last = "";
	// The ask-tool calls currently blocking. A set rather than a flag: pi can
	// run tools in parallel, and two askers would otherwise have the first one
	// finishing clear the second one's `waiting`.
	const asks = new Set<string>();
	// The provider fault is once per session — see the header.
	let faulted = false;

	// Every spawn on this file's paths goes through here, and the `error`
	// listener is the load-bearing half rather than the try/catch around it.
	// A failed spawn — no such binary (not a haus machine, or a rebuild is
	// mid-flight), or a cwd that no longer exists (a lane reaped out from under
	// a still-running pi) — arrives ASYNCHRONOUSLY as an `error` event, and an
	// unhandled one on a ChildProcess is a thrown exception out of the event
	// loop: pi's whole process, killed by a menu-bar pill. The try/catch cannot
	// see it; the listener is the only thing that can. Measured, not theorised
	// — it is what a missing cwd did the first time this was exercised.
	const launch = (bin: string, argv: string[], stdin?: string): void => {
		try {
			const child = spawn(bin, argv, {
				cwd,
				stdio: [stdin === undefined ? "ignore" : "pipe", "ignore", "ignore"],
				detached: stdin === undefined,
			});
			child.on("error", () => {});
			if (stdin !== undefined) {
				child.stdin?.on("error", () => {});
				child.stdin?.end(stdin);
			}
			child.unref();
		} catch {
			/* never break a turn over a pill or a banner */
		}
	};

	const report = (next: string, wait = false): void => {
		if (!live) return;
		if (next !== "remove" && next === last) return;
		last = next;
		// Two arguments, not three. The third is `agent-state`'s `convo` label —
		// WHICH conversation a window is showing — and nothing can read a pi
		// one: terminal's ⌘F join (scripts/find.sh, `opencode_session`) treats
		// any `convo` label as an OPENCODE session id whenever an opencode db
		// exists on the machine, so filling it would route every pi window into
		// opencode's sqlite, return nothing, and silently cost ⌘F the
		// `zmx history` fallback it has today. Fill it when find.sh learns to
		// render a pi session, and not before.
		const argv = [next, "pi"];
		// `remove` is the one report that must land before we are gone:
		// session_shutdown is the last thing that runs, and an async child
		// would be orphaned mid-write, leaving a stale row on the bar for as
		// long as the zmx session outlives pi. (Same reasoning as the
		// OpenCode plugin's `dispose`.) spawnSync reports a failed spawn in its
		// return value rather than through an event, so it needs no listener.
		if (wait) {
			try {
				spawnSync(AGENT_STATE, argv, { cwd, stdio: "ignore" });
			} catch {
				/* a stale row is better than a client that will not quit */
			}
			return;
		}
		launch(AGENT_STATE, argv);
	};

	// One Claude-shaped hook payload into `scruff hook notify`. The four names
	// are the only Claude-specific thing about that hook; everything downstream
	// of them — the lane lookup, the fin key, the "Go to lane" action, the
	// marker gate, the resolve — is client-agnostic.
	const hook = (event: string): void => {
		if (!live) return;
		launch(
			SCRUFF,
			["hook", "notify"],
			JSON.stringify({ hook_event_name: event, cwd, session_id: SESSION_KEY }),
		);
	};

	// The two pi-only events, drawn through the one door onto the screen.
	const banner = (source: string, kind: string, title: string, body: string, symbol: string): void => {
		if (!live) return;
		launch(HAUS_NOTIFY, [
			"--source", source,
			"--kind", kind,
			"--title", title,
			"--body", body,
			"--symbol", symbol,
		]);
	};

	// The lane this pane is sitting in, for a banner that has no scruff row to
	// name it. `scruff hook notify` does its own, better lookup from cwd; this
	// is only for the haus-notify pair above.
	const where = (): string => {
		const base = cwd.split("/").filter(Boolean).pop();
		return base && base.length > 0 ? base : "pi";
	};

	pi.on("session_start", (_event: any, ctx: any) => {
		live = ctx.mode === "tui";
		cwd = ctx.cwd ?? cwd;
		// Deliberately no state report. A pane that just opened has not been
		// prompted, and `idle` in this vocabulary means "finished, go and look"
		// — a tick on the pill for a lane that has done nothing yet.
		last = "";
	});

	pi.on("input", (event: any) => {
		report("working");
		// Only a person typing takes a fin down. An extension steering the
		// session (pi-subagents, a queued follow-up) is not an answer to the
		// question the fin is asking.
		if (event?.source === "interactive") hook("UserPromptSubmit");
	});

	// The turn a lane is SPAWNED with never passes through `input`: ⌘↵ hands pi
	// the held prompt on its command line.
	pi.on("agent_start", () => report("working"));

	pi.on("tool_execution_start", (event: any) => {
		if (!ASK_TOOLS.has(event?.toolName)) return;
		asks.add(event.toolCallId);
		report("waiting");
		hook("Notification");
	});

	pi.on("tool_execution_end", (event: any) => {
		if (!asks.delete(event?.toolCallId)) return;
		if (asks.size === 0) report("working");
		hook("PostToolUse");
	});

	// "Fully settled": no automatic retry, compaction or queued continuation
	// will run. That is Claude Code's Stop minus the stop_hook_active case the
	// scruff hook has to filter for — pi does the filtering here.
	pi.on("agent_settled", () => {
		// A settled run has no tool in flight, whatever this set thinks.
		// `prepareToolCall` sits outside pi's own try in the agent loop, so a
		// throw there leaves a start with no matching end — and one stranded id
		// would keep `asks.size > 0` for the rest of the session, so every later
		// ask would end without ever reporting `working` again and the pill
		// would stick on red.
		asks.clear();
		report("idle");
		hook("Stop");
	});

	pi.on("session_shutdown", (event: any) => {
		if (event?.reason !== "quit") return; // reload/new/resume/fork keep the pane
		report("remove", true);
	});

	pi.on("session_compact_failed", (event: any) => {
		if (event?.aborted) return; // you cancelled it; you know
		banner(
			"haus.ai.pi.compact",
			"fault",
			where(),
			"compaction failed — the turn may be dead",
			"exclamationmark.triangle",
		);
	});

	pi.on("after_provider_response", (event: any) => {
		if (faulted) return;
		const status = event?.status;
		if (status !== 401 && status !== 402 && status !== 403) return;
		faulted = true;
		banner(
			"haus.ai.pi.auth",
			"fault",
			where(),
			`the model provider refused this session (${status})`,
			"key.slash",
		);
	});
}
