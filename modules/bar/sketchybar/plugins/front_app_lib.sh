#!/bin/bash
# front_app_lib.sh — who is frontmost, without an Apple event.
#
# Sourced by front_app.sh (the pill) and by resize_mode.sh / navigate_mode.sh,
# which repaint that same pill's label when a mode arms. A LIBRARY: sourced,
# never exec'd, so it is 0644 and named in flake.nix's `bar-plugins-executable`
# libs list beside aerospace_lib.sh and the rest.
#
# WHY it exists rather than the one-liner it replaced. All three used to ask
#
#     osascript -e 'tell application "System Events" to get name of first
#                   application process whose frontmost is true'
#
# and on a fresh machine macOS files that request under /bin/bash — the
# plugin's interpreter — because the responsible-process chain from
# SketchyBar's exec never resolves to an app bundle. The modal reads "'bash'
# wants access to control 'System Events.app'", which names nothing the person
# recognises, and front_app.sh is subscribed to front_app_switched, so it
# re-asks on the NEXT app switch and the modal comes straight back. Meanwhile
# an unanswered Automation prompt blocks every other Apple event on the
# machine: each one hangs ~2 minutes and dies with -1712, which is pounce's
# Lock Screen and Force Quit, and any osascript the person runs themselves,
# silently doing nothing. The pill is a NAME — it was never worth an Apple
# event, and now it costs none.
#
# Two sources, in order:
#
#   $INFO      SketchyBar hands the app name straight to a front_app_switched
#              script (src/bar_manager.c, bar_manager_handle_front_app_switch);
#              the value is the NSRunningApplication localizedName it read off
#              NSWorkspaceDidActivateApplicationNotification. Free — already in
#              the environment, no process at all. Gated on $SENDER because
#              INFO is per-event: space_windows_change and the mouse events put
#              JSON there, so a pill that later subscribed to one of those
#              would otherwise paint a brace.
#
#   lsappinfo  LaunchServices' own view of who is frontmost (≈7 ms for the
#              pair of calls, no grant, no Apple event — the binary
#              lane-open.sh asks to name the app it has to give the screen back
#              to, and the one last_closed_app.sh and empty_workspace.sh
#              already run on every single event). This is the cold paint at
#              bar start, where SENDER is `forced` or `routine` and no event
#              has fired yet, and it is every call from the two mode scripts,
#              which AeroSpace runs with none of SketchyBar's environment.
#
# Both sources answer with the app's display name, so the pill reads the same
# whichever one it took.

# front_app_name — print the frontmost app's name, or nothing if neither source
# can say (same silence the denied osascript gave, and about as likely).
front_app_name() {
    if [ "${SENDER:-}" = front_app_switched ] && [ -n "${INFO:-}" ]; then
        printf '%s' "$INFO"
        return 0
    fi

    # Two calls, not one: `lsappinfo front` answers with an ASN, which is the
    # handle `info` wants. The quoting is lsappinfo's own output format —
    # `"LSDisplayName"="Ghostty"` — peeled the way lane-open.sh peels
    # CFBundleIdentifier.
    /usr/bin/lsappinfo info -only name "$(/usr/bin/lsappinfo front 2>/dev/null)" 2>/dev/null |
        sed -n 's/.*"LSDisplayName"="\([^"]*\)".*/\1/p'
}
