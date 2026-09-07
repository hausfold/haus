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
agent skill (`factory`). Its README is the manual for the shift itself: the
verbs, tier 1 and the floor under it, the budget governor, the runner. Nothing
below is a `haus.*` option factory knows about. The tool is repo-agnostic and
deliberately names none of this; the wiring is the layer's, so the layer is
where it is written down.

## launchd owns the runner, and `ThrottleInterval` is why it can

`factory watchdog run` is the loop. `haus.ai.factory.enable` — on by default
with the AI room — is the per-user launchd agent `com.hausfold.factory` that
keeps one alive, and it is a switch about SUPERVISION rather than about
authority: the lease and `~/.config/factory/config.json` decide what merges,
this decides only what happens when the process reading them dies.

There used to be a second process here. The runner's four fixer gates were a
skill an agent session re-read on every wakeup, that session was the foreman,
and factory's watchdog measured whether the foreman was still alive. The gates
turned out to be four string checks and a retry counter, so they are code now,
and the only supervision left is restarting something that died. **`KeepAlive`
is that supervisor**, which is what the alternative — a second haus-side
process watching the first — would have had to reinvent worse.

**The measured fact under the plist is that `run` exits.** With no live lease
it returns 0 in about 0.2 seconds, and that is the state of a machine almost
all of the time. `KeepAlive = true` at launchd's default ten-second throttle
would make that roughly 8,600 spawns a day for nothing, so the agent sets
`ThrottleInterval = 300`, which is 288 a day.

**That costs the crash case nothing, because launchd measures the throttle from
the last SPAWN rather than from the exit.** Measured with a probe job at
`ThrottleInterval = 20`: killed eight seconds after it started, launchd waited
out the remaining twelve; killed after thirty seconds alive, it was back in
under a second. A runner passing under a live lease has been up for at least one
`runner.interval` before anything can kill it, so the kill this agent exists for
is an immediate restart whatever the throttle says. And in the worst case the
window is still four times inside `runner.interval` (1200s) and nine times
inside `watchdog.stale` (2700s), so a restarted runner is passing again long
before factory would call the gap a stall.

**`SuccessfulExit = false` is the wrong shape here and looks like the right
one.** It costs nothing when idle, which is its whole appeal — and it leaves
the job DOWN after every lease-less exit, so a `factory lease grant` typed in
another pane or over ssh is supervised by nothing at all. The runner that grant
spawns is a detached child of your shell; the reboot, panic or OOM kill that
takes it is exactly the case this agent exists for.

**The services deck stays honest because of a launchd state, not because of the
entry.** `KeepAlive = true` puts this job in core's `running` liveness class,
and `haus doctor` calls a `running` job that is not live *wedged* — which on a
machine with no lease would be a permanent red line for the majority state, the
exact false red the deck exists to delete. It is not, because a `KeepAlive` job
waiting out its throttle prints `state = spawn scheduled` and never `not
running`, and `_svc_probe` reads only `not running` as stopped
(`modules/core/haus.sh`, whose own comment names this case). Sampled every
thirty seconds across a full 300-second window on a probe job: `spawn scheduled`
throughout, `runs` ticking at the boundary. Doctor reads `ok`, and
`_perm_agent_wedged` puts up no login-items card. Change `ThrottleInterval`
here or that state test there and the pair has to be re-checked.

Two runners can never both pass, and that is factory's invariant rather than
this file's: `run` claims `watchdog.pid`, and a second one prints `already
running` and exits 0. So launchd's copy and `lease grant`'s coexist safely, and
whichever claimed first is the one doing the work.

**It is an agent, not a daemon, because it merges as YOU.** `gh`'s credentials,
the lease and the shift log all live in your login session and root has none of
them. Its `PATH` is written out in `modules/ai/default.nix` for the reason every
launchd `PATH` in this repo is: an agent inherits `/usr/bin:/bin:/usr/sbin:/sbin`
and this one shells out past factory's own wrapper twice — to `fixer.command`
in the system profile, and to whatever after-merge hooks the policy names, which
on this family's machines are `bench pull` and `bench ship` out of the user
profile.

The launchd log (`/tmp/haus-factory.{out,err}.log`) is the crash channel only.
What a person reads in the morning is factory's own `~/.cache/factory/shift-*.log`.

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

Two things the site deliberately does not carry, because only a caller needs
them. **`HAUS_LANE_BACKGROUND=1`** is what makes the spawn silent, and the
binary already sets it — anything else that spawns a lane on a sleeping desk
sets it itself, and `modules/launcher/commands/spawn-agent.sh` is the other
caller to copy. The second is the **argv**, and it is the reason `fixer.command`
cannot name this binary. factory's runner appends `<repo> <default branch> <run
url>` to whatever that key holds; `haus-fix-github` takes `<selector> <verdict>
<url>`. Three words meet three words in a different order, and `ci` — the
verdict, because a red default branch is the only failure a fixer lane is
handed — is carried by neither side.

So the layer ships the shim rather than describing it: **`haus-factory-fixer`**,
on PATH beside `haus-fix-github` and gated the same way, drops the repo word,
puts the branch in the selector and writes the verdict in. What a policy names
is the whole of it:

```json
"fixer": { "command": ["haus-factory-fixer"] }
```

That file is still the person's — `~/.config/factory/config.json` is authority,
and haus writes none of it, which is why `factory doctor`'s `no fixer.command`
line is the thing that reminds you. The shim refuses any argv that is not
exactly three words, at exit 64, because factory turns a non-zero exit into
`fixer-failed` with the stderr quoted and cards it: a `fixer.command` with a
stray flag in it says so on screen instead of opening a lane on a branch nobody
named. `factory doctor` blocks on a `fixer.command` PATH cannot find, so what
goes unchecked is not the program but its ARGV — which is the whole reason the
shim exists as a binary instead of a paragraph.

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
