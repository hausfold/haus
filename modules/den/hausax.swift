// hausax — effective appearance + accessibility state, per AppKit, not a plist
// read-back. Plus the two things activation needs that nothing else in the rice
// can reach: posting a distributed notification, and the Text Input Sources API.
//
//   hausax                                  the JSON state below
//   hausax post-notification <name>         restart-map.nix's `notify:` verb
//   hausax input-sources [--all]            enabled (or every) keyboard layout id
//   hausax input-source enable|disable <id>
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
//
// The input-source subcommands exist for the same class of reason. Enabling a
// keyboard layout by writing com.apple.HIToolbox DOES work, but the entry
// resolves by an English display name ("Swiss French", not the "SwissFrench" in
// its input-source id) beside a numeric `KeyboardLayout ID` that is required
// and never validated — a name/id table the rice would have to hardcode and
// would get wrong for exactly the layouts nobody here tests. TISEnableInputSource
// is documented, live, and writes the canonical entry itself.
import AppKit
import Carbon.HIToolbox
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("hausax: \(message)\n".utf8))
    exit(1)
}

// ---- state (the no-argument form) -----------------------------------------

func printState() {
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
}

// ---- input sources ---------------------------------------------------------

func sourceID(_ s: TISInputSource) -> String {
    guard let r = TISGetInputSourceProperty(s, kTISPropertyInputSourceID) else { return "?" }
    return Unmanaged<CFString>.fromOpaque(r).takeUnretainedValue() as String
}

/// Keyboard LAYOUTS only. The two always-present input methods (the emoji
/// picker, press-and-hold) are not layouts and are never the rice's business —
/// disabling one would take the ⌃⌘Space palette away from a machine that never
/// asked.
func layouts(includeDisabled: Bool) -> [TISInputSource] {
    let all =
        TISCreateInputSourceList(nil, includeDisabled)?.takeRetainedValue() as? [TISInputSource]
        ?? []
    return all.filter { sourceID($0).hasPrefix("com.apple.keylayout.") }
}

// ---- dispatch --------------------------------------------------------------

let args = Array(CommandLine.arguments.dropFirst())

switch args.first {
case nil:
    printState()

case "post-notification":
    guard args.count == 2 else { fail("usage: hausax post-notification <name>") }
    DistributedNotificationCenter.default().postNotificationName(
        Notification.Name(args[1]), object: nil, userInfo: nil, deliverImmediately: true)

case "input-sources":
    let all = args.contains("--all")
    print(layouts(includeDisabled: all).map(sourceID).sorted().joined(separator: "\n"))

case "input-source":
    guard args.count == 3, args[1] == "enable" || args[1] == "disable" else {
        fail("usage: hausax input-source enable|disable <input-source-id>")
    }
    guard let src = layouts(includeDisabled: true).first(where: { sourceID($0) == args[2] }) else {
        fail("no such keyboard layout: \(args[2]) — `hausax input-sources --all` lists them")
    }
    let status = args[1] == "enable" ? TISEnableInputSource(src) : TISDisableInputSource(src)
    if status != noErr { fail("could not \(args[1]) \(args[2]) — OSStatus \(status)") }

default:
    fail("unknown command: \(args[0])")
}
