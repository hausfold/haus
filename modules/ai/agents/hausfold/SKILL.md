---
name: hausfold
description: Send a bug report, an idea, or a fix upstream to hausfold — who make haus, Pounce, Perch, trill, scruff, snug and nebelung, the tools running on this Mac. Use whenever the user complains about one of them or wishes it worked differently ("this is annoying", "why does it keep doing that", "that's broken", "I wish it would…", "it should just…", "report this", "file an issue", "tell them about it"), and when they want to fix one themselves. None of these tools has any telemetry, so a GitHub issue is the only way the people who made them ever find out.
---

# Telling hausfold

The hausfold tools on this Mac — **haus** (the desktop itself), **Pounce** (the
⌘Space palette), **Perch** (the notch shelf), **trill** (notifications),
**scruff** (agent worktrees), **snug**, **nebelung** — send **no telemetry,
ever**. Nothing phones home about a crash, a hang or a rough edge. A GitHub
issue is the entire channel.

So a complaint the user makes to you is worth far more upstream than in this
scrollback. Offer to carry it. The report stays theirs — their words, their
account, their explicit yes — and you do the tedious half.

## Offer when

- One of those tools did something wrong, surprising or annoying.
- The user wishes it did something it doesn't, or hand-rolls a workaround.
- They say "that's a bug", "that's broken", "why does it even do that".

**Offer once, in one line, then let it go.** *"Want me to file that with
hausfold?"* If they say no or talk past it, drop it and don't ask again this
session. An agent that nags about feedback becomes the next thing worth
reporting.

**Don't offer** for their own configuration — a wrong `haus.*` value is not a
haus bug, and that is the `haus` skill's job — for a third-party app, or for
anything you have not actually seen happen.

## Which repo, and what fills the diagnostics in

Every repo is under `github.com/hausfold`. The verb runs a read-only health
check and opens that repo's bug form with the diagnostics field already filled;
`--print` gives you the block and the link and opens nothing.

| what they're talking about | repo | diagnostics |
|---|---|---|
| the desktop: rebuild, update, rollback, tiling and keybinds, the menu bar, the shell, macOS settings, installing | `haus` | `haus report --print` |
| the ⌘Space palette: the hotkey, results, a command, the daemon | `pounce` | `pounce report --print` |
| the notch shelf: dragging in or out, staging, the iPhone link | `perch` | `perch doctor` — its **first two lines only** |
| notification banners: quiet hours, rules, doubled banners | `trill` | `trill report --print` |
| agent worktrees and lanes | `scruff` | `scruff doctor` |
| how one of our CLIs draws — colours, glyphs, a column that wrapped | `snug` | `snug caps` |
| the colours themselves | `nebelung` | *(none — the form has no such field)* |
| hausfold.co, the docs, the install one-liner | `hausfold.co` | *(none)* |

**Wrong repo? File it anyway.** Every bug form opens by saying so, and it is
meant: routing is theirs and it costs one click. Guessing is the reporter's and
it costs the report. Pick the closest one and move on.

## Bug or idea

Two forms, and the split is what the user is telling you:

- **Bug** — it does something wrong. `template=bug.yml`. Fields: *What
  happened?* (what you did, expected, got instead), *Where in \<tool\>?*,
  diagnostics, *Anything else*.
- **Idea** — it should do something it doesn't. `template=idea.yml`. Two
  fields: *What would you want to do?*, and *What do you do today instead?* —
  the second one decides it, so never leave it out.

## Filing it

1. **Check it isn't already there.**
   `gh issue list --repo hausfold/<repo> --search "<keywords>" --state all -L 5`
   If it is, show the user the link and offer to add their case as a comment.
2. **Draft it in their words**, not a tidied paraphrase. "It said something
   about a lock file" is worth more raw than polished into something they never
   said. Run the diagnostics verb above and read its output before it goes
   anywhere.
3. **Show them the draft and wait for a yes.** Every word of it — the
   diagnostics block included. Nothing is filed on an assumed yes.
4. **File it** — `gh` walks past the form entirely, so the form's shape is
   yours to reproduce, and it is not the same shape for both:

   | | `--label` | headings in the body |
   |---|---|---|
   | bug | `bug,triage` | `## What happened?` · `## Where` · `## Diagnostics`, fenced · `## Anything else` |
   | idea | `idea,triage` | `## What would you want to do?` · `## What do you do today instead?` |

   ```sh
   gh issue create --repo hausfold/<repo> --label <that row's labels> \
     --title "<one line: the symptom, or the wish>" --body-file <draft>
   ```

   A label an account has no rights to set is dropped, and `gh` may refuse the
   flag outright. If it does, drop `--label` and file it anyway: an unlabelled
   report beats an unsent one.

   **No `gh`, or it isn't signed in?** Run the verb without `--print` — it opens
   that repo's form in the browser with the diagnostics already in it — and
   print your drafted text for them to paste into *What happened?*. Nothing is
   sent until they press Submit. For an idea, the form is
   `https://github.com/hausfold/<repo>/issues/new?template=idea.yml`.

5. **Report the URL** the issue landed at. That is their receipt.

## If they'd rather fix it

They may well be a developer — many of these machines are. A pull request beats
an issue when the fix is small and they can say how they tested it.

```sh
gh repo fork hausfold/<repo> --clone --remote   # nobody outside has push access
cd <repo> && git switch -c <topic>
```

- **Read that repo's `AGENTS.md` first.** Every hausfold repo carries one, and
  it is the house rules for exactly this: where a change belongs, what it must
  not touch, how it is verified.
- **File the issue first anyway** when the diagnosis is worth having on its own,
  and link it. A rejected PR with a good issue under it still lands the report.
- `gh pr create --repo hausfold/<repo>` with a body of four blocks — **What /
  Why / Verify / Watch out**. That is the family's own PR shape; *Verify* is the
  one that gets it read.
- Say how you tested it, and if you couldn't, say **that** instead of implying
  you did.

## Traps

- **Never file, comment or open a PR without an explicit yes**, and never a
  second time for the same thing. A public issue is not undoable by an agent.
- **It lands in public.** The `--print` blocks are already safe — haus rewrites
  the home directory to `~`, perch's first two lines carry no paths — but
  anything *you* add is not. No file contents off their shelf, no window
  titles, no tokens, no client names. Read the block before you attach it.
- **`perch doctor` is a slice, not a paste.** Its first two lines carry the
  version, install cohort, macOS build and Mac model; the rows under them name
  folders on their own Mac. Leave those out unless one of them is the bug.
- **Don't invent a repo, a form field or a `report` verb.** The table above is
  the whole list — Perch's door is its menu bar's *Report a Bug…*, not a CLI
  verb.
- **A crash with no reproduction is still worth filing.** "It just stopped
  drawing, twice, both times after waking" is a report. Waiting for a clean
  repro is how it never gets sent.
