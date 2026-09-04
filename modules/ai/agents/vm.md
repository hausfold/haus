# Seeing your change without taking the screen

Someone is sitting in front of this Mac. Do not foreground an app, move the
pointer or send a keystroke **here** just to look at your own work. On a machine
that ships `haus.ai.instructions` you already have that rule in your global
instructions, and `agent-desktop-guard` puts the question back in front of a
human when you try — as a permission prompt on Claude Code panes, as a trill
banner with Allow/Deny pills on pi ones — but it holds either way.

Take a **VM** instead, and reach for it *before* handing the feel-test back —
asking the user a question is never what the VM replaces; driving this desktop
is. The VM is a second, disposable macOS you own outright: headless on the host,
so nothing it draws reaches the user's display, and real enough to run `haus
rebuild` and render the actual UI. Drive it as hard as you like. It wants the AI
room on (`haus.ai.enable` — `this-machine.md`'s Rooms table says whether it is
here) and a base image named by `SCRUFF_TART_BASE`; the room brings `tart`
itself.

```sh
scruff runtime up    my-lane --backend tart   # clone, boot headless, wait for ssh
scruff runtime enter my-lane --backend tart   # ssh in
scruff runtime down  my-lane --backend tart   # delete the clone
```

Build an image that has haus *inside* it with `script/build-golden-vm.sh` — it
lives in the <https://github.com/hausfold/haus> repo and is **not** shipped by
the flake, so a machine with no checkout has to fetch it. Cloning a bare
`ghcr.io/cirruslabs/macos-tahoe-base` needs nothing, but a lane that clones one
has no haus in it to test.

## Driving it from the host

Usually easier than sitting inside it:

```sh
guest=$(tart ip scruff-my-lane)
vmssh=(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
"${vmssh[@]}" admin@"$guest" 'haus rebuild'
"${vmssh[@]}" admin@"$guest" '/usr/sbin/screencapture -x /tmp/s.png'   # real pixels
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    admin@"$guest":/tmp/s.png ./shot.png                              # fetch it, then look
haus-vm-shot my-lane                                                  # or those two in one
                                                                      # verb, guest tidied
                                                                      # up after
"${vmssh[@]}" admin@"$guest" '/usr/bin/osascript -e "tell application \"System Events\" to keystroke space using command down"'
```

⚠️ **Those two options are not optional, and a bare `ssh admin@<guest>` is the
trap.** vmnet hands the same `192.168.64.x` addresses out again from one clone
to the next, so an address is a different host with a different key every time.
A first connection either dies on `Host key verification failed` (nothing
answers a host-key prompt in an agent's shell) or writes an entry that turns
every later lane landing on that address into a `REMOTE HOST IDENTIFICATION HAS
CHANGED` refusal — a wedge that outlives the VM that caused it. `scruff runtime
enter` and `haus-vm-shot` already carry them; anything you type yourself has to.

Four things that are easy to get wrong:

- **`screencapture -x` needs no GUI-session juggling.** Call the binary
  directly — `launchctl asuser 501` fails there with `Could not switch to audit
  session`.
- **`osascript` → System Events is the only input path** over SSH: keystrokes,
  clicks, and enumerating the alert windows standing in your way.
- **TCC dialogs fire on first use and do not block.** The grant is written at the
  same instant the modal appears, so the command returns real data while an
  unanswered dialog sits on the guest's desktop. One per (service, client), not
  per call — but they *are* in every screenshot until something dismisses them.
- **Keep it headless.** `tart run` without `--no-graphics` opens the guest's
  window on the user's display — the one command in this whole flow that really
  is screen theft. The adapter behind `scruff runtime up` already passes it.

## Showing it to a human: put the picture in the pull request

A screenshot only you ever looked at is a claim, not evidence. `haus-vm-shot
<lane> [dest.png]` prints one line — the host path of a PNG captured in that
lane's guest — which is exactly the shape `--attach` wants.

⚠️ **Check `gh --version` first.** `--attach` arrived in **gh 2.99.0**; 2.98.0
does not have the flag at all, and the nixpkgs this layer pins may not have
caught up. When it is not there, print the path and let the person attach it —
do not go looking for another way to upload.

```sh
gh pr comment 42 --attach "$(haus-vm-shot my-lane)#the bar, after"
gh pr create  --attach "$(haus-vm-shot my-lane)#⌘Space, no filter flash"
```

`--attach` is repeatable (up to 50 files a command), takes
PNG/JPEG/GIF/WebP/SVG/MP4/MOV/WebM, puts alt text after a `#`, and uploads with
the token `gh` already holds. Images cap at 10 MB. It is not supported against
GitHub Enterprise Server, and the release that shipped it names OAuth and
classic personal access tokens as what it authenticates with — it says nothing
about fine-grained ones, so treat a job running on a fine-grained token or a
workflow's `GITHUB_TOKEN` as unproven here rather than as working.

**Opt in per PR; do not make it a habit.** The capture is seconds, but a picture
that shows *your change* means `haus rebuild` inside the guest first, which is
minutes. Attach one when the alternative is a human having to feel the change
themselves: a bar layout, a palette hue, a tiling gap, a notch shelf, a banner.
A docs or script PR gets nothing from a photograph of a desktop.

Two things to check before uploading, both of them the dialog problem above
wearing a different hat: a frame that is 40% unanswered modal is a worse answer
than no frame, and a guest that has not rebuilt is a photograph of the change
you did not make.

None of this is gated on the user's Mac: work that runs over `ssh` somewhere else
is never a desktop interruption, however loudly it redraws over there.

## When the guest looks unreachable

`scruff runtime up` returns once **sshd answered**, not once the guest took a
DHCP lease, so an address it printed was reachable a moment ago. It waits up to
`SCRUFF_TART_SSH_WAIT` seconds (180) for that answer, and says which address it
is waiting on while it does. A guest that never answers is told to you instead,
with the path of its boot log (`$TMPDIR/scruff-<lane>.boot.log`) and whatever
the last ssh attempt printed — read those before anything else.

The clone is still on disk either way, and how you reclaim it depends on which
failure you got: a guest that never took an address has already been stopped, so
`tart delete scruff-<lane>` works; one that has an address but no sshd was left
RUNNING on purpose, so it takes `scruff runtime down <lane> --backend tart` —
`tart delete` refuses a running VM and there is no `--force`.

If ssh or ping fails anyway, do **not** start debugging the network.
hausfold/haus#663 spent two sessions ruling these out and none of them wants
re-running: the guest image (Remote Login is on, no guest firewall), the host
bridge (`bridge100` has both `vmenet` members, ARP resolves, routes are
present), Claude Code's own sandbox (`dangerouslyDisableSandbox` changes
nothing), and Tailscale. The mechanical half of that report turned out to be
this script rather than the network, and is fixed; what is left over is one
observation, worth exactly one try: a second pane reached the same class of
guest cleanly at the same moment one pane could not. So if it still fails after
the checks above, try it once from a fresh pane, take that pane if it works, and
hand the rest back. Two minutes, not twenty.

## When the VM cannot answer

Ask for the user's own screen only when it genuinely cannot — their windows,
their data, their hardware, or a guest that will not boot. If the VM is out of
reach at all (no `tart`, no image on disk), say so in one line and hand the
feel-test back rather than reaching for the pointer here.
