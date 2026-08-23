# System Settings deep links, spelled once.
#
# Every card in the manual-click deck (`haus._contrib.permissions`, rendered by
# `haus permissions`) points at the pane that grants the thing, and a pane URL
# is the one field in a card that fails SILENTLY: `open` on an
# `x-apple.systempreferences:` URL macOS does not recognise puts the user in
# System Settings' front page with no error anywhere, which is the exact
# experience the deck exists to remove. Four rooms wanting
# `Privacy_Accessibility` is four chances to typo it.
#
# These are the anchors macOS 26 answers to. They are NOT http, so `open` is the
# only thing that follows them — nothing here is fetchable and nothing verifies
# them at build time; adding one means opening it on a real Mac first.
rec {
  # Privacy & Security, and its per-service anchors.
  privacy = "x-apple.systempreferences:com.apple.preference.security";
  accessibility = "${privacy}?Privacy_Accessibility";
  fullDiskAccess = "${privacy}?Privacy_AllFiles";
  automation = "${privacy}?Privacy_Automation";
  inputMonitoring = "${privacy}?Privacy_ListenEvent";
  screenRecording = "${privacy}?Privacy_ScreenCapture";

  # General ▸ Login Items & Extensions — where Tahoe's Background Task
  # Management puts the "Allow in the Background" list every nix agent lands in.
  loginItems = "x-apple.systempreferences:com.apple.LoginItems-Settings.extension";
}
