/**
 * desktop-guard.ts — pi's half of the guard that keeps an agent off the screen
 * the user is sitting at, asked as a trill banner you can answer from anywhere.
 *
 * Installed by terminal as ~/.pi/agent/extensions/haus-desktop-guard.ts, with
 * the two @PLACEHOLDER@ paths rendered to absolute /run/current-system/sw/bin
 * names: an extension runs inside pi's own process, which is given no PATH
 * guarantees.
 *
 * ── what this is ────────────────────────────────────────────────────────────
 * Claude Code panes have run behind `agent-desktop-guard` (modules/ai) for a
 * while: a PreToolUse hook that re-opens the permission prompt before a call
 * that would move the pointer, take focus or redraw the desktop. pi had
 * nothing. pi has no permission modes, no permission prompt and no sandbox —
 * its own docs say so — so an agent that decides to `open -a Ghostty` while you
 * are typing into something else simply does it, and no amount of prompt
 * wording makes that never happen.
 *
 * `tool_call` is pi's seam for it: it fires before the tool runs, it can block
 * (`{ block: true, reason }`), and the handler may be async — so it can hold
 * the turn open while a human answers. That is the whole mechanism.
 *
 * ── ONE ruleset, two clients ────────────────────────────────────────────────
 * The line this draws is not written here. This file shells out to the SAME
 * `agent-desktop-guard` binary Claude Code's PreToolUse hook calls, hands it
 * the same hook-shaped JSON on stdin, and reads the same verdict back:
 *
 *     {"tool_name":"Bash","tool_input":{"command":"…"}}
 *       → nothing at all                 no opinion, run it
 *       → hookSpecificOutput.permissionDecision == "ask" + a reason
 *
 * That is deliberate and it is the point. The guard's value is entirely in
 * WHERE the line falls — too loud trains click-through, too quiet lets a window
 * jump in front of someone mid-sentence — and both sides of it fail silently.
 * A second copy of those patterns in TypeScript would drift from the shell one
 * within a release and nothing would notice (docs/drift.md, and the workshop's
 * `bash`-and-`ts`-say-different-things shape). So pi inherits the ssh filter,
 * the `open -g` / `screencapture -x` / `tart --no-graphics` exemptions, the
 * size caps and test/desktop-guard.bats along with the patterns, for free, and
 * a change to the line lands in one file for both clients.
 *
 * Only `bash` is gated, which is the whole of pi's reach onto this screen —
 * the guard's other half matches computer-use tools, and pi has none.
 *
 * ── why the question goes to trill ──────────────────────────────────────────
 * The guard can only ever answer "ask", which for Claude Code means re-opening
 * the prompt IN THE PANE. That is the right answer for a watched pane and the
 * wrong one here: the whole reason
 * a lane runs in its own window is that nobody is watching it, and a question
 * that can only be answered by finding the pane is a lane parked until you go
 * looking. (Claude Code has since grown the same banner door — modules/ai's
 * `agent-desktop-ask`, which asks trill exactly when the pane's window is NOT
 * the focused one. This file is where that shape was worked out first.) `trill ask` blocks, draws Allow/Deny pills, exits with the pill's
 * index, and — the part that matters — parks the unanswered question as a fin
 * on the screen edge instead of dropping it. So the question survives you being
 * elsewhere, and answering costs one click from wherever you are.
 *
 * Not through `haus-notify`, unlike the two banners agent-state.ts raises: that
 * script is send-only, and its fallback when trill is absent is Apple's own
 * banner, which has no buttons and nothing to block on. An ask has no such
 * fallback, so this calls `trill` directly and falls back to the PANE.
 *
 * ── both doors are open at once ─────────────────────────────────────────────
 * The banner and pi's own `ctx.ui.select` dialog race, and the first definite
 * answer wins; the loser is taken down (the child gets SIGINT, which is what
 * retracts an ask, and the dialog gets its AbortSignal). You are never sent to
 * the other place: if you are already in the pane, answer there; if you are not,
 * the fin is waiting. Neither is a fallback for the other — the fallbacks are
 * for a machine with no trill (pane only) and a `pi -p` with no UI (banner
 * only).
 *
 * ── what a refusal may not say ──────────────────────────────────────────────
 * A blocked call's `reason` is read by the MODEL, not by a human — pi hands it
 * straight back as the tool result. So it may not name the escape hatch, and
 * the first draft of this file did: "…or re-run with HAUS_DESKTOP_OK=1 if this
 * is an unattended run". The very first end-to-end run answered the question
 * with a block and pi's next move, five seconds later, was to re-issue the
 * command as `HAUS_DESKTOP_OK=1 bash -c '<the same command>'`. It was doing as
 * it was told.
 *
 * That is the difference between a verdict a person reads and one the model
 * does: a guard that can only say "ask" is talking to a person, and a guard
 * that can BLOCK is talking to something that will read the refusal as a
 * puzzle. So the reason carries the why and one instruction — stop, hand it
 * back — and the env var lives in this header, where a human reads it. The
 * Claude side's `agent-desktop-ask` denies with the same wording, under the
 * same rule.
 *
 * The wrapper in that rewrite is worth knowing about on its own: the shared
 * ruleset anchors its patterns per segment (`^ *open …`), so `bash -c 'open …'`
 * is not matched. That is a property of the ruleset, true on the Claude side
 * too, and a backstop for accidents was never a jail — but the message above is
 * what keeps an accident from being turned into an evasion on purpose.
 *
 * ── the one case that refuses ───────────────────────────────────────────────
 * Nothing here is a blocklist: every verdict is a question, and every question
 * has an Allow on it. The single exception is having nowhere to ask — a
 * non-interactive `pi -p` on a machine where trill is unreachable — where the
 * call is blocked with the reason. Silence is not consent, which is trill's own
 * rule for an unanswered ask, and the direction of the failure matches what
 * this guard exists to prevent. It costs one env var to opt out of, which is
 * the same escape hatch as ever:
 *
 *   HAUS_DESKTOP_OK=1     turns the guard off for this pane, both clients
 *   HAUS_PI_ASK_TIMEOUT   seconds before an unanswered question gives up
 *                         (unset = wait as long as you do, which is the default
 *                         and what a permission prompt should do)
 *
 * Fire-and-forget everywhere else: a missing binary, a machine with no trill, a
 * malformed verdict — none of them may surface as a broken turn. Every failure
 * that is not "nowhere to ask" resolves to no opinion, and the tool runs.
 */

