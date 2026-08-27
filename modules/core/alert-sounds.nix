# The alert sounds macOS ships, as ONE table — the enum in core/options.nix and
# the path core/default.nix writes both come from here, so the option can never
# offer a name the module then fails to resolve. Same shape, and the same
# reason, as hot-corners.nix.
#
# These are the basenames in /System/Library/Sounds (macOS 26.6, 14 of them).
# The rice writes `/System/Library/Sounds/<name>.aiff`, and checks the file
# exists before writing it: `com.apple.sound.beep.sound` takes an absolute path,
# validates nothing, and a path that doesn't resolve makes the alert SILENT
# rather than falling back to the default beep (measured by ear 2026-08-08 —
# see `docs/macos-settings.md`). A release that retires a
# sound must degrade to a warning, never to a machine that stopped beeping.
[
  "Basso"
  "Blow"
  "Bottle"
  "Frog"
  "Funk"
  "Glass"
  "Hero"
  "Morse"
  "Ping"
  "Pop"
  "Purr"
  "Sosumi"
  "Submarine"
  "Tink"
]
