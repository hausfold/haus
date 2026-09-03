# The night shift's haus-side internals

**The operator guide moved.** What a person *sets and runs* to leave a merge
shift going overnight — `haus.power.lidAwake.while = "always"`, the
`haus-fix-github` call, and the two warnings that come with them — is
[hausfold.co/docs/haus/night-shift](https://hausfold.co/docs/haus/night-shift),
where haus's user-facing behaviour belongs. This file is the half that stayed:
the seams a shift leans on here, each of them a live way to break a night
silently and none of them visible from the shift's own side.

The tool that merges is [hausfold/factory](https://github.com/hausfold/factory)
— a flake input this layer ships on `PATH` with `haus.ai.enable`, along with its
two agent skills (`factory` and `nightshift`). Its README is the manual for the
shift itself: the verbs, tier 1 and the floor under it, the budget governor, the
watchdog. Nothing below is a `haus.*` option factory knows about. The tool is
repo-agnostic and deliberately names none of this; the wiring is the layer's, so
the layer is where it is written down.

## Why the `always` lid hold draws nothing

A machine holding the lid open through the power room alone has **nothing on
screen saying so**, and that is structural rather than an oversight. The bar's
coffee pill reads the AI room's user-agent hold file; the power room's root
daemon over `disablesleep` never writes one — that is the power room's shape and
it has never had a pill. So the `always` hold is invisible, which is the exact
failure `modules/core/lidawake.sh`'s own header names: a Mac that never sleeps
again with nothing to say why.

The consequence (your shift's banners stop, the hold does not) is on the site,
because it is a warning a person acts on. The mechanism is here, because a
reader who is not editing the bar or the power room can do nothing with it. If
either half moves, move both.

What `requirePower`, `maxHold` and `linger` each do under `always` is the
site's, because it is what a person picks. The fact under all three is here:
`always` has no agent signal, so two of the dials have nothing to act on. Change
a default and the page needs the edit, not this file.

## `haus-fix-github`'s endings that produce no lane

The contract and the no-local-checkout ending are on the site: that is what a
person types. What is here is the observability, which is a *caller's* problem
rather than an operator's.

Two strings the site deliberately does not carry, because only a caller needs
them. **`HAUS_LANE_BACKGROUND=1`** is what makes the spawn silent, and the
binary already sets it — anything else that spawns a lane on a sleeping desk
sets it itself, and `modules/launcher/commands/spawn-agent.sh` is the other
caller to copy. **`CI-RED <repo> <url>`** is factory's own cue for a red default
branch (`ai/nightshift/SKILL.md`), and it is *most* of the argv: the URL is the
run, the verdict is `ci` because that is the only failure this line reports, and
the selector is the one field the line does NOT carry — the caller has to know
that repo's default branch name. That is the whole join between factory's output
and this binary, it exists in neither repo's code, and it is why the two names
are written down together here.

**Three of the endings that produce no lane leave nothing behind but the
banner** — nothing in `haus.ai.clients` on `PATH`, no local checkout, and a lane
already running under the lock. A fourth leaves nothing at all: where the binary
was never installed, the caller gets `command not found`, and neither the screen
nor `~/.local/state/haus/github-fix.log` records that a lane was wanted.
**Whatever asks for a lane has to log the asking itself.**

`~/.local/state/haus/github-fix.log` takes the spawn's stderr unconditionally,
so a successful spawn can write there too; a failure is only the case that
reliably does. Bad argv (exit 64) and a URL that is not github.com's (a banner,
exit 2) are both decided before the fork and *are* visible in the status —
everything after that point is forked and exits 0, so the resolve and the spawn
are the unobservable half.

**A lane spawned with the screen asleep gets no window, and that is the fix
rather than the fault.** The fault was the other way round: Ghostty cannot build
a terminal surface while macOS reports zero active displays, so a background
lane born at 3 a.m. came up as a "failed to initialize" pane. Because
`modules/terminal/lanes/lane-open.sh` *is* the lane's `--initial-command`,
nothing below the spawn ran — no zmx session, no client, no banner — while
`scruff spawn` exited 0 and every caller reported a lane that was working. That
script now asks `hausdisp` first and, with no display, starts the client
detached in its zmx session instead. The window comes later, from `scruff
<name>` or from clicking the spawn banner — **not from ⌃⇥**, which walks
non-empty `T/*` pages and so cannot see a lane that never tiled. **A shift on a
sleeping desk therefore has lanes with no windows, and the zmx session rather
than the tiler is what says a fixer lane exists.** The window path keeps a
bounded watch of its own: a spawn whose session never appears within ten seconds
draws a `haus.lane` fault, naming the launcher file the prompt is still in when
that spawn is the one that never got a surface.

**"It can build; it cannot activate" is `bench`'s doing, not this binary's**,
which is why only the consequence is on the site. `bench try` builds against the
lane's branch; `bench try switch` is refused to an agent in a worktree unless it
is told `BENCH_AGENT_SWITCH=1`, which a shift never sets, because activation is
machine-wide and serial. Nothing in `haus-fix-github` enforces it.

## The budget feed — `usage-claude.tsv`

factory's metered budget gate reads a TSV, and on this machine that file is
haus's: `~/.cache/claude-statusline/usage-claude.tsv`. Nothing in factory writes
it.

`modules/ai/statusline.sh` stashes the account's 5-hour and weekly percentages
on every Claude Code statusline render — the client hands both to each render,
so the primary source is also the cheapest there is: no keychain read, no API
call. `modules/ai/statusline-refresh.sh` fills the hole under it, polling
`api.anthropic.com/api/oauth/usage` on a 120-second TTL. A stale feed kicks it
from a render, and the bar's own pill kicks it as well — the second path is what
covers a machine with no Claude statusline running at all.

**Nine columns are written and the first four are what a budget reader wants:**

| | |
|---|---|
| 1–2 | 5-hour and weekly used-percentage, integers, truncated rather than rounded |
| 3–4 | the 5-hour and weekly reset stamps |
| 5–9 | written, provider, model, provider id, last burned — the bar's `aiUsage` pill reads all nine |

A reader taking the first four positionally is leaning on the safe half: the
columns that could go empty are 7 and 8, which are filled with a literal
`claude` and `anthropic` for the pill's sake, and the first four default to `0`
on both writers and are never blank. **What nothing checks at RUNTIME is the
ORDER** — two percentages that swapped places are both integers under 100, and
either side would keep reading the other happily. What holds the contract is a
test rather than a guard: `test/statusline-refresh.bats` pins the positions with
distinct values, so a swap fails haus's suite here. There is nothing equivalent
on a reader's side, which is why the test is worth knowing about before moving a
column.

**The `-claude` in that path is load-bearing, and `usage-opencode.tsv` is the
reason to say so out loud.** The three feeds share a column count and not a
meaning. Claude's and Codex's are *subscription* rows — percentages and reset
stamps. **Opencode's is a cost row**: columns 1 and 2 are today's and
month-to-date API spend **in dollars**, and columns 3 and 4 are literal `0`
rather than reset stamps. `ai_usage.sh`'s header carries both shapes side by
side and is the contract.

A reader that assumes percentages gets a dollar figure in the slot where a
percentage goes, and a small bill reads as a nearly-empty quota. Codex's row is
percentages, but its two windows are whatever OpenAI reports, classified only as
under or over a day — nothing promises the second is the seven days a weekly
bound expects. **A budget gate written for Anthropic's two windows may only read
the Claude feed**, and the constraint and the right choice coincide here, since
a fixer lane on this machine is a Claude Code lane.

**The hole under all of it is that a statusline is a TUI feature.** The Claude
Code macOS app renders none and pushes nothing, and what gates the refresher's
poll is not its caller but its bearer — the `Claude Code-credentials` keychain
item, which the macOS app never writes and a terminal `claude` renews in place
whenever a pane runs. Hence the site's "start it from a terminal" warning; this
is the reason under it.

A feed that stops does not mis-spend for long; it stops the gate. The 5-hour
reset stamp is bounded to the window it names, so a row can be at most five
hours stale before a metered reader gives up on it.

## What a night puts on screen

Four `--source` strings, and only the first is the shift's own. Nothing routes
any of them until `~/.config/trill/rules.json` names one, because no match means
banner. trill matches `source` exactly, so a rule on `haus` does not reach
`haus.lane` or `haus.github.fix` — the dotted name is a convention this family
writes, not a namespace trill walks.

| source | whose | what a rule on it costs |
|---|---|---|
| `factory` | the shift's own cards — five faults and one `done` count of what a pass merged | nothing the shift log does not already hold. `drop` loses the interruption and keeps the record; the card worth splitting off first is the `done`, matched on `kind` ahead of a broader rule, so the merges tally into a digest and the faults still bang on the door |
| `haus.github.fix` | the fixer lane's | more than a night. The same binary is behind the pill's *Fix with AI*, so a rule covers a click at the keyboard too — and for the three endings above the banner is the entire record, so `inbox` or a digest keeps them findable where `drop` does not |
| `haus.lane` | how a lane that could not be tiled says so, including the silent birth a background spawn uses | every lane on this machine, the ones spawned at the keyboard included |
| `claude` | scruff's per-lane fin — an `ask` when a lane blocks, a `done` when it finishes a turn | the same: quieting a loud night through it is quieting the lanes themselves |

`bench` is the reasonable guess that is wrong. A shift's after-merge hook runs
`bench pull` and `bench ship`; bench cards only from `try` and `rebuild` and
notifies only from `try-batch` and `release`, none of which a pass runs.