import { spawn } from "node:child_process";
import type { ChildProcess } from "node:child_process";

const DESKTOP_GUARD = "@DESKTOP_GUARD@";
const TRILL = "@TRILL@";

// One fin per pane, never a stack. Re-asking with the same --key REPLACES the
// parked question, and pi preflights sibling tool calls sequentially while this
// handler awaits, so a pane can only ever have one question outstanding. The
// pid is exactly pane-lived, for the reason agent-state.ts gives about pi's own
// session id: /new, /resume and a fork each mint a new one, and a fin raised
// under the old id could then never be replaced.
const ASK_KEY = `haus-pi-desktop-${process.pid}`;

// Unset means wait forever, which is what a permission prompt is for. A number
// is for an unattended run that would rather lose the tool call than the night.
//
// It has to reach BOTH doors or it reaches neither: a lane is `mode: "tui"`, so
// `hasUI` is true, so the pane dialog is always in the race — and a clock that
// only stopped the banner would leave the handler waiting on a dialog nobody is
// sitting at, in exactly the unattended case the variable exists for.
const ASK_SECONDS = (() => {
	const raw = process.env.HAUS_PI_ASK_TIMEOUT;
	if (raw === undefined || raw.trim().length === 0) return undefined;
	const n = Number(raw);
	return Number.isFinite(n) && n > 0 ? Math.round(n) : undefined;
})();

// How long the guard itself may take before it is treated as having no opinion.
// Not configurable: the shell guard is a pure function measured in tens of
// milliseconds, and this is only here so a wedged one cannot hold a turn open
// with nothing on screen to explain why.
const GUARD_DEADLINE_MS = 5000;

