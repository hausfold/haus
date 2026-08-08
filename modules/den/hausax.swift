// hausax — effective appearance + accessibility state, per AppKit, not a plist
// read-back.
//
//   hausax
//
// Prints JSON: {"appearance":"light"|"dark",
//               "differentiateWithoutColor":bool,"increaseContrast":bool,
//               "reduceMotion":bool,"reduceTransparency":bool}
//
// Why this exists: on macOS 26, com.apple.Accessibility writes succeed and
// change nothing — the plist flips, NSWorkspace does not (see the workshop's
// notes/macos-settings-matrix.md). A settings command that only reads plists
// would call that write "applied" when it silently did nothing. This is the
// oracle `haus diff` / `haus plan` use for the keys with a measured
// write-vs-effect gap; every other domain's plist read is reliable (the
// matrix's control group wrote the same value to five ordinary domains from
// the same shell and read it straight back).
//
// `appearance` is the same story one step worse, measured 2026-08-08 on macOS
// 26.6. NSGlobalDomain's AppleInterfaceStyle is not a lever at all — it is a
// MIRROR the appearance system writes when something else changes polarity.
// Neither `defaults write -g AppleInterfaceStyle Dark` from a light session nor
// `defaults delete -g AppleInterfaceStyle` from a dark one moves the effective
// appearance, before OR after `activateSettings -u`, and not even for a process
// launched fresh afterwards; no AppleInterfaceThemeChangedNotification is
// posted. The System Events route does all of that within ~0.3s, and deletes or
// writes that same key on its way past. So haus.theme.systemAppearance is
// driven by AppleScript and confirmed HERE — never by reading the key back,
// which would report the write it just made and call an inert one applied.
import AppKit
import Foundation

let w = NSWorkspace.shared
let dark =
    NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
let state: [String: Any] = [
    "appearance": dark ? "dark" : "light",
    "reduceMotion": w.accessibilityDisplayShouldReduceMotion,
    "reduceTransparency": w.accessibilityDisplayShouldReduceTransparency,
    "increaseContrast": w.accessibilityDisplayShouldIncreaseContrast,
    "differentiateWithoutColor": w.accessibilityDisplayShouldDifferentiateWithoutColor,
]
let data = try! JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])
print(String(data: data, encoding: .utf8)!)
