// sillpop — dismiss a SketchyBar popup by clicking anywhere else, the way every
// other dropdown on the machine behaves.
//
//   sillpop toggle <item>   what a pill's click_script calls instead of
//                           `sketchybar --set <item> popup.drawing=toggle`
//   sillpop watch  <item>   the armed watcher; `toggle` spawns it, detached
//
// Why a binary at all: SketchyBar sees clicks on its OWN items and nothing else,
// so a popup opened by a pill stays up until that pill is clicked a second time.
// The only signal it has that the pointer went elsewhere is `mouse.exited.global`
// — a HOVER-out, which would yank the agents / AI-usage list away the instant you
// moved the mouse off the bar to read something. Wrong gesture. A click is the
// gesture, and observing clicks outside our own process needs AppKit.
//
// It costs no new permission: NSEvent's global monitor is Accessibility-gated for
// KEY events only, mouse events come through to any process. And it costs no
// daemon — `toggle` arms one watcher while a dropdown is up, and the watcher exits
// the moment the popup closes, however it closed.
import AppKit
import Foundation

// ── talking to sketchybar ────────────────────────────────────────────────────
// The launchd agent runs the Homebrew binary (see modules/sill/default.nix); the
// bare name is the fallback so this still works from a shell with sketchybar on
// PATH, and SKETCHYBAR_BIN overrides both.
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
    return "sketchybar"
}()

@discardableResult
func sb(_ args: [String]) -> Data {
    let task = Process()
    if sketchybarBin.hasPrefix("/") {
        task.executableURL = URL(fileURLWithPath: sketchybarBin)
        task.arguments = args
    } else {
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = [sketchybarBin] + args
    }
    let out = Pipe()
    task.standardOutput = out
    task.standardError = FileHandle.nullDevice
    guard (try? task.run()) != nil else { return Data() }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    return data
}

func query(_ name: String) -> [String: Any]? {
    try? JSONSerialization.jsonObject(with: sb(["--query", name])) as? [String: Any]
}

func popupIsOpen(_ item: String) -> Bool {
    guard let popup = query(item)?["popup"] as? [String: Any] else { return false }
    return popup["drawing"] as? String == "on"
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
/// space `bounding_rects` reports. Only DRAWN items have one, so this is empty
/// until the popup is actually up, and it is re-read per click because a plugin
/// rebuilds its rows (agents, ai_usage) every time the pill is clicked.
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

// ── the two commands ─────────────────────────────────────────────────────────

func watch(item: String) -> Never {
    // The click_script that spawned us is already gone; leave its session so
    // nothing downstream can take this process with it.
    setsid()
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let strip = barStrip()

    NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown])
    { _ in
        guard let (point, screenHeight) = localPoint(NSEvent.mouseLocation) else { return }
        let onBar =
            strip.atTop ? point.y <= strip.thickness : point.y >= screenHeight - strip.thickness
        // A click on the bar or on a row of the popup belongs to sketchybar: the
        // pill toggles itself, and every row's own click_script closes up after
        // running. Closing it from here too would race that script.
        if onBar || popupRects(item).contains(where: { $0.contains(point) }) {
            if !popupIsOpen(item) { exit(0) }
            return
        }
        sb(["--set", item, "popup.drawing=off"])
        exit(0)
    }

    // A popup can also close without any click — a plugin refresh, another pill,
    // `sketchybar --reload`. Nothing left to guard then.
    Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
        if !popupIsOpen(item) { exit(0) }
    }
    // Backstop, so a dropdown someone walked away from can't leave a watcher.
    Timer.scheduledTimer(withTimeInterval: 900, repeats: false) { _ in exit(0) }

    app.run()
    exit(0)
}

func toggle(item: String) {
    if popupIsOpen(item) {
        sb(["--set", item, "popup.drawing=off"])
        return
    }
    // Opening one dropdown closes every other: menu behaviour, and it keeps the
    // watcher one-per-bar instead of one-per-pill.
    sb(["--set", "/.*/", "popup.drawing=off"])
    sb(["--set", item, "popup.drawing=on"])

    let watcher = Process()
    watcher.executableURL = URL(
        fileURLWithPath: Bundle.main.executablePath ?? CommandLine.arguments[0])
    watcher.arguments = ["watch", item]
    watcher.standardOutput = FileHandle.nullDevice
    watcher.standardError = FileHandle.nullDevice
    try? watcher.run()  // deliberately not waited on
}

let argv = CommandLine.arguments
guard argv.count >= 3, ["toggle", "watch"].contains(argv[1]) else {
    FileHandle.standardError.write(
        Data("usage: sillpop toggle|watch <sketchybar item>\n".utf8))
    exit(2)
}
if argv[1] == "watch" { watch(item: argv[2]) }
toggle(item: argv[2])
exit(0)
