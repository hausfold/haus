// hausax — effective accessibility state, per NSWorkspace, not a plist read-back.
//
//   hausax
//
// Prints JSON: {"differentiateWithoutColor":bool,"increaseContrast":bool,
//               "reduceMotion":bool,"reduceTransparency":bool}
//
// Why this exists: on macOS 26, com.apple.Accessibility writes succeed and
// change nothing — the plist flips, NSWorkspace does not (see the workshop's
// notes/macos-settings-matrix.md). A settings command that only reads plists
// would call that write "applied" when it silently did nothing. This is the
// oracle `haus diff` / `haus plan` use for the four keys with a measured
// write-vs-effect gap; every other domain's plist read is reliable (the
// matrix's control group wrote the same value to five ordinary domains from
// the same shell and read it straight back).
import AppKit
import Foundation

let w = NSWorkspace.shared
let state: [String: Bool] = [
    "reduceMotion": w.accessibilityDisplayShouldReduceMotion,
    "reduceTransparency": w.accessibilityDisplayShouldReduceTransparency,
    "increaseContrast": w.accessibilityDisplayShouldIncreaseContrast,
    "differentiateWithoutColor": w.accessibilityDisplayShouldDifferentiateWithoutColor,
]
let data = try! JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])
print(String(data: data, encoding: .utf8)!)