// A banner is a card, not a terminal. The command goes in the title so you can
// tell two asks apart at a glance; the guard's reason (a paragraph, with
// backticks) goes in the body, where there is room for it.
const clip = (s: string, n: number): string => {
	const flat = s.replace(/\s+/g, " ").trim();
	return flat.length > n ? `${flat.slice(0, n - 1)}…` : flat;
};

export default function (pi: any) {
	// The pane's own directory, for the subtitle. `scruff hook notify` does a
	// better lookup than this from cwd, but nothing about an ask goes through
	// scruff — this is the whole of what names the lane on the card.
	let cwd = process.cwd();

	pi.on("session_start", (_event: any, ctx: any) => {
		cwd = ctx?.cwd ?? cwd;
	});

	const where = (): string => {
		const base = cwd.split("/").filter(Boolean).pop();
		return base && base.length > 0 ? base : "pi";
	};

	// Ask the shared guard. Resolves to the reason the user should read, or ""
	// for "no opinion" — which is also every failure path, because a guard that
	// cannot run must not be able to stop a turn.
	const verdict = (command: string): Promise<string> =>
		new Promise((resolve) => {
			let out = "";
			let child: ChildProcess;
			let done = false;
			const settle = (v: string) => {
				if (done) return;
				done = true;
				clearTimeout(timer);
				resolve(v);
			};
			try {
				child = spawn(DESKTOP_GUARD, [], { cwd, stdio: ["pipe", "pipe", "ignore"] });
			} catch {
				resolve("");
				return;
			}
			// A guard that never exits would hold the turn with nothing on screen
			// and nothing to Ctrl-C out of — the abort listener is not registered
			// until this promise settles. Fail open, like every other guard
			// failure: a check that cannot answer must not be able to stop a turn.
			const timer = setTimeout(() => {
				try {
					child.kill("SIGKILL");
				} catch {
					/* already gone */
				}
				settle("");
			}, GUARD_DEADLINE_MS);
			// An unhandled `error` on a ChildProcess is a thrown exception out of
			// the event loop — pi's whole process, killed by a permission check.
			// The listener is the only thing that can see it; the try/catch cannot.
			child.on("error", () => settle(""));
			child.stdin?.on("error", () => settle(""));
			child.stdout?.on("data", (chunk) => {
				out += String(chunk);
			});
			child.on("close", () => {
				try {
					const parsed = JSON.parse(out);
					const v = parsed?.hookSpecificOutput;
					if (v?.permissionDecision !== "ask") return settle("");
					settle(String(v?.permissionDecisionReason ?? "This touches the user's screen."));
				} catch {
					settle("");
				}
			});
			child.stdin?.end(
				JSON.stringify({ tool_name: "Bash", tool_input: { command } }),
			);
		});

	// The banner half. `undefined` means "no answer from here" — no trill on the
	// machine, the daemon unreachable or refusing, the question timed out, or we
	// killed it because the pane answered first.
	const askTrill = (
		command: string,
		reason: string,
		cancel: AbortSignal,
	): Promise<boolean | undefined> =>
		new Promise((resolve) => {
			const argv = [
				"ask",
				clip(`Run ${command}?`, 90),
				"--pill", "Allow",
				"--pill", "Deny",
				// The card is the consent surface, so the command goes on it in
				// full-ish rather than only in the title, which the 90-char clip
				// can cut mid-argument. Approving what you cannot see is the one
				// thing a permission banner may not ask of anyone.
				"--body", `${clip(command, 220)}\n\n${clip(reason, 200)}`,
				"--subtitle", where(),
				"--source", "haus.ai.pi.desktop",
				"--symbol", "hand.raised",
				"--key", ASK_KEY,
			];
			if (ASK_SECONDS !== undefined) argv.push("--timeout", String(ASK_SECONDS));

			let child: ChildProcess;
			try {
				child = spawn(TRILL, argv, { cwd, stdio: "ignore" });
			} catch {
				resolve(undefined);
				return;
			}
			child.on("error", () => resolve(undefined));
			// SIGINT is what retracts an ask — `trill help` names Ctrl-C at the
			// terminal as the way a question comes down when nobody is behind it
			// any more. Which is exactly the case here: the pane answered.
			cancel.addEventListener("abort", () => {
				try {
					child.kill("SIGINT");
				} catch {
					/* already gone */
				}
			});
			child.on("close", (code, signal) => {
				if (signal !== null) return resolve(undefined); // we took it down
				if (code === 0) return resolve(true); // first --pill: Allow
				if (code === 1) return resolve(false); // second --pill: Deny
				// 64 usage · 69 daemon unreachable · 70 refused · 75 nobody answered
				resolve(undefined);
			});
		});

	// The pane half. Same three-valued answer, same meaning.
	const askPane = (
		command: string,
		reason: string,
		ctx: any,
		cancel: AbortSignal,
	): Promise<boolean | undefined> => {
		try {
			return Promise.resolve(
				ctx.ui.select(`${reason}\n\n  ${clip(command, 160)}`, ["Allow", "Deny"], {
					signal: cancel,
					...(ASK_SECONDS === undefined ? {} : { timeout: ASK_SECONDS * 1000 }),
				}),
			)
				.then((choice: string | undefined) =>
					choice === "Allow" ? true : choice === "Deny" ? false : undefined,
				)
				.catch(() => undefined);
		} catch {
			return Promise.resolve(undefined);
		}
	};

	pi.on("tool_call", async (event: any, ctx: any) => {
		// The whole-guard escape hatch, read per call rather than once at load:
		// same variable, same meaning, same spelling as the Claude Code side.
		if (process.env.HAUS_DESKTOP_OK) return undefined;
		if (event?.toolName !== "bash") return undefined;
		const command = event?.input?.command;
		if (typeof command !== "string" || command.length === 0) return undefined;

		const reason = await verdict(command);
		if (reason.length === 0) return undefined;

		const cancel = new AbortController();
		// The turn being aborted (Ctrl-C in the pane) has to take the banner down
		// too, or a fin outlives the question it was asking about.
		const onTurnAbort = () => cancel.abort();
		ctx?.signal?.addEventListener?.("abort", onTurnAbort);

		const banner = askTrill(command, reason, cancel.signal);
		const pane = ctx?.hasUI ? askPane(command, reason, ctx, cancel.signal) : undefined;

		// First DEFINITE answer wins. A plain Promise.race would be wrong: a
		// machine with no trill resolves `undefined` immediately and would win
		// the race against a dialog nobody has looked at yet. So each side only
		// settles the race when it actually decided, and the both-gave-up case is
		// a third promise that waits for both.
		const first = (p: Promise<boolean | undefined>): Promise<boolean> =>
			new Promise((res) => {
				p.then((v) => {
					if (v !== undefined) res(v);
				});
			});
		const racers: Promise<boolean | undefined>[] = [first(banner)];
		if (pane !== undefined) racers.push(first(pane));
		racers.push(
			Promise.all(pane === undefined ? [banner] : [banner, pane]).then(() => undefined),
		);

		let answer: boolean | undefined;
		try {
			answer = await Promise.race(racers);
		} catch {
			answer = undefined;
		} finally {
			cancel.abort(); // take down whichever door nobody used
			ctx?.signal?.removeEventListener?.("abort", onTurnAbort);
		}

		if (answer === true) return undefined;
		// Both refusals read the same to the model, and NEITHER names the escape
		// hatch — see "what a refusal may not say" in the header. What it gets is
		// the reason and one instruction: stop, and hand the step back.
		const denied = answer === false;
		const refusal =
			`${reason}\n\n` +
			(denied ? "The user said no." : "Nobody answered.") +
			" Do not retry this, and do not reach the same effect another way." +
			" Hand this step back to the user and carry on with the rest of the task.";
		// `terminate` only where nobody is there. A person who pressed Deny is at
		// the machine and may well want the rest of the turn to carry on without
		// this one step — that is what the refusal asks for. Nobody answering is
		// the other case entirely: left running, the model retries, and every
		// retry raises the same question at a screen nobody is in front of.
		return { block: true, reason: refusal, ...(denied ? {} : { terminate: true }) };
	});
}
