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
scruff runtime up    my-lane --backend tart   # clone the image, boot it headless
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
ssh admin@"$guest" 'haus rebuild'
ssh admin@"$guest" '/usr/sbin/screencapture -x /tmp/s.png'   # real pixels
scp admin@"$guest":/tmp/s.png ./shot.png                     # fetch it, then look
ssh admin@"$guest" '/usr/bin/osascript -e "tell application \"System Events\" to keystroke space using command down"'
```

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

None of this is gated on the user's Mac: work that runs over `ssh` somewhere else
is never a desktop interruption, however loudly it redraws over there.

## When the VM cannot answer

Ask for the user's own screen only when it genuinely cannot — their windows,
their data, their hardware, or a guest that will not boot. If the VM is out of
reach at all (no `tart`, no image on disk), say so in one line and hand the
feel-test back rather than reaching for the pointer here.
