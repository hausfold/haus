# The declarative source of truth for §4 of the workshop's
# notes/options-roadmap.md, answering the spike in
# notes/macos-settings-matrix.md (macOS 26.6, run 2026-07-25 on real hardware,
# not recalled from docs). nix-darwin's own restart logic is one line —
# `killall Dock`, and only when a `dock.*` option changed — and stops there:
# Finder, the menu bar and Control Center all leave their write in the plist
# and wait for a logout unless something restarts them.
#
# This is that something, as DATA rather than one-off fixes scattered through
# postActivation. rice#181 hand-rolled the Finder case alone; den/default.nix
# now derives every restart it fires from this table instead, and asserts
# that every plist domain it actually writes into has an entry here — so a
# future domain with no restart declared fails the build loudly instead of
# silently waiting for a logout the way Finder used to.
#
# Keyed by the plist domain exactly as `defaults write DOMAIN …` (and
# nix-darwin's `system.defaults.<domain>` / `CustomUserPreferences."<domain>"`)
# name it, so a domain never needs two spellings.
#
# Values, per the matrix:
#   "Dock" / "Finder" / "ControlCenter" / "SystemUIServer"
#     — killall that process; it re-reads its domain at launch.
#   "activateSettings"
#     — no process restart. `activateSettings -u` (den's postActivation,
#       mkAfter) is the private binary System Settings itself calls to
#       broadcast a preference change, and covers everything measured in this
#       domain: key repeat, the trackpad trio, _HIHideMenuBar and
#       SLSMenuBarUseBlurredAppearance (both of which Sill depends on).
#   "none"
#     — takes effect immediately; nothing to do.
#   "logout"
#     — macOS has no live-reload path for this domain (measured, not assumed:
#       nix-darwin's restart logic never touches it and no private API does
#       either). Declared so a future write here is a conscious decision, not
#       a silent gap — see the matrix's `com.apple.WindowManager` row.
{
  # ---- always written (mkDefault, every rebuild) ---------------------------
  "com.apple.dock" = "Dock"; # nix-darwin restarts Dock itself whenever this domain is set — see den's postActivation, which skips it to avoid bouncing the Dock twice
  "com.apple.finder" = "Finder";
  "NSGlobalDomain" = "activateSettings";
  "com.apple.AppleMultitouchTrackpad" = "activateSettings";
  "com.apple.screencapture" = "none"; # screencapture re-reads its prefs on every capture

  # ---- FDA-gated, guarded separately -----------------------------------
  # den's `nebelhausAccessibility` block writes this domain itself, guarded
  # against the missing-FDA failure the matrix found (an unguarded write here
  # aborts the rest of activation under `set -e`). A failed write already
  # degrades to "setting skipped"; a successful one is confirmed live by
  # `hausax`'s NSWorkspace read (`haus diff`/`haus plan`), not by a restart.
  "com.apple.universalaccess" = "none";

  # ---- CustomUserPreferences domains actually written today ----------------
  "com.apple.commerce" = "none"; # App Store auto-update pref, read on demand
  "com.apple.desktopservices" = "Finder"; # .DS_Store behaviour; Finder reads it at launch same as its own domain

  # ---- not written yet — declared ahead of use ------------------------------
  # The day the rice (or a host) writes into either of these, the assertion in
  # den/default.nix already has a correct answer instead of another rice#181.
  "com.apple.controlcenter" = "ControlCenter"; # matrix: killall ControlCenter, not done anywhere before this
  "com.apple.WindowManager" = "logout"; # matrix: 12 typed keys, no live-reload path exists on macOS 26
}
