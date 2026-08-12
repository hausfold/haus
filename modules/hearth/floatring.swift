// floatring — draw a thin rounded outline just outside ANOTHER process's window,
// and keep it there until that process exits.
//
// It exists for the rice's floating Ghostty popups (Super-y peek, the Rebuild
// System palette command, the bar's agent peek), which land on top of a tiled
// desktop with nothing separating their edge from whatever is behind them.
// Ghostty can't draw the edge itself: 1.3.1's only padding-colour knob is
// `window-padding-color = background|extend`, with no border option at all, and
// neither aerospace (which explicitly leaves borders to other tools) nor
// SketchyBar can decorate a window it doesn't own. So the outline is its own
// tiny overlay window, spawned beside the popup by float-term.sh.
//
//   floatring --pid 1234 [--color '#343434'] [--width 2] [--radius 16.5]
//
// Why not JankyBorders: it filters by APPLICATION, so `whitelist=Ghostty` rings
// every terminal in the tiling too — the popups are plain Ghostty instances,
// indistinguishable to it — and it costs a second always-on daemon. One ring
// per popup, living and dying with it, is the scope that was actually asked for.
//
// It needs NO TCC grant, which is the whole reason geometry comes from
// CGWindowListCopyWindowInfo rather than the Accessibility API: the window list
// hands out bounds, owner pid and layer without Screen Recording (only window
// *names* are withheld), while an AX follower would need an Accessibility grant
// keyed to this binary's /nix/store path — and that path changes on every
// rebuild, so the grant would silently orphan itself (the same trap that bites
// Homebrew-versioned CLIs).
//
// The ring is drawn only while the target owns the frontmost ORDINARY window:
// it hides itself the moment you Cmd-Tab away, when aerospace parks the popup's
// workspace off-screen, and when the popup's window closes.

import AppKit

// ── args ────────────────────────────────────────────────────────────────────
var pid: pid_t = 0
// Only a hand-run fallback: modules/hearth always passes --color, resolved from
// the SELECTED Nebelung variant (mocha surface0 #343434, latte's #d0d0d0), so
// this constant can't follow the theme and must never be relied on to.
var hex = "#343434"
var width: CGFloat = 2
// 16.5pt is macOS 26's window corner radius, measured rather than guessed:
// screenshot a Ghostty window's corner, then fit a CALayer's continuous-corner
// profile to the pixels (best fit 16.5pt, sub-pixel RMSE). If a later macOS
// reshapes its windows, this is the one number to re-measure — the ring's inner
// edge has to sit exactly on the window's own curve or the corners read as bent.
var radius: CGFloat = 16.5

var args = Array(CommandLine.arguments.dropFirst())
var i = 0
while i < args.count {
    let flag = args[i]
    let value = i + 1 < args.count ? args[i + 1] : ""
    switch flag {
    case "--pid": pid = pid_t(value) ?? 0; i += 2
    case "--color": hex = value; i += 2
    case "--width": width = CGFloat(Double(value) ?? Double(width)); i += 2
    case "--radius": radius = CGFloat(Double(value) ?? Double(radius)); i += 2
    default: i += 1
    }
}

guard pid > 0, width > 0 else {
    FileHandle.standardError.write(
        "usage: floatring --pid PID [--color '#rrggbb'] [--width PT] [--radius PT]\n"
            .data(using: .utf8)!)
    exit(2)
}

func parseColor(_ s: String) -> NSColor {
    var t = s.trimmingCharacters(in: .whitespaces)
    if t.hasPrefix("#") { t.removeFirst() }
    guard t.count == 6, let v = UInt32(t, radix: 16) else {
        return NSColor(srgbRed: 0.2, green: 0.2, blue: 0.2, alpha: 1)
    }
    return NSColor(
        srgbRed: CGFloat((v >> 16) & 0xff) / 255,
        green: CGFloat((v >> 8) & 0xff) / 255,
        blue: CGFloat(v & 0xff) / 255,
        alpha: 1)
}

