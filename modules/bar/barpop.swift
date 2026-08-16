// barpop — dismiss a SketchyBar popup by clicking anywhere else, the way every
// other dropdown on the machine behaves.
//
//   barpop arm <item>      guard the dropdown a pill just opened
//
// The pill still opens its own popup with a plain `popup.drawing=toggle`, and
// then hands the item here — backgrounded, so nothing about opening a dropdown
// waits on this binary:
//
//   sketchybar --set <item> popup.drawing=toggle; barpop arm <item> &
//
// Why a binary at all: SketchyBar sees clicks on its OWN items and nothing else,
// so a popup it opened stays up until that pill is clicked a second time. The
// only signal it has that the pointer went elsewhere is `mouse.exited.global` —
// a HOVER-out, which would yank the agents / AI-usage list away the instant you
// moved the mouse off the bar to read something. Wrong gesture. A click is the
// gesture, and observing clicks outside our own process needs AppKit.
//
// It costs no new permission: NSEvent's global monitor is Accessibility-gated for
// KEY events only, mouse events come through to any process. And it costs no
// daemon — one guard lives while a dropdown is up, and exits the moment the popup
// closes, however it closed.
import AppKit
import Darwin
import Foundation

// ── running sketchybar ───────────────────────────────────────────────────────
// posix_spawn, NOT Foundation's Process. Measured on a live bar: one sketchybar
// round trip costs ~4 ms from a shell and ~85 ms through Process, and a guard
// makes several — which is exactly how the first cut of this file turned a
// dropdown into a visibly laggy one (~200 ms to open, over a second to close on
// the pill with 16 rows). Don't "modernise" this back.
let sketchybarBin: String = {
    let candidates = [
        ProcessInfo.processInfo.environment["SKETCHYBAR_BIN"] ?? "",
        "/opt/homebrew/opt/sketchybar/bin/sketchybar",
        "/opt/homebrew/bin/sketchybar",
        "/usr/local/bin/sketchybar",
    ]
    for path in candidates where !path.isEmpty {
        if FileManager.default.isExecutableFile(atPath: path) { return path }
    }
    return "sketchybar"  // last resort: whatever PATH says
}()

/// Run sketchybar. `capture: false` doesn't even wait for it — the caller only
/// cares that the command is on its way, and SIGCHLD is ignored so the kernel
/// reaps it. That's what makes a dismissal feel like a click rather than a round
/// trip.
@discardableResult
func sb(_ args: [String], capture: Bool = false) -> Data {
    var actions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&actions)
    defer { posix_spawn_file_actions_destroy(&actions) }

    var fds: [Int32] = [-1, -1]
    if capture {
        guard pipe(&fds) == 0 else { return Data() }
        posix_spawn_file_actions_adddup2(&actions, fds[1], 1)
        posix_spawn_file_actions_addclose(&actions, fds[0])
        posix_spawn_file_actions_addclose(&actions, fds[1])
    } else {
        posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0)
    }
    posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)

    var argv: [UnsafeMutablePointer<CChar>?] = ([sketchybarBin] + args).map { strdup($0) }
    argv.append(nil)
    defer { argv.forEach { free($0) } }

    var pid: pid_t = 0
    let spawned = posix_spawnp(&pid, sketchybarBin, &actions, nil, &argv, environ) == 0
    if capture { close(fds[1]) }
    guard spawned else {
        if capture { close(fds[0]) }
        return Data()
    }
    guard capture else { return Data() }

    var out = Data()
    var buffer = [UInt8](repeating: 0, count: 8192)
    while true {
        let n = read(fds[0], &buffer, buffer.count)
        if n <= 0 { break }
        out.append(contentsOf: buffer[0..<n])
    }
    close(fds[0])
    var status: Int32 = 0
    waitpid(pid, &status, 0)
    return out
}

func query(_ name: String) -> [String: Any]? {
    try? JSONSerialization.jsonObject(with: sb(["--query", name], capture: true)) as? [String: Any]
}

/// Is the popup up? `nil` means the bar DIDN'T ANSWER — which is not the same
/// thing as "closed", and conflating the two is what cost the agents pill its
/// click-outside dismissal entirely. A pill that rebuilds its rows before
/// toggling (`--remove` + one `--add` per row: 44 of them on a busy agents
/// popup) leaves sketchybar's mach service too busy to answer for ~150 ms, and
/// `--query` in that window returns not `drawing: off` but an EMPTY STRING.
/// Every caller here used to read that as off and give up.
func popupDrawing(_ item: String) -> Bool? {
    guard let popup = query(item)?["popup"] as? [String: Any] else { return nil }
    return popup["drawing"] as? String == "on"
}

/// The arming gate, which is the one caller that has to wait: it runs
/// milliseconds after the click script asked for the popup, so "no answer yet"
/// is the EXPECTED first read on any pill big enough to matter. Poll until the
/// bar answers or the deadline passes. A settled `off` still exits on the first
/// read — closing a dropdown stays as fast as it was.
func popupIsOpen(_ item: String, settleFor: TimeInterval = 0) -> Bool {
    let deadline = Date().addingTimeInterval(settleFor)
    // Backing off rather than hammering: every retry is a posix_spawn of
    // `sketchybar --query` aimed INTO the busy window we're waiting on, so a
    // tight poll would be contending with the very batch whose completion is
    // the thing we want. First read is immediate — a settled pill answers at
    // once and never sleeps — then 30 ms growing to 120 ms, ~8 queries across
    // the full budget instead of ~30.
    var wait: useconds_t = 30_000
    repeat {
        if let drawing = popupDrawing(item) { return drawing }
        if settleFor > 0 {
            usleep(wait)
            wait = min(wait * 3 / 2, 120_000)
        }
    } while Date() < deadline
    return false
}

