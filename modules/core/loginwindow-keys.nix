# The `com.apple.loginwindow` half of §5.6's "Lock / login / screensaver" and
# "Security posture" groups, as one table: the plist key macOS stores, and the
# `haus.*` path that sets it.
#
# Same shape as ./hot-corners.nix, ./alert-sounds.nix and
# ../windows/window-manager-keys.nix, for the same reason — two files read it
# and neither may restate it:
#
#   ./options.nix   declares the options; `mkLoginWindow` refuses a plist key
#                   this table doesn't carry, so an option can't exist for a key
#                   nothing will write.
#   ./default.nix   walks the table to build the `system.defaults.loginwindow`
#                   block, reading each option by the path here, so a table entry
#                   with no option fails at eval instead of writing nothing.
#
# The paths are absolute under `haus`, not relative to one namespace, because
# this domain is genuinely split across two of them and the split is right:
# `haus.lock.login.*` is what the login WINDOW looks like, `haus.security.*` is
# who gets past it. One plist domain, two questions, and the option tree should
# answer the question a person is asking rather than mirroring Apple's filing.
#
# Every key here is logout-only (../lib/restart-map.nix marks the domain
# `logout`), which is why every option built from this table carries
# ../lib/login-map.nix's paragraph. That is not restated per key: it is a
# property of the domain, and all of these keys are in it.
{
  # ---- the login window's appearance (haus.lock.login.*) --------------------
  SHOWFULLNAME = [
    "lock"
    "login"
    "showNameField"
  ];
  LoginwindowText = [
    "lock"
    "login"
    "message"
  ];
  ShutDownDisabled = [
    "lock"
    "login"
    "hideShutDown"
  ];
  RestartDisabled = [
    "lock"
    "login"
    "hideRestart"
  ];
  SleepDisabled = [
    "lock"
    "login"
    "hideSleep"
  ];

  # ---- who may log in at all (haus.security.*) ------------------------------
  GuestEnabled = [
    "security"
    "guestAccount"
  ];
}