// ── the target's window ─────────────────────────────────────────────────────
// Frame of the target's window IF it currently owns the frontmost ordinary
// window, else nil (which the tick reads as "hide the ring"). The window list
// comes back front-to-back, so the first layer-0 entry IS the frontmost
// ordinary window — everything above layer 0 is a panel, popup or overlay,
// including this process's own ring, which must never be mistaken for the
// thing it's drawn around.
func frontmostFrame() -> CGRect? {
    guard
        let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
    else { return nil }
    for w in list {
        guard (w[kCGWindowLayer as String] as? Int) == 0 else { continue }
        guard (w[kCGWindowOwnerPID as String] as? pid_t) == pid else { return nil }
        guard let bounds = w[kCGWindowBounds as String] as? NSDictionary,
            let rect = CGRect(dictionaryRepresentation: bounds)
        else { return nil }
        // Sanity gate, same spirit as float-term.sh's: a real window, not a
        // zero-size stub mid-teardown.
        return rect.width >= 40 && rect.height >= 40 ? rect : nil
    }
    return nil
}

// Does the target still HAVE a window anywhere (on screen or not)? Distinguishes
// "you Cmd-Tabbed away" from "the popup closed but the process hasn't reaped
// yet" — without it a lingering instance would leave an invisible ring process
// behind forever.
func hasAnyWindow() -> Bool {
    guard
        let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]]
    else { return true }
    return list.contains {
        ($0[kCGWindowOwnerPID as String] as? pid_t) == pid
            && ($0[kCGWindowLayer as String] as? Int) == 0
    }
}

// CoreGraphics global coords are top-left origin on the zero screen; AppKit
// window frames are bottom-left. Same conversion float-term.sh's JXA does, and
// deliberately spelled the same way (screens[0] is the zero screen).
func toWindowCoords(_ r: CGRect) -> NSRect {
    let primaryH = NSScreen.screens.first?.frame.height ?? r.maxY
    return NSRect(x: r.origin.x, y: primaryH - r.maxY, width: r.width, height: r.height)
}

// ── the ring ────────────────────────────────────────────────────────────────
let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // no Dock tile, no menu bar, never activates

let panel = NSPanel(
    contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered, defer: false)
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = false
panel.ignoresMouseEvents = true  // a summoned popup you can't click through to is worse than no ring
panel.level = .floating  // one step above ordinary windows, i.e. above the popup
panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
panel.isReleasedWhenClosed = false

let view = NSView(frame: .zero)
view.wantsLayer = true
if let layer = view.layer {
    layer.backgroundColor = .clear
    layer.borderWidth = width
    layer.borderColor = parseColor(hex).cgColor
    // The panel is outset by `width`, so the layer's OUTER radius is the
    // window's plus the stroke; the border draws inward from there, leaving its
    // inner edge on the window's own curve. `.continuous` is what makes it a
    // squircle instead of a circular arc — matching macOS is the difference
    // between an invisible outline and one that visibly bulges at the corners.
    layer.cornerRadius = radius + width
    layer.cornerCurve = .continuous
}
panel.contentView = view

var shown = false
var windowlessTicks = 0

let tick = Timer(timeInterval: 1.0 / 30.0, repeats: true) { _ in
    // Process gone: nothing left to ring.
    if kill(pid, 0) != 0 && errno == ESRCH { exit(0) }

    if let frame = frontmostFrame() {
        windowlessTicks = 0
        let target = toWindowCoords(frame).insetBy(dx: -width, dy: -width)
        if panel.frame != target { panel.setFrame(target, display: false) }
        if !shown {
            panel.orderFront(nil)  // a nonactivating panel can front without stealing focus
            shown = true
        }
        return
    }

    if shown {
        panel.orderOut(nil)
        shown = false
    }
    // ~2s with no window of its own at all — the popup closed, so stop.
    windowlessTicks = hasAnyWindow() ? 0 : windowlessTicks + 1
    if windowlessTicks > 60 { exit(0) }
}
RunLoop.main.add(tick, forMode: .common)
app.run()
