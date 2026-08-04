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
# Finder" (Finder is quittable — den sets QuitMenuItem). With no bound, a
# KeepAlive restart while Finder is closed parks the agent in the loop forever:
# pounce stops answering its hotkey until the next reboot, with a live pid and
# nothing in the log. Past the deadline we launch anyway — a GUI agent starting
# slightly too early degrades (a hotkey to re-register); one that never starts
# is just gone.
let
  script = ''
    deadline=$(( $(/bin/date +%s) + 60 ))
    for proc in Dock Finder SystemUIServer; do
      until /usr/bin/pgrep -x "$proc" >/dev/null 2>&1; do
        [ "$(/bin/date +%s)" -ge "$deadline" ] && break
        sleep 1
      done
    done
    until /usr/bin/osascript -e 'tell application "System Events" to count processes' >/dev/null 2>&1; do
      [ "$(/bin/date +%s)" -ge "$deadline" ] && break
      sleep 1
    done
  '';
in
{
  inherit script;

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
