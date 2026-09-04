// floatpin — pin ANOTHER Ghostty instance's window above every tiled window,
// and keep it there no matter what you click next.
//
//   floatpin --pid 1234 [--off] [--timeout 2.0]
//
// It exists because "floating" in AeroSpace is a LAYOUT, not a stacking order.
// A float-term popup lands on top of the tiled desktop and then vanishes behind
// the first tiled window you click — which is fatal for the popups that exist
// to be READ while you work (⌘Y's yazi peek, ⌘G's gh-dash, the bar's agent
// peek): the thing you summoned to look at is the thing that disappears.
//
// ── why the stacking order is the wrong lever, measured ─────────────────────
// Raising is not enough, and this is the trap to not fall into twice. AX's
// `kAXRaiseAction` does work cross-app and does NOT steal focus, but it caps at
// z-index 1: macOS pins the active application's key window at 0, so a raised
// popup lands directly BEHIND the tiled window you just clicked and is covered
// by it exactly as before (measured on Darwin 25.6, 2026-08-30). The private
// SkyLight route is worse — `SLSSetWindowLevel(cid, wid, 3)` returns err=0 and
// reads back 3 inside the calling process, but a fresh process reads 0 and
// `kCGWindowLayer` never leaves 0, whether addressed through the main
// connection or the window's own from `SLSGetWindowOwner`. It simply does not
// apply. That is the gap yabai fills by injecting a scripting addition under
// partially-disabled SIP, and it is why haus does not chase foreign apps here.
//
// What DOES beat the active app's key window is the window's LEVEL. A window
// above `.normal` sits over everything at normal level regardless of which app
// is frontmost — the same mechanism floatring.swift uses for its own outline.
// A level can only be set by the process that owns the window, so the only
// question is how to ask Ghostty to set it on one of its own.
//
// ── why an Apple event, addressed by pid ────────────────────────────────────
// Ghostty 1.3.1 ships the action `toggle_window_float_on_top` and exposes
// `perform action` in its AppleScript dictionary. It does NOT expose the state
// as a config key, so there is nothing to pass on the `open -na` command line —
// the window has to be told after it exists.
//
// `osascript -e 'tell application "Ghostty" …'` cannot do it. Every float-term
// popup and every agent lane is its own `open -na Ghostty.app` INSTANCE, and a
// `tell application` by name resolves to exactly one of them through
// LaunchServices — measured picking the most recently launched, which is a race
// we would lose the moment two popups (or a popup and a lane) open together.
// Pinning the wrong window is silent and looks like the feature not working.
// So the event is addressed to a process id, which float-term.sh already knows
// because it is the pid it just spawned.
//
// Two details of that event cost an hour each if rediscovered:
//   * the `on` parameter is REQUIRED. Omitting it returns errAEDescNotFound
//     (-1701) rather than defaulting to the focused terminal.
//   * Ghostty's window class code is `Gwnd`, not the standard `cwin`. A `cwin`
//     specifier returns errAENoSuchObject (-1728), which reads like a missing
//     window rather than a wrong four-char code.
// The specifier is therefore `terminal 1 of tab 1 of window 1`, which is the
// whole of a fresh popup: one window, one tab, one surface.
//
// ── TCC ─────────────────────────────────────────────────────────────────────
// Sending an Apple event to another application is gated by Automation, and
// which application is ASKING is the responsible process — whatever spawned
// float-term.sh, NOT this binary. There are two of those and they need separate
// grants: Pounce, for the palette commands and the ⌘-chords its event tap owns,
// and SketchyBar, for the bar's agent peek (modules/bar/sketchybar/plugins/
// agents.sh calls `float-term.sh spawn` directly). Pounce's grant survives a
// rebuild because the daemon runs the CI-built release app, signed with
// hausfold's Developer ID — its requirement anchors on the team, not a
// per-build cdhash. Sketchybar is an adhoc-signed store path, so its grant is
// re-asked whenever that path moves. Both are one card in the
// manual-click deck rather than a surprise.
//
// A denied or stale grant costs the pin and nothing else: the popup still
// opens, still floats, still wears its ring, and — because float-term.sh
// detaches this call — still takes focus without waiting for us.
//
// The level itself is read back through CGWindowListCopyWindowInfo, which needs
// no grant at all — same TCC-free source floatring.swift and hausrect.swift
// use, and the reason this can verify its own work instead of trusting a reply.

import AppKit
import Foundation

// ── args ────────────────────────────────────────────────────────────────────
var pid: pid_t = 0
var wantPinned = true
// The caller spawns the window and calls us in the same breath, so the window
// may not exist yet. Two seconds is far past the ~200 ms it actually takes and
// still short enough that a popup that died on launch doesn't leave a process
// waiting on it. Nothing blocks on this wait — float-term.sh's pin() detaches —
// so it buys reliability rather than costing latency.
var timeout: Double = 2.0

var args = Array(CommandLine.arguments.dropFirst())
while !args.isEmpty {
    let flag = args.removeFirst()
    switch flag {
    case "--pid":
        if let v = args.first.flatMap(Int32.init) { pid = v; args.removeFirst() }
    case "--off":
        wantPinned = false
    case "--timeout":
        if let v = args.first.flatMap(Double.init) { timeout = v; args.removeFirst() }
    default:
        break
    }
}
guard pid > 0 else {
    FileHandle.standardError.write(Data("floatpin: --pid is required\n".utf8))
    exit(2)
}

