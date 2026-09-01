# The hot-corner actions haus offers, as ONE table.
#
# macOS stores a corner as a bare integer in com.apple.dock (wvous-tl-corner and
# friends). Three things have to agree about that integer — the option's enum,
# the prose that explains each value, and the write that emits it — and they live
# in two different files, so the table is data here and everything else is
# derived from it. A value can never exist in the enum but not the writer, and
# the docs page can never describe an action the option won't accept.
#
# A LIST rather than an attrset because the order is meaningful: it's the order
# the description lists them in, roughly grouped (do nothing · show me things ·
# power · capture), and attrsOf would sort them alphabetically into nonsense.
#
# `7` (Dashboard) is deliberately absent — the feature has been gone since
# Catalina and the corner is a no-op. `8`/`9` were never assigned.
[
  {
    name = "disabled";
    value = 1;
    label = "nothing happens — the corner is explicitly claimed and left inert";
  }
  {
    name = "mission-control";
    value = 2;
    label = "Mission Control: every window and Space, zoomed out";
  }
  {
    name = "application-windows";
    value = 3;
    label = "App Exposé: every window of the app you're in";
  }
  {
    name = "desktop";
    value = 4;
    label = "push all windows aside and show the desktop";
  }
  {
    name = "launchpad";
    value = 11;
    label = "the grid of installed apps (on macOS 26 this opens the Apps view)";
  }
  {
    name = "notification-center";
    value = 12;
    label = "slide out Notification Center and its widgets";
  }
  {
    name = "quick-note";
    value = 14;
    label = "start a Quick Note — Apple's own default for the bottom-right corner";
  }
  {
    name = "screen-saver";
    value = 5;
    label = "start the screen saver immediately";
  }
  {
    name = "prevent-screen-saver";
    value = 6;
    label = "hold the screen saver off while the pointer rests here";
  }
  {
    name = "sleep-display";
    value = 10;
    label = "put the display to sleep (the machine keeps running)";
  }
  {
    name = "lock-screen";
    value = 13;
    label = "lock the screen and return to the login window";
  }
]
