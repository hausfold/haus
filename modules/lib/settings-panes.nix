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

  # Local Network has NO anchor of its own, so this is deliberately the privacy
  # LIST and the card that uses it owes the reader a step. Spelled out here
  # anyway, rather than left for each room to rediscover: a room asking for
  # `panes.localNetwork` gets the best that exists and the reason, instead of
  # inventing a fourth wrong URL.
  #
  # MEASURED 2026-09-12, macOS 26.6.2 guest, four spellings:
  #   ?Privacy_LocalNetwork                 → this list (anchor ignored)
  #   extension?privacy-localnetwork        → this list (anchor ignored)
  #   extension.privacy-localnetwork        → General, the front page
  #   extension.privacy-allfiles            → General, the front page
  # The last one is the control, and it is what settles the shape: the UTType
  # form is not a deep link at ALL, even for a service that HAS a working
  # anchor, so there is no modern spelling left to try. And
  # `com.apple.settings.PrivacySecurity.extension.privacy-localnetwork` really
  # is a type SecurityPrivacyExtension.appex declares — the whole `Privacy_*`
  # anchor family lives in that binary's strings and LocalNetwork is the one
  # service missing from it.
  localNetwork = privacy;

  # General ▸ Login Items & Extensions — where Tahoe's Background Task
  # Management puts the "Allow in the Background" list every nix agent lands in.
  loginItems = "x-apple.systempreferences:com.apple.LoginItems-Settings.extension";
}
