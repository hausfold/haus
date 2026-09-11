# The GUI-session wait every launchd GUI agent starts with, in two forms:
#
#   .script  — the bash snippet on its own, for an agent that builds its own
#              launcher (pounce, whose daemon line is generated beside it).
#   .wrap    — wrap a plain executable:  .wrap "/Applications/Foo.app/…/Foo"
#
# Two problems this solves, both from launching GUI agents via launchd on
# Determinate Nix:
#   1. The launcher must NOT live in /nix/store. Determinate mounts /nix from a
#      separate APFS volume; at cold boot the user-domain launchd evaluates
#      plists before that volume is reliably up, the kernel reports "Missing
#      executable", and the job parks with last exit = 78 (EX_CONFIG). Embedding
#      the script inline keeps it on the boot volume (~/Library/LaunchAgents).
#   2. We wait until the GUI (Aqua) session is actually ready before exec'ing —
#      the Aqua-session limit alone isn't enough (e.g. AeroSpace's Carbon hotkey
#      registration silently no-ops if the event manager isn't up yet).
#
# EVERY wait here is bounded by ONE shared 60 s deadline. That bound is the
# whole point: the loops answer "is the session up *yet*", and an unbounded
# `until pgrep -x Finder` can't tell "not booted yet" from "you pressed ⌘Q in
# Finder" (Finder is quittable — core sets QuitMenuItem). With no bound, a
# KeepAlive restart while Finder is closed parks the agent in the loop forever:
# pounce stops answering its hotkey until the next reboot, with a live pid and
# nothing in the log. Past the deadline we launch anyway — a GUI agent starting
# slightly too early degrades (a hotkey to re-register); one that never starts
# is just gone.
#
# WHY THE SECOND LOOP ASKS LAUNCHSERVICES AND NOT SYSTEM EVENTS. It used to be
#
#     osascript -e 'tell application "System Events" to count processes'
#
# which made this file the first thing a fresh machine ever put on screen. macOS
# files that request under /bin/bash — this script's own interpreter, because
# the responsible-process chain from a launchd job never resolves to an app
# bundle — so the modal reads "'bash' wants access to control 'System
# Events.app'", naming nothing the person installed, with no bar, no tiler and
# no palette drawn behind it, since all of them are blocked in this very loop.
#
# Refusing it was worse than being asked. A denied Apple event does not fail
# fast: it sits out the Apple Event Manager's two-minute timeout and dies with
# -1712. That happens in the `until` CONDITION, which the deadline check in the
# loop body only gets to run between — so the bound this comment is otherwise
# entirely about quietly stopped holding. Instrumented on a cold boot of a guest
# with the grant refused, AeroSpace exec'd 125 s in rather than 65, SketchyBar
# and pounce alongside it; and a refusal is remembered, so that was every login
# from then on. With the probe below, same guest, same refusal: 4.3 s.
#
# That structure is unchanged and worth knowing: a probe still runs in a
# condition, so a probe that BLOCKS still outlives the deadline. Apple events
# were the one call here with a multi-minute manager timeout behind them, which
# is why removing that one fixes the observed bug — it is not a proof that the
# shape is safe for any future probe.
#
# `lsappinfo` is LaunchServices' own door: no Apple event, no grant, no prompt,
# a couple of milliseconds, and a /usr/bin binary on the boot volume like
# everything else here. Three parts, because `front` answers with an ASN, `info`
# turns one into a `"LSDisplayName"="Finder"` line, and the `sed` is what makes
# the test a NAME rather than some bytes: ask `info` about the null ASN and it
# answers `"LSDisplayName"=[ NULL ]`, which is non-empty and would satisfy a
# bare `-n` on the first iteration — in exactly the window the loop exists for,
# where the session is up but nothing is frontmost yet. That is the peel
# front_app_lib.sh already does in the bar; the two halves of one idiom agree.
#
# A name coming back proves coreservicesd is answering FOR THIS SESSION, and
# that the session has a frontmost app for it to answer about. That is a
# correlate, not the thing itself, and the honest reading of the measurement
# says so. On three instrumented cold boots the name first came back at
# 1.08 / 1.35 / 3.87 s, and a freshly spawned process first got a CGS session, a
# WindowServer round trip and a real RegisterEventHotKey — the Carbon call
# AeroSpace's hotkeys ARE, and what point 2 is actually waiting for — at
# 1.16 / 1.89 / 4.18 s. So the probe ran 0.08 / 0.54 / 0.31 s early, and those
# three are ceilings rather than moments: each is the first tick on which the
# measuring binary could be spawned at all, which early in a boot is itself the
# slow part.
#
# Which is why the `/bin/sleep 5` at the end is LOAD-BEARING rather than
# decoration, and why it lives in the shared script rather than in the two
# wrappers: it is the margin that covers a probe answering a little before the
# event path does, and pounce — the agent whose failure IS a dead ⌘Space —
# takes the bare `.script`. The old Apple event supplied that margin by
# accident, since it had to wait for System Events to launch; a probe measured
# in milliseconds does not.
#
# The pgrep trio stays above the second loop. It was true a second earlier on
# all three runs and costs nothing to keep asking.
let
  script = ''
    deadline=$(( $(/bin/date +%s) + 60 ))
    for proc in Dock Finder SystemUIServer; do
      until /usr/bin/pgrep -x "$proc" >/dev/null 2>&1; do
        [ "$(/bin/date +%s)" -ge "$deadline" ] && break
        /bin/sleep 1
      done
    done
    until [ -n "$(/usr/bin/lsappinfo info -only name "$(/usr/bin/lsappinfo front 2>/dev/null)" 2>/dev/null | /usr/bin/sed -n 's/.*"LSDisplayName"="\([^"]*\)".*/\1/p')" ]; do
      [ "$(/bin/date +%s)" -ge "$deadline" ] && break
      /bin/sleep 1
    done
    /bin/sleep 5
  '';
in
{
  inherit script;

  # `.wrapArgs` is `.wrap` for an executable that also takes arguments. Kept as
  # `exec "$0" "$@"` with the target passed as bash's $0 rather than folded into
  # the -c string, because ARGV[0] IS LOAD-BEARING for at least one caller:
  # SketchyBar names its instance after `basename(argv[0])` and keys both its
  # lock file and its mach service on that, which is how bar draws a second bar
  # (a `bar-bottom` symlink to the same binary — see modules/bar).
  wrapArgs =
    target: args:
    [
      "/bin/bash"
      "-c"
      ''
        ${script}
        exec "$0" "$@"
      ''
      target
    ]
    ++ args;

  wrap = target: [
    "/bin/bash"
    "-c"
    ''
      ${script}
      exec "$0"
    ''
    target
  ];
}
