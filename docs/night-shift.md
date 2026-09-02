# What haus gives an unattended merge shift

**Four levers, and they are the whole of haus's side.** The tool that merges is
[hausfold/factory](https://github.com/hausfold/factory) — a flake input this
layer ships on `PATH` with `haus.ai.enable`, along with its two agent skills
(`factory` and `nightshift`). Its README is the manual for the shift itself: the
verbs, tier 1 and the floor under it, the budget governor, the watchdog. This
page is only what a shift reaches for **here**, in the four places it touches
haus rather than the forge.

Nothing on this page is a `haus.*` option factory knows about. The tool is
repo-agnostic and deliberately names none of this; the wiring is the layer's, so
the layer is where it is written down.

## 1. The lid — `haus.power.lidAwake`

macOS sleeps on lid-close whatever `caffeinate` says, so a shift on a closed lid
needs `pmset -a disablesleep 1` held for its duration. That lever is the power
room's:

```nix
haus.power.lidAwake = {
  enable = true;
  while  = "always";
};
```

`enable` is off by default because closing the lid is the one gesture everybody
reads as "stop", so a host that wants a shift has to say so.

**`haus.ai.keepAwake` is not this lever, and reaching for it is the mistake to
avoid.** It is the AI room's profile and means *while my agents work* at every
one of its stops — `lid` included, which switches `haus.power.lidAwake.enable`
on at `mkDefault` but still rides the agents signal rather than becoming an
unconditional hold. That signal lingers five minutes past the last turn, and a
foreman loop wakes on a cadence measured in tens of minutes, so it drops in
every gap. `while = "always"` has to be named directly, in the host's power
block.

The two neighbours stay at their defaults on purpose. `requirePower` keeps
unplugging as the way to say stop. `maxHold` does not apply: its 8-hour cap is a
failsafe for an *agent* hold that leaked, and `always` has no signal to leak, so
a twelve-hour shift is not cut off at hour eight.

## 2. The fixer lane — `haus-fix-github`

A red default branch that is worth a machine gets one, and the binary already
exists: `haus-fix-github` is what the bar's GitHub pill runs behind *Fix with
AI*. A shift's `CI-RED <repo> <url>` line is its argv already filled in — the
verdict is `ci`, the selector is the default branch, the URL is the failed run:

```sh
haus-fix-github main ci "$url"
```

Calling it rather than improvising a spawn is the point. Resolving the local
checkout, picking a client, taking the double-click lock and cleaning up a lane
the open seam refused are all this binary's, and none of them is worth
re-deriving in prose at 3 a.m.

**The spawn is a background one, and that is not a nicety.** The machine is
somebody's desk whether or not they are asleep at it, so the lane must not raise
a window or take focus — `HAUS_LANE_BACKGROUND=1` is what the binary already
sets. The receipt is a banner under `--source haus.github.fix` and the lane's
row in the agents pill.

**It can build; it cannot activate.** The repo's own tests run in the lane's
checkout and `bench try` builds against its branch, but `bench try switch` is
refused to an agent in a worktree unless it is told `BENCH_AGENT_SWITCH=1`,
which a shift never sets — activation is machine-wide and serial. A red `main`
that only reproduces on activation is diagnosed and proposed overnight, never
confirmed; the confirmation is the morning's.

**A repo with no local checkout gets a banner and no lane**, which is the whole
of what a shift can do about a red branch it cannot reach. The walk starts from
the repo's basename across `haus.ai.repoRoots` and scruff's registry, so a
checkout cloned under another name is the same ending as no checkout at all.

**Three of the endings that produce no lane leave nothing behind but the
banner** — nothing in `haus.ai.clients` on `PATH`, no local checkout, and a lane
already running under the lock. Only spawn *failures* reach
`~/.local/state/haus/github-fix.log`. The binary forks its work and exits 0
before any of it happens, so no caller learns the outcome from a status.

## 3. The budget feed — `usage-claude.tsv`

factory's metered budget gate reads a TSV, and on this machine that file is
haus's: `~/.cache/claude-statusline/usage-claude.tsv`. Nothing in factory writes
it.

`modules/ai/statusline.sh` stashes the account's 5-hour and weekly percentages
on every Claude Code statusline render — the client hands both to each render,
so the primary source is also the cheapest there is: no keychain read, no API
call. `modules/ai/statusline-refresh.sh` fills the hole under it, polling
`api.anthropic.com/api/oauth/usage` on a 120-second TTL, kicked by the bar's own
pill rather than by a session.

**Nine columns are written and the first four are what a budget reader wants:**

| | |
|---|---|
| 1–2 | 5-hour and weekly used-percentage, integers, truncated rather than rounded |
| 3–4 | the 5-hour and weekly reset stamps |
| 5–9 | written, provider, model, provider id, last burned — the bar's `aiUsage` pill reads all nine |

A reader taking the first four positionally is leaning on the safe half: the
columns that could go empty are 7 and 8, which are filled with a literal
`claude` and `anthropic` for the pill's sake, and the first four default to `0`
on both writers and are never blank. **What nothing on either side checks is the
ORDER** — two percentages that swapped places are both integers under 100, and
each side would keep reading the other happily.

**The `-claude` in that path is load-bearing.** The two sibling feeds beside it
are not interchangeable: `usage-codex.tsv` carries a weekly reset a fortnight
out and `usage-opencode.tsv` reports a fractional percentage, and a gate whose
arithmetic is written for Anthropic's two windows answers `budget unknown`
forever against either.

**The hole under all of it is that a statusline is a TUI feature.** The Claude
Code macOS app renders none and pushes nothing, and what gates the refresher's
poll is not its caller but its bearer — the `Claude Code-credentials` keychain
item, which the macOS app never writes and a terminal `claude` renews in place
whenever a pane runs. **Drive a foreman from a terminal pane, not the desktop
app**, or it spends against percentages from whenever one last was.

A feed that stops does not mis-spend for long; it stops the gate. The 5-hour
reset stamp is bounded to the window it names, so a row can be at most five
hours stale before a metered reader gives up on it.

## 4. What a night puts on screen

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