// ── the window's level, from the grant-free window list ─────────────────────
// Layer 0 is an ordinary application window; anything above it is pinned, which
// is the only distinction this tool needs. Deliberately NOT a test for 3: 3 is
// what `toggle_window_float_on_top` happens to produce today
// (kCGFloatingWindowLevel), and hard-coding it would make a Ghostty that picked
// any other level read as "the toggle did nothing" — which, with a retry above
// it, would toggle the window straight back OFF. `pinned` is a predicate about
// the level's relationship to ordinary windows, so it survives Ghostty changing
// its mind.
//
// Returns nil while the pid owns no on-screen window at all — that is how the
// wait below tells "not yet" from "on screen and unpinned".
func currentLayer(of pid: pid_t) -> Int? {
    let info =
        CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] ?? []
    for window in info {
        guard window[kCGWindowOwnerPID as String] as? Int == Int(pid),
            let layer = window[kCGWindowLayer as String] as? Int
        else { continue }
        // Menus, popovers and the dragging layer live in the twenties and
        // above; a terminal window never does. Excluding them stops a menu that
        // happens to be open answering for the window we mean.
        if layer < 20 { return layer }
    }
    return nil
}

func isPinned(_ layer: Int) -> Bool { layer > 0 }

func fourCharCode(_ s: String) -> UInt32 {
    var value: UInt32 = 0
    for byte in s.utf8 { value = (value << 8) | UInt32(byte) }
    return value
}

// One rung of an object specifier: `<want> <index> of <from>`.
func objectSpecifier(want: String, from: NSAppleEventDescriptor, index: Int32)
    -> NSAppleEventDescriptor
{
    let spec = NSAppleEventDescriptor.record().coerce(toDescriptorType: typeObjectSpecifier)!
    spec.setDescriptor(
        NSAppleEventDescriptor(typeCode: fourCharCode(want)),
        forKeyword: AEKeyword(fourCharCode("want")))
    spec.setDescriptor(from, forKeyword: AEKeyword(fourCharCode("from")))
    spec.setDescriptor(
        NSAppleEventDescriptor(enumCode: fourCharCode("indx")),
        forKeyword: AEKeyword(fourCharCode("form")))
    spec.setDescriptor(NSAppleEventDescriptor(int32: index), forKeyword: AEKeyword(fourCharCode("seld")))
    return spec
}

// `tell app (pid) to perform action "<action>" on terminal 1 of tab 1 of window 1`
func performGhosttyAction(_ action: String, pid: pid_t) -> Bool {
    let window = objectSpecifier(want: "Gwnd", from: .null(), index: 1)
    let tab = objectSpecifier(want: "Gtab", from: window, index: 1)
    let terminal = objectSpecifier(want: "Gtrm", from: tab, index: 1)

    let event = NSAppleEventDescriptor.appleEvent(
        withEventClass: fourCharCode("Ghst"), eventID: fourCharCode("PfAc"),
        targetDescriptor: NSAppleEventDescriptor(processIdentifier: pid),
        returnID: AEReturnID(kAutoGenerateReturnID),
        transactionID: AETransactionID(kAnyTransactionID))
    event.setDescriptor(NSAppleEventDescriptor(string: action), forKeyword: AEKeyword(keyDirectObject))
    event.setDescriptor(terminal, forKeyword: AEKeyword(fourCharCode("GonT")))

    // A popup whose workspace AeroSpace has already parked off-screen can answer
    // slowly or not at all (App Nap), so the send is bounded tightly rather than
    // trusted. 1.5s, not AppleScript's customary 5: the whole run is on the tail
    // of a keystroke, and the verify below is what decides success anyway.
    guard let reply = try? event.sendEvent(options: [.waitForReply], timeout: 1.5) else {
        return false
    }
    if let err = reply.forKeyword(AEKeyword(fourCharCode("errn")))?.int32Value, err != 0 {
        return false
    }
    return reply.forKeyword(AEKeyword(keyDirectObject))?.booleanValue ?? false
}

// ── wait for the window, then make the level match ──────────────────────────
let deadline = Date().addingTimeInterval(timeout)
var layer: Int? = nil
while Date() < deadline {
    layer = currentLayer(of: pid)
    if layer != nil { break }
    usleep(20_000)
}
guard var observed = layer else { exit(1) }  // no window ever appeared

// Toggle, then confirm against the window list rather than against the reply:
// the reply says Ghostty ran the action, the layer says the window actually
// moved. One retry covers a popup still finishing its first layout.
//
// ⚠️ The retry re-reads the level and only fires again if the window is STILL
// where it started. `toggle_window_float_on_top` is a TOGGLE, so a retry that
// assumed failure because the level is not the number it expected would undo a
// pin that had worked — the exact bug a hard-coded "is it 3?" oracle invites.
// Unchanged means the action didn't land; anything else is Ghostty's answer and
// we accept it.
for attempt in 0..<2 {
    if isPinned(observed) == wantPinned { exit(0) }

    _ = performGhosttyAction("toggle_window_float_on_top", pid: pid)

    let settle = Date().addingTimeInterval(0.4)
    while Date() < settle {
        if let now = currentLayer(of: pid), now != observed {
            observed = now
            break
        }
        usleep(20_000)
    }
    if attempt == 0 { usleep(80_000) }
}
exit(isPinned(observed) == wantPinned ? 0 : 1)