// ── geometry ─────────────────────────────────────────────────────────────────

/// The strip the bar itself occupies, as a thickness from the top (or bottom)
/// edge of whatever display the pointer is on — sketchybar draws it full width.
struct BarStrip {
    var thickness: CGFloat = 38
    var atTop = true
}

func barStrip() -> BarStrip {
    guard let bar = query("bar") else { return BarStrip() }
    let height = (bar["height"] as? NSNumber)?.doubleValue ?? 36
    let offset = (bar["y_offset"] as? NSNumber)?.doubleValue ?? 0
    let atTop = (bar["position"] as? String ?? "top") != "bottom"
    return BarStrip(thickness: CGFloat(height + abs(offset)) + 2, atTop: atTop)
}

/// Rects of the popup's rows, in the display's own top-left coordinates — the
/// space `bounding_rects` reports. Read ONCE while arming, never on the click
/// itself: it's a query per row (17 of them on the AI-usage pill), and paying
/// that after the click is what a slow dismissal is made of. By then the popup is
/// already on screen, so the cost is invisible.
///
/// Display identity is deliberately dropped: one open popup lives on one display
/// anyway, and the worst a same-coordinates click on a second monitor can cost is
/// a single missed dismissal.
func popupRects(_ item: String) -> [CGRect] {
    guard let popup = query(item)?["popup"] as? [String: Any],
        let rows = popup["items"] as? [String]
    else { return [] }
    var rects: [CGRect] = []
    for row in rows {
        guard let boxes = query(row)?["bounding_rects"] as? [String: Any] else { continue }
        for (_, box) in boxes {
            guard let box = box as? [String: Any],
                let origin = (box["origin"] as? [NSNumber])?.map({ CGFloat($0.doubleValue) }),
                let size = (box["size"] as? [NSNumber])?.map({ CGFloat($0.doubleValue) }),
                origin.count == 2, size.count == 2
            else { continue }
            rects.append(CGRect(x: origin[0], y: origin[1], width: size[0], height: size[1]))
        }
    }
    return rects
}

/// `NSEvent.mouseLocation` is bottom-left and global across all displays;
/// sketchybar reports top-left and per display. Convert into the screen the
/// click landed on, and hand back that screen's height for the bottom-bar case.
func localPoint(_ point: NSPoint) -> (point: CGPoint, screenHeight: CGFloat)? {
    guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) })
    else { return nil }
    return (
        CGPoint(x: point.x - screen.frame.minX, y: screen.frame.maxY - point.y),
        screen.frame.height
    )
}

// ── the guard ────────────────────────────────────────────────────────────────

func arm(item: String) -> Never {
    // Our caller is a click_script that has already returned; leave its session
    // so nothing downstream can take this process with it. Children are reaped by
    // the kernel, since the fire-and-forget sketchybar calls are never waited on.
    //
    // FIRST, before the gate below — that gate can now spend up to 600 ms
    // waiting for the bar, and every millisecond of it used to be time spent
    // still inside the click_script's process group. Anything that signals that
    // group in the window (a bar reload, a script timeout) would take the guard
    // with it and leave the dropdown un-dismissable again, intermittently.
    setsid()
    signal(SIGCHLD, SIG_IGN)

    // Nothing opened (the pill's toggle just CLOSED its popup), so there's
    // nothing to guard. Whatever guard was running notices the same thing.
    // The wait is for the OTHER answer — see popupIsOpen: a pill that rebuilds
    // a long popup before toggling it can't answer a query for the first
    // ~150 ms, and taking that silence for "closed" left the biggest dropdowns
    // on the bar as the only ones a click outside never dismissed.
    if !popupIsOpen(item, settleFor: 0.6) { exit(0) }

    // Opening one dropdown closes every other: menu behaviour, and it keeps this
    // one-guard-at-a-time. One sketchybar call, and it runs after the popup is
    // already up, so nothing flickers.
    sb(["--set", "/.*/", "popup.drawing=off", "--set", item, "popup.drawing=on"])

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let strip = barStrip()
    // Rows are laid out by the time a popup is drawn, but the pill's own plugin
    // may still have been rebuilding them a millisecond ago — one retry covers
    // the case where the first read finds nothing.
    var rows = popupRects(item)
    if rows.isEmpty { rows = popupRects(item) }

    NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown])
    { _ in
        guard let (point, screenHeight) = localPoint(NSEvent.mouseLocation) else { return }
        let onBar =
            strip.atTop ? point.y <= strip.thickness : point.y >= screenHeight - strip.thickness
        // A click on the bar or on a row of the popup belongs to sketchybar: the
        // pill toggles itself, and every row's own click_script closes up after
        // running. Closing it from here too would race that script.
        if onBar || rows.contains(where: { $0.contains(point) }) {
            // `== false` on purpose: an unanswered query means the bar is busy,
            // not that the popup went away, and exiting on it drops the guard
            // for a dropdown still on screen.
            if popupDrawing(item) == false { exit(0) }
            return
        }
        sb(["--set", item, "popup.drawing=off"])  // not waited on: fire and exit
        exit(0)
    }

    // A popup can also close without any click — a plugin refresh, another pill,
    // `sketchybar --reload`. Nothing left to guard then.
    Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
        if popupDrawing(item) == false { exit(0) }
    }
    // Backstop, so a dropdown someone walked away from can't leave a guard.
    Timer.scheduledTimer(withTimeInterval: 900, repeats: false) { _ in exit(0) }

    app.run()
    exit(0)
}

let argv = CommandLine.arguments
guard argv.count >= 3, argv[1] == "arm" else {
    FileHandle.standardError.write(
        Data("usage: barpop arm <sketchybar item>   (run it backgrounded, after the toggle)\n".utf8)
    )
    exit(2)
}
arm(item: argv[2])
