# The GUI-session wait every launchd GUI agent starts with, in two forms:
#
#   .script  — the bash snippet on its own, for agents that do their own work
#              before exec'ing (pounce copies + re-signs its bundle first).
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
# no palette drawn behind it, since all three are blocked in this very loop.
#
# Refusing it was worse than being asked. A denied Apple event does not fail
# fast: it sits out the Apple Event Manager's two-minute timeout and dies with
# -1712, INSIDE the loop body, where the deadline above never gets read. So the
# bound this comment is otherwise entirely about quietly stopped holding —
# instrumented on a cold boot of a guest with the grant refused, AeroSpace
# exec'd 125 s in, not 65, and SketchyBar and pounce alongside it — and a
# refusal is remembered, so that was every login from then on. With the probe
# below, same guest, same refusal: 4.3 s.
#
# `lsappinfo` is LaunchServices' own door: no Apple event, no grant, no prompt,
# a couple of milliseconds, and a /usr/bin binary on the boot volume like
# everything else here. Two calls, because `front` answers with an ASN and
# `info` is what turns one into a name — the pair the bar already asks in
# front_app_lib.sh. A name coming back proves coreservicesd is answering FOR
# THIS SESSION, and that the session has a frontmost app for it to answer
# about.
#
# That is a correlate, not the thing itself, and the honest reading of the
# measurement says so. On three instrumented cold boots the name first came
# back at 1.08 / 1.35 / 3.87 s, and a freshly spawned process first got a CGS
# session, a WindowServer round trip and a real RegisterEventHotKey — the
# Carbon call AeroSpace's hotkeys ARE, and what point 2 is actually waiting for
# — at 1.16 / 1.89 / 4.18 s. Never more than half a second later, and those
# three are ceilings rather than moments: they are the first tick on which the
# probe binary could be spawned at all, which early in a boot is itself the
# slow part. Which makes the `sleep 5` in the two wrappers below LOAD-BEARING
# now rather than decoration: it is the margin that covers a probe answering a
# little before the event path does. The pgrep trio stays above this loop for
# the same reason — it was true a second earlier on all three runs, and it
# costs nothing to keep asking.
let
  script = ''
    deadline=$(( $(/bin/date +%s) + 60 ))
    for proc in Dock Finder SystemUIServer; do
      until /usr/bin/pgrep -x "$proc" >/dev/null 2>&1; do
        [ "$(/bin/date +%s)" -ge "$deadline" ] && break
        sleep 1
      done
    done
    until [ -n "$(/usr/bin/lsappinfo info -only name "$(/usr/bin/lsappinfo front 2>/dev/null)" 2>/dev/null)" ]; do
      [ "$(/bin/date +%s)" -ge "$deadline" ] && break
      sleep 1
    done
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
        sleep 5
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
      sleep 5
      exec "$0"
    ''
    target
  ];
}
